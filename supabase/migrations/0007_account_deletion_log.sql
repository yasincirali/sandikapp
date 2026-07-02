-- 0007_account_deletion_log.sql
-- Hesap silme akışı için anonim kayıt tablosu.
-- KVKK Madde 12 (kanıt) + Madde 11 (silme hakkı) + TBK Madde 146 (zamanaşımı).
--
-- PII içermez: user_id_hash SHA-256'dır (geri çevrilemez),
-- email yalnızca domain kısmı tutulur.

CREATE TABLE IF NOT EXISTS public.account_deletion_log (
    id            BIGSERIAL PRIMARY KEY,
    deleted_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id_hash  TEXT NOT NULL,
    email_domain  TEXT,
    reason        TEXT NOT NULL DEFAULT 'user_request'
                  CHECK (reason IN (
                    'user_request',
                    'admin_action',
                    'inactive',
                    'tos_violation'
                  )),
    notes         TEXT
);

CREATE INDEX IF NOT EXISTS idx_deletion_log_deleted_at
  ON public.account_deletion_log(deleted_at);

-- RLS — yalnızca service-role yazabilir/okuyabilir.
-- (Politika tanımlanmadığı için authenticated/anon erişemez;
--  service-role her durumda RLS'i bypass eder.)
ALTER TABLE public.account_deletion_log ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE public.account_deletion_log IS
  'Anonim hesap silme kayıtları. KVKK kanıtı için 3 yıl saklanır. PII içermez.';

-- 3 yıl sonra otomatik temizleme için cron job (opsiyonel — pg_cron uzantısı gerekir).
-- SELECT cron.schedule(
--   'purge-deletion-log-3y',
--   '0 4 * * 0',  -- pazar 04:00
--   $$ DELETE FROM public.account_deletion_log WHERE deleted_at < NOW() - INTERVAL '3 years' $$
-- );
