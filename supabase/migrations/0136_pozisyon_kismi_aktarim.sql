-- 0136 — Portföyler arası KISMİ aktarım (Premium, bayrak `coklu_portfoy`).
--
-- Kullanıcı isteği (2026-10-10): "premiuma özel, portföyler arası
-- klonlama/aktarım". Klon (aynı varlık iki portföyde) toplamı iki kez
-- sayacağı için yapılmadı; aktarım miktar seçilerek yapılır.
--
-- ## Neden ORANTILI bölme
-- 0133'te kısmi taşıma bilerek yoktu (`PortfolioNotifier.pozisyonuTasi`):
-- lot seçerek bölmek maliyeti uydurur, kaynakta satış + hedefte alım ise
-- para hareketi olmayan günü nakit akışı sayar. Burada pozisyonun HER
-- satırı (alım, satış, temettü) aynı r oranıyla ikiye ayrılır: hedefe
-- r × satır, kaynakta (1 − r) × satır. Böylece iki portföyün geçmişi de
-- "pozisyonun bu payı baştan beri buradaydı" der: ortalama maliyet, tarih,
-- kur, dönem getirisi ve XIRR iki tarafta da birebir aynı; Tümü değişmez
-- (r + (1 − r) = 1). Ölçeklenen alanlar yalnız miktar ve tutarlar
-- (quantity, commission, dividend_amount); birim fiyatlar (purchase_price,
-- sell_price) ve kurlar zaten paya bağlı değil.
--
-- Silinmiş satırlar (deleted_at) ve silme kaydı (delete_log) kaynakta kalır:
-- hesaplara girmezler, bölünmeleri yalnız hareket listesini kalabalıklaştırır.
-- Sözleşmeli (BES/mevduat) lot bölünmez: sözleşme tek portföydedir
-- (`tasinacakLotlar` gerekçesi).
--
-- ## Yarış giriş anı (0095) korunur
-- `assets_giris_ani` INSERT'te ve miktar değişiminde `created_at = now()`
-- yazar (geriye tarihli girişle Yarış'ı şişirmeyi önler). Bölme bunu iki
-- tarafta da tetikleyip pozisyonu "bugün girildi" sayardı. Bölme toplam
-- miktarı her an için korur, oyun açmaz; bu yüzden fonksiyon işlem içinde
-- `sandik.giris_ani_koru` ayarını açar ve tetikleyici o işlemde giriş anını
-- satırdan alır. Ayar istemciden kurulamaz (PostgREST ham SQL çalıştırmaz,
-- `set_config` açık şemada değil) ve `is_local = true` ile işlem sonunda düşer.
--
-- Yalnız ekler: yeni fonksiyon + tetikleyicinin ayar yokken BİREBİR aynı
-- davranışı. Eski sürümler hiçbir fark görmez.

-- ── 1) Tetikleyici: bölme işleminde giriş anı korunur ─────────────────────
create or replace function public.assets_giris_ani()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- 0136: orantılı bölme (`pozisyon_kismi_aktar`) aynı işlemde açar.
  if coalesce(current_setting('sandik.giris_ani_koru', true), '') = 'on' then
    if tg_op = 'INSERT' then
      new.created_at := coalesce(new.created_at, now());
    else
      new.created_at := old.created_at;
    end if;
    return new;
  end if;
  if tg_op = 'INSERT' then
    new.created_at := now();
    return new;
  end if;
  -- Tarih ve miktar TOLERANSLA kıyaslanır: istemci fiyat turunda satırın
  -- TAMAMINI geri yazar (`updateAsset`, her 30 sn). Gidiş-dönüşte bir
  -- yuvarlama farkı (mikro saniye, kayan nokta) olsaydı her tur bütün
  -- satırları "şimdi girildi" sayar, herkesin yarış geçmişi silinirdi.
  if new.added_date is null or old.added_date is null
     or abs(extract(epoch from new.added_date - old.added_date)) > 1
     or abs(new.quantity - old.quantity)
          > 1e-9 * greatest(abs(old.quantity), 1)
     or new.ticker    is distinct from old.ticker
     or new.type      is distinct from old.type
     or new.kind      is distinct from old.kind
     or new.currency  is distinct from old.currency
     or new.sub_category is distinct from old.sub_category then
    new.created_at := now();
  else
    -- Fiyat tazelemesi (`current_price`, her 30 sn), not, ad, silme damgası:
    -- giriş anı değişmez — ve istemci onu elle de değiştiremez.
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

-- ── 2) Orantılı bölme ───────────────────────────────────────────────────────
-- SECURITY INVOKER (varsayılan): her okuma/yazma `assets_own` RLS'inden
-- geçer; hedef portföyün sahipliği 0133 bileşik FK'sinde. Ek olarak
-- yalnız çağıranın satırları seçilir ve sayı tutmazsa bütün işlem düşer —
-- yarım bölme olmaz. Dönüş: hedefe yazılan yeni satırlar ve kaynakta
-- küçülen satırlar (istemci defteri yeniden yüklemeden günceller).
create or replace function public.pozisyon_kismi_aktar(
  p_ids   uuid[],
  p_oran  double precision,
  p_hedef uuid
)
returns setof public.assets
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_uid   uuid := auth.uid();
  v_say   int;
  r       public.assets%rowtype;
  yeni    public.assets%rowtype;
  eslem   jsonb := '{}'::jsonb;
  bolunen uuid[] := '{}';
begin
  if v_uid is null then
    raise exception 'oturum_yok' using errcode = '28000';
  end if;
  if p_oran is null or not (p_oran > 0 and p_oran < 1) then
    raise exception 'oran_gecersiz' using errcode = '22023';
  end if;
  if p_ids is null or cardinality(p_ids) = 0 or cardinality(p_ids) > 2000 then
    raise exception 'satir_gecersiz' using errcode = '22023';
  end if;

  select count(*) into v_say
    from public.assets a
   where a.id = any(p_ids) and a.user_id = v_uid;
  if v_say <> cardinality(array(select distinct unnest(p_ids))) then
    raise exception 'satir_bulunamadi' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.assets a
              where a.id = any(p_ids) and a.sozlesme_id is not null) then
    raise exception 'sozlesmeli_bolunmez' using errcode = '22023';
  end if;
  if exists (select 1 from public.assets a
              where a.id = any(p_ids) and a.portfoy_id is not distinct from p_hedef) then
    raise exception 'ayni_portfoy' using errcode = '22023';
  end if;

  perform set_config('sandik.giris_ani_koru', 'on', true);

  -- Alımlar önce: satış/temettü `ref_asset_id`'si yeni alım kopyasına
  -- eşlenir (referans kümede yoksa olduğu gibi kalır).
  for r in
    select * from public.assets a
     where a.id = any(p_ids)
       and a.deleted_at is null
       and a.kind in ('buy', 'sell', 'dividend')
     order by (a.kind <> 'buy'), a.added_date, a.id
  loop
    yeni := r;
    yeni.id := gen_random_uuid();
    yeni.portfoy_id := p_hedef;
    yeni.quantity := r.quantity * p_oran;
    yeni.commission := r.commission * p_oran;
    yeni.dividend_amount := r.dividend_amount * p_oran;
    if r.ref_asset_id is not null and eslem ? r.ref_asset_id::text then
      yeni.ref_asset_id := (eslem ->> r.ref_asset_id::text)::uuid;
    end if;
    insert into public.assets select (yeni).*;
    eslem := eslem || jsonb_build_object(r.id::text, yeni.id::text);
    bolunen := bolunen || r.id;
    return next yeni;
  end loop;

  if cardinality(bolunen) = 0 then
    raise exception 'bolunecek_satir_yok' using errcode = 'P0002';
  end if;

  return query
    update public.assets a
       set quantity = a.quantity * (1 - p_oran),
           commission = a.commission * (1 - p_oran),
           dividend_amount = a.dividend_amount * (1 - p_oran)
     where a.id = any(bolunen)
    returning a.*;

  perform set_config('sandik.giris_ani_koru', 'off', true);
end;
$$;

revoke all on function public.pozisyon_kismi_aktar(uuid[], double precision, uuid)
  from public, anon;
grant execute on function public.pozisyon_kismi_aktar(uuid[], double precision, uuid)
  to authenticated;

-- ── 3) Doğrulama ───────────────────────────────────────────────────────────
do $$
begin
  if has_function_privilege('anon',
       'public.pozisyon_kismi_aktar(uuid[], double precision, uuid)', 'EXECUTE') then
    raise exception '0136: pozisyon_kismi_aktar anon tarafindan cagrilabilir olmamali';
  end if;
  if not has_function_privilege('authenticated',
       'public.pozisyon_kismi_aktar(uuid[], double precision, uuid)', 'EXECUTE') then
    raise exception '0136: pozisyon_kismi_aktar authenticated icin acik olmali';
  end if;
  if exists (select 1 from pg_proc
              where proname = 'pozisyon_kismi_aktar' and prosecdef) then
    raise exception '0136: pozisyon_kismi_aktar SECURITY INVOKER olmali (RLS)';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgname = 'assets_giris_ani'
                    and tgrelid = 'public.assets'::regclass) then
    raise exception '0136: assets_giris_ani tetikleyicisi yok';
  end if;
end;
$$;
