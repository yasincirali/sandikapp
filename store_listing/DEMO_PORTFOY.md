# Demo Portföy — mağaza ekran görüntüleri için

`SCREENSHOT_PLAN.md` görsel #1 kriterleri: karışık türler, **artıda**,
en az bir varlık zararda.

Buna bir kriter daha eklendi (kullanıcı, 2026-09-16): portföy **enflasyonu
da geçmeli**. Ana ekrandaki reel getiri rozeti sandığın en ayırt edici
satırı; kırmızı bir rozetle ("enflasyonun 20 puan gerisindesin") mağaza
görseli yapılmaz.

Fiyatlar **16.09.2026'da emülatördeki canlı fiyatlardan** okundu — uydurma
değil, uygulamanın kendi kaynağından (`price_service`/`tefas_service`).

## Kompozisyon

| Varlık | Tür | Adet | Alış | Güncel | Değer | K/Z | % |
|---|---|---|---|---|---|---|---|
| Çeyrek Altın | Altın | 20 | 7.850,00 | 10.827,72 | 216.554 | +59.554 | +37,9 |
| DLY | Fon | 32.000 | 4,30 | 6,2350 | 199.520 | +61.920 | +45,0 |
| KCHOL | Hisse | 620 | 148,00 | 206,10 | 127.782 | +36.022 | +39,3 |
| ABD Doları | Döviz | 2.200 | 38,50 | 48,65 | 107.030 | +22.330 | +26,4 |
| AFT | Fon | 70.000 | 0,69 | 0,9813 | 68.690 | +20.390 | +42,2 |
| SAHOL | Hisse | 550 | 93,50 | 86,00 | 47.300 | **−4.125** | **−8,0** |
| **TOPLAM** | | | | | **766.876** | **+196.091** | **+34,35** |

Maliyet ₺570.785 · Değer ₺766.876

## Enflasyon karşılaştırması

| | |
|---|---|
| Portföy getirisi | **+%34,35** |
| TÜFE (son 12 ay) | %31,51 |
| **Puan farkı** | **+2,85 puan ÖNDE** → rozet YEŞİL |
| Bileşik reel getiri | +%2,17 |

## Neden bu sayılar

- **+%34,35 > TÜFE %31,51** — rozet "enflasyonu geçti" der. Önceki sürüm
  %10,65'teydi ve rozet 20,86 puan **geride** çıkıyordu; ekran görüntüsü
  için kullanılamazdı.
- **Fark +2,85 puan** — abartısız. %50'lik bir getiri ekranda sahte durur
  ve mağaza incelemesinde risk oluşturur.
- **SAHOL −%8** — plan "en az bir varlık zararda" istiyor. Her şeyin yeşil
  olduğu kare inandırıcı değil.
- **Tüm alımlar Eylül–Ekim 2025** — reel getiri rozetinin penceresi son 12
  ay ve nominal getiri o pencerede ölçülüyor. Alımlar pencere başından
  ÖNCE olmalı ki tabanın içinde kalsınlar; sonra alınan varlık "katkı"
  sayılır ve getiriye girmez (bkz. `PeriodSummaryService.compute`).
- **Getiriler gerçekçi** — altın +%37,9 son 12 ayın gerçek hareketi
  (emülatörde 08.09.2025 alışı 7.835,17 → bugün 10.827,72). Fonlar ve
  hisse o dönemde enflasyonu geçen varlıklardı.
- **Tür dağılımı dengeli** (Fon %35,0 · Altın %28,2 · Hisse %22,8 ·
  Döviz %14,0) — pasta grafiğinde hiçbir dilim %35'i geçmiyor.
- **Alış fiyatları yuvarlak** (7.850 / 4,30 / 148,00) — elle girilmiş gibi
  durur.

## Nasıl yüklenir

CSV iki emülatörün de `/sdcard/Download/` klasöründe:

```
adb -s emulator-5554 push store_listing/demo_portfoy.csv /sdcard/Download/
```

Uygulamada: **Varlık ekle → CSV ile içe aktar → içeriği YAPIŞTIR → Önizle
→ Sepete ekle**

> Ekranda dosya seçici YOK, yalnızca yapıştırma alanı var. `/sdcard` yolu
> oradan görünmez; CSV içeriğini kopyalayıp kutuya yapıştırın.

Format `sembol;adet;fiyat;tarih` (Türkçe ondalık virgül, tarih gg.aa.yyyy).
`CsvImportService.parse` ile doğrulandı: 6 satır, 0 hata, türler doğru.

> `CEYREK` yazmayın — `inferType` onu 6 harfli BIST kodu sanıp hisse yapar.
> `ALTIN_CEYREK` gerekli.

## Görsel #1 için son kontrol

- [ ] Bakiye gizleme **kapalı** (rakamlar görünsün)
- [ ] Liste "Varlıklarım" segmentinde (Takip Listesi değil)
- [ ] Reel getiri rozeti **yeşil** ve "enflasyonu geçti" diyor
- [ ] Alt menüdeki **+** butonu karede

---

## v4 — 1.1.6 mağaza görselleri (2026-10-03)

`SCREENSHOT_PLAN` v4'ün 10 karesi için. Gerçek iPhone'da **Toplu ekle ›
Ekstreden içe aktar** ile dosya olarak yüklenir. Bu adım aynı zamanda 5.
kareyi verir. Dosyayı telefona AirDrop/Dosyalar/e-posta ile at.

| Dosya | Hesap | Ne |
|---|---|---|
| `demo_portfoy_v4.csv` | demo (ana) | v3'ün 6 satırı + BTC |
| `demo_portfoy_v4_ayse.csv` | ikinci hesap "Ayşe" | 24 ayar gram, euro, KCHOL |

**Neden kurum ekstresi biçimi** (`Tarih;İşlem Türü;Menkul Kıymet;Tür;Adet;
Ortalama Maliyet`): 5. kare "sütun adı ne olursa olsun tanır" iddiasını
gösteriyor. Kanonik `sembol;adet;fiyat;tarih` başlığı bunu göstermez.
`test/demo_portfoy_csv_test.dart` iki dosyayı ekstre motorundan geçirir.

**Neden BTC 15.07.2026'da alındı:** Eylül 2025'teki BTCTRY kapanışı
4.701.396, 02.10.2026'da 4.152.799 (Binance). v3 tarihleriyle alınsaydı
kripto zararda olurdu (−%12) ve 3. karede ikinci kırmızı satır çıkardı.
Temmuz 2026 aralığı 2,69–2,98 milyon. 3.000.000 yuvarlak alış yaklaşık
+%38 verir. Satır 12 aylık pencerenin içinde olduğu için getiriye katkı
olarak girer. Rozetin hâlâ **yeşil** olduğunu çekim öncesi gözle kontrol et.

**Ayşe neden KCHOL da tutuyor:** Birlikte görünümünde aynı varlık tek
satırda birleşir (d6aa360). 7. kare bunu gösterir.

Alış fiyatlarının dayanağı (Yahoo/Binance, kapanış): 24 ayar gram
22.09.2025 ≈ 5.058 (XAU 3.809 × USDTRY ÷ 31,1035), EURTRY 24.09.2025
48,81, KCHOL Eylül sonu ~148. Güncel (02.10.2026): KCHOL 206,80, SAHOL
86,70, USDTRY 49,11, EURTRY 55,26.

### CSV'ye girmeyenler (formdan)

CSV mevduat ve BES taşımaz (`_typeFromCell`: sözleşmeli türler formdan
girilir). Demo hesaba elle ekle:

- **Vadeli mevduat:** Varlık ekle › Mevduat. 100.000 TL, 32 gün, faiz için
  bankanın **güncel** oranını yaz. Sabit oran uydurma.
- **BES:** Varlık ekle › BES. Tek şirket, birikim yaklaşık 85.000 TL,
  2–3 fonluk dağılım. Devlet katkısı satırı ayrı görünsün (yedek kare Y2).
- **KCHOL komisyonu + temettü:** varlık sayfasından (4. kare).
- **İki fiyat alarmı:** KCHOL ve gram altın (8. kare).
