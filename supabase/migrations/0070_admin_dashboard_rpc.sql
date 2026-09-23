-- 0070_admin_dashboard_rpc.sql
-- ============================================================
-- Admin destek paneli — okuma katmanı.
--
-- ── Neden ───────────────────────────────────────────────────────────────────
-- "Müşteri X hata alıyor" şikayeti geldiğinde bugün elde olan tek yol
-- Supabase Dashboard'da elle SQL yazmak. `db_logs` (0000) istemci
-- isteklerini yazıyor ama RLS politikası `db_logs_select_own` — yönetici
-- BAŞKASININ logunu göremiyor. `auth.audit_log_entries` (şifre denemesi,
-- OTP, token yenileme) ve `rate_limit_attempts` (0028, FORCE RLS + GRANT yok)
-- istemciden hiç okunamıyor.
--
-- Bu migration o üç kaynağı TEK bir admin okuma yüzeyine çıkarır. Yazma yok:
-- her fonksiyon `stable`, hiçbiri satır değiştirmez. Panel yalnızca teşhis
-- eder; müdahale (kilit açma, kullanıcı silme) ayrı ve bilinçli bir adımdır —
-- 0071'e bırakıldı değil, kasten dışarıda: yanlış tıklama ile canlı veri
-- bozulmasın.
--
-- ── Güvenlik sözleşmesi ─────────────────────────────────────────────────────
-- Her fonksiyon: `security definer` + sabit `search_path` + ilk satırda
-- `is_push_admin()` (0060, UUID tabanlı) kontrolü. GRANT `authenticated`a
-- verilir — ama admin olmayan bir authenticated kullanıcı çağırırsa
-- `raise exception 'Yetkisiz'` alır. GRANT ile RLS ayrı şeylerdir
-- (CLAUDE.md): burada RLS'yi security definer atlıyor, kapıyı
-- `is_push_admin()` tutuyor.
--
-- ── PII kararı ──────────────────────────────────────────────────────────────
-- Panel e-posta ve görünen adı AÇIK gösterir: amacı zaten "bu müşteriyi
-- bul". Ama `db_logs.response_json` istemcide `DbLogger.sanitize` ile
-- maskelenmiş geliyor (e-posta/UUID/JWT/IP), o maske korunur — panel ham
-- gövdeyi yeniden açmaz. `auth.audit_log_entries.payload` IP ve user-agent
-- taşır; bunlar açık verilir, çünkü "10 kere yanlış şifre" teşhisinde
-- denemenin NEREDEN geldiği sorunun kendisidir.
-- ============================================================

-- ── 1. Kullanıcı arama: e-posta veya isim ───────────────────────────────────
-- Şikayet e-posta ile de gelir ("ahmet@..."), isimle de ("Ahmet Bey aradı").
-- Tek fonksiyon ikisini de karşılar: `p_q` her iki alanda ILIKE aranır.
-- auth.users ile join: son giriş, e-posta onayı ve banlı mı bilgisi orada.
create or replace function public.admin_find_users(
  p_q     text,
  p_limit int default 25
)
returns table (
  user_id            uuid,
  email              text,
  display_name       text,
  created_at         timestamptz,
  last_sign_in_at    timestamptz,
  email_confirmed_at timestamptz,
  banned_until       timestamptz,
  provider           text,
  asset_count        bigint,
  error_count_7d     bigint
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  -- Boş sorgu tüm tabloyu dökmesin: en son kaydolanlar gelir.
  return query
  select
    p.id,
    p.email,
    p.display_name,
    p.created_at,
    u.last_sign_in_at,
    u.email_confirmed_at,
    u.banned_until,
    coalesce(u.raw_app_meta_data->>'provider', 'email') as provider,
    (select count(*) from public.assets a where a.user_id = p.id),
    (select count(*) from public.db_logs d
      where d.user_id = p.id and d.is_error and d.ts > now() - interval '7 days')
  from public.profiles p
  join auth.users u on u.id = p.id
  where p_q is null or btrim(p_q) = ''
     or p.email ilike '%' || btrim(p_q) || '%'
     or p.display_name ilike '%' || btrim(p_q) || '%'
     or p.id::text = btrim(p_q)
  order by u.last_sign_in_at desc nulls last, p.created_at desc
  limit least(coalesce(p_limit, 25), 200);
end;
$$;

-- ── 2. Bir kullanıcının istek günlüğü ───────────────────────────────────────
-- "Nerelere girmiş, hangi serviste hata almış" sorusunun cevabı.
-- `p_only_errors` ile gürültü kesilir; `p_source_like` ile tek servise
-- (ör. 'AuthService%') daralır.
create or replace function public.admin_user_logs(
  p_user_id     uuid,
  p_limit       int     default 200,
  p_only_errors boolean default false,
  p_source_like text    default null,
  p_since       timestamptz default null
)
returns table (
  id            bigint,
  ts            timestamptz,
  source        text,
  table_name    text,
  op            text,
  duration_ms   integer,
  is_error      boolean,
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
  select d.id, d.ts, d.source, d.table_name, d.op,
         d.duration_ms, d.is_error, d.request_json, d.response_json
  from public.db_logs d
  where d.user_id = p_user_id
    and (not p_only_errors or d.is_error)
    and (p_source_like is null or d.source ilike p_source_like)
    and (p_since is null or d.ts >= p_since)
  order by d.ts desc
  limit least(coalesce(p_limit, 200), 1000);
end;
$$;

-- ── 3. Hata kümeleri: "şu an ne bozuk?" ─────────────────────────────────────
-- Tek kullanıcıdan önce gelen soru. (source, table_name, hata metni)
-- üçlüsüne göre gruplar; aynı arıza 300 satır yerine tek satır olur.
-- `sample_response` ilk örneği taşır — tıklayınca detaya inilir.
create or replace function public.admin_error_clusters(
  p_hours int default 24,
  p_limit int default 50
)
returns table (
  source          text,
  table_name      text,
  op              text,
  error_text      text,
  hits            bigint,
  affected_users  bigint,
  first_seen      timestamptz,
  last_seen       timestamptz,
  p95_ms          integer,
  sample_request  jsonb
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
    d.source,
    d.table_name,
    d.op,
    -- Hata metni değişken kuyruk taşır (id, süre). İlk 120 karakter
    -- gruplamak için yeterli ayırt ediciliği veriyor.
    left(coalesce(d.response_json->>'error', '(mesajsız)'), 120) as error_text,
    count(*),
    count(distinct d.user_id),
    min(d.ts),
    max(d.ts),
    (percentile_disc(0.95) within group (order by d.duration_ms))::int,
    (array_agg(d.request_json order by d.ts desc))[1]
  from public.db_logs d
  where d.is_error
    and d.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)))
  group by d.source, d.table_name, d.op,
           left(coalesce(d.response_json->>'error', '(mesajsız)'), 120)
  order by count(*) desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- ── 4. Servis sağlığı: hangi endpoint yavaş/kırık ───────────────────────────
-- Hata sayısı tek başına yanıltır: 1000 çağrıda 5 hata ≠ 6 çağrıda 5 hata.
-- Oran ve gecikme birlikte verilir.
create or replace function public.admin_service_health(
  p_hours int default 24
)
returns table (
  source       text,
  table_name   text,
  calls        bigint,
  errors       bigint,
  error_rate   numeric,
  p50_ms       integer,
  p95_ms       integer,
  max_ms       integer,
  users        bigint,
  last_seen    timestamptz
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
    d.source,
    d.table_name,
    count(*),
    count(*) filter (where d.is_error),
    round(100.0 * count(*) filter (where d.is_error) / nullif(count(*), 0), 1),
    (percentile_disc(0.50) within group (order by d.duration_ms))::int,
    (percentile_disc(0.95) within group (order by d.duration_ms))::int,
    max(d.duration_ms),
    count(distinct d.user_id),
    max(d.ts)
  from public.db_logs d
  where d.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)))
  group by d.source, d.table_name
  order by count(*) filter (where d.is_error) desc, count(*) desc
  limit 300;
end;
$$;

-- ── 5. Auth olayları: OTP, şifre denemesi, token ────────────────────────────
-- İki kaynak birleşir çünkü ikisi de tek başına eksik:
--   · `auth.audit_log_entries` — GoTrue'nun kendi defteri. Başarılı giriş,
--     çıkış, şifre kurtarma isteği, kullanıcı güncelleme. IP ve user-agent
--     burada. Ama BAŞARISIZ şifre denemesi GoTrue sürümüne göre bazen
--     `login` action'ı olarak hiç yazılmaz.
--   · `public.db_logs` — istemci tarafı. `AuthService.login` başarısızsa
--     `is_error=true` satırı BURADA kesin var (release'te de: DbLogger
--     release'te yalnızca hataları yazar, ki bu tam da aradığımız şey).
-- Union ikisini tek zaman eksenine dizer; `kaynak` sütunu hangisinden
-- geldiğini söyler.
create or replace function public.admin_auth_events(
  p_q     text default null,   -- e-posta parçası veya user_id
  p_hours int  default 72,
  p_limit int  default 300
)
returns table (
  ts         timestamptz,
  kaynak     text,
  user_id    uuid,
  email      text,
  action     text,
  basarili   boolean,
  ip         text,
  user_agent text,
  detay      text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 72), 720)));
  v_q     text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  -- GoTrue defteri.
  --
  -- Şema notu (canlıdan doğrulandı, 2026-09-22): `payload` tipi `json`
  -- (jsonb DEĞİL) ve `ip_address` AYRI bir kolondur — payload içinde
  -- aranmaz. `actor_id` / `actor_username` GoTrue'nun yazdığı alanlardır;
  -- eksik olabilirler, bu yüzden hepsi `nullif` + `coalesce` ile korunuyor.
  -- `actor_id` geçerli bir UUID değilse cast patlardı: regex ön kontrolü
  -- bunu kapatır (CASE olmadan `::uuid` tüm sorguyu düşürür).
  select
    a.created_at,
    'gotrue'::text,
    u.id,
    coalesce(u.email::text, nullif(a.payload->>'actor_username', '')),
    coalesce(a.payload->>'action', '?')::text,
    -- GoTrue yalnızca gerçekleşen olayı yazar; bu defterde satır olması
    -- eylemin tamamlandığı anlamına gelir. Başarısızlık db_logs'tan gelir.
    true,
    a.ip_address::text,
    nullif(a.payload->>'traits', ''),
    left(a.payload::text, 400)
  from auth.audit_log_entries a
  left join auth.users u
    on a.payload->>'actor_id' ~ '^[0-9a-fA-F-]{36}$'
   and u.id = (a.payload->>'actor_id')::uuid
  where a.created_at >= v_since
    and (v_q is null
         or coalesce(a.payload->>'actor_username', '') ilike '%' || v_q || '%'
         or coalesce(a.payload->>'actor_id', '') = v_q
         or u.email ilike '%' || v_q || '%')

  union all

  -- İstemci defteri: auth/* tabloları AuthService çağrılarından gelir.
  select
    d.ts,
    'istemci'::text,
    d.user_id,
    p.email,
    d.table_name,               -- 'auth/sign-in-with-password', 'auth/verify-otp' …
    not d.is_error,
    null::text,
    null::text,
    left(coalesce(d.response_json->>'error', d.response_json::text), 400)
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.ts >= v_since
    and d.table_name like 'auth/%'
    and (v_q is null
         or p.email ilike '%' || v_q || '%'
         or d.user_id::text = v_q)

  order by 1 desc
  limit least(coalesce(p_limit, 300), 2000);
end;
$$;

-- ── 6. Şifre/OTP saldırı yüzeyi: aynı hedefe tekrar tekrar ──────────────────
-- "10 kere yanlış şifre" sorusunun doğrudan cevabı. Başarısız auth
-- denemelerini (kullanıcı, eylem) bazında sayar ve eşiği aşanları öne alır.
-- `ardisik_basarisiz` son başarılı girişten BU YANA kaç deneme olduğunu
-- söyler — toplam sayıdan daha anlamlı: dün 3, bugün 9 deneme yapan hesap
-- "12" değil "9" olarak görünür.
create or replace function public.admin_auth_abuse(
  p_hours     int default 24,
  p_min_hits  int default 3,
  p_limit     int default 100
)
returns table (
  user_id            uuid,
  email              text,
  display_name       text,
  action             text,
  basarisiz          bigint,
  ardisik_basarisiz  bigint,
  ilk_deneme         timestamptz,
  son_deneme         timestamptz,
  son_basarili       timestamptz,
  ornek_hata         text
)
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)));
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  with basarisiz as (
    select d.user_id, d.table_name as action, d.ts, d.response_json->>'error' as err
    from public.db_logs d
    where d.ts >= v_since and d.is_error and d.table_name like 'auth/%'
  ),
  son_ok as (
    select d.user_id, d.table_name as action, max(d.ts) as ok_ts
    from public.db_logs d
    where d.ts >= v_since and not d.is_error and d.table_name like 'auth/%'
    group by d.user_id, d.table_name
  )
  select
    b.user_id,
    p.email,
    p.display_name,
    b.action,
    count(*),
    count(*) filter (where s.ok_ts is null or b.ts > s.ok_ts),
    min(b.ts),
    max(b.ts),
    max(s.ok_ts),
    left((array_agg(b.err order by b.ts desc))[1], 160)
  from basarisiz b
  left join son_ok s on s.user_id is not distinct from b.user_id and s.action = b.action
  left join public.profiles p on p.id = b.user_id
  group by b.user_id, p.email, p.display_name, b.action
  having count(*) >= greatest(1, coalesce(p_min_hits, 3))
  order by count(*) filter (where s.ok_ts is null or b.ts > s.ok_ts) desc, count(*) desc
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- ── 7. Rate limit durumu ────────────────────────────────────────────────────
-- `rate_limit_attempts` (0028) FORCE RLS + GRANT yok; bugüne dek yalnızca
-- service-role okuyabiliyordu. Kilitli mi, ne zaman açılacak — panel bunu
-- göstermeden "davet kodum çalışmıyor" şikayeti teşhis edilemiyor.
-- `subject` genelde auth.users(id); e-postaya çevirmek için profiles'a
-- gevşek join (subject UUID değilse null kalır, hata vermez).
create or replace function public.admin_rate_limits(
  p_hours int default 24,
  p_limit int default 100
)
returns table (
  subject         text,
  email           text,
  display_name    text,
  scope           text,
  deneme          bigint,
  pencere_icinde  bigint,
  ilk_deneme      timestamptz,
  son_deneme      timestamptz,
  kilitli_mi      boolean,
  kalan_saniye    integer
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)));
  -- 0028/0030 varsayılanları: 5 deneme / 600 sn. Panel bu varsayımı
  -- gösterir; çağıran taraf farklı değer geçiyorsa gerçek kilit farklı
  -- olabilir — bu yüzden `kilitli_mi` bir TAHMİNdir, tek gerçek kaynak
  -- peek_rate_limit'tir (service-role).
  v_max    int := 5;
  v_window int := 600;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    r.subject,
    p.email,
    p.display_name,
    r.scope,
    count(*),
    count(*) filter (where r.attempted_at >= now() - make_interval(secs => v_window)),
    min(r.attempted_at),
    max(r.attempted_at),
    count(*) filter (where r.attempted_at >= now() - make_interval(secs => v_window)) >= v_max,
    greatest(0, ceil(extract(epoch from (
      min(r.attempted_at) filter (where r.attempted_at >= now() - make_interval(secs => v_window))
      + make_interval(secs => v_window) - now()
    )))::int)
  from public.rate_limit_attempts r
  left join public.profiles p
    on r.subject ~ '^[0-9a-fA-F-]{36}$' and p.id = r.subject::uuid
  where r.attempted_at >= v_since
  group by r.subject, p.email, p.display_name, r.scope
  order by count(*) filter (where r.attempted_at >= now() - make_interval(secs => v_window)) desc,
           max(r.attempted_at) desc
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- ── 8. Genel durum tablosu ──────────────────────────────────────────────────
-- Panelin ilk ekranı. Tek sorguda "bugün her şey yolunda mı".
create or replace function public.admin_overview(
  p_hours int default 24
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)));
  v_out jsonb;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  select jsonb_build_object(
    'pencere_saat',     extract(epoch from (now() - v_since)) / 3600,
    'toplam_kullanici', (select count(*) from public.profiles),
    'yeni_kullanici',   (select count(*) from public.profiles where created_at >= v_since),
    'aktif_kullanici',  (select count(distinct user_id) from public.db_logs
                          where ts >= v_since and user_id is not null),
    'istek',            (select count(*) from public.db_logs where ts >= v_since),
    'hata',             (select count(*) from public.db_logs where ts >= v_since and is_error),
    'hatali_kullanici', (select count(distinct user_id) from public.db_logs
                          where ts >= v_since and is_error and user_id is not null),
    'auth_hata',        (select count(*) from public.db_logs
                          where ts >= v_since and is_error and table_name like 'auth/%'),
    'kilitli_subject',  (select count(*) from (
                          select r.subject, r.scope
                          from public.rate_limit_attempts r
                          where r.attempted_at >= now() - interval '600 seconds'
                          group by r.subject, r.scope
                          having count(*) >= 5) k),
    'yavas_istek',      (select count(*) from public.db_logs
                          where ts >= v_since and duration_ms > 3000),
    'en_eski_log',      (select min(ts) from public.db_logs),
    'son_log',          (select max(ts) from public.db_logs)
  ) into v_out;

  return v_out;
end;
$$;

-- ── 9. Zaman serisi: hata eğrisi ────────────────────────────────────────────
-- "Ne zaman başladı" sorusu. Saatlik kova; grafik bunu çizer.
create or replace function public.admin_error_timeline(
  p_hours int default 48
)
returns table (
  kova     timestamptz,
  istek    bigint,
  hata     bigint,
  auth_hata bigint,
  kullanici bigint
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
    date_trunc('hour', d.ts),
    count(*),
    count(*) filter (where d.is_error),
    count(*) filter (where d.is_error and d.table_name like 'auth/%'),
    count(distinct d.user_id)
  from public.db_logs d
  where d.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 48), 720)))
  group by 1
  order by 1;
end;
$$;

-- ── 10. Kullanıcı künyesi ───────────────────────────────────────────────────
-- Tek kullanıcı seçilince sağ panelde açılan özet: hesabın hali, portföy
-- büyüklüğü, push token durumu, ortaklık, son hatası. Destek yanıtı
-- yazmadan önce bakılacak tek yer.
create or replace function public.admin_user_detail(p_user_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = public, auth
as $$
declare
  v_out jsonb;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  select jsonb_build_object(
    'user_id',            p.id,
    'email',              p.email,
    'display_name',       p.display_name,
    'created_at',         p.created_at,
    'onboarding',         p.onboarding_completed,
    'last_sign_in_at',    u.last_sign_in_at,
    'email_confirmed_at', u.email_confirmed_at,
    'banned_until',       u.banned_until,
    'provider',           coalesce(u.raw_app_meta_data->>'provider', 'email'),
    'asset_count',        (select count(*) from public.assets a where a.user_id = p.id),
    'push_tokens',        (select count(*) from public.user_push_tokens t where t.user_id = p.id),
    -- partnerships kolonları user_id_1 / user_id_2 (0000). `active` filtresi
    -- kasıtlı: kopmuş ortaklık destek sorusunda "ortağı var" diye okunmamalı.
    'partner_count',      (select count(*) from public.partnerships pa
                            where pa.active
                              and (pa.user_id_1 = p.id or pa.user_id_2 = p.id)),
    'log_24h',            (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.ts > now() - interval '24 hours'),
    'hata_24h',           (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.is_error and d.ts > now() - interval '24 hours'),
    'hata_7g',            (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.is_error and d.ts > now() - interval '7 days'),
    'son_hata',           (select jsonb_build_object('ts', d.ts, 'source', d.source,
                                    'table', d.table_name, 'error', d.response_json->>'error')
                            from public.db_logs d
                            where d.user_id = p.id and d.is_error
                            order by d.ts desc limit 1),
    'son_gorulme',        (select max(d.ts) from public.db_logs d where d.user_id = p.id)
  ) into v_out
  from public.profiles p
  join auth.users u on u.id = p.id
  where p.id = p_user_id;

  return v_out;
end;
$$;

-- ── GRANT / REVOKE ──────────────────────────────────────────────────────────
-- anon hiçbirini çağıramaz. authenticated çağırabilir ama gövdedeki
-- is_push_admin() duvarına çarpar — GRANT yetki değil, sadece kapı.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_find_users(text,int)',
    'public.admin_user_logs(uuid,int,boolean,text,timestamptz)',
    'public.admin_error_clusters(int,int)',
    'public.admin_service_health(int)',
    'public.admin_auth_events(text,int,int)',
    'public.admin_auth_abuse(int,int,int)',
    'public.admin_rate_limits(int,int)',
    'public.admin_overview(int)',
    'public.admin_error_timeline(int)',
    'public.admin_user_detail(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ── Doğrulama: GRANT eksikse migration burada patlasın ──────────────────────
-- CLAUDE.md kuralı: "eksikse raise exception ile doğrula" (0036/0042/0043).
do $$
declare
  v_eksik text;
begin
  select string_agg(p.proname, ', ')
  into v_eksik
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'admin\_%'
    and not has_function_privilege('authenticated', p.oid, 'execute');

  if v_eksik is not null then
    raise exception 'admin_* fonksiyonlarinda GRANT eksik: %', v_eksik;
  end if;
end $$;

-- Her admin fonksiyonunun gerçekten security definer + sabit search_path
-- olduğunu doğrula: biri unutulursa RLS sessizce kapıyı açar.
do $$
declare
  v_kotu text;
begin
  select string_agg(p.proname, ', ')
  into v_kotu
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'admin\_%'
    and (not p.prosecdef or p.proconfig is null
         or not exists (select 1 from unnest(p.proconfig) c where c like 'search\_path=%'));

  if v_kotu is not null then
    raise exception 'admin_* fonksiyonlari security definer + search_path degil: %', v_kotu;
  end if;
end $$;

comment on function public.admin_find_users(text,int) is
  'Admin paneli: e-posta / isim / uuid ile kullanıcı arama. is_push_admin() zorunlu.';
comment on function public.admin_user_logs(uuid,int,boolean,text,timestamptz) is
  'Admin paneli: bir kullanıcının db_logs geçmişi (RLS db_logs_select_own bunu engeller, bu fonksiyon definer ile açar).';
comment on function public.admin_error_clusters(int,int) is
  'Admin paneli: hataları (source, table, mesaj) bazında grupla — "şu an ne bozuk".';
comment on function public.admin_service_health(int) is
  'Admin paneli: endpoint bazında çağrı/hata oranı ve p50/p95 gecikme.';
comment on function public.admin_auth_events(text,int,int) is
  'Admin paneli: auth.audit_log_entries + istemci auth/* logları tek zaman ekseninde.';
comment on function public.admin_auth_abuse(int,int,int) is
  'Admin paneli: ardışık başarısız şifre/OTP denemeleri — brute force tespiti.';
comment on function public.admin_rate_limits(int,int) is
  'Admin paneli: rate_limit_attempts özeti; kilitli_mi 5/600sn varsayımına dayalı TAHMİNdir.';
comment on function public.admin_overview(int) is
  'Admin paneli: tek sorguda genel durum kartları.';
comment on function public.admin_error_timeline(int) is
  'Admin paneli: saatlik istek/hata eğrisi — "ne zaman başladı".';
comment on function public.admin_user_detail(uuid) is
  'Admin paneli: tek kullanıcı künyesi (hesap, portföy, push, ortaklık, son hata).';
