-- 0049_partner_activity_push.sql
-- ============================================================
-- Ortak hareketi bildirimi tercihi.
--
-- ÜRÜN GEREKÇESİ: sosyal bağ, bireysel mekaniklerin hepsinden güçlü bir
-- tutundurma kaldıracıdır — uygulamayı silmek artık tek kişilik bir karar
-- değildir. Ortaklık özelliği rakiplerde yok.
--
-- MAHREMİYET: bu bildirim YENİ bir bilgi açmaz. Ortağın lot'ları zaten
-- karşı tarafta görünüyor (`allPartnerAssetsProvider`); burada yapılan,
-- zaten paylaşılmış olanı gündeme getirmek. Yine de ALICI tarafın kapatma
-- hakkı olmalı: bildirimi istemeyen kullanıcı, ortaklığı bozmak zorunda
-- kalmadan susturabilmeli.
--
-- Tercih `profiles`ta çünkü sunucu okuyor. Cihaz tercihleri
-- (SharedPreferences) edge function'dan görünmez.
-- ============================================================

alter table public.profiles
  add column if not exists partner_activity_push boolean not null default true;

comment on column public.profiles.partner_activity_push is
  'Ortagin portfoy hareketi gunluk brifingde anilsin mi. Alici tarafin '
  'tercihi; ortagin lot''lari zaten karsi tarafta gorunur.';
