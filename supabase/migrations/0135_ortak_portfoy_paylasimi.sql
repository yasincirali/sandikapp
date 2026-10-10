-- 0135 — Ortak hangi portföyleri görür (`ortak_paylasimlari`) (2026-10-10)
--
-- ## Neden (yasin, 2026-10-10)
-- "Çoklu portföyde ortağıma hangisinin gözükeceğini seçebilmeliyim."
-- 0133'e kadar ortak, sahibin BÜTÜN lotlarını okuyordu (`assets_partner_read`).
-- Portföy bir mahremiyet sınırı da olabiliyor ("Çocuğum için", "Kendi
-- birikimim"); seçim yalnız istemcide süzülseydi ortağın cihazı yine bütün
-- satırları indirirdi. Sınır bu yüzden RLS'te.
--
-- ## Tasarım — YALNIZ EKLER (eski sürümler etkilenmez)
--   · Satır yoksa = bugünkü davranış (ortak her şeyi görür). Eski istemci
--     satır yazamaz; yeni istemci yalnız kullanıcı seçim yapınca yazar.
--     Göç yok, varsayılan değişmez.
--   · Satır (sahip, ortak) başınadır: iki ortağı olan Premium kullanıcı
--     birine "Aile"yi, öbürüne hepsini gösterebilir.
--   · `tumu = true` → her şey (yeni açılan portföyler dahil).
--     `tumu = false` → yalnız `ana` (portfoy_id NULL lotlar) ve
--     `portfoy_idler`. Seçili modda yeni açılan portföy GİZLİ başlar —
--     mahremiyet için güvenli taraf; sayfa bunu yazar.
--   · Silinmiş portföyün kimliği dizide kalabilir: lotu FK ile Ana'ya
--     döndüğü için hiçbir şeyi açmaz, zararsız.
--   · Ortak, sahibin portföyleri olduğunu BİLMEZ (yasin 2026-10-10: "ortağım
--     benim 2 portföyüm olduğunu bilmemeli; paylaştıklarımı tek liste olarak
--     görmeli"). Bu yüzden ortak: paylaşım satırını okuyamaz, portföy ADLARINI
--     okuyamaz (`portfoyler_partner_read` kalkar), süzgeç fonksiyonları API'de
--     görünmeyen `ozel` şemasındadır (çağırıp "kısıt var mı" yoklayamasın).
--     İstemci ortağın lotlarındaki `portfoy_id`'yi atar
--     (`SupabaseService.fetchOrtakLotlari`). Kalan iz: ham API'de paylaşılan
--     lotların `portfoy_id` sütunu; tam kapatma eski sürümler düşünce ortak
--     okumasını sütunsuz bir RPC'ye taşıyan ayrı migration'la
--     (TECHNICAL_DEBT "Çoklu portföy v1 sınırları").
--   · Ortaklık bitip yeniden kurulursa seçim korunur (gizlenen yeniden
--     açılmaz).
--
-- ## Etkilenen okumalar
--   · `assets_partner_read`: lot yalnız paylaşılan portföydeyse.
--   · `portfoyler_partner_read`: KALDIRILIR (ortak hiçbir portföy adı
--     okumaz). 0133'ten beri istemci bunu hiç okumadı; eski sürüm etkilenmez.
--   · `sozlesmeler_partner_read`, `mevduat_donemleri_partner_read`:
--     kısıtlı ortak sözleşmeyi ancak görebildiği bir lotu bağlıysa okur
--     (BES/mevduat sözleşmesi banka, faiz, tutar taşır).
--   · Sunucu tarafı: `daily-brief`'in "ortağın dün N varlık ekledi" sayımı
--     aynı süzgeci uygular (service-role RLS'i atlar).
--   · DEĞİŞMEYEN: Yarış/Zirve anlık görüntüleri (kullanıcı TOPLAMI, ayrı
--     açık rıza) ve ortaklar arası Yarış (cihazda, artık görülebilen lotlardan).

-- ── 1) Tablo ───────────────────────────────────────────────────────────────
create table if not exists public.ortak_paylasimlari (
  sahip_id      uuid not null default auth.uid()
                references auth.users(id) on delete cascade,
  ortak_id      uuid not null references auth.users(id) on delete cascade,
  tumu          boolean not null default true,
  ana           boolean not null default true,
  portfoy_idler uuid[] not null default '{}'
                check (cardinality(portfoy_idler) <= 50),
  updated_at    timestamptz not null default now(),
  primary key (sahip_id, ortak_id),
  check (sahip_id <> ortak_id)
);

-- Ortağın kendi satırını bulması (RLS politikalarının her lot için sorduğu
-- soru): (sahip, ortak) birincil anahtar zaten kapsar; ters yön için indeks.
create index if not exists ortak_paylasimlari_ortak_idx
  on public.ortak_paylasimlari(ortak_id);

create or replace function public.ortak_paylasimlari_updated_at()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists ortak_paylasimlari_updated_at on public.ortak_paylasimlari;
create trigger ortak_paylasimlari_updated_at
  before update on public.ortak_paylasimlari
  for each row execute function public.ortak_paylasimlari_updated_at();

alter table public.ortak_paylasimlari enable row level security;
alter table public.ortak_paylasimlari force row level security;

drop policy if exists "ortak_paylasimlari_own" on public.ortak_paylasimlari;
create policy "ortak_paylasimlari_own" on public.ortak_paylasimlari
  for all using (auth.uid() = sahip_id)
  with check (auth.uid() = sahip_id);

-- Ortak okuma politikası YOK: kısıtın varlığı bile ortağa söylenmez.
drop policy if exists "ortak_paylasimlari_ortak_read" on public.ortak_paylasimlari;

revoke all on table public.ortak_paylasimlari from anon;
grant select, insert, update, delete on table public.ortak_paylasimlari
  to authenticated;

-- ── 2) Süzgeç fonksiyonları ────────────────────────────────────────────────
-- `ozel` şeması PostgREST'e açık DEĞİL (config: schemas = public,
-- graphql_public): fonksiyon yalnız politika içinden çalışır, ortak RPC ile
-- yoklayamaz. SECURITY DEFINER: ortağın paylaşım satırını okuma yetkisi yok
-- (yukarıda); fonksiyon yalnız ÇAĞIRANIN (`auth.uid()`) evet/hayırını döner.
-- Satır yoksa ya da `tumu` ise true — bugünkü davranış.
create schema if not exists ozel;
revoke all on schema ozel from public, anon;
grant usage on schema ozel to authenticated;

create or replace function ozel.ortak_portfoyu_gorur(
  p_sahip uuid,
  p_portfoy uuid
) returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((
    select s.tumu
        or (p_portfoy is null and s.ana)
        or (p_portfoy is not null and p_portfoy = any(s.portfoy_idler))
      from public.ortak_paylasimlari s
     where s.sahip_id = p_sahip
       and s.ortak_id = auth.uid()
  ), true);
$$;

-- Bu sahip, çağıran ortağa KISITLI mı paylaşıyor (sözleşme politikaları).
create or replace function ozel.ortak_paylasimi_kisitli(p_sahip uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.ortak_paylasimlari s
     where s.sahip_id = p_sahip
       and s.ortak_id = auth.uid()
       and not s.tumu
  );
$$;

revoke all on function ozel.ortak_portfoyu_gorur(uuid, uuid) from public, anon;
revoke all on function ozel.ortak_paylasimi_kisitli(uuid) from public, anon;
grant execute on function ozel.ortak_portfoyu_gorur(uuid, uuid) to authenticated;
grant execute on function ozel.ortak_paylasimi_kisitli(uuid) to authenticated;

-- ── 3) Politikalar ─────────────────────────────────────────────────────────
-- Ortaklık koşulu 0000/0088/0133 ile birebir; yalnız sona süzgeç eklenir.
drop policy if exists "assets_partner_read" on public.assets;
create policy "assets_partner_read" on public.assets
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = assets.user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = assets.user_id))
    )
    and ozel.ortak_portfoyu_gorur(assets.user_id, assets.portfoy_id)
  );

drop policy if exists "portfoyler_partner_read" on public.portfoyler;

-- Sözleşme: kısıtsızsa bugünkü gibi; kısıtlıysa ancak GÖREBİLDİĞİ bir lot
-- (iç sorgu `assets` RLS'ine tabi) bu sözleşmeye bağlıysa.
drop policy if exists "sozlesmeler_partner_read" on public.sozlesmeler;
create policy "sozlesmeler_partner_read" on public.sozlesmeler
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = sozlesmeler.user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = sozlesmeler.user_id))
    )
    and (
      not ozel.ortak_paylasimi_kisitli(sozlesmeler.user_id)
      or exists (
        select 1 from public.assets a
         where a.sozlesme_id = sozlesmeler.id
           and a.user_id = sozlesmeler.user_id
      )
    )
  );

drop policy if exists "mevduat_donemleri_partner_read" on public.mevduat_donemleri;
create policy "mevduat_donemleri_partner_read" on public.mevduat_donemleri
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = mevduat_donemleri.user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = mevduat_donemleri.user_id))
    )
    and (
      not ozel.ortak_paylasimi_kisitli(mevduat_donemleri.user_id)
      or exists (
        select 1 from public.assets a
         where a.sozlesme_id = mevduat_donemleri.sozlesme_id
           and a.user_id = mevduat_donemleri.user_id
      )
    )
  );

-- ── 4) Doğrulama ───────────────────────────────────────────────────────────
do $$
declare
  g int;
  p int;
begin
  select count(*) into g from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'ortak_paylasimlari'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  select count(*) into p from pg_policies
   where schemaname = 'public' and tablename = 'ortak_paylasimlari';

  if g <> 4 then
    raise exception '0135: ortak_paylasimlari GRANT eksik: % / 4', g;
  end if;
  if p <> 1 then
    raise exception '0135: ortak_paylasimlari RLS politikasi % / 1 (ortak okumasi olmamali)', p;
  end if;
  if has_table_privilege('anon', 'public.ortak_paylasimlari', 'SELECT') then
    raise exception '0135: anon ortak_paylasimlari okuyabiliyor';
  end if;
  if not exists (
    select 1 from pg_class
     where oid = 'public.ortak_paylasimlari'::regclass
       and relrowsecurity and relforcerowsecurity
  ) then
    raise exception '0135: ortak_paylasimlari RLS zorunlu degil';
  end if;
  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'assets'
       and policyname = 'assets_partner_read'
       and qual like '%ortak_portfoyu_gorur%'
  ) then
    raise exception '0135: assets_partner_read suzgecsiz';
  end if;
  if has_function_privilege('anon', 'ozel.ortak_portfoyu_gorur(uuid, uuid)', 'EXECUTE') then
    raise exception '0135: anon ortak_portfoyu_gorur cagirabiliyor';
  end if;
  -- SECURITY DEFINER fonksiyonun sahibi FORCE RLS'li paylaşım tablosunu
  -- okuyabilmeli; okuyamazsa satır hiç bulunmaz ve fonksiyon "hepsi" der
  -- (seçim sessizce yok sayılır). 0102'deki kontrolün aynısı.
  if not exists (
    select 1 from pg_proc f join pg_roles r on r.oid = f.proowner
     where f.oid = 'ozel.ortak_portfoyu_gorur(uuid, uuid)'::regprocedure
       and (r.rolsuper or r.rolbypassrls)
  ) then
    raise exception '0135: suzgec fonksiyonunun sahibi RLS asamiyor';
  end if;
  if exists (select 1 from pg_policies where schemaname = 'public'
              and tablename = 'portfoyler' and policyname = 'portfoyler_partner_read') then
    raise exception '0135: ortak portfoy adlarini okuyabiliyor';
  end if;
end $$;

comment on table public.ortak_paylasimlari is
  'Sahibin ortagina hangi portfoyleri gosterdigi (0135). Satir yoksa ya da '
  'tumu=true ise ortak her seyi gorur. Ortak bu tabloyu okuyamaz.';
