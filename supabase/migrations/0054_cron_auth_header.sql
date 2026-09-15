-- 0054 — Cron çağrıları API gateway'de ölüyordu: secret ayrı header'a taşındı
--
-- ## Belirti
--
-- `daily_brief_log` Mayıs 2026'dan beri BOŞTU. Sabah brifingi hiç
-- gönderilmemişti. `calendar_nudge_log` ve `weekly_summary_log` de boş.
-- Cron her gün düzgün koşuyordu; hata hiçbir yerde görünmüyordu.
--
-- ## Sebep
--
-- Supabase API gateway, isteği edge function'a iletmeden ÖNCE
-- `Authorization` header'ını JWT olarak ayrıştırır. Tetikleyiciler oraya
-- rastgele hex bir cron secret koyuyordu:
--
--     Authorization: Bearer <cron_secret>   ← 64 karakter hex, JWT değil
--
-- Bu JWT biçiminde olmadığı için gateway isteği fonksiyona HİÇ ULAŞTIRMADAN
-- reddediyordu:
--
--     401 {"code":"UNAUTHORIZED_INVALID_JWT_FORMAT","message":"Invalid JWT"}
--
-- Yanıt `net._http_response` içine yazılıyor ama kimse okumuyordu. Fonksiyon
-- logları da boştu — çünkü fonksiyon hiç çalışmamıştı. Sessiz arıza.
--
-- ## Neden `live-activity-refresh` çalışıyordu
--
-- Vault'taki `live_activity_cron_secret` değeri 219 karakterdi: rastgele bir
-- string değil, gerçek bir service_role JWT'si. Gateway onu kabul ediyordu.
-- Yani tek çalışan iş, yanlışlıkla doğru header'ı taşıyordu.
--
-- ## Çözüm
--
--     Authorization: Bearer <service_role JWT>  → gateway'i geçer
--     x-cron-secret: <rastgele uzun string>     → fonksiyon doğrular
--
-- İki katman KORUNUR. Reddedilen iki alternatif:
--
--   · `verify_jwt = false`: gateway katmanı tamamen kalkar, fonksiyonlar
--     internete yalnızca secret korumasıyla açılır.
--   · Vault'a cron secret'ı OLARAK service_role JWT yazmak
--     (`live-activity`'nin bugünkü hâli): fonksiyon başına izolasyon
--     kaybolur — tek sızıntı tüm DB'yi açar.
--
-- ## Sıra ÖNEMLİ
--
-- Fonksiyonlar ÖNCE dağıtılır, migration SONRA koşar. `cron_auth.ts`
-- geriye dönük uyumlu (`Authorization: Bearer <secret>` hâlâ kabul edilir),
-- yani arada kalan çağrı kaybolmaz. Ters sırada — migration önce koşarsa —
-- eski fonksiyon `x-cron-secret`'ı tanımaz ve gönderim bir tur atlar.
--
-- ## Ayrıca: `timeout_milliseconds` eksik olan dördü
--
-- `0040_cron_http_timeout.sql` pg_net'in 5 saniyelik varsayılanının
-- tuzağını belgelemişti: süre aşımında pg_net yalnızca YANITI beklemeyi
-- bırakır, fonksiyon sunucuda çalışmaya devam eder. Sonuç "bazen çalışıyor"
-- gibi görünür ve teşhis edilemez. `daily_brief`, `calendar_nudge`,
-- `price_alerts` ve `live_activity` bu bayrağı hiç almamıştı; bu turda
-- hepsine veriliyor.

-- ── service_role JWT'si Vault'ta ────────────────────────────────────────────
--
-- Tetikleyiciler bunu `Authorization` header'ına koyacak. Vault'ta
-- `cron_gateway_jwt` adıyla BİR KEZ tutulur; her tetikleyiciye kopyalamak
-- rotasyonu yedi ayrı yere dokunmak yapardı.
--
-- Değeri KURULUM ADIMI (bu migration yazamaz — service_role key'i SQL
-- içinden okuyamaz ve repoya girmemeli):
--
--     select vault.create_secret(
--       '<service_role JWT>', 'cron_gateway_jwt',
--       'API gateway JWT dogrulamasini gecmek icin — cron tetikleyicileri'
--     );
--
-- Yoksa aşağıdaki fonksiyonlar açık hatayla durur. SESSİZ düşmemesi
-- kasıtlı: bu arızanın ilk hâli tam olarak sessizliğinden dolayı dört ay
-- fark edilmedi.

-- Gateway JWT'sini okuyan ortak yardımcı.
--
-- Mükerrer Vault kaydı tuzağı `0034`'ten miras: aynı adla ikinci bir kayıt
-- oluşturulduğunda hangisinin döndüğü belirsizdi. En SON oluşturulan
-- kullanılır; mükerrer varsa uyarı basılır (sessizce doğru olanı seçmek
-- Vault'ta çöp biriktiğini gizler).
create or replace function public.cron_gateway_jwt()
returns text
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  jwt text;
  adet int;
begin
  select count(*) into adet
  from vault.decrypted_secrets
  where name = 'cron_gateway_jwt';

  if adet > 1 then
    raise warning
      'Vault''ta % adet cron_gateway_jwt kaydi var — en yenisi kullanilacak. Fazlalari silin.',
      adet;
  end if;

  select decrypted_secret into jwt
  from vault.decrypted_secrets
  where name = 'cron_gateway_jwt'
  order by created_at desc
  limit 1;

  if jwt is null then
    raise exception
      'Vault secret cron_gateway_jwt bulunamadi. Cron cagrilari API gateway''de 401 alir. Kurulum: select vault.create_secret(''<service_role JWT>'', ''cron_gateway_jwt'');';
  end if;

  return jwt;
end;
$$;

revoke all on function public.cron_gateway_jwt() from public, anon, authenticated;
grant execute on function public.cron_gateway_jwt() to service_role;

-- Cron secret'ını okuyan ortak yardımcı — aynı mükerrer-kayıt kuralı.
create or replace function public.cron_secret_of(secret_name text)
returns text
language plpgsql
security definer
set search_path = public, vault
as $$
declare
  s text;
begin
  select decrypted_secret into s
  from vault.decrypted_secrets
  where name = secret_name
  order by created_at desc
  limit 1;

  if s is null then
    raise exception 'Vault secret % bulunamadi', secret_name;
  end if;

  return s;
end;
$$;

revoke all on function public.cron_secret_of(text) from public, anon, authenticated;
grant execute on function public.cron_secret_of(text) to service_role;

-- Cron HTTP başlıkları — tek yerde.
--
-- Yedi tetikleyicinin hepsi bunu çağırır. Header deseni bir daha
-- değişirse (gateway davranışı yine değişebilir) dokunulacak tek yer.
create or replace function public.cron_headers(secret_name text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'Content-Type', 'application/json',
    -- Gateway'i geçmek için: JWT biçiminde OLMALI.
    'Authorization', 'Bearer ' || public.cron_gateway_jwt(),
    -- Fonksiyonun doğruladığı sır (bkz. _shared/cron_auth.ts).
    'x-cron-secret', public.cron_secret_of(secret_name)
  );
$$;

revoke all on function public.cron_headers(text) from public, anon, authenticated;
grant execute on function public.cron_headers(text) to service_role;

-- ── Tetikleyiciler ──────────────────────────────────────────────────────────

-- analyze-signals (0017 → 0040 → bu)
create or replace function public.trigger_analyze_signals(slot text)
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/analyze-signals',
    headers := public.cron_headers('analyze_signals_cron_secret'),
    body := jsonb_build_object('slot', slot),
    -- 0040: teknik analiz turu 5 saniyede bitmez.
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.trigger_analyze_signals(text) from public, anon, authenticated;

-- daily-brief (0044 → bu). timeout İLK KEZ veriliyor.
create or replace function public.trigger_daily_brief()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/daily-brief',
    headers := public.cron_headers('daily_brief_cron_secret'),
    body := '{}'::jsonb,
    -- Her kullanıcı için fiyat geçmişi yüklenir; 5 saniye yetmez.
    timeout_milliseconds := 120000
  );
end;
$$;

revoke all on function public.trigger_daily_brief() from public, anon, authenticated;

-- weekly-summary (0052 → bu)
create or replace function public.trigger_weekly_summary()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/weekly-summary',
    headers := public.cron_headers('weekly_summary_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_weekly_summary() from public, anon, authenticated;

-- fetch-inflation (0053 → bu)
create or replace function public.trigger_fetch_inflation()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/fetch-inflation',
    headers := public.cron_headers('inflation_fetch_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    -- EVDS turu + 24 aylık upsert 5 saniyede bitmez.
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_fetch_inflation() from public, anon, authenticated;

-- calendar-nudge (0048 → bu). timeout İLK KEZ veriliyor.
create or replace function public.trigger_calendar_nudge()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/calendar-nudge',
    headers := public.cron_headers('calendar_nudge_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_calendar_nudge() from public, anon, authenticated;

-- check-price-alerts (0046 → bu). timeout İLK KEZ veriliyor.
create or replace function public.trigger_check_price_alerts()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/check-price-alerts',
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_check_price_alerts() from public, anon, authenticated;

-- push-live-activity (0033 → 0034 → bu)
--
-- Bu fonksiyon cron secret'ı DOĞRULAMIYOR — yalnızca gateway JWT'sine
-- dayanıyor ve o yüzden tek çalışan işti. Yine de aynı desene alınıyor:
-- Vault'undaki service_role JWT'si artık `Authorization`'a `cron_gateway_jwt`
-- üzerinden gelir ve `live_activity_cron_secret` ayrı header'da taşınır.
-- Böylece o Vault kaydı JWT tutmaktan kurtulur ve rotasyon tek yere döner.
--
-- Boş tur atlama korunuyor (0033): aktif oturum yoksa HTTP turu atılmaz.
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
    url := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/push-live-activity',
    headers := public.cron_headers('live_activity_cron_secret'),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_live_activity_push() from public, anon, authenticated;

-- ── Yerel/CI yığını için Vault tohumu ───────────────────────────────────────
--
-- Aşağıdaki doğrulama bloğu Vault'ta yedi cron secret'ı + gateway JWT'si
-- arar ve yoksa `raise exception` eder. Bu CANLI için doğru: `0054`'ün
-- tamamı "sessizce uygulanmamış migration" arızasından doğdu ve fail-closed
-- olması bilinçli bir karardır.
--
-- Ama `supabase start` (CI, `db reset`) TAZE ve BOŞ bir Vault ile gelir.
-- Orada secret'lar hiç yoktur, migration zinciri burada durur ve arkasındaki
-- her şey — duman testi, emülatörde `integration_test/` — hiç koşmaz.
-- `integration.yml` bu yüzden aylarca her push'ta kırıldı: kapının tek işi
-- "yeni migration taze yığında kırılıyor mu?" sorusunu yanıtlamaktı ve
-- sürekli kırmızı olduğu için sinyal değeri sıfıra indi.
--
-- ## Değişmez: VAR OLAN BİR SECRET'A ASLA DOKUNULMAZ
--
-- `where not exists` kapısı satır satır uygulanır. Canlıda yedi secret da
-- mevcut olduğu için bu blok orada HİÇBİR ŞEY yazmaz — gerçek bir değeri
-- ezme yolu yoktur. Yalnızca hiç kaydı olmayan bir Vault'a (yani taze yerel
-- yığına) placeholder koyar.
--
-- ## Neden `db push` bunu canlıya taşımaz
--
-- `0054` canlıda ZATEN uygulanmış durumda (defterde kayıtlı, 2026-09-14'te
-- `repair --status reverted` + `db push --include-all` ile gerçekten koştu).
-- Uygulanmış bir migration yeniden çalıştırılmaz; bu düzenleme yalnızca
-- BUNDAN SONRA kurulan taze yığınları etkiler.
--
-- ## Değerler neden böyle
--
-- Gateway JWT'si üç parçalı bir JWT BİÇİMİNDE olmak zorunda: doğrulama
-- bloğu `^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$` regex'iyle
-- biçim denetimi yapıyor (hex bir string yazılırsa arıza sessizce geri
-- dönerdi). Aşağıdaki değer o biçime uyan, `local-stack-only` yazan ve
-- HİÇBİR YERDE geçerli olmayan sahte bir token'dır.
--
-- Bunlar gerçek secret DEĞİLDİR ve öyle görünmemelidir: adları açıkça
-- yereli söyler. Yerel yığın dışarıdan erişilemez, her `db reset`'te
-- sıfırlanır ve bu tetikleyiciler CI'da hiç çağrılmaz — çağrılsalar bile
-- `net.http_post` hedefi canlı proje URL'si olduğu için gateway reddeder.
do $$
declare
  ad text;
begin
  -- Gateway JWT'si — JWT biçiminde olmak ZORUNDA (regex denetimi var).
  if not exists (
    select 1 from vault.decrypted_secrets where name = 'cron_gateway_jwt'
  ) then
    perform vault.create_secret(
      'eyJsb2NhbCI6dHJ1ZX0.eyJzdWIiOiJsb2NhbC1zdGFjay1vbmx5In0.local-stack-only-not-a-real-key',
      'cron_gateway_jwt'
    );
  end if;

  -- Yedi cron secret'ı. Biçim serbest: yalnızca varlıkları denetleniyor.
  foreach ad in array array[
    'analyze_signals_cron_secret',
    'daily_brief_cron_secret',
    'weekly_summary_cron_secret',
    'inflation_fetch_cron_secret',
    'calendar_nudge_cron_secret',
    'price_alerts_cron_secret',
    'live_activity_cron_secret'
  ] loop
    if not exists (
      select 1 from vault.decrypted_secrets where name = ad
    ) then
      perform vault.create_secret('local-stack-only-not-a-real-secret', ad);
    end if;
  end loop;
end;
$$;

-- ── Kendini doğrulama ───────────────────────────────────────────────────────
--
-- Bu migration'ın ASIL RİSKİ sessiz başarısızlık: düzelttiği hata dört ay
-- fark edilmemişti çünkü kimse `net._http_response`'a bakmıyordu. O yüzden
-- kurulumun eksik kalması burada YÜKSEK SESLE patlar.
do $$
declare
  eski int;
  jwt  text;
begin
  -- 1) Hiçbir tetikleyicide eski desen kalmadı mı?
  select count(*) into eski
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'trigger_%'
    and pg_get_functiondef(p.oid) ~ '''Authorization'', ''Bearer '' \|\| cron_secret';

  if eski > 0 then
    raise exception
      '% tetikleyici hala Authorization header''ina cron secret koyuyor — gateway 401 dondurur.',
      eski;
  end if;

  -- 2) Gateway JWT'si Vault'ta var mı ve JWT BİÇİMİNDE mi?
  --
  -- Biçim denetimi şart: buraya yanlışlıkla hex bir string yazılırsa hata
  -- yine sessiz olur ve düzeltilen arıza aynen geri döner.
  begin
    jwt := public.cron_gateway_jwt();
  exception when others then
    raise exception
      'KURULUM EKSIK: %  ->  select vault.create_secret(''<service_role JWT>'', ''cron_gateway_jwt'');',
      sqlerrm;
  end;

  if jwt !~ '^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$' then
    raise exception
      'cron_gateway_jwt bir JWT gibi gorunmuyor (uzunluk %). Gateway yine 401 dondurur — service_role key''i yazin.',
      length(jwt);
  end if;

  -- 3) Her tetikleyicinin okuduğu cron secret Vault'ta var mı?
  perform public.cron_secret_of('analyze_signals_cron_secret');
  perform public.cron_secret_of('daily_brief_cron_secret');
  perform public.cron_secret_of('weekly_summary_cron_secret');
  perform public.cron_secret_of('inflation_fetch_cron_secret');
  perform public.cron_secret_of('calendar_nudge_cron_secret');
  perform public.cron_secret_of('price_alerts_cron_secret');
  perform public.cron_secret_of('live_activity_cron_secret');

  raise notice
    '0054 tamam: 7 tetikleyici x-cron-secret desenine gecti, gateway JWT''si yerinde.';
end;
$$;
