-- 0076 — Edge function adresi Vault'tan: proje taşınabilir hâle geldi
--
-- ## Neden
--
-- Proje Tokyo'dan (ap-northeast-1, ref ybdb…) Frankfurt'a (eu-central-1,
-- ref ynwy…) taşınıyor (kullanıcı kararı 2026-09-27; plan:
-- docs/SUPABASE_FRANKFURT_TASIMA.md). Supabase bir projenin bölgesini
-- değiştirmiyor — yeni proje açılıp şema bu migration zinciriyle kuruluyor.
--
-- Ama 14 tetikleyici fonksiyon eski projenin adresini SABİT yazıyordu
-- (0017'den beri kopyalanarak çoğaldı). Zincir yeni projeye olduğu gibi
-- koşulsaydı, Frankfurt'taki cron'lar Tokyo'daki fonksiyonları çağırmaya
-- devam ederdi: taşıma bitmiş görünür, iş eski projede yürür, eski proje
-- kapatıldığı gün bildirimler sessizce durur. 0054'ün belgelediği sınıfın
-- aynısı — hata `net._http_response`'a düşer, kimse bakmaz.
--
-- ## Çözüm
--
-- Adres tek yerden okunur: Vault'taki `project_url` (Supabase'in kendi cron
-- örneklerindeki ad). Her proje kendi değerini taşır; migration ikisinde de
-- aynıdır.
--
--     select vault.create_secret('https://<ref>.supabase.co', 'project_url');
--
-- ## Neden eksikse EXCEPTION değil WARNING
--
-- `integration.yml`'in yerel yığını (`supabase start`) boş Vault ile gelir
-- ve bu migration'ı da koşar. 0054 bunun için yer tutucu tohum ekmişti; burada
-- tohum EKİLMEZ: yer tutucu bir adres canlıda yanlışlıkla kalırsa istekler
-- sessizce yanlış yere gider. Onun yerine çağrı anında `cron_secret_of`
-- 'Vault secret project_url bulunamadi' diye patlar — hata
-- `cron.job_run_details`'ta "failed" olarak görünür (fail-closed). Migration
-- anında ise uyarı basılır; canlıda `db push` ÖNCESİ secret yazılmış olmalı
-- (taşıma belgesi, adım sırası).
--
-- ## Kapsam
--
-- Gövdeler, her fonksiyonun SON tanımının (0023/0054/0063/0067/0068/0074)
-- birebir kopyasıdır; yalnızca `url :=` satırı değişti. Tek istisna
-- `push_test_trigger`: 0023'ten beri cron secret'ı Authorization'a koyuyordu
-- — 0054'ün gateway 401 hatasının atlanmış son örneği (yönetici test
-- düğmesi, cron değil; o yüzden gözden kaçmış). O da `cron_headers`'a geçti.
--
-- `x-region: eu-central-1` (kripto): Binance ABD bölgesini engellediği için
-- fonksiyon Frankfurt'ta koşturuluyordu (0074). Proje artık zaten orada;
-- başlık zararsız, korunuyor — proje başka bölgeye giderse yine gerekir.

-- ── Yardımcı ────────────────────────────────────────────────────────────────

create or replace function public.edge_function_url(fn text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  -- Ad yalnızca sabit literal olarak gelir; yine de yol enjeksiyonuna
  -- (`../`, `?`) kapı bırakma.
  if fn !~ '^[a-z0-9-]+$' then
    raise exception 'Gecersiz edge function adi: %', fn;
  end if;

  return rtrim(public.cron_secret_of('project_url'), '/') || '/functions/v1/' || fn;
end;
$$;

revoke all on function public.edge_function_url(text) from public, anon, authenticated;
grant execute on function public.edge_function_url(text) to service_role;

comment on function public.edge_function_url(text) is
  'Edge function adresi = Vault project_url + /functions/v1/<ad>. Proje taşınabilirliği için tek kaynak (0076).';

-- ── Tetikleyiciler (son tanımlar; yalnızca url değişti) ─────────────────────

-- 0054
create or replace function public.trigger_analyze_signals(slot text)
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('analyze-signals'),
    headers := public.cron_headers('analyze_signals_cron_secret'),
    body := jsonb_build_object('slot', slot),
    -- 0040: teknik analiz turu 5 saniyede bitmez.
    timeout_milliseconds := 120000
  );
end;
$$;

-- 0054
create or replace function public.trigger_calendar_nudge()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('calendar-nudge'),
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0054
create or replace function public.trigger_check_price_alerts()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('check-price-alerts'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0054
create or replace function public.trigger_daily_brief()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('daily-brief'),
    headers := public.cron_headers('daily_brief_cron_secret'),
    body := '{}'::jsonb,
    -- Her kullanıcı için fiyat geçmişi yüklenir; 5 saniye yetmez.
    timeout_milliseconds := 120000
  );
end;
$$;

-- 0068
create or replace function public.trigger_daily_brief_evening()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('daily-brief'),
    headers := public.cron_headers('daily_brief_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'slot', 'evening'),
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0054
create or replace function public.trigger_fetch_inflation()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('fetch-inflation'),
    headers := public.cron_headers('inflation_fetch_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- EVDS turu + 24 aylık upsert 5 saniyede bitmez.
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0074
create or replace function public.trigger_kripto_fiyat()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('kripto-fiyat'),
    headers := public.cron_headers('kripto_cron_secret')
               || jsonb_build_object('x-region', 'eu-central-1'),
    body := jsonb_build_object('source', 'cron'),
    -- ~4 paralel Binance isteği + tek upsert; 10 sn zaman aşımı × yedek.
    timeout_milliseconds := 45000
  );
end;
$$;

-- 0074
create or replace function public.trigger_kripto_katalog()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('kripto-katalog'),
    headers := public.cron_headers('kripto_cron_secret')
               || jsonb_build_object('x-region', 'eu-central-1'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0054
create or replace function public.trigger_live_activity_push()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  if not exists (
    select 1 from live_activity_sessions where expires_at > now()
  ) then
    return;
  end if;

  perform net.http_post(
    url := public.edge_function_url('push-live-activity'),
    headers := public.cron_headers('live_activity_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0067
create or replace function public.trigger_monthly_summary()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('weekly-summary'),
    headers := public.cron_headers('weekly_summary_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'period', 'month'),
    -- Ay penceresi için 365 günlük snapshot taraması; 5 sn yetmez (0040).
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0063
create or replace function public.trigger_observe_tefas_nav()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('observe-tefas-nav'),
    headers := public.cron_headers('tefas_nav_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- Kod sayısı kadar TEFAS isteği (4'lü paralel); 5 sn yetmez
    -- (bkz. 0040_cron_http_timeout.sql).
    timeout_milliseconds := 90000
  );
end;
$$;

-- 0068
create or replace function public.trigger_watchlist_moves()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('check-price-alerts'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron', 'watchlist', true),
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0054
create or replace function public.trigger_weekly_summary()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('weekly-summary'),
    headers := public.cron_headers('weekly_summary_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

-- 0023 — yönetici test düğmesi (cron değil). Yetki kontrolü ve imza aynen;
-- başlıklar artık cron_headers'tan (gateway JWT + x-cron-secret).
create or replace function public.push_test_trigger(
  p_slot     text default 'morning',
  p_dry_run  boolean default true
)
returns text
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  req_id bigint;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  if p_slot not in ('morning', 'afternoon') then
    raise exception 'Gecersiz slot: %', p_slot;
  end if;

  select net.http_post(
    url := public.edge_function_url('analyze-signals'),
    headers := public.cron_headers('analyze_signals_cron_secret'),
    body := jsonb_build_object('slot', p_slot, 'dry_run', p_dry_run),
    timeout_milliseconds := 120000
  ) into req_id;

  -- net.http_post asenkron: yanıt net._http_response'a düşer.
  -- push_http_responses() ile birkaç saniye sonra okunabilir.
  return 'İstek kuyruğa alındı (id=' || req_id ||
         '). Birkaç saniye sonra yenileyip 3. bölüme bakın.';
end;
$$;

-- ── Kendini doğrulama ───────────────────────────────────────────────────────
do $$
declare
  sabit int;
  url   text;
begin
  -- 1) Hiçbir public fonksiyonda sabit proje adresi kalmadı mı?
  --    (Burada EXCEPTION: bu, migration'ın kendi işini yapıp yapmadığı.)
  select count(*) into sabit
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.prokind = 'f'
    and pg_get_functiondef(p.oid) ~ '[a-z0-9]{20}\.supabase\.co/functions';

  if sabit > 0 then
    raise exception
      '% fonksiyon hala sabit bir proje adresi tasiyor — tasima sonrasi eski projeyi cagirir.',
      sabit;
  end if;

  -- 2) project_url Vault'ta mı? (WARNING — gerekçe başlıkta.)
  begin
    url := public.cron_secret_of('project_url');
  exception when others then
    raise warning
      'KURULUM EKSIK: project_url yok — cron cagrilari basarisiz olur.  ->  select vault.create_secret(''https://<ref>.supabase.co'', ''project_url'');';
    return;
  end;

  if url !~ '^https://[a-z0-9]+\.supabase\.co/?$' then
    raise warning
      'project_url beklenen bicimde degil (%): yerel yigin disinda https://<ref>.supabase.co olmali.',
      url;
  end if;

  raise notice '0076 tamam: 14 fonksiyon adresi Vault project_url''den okuyor (%).', url;
end;
$$;
