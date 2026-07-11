-- ============================================================
-- PortfoyTakip - Tam Sifirlama + Yeniden Kurulum
-- Supabase Dashboard > SQL Editor'da calistirin
-- ============================================================

DROP TABLE IF EXISTS public.partnerships    CASCADE;
DROP TABLE IF EXISTS public.user_push_tokens CASCADE;
DROP TABLE IF EXISTS public.partner_invites CASCADE;
DROP TABLE IF EXISTS public.snapshots       CASCADE;
DROP TABLE IF EXISTS public.assets          CASCADE;
DROP TABLE IF EXISTS public.profiles        CASCADE;

DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

DELETE FROM auth.users;

CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE public.profiles (
  id            UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email         TEXT NOT NULL,
  display_name  TEXT NOT NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE public.assets (
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

CREATE INDEX assets_user_id_idx ON public.assets(user_id);

CREATE TABLE public.snapshots (
  id         BIGSERIAL PRIMARY KEY,
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  ts         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  data       JSONB NOT NULL
);

CREATE INDEX snapshots_user_ts_idx ON public.snapshots(user_id, ts);

CREATE TABLE public.partner_invites (
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

CREATE TABLE public.user_push_tokens (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token      TEXT NOT NULL UNIQUE,
  platform   TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX user_push_tokens_user_id_idx ON public.user_push_tokens(user_id);

CREATE TABLE public.partnerships (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id_1   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_id_2   UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  UNIQUE (user_id_1, user_id_2)
);

CREATE INDEX partnerships_user1_idx ON public.partnerships(user_id_1);
CREATE INDEX partnerships_user2_idx ON public.partnerships(user_id_2);

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

SELECT 'Kurulum tamamlandi. Tablolar ve RLS hazir.' AS durum;
