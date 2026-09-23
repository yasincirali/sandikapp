-- 0072_db_logs_hata_detayi.sql
-- ============================================================
-- `db_logs`: yapılandırılmış hata detayı + stack trace.
-- Panel: push token künyesi.
--
-- ── Neden ───────────────────────────────────────────────────────────────────
-- Bugün hata TEK bir yerde duruyor: `response_json->>'error'`, yani
-- `e.toString()`'in maskelenmiş hâli. Bu üç şeyi birden kaybediyor:
--
--   1. **Hata SINIFI.** `PostgrestException` mi `TimeoutException` mı
--      `ClientException` mı? İlki şema/RLS sorunu, ikincisi ağ, üçüncüsü
--      bağlantı. Aynı metnin içine gömülü oldukları için gruplama
--      (`admin_error_clusters`) bunları ayıramıyor.
--   2. **Hata KODU.** Postgres `42501` (RLS reddi) ile `23505` (tekillik
--      ihlali) tamamen farklı müdahaleler ister. Bugün ikisi de serbest
--      metin içinde kayıp.
--   3. **NEREDE kırıldığı.** Stack trace hiç tutulmuyor. `source` alanı
--      yalnızca çağıran servisi söylüyor ("SupabaseService.updateAsset");
--      o çağrının hangi ekrandan, hangi akıştan geldiği bilinmiyor.
--      Crashlytics'te var ama orada da `db_logs` satırıyla eşleşmiyor —
--      iki ayrı pencerede iki ayrı arama demek.
--
-- ── PII kararı (kullanıcı, 2026-09-22) ─────────────────────────────────────
-- E-posta ve oturum JWT'si log satırına YAZILMAZ. Gerekçe yalnızca ilke
-- değil, yayınlanmış taahhüt: `legal/tr/PRIVACY_POLICY.md` ve `legal/en/`
-- iki ayrı yerde "hassas alanlar (e-posta, şifre, token) maskelenir"
-- diyor ve bu metin mağazalara da beyan edildi.
--
-- Teşhis gücü bundan ZARAR GÖRMÜYOR:
--   · e-posta → `user_id` log'da, panel `profiles` ile join edip EKRANDA
--     gösteriyor (0070'ten beri çalışıyor).
--   · FCM push token → `user_push_tokens` tablosunda; bu migration panel
--     künyesine TAM değerini getiriyor (aşağıda `admin_user_push_tokens`).
--   · oturum JWT'si → hiçbir yerde. Loglanırsa panel bir sır deposuna
--     dönüşür: satırı okuyan herkes o oturumu taklit edebilir. Onun yerine
--     oturumun DURUMU (son giriş, süre) künyede zaten var.
--
-- Stack trace istemcide `DbLogger.sanitize()`'dan geçirilerek yazılır
-- (JWT/e-posta/UUID/IP maskesi). Bu migration alanı açar; doldurma
-- istemci turunda (bkz. TECHNICAL_DEBT).
-- ============================================================

-- ── Yeni kolonlar ───────────────────────────────────────────────────────────
alter table public.db_logs
  -- Dart sınıf adı: 'PostgrestException', 'TimeoutException',
  -- 'ClientException', 'AuthApiException'… Gruplamanın birincil ekseni.
  add column if not exists error_type text,

  -- Sağlayıcı hata kodu. Postgres SQLSTATE ('42501', '23505'), PostgREST
  -- kodu ('PGRST202'), HTTP durumu ('401') — hangisi varsa.
  add column if not exists error_code text,

  -- Maskelenmiş hata mesajı. `response_json->>'error'` ile çakışıyor gibi
  -- görünür ama ayrı tutuluyor: o alan serbest bir özet, bu alan
  -- İNDEKSLENEBİLİR ve gruplanabilir tek bir metin.
  add column if not exists error_message text,

  -- Maskelenmiş stack trace. Uzun: kırpma İSTEMCİDE yapılır (ilk ~40 kare),
  -- burada sınır yok — kırpılmış bir trace'i sonradan uzatmak imkânsız.
  add column if not exists stack_trace text;

comment on column public.db_logs.error_type is
  'Dart hata sınıfı (PostgrestException, TimeoutException…). Gruplamanın birincil ekseni.';
comment on column public.db_logs.error_code is
  'Sağlayıcı kodu: SQLSTATE (42501), PostgREST (PGRST202) veya HTTP durumu.';
comment on column public.db_logs.error_message is
  'Maskelenmiş hata mesajı. response_json->>''error'' serbest özettir; bu alan gruplanabilir.';
comment on column public.db_logs.stack_trace is
  'Maskelenmiş stack trace (DbLogger.sanitize). E-posta/UUID/JWT/IP temizlenmiş hâlde yazılır.';

-- Hata sınıfı + kod bazlı tarama: "bugün kaç RLS reddi aldık".
create index if not exists db_logs_error_type_idx
  on public.db_logs (error_type, ts desc)
  where is_error;

-- ── admin_user_logs: hata alanlarını taşı ───────────────────────────────────
-- `returns table` genişliyor → drop şart (42P13), GRANT yeniden verilir.
drop function if exists public.admin_user_logs(uuid,int,boolean,text,timestamptz,text,text);

create or replace function public.admin_user_logs(
  p_user_id     uuid,
  p_limit       int     default 200,
  p_only_errors boolean default false,
  p_source_like text    default null,
  p_since       timestamptz default null,
  p_session_id  text    default null,
  p_device_id   text    default null
)
returns table (
  id            bigint,
  ts            timestamptz,
  requested_at  timestamptz,
  responded_at  timestamptz,
  saat_farki_ms bigint,
  source        text,
  table_name    text,
  op            text,
  event_kind    text,
  duration_ms   integer,
  is_error      boolean,
  error_type    text,
  error_code    text,
  error_message text,
  stack_trace   text,
  session_id    text,
  device_id     text,
  platform      text,
  os_version    text,
  app_version   text,
  device_model  text,
  request_json  jsonb,
  response_json jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select d.id, d.ts, d.requested_at, d.responded_at,
         case
           when d.requested_at is null then null
           else (extract(epoch from (d.ts - d.requested_at)) * 1000)::bigint
         end,
         d.source, d.table_name, d.op, d.event_kind,
         d.duration_ms, d.is_error,
         d.error_type, d.error_code,
         -- Eski satırlarda `error_message` yok ama `response_json` var:
         -- geriye dönük okunabilirlik için oradan düşülür.
         coalesce(d.error_message, d.response_json->>'error'),
         d.stack_trace,
         d.session_id, d.device_id, d.platform, d.os_version,
         d.app_version, d.device_model,
         d.request_json, d.response_json
  from public.db_logs d
  where d.user_id = p_user_id
    and (not p_only_errors or d.is_error)
    and (p_source_like is null or d.source ilike p_source_like)
    and (p_since is null or d.ts >= p_since)
    and (p_session_id is null or d.session_id = p_session_id)
    and (p_device_id is null or d.device_id = p_device_id)
  order by d.ts desc
  limit least(coalesce(p_limit, 200), 1000);
end;
$$;

-- ── admin_session_timeline: aynı alanlar ────────────────────────────────────
drop function if exists public.admin_session_timeline(text,int);

create or replace function public.admin_session_timeline(
  p_session_id text,
  p_limit      int default 500
)
returns table (
  id            bigint,
  ts            timestamptz,
  requested_at  timestamptz,
  responded_at  timestamptz,
  onceki_bosluk_sn numeric,
  user_id       uuid,
  email         text,
  source        text,
  table_name    text,
  op            text,
  event_kind    text,
  duration_ms   integer,
  is_error      boolean,
  error_type    text,
  error_code    text,
  error_message text,
  stack_trace   text,
  request_json  jsonb,
  response_json jsonb
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    d.id, d.ts, d.requested_at, d.responded_at,
    round(extract(epoch from (
      d.ts - lag(d.ts) over (order by d.ts)
    ))::numeric, 1),
    d.user_id,
    -- E-posta log satırında DEĞİL: buradan, profiles join'i ile geliyor.
    p.email,
    d.source, d.table_name, d.op, d.event_kind,
    d.duration_ms, d.is_error,
    d.error_type, d.error_code,
    coalesce(d.error_message, d.response_json->>'error'),
    d.stack_trace,
    d.request_json, d.response_json
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.session_id = p_session_id
  order by d.ts
  limit least(coalesce(p_limit, 500), 2000);
end;
$$;

-- ── admin_error_clusters: sınıf + kod ile grupla ────────────────────────────
-- Asıl kazanç burada: bugün 'PostgrestException: new row violates RLS…'
-- metninin tamamı gruplama anahtarıydı, en ufak değişken (tablo adı, id)
-- kümeyi bölüyordu. Artık (tip, kod) sabit eksen; mesaj ikincil.
drop function if exists public.admin_error_clusters(int,int);

create or replace function public.admin_error_clusters(
  p_hours int default 24,
  p_limit int default 50
)
returns table (
  error_type      text,
  error_code      text,
  source          text,
  table_name      text,
  op              text,
  error_text      text,
  hits            bigint,
  affected_users  bigint,
  affected_devices bigint,
  surumler        text,
  first_seen      timestamptz,
  last_seen       timestamptz,
  p95_ms          integer,
  sample_request  jsonb,
  sample_stack    text,
  sample_log_id   bigint
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    coalesce(d.error_type, '(tipsiz)'),
    coalesce(d.error_code, '—'),
    d.source,
    d.table_name,
    d.op,
    left(coalesce(d.error_message, d.response_json->>'error', '(mesajsız)'), 120),
    count(*),
    count(distinct d.user_id),
    count(distinct d.device_id),
    -- Hangi sürümlerde görüldü: "yalnızca 1.1.4'te" tespiti tek bakışta.
    array_to_string((array_agg(distinct d.app_version)
      filter (where d.app_version is not null))[1:5], ', '),
    min(d.ts),
    max(d.ts),
    (percentile_disc(0.95) within group (order by d.duration_ms))::int,
    (array_agg(d.request_json order by d.ts desc))[1],
    (array_agg(d.stack_trace order by d.ts desc)
      filter (where d.stack_trace is not null))[1],
    -- Örnek satırın id'si: panelden tek tıkla tam kayda gidilsin.
    (array_agg(d.id order by d.ts desc))[1]
  from public.db_logs d
  where d.is_error
    and d.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)))
  group by
    coalesce(d.error_type, '(tipsiz)'),
    coalesce(d.error_code, '—'),
    d.source, d.table_name, d.op,
    left(coalesce(d.error_message, d.response_json->>'error', '(mesajsız)'), 120)
  order by count(*) desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- ── Tek log satırının TAMAMI ────────────────────────────────────────────────
-- Panelde bir hataya tıklandığında açılan kayıt. E-posta burada da
-- join'den gelir, satırdan değil.
create or replace function public.admin_log_detail(p_id bigint)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_out jsonb;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  select jsonb_build_object(
    'id',            d.id,
    'ts',            d.ts,
    'requested_at',  d.requested_at,
    'responded_at',  d.responded_at,
    'saat_farki_ms', case when d.requested_at is null then null
                          else (extract(epoch from (d.ts - d.requested_at)) * 1000)::bigint end,
    'duration_ms',   d.duration_ms,
    'user_id',       d.user_id,
    'email',         p.email,           -- join'den; log satırında yok
    'display_name',  p.display_name,
    'session_id',    d.session_id,
    'device_id',     d.device_id,
    'platform',      d.platform,
    'os_version',    d.os_version,
    'app_version',   d.app_version,
    'device_model',  d.device_model,
    'sdk',           d.sdk,
    'source',        d.source,
    'table_name',    d.table_name,
    'op',            d.op,
    'event_kind',    d.event_kind,
    'is_error',      d.is_error,
    'error_type',    d.error_type,
    'error_code',    d.error_code,
    'error_message', coalesce(d.error_message, d.response_json->>'error'),
    'stack_trace',   d.stack_trace,
    'request_json',  d.request_json,
    'response_json', d.response_json,
    -- Aynı seansın komşu olayları: hatanın öncesi/sonrası bağlamı.
    'komsular',      (select jsonb_agg(x order by x->>'ts') from (
                        select jsonb_build_object(
                          'id', n.id, 'ts', n.ts, 'source', n.source,
                          'table_name', n.table_name, 'is_error', n.is_error,
                          'error_type', n.error_type,
                          'duration_ms', n.duration_ms) as x
                        from public.db_logs n
                        where n.session_id is not null
                          and n.session_id = d.session_id
                          and n.ts between d.ts - interval '2 minutes'
                                       and d.ts + interval '2 minutes'
                          and n.id <> d.id
                        order by n.ts
                        limit 20) y)
  ) into v_out
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.id = p_id;

  return v_out;
end;
$$;

-- ── Kullanıcının push token'ları ────────────────────────────────────────────
-- "Push gitmiyor" şikâyetinin tek ekranlık cevabı. Token TAM gösterilir:
-- `user_push_tokens` zaten sunucuda duruyor, panel yeni bir sır üretmiyor —
-- yalnızca var olanı yöneticiye açıyor. (Log SATIRINA yazmak farklı şeydi:
-- orada token 30 gün boyunca her istekte çoğalırdı.)
-- Taze ortamda bu fonksiyon yoktur; canlida 0072'nin ILK surumu farkli
-- bir `returns table` ile kurulmustu (created_at vardi). Iki durumu da
-- karsilamak icin drop: `create or replace` donus tipini degistiremez (42P13).
drop function if exists public.admin_user_push_tokens(uuid);

create or replace function public.admin_user_push_tokens(p_user_id uuid)
returns table (
  token       text,
  platform    text,
  device_id   text,
  updated_at  timestamptz,
  yas_gun     integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  -- Şema notu (canlıdan doğrulandı 2026-09-22): tabloda `id` ve
  -- `created_at` YOK. 0000'deki taban tanım onları içeriyordu ama 0041
  -- `token`'ı birincil anahtar yaptı ve sütunlar sadeleşti. Bugünkü
  -- kolonlar: token, user_id, platform, updated_at, device_id.
  --
  -- `yas_gun` bayat token teşhisi için: FCM token'ı rotasyona uğrar,
  -- aylardır güncellenmemiş bir satır büyük olasılıkla ölü bir cihazdır
  -- ve "push gitmiyor" şikâyetinin sebebi olabilir.
  return query
  select t.token, t.platform, t.device_id, t.updated_at,
         extract(day from (now() - t.updated_at))::int
  from public.user_push_tokens t
  where t.user_id = p_user_id
  order by t.updated_at desc;
end;
$$;

-- ── GRANT / REVOKE ──────────────────────────────────────────────────────────
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_user_logs(uuid,int,boolean,text,timestamptz,text,text)',
    'public.admin_session_timeline(text,int)',
    'public.admin_error_clusters(int,int)',
    'public.admin_log_detail(bigint)',
    'public.admin_user_push_tokens(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ── Doğrulama (0070/0071 ile aynı sözleşme) ─────────────────────────────────
do $$
declare
  v_eksik text;
begin
  select string_agg(p.proname, ', ') into v_eksik
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'admin\_%'
    and not has_function_privilege('authenticated', p.oid, 'execute');
  if v_eksik is not null then
    raise exception 'admin_* GRANT eksik: %', v_eksik;
  end if;
end $$;

do $$
declare
  v_kotu text;
begin
  select string_agg(p.proname, ', ') into v_kotu
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'admin\_%'
    and (not p.prosecdef or p.proconfig is null
         or not exists (select 1 from unnest(p.proconfig) c where c like 'search\_path=%'));
  if v_kotu is not null then
    raise exception 'admin_* security definer + search_path degil: %', v_kotu;
  end if;
end $$;

do $$
declare
  v_acik text;
begin
  select string_agg(p.proname, ', ') into v_acik
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.proname like 'admin\_%'
    and has_function_privilege('anon', p.oid, 'execute');
  if v_acik is not null then
    raise exception 'admin_* anon''a acik: %', v_acik;
  end if;
end $$;

-- E-posta kolonu db_logs'a EKLENMEDİĞİNİ doğrula.
-- Bu bir kod denetimi değil sözleşme denetimi: ileride biri "pratik olur"
-- diye eklerse migration burada durur ve gizlilik politikasıyla
-- (legal/tr + legal/en: "hassas alanlar maskelenir") çelişki sessizce
-- canlıya gitmez.
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'db_logs'
      and column_name in ('email', 'user_email', 'jwt', 'access_token', 'auth_token')
  ) then
    raise exception
      'db_logs''a PII kolonu eklenmis. Gizlilik politikasi (legal/tr, legal/en) e-posta ve token''in maskelendigini taahhut ediyor; e-posta panelde profiles join''i ile gosterilir.';
  end if;
end $$;

comment on function public.admin_log_detail(bigint) is
  'Admin paneli: tek log satırının tamamı + aynı seanstaki komşu olaylar. E-posta join''den gelir.';
comment on function public.admin_user_push_tokens(uuid) is
  'Admin paneli: kullanıcının FCM push token''ları (tam değer). "Push gitmiyor" teşhisi.';
comment on function public.admin_error_clusters(int,int) is
  'Admin paneli: hataları (tip, kod, kaynak, mesaj) ile grupla; etkilenen sürüm ve örnek stack taşır.';
