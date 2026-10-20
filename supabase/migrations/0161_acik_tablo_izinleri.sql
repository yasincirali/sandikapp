-- 0161 — `public`'te yeni tablo/dizi için otomatik GRANT kapanır (2026-10-20)
-- ============================================================
--
-- Supabase 30 Ekim 2026'da var olan projelerde `public`'e yeni yaratılan
-- tablolara anon / authenticated / service_role için otomatik
-- select/insert/update/delete (dizilerde usage/select) vermeyi bırakıyor.
-- Var olan tablolar izinlerini korur; bu migration onlara dokunmaz.
--
-- Bu dosya aynı kuralı canlıda (iki sunucuda) ve taze yığında BİR KEZ, aynı
-- yerde kurar ki üç ortam aynı davransın:
--   · Canlı: Supabase'in 30 Ekim'de koşacağı revoke'un aynısı; önce gelirse
--     yalnızca bundan SONRA yaratılan tabloları etkiler. Revoke idempotent,
--     Supabase sonra tekrar koşsa da sonuç aynı.
--   · Taze yığın: 0000 eski varsayılanı geri kurmuştu (0001–0160 o izinlere
--     dayanıyor); burada kapanır. Böylece 0162+ bir migration açık GRANT
--     yazmazsa CI yığınında da "permission denied" görülür, canlıda ilk kez
--     değil. Statik kilit: `test/tablo_izinleri_test.dart`.
--
-- Kural (CLAUDE.md "Sunucu"): her yeni `public` tablosu, onu yaratan
-- migration'da hangi rolün ne yapacağını AÇIKÇA yazar. anon'a yalnız gerçekten
-- giriş öncesi okunan tabloda (ör. `yasal_metinler`) izin verilir; sunucu-içi
-- tabloda yalnız service_role. RLS yine ayrıca açılır.

alter default privileges for role postgres in schema public
  revoke select, insert, update, delete on tables from anon, authenticated, service_role;
alter default privileges for role postgres in schema public
  revoke usage, select on sequences from anon, authenticated, service_role;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
declare
  kalan text;
begin
  select string_agg(defaclobjtype::text || ':' || defaclacl::text, ' ')
    into kalan
    from pg_default_acl d
    join pg_namespace n on n.oid = d.defaclnamespace
   where n.nspname = 'public'
     and d.defaclrole = 'postgres'::regrole
     and d.defaclobjtype in ('r', 'S')
     and exists (
       select 1 from aclexplode(d.defaclacl) a
        where a.grantee in ('anon'::regrole, 'authenticated'::regrole, 'service_role'::regrole)
          and (a.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
               and d.defaclobjtype = 'r'
               or a.privilege_type in ('SELECT', 'USAGE') and d.defaclobjtype = 'S')
     );
  if kalan is not null then
    raise exception 'public varsayilan izinleri hala acik: %', kalan;
  end if;
end $$;
