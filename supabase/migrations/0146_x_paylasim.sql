-- 0146 — SANDIK X (Twitter) hesabı: gönderi taslakları ve günlük tetik (2026-10-13)
--
-- ## Neden
-- yasin (13 Eki): "finansal yorumlar yapan bir twitter botu … sandık
-- markasıyla, o günün en öne çıkanları, istatistiki veri, yorumlamaktan
-- çok insansı cümlelerle." Bot olanı anlatır (TEFAS fon akışı, TÜİK TÜFE);
-- tahmin ve yönlendirme yok. İçerik kuralları: `_shared/x_paylasim.ts`.
--
-- ## Akış
-- pg_cron (hafta içi TR 19:40) → `x-paylas` taslak yazar ve Telegram'da
-- yasin'e "Yayınla / Reddet" ile gösterir → `x-onay` (Telegram webhook)
-- onaylananı X'e atar. Hepsi function secret'larıyla kapalı doğar
-- (`X_BOT_MODU` tanımsız → 503, hiçbir iş yapılmaz, AI maliyeti yok).
--
-- ## Eski sürümler / canlı kullanıcı
-- Yalnızca EKLER. Uygulama bu tabloya hiç dokunmaz; istemciye görünmez.
-- Kullanıcı verisi kullanılmaz → yasal metin değişmez.
--
-- ## Secret
-- Tetik, fon akışı gözlemiyle aynı Vault kaydını kullanır
-- (`tefas_nav_cron_secret`; emsal 0106): yeni kayıt iki sunucuda elle kurulum
-- isterdi. Sızarsa en çok günde bir taslak açtırır (tür + dönem benzersiz).

-- ── 1) Taslak / gönderi defteri ─────────────────────────────────────────────
create table if not exists public.x_gonderileri (
  id               bigint generated always as identity primary key,
  tur              text not null check (tur in ('fon_akisi', 'haftalik', 'tufe', 'abd_tufe', 'fed')),
  -- Gönderinin anlattığı gün (fon_akisi, haftalik: haftanın Cuma'sı) ya da
  -- ayın ilk günü (tufe).
  donem            date not null,
  -- Gönderilecek metin (model ya da şablon; ikisi de kapıdan geçmiş).
  metin            text not null check (char_length(metin) between 20 and 280),
  sablon_metin     text not null,
  metin_kaynagi    text not null check (metin_kaynagi in ('model', 'sablon')),
  -- Metnin dayandığı olgular ve kart verisi: görsel bunlardan yeniden
  -- çizilir (PNG saklanmaz; Free plan 500 MB).
  olgular          jsonb not null default '[]'::jsonb,
  kart             jsonb not null,
  durum            text not null default 'taslak' check (durum in
                     ('taslak', 'onaylandi', 'gonderiliyor', 'gonderildi', 'reddedildi', 'suresi_doldu', 'hata')),
  model            text,
  maliyet_usd      numeric(10, 5),
  model_red_nedeni text,
  x_id             text,
  hata             text,
  olusturuldu      timestamptz not null default now(),
  karar_at         timestamptz,
  gonderildi_at    timestamptz,
  -- Gün başına tür başına tek taslak: cron iki kez koşsa da model bir kez.
  unique (tur, donem)
);

create index if not exists x_gonderileri_olusturuldu
  on public.x_gonderileri (olusturuldu);

comment on table public.x_gonderileri is
  'SANDIK X hesabi gonderi taslaklari (0146). Yalniz x-paylas / x-onay '
  '(service_role) okur ve yazar; istemciye kapali.';

alter table public.x_gonderileri enable row level security;
alter table public.x_gonderileri force row level security;
-- Politika YOK: anon/authenticated hiçbir satırı göremez (service_role RLS'i aşar).
revoke all on table public.x_gonderileri from public, anon, authenticated;
grant select, insert, update, delete on table public.x_gonderileri to service_role;

-- ── 2) Tetikleyici (0106 deseni) ────────────────────────────────────────────
create or replace function public.trigger_x_paylas()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('x-paylas'),
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Model çağrısı + kart çizimi + Telegram; birkaç saniye.
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_x_paylas() from public, anon, authenticated;

-- ── 3) Zamanlama (pg_cron UTC) ──────────────────────────────────────────────
-- TR 19:40, Pzt–Cum. Fon akışının günün son turu TR 19:15 (0106); 25 dk pay.
select cron.unschedule(jobid) from cron.job where jobname = 'x-paylas';
select cron.schedule('x-paylas', '40 16 * * 1-5',
  $$select public.trigger_x_paylas()$$);

-- İki sunucu birebir: proje "tüm cron kapalı" kipindeyse yeni iş de kapalı
-- doğar (0086/0089/0101/0106 gerekçesi; proje ref'i sabit yazılmaz).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'x-paylas')
     and not exists (select 1 from cron.job
                      where jobname <> 'x-paylas' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'x-paylas';
    raise notice '0146: projede tum cron isleri kapali — x-paylas de kapali kuruldu.';
  end if;
end $$;

-- ── 4) Doğrulama: GRANT ve RLS ayrı şeyler (0036/0042 deseni) ───────────────
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.x_gonderileri'::regclass) then
    raise exception '0146: x_gonderileri RLS kapali';
  end if;
  if has_table_privilege('anon', 'public.x_gonderileri', 'select')
     or has_table_privilege('authenticated', 'public.x_gonderileri', 'select') then
    raise exception '0146: istemci x_gonderileri okuyabiliyor';
  end if;
  if has_function_privilege('authenticated', 'public.trigger_x_paylas()', 'execute') then
    raise exception '0146: authenticated tetigi calistirabiliyor';
  end if;
end;
$$;
