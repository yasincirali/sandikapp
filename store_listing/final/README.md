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
| iPhone 6.7" (8) | `iphone_6.7_1284x2778/01…08` |
| iPhone 6.5" (8) — yalnız istenirse | `iphone_6.5_1242x2688/01…08` |

Sırayı koru: arama listesinde yalnızca 01–02 (App Store'da 01–03) görünür.

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

**Bilinen kusurlar** (yeniden çekimle kapanır): 06'da toplam ₺973.501
(01'de ₺874.835) ve eski başlıktaki çıkış düğmesi; 07'de eski Performans
başlığı ve %33 pil.
