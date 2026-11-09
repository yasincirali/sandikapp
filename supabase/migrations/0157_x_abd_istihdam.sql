-- 0157 — SANDIK X hesabı: ABD istihdam gönderisi türü (2026-10-19)
--
-- ## Neden
-- yasin (19 Eki): "sadece fon giriş çıkış twitleri mi atmalı, altın petrol
-- abd enflasyon işsizlik bilgileri de paylaşılmalı". ABD işsizlik oranı ve
-- tarım dışı istihdam (BLS, kamu verisi) açıklandığı akşam ayrı gönderi
-- olur; tür listesine `abd_istihdam` eklenir. Altın/dolar sabah kartına,
-- Brent Cuma özetine satır olarak girer: yeni tür gerekmez. Etiketler metne
-- kodda eklenir, şema değişmez (metin ≤ 280 kuralı zaten var).
--
-- ## Eski sürümler / canlı kullanıcı
-- Yalnızca EKLER (izinli değer listesi genişler). Uygulama bu tabloya
-- dokunmaz; kullanıcı verisi yok → yasal metin değişmez. İki sunucu birlikte.

alter table public.x_gonderileri drop constraint if exists x_gonderileri_tur_check;
alter table public.x_gonderileri add constraint x_gonderileri_tur_check
  check (tur in ('fon_akisi', 'haftalik', 'tufe', 'abd_tufe', 'fed', 'fon_getiri', 'takvim', 'abd_istihdam'));
