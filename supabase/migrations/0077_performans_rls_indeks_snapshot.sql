-- 0077 — Performans: RLS initplan, gereksiz indeks/politika, FK indeksleri,
--        saatlik anlık görüntü
--
-- Kullanıcı isteği (2026-09-28): "db'yi kontrol et, normalizasyon veya indeks
-- gereken alanlar varsa ekle; ilk açılış ve sayfalara ilk girişte hız".
--
-- ## Ölçüm (Frankfurt, pilot hesap: 97 varlık, 11.803 anlık görüntü)
--
-- Sunucuda sorgular zaten hızlıydı (RLS etkin EXPLAIN ANALYZE):
--   varlıklar 1,09 ms · anlık görüntü 365 gün 6,6 ms · diğerleri < 0,3 ms.
-- Yavaşlığın ağırlığı ağda (Tokyo ~250 ms gidiş-dönüş → Frankfurt taşıması)
-- ve TAŞINAN VERİDE. En büyük bulgu `snapshots`:
--   365 günde 11.803 satır = 2,2 MB JSON; günde ortalama 136, bir günde 1.259.
-- Her fiyat yenilemesi bir satır EKLİYOR ve bir "2 yıldan eskiyi sil"
-- DELETE'i gönderiyordu. Okuyanlar (Yıllık Özet, weekly-summary) yalnız
-- pencerenin İLK ve SON değerini kullanıyor — saatte bir nokta fazlasıyla
-- yeter. weekly-summary ise TÜM kullanıcıların bir yıllık serisini tek
-- sorguda çekiyor: kullanıcı sayısıyla doğrusal büyüyen bir zaman aşımıydı.
--
-- Normalizasyon: şemada tekrar eden veri yok; kullanıcı başına zaman
-- serileri doğru ayrılmış. Değişiklik gerektiren normal form ihlali bulunmadı.

-- ── 1) RLS: auth.uid() satır başına DEĞİL, sorgu başına bir kez ─────────────
--
-- `auth.uid() = user_id` her satır için fonksiyon çağırır; `(select
-- auth.uid())` planlayıcıda initplan olur ve bir kez hesaplanır (Supabase
-- performans kılavuzu, "auth_rls_initplan"). ~55 politika çıplak çağrı
-- taşıyordu. İfade anlamı DEĞİŞMEZ; yalnız değerlendirme sayısı.
-- Zaten sarılı olan (`SELECT auth.uid()`) çift sarılmaz (geriye bakan regex,
-- PG17'de denendi).
do $$
declare
  p record;
  yeni_qual text;
  yeni_check text;
  sql text;
  sayi int := 0;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)'
         or coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)')
  loop
    yeni_qual := regexp_replace(p.qual, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    yeni_check := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    sql := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if yeni_qual is not null then sql := sql || format(' using (%s)', yeni_qual); end if;
    if yeni_check is not null then sql := sql || format(' with check (%s)', yeni_check); end if;
    execute sql;
    sayi := sayi + 1;
  end loop;
  raise notice '0077: % politika initplan biçimine alındı.', sayi;
end;
$$;

-- ── 2) Tekrar eden politikalar: user_push_tokens ────────────────────────────
--
-- 0000 `push_tokens_own_*`, 0016 `user_push_tokens_own_*` — birebir aynı dört
-- politika. İzin veren (permissive) politikalar OR'lanır: her sorguda ikisi
-- de değerlendiriliyordu. 0016'dakiler kalır.
drop policy if exists "push_tokens_own_select" on public.user_push_tokens;
drop policy if exists "push_tokens_own_insert" on public.user_push_tokens;
drop policy if exists "push_tokens_own_update" on public.user_push_tokens;
drop policy if exists "push_tokens_own_delete" on public.user_push_tokens;

-- ── 3) Gereksiz indeksler (her yazımı yavaşlatır, hiçbir okumayı hızlandırmaz)
--
-- Her biri başka bir indeksin baş kolonlarıyla TAMAMEN kapsanıyor.
drop index if exists public.assets_user_id_idx;            -- ⊂ assets_user_kind_idx (user_id, kind)
drop index if exists public.partnerships_user1_idx;        -- ⊂ tekil (user_id_1, user_id_2)
drop index if exists public.signal_preferences_user_idx;   -- ⊂ PK (user_id, asset_type)
drop index if exists public.user_push_tokens_user_idx;     -- = user_push_tokens_user_id_idx
drop index if exists public.ix_user_roi_snapshots_user;    -- = tekil (user_id, period_days, created_at)

-- ── 4) İndekssiz yabancı anahtarlar ─────────────────────────────────────────
--
-- Kullanıcı silinirken (ON DELETE) ve davet/alarm aramalarında tam tarama.
create index if not exists partner_invites_from_user_idx on public.partner_invites (from_user_id);
create index if not exists partner_invites_to_user_idx on public.partner_invites (to_user_id);
create index if not exists price_alert_notifications_alert_idx on public.price_alert_notifications (alert_id);

-- ── 5) Anlık görüntü: saatte en fazla BİR satır ─────────────────────────────
--
-- Neden TEKİL İNDEKS değil tetikleyici: mağazadaki 1.1.6 düz INSERT yapıyor.
-- Tekil indeks saatteki ikinci yazımda 409 döndürür, istemci bunu fiyat
-- yenileme hatası sayıp HER turda "Fiyatlar güncellenemedi" gösterirdi.
-- Tetikleyici aynı saatte satır varsa onu GÜNCELLER (son değer kalır),
-- yoksa ekler — eski ve yeni sürüm için şeffaf. Eşzamanlı iki yazım nadiren
-- iki satır bırakabilir; tüketiciler (ilk/son değer) bundan etkilenmez.
alter table public.snapshots
  add column if not exists saat timestamp
  generated always as (date_trunc('hour', ts at time zone 'UTC')) stored;

-- Mevcut fazlalık: her (kullanıcı, saat) için SON satır kalır. Kayıp yok:
-- tüketiciler pencerenin ilk/son değerini okur, saat içi ara noktaları değil.
delete from public.snapshots s
 using (
   select id, row_number() over (
            partition by user_id, date_trunc('hour', ts at time zone 'UTC')
            order by ts desc, id desc) as sira
     from public.snapshots
 ) d
 where s.id = d.id and d.sira > 1;

create index if not exists snapshots_user_saat_idx on public.snapshots (user_id, saat);

create or replace function public.snapshots_saatlik()
returns trigger
language plpgsql
-- INVOKER (definer değil): UPDATE çağıranın RLS'iyle koşar — yalnız kendi
-- satırını günceller. search_path yine sabit (CLAUDE.md kuralı).
set search_path = public
as $$
begin
  update public.snapshots
     set data = new.data, ts = new.ts
   where user_id = new.user_id
     and saat = date_trunc('hour', new.ts at time zone 'UTC');
  if found then
    return null;  -- mevcut saat güncellendi, ekleme yok
  end if;
  return new;
end;
$$;

drop trigger if exists snapshots_saatlik on public.snapshots;
create trigger snapshots_saatlik
  before insert on public.snapshots
  for each row execute function public.snapshots_saatlik();

-- ── 6) Anlık görüntü saklama süresi: istemciden cron'a ──────────────────────
--
-- İstemci her yazımdan sonra "2 yıldan eskiyi sil" DELETE'i gönderiyordu —
-- fiyat yenilemesi başına ikinci bir gidiş-dönüş. Günlük tek görev yeter.
-- (Eski sürümler DELETE'i göndermeye devam eder; indeksli ve zararsız.)
select cron.unschedule(jobid) from cron.job where jobname = 'snapshots-retention';
select cron.schedule('snapshots-retention', '25 3 * * *',
  $$delete from public.snapshots where ts < now() - interval '730 days'$$);

-- ── Kendini doğrulama ───────────────────────────────────────────────────────
do $$
declare
  ciplak int;
  cift int;
begin
  select count(*) into ciplak from pg_policies
   where schemaname = 'public'
     and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )auth\.uid\(\)';
  if ciplak > 0 then
    raise exception '0077: % politika hâlâ satır başına auth.uid() çağırıyor.', ciplak;
  end if;

  select count(*) into cift from (
    select user_id, saat from public.snapshots group by 1, 2 having count(*) > 1) x;
  if cift > 0 then
    raise exception '0077: % (kullanıcı, saat) çifti hâlâ tekrarlı.', cift;
  end if;

  if not exists (select 1 from pg_trigger where tgname = 'snapshots_saatlik') then
    raise exception '0077: snapshots_saatlik tetikleyicisi kurulamadı.';
  end if;

  raise notice '0077 tamam: RLS initplan, tekrar eden indeks/politika, FK indeksleri, saatlik anlık görüntü.';
end;
$$;
