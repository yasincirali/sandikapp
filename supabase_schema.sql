-- ============================================================
-- PortfoyTakip - Supabase Schema + RLS
-- Supabase Dashboard > SQL Editor'da calistirin
-- ============================================================

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS public.profiles (
  id                    UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email                 TEXT NOT NULL,
  display_name          TEXT NOT NULL,
  onboarding_completed  BOOLEAN NOT NULL DEFAULT FALSE,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- Var olan profiles tablolarına idempotent kolon eklemesi (mevcut deploy için).
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS onboarding_completed BOOLEAN NOT NULL DEFAULT FALSE;

CREATE TABLE IF NOT EXISTS public.assets (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  name            TEXT NOT NULL,
  ticker          TEXT NOT NULL DEFAULT '',
  type            TEXT NOT NULL,
  sub_category    TEXT,
  unit_type       TEXT NOT NULL DEFAULT 'piece',
  quantity        DOUBLE PRECISION NOT NULL,
  purchase_price  DOUBLE PRECISION NOT NULL,
  currency        TEXT NOT NULL DEFAULT 'TRY',
  current_price   DOUBLE PRECISION NOT NULL,
  last_updated    TIMESTAMPTZ,
  added_date      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  notes           TEXT NOT NULL DEFAULT '',
  is_manual_price BOOLEAN NOT NULL DEFAULT FALSE,
  purchase_fx_rate DOUBLE PRECISION NOT NULL DEFAULT 1.0
);

CREATE INDEX IF NOT EXISTS assets_user_id_idx ON public.assets(user_id);

CREATE TABLE IF NOT EXISTS public.snapshots (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ts         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  data       JSONB NOT NULL
);

CREATE INDEX IF NOT EXISTS snapshots_user_ts_idx ON public.snapshots(user_id, ts);

CREATE TABLE IF NOT EXISTS public.partner_invites (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  from_user_id   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  to_user_id     UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  requester_name TEXT,
  code           TEXT NOT NULL UNIQUE,
  payload        TEXT NOT NULL,
  expires_at     TIMESTAMPTZ NOT NULL,
  used           BOOLEAN NOT NULL DEFAULT FALSE,
  status         TEXT NOT NULL DEFAULT 'pending'
);

CREATE TABLE IF NOT EXISTS public.user_push_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  platform   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS user_push_tokens_user_id_idx
  ON public.user_push_tokens(user_id);

CREATE TABLE IF NOT EXISTS public.partnerships (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_1   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id_2   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (user_id_1, user_id_2)
);

CREATE INDEX IF NOT EXISTS partnerships_user1_idx ON public.partnerships(user_id_1);
CREATE INDEX IF NOT EXISTS partnerships_user2_idx ON public.partnerships(user_id_2);

ALTER TABLE public.profiles        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assets          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.snapshots       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partner_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_push_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.partnerships    ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select_own" ON public.profiles
  FOR SELECT USING (auth.uid() = id);

CREATE POLICY "profiles_insert_own" ON public.profiles
  FOR INSERT WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_update_own" ON public.profiles
  FOR UPDATE USING (auth.uid() = id);

CREATE POLICY "profiles_select_partner" ON public.profiles
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.partnerships p
      WHERE (p.user_id_1 = auth.uid() AND p.user_id_2 = id)
         OR (p.user_id_2 = auth.uid() AND p.user_id_1 = id)
    )
  );

CREATE POLICY "assets_own" ON public.assets
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "assets_partner_read" ON public.assets
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.partnerships p
      WHERE p.active = TRUE
        AND (
          (p.user_id_1 = auth.uid() AND p.user_id_2 = user_id)
          OR
          (p.user_id_2 = auth.uid() AND p.user_id_1 = user_id)
        )
    )
  );

CREATE POLICY "snapshots_own" ON public.snapshots
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "invites_own_insert" ON public.partner_invites
  FOR INSERT WITH CHECK (auth.uid() = from_user_id);

CREATE POLICY "invites_own_select" ON public.partner_invites
  FOR SELECT USING (auth.uid() = from_user_id);

CREATE POLICY "invites_own_update" ON public.partner_invites
  FOR UPDATE USING (auth.uid() = from_user_id);

CREATE POLICY "invites_redeem_select" ON public.partner_invites
  FOR SELECT USING (
    auth.uid() IS NOT NULL
    AND used = FALSE
    AND expires_at > NOW()
  );

CREATE POLICY "invites_claim_update" ON public.partner_invites
  FOR UPDATE USING (
    auth.uid() IS NOT NULL
    AND to_user_id IS NULL
    AND used = FALSE
    AND expires_at > NOW()
  )
  WITH CHECK (
    auth.uid() = to_user_id
    AND status = 'pending'
  );

CREATE POLICY "invites_target_update" ON public.partner_invites
  FOR UPDATE USING (auth.uid() = to_user_id);

CREATE POLICY "invites_target_select" ON public.partner_invites
  FOR SELECT USING (auth.uid() = to_user_id);

CREATE POLICY "push_tokens_own_select" ON public.user_push_tokens
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "push_tokens_own_insert" ON public.user_push_tokens
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "push_tokens_own_update" ON public.user_push_tokens
  FOR UPDATE USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "push_tokens_own_delete" ON public.user_push_tokens
  FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "partnerships_select" ON public.partnerships
  FOR SELECT USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

CREATE POLICY "partnerships_insert" ON public.partnerships
  FOR INSERT WITH CHECK (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

CREATE POLICY "partnerships_update" ON public.partnerships
  FOR UPDATE USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

CREATE POLICY "partnerships_delete" ON public.partnerships
  FOR DELETE USING (auth.uid() = user_id_1 OR auth.uid() = user_id_2);

-- ── Disclaimer Acceptances ───────────────────────────────────────────────────
-- Yasal uyarı onay kaydı. Hukuki delil niteliği taşıdığı için:
--   • Satır güncelleme/silme yasak (RLS + tablo tasarımı)
--   • Her disclaimer versiyonu ayrı kayıt oluşturur
--   • Uygulama versiyonu, platform ve zaman dilimi saklanır

CREATE TABLE IF NOT EXISTS public.disclaimer_acceptances (
  id                  BIGSERIAL PRIMARY KEY,
  user_id             UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  accepted_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  disclaimer_version  TEXT NOT NULL,          -- Örn: "1.0"
  disclaimer_hash     TEXT NOT NULL,          -- SHA-256 (metin içeriği)
  app_version         TEXT NOT NULL,          -- Örn: "1.0.0+1"
  platform            TEXT NOT NULL,          -- "android" | "ios"
  device_model        TEXT,                   -- Cihaz modeli (opsiyonel)
  locale              TEXT,                   -- Kullanıcı dil ayarı
  UNIQUE (user_id, disclaimer_version)        -- Aynı versiyon için çift kayıt engeli
);

-- Zaman bazlı sorgular için index
CREATE INDEX IF NOT EXISTS disclaimer_acceptances_user_idx
  ON public.disclaimer_acceptances(user_id, accepted_at DESC);

ALTER TABLE public.disclaimer_acceptances ENABLE ROW LEVEL SECURITY;

-- Kullanıcı kendi onayını ekleyebilir
CREATE POLICY "disclaimer_insert_own" ON public.disclaimer_acceptances
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- Kullanıcı kendi onaylarını görebilir
CREATE POLICY "disclaimer_select_own" ON public.disclaimer_acceptances
  FOR SELECT USING (auth.uid() = user_id);

-- UPDATE ve DELETE kesinlikle yasak — policy tanımlanmıyor (default deny)

-- ── DB Logs ───────────────────────────────────────────────────────────────────
-- Uygulama tarafındaki tüm Supabase/DB istekleri buraya yazılır.
-- user_id nullable: oturum açılmadan gelen istekleri de yakalar (login, register).
-- 30 gün retention: eski kayıtlar otomatik silinir.

CREATE TABLE IF NOT EXISTS public.db_logs (
  id            BIGSERIAL PRIMARY KEY,
  user_id       UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ts            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  sdk           TEXT NOT NULL,
  source        TEXT NOT NULL,
  table_name    TEXT NOT NULL,
  op            TEXT NOT NULL,
  request_json  JSONB,
  response_json JSONB,
  duration_ms   INTEGER NOT NULL,
  is_error      BOOLEAN NOT NULL DEFAULT FALSE
);

CREATE INDEX IF NOT EXISTS db_logs_user_ts_idx ON public.db_logs(user_id, ts DESC);
CREATE INDEX IF NOT EXISTS db_logs_source_idx  ON public.db_logs(source);

ALTER TABLE public.db_logs ENABLE ROW LEVEL SECURITY;

-- Herhangi bir oturumlu kullanıcı log ekleyebilir
CREATE POLICY "db_logs_insert" ON public.db_logs
  FOR INSERT WITH CHECK (auth.uid() IS NOT NULL);

-- Sadece kendi loglarını okuyabilir
CREATE POLICY "db_logs_select_own" ON public.db_logs
  FOR SELECT USING (auth.uid() = user_id);

-- 30 gün retention: pg_cron varsa aktif edilebilir
-- SELECT cron.schedule('delete-old-db-logs', '0 3 * * *',
--   $$DELETE FROM public.db_logs WHERE ts < NOW() - INTERVAL '30 days'$$);

DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM pg_publication
    WHERE pubname = 'supabase_realtime'
  ) AND NOT EXISTS (
    SELECT 1
    FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'partner_invites'
  ) THEN
    EXECUTE 'ALTER PUBLICATION supabase_realtime ADD TABLE public.partner_invites';
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles (id, email, display_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'display_name', split_part(NEW.email, '@', 1))
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
