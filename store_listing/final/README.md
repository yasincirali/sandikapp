# Mağaza final görselleri

Console'a yüklenecek her şey burada. Bu klasör **türetilmiştir**:
`python build_screenshots.py --v4` her koşuda silip baştan yazar (kaynak:
set D, `../screenshots/raw_v4/`). Elle düzenleme; değişiklik raw_v4'e ve
betikteki `CAPTIONS_V4` / `REDACTIONS_V4`'e yapılır.

## Google Play — `google_play/`

| Console alanı | Dosya |
|---|---|
| Telefon ekran görüntüleri (8) | `telefon_1080x1920/01…08` |
| Feature graphic | `feature_graphic_1024x500.png` |
| Uygulama simgesi | `icon_512.png` |

## App Store — `app_store/`

| ASC alanı | Dosya |
|---|---|
| iPhone 6.9" (8) | `iphone_6.9_1320x2868/01…08` |
| iPhone 6.1" / 6.3" (8) | `iphone_6.3_1206x2622/01…08` |
| iPhone 6.5" (8) | `iphone_6.5_1284x2778/01…08` (ya da `iphone_6.5_1242x2688/`) |
| Uygulama önizlemesi (her bölüm — aynı dosya) | `onizleme_videosu/sandik_onizleme_886x1920_28sn.mp4` |
| Uygulama içi etkinlik — kart / ayrıntı | `etkinlik_gorselleri/*_kart_1920x1080.png` / `*_detay_1080x1920.png` |

## Metinler — `metinler/`

Promotional Text (en fazla 170, incelemesiz değişir) ve What's New, App
Store için TR/EN; Play sürüm notu (en fazla 500) TR/EN. Kaynakları
`../ios/tr|en/` ve `../tr-TR|en-US/`; buradakiler kopya.

⚠️ Promotional Text Eylül TÜFE'sini (%29,73) anıyor — Ekim rakamı
3 Kasım'da açıklanınca güncelle (Enflasyon günü etkinliğiyle aynı gün).

Sırayı koru: arama listesinde yalnızca 01–02 (App Store'da 01–03) görünür.
Önizleme videosu galeride ilk sıraya geçer ve otomatik oynar; bu yüzden
arama listesinde 01'in yerini o alır.

Etkinlik görselleri bilerek metinsizdir — ad/açıklamayı App Store üstüne
yazar. Etkinlikler `tool/asc_in_app_events.py` ile TASLAK kurulur
(`../ios/in_app_events/etkinlikler.json`); buradaki kopyalar elle yükleme
gerekirse diye.

## Seçim (2026-10-11)

| # | Kare | Kaynak |
|---|---|---|
| 01 | Portföy — beş tür, kripto dahil | yeni çekim |
| 02 | Performans — paranın getirisi | yeni çekim |
| 03 | KCHOL mum + EMA50/200 | yeni çekim |
| 04 | Takip listesi kıyası | yeni çekim |
| 05 | Fiyat alarmı | yeni çekim |
| 06 | Ana ekran — enflasyonun önündesin | set C (eski) |
| 07 | Paylaşım kartı | set C (eski) |
| 08 | Masraflar | yeni çekim |

**Dışarıda kalanlar ve neden**

- **Set A** — Ağustos arayüzü, başka (büyük tutarlı) portföy.
- **Set B** — açık tema + eski arayüz + başka portföy. Sinyal ve kilit
  ekranı (Live Activity) iddiaları güçlü ama koyu galeride yamalı durur;
  güncel arayüzle yeniden çekilirse App Store'un 9–10. yerine girebilir.
- **Set C 01–05, 08** — eski arayüz; karşılıkları yukarıda güncel hâliyle var.
- **`screenshots/raw/` WhatsApp kareleri, `preview_video/public/shots/`** —
  set A/B'nin ham kaynakları: gerçek portföy ve maskelenmemiş gerçek adlar.
- **`sandik_onizleme_30sn.mp4`** — 30,06 sn (Apple sınırı 30) ve
  "enflasyonun gerisindesin" mesajı galerideki 06 ile çelişiyor.
- **Anlatımlı / sessiz önizleme videoları** — açıklamalı sürümün eski
  denemeleri; `sandik_tanitim_16x9.mp4` 16:9, iPhone önizlemesi olamaz.
- **`reklam/out/`** — reklam kreatifleri; HTML ile yeniden çizim, mağaza
  önizlemesi değil (Apple 2.3.4: yalnız gerçek ekran). Play'in YouTube
  video alanı için `sandik_tanitim_16x9.mp4` kullanılabilir (yüklemesi sende).

**Bilinen kusurlar** (yeniden çekimle kapanır): 06'da toplam ₺973.501
(01'de ₺874.835) ve eski başlıktaki çıkış düğmesi; 07'de eski Performans
başlığı ve %33 pil.
