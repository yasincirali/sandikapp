-- 0075 — Fiyat alarmında küçük birim fiyat (kripto)
-- ============================================================
--
-- 0046/0065 `numeric(18, 4)` seçmişti: TL cinsinden hisse, altın ve döviz
-- için 4 ondalık fazlasıyla yeterdi. Kripto (0074) bunu kırar: SHIB
-- ~0,0004 ₺, PEPE ~0,0003 ₺. 4 haneye yuvarlanan hedef ya 0 olur
-- (`check (target_price > 0)` reddeder) ya da %25'e varan sapmayla kayar;
-- "0,00043 olunca haber ver" alarmı 0,0004'te tetiklenirdi.
--
-- `numeric(28, 10)`: tam kısım yine 18 hane (BTC ~4 milyon ₺ rahat sığar),
-- ondalık 10 hane (en küçük coin'lerde bile 4+ anlamlı hane). İstemci
-- birim fiyatı zaten `double` tutar; kayıp yalnızca bu sütundaydı.
--
-- Genişletme mevcut değerleri DEĞİŞTİRMEZ (4 haneli her sayı 10 hanede
-- aynıdır). Tablolar küçük; tip değişikliğinin yeniden yazımı önemsiz.

alter table public.price_alerts
  alter column target_price type numeric(28, 10);

alter table public.price_alert_notifications
  alter column target_price    type numeric(28, 10),
  alter column triggered_price type numeric(28, 10);

do $$
begin
  if (select numeric_scale from information_schema.columns
       where table_schema = 'public' and table_name = 'price_alerts'
         and column_name = 'target_price') <> 10 then
    raise exception 'price_alerts.target_price hassasiyeti genisletilmedi';
  end if;
end $$;
