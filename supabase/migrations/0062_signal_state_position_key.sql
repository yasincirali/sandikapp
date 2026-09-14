-- ============================================================
-- 0062 — signal_state: lot id → pozisyon anahtarı
--
-- TECHNICAL_DEBT "signal_state hâlâ lot başına anahtarlı". 0025'ten beri
-- PK `(user_id, asset_id)` ve `asset_id` bir LOT id'siydi. analyze-signals
-- döngüyü pozisyona indirgemişti (`collapseLotsToPositions`) ama de-dup
-- hafızası temsilci lot'un id'sinde kalıyordu: temsilci yumuşak silinince
-- pozisyon yeni temsilciye geçer, hafıza sıfırlanır, kullanıcı o varlık
-- için bir kez fazladan push alırdı.
--
-- ## Ne değişti
-- `asset_id` sütunu ADINI korur, İÇERİĞİ artık pozisyon anahtarıdır:
--   pos:<tür>|<TICKER>      (ticker trim + upper; edge function `positionKeyOf`)
-- Sütun adı bilinçli olarak değiştirilmedi: `touch_signal_state(p_asset_id)`
-- imzası ve PK aynı kalır. Migration ile function deploy'u arasındaki
-- pencerede eski function lot id'siyle yazmaya devam eder; o satırlar yeni
-- function tarafından okunmaz ve en kötü sonuç bir kez fazladan bildirimdir
-- — bugünkü davranışla aynı. Eski function'ın yazdığı artıklar zararsız
-- kalır (yeni anahtar `pos:` önekiyle ayrışır).
--
-- ## Taşıma
-- Her eski satır `assets` üzerinden pozisyon anahtarına çevrilir. Aynı
-- pozisyonun birden çok lot satırı varsa EN SON bildirilen kazanır
-- (notified_at desc, sonra updated_at desc) — en taze hafıza, en az
-- fazladan bildirim. Yumuşak silinmiş lot'ların satırları da taşınır:
-- pozisyon hâlâ başka lot'larla yaşıyor olabilir. Ticker'sız lot'ların
-- satırları (sinyal üretemezler) ve `assets`'te artık bulunmayan id'ler
-- silinir.
-- ============================================================

-- 1) Yeni anahtarlı satırları üret ve YAZ (varsa ez: en tazesi kazanır).
WITH tasinan AS (
  SELECT DISTINCT ON (s.user_id, k.key)
    s.user_id,
    k.key AS asset_id,
    s.signal,
    s.updated_at,
    s.notified_at,
    s.confidence
  FROM public.signal_state s
  JOIN public.assets a ON a.id::text = s.asset_id
  CROSS JOIN LATERAL (
    SELECT 'pos:' || a.type || '|' || upper(btrim(a.ticker)) AS key
  ) k
  WHERE s.asset_id NOT LIKE 'pos:%'
    AND coalesce(btrim(a.ticker), '') <> ''
  ORDER BY s.user_id, k.key, s.notified_at DESC NULLS LAST, s.updated_at DESC
)
INSERT INTO public.signal_state
  (user_id, asset_id, signal, updated_at, notified_at, confidence)
SELECT user_id, asset_id, signal, updated_at, notified_at, confidence
FROM tasinan
ON CONFLICT (user_id, asset_id) DO UPDATE SET
  signal      = EXCLUDED.signal,
  updated_at  = EXCLUDED.updated_at,
  notified_at = EXCLUDED.notified_at,
  confidence  = coalesce(EXCLUDED.confidence, public.signal_state.confidence)
WHERE coalesce(EXCLUDED.notified_at, EXCLUDED.updated_at)
      >= coalesce(public.signal_state.notified_at, public.signal_state.updated_at);

-- 2) Eski (lot id'li) satırlar artık okunmuyor; sil.
DELETE FROM public.signal_state WHERE asset_id NOT LIKE 'pos:%';

COMMENT ON COLUMN public.signal_state.asset_id IS
  '0062''den beri POZİSYON anahtarı: pos:<tür>|<TICKER> (analyze-signals '
  'positionKeyOf). Sütun adı tarihî; lot id''si DEĞİL.';

-- 3) Doğrulama: taşıma sonrası lot id'li satır kalmamalı.
DO $$
DECLARE
  kalan int;
BEGIN
  SELECT count(*) INTO kalan
  FROM public.signal_state WHERE asset_id NOT LIKE 'pos:%';
  IF kalan <> 0 THEN
    RAISE EXCEPTION 'signal_state: % satır hâlâ lot anahtarlı', kalan;
  END IF;
END $$;
