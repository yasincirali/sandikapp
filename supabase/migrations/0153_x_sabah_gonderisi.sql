-- 0153 — SANDIK X hesabı: sabah gönderisi ve veri takvimi (2026-10-15)
--
-- ## Neden
-- yasin (15 Eki): "günde 2 gönderi yapmak istesek", karar kartında "İkisi
-- dönüşümlü": akşam 19:40 gönderisi aynen kalır; sabah TR 09:30'da
-- Pazartesi haftanın veri takvimi, diğer günler dünün fon getirileri
-- (kategori medyanı, TEFAS). Pazartesi takvimde olay yoksa getiri atılır.
--
-- ## Takvim neden tablo
-- Açıklama günleri kuralla tahmin edilmez: TÜİK "ayın 3'ü" hafta sonuna
-- düşünce kayar (Eylül 2026 verisi 5 Ekim'de), Fed ve TCMB yıllık takvim
-- ilan eder. Yanlış gün yazmak uydurma sayı demek; yalnız duyurudan
-- doğrulanmış satır girer. Tablo boşsa Pazartesi de getiri gönderisi atılır.
--
-- ## Eski sürümler / canlı kullanıcı
-- Yalnızca EKLER: tür listesine iki değer, bir tablo, bir tetik, bir cron.
-- Uygulama bu tablolara dokunmaz. Kullanıcı verisi yok → yasal metin değişmez.
--
-- ## İki sunucu
-- Sabah cron'u akşamki `x-paylas` ile aynı aktiflikte kurulur: Frankfurt'ta
-- `x-paylas` geçişe kadar kapalı (çift gönderi), sabah da kapalı doğar.
-- Geçiş gecesi ikisi birlikte açılır (frankfurt-tasima/gecis_gecesi_K4.md).

-- ── 1) Yeni gönderi türleri ─────────────────────────────────────────────────
alter table public.x_gonderileri drop constraint if exists x_gonderileri_tur_check;
alter table public.x_gonderileri add constraint x_gonderileri_tur_check
  check (tur in ('fon_akisi', 'haftalik', 'tufe', 'abd_tufe', 'fed', 'fon_getiri', 'takvim'));

-- ── 2) Veri takvimi ─────────────────────────────────────────────────────────
create table if not exists public.x_takvim (
  id      bigint generated always as identity primary key,
  -- Açıklama günü, TR takvimi.
  tarih   date not null,
  -- TR saati; bilinmiyorsa NULL (gönderide saat yazılmaz).
  saat    time,
  baslik  text not null check (char_length(baslik) between 3 and 60),
  -- Tarihin doğrulandığı duyuru (denetim için; gönderide geçmez).
  kaynak  text not null,
  unique (tarih, baslik)
);

comment on table public.x_takvim is
  'SANDIK X hesabi Pazartesi takvim gonderisinin olaylari (0153). Yalniz '
  'dogrulanmis duyurular; x-paylas (service_role) okur, istemciye kapali.';

alter table public.x_takvim enable row level security;
alter table public.x_takvim force row level security;
-- Politika YOK: anon/authenticated göremez (service_role RLS'i aşar).
revoke all on table public.x_takvim from public, anon, authenticated;
grant select, insert, update, delete on table public.x_takvim to service_role;

-- Ekim–Aralık 2026, duyurulardan (15 Eki 2026 itibarıyla). Saatler TR:
-- TCMB kararı 14:00; Fed kararı 14:00 ET (28 Eki EDT → 21:00, 9 Ara EST → 22:00).
-- TÜİK TÜFE ve BLS TÜFE günleri resmi takvimden doğrulanamadı; eklenmedi.
insert into public.x_takvim (tarih, saat, baslik, kaynak) values
  ('2026-10-22', '14:00', 'TCMB faiz kararı',       'TCMB 2026 PPK toplantı takvimi'),
  ('2026-10-28', '21:00', 'Fed faiz kararı',        'Federal Reserve 2026 FOMC takvimi'),
  ('2026-11-12', null,    'TCMB Enflasyon Raporu',  'TCMB 2026 Enflasyon Raporu takvimi'),
  ('2026-12-09', '22:00', 'Fed faiz kararı',        'Federal Reserve 2026 FOMC takvimi'),
  ('2026-12-10', '14:00', 'TCMB faiz kararı',       'TCMB 2026 PPK toplantı takvimi')
on conflict (tarih, baslik) do nothing;

-- ── 3) Tetikleyici (0146 deseni, gövdede kip) ───────────────────────────────
create or replace function public.trigger_x_paylas_sabah()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('x-paylas'),
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'kip', 'sabah'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_x_paylas_sabah() from public, anon, authenticated;

-- ── 4) Zamanlama: TR 09:30, Pzt–Cum ─────────────────────────────────────────
-- Dünün fon verisi akşam turlarında tamamlanır; 09:30 piyasa açılışından önce.
select cron.unschedule(jobid) from cron.job where jobname = 'x-paylas-sabah';
select cron.schedule('x-paylas-sabah', '30 6 * * 1-5',
  $$select public.trigger_x_paylas_sabah()$$);

-- Akşamki işle aynı aktiflik (Frankfurt'ta geçişe kadar kapalı).
do $$
begin
  if exists (select 1 from cron.job where jobname = 'x-paylas' and not active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'x-paylas-sabah';
    raise notice '0153: x-paylas kapali — x-paylas-sabah de kapali kuruldu.';
  end if;
end $$;

-- ── 5) Doğrulama: GRANT ve RLS ayrı şeyler (0036/0042 deseni) ───────────────
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.x_takvim'::regclass) then
    raise exception '0153: x_takvim RLS kapali';
  end if;
  if has_table_privilege('anon', 'public.x_takvim', 'select')
     or has_table_privilege('authenticated', 'public.x_takvim', 'select') then
    raise exception '0153: istemci x_takvim okuyabiliyor';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_x_paylas_sabah()', 'execute') then
    raise exception '0153: authenticated tetigi calistirabiliyor';
  end if;
end;
$$;
