# Demo Portföy — mağaza ekran görüntüleri için

`SCREENSHOT_PLAN.md` görsel #1'in kurulum kriterlerine göre hazırlandı:
karışık türler, **artıda** ama abartısız, en az bir varlık zararda.

Fiyatlar **16.09.2026'da emülatördeki canlı fiyatlardan** okundu — uydurma
değil, uygulamanın kendi kaynağından (`price_service`/`tefas_service`).

## Kompozisyon

| Varlık | Tür | Adet | Alış | Güncel | Değer | K/Z | % |
|---|---|---|---|---|---|---|---|
| Çeyrek Altın | Altın | 14 | 8.950,00 | 10.827,72 | 151.588 | +26.288 | +21,0 |
| DLY | Fon | 28.000 | 5,42 | 6,2350 | 174.580 | +22.820 | +15,0 |
| KCHOL | Hisse | 500 | 185,00 | 206,10 | 103.050 | +10.550 | +11,4 |
| ABD Doları | Döviz | 2.800 | 44,80 | 48,65 | 136.220 | +10.780 | +8,6 |
| SAHOL | Hisse | 900 | 93,50 | 86,00 | 77.400 | **−6.750** | **−8,0** |
| AFT | Fon | 55.000 | 0,92 | 0,9813 | 53.970 | +3.370 | +6,7 |
| **TOPLAM** | | | | | **696.809** | **+67.059** | **+10,65** |

### Neden bu sayılar

- **+%10,65 toplam** — plan %8–15 diyor; alt uçta kalmak zayıf, üst uç
  şüpheli durur. Ortası inandırıcı.
- **SAHOL −%8** — plan "en az bir varlık zararda" istiyor. Her şeyin yeşil
  olduğu bir kare sahte görünür ve mağaza incelemesinde de risk.
- **Tür dağılımı dengeli** (Fon %32,8 · Hisse %25,9 · Altın %21,8 ·
  Döviz %19,5) — pasta grafiği hiçbir dilim %35'i geçmediği için okunaklı.
- **Alış fiyatları yuvarlak** (8.950 / 5,42 / 185,00) — elle girilmiş gibi
  durur. Ondalıklı "rastgele" sayılar veri tabanından dökülmüş izlenimi
  verir.
- **Alım tarihleri dağıtık** (Kasım 2025 – Nisan 2026) — grafik #2 için
  gerekli: plan "en az 6 aylık veri, dalgalı çizgi" istiyor.

## Nasıl yüklenir

CSV iki emülatörün de `/sdcard/Download/` klasöründe:

```
adb -s emulator-5554 push store_listing/demo_portfoy.csv /sdcard/Download/
```

Uygulamada: **Varlık ekle → CSV içe aktar → demo_portfoy.csv**

Format `sembol;adet;fiyat;tarih` (Türkçe ondalık virgül, tarih gg.aa.yyyy).
`CsvImportService.parse` ile doğrulandı: 6 satır, 0 hata, türler doğru
(ALTIN_CEYREK→altın, DLY/AFT→fon, KCHOL/SAHOL→hisse, USD→döviz).

> `CEYREK` yazmayın — `inferType` onu 6 harfli BIST kodu sanıp hisse yapar.
> `ALTIN_CEYREK` gerekli.

## Görsel #1 için son kontrol

- [ ] Bakiye gizleme **kapalı** (göz ikonu açık)
- [ ] Liste "Varlıklarım" segmentinde (Takip Listesi değil)
- [ ] Reel getiri rozeti görünüyor (enflasyonu geçmiş olmalı)
- [ ] Alt menüdeki **+** butonu karede
