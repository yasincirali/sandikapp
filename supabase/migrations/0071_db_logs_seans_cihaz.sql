-- 0071_db_logs_seans_cihaz.sql
-- ============================================================
-- `db_logs`: seans, cihaz ve yanıt zamanı.
--
-- ── Neden ───────────────────────────────────────────────────────────────────
-- Destek paneli (0070) "müşteri X hata alıyor" sorusunu cevaplıyor ama üç
-- soruya sessiz kalıyordu:
--
--   1. "Bu hata hangi OTURUMDA oldu?"  Aynı kullanıcının dün akşamki
--      denemesiyle bu sabahki denemesini ayıramıyorduk. `user_id + ts`
--      sıralaması bir seansın nerede başlayıp bittiğini söylemez; araya
--      giren 9 saatlik boşluk log'da görünmüyor.
--
--   2. "Hangi CİHAZDA / SÜRÜMDE oluyor?"  "Sadece iOS 1.1.4'te kırılıyor"
--      tespiti mümkün değildi. Kullanıcının iki telefonu varsa hangisinin
--      sorunlu olduğu da bilinmiyordu.
--
--   3. "İstek ne zaman ATILDI, yanıt ne zaman DÖNDÜ?"  Tabloda tek zaman
--      damgası (`ts`) ve `duration_ms` vardı. İkisinden yanıt zamanı
--      türetilebilir ama istemci saati ile sunucu saati ayrıştığında
--      (uçak modu, saat dilimi, cihaz saati yanlış) bu hesap sessizce
--      yanlış olur. Zaman ayrışması bizzat bir teşhis sinyalidir ve
--      türetilmiş bir alanda görünmez.
--
-- ── Bu migration NE YAPMAZ ──────────────────────────────────────────────────
-- İstemciye dokunmaz. Kolonlar `null` kabul eder; bugünkü uygulama sürümü
-- onları DOLDURMADAN yazmaya devam eder ve hiçbir şey kırılmaz. Alanlar
-- ancak `DbLogger` güncellenip yeni sürüm yayınlandıktan sonra dolmaya
-- başlar (kullanıcı kararı 2026-09-22: önce sunucu + panel, uygulama
-- ayrı turda). Panel bu ara dönemde "bilinmiyor" gösterir — TECHNICAL_DEBT.
--
-- ── Üretimde yazma kuralı değişiyor (kullanıcı kararı 2026-09-22) ───────────
-- Bugün `DbLogger._persistAsync` üretimde YALNIZCA hataları yazıyor. Karar:
-- gezinme olayları da yazılacak (ekran açılışı, auth akışları, oturum
-- başlangıcı), rutin fiyat/portföy çekmeleri yazılmayacak. `event_kind`
-- kolonu bu ayrımı TAŞIR ki panel "seans izi" ile "hata" ayrımını
-- sorgulayabilsin. İstemci tarafı henüz yazmıyor; kolon hazır bekliyor.
-- ============================================================

-- ── Yeni kolonlar ───────────────────────────────────────────────────────────
-- Hepsi nullable: eski sürümler doldurmadan yazmaya devam eder.
alter table public.db_logs
  -- Uygulama açılışından kapanışına kadar sabit kalan rastgele kimlik.
  -- auth oturumu DEĞİL: kullanıcı giriş yapmadan da bir seansı vardır
  -- (kayıt ekranında kırılan bir akış da izlenebilmeli) ve tek seans
  -- içinde hesap değişebilir (A çıkar, B girer — `user_id` değişir ama
  -- seans aynıdır; bkz. kullanıcı değişimi tuzakları).
  add column if not exists session_id text,

  -- Cihaz başına kalıcı, ANONİM kimlik. Donanım kimliğiyle ilişkisi yok.
  -- `remote_push_service`'teki `push_device_id`'den AYRI tutulur: o kimlik
  -- çıkışta siliniyor (auth_service.dart) çünkü push hedefleme amacı var.
  -- Log kimliği çıkışta silinMEZ, yoksa "aynı cihazda hesap değiştirince
  -- kırılıyor" gibi tam da izlemek istediğimiz senaryo görünmez olur.
  add column if not exists device_id text,

  -- 'ios' | 'android' | 'web' — teşhisin en sık ilk sorusu.
  add column if not exists platform text,

  -- İşletim sistemi sürümü, ör. '18.2' / '15'.
  add column if not exists os_version text,

  -- Uygulama sürümü + build, ör. '1.1.4+7'. "Hangi sürümde kırıldı"
  -- sorusunun tek cevabı; sürüm notu/rollout kararları buna bakar.
  add column if not exists app_version text,

  -- Cihaz modeli, ör. 'iPhone14,2'. Üretici/model ötesi detay YOK
  -- (kullanıcı kararı: donanım kimliği toplanmaz).
  add column if not exists device_model text,

  -- İsteğin ATILDIĞI an (istemci saati). `ts` ile aynı olması BEKLENİR
  -- ama ayrı tutulur: `ts` sunucuya yazılma anına kaydırılabilir,
  -- `requested_at` istemcinin gördüğü andır.
  add column if not exists requested_at timestamptz,

  -- Yanıtın DÖNDÜĞÜ an (istemci saati). `requested_at + duration_ms`
  -- ile tutarlı olmalı; tutarsızsa cihaz saati oynamış demektir.
  add column if not exists responded_at timestamptz,

  -- Olayın türü. Panel "seans izi" ile "hata"yı bununla ayırır:
  --   'db'        — Supabase tablo/RPC çağrısı (bugünkü davranış)
  --   'auth'      — giriş/kayıt/OTP/çıkış
  --   'screen'    — ekran açılışı (gezinme izi)
  --   'session'   — oturum başlangıcı/bitişi
  --   'lifecycle' — uygulama ön plana/arka plana geçti
  -- CHECK KOYULMADI: yeni bir tür eklemek istemci sürümü ile migration'ı
  -- birbirine kilitlerdi (eski sunucu + yeni istemci = sessiz INSERT
  -- hatası, yani log kaybı — teşhis aracının kendisi kör olur).
  add column if not exists event_kind text;

-- ── İndeksler ───────────────────────────────────────────────────────────────
-- Panelin gerçekten attığı sorgulara göre; spekülatif indeks yok.

-- "Bu seansta ne oldu" — seans zaman çizelgesi.
create index if not exists db_logs_session_idx
  on public.db_logs (session_id, ts desc)
  where session_id is not null;

-- "Bu cihazda ne oldu" — cihaz geçmişi, hesaptan bağımsız.
create index if not exists db_logs_device_idx
  on public.db_logs (device_id, ts desc)
  where device_id is not null;

-- "Şu sürümde hata var mı" — sürüm bazlı hata taraması.
create index if not exists db_logs_version_error_idx
  on public.db_logs (app_version, ts desc)
  where is_error;

-- ── Yorumlar (şema kendini anlatsın) ────────────────────────────────────────
comment on column public.db_logs.session_id is
  'Uygulama açılışından kapanışına sabit rastgele kimlik. Auth oturumu DEĞİL: giriş yapılmadan da vardır ve tek seansta hesap değişebilir.';
comment on column public.db_logs.device_id is
  'Cihaz başına kalıcı anonim kimlik. push_device_id''den AYRI: bu kimlik çıkışta silinmez, yoksa hesap değişimi senaryosu izlenemez.';
comment on column public.db_logs.requested_at is
  'İsteğin atıldığı an (istemci saati). ts sunucu yazımına kayabilir; bu alan istemcinin gördüğü andır.';
comment on column public.db_logs.responded_at is
  'Yanıtın döndüğü an (istemci saati). requested_at + duration_ms ile tutarsızsa cihaz saati oynamıştır.';
comment on column public.db_logs.event_kind is
  'db | auth | screen | session | lifecycle. CHECK yok: yeni tür istemci sürümünü migration''a kilitlemesin.';

-- ── 0070 RPC'lerini yeni kolonlarla güncelle ────────────────────────────────
--
-- `admin_user_logs`: `returns table`'a sütun eklemek `create or replace`
-- ile YAPILAMAZ (42P13) — `drop function` şarttır ve GRANT'ları götürür,
-- bu yüzden aşağıda yeniden veriliyor. (Bkz. PG dönüş tipi tuzağı.)
drop function if exists public.admin_user_logs(uuid,int,boolean,text,timestamptz);

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
         -- Cihaz saati sapması: istemcinin "istek attım" dediği an ile
         -- sunucunun satırı yazdığı an arasındaki fark. Büyük bir değer
         -- "kullanıcının telefonu saati şaşmış" demektir ve token süresi
         -- / OTP gibi zamana bağlı akışlarda ASIL sebep olabilir.
         case
           when d.requested_at is null then null
           else (extract(epoch from (d.ts - d.requested_at)) * 1000)::bigint
         end,
         d.source, d.table_name, d.op, d.event_kind,
         d.duration_ms, d.is_error,
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

-- ── Bir kullanıcının seansları ──────────────────────────────────────────────
-- Log satırlarını seansa toplar: "kaç kez açtı, her açılışta ne oldu".
-- `session_id` null olan (eski sürüm) satırlar TEK bir sentetik seansta
-- toplanır — kaybolmasınlar ama gerçek seanslarla da karışmasınlar.
create or replace function public.admin_user_sessions(
  p_user_id uuid,
  p_limit   int default 50
)
returns table (
  session_id   text,
  baslangic    timestamptz,
  bitis        timestamptz,
  sure_sn      numeric,
  olay         bigint,
  hata         bigint,
  ekran        bigint,
  device_id    text,
  platform     text,
  os_version   text,
  app_version  text,
  device_model text,
  ilk_kaynak   text,
  son_hata     text
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
    coalesce(d.session_id, '(seanssız — eski sürüm)'),
    min(d.ts),
    max(d.ts),
    round(extract(epoch from (max(d.ts) - min(d.ts)))::numeric, 1),
    count(*),
    count(*) filter (where d.is_error),
    count(*) filter (where d.event_kind = 'screen'),
    -- Tek seansta tek cihaz beklenir; yine de `max` ile tekilleştiriyoruz
    -- ki gruplama patlamasın.
    max(d.device_id),
    max(d.platform),
    max(d.os_version),
    max(d.app_version),
    max(d.device_model),
    (array_agg(d.source order by d.ts))[1],
    (array_agg(d.response_json->>'error' order by d.ts desc)
       filter (where d.is_error))[1]
  from public.db_logs d
  where d.user_id = p_user_id
  group by coalesce(d.session_id, '(seanssız — eski sürüm)')
  order by min(d.ts) desc
  limit least(coalesce(p_limit, 50), 200);
end;
$$;

-- ── Bir seansın tam zaman çizelgesi ─────────────────────────────────────────
-- Seçilen seansın her olayı, bir önceki olaydan kaç sn sonra olduğuyla
-- birlikte. "Kullanıcı 40 sn bekledikten sonra tekrar denedi" gibi
-- davranış ancak bu boşlukla okunur.
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
    p.email,
    d.source, d.table_name, d.op, d.event_kind,
    d.duration_ms, d.is_error,
    d.request_json, d.response_json
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.session_id = p_session_id
  order by d.ts
  limit least(coalesce(p_limit, 500), 2000);
end;
$$;

-- ── Cihaz envanteri ─────────────────────────────────────────────────────────
-- "Hangi cihazlar, hangi sürümler, nerede kırılıyor". Bir cihaz birden çok
-- kullanıcı görebilir (aynı telefonda hesap değişimi) — `kullanici` sayısı
-- bunu ortaya çıkarır ve push token devralma gibi sorunların ilk ipucudur.
create or replace function public.admin_devices(
  p_hours int  default 168,
  p_q     text default null,
  p_limit int  default 100
)
returns table (
  device_id    text,
  platform     text,
  os_version   text,
  app_version  text,
  device_model text,
  kullanici    bigint,
  emailler     text,
  seans        bigint,
  olay         bigint,
  hata         bigint,
  ilk_gorulme  timestamptz,
  son_gorulme  timestamptz
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 168), 720)));
  v_q     text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    d.device_id,
    max(d.platform),
    max(d.os_version),
    max(d.app_version),
    max(d.device_model),
    count(distinct d.user_id),
    -- Cihazı kullanan hesaplar. Destek sorusunda "bu telefonda kim var"
    -- doğrudan cevaplanmalı; beş isimden sonrası kırpılır.
    (array_to_string((array_agg(distinct p.email))[1:5], ', ')),
    count(distinct d.session_id),
    count(*),
    count(*) filter (where d.is_error),
    min(d.ts),
    max(d.ts)
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.device_id is not null
    and d.ts >= v_since
    and (v_q is null
         or d.device_id ilike '%' || v_q || '%'
         or d.app_version ilike '%' || v_q || '%'
         or d.platform ilike '%' || v_q || '%'
         or d.device_model ilike '%' || v_q || '%'
         or p.email ilike '%' || v_q || '%')
  group by d.device_id
  order by count(*) filter (where d.is_error) desc, max(d.ts) desc
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- ── Sürüm / platform kırılımı ───────────────────────────────────────────────
-- "Yeni sürümde hata arttı mı" sorusunun tek ekranlık cevabı.
create or replace function public.admin_version_health(
  p_hours int default 168
)
returns table (
  app_version  text,
  platform     text,
  os_version   text,
  cihaz        bigint,
  kullanici    bigint,
  olay         bigint,
  hata         bigint,
  hata_orani   numeric,
  p95_ms       integer,
  son_gorulme  timestamptz
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
    coalesce(d.app_version, '(bilinmiyor)'),
    coalesce(d.platform, '(bilinmiyor)'),
    coalesce(d.os_version, '(bilinmiyor)'),
    count(distinct d.device_id),
    count(distinct d.user_id),
    count(*),
    count(*) filter (where d.is_error),
    round(100.0 * count(*) filter (where d.is_error) / nullif(count(*), 0), 1),
    (percentile_disc(0.95) within group (order by d.duration_ms))::int,
    max(d.ts)
  from public.db_logs d
  where d.ts > now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 168), 720)))
  group by coalesce(d.app_version, '(bilinmiyor)'),
           coalesce(d.platform, '(bilinmiyor)'),
           coalesce(d.os_version, '(bilinmiyor)')
  order by count(*) filter (where d.is_error) desc, count(*) desc
  limit 200;
end;
$$;

-- ── Seans arama: kişiden bağımsız ───────────────────────────────────────────
-- Panelin "seans" sekmesi. E-posta/isim/cihaz/sürüm ile filtrelenebilir;
-- sorgu boşsa en son seanslar gelir.
create or replace function public.admin_sessions(
  p_q           text    default null,
  p_hours       int     default 24,
  p_only_errors boolean default false,
  p_limit       int     default 100
)
returns table (
  session_id   text,
  user_id      uuid,
  email        text,
  display_name text,
  baslangic    timestamptz,
  bitis        timestamptz,
  sure_sn      numeric,
  olay         bigint,
  hata         bigint,
  device_id    text,
  platform     text,
  app_version  text,
  son_hata     text
)
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_since timestamptz := now() - make_interval(hours => greatest(1, least(coalesce(p_hours, 24), 720)));
  v_q     text := nullif(btrim(coalesce(p_q, '')), '');
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select
    d.session_id,
    -- Tek seansta hesap değişebilir (A çıkar, B girer). Burada istenen
    -- "seansın SON sahibi". `max(uuid)` yok (Postgres'te uuid için max
    -- tanımlı değil) ve olsaydı da yanlış olurdu: bit sırasına göre en
    -- büyüğü verirdi, son gireni değil. Zaman sırasına göre son değer:
    (array_agg(d.user_id order by d.ts desc))[1],
    (array_agg(p.email order by d.ts desc) filter (where p.email is not null))[1],
    (array_agg(p.display_name order by d.ts desc) filter (where p.display_name is not null))[1],
    min(d.ts),
    max(d.ts),
    round(extract(epoch from (max(d.ts) - min(d.ts)))::numeric, 1),
    count(*),
    count(*) filter (where d.is_error),
    max(d.device_id),
    max(d.platform),
    max(d.app_version),
    (array_agg(d.response_json->>'error' order by d.ts desc)
       filter (where d.is_error))[1]
  from public.db_logs d
  left join public.profiles p on p.id = d.user_id
  where d.session_id is not null
    and d.ts >= v_since
    and (v_q is null
         or p.email ilike '%' || v_q || '%'
         or p.display_name ilike '%' || v_q || '%'
         or d.session_id ilike '%' || v_q || '%'
         or d.device_id ilike '%' || v_q || '%'
         or d.app_version ilike '%' || v_q || '%')
  group by d.session_id
  having (not p_only_errors or count(*) filter (where d.is_error) > 0)
  order by min(d.ts) desc
  limit least(coalesce(p_limit, 100), 500);
end;
$$;

-- ── 0070'teki admin_user_detail'e cihaz/seans özeti ekle ────────────────────
-- jsonb döndüğü için `create or replace` yeterli (42P13 riski yok).
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
    'partner_count',      (select count(*) from public.partnerships pa
                            where pa.active
                              and (pa.user_id_1 = p.id or pa.user_id_2 = p.id)),
    'log_24h',            (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.ts > now() - interval '24 hours'),
    'hata_24h',           (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.is_error and d.ts > now() - interval '24 hours'),
    'hata_7g',            (select count(*) from public.db_logs d
                            where d.user_id = p.id and d.is_error and d.ts > now() - interval '7 days'),
    -- 0071: seans ve cihaz özeti
    'seans_7g',           (select count(distinct d.session_id) from public.db_logs d
                            where d.user_id = p.id and d.session_id is not null
                              and d.ts > now() - interval '7 days'),
    'cihaz_sayisi',       (select count(distinct d.device_id) from public.db_logs d
                            where d.user_id = p.id and d.device_id is not null),
    'cihazlar',           (select jsonb_agg(x) from (
                            select d.device_id, max(d.platform) as platform,
                                   max(d.os_version) as os_version,
                                   max(d.app_version) as app_version,
                                   max(d.device_model) as device_model,
                                   max(d.ts) as son_gorulme,
                                   count(*) filter (where d.is_error) as hata
                            from public.db_logs d
                            where d.user_id = p.id and d.device_id is not null
                            group by d.device_id
                            order by max(d.ts) desc
                            limit 10) x),
    'son_hata',           (select jsonb_build_object('ts', d.ts, 'source', d.source,
                                    'table', d.table_name, 'error', d.response_json->>'error',
                                    'session_id', d.session_id, 'app_version', d.app_version)
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
-- `admin_user_logs` DROP edildiği için GRANT'ı da gitti; yenileri ile
-- birlikte tek yerden veriliyor.
do $$
declare
  f text;
begin
  foreach f in array array[
    'public.admin_user_logs(uuid,int,boolean,text,timestamptz,text,text)',
    'public.admin_user_sessions(uuid,int)',
    'public.admin_session_timeline(text,int)',
    'public.admin_devices(int,text,int)',
    'public.admin_version_health(int)',
    'public.admin_sessions(text,int,boolean,int)',
    'public.admin_user_detail(uuid)'
  ] loop
    execute format('revoke all on function %s from public, anon', f);
    execute format('grant execute on function %s to authenticated', f);
  end loop;
end $$;

-- ── Doğrulama (0070 ile aynı sözleşme) ──────────────────────────────────────
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

-- anon hiçbirini çağıramamalı: GRANT bloğu yanlışlıkla genişlerse yakala.
do $$
declare
  v_acik text;
begin
  select string_agg(p.proname, ', ')
  into v_acik
  from pg_proc p
  join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public'
    and p.proname like 'admin\_%'
    and has_function_privilege('anon', p.oid, 'execute');

  if v_acik is not null then
    raise exception 'admin_* fonksiyonlari anon''a acik: %', v_acik;
  end if;
end $$;

comment on function public.admin_user_sessions(uuid,int) is
  'Admin paneli: bir kullanıcının seansları (açılıştan kapanışa), cihaz ve sürümüyle.';
comment on function public.admin_session_timeline(text,int) is
  'Admin paneli: tek seansın olay çizelgesi + olaylar arası boşluk.';
comment on function public.admin_devices(int,text,int) is
  'Admin paneli: cihaz envanteri. kullanici>1 = aynı cihazda hesap değişimi.';
comment on function public.admin_version_health(int) is
  'Admin paneli: sürüm/platform bazlı hata oranı — "yeni sürümde arttı mı".';
comment on function public.admin_sessions(text,int,boolean,int) is
  'Admin paneli: kişiden bağımsız seans araması (e-posta/cihaz/sürüm ile filtrelenir).';
