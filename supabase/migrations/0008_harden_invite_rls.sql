-- 0008_harden_invite_rls.sql
-- ============================================================
-- SECURITY: Davet akışındaki RLS açıklarını kapat (A1+A2+A3+C1).
-- Davet redeem + partnership creation Edge Function'a taşındı.
-- Bu migration RLS politikalarını sıkılaştırır.
-- ============================================================

-- ─────────────────────────────────────────────────────────────
-- A1: invites_redeem_select — filtresiz tüm aktif davetleri okutuyordu
-- Tüm authenticated kullanıcıların tüm aktif davetleri listelemesini
-- engellemek için bu policy'yi tamamen kaldırıyoruz.
-- Kod doğrulama artık `redeem-invite-code` Edge Function'ı üzerinden
-- service-role ile yapılır.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "invites_redeem_select" ON public.partner_invites;

-- ─────────────────────────────────────────────────────────────
-- A2: invites_claim_update — herhangi bir kullanıcının to_user_id=NULL
-- olan daveti UPDATE etmesine izin veriyordu. Service-role'e taşındı.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "invites_claim_update" ON public.partner_invites;

-- ─────────────────────────────────────────────────────────────
-- A3: partnerships_insert — tek tarafın eklemesine izin veriyordu.
-- Artık yalnızca `accept-invite` Edge Function (service-role) ekler.
-- Policy YOK = anon/authenticated INSERT edemez; service-role bypass eder.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "partnerships_insert" ON public.partnerships;

-- ─────────────────────────────────────────────────────────────
-- A2b: invites_target_update — to_user_id zaten set edilmiş davetlerin
-- güncellenmesi (accept/reject). Sadece davet sahibi yetkili olmalı,
-- ama mevcut policy "auth.uid() = to_user_id" diyor → davet hedefi
-- kendi statüsünü değiştirebiliyor (kasıtlı değil).
-- Artık accept/reject de Edge Function üzerinden yapılır.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "invites_target_update" ON public.partner_invites;

-- ─────────────────────────────────────────────────────────────
-- Kalan policy'ler:
--   invites_own_insert      — kullanıcı kendi davetini oluşturur ✓
--   invites_own_select      — kullanıcı kendi davetlerini görür ✓
--   invites_own_update      — kullanıcı kendi davetini günceller (örn. iptal) ✓
--   invites_target_select   — davet hedefi kendi gelen daveti görür ✓
-- ─────────────────────────────────────────────────────────────

-- ─────────────────────────────────────────────────────────────
-- A6: db_logs_insert — user_id check eksikti, log enjeksiyonu mümkündü.
-- ─────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "db_logs_insert" ON public.db_logs;
CREATE POLICY "db_logs_insert" ON public.db_logs
  FOR INSERT WITH CHECK (
    auth.uid() IS NOT NULL
    AND (user_id IS NULL OR user_id = auth.uid())
  );

-- ─────────────────────────────────────────────────────────────
-- C1: handle_new_user trigger — SECURITY DEFINER + search_path explicit.
-- pg_temp üzerinden privilege escalation saldırısına karşı koruma.
-- ─────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
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

-- ─────────────────────────────────────────────────────────────
-- C3: disclaimer_acceptances FORCE RLS — owner bypass'ı engelle
-- (yasal delil immutability garantisi)
-- ─────────────────────────────────────────────────────────────
ALTER TABLE public.disclaimer_acceptances FORCE ROW LEVEL SECURITY;

-- ─────────────────────────────────────────────────────────────
-- D1: assets CHECK constraint — negatif/sınırsız değer engeli
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_quantity_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_quantity_check
      CHECK (quantity >= 0 AND quantity < 1e15);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_purchase_price_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_purchase_price_check
      CHECK (purchase_price >= 0 AND purchase_price < 1e15);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'assets_current_price_check'
  ) THEN
    ALTER TABLE public.assets
      ADD CONSTRAINT assets_current_price_check
      CHECK (current_price >= 0 AND current_price < 1e15);
  END IF;
END $$;

-- ─────────────────────────────────────────────────────────────
-- D2: profiles.display_name length cap — push body ve UI taşmayı önle
-- ─────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'profiles_display_name_length_check'
  ) THEN
    ALTER TABLE public.profiles
      ADD CONSTRAINT profiles_display_name_length_check
      CHECK (char_length(display_name) BETWEEN 1 AND 60);
  END IF;
END $$;
