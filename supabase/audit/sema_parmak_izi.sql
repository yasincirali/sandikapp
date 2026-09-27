-- Şema parmak izi — Tokyo ile Frankfurt "birebir aynı" mı? (2026-09-28)
--
-- Kullanıcı kuralı: iki sunucu hep senkron gider. Migration defteri
-- (`supabase migration list`) yalnızca "hangi dosya koştu"yu söyler; elle
-- SQL Editor'dan yapılan değişikliği, yarım kalan repair'i, farklı sürümlü
-- eklentiyi göremez. Bu sorgu şemanın KENDİSİNİ özetler: iki projede aynı
-- satırları döndürmüyorsa sunucular ayrışmıştır.
--
-- Tek SELECT (Management API tek ifade kabul eder). Her satır:
--   tur | ad | ozet | tanim   — ozet = tanımın md5'i (eşitlik bundan
--   sorulur); tanim, fark çıkınca "neden" diye bakmak için (cron hariç).
--
-- BİLİNÇLİ OLARAK DIŞARIDA:
--   * Sütun SIRASI — anlam taşımaz ve tablo yeniden yazılmadan değişmez
--     (Tokyo'da profiles.created_at, kolon sonradan eklendiği için yerinde
--     değil). Sütunlar ada göre sıralanır.
--   * Veri, satır sayıları — iki sunucu aynı ŞEMAYI taşır, aynı veriyi değil
--     (geçişe kadar Frankfurt'ta yalnız pilot kopya var).
--   * Cron işlerinin `active` bayrağı — geçişe kadar Frankfurt'ta KAPALI
--     olmak ZORUNDA, yoksa iki sunucu aynı kullanıcıya iki push atar
--     (docs/SUPABASE_FRANKFURT_TASIMA.md). Bayrak ayrı satırda raporlanır
--     (`cron_aktif`), karşılaştırıcı onu ayrı listeler.
--   * Vault DEĞERLERİ — yalnız ADLAR. Değerler projeye özgü (project_url,
--     cron_gateway_jwt) ve log'a düşmemeli.
with
tablolar as (
  select 'tablo' tur, c.relname ad,
         (string_agg(a.attname || ':' || format_type(a.atttypid, a.atttypmod)
               || ':' || a.attnotnull::text
               || ':' || coalesce(pg_get_expr(d.adbin, d.adrelid), '')
               || ':' || a.attgenerated::text, ',' order by a.attname)
             || ':rls=' || c.relrowsecurity::text || ':force=' || c.relforcerowsecurity::text) tanim
  from pg_class c
  join pg_namespace n on n.oid = c.relnamespace
  join pg_attribute a on a.attrelid = c.oid and a.attnum > 0 and not a.attisdropped
  left join pg_attrdef d on d.adrelid = c.oid and d.adnum = a.attnum
  where n.nspname = 'public' and c.relkind in ('r', 'p', 'v', 'm')
  group by c.relname, c.relrowsecurity, c.relforcerowsecurity
),
kisitlar as (
  select 'kisit', conrelid::regclass::text || '.' || conname, pg_get_constraintdef(oid)
  from pg_constraint
  where connamespace = 'public'::regnamespace
),
indeksler as (
  select 'indeks', indexname, indexdef
  from pg_indexes where schemaname = 'public'
),
politikalar as (
  select 'politika', tablename || '.' || policyname,
         cmd || ':' || permissive || ':' || array_to_string(roles, ',')
             || ':' || coalesce(qual, '') || ':' || coalesce(with_check, '')
  from pg_policies where schemaname = 'public'
),
fonksiyonlar as (
  select 'fonksiyon', p.oid::regprocedure::text,
         pg_get_functiondef(p.oid) || E'
-- acl=' || coalesce(p.proacl::text, '')
  from pg_proc p
  where p.pronamespace = 'public'::regnamespace and p.prokind in ('f', 'p')
),
tetikleyiciler as (
  select 'tetikleyici', t.tgrelid::regclass::text || '.' || t.tgname, pg_get_triggerdef(t.oid)
  from pg_trigger t
  join pg_class c on c.oid = t.tgrelid
  join pg_namespace n on n.oid = c.relnamespace
  where not t.tgisinternal
    -- auth.users üstündeki profil tetikleyicisi de uygulamanın parçası.
    and (n.nspname = 'public' or (n.nspname = 'auth' and c.relname = 'users'))
),
yetkiler as (
  select 'yetki', table_name || ':' || grantee,
         string_agg(privilege_type, ',' order by privilege_type)
  from information_schema.role_table_grants
  where table_schema = 'public' and grantee in ('anon', 'authenticated', 'service_role')
  group by table_name, grantee
),
sutun_yetkileri as (
  select 'sutun_yetki', table_name || '.' || column_name || ':' || grantee,
         string_agg(privilege_type, ',' order by privilege_type)
  from information_schema.column_privileges
  where table_schema = 'public' and grantee in ('anon', 'authenticated')
  group by table_name, column_name, grantee
),
eklentiler as (
  select 'eklenti', extname, extname::text from pg_extension
),
olay_tetikleyicileri as (
  select 'olay_tetikleyici', evtname,
         evtevent || ':' || array_to_string(evttags, ',') || ':' || evtfoid::regproc::text || ':' || evtenabled::text
  from pg_event_trigger
  -- Supabase'in kendi platform tetikleyicileri (pgrst_*, issue_*) her
  -- projede aynı; yalnız bizim kurduklarımız (public fonksiyona bağlı).
  where evtfoid::regproc::text like 'public.%' or evtfoid::regproc::text not like '%.%'
),
cron_isleri as (
  select 'cron', jobname, schedule || ':' || command from cron.job
),
cron_aktif as (
  select 'cron_aktif', jobname, active::text from cron.job
),
vault_adlari as (
  select 'vault', name, name from vault.secrets
),
defter as (
  select 'migration', version, version from supabase_migrations.schema_migrations
)
, hepsi as (
select * from tablolar
union all select * from kisitlar
union all select * from indeksler
union all select * from politikalar
union all select * from fonksiyonlar
union all select * from tetikleyiciler
union all select * from yetkiler
union all select * from sutun_yetkileri
union all select * from eklentiler
union all select * from olay_tetikleyicileri
union all select * from cron_isleri
union all select * from cron_aktif
union all select * from vault_adlari
union all select * from defter
)
-- Tanım metni yalnız karşılaştırıcının "neden farklı" çıktısı için döner.
-- Cron komutu dönmez: komut satırı projeye özgü başlık/anahtar taşıyabilir
-- ve CI log'una düşer — yalnız md5'i.
-- Satır sonu (CRLF/LF) anlam taşımaz: Windows'tan push edilen gövdelerde
-- CR karakteri kalıyor ve aynı fonksiyon iki projede "farklı" görünüyordu.
select tur, ad, md5(replace(tanim, E'', '')) ozet,
       case when tur = 'cron' then null else replace(tanim, E'', '') end tanim
from hepsi
order by 1, 2
