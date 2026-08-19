-- De-dup'a hafıza ekler: en son BİLDİRİLEN güven ve bildirim anı.
--
-- ## Neden
-- De-dup kuralı tek satırdı: `oncekiSinyal !== yeniSinyal`. Bu iki uçta
-- birden yanlış davranıyordu:
--
--   * **Kalıcı sessizlik.** Sinyal SAT'ta takılı kalırsa süresiz hiçbir
--     bildirim gitmez. 2026-08-09 → 08-18 arası tam bu yaşandı: dokuz gün
--     boyunca sinyaller aynıydı ve sistem "bozuk" göründü.
--   * **Zıplama (flapping).** Güven eşiğin hemen etrafındaysa
--     AL → NÖTR → AL → NÖTR salınır ve HER geçiş bildirim üretir.
--     Kullanıcı yarım saatte dört bildirim alır, içerik neredeyse aynıdır.
--
-- Ayrıca aynı sinyalin güveni %50'den %85'e çıkması YENİ BİLGİDİR ama
-- eski kural bunu sessizce yutuyordu.
--
-- ## Eklenen alanlar
-- `notified_at` — son GÖNDERİLEN bildirimin anı. `updated_at`'ten ayrıdır:
-- o satırın her yazılışında değişir (durum takibi), bu ise yalnızca gerçek
-- bir push çıktığında. İkisini karıştırmak cooldown'u anlamsız kılardı.
--
-- `confidence` — o bildirimde taşınan güven (0-100). Sonraki turda anlamlı
-- bir sıçrama olup olmadığını ölçmek için gerekir.
--
-- Mevcut satırlarda ikisi de NULL kalır; kod NULL'ı "bilinmiyor" sayıp
-- güvenli tarafa (gönder) düşer — sessiz kalmaktansa bir kez fazla
-- bildirmek yeğdir.

alter table signal_state
  add column if not exists notified_at timestamptz,
  add column if not exists confidence numeric;

comment on column signal_state.notified_at is
  'Son GONDERILEN bildirimin ani. `updated_at` satirin her yazilisinda '
  'degisir; bu yalnizca gercek bir push ciktiginda. Cooldown ve repeat '
  'interval bu sutundan hesaplanir.';

comment on column signal_state.confidence is
  'Son bildirimde tasinan guven (0-100). Ayni sinyalde anlamli sicrama '
  'olup olmadigini olcmek icin saklanir.';

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'signal_state' and column_name = 'notified_at'
  ) or not exists (
    select 1 from information_schema.columns
    where table_name = 'signal_state' and column_name = 'confidence'
  ) then
    raise exception 'signal_state de-dup sutunlari eklenemedi';
  end if;
end $$;
