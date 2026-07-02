-- ============================================================
-- sandık — DB Security & CASCADE Audit
-- ============================================================
-- Çalıştırma: Supabase Dashboard → SQL Editor → bu dosyayı yapıştır → Run.
-- Read-only — hiçbir şey değiştirmez. 8 ayrı rapor üretir.
--
-- BEKLENEN SONUÇ:
--   1) Tüm user_id FK'leri ON DELETE CASCADE veya SET NULL olmalı
--   2) RLS her public tabloda enabled olmalı
--   3) Her tablo için en az 1 SELECT politikası olmalı
--   4) Servis-role bypass dışında "anon" rolüne aşırı yetki olmamalı
--   5) Trigger'lar SECURITY DEFINER ise search_path explicit olmalı
--   6) "force_rls" disclaimer_acceptances için ON olmalı (silme yasağı)
--   7) Backup retention ayarları (Supabase Dashboard'tan ayrıca kontrol)
--   8) SECURITY DEFINER fonksiyonlarının sayısı minimum

-- ─────────────────────────────────────────────────────────────────
-- 1. Tüm user_id Foreign Key'leri için DELETE rule
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 1) FOREIGN KEY DELETE RULES (auth.users referansları) ===' AS rapor;

SELECT
    tc.table_schema,
    tc.table_name,
    kcu.column_name,
    ccu.table_schema  AS foreign_table_schema,
    ccu.table_name    AS foreign_table_name,
    ccu.column_name   AS foreign_column,
    rc.delete_rule,
    CASE
        WHEN rc.delete_rule IN ('CASCADE', 'SET NULL') THEN '✓ OK'
        ELSE '⚠️ INCELE — hesap silme bu satırları temizleyemez'
    END AS durum
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
   AND tc.table_schema = kcu.table_schema
JOIN information_schema.constraint_column_usage ccu
    ON ccu.constraint_name = tc.constraint_name
   AND ccu.table_schema = tc.table_schema
JOIN information_schema.referential_constraints rc
    ON tc.constraint_name = rc.constraint_name
   AND tc.table_schema = rc.constraint_schema
WHERE tc.constraint_type = 'FOREIGN KEY'
  AND ccu.table_schema = 'auth'
  AND ccu.table_name = 'users'
ORDER BY tc.table_name, kcu.column_name;

-- ─────────────────────────────────────────────────────────────────
-- 2. RLS aktif mi her public tabloda
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 2) ROW LEVEL SECURITY (RLS) ETKİN Mİ ===' AS rapor;

SELECT
    schemaname,
    tablename,
    CASE
        WHEN rowsecurity THEN '✓ RLS açık'
        ELSE '🔴 KRİTİK — RLS kapalı, yetkisiz erişim mümkün'
    END AS rls_durum,
    CASE
        WHEN forcerowsecurity THEN '✓ force_rls'
        ELSE '— (servis-role bypass eder)'
    END AS force_rls
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY tablename;

-- ─────────────────────────────────────────────────────────────────
-- 3. Her tablonun politikaları
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 3) RLS POLİTİKALARI ===' AS rapor;

SELECT
    schemaname,
    tablename,
    policyname,
    cmd       AS operation,
    roles,
    qual      AS using_expression,
    with_check
FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, cmd, policyname;

-- ─────────────────────────────────────────────────────────────────
-- 4. Politikası olmayan tablolar (RLS açıksa hiçbir şey okunamaz!)
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 4) POLİTİKASI OLMAYAN TABLOLAR ===' AS rapor;

SELECT
    t.schemaname,
    t.tablename,
    t.rowsecurity,
    CASE
        WHEN t.rowsecurity AND NOT EXISTS (
            SELECT 1 FROM pg_policies p
            WHERE p.schemaname = t.schemaname AND p.tablename = t.tablename
        ) THEN '⚠️ RLS açık ama policy yok — yalnızca service-role okur (kasıtlıysa OK)'
        WHEN NOT t.rowsecurity THEN '🔴 RLS KAPALI'
        ELSE '✓ politika tanımlı'
    END AS durum
FROM pg_tables t
WHERE t.schemaname = 'public'
ORDER BY t.tablename;

-- ─────────────────────────────────────────────────────────────────
-- 5. anon rolüne verilmiş yetkilerine bakış
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 5) ANON ROLÜNE TABLO YETKİLERİ ===' AS rapor;

SELECT
    grantee,
    table_schema,
    table_name,
    privilege_type
FROM information_schema.role_table_grants
WHERE table_schema = 'public'
  AND grantee IN ('anon', 'authenticated')
ORDER BY grantee, table_name, privilege_type;

-- ─────────────────────────────────────────────────────────────────
-- 6. SECURITY DEFINER fonksiyonları (yetki yükseltme — dikkat)
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 6) SECURITY DEFINER FONKSİYONLAR ===' AS rapor;

SELECT
    n.nspname AS schema,
    p.proname AS function_name,
    pg_get_userbyid(p.proowner) AS owner,
    p.prosecdef AS is_security_definer,
    p.proconfig AS config_settings,
    CASE
        WHEN p.prosecdef AND (p.proconfig IS NULL OR
             NOT (array_to_string(p.proconfig, ',') LIKE '%search_path%'))
        THEN '⚠️ search_path explicit set edilmemiş (CVE riski)'
        WHEN p.prosecdef THEN '✓ search_path tanımlı'
        ELSE '— (SECURITY DEFINER değil)'
    END AS durum
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname IN ('public', 'auth')
  AND p.prosecdef = TRUE
ORDER BY n.nspname, p.proname;

-- ─────────────────────────────────────────────────────────────────
-- 7. disclaimer_acceptances — UPDATE/DELETE policy yokluğu doğrulaması
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 7) DISCLAIMER IMMUTABILITY (UPDATE/DELETE policy yok olmalı) ===' AS rapor;

SELECT
    policyname,
    cmd,
    CASE
        WHEN cmd IN ('UPDATE', 'DELETE') THEN
            '🔴 KRİTİK — disclaimer kaydı değiştirilebilir/silinebilir!'
        ELSE '✓ OK'
    END AS durum
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'disclaimer_acceptances';

-- Politika yoksa "no rows" döner — bu DA OK (default deny).
SELECT
    'Yukarıda UPDATE/DELETE komutu için satır YOKSA = immutability korunuyor.' AS not;

-- ─────────────────────────────────────────────────────────────────
-- 8. account_deletion_log — sadece service-role yazabilir mi?
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 8) ACCOUNT DELETION LOG GÜVENLİĞİ ===' AS rapor;

SELECT
    EXISTS (
        SELECT 1 FROM pg_tables
        WHERE schemaname = 'public' AND tablename = 'account_deletion_log'
    ) AS tablo_var,
    (SELECT rowsecurity FROM pg_tables
     WHERE schemaname = 'public' AND tablename = 'account_deletion_log') AS rls_etkin,
    (SELECT COUNT(*) FROM pg_policies
     WHERE schemaname = 'public' AND tablename = 'account_deletion_log') AS policy_sayisi,
    CASE
        WHEN NOT EXISTS (SELECT 1 FROM pg_tables
                         WHERE schemaname = 'public' AND tablename = 'account_deletion_log')
        THEN '⚠️ Migration uygulanmamış — supabase db push çalıştır'
        WHEN (SELECT rowsecurity FROM pg_tables
              WHERE schemaname = 'public' AND tablename = 'account_deletion_log') = FALSE
        THEN '🔴 KRİTİK — RLS kapalı'
        WHEN (SELECT COUNT(*) FROM pg_policies
              WHERE schemaname = 'public' AND tablename = 'account_deletion_log') > 0
        THEN '⚠️ Policy tanımlı — yalnızca service-role bypass etmeli'
        ELSE '✓ RLS açık, policy yok = sadece service-role erişimi'
    END AS durum;

-- ─────────────────────────────────────────────────────────────────
-- 9. Index sağlığı — sorgu performansı için kritik kolonlarda index var mı?
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 9) INDEX SAĞLIK KONTROLÜ ===' AS rapor;

SELECT
    schemaname,
    tablename,
    indexname,
    indexdef
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename IN (
    'assets', 'snapshots', 'partner_invites',
    'partnerships', 'user_push_tokens',
    'disclaimer_acceptances', 'db_logs', 'account_deletion_log'
  )
ORDER BY tablename, indexname;

-- ─────────────────────────────────────────────────────────────────
-- 10. Beklenmedik tablolar (şemada olmayanlar)
-- ─────────────────────────────────────────────────────────────────
SELECT
    '=== 10) PUBLIC ŞEMASINDA BEKLENMEDIK TABLOLAR ===' AS rapor;

SELECT tablename
FROM pg_tables
WHERE schemaname = 'public'
  AND tablename NOT IN (
    'profiles', 'assets', 'snapshots',
    'partner_invites', 'partnerships',
    'user_push_tokens', 'disclaimer_acceptances',
    'db_logs', 'account_deletion_log'
  )
ORDER BY tablename;

-- Boşsa: ✓ tüm tablolar şemada tanımlı.
-- Çıktıda satır varsa: bu tablo nereden geldi? Manuel mi oluşturuldu?

SELECT '=== AUDIT TAMAMLANDI ===' AS son;
