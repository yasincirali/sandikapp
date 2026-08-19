-- Bildirim penceresini 24 saate açar (10–18 sabit aralığı kaldırılır).
--
-- ## Sorun
-- `window_start` ve `window_end` yalnızca 10–18 arası değer kabul ediyordu.
-- Bu sınır BIST seansından türetilmişti ama tercihe uygulanması iki şeyi
-- birden bozuyor:
--
--   * **7/24 varlıklar.** Kripto, ons altın ve döviz seans dışında da
--     hareket eder. Kullanıcı "gece de haber ver" diyemiyordu.
--   * **Test edilemezlik.** Mekanizmanın çalıştığını doğrulamak için
--     seans saatini beklemek gerekiyordu; akşam yapılan her deneme
--     `skipped_by_frequency: 18` ile sessizce düşüyordu.
--
-- Seans kavramı zaten AYRI bir yerde korunuyor: `analyze-signals` fiyat
-- verisi çekemediğinde sinyal üretmez (`symbols: 0`). Yani pencereyi açmak
-- "kapalı piyasada uydurma sinyal" riski yaratmaz — yalnızca kullanıcının
-- ne zaman haber almak istediğini kendi seçmesine izin verir.
--
-- ## Değişmeyenler
-- `window_start <= window_end` kuralı ve `notify_hours` değerlerinin
-- pencere içinde kalması zorunluluğu aynen duruyor; onlar mantıksal
-- tutarlılık kuralları, keyfi sınır değil.

alter table signal_preferences
  drop constraint if exists signal_preferences_window_start_check;

alter table signal_preferences
  drop constraint if exists signal_preferences_window_end_check;

alter table signal_preferences
  add constraint signal_preferences_window_start_check
  check (window_start >= 0 and window_start <= 23);

alter table signal_preferences
  add constraint signal_preferences_window_end_check
  check (window_end >= 0 and window_end <= 23);

comment on column signal_preferences.window_start is
  'Bildirim penceresi baslangici (0-23, Istanbul saati). Seans kavramindan '
  'AYRIDIR: kapali piyasada fiyat cekilemedigi icin sinyal zaten uretilmez.';

comment on column signal_preferences.window_end is
  'Bildirim penceresi bitisi (0-23, Istanbul saati).';

-- Doğrulama: yeni sınırlar gerçekten yürürlükte mi?
do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid = 'signal_preferences'::regclass
      and conname = 'signal_preferences_window_end_check'
      and pg_get_constraintdef(oid) like '%23%'
  ) then
    raise exception 'window_end kisiti 0-23 araligina genisletilemedi';
  end if;
end $$;
