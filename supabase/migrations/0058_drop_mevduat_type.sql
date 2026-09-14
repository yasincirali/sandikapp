-- 0058: Vadeli mevduat türü kaldırıldı (2026-09-14).
--
-- Neden: özellik hiç yayına çıkmadı (`deposits_enabled` her ortamda false),
-- ayrı bir form + istemci tarafı faiz motoru taşıyordu ve fiyat/sinyal/
-- tarihçe motorlarının her birinde "mevduat hariç" dalları biriktiriyordu.
-- İstemci enum'undan çıkarıldı; `AssetType.fromString` bilinmeyen türü
-- zaten 'diger'e düşürür. Sunucuda da aynı dönüşümü kalıcı yapıyoruz ki
-- edge function'lar (positions.ts, analyze-signals) ve istemci aynı veriyi
-- görsün. Satır SİLİNMEZ: kullanıcı test ortamında girdiği kaydı "Diğer"
-- altında görmeye ve elle silmeye devam eder.
--
-- Fiyat: mevduat satırlarında `current_price` birim değeri (1.xx) taşıyordu,
-- 'diger' için bu "elle girilen fiyat" anlamına gelir — tutar korunur.

update public.assets
   set type = 'diger',
       notes = case
                 when coalesce(notes, '') = '' then 'Eski vadeli mevduat kaydı'
                 else notes || ' · Eski vadeli mevduat kaydı'
               end
 where type = 'mevduat';

-- İzleme listesinde tür sütunu varsa aynı dönüşüm (tablo 0043'te).
do $$
begin
  if to_regclass('public.watchlist_items') is not null then
    update public.watchlist_items set type = 'diger' where type = 'mevduat';
  end if;
end $$;
