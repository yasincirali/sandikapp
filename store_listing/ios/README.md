# iOS — App Store Connect'e yüklenecek görseller

Bu klasördeki ekran görüntüleri **türetilmiş çıktıdır** — elle düzenleme.
Ham görüntüler değişirse betiği yeniden koş:

```bash
cd store_listing
python build_screenshots.py       # set A
python build_screenshots.py --v2  # set B
```

## App Store Connect → Uygulama önizlemeleri ve ekran görüntüleri

| ASC alanı | Dosya |
|---|---|
| iPhone 6.5" | `screenshots/set_a/1242x2688/` (7) **veya** `screenshots/set_b/1242x2688/` (8) |
| iPhone 6.7" | `screenshots/set_a/1284x2778/` (7) **veya** `screenshots/set_b/1284x2778/` (8) |

**Uygulama ikonu burada yok** — App Store ikonu `.ipa` içinden gelir
(`ios/Runner/Assets.xcassets/AppIcon.appiconset`), ayrıca yüklenmez.
`android/graphics/icon_512.png` yalnızca Play Console'un "Uygulama
simgesi" alanı içindir; feature graphic'in de App Store'da karşılığı yok.

### ⚠️ Yalnızca `set_b` yeniden üretilebilir

Çıktı PNG'leri `.gitignore`'da (türetilmiş dosya), kaynak izleniyor. Ama
iki setin kaynağı eşit durumda değil:

| Set | Ham kaynak | Temiz klonda üretilebilir mi |
|---|---|---|
| `set_b` | `screenshots/raw_v2/*.jpeg` — **commit'li** | ✅ evet, `--v2` ile |
| `set_a` | `screenshots/raw/*.png` — **ignore'da** | ❌ hayır, ham kareler yalnızca bu makinede |

`set_a` kareleri şu an diskte duruyor ama repoda yok; makine değişirse
geri gelmez. Kalıcı olarak gerekiyorsa ham görüntüleri `raw/` içine koyup
`.gitignore`'daki `store_listing/screenshots/raw/*.png` satırını kaldır.
Pratikte sorun değil — Console'a **tek set** yükleniyor ve seçilen `set_b`.

### ⚠️ İki set karıştırılmaz

`set_a` ile `set_b` **BAŞKA portföylere** ait. Tek galeride karıştırmak
"aynı portföy tüm karelerde" tutarlılığını bozar — birini seç, hem 6.5"
hem 6.7" karelerini aynı setten yükle.

Sıralama için [`../SCREENSHOT_PLAN.md`](../SCREENSHOT_PLAN.md).

## Mağaza metni

[`APP_STORE_1.1.3.md`](APP_STORE_1.1.3.md) — App Store açıklaması.
`../tr-TR/full_description.txt` bunun **birebir aynısı** (tek bilinçli
fark: Play sürümünde sabit satır kırılmaları kaldırıldı, paragraflar tek
satır). Metni değiştirirken ikisini birlikte güncelle — eşleme tablosu
`PLAY_STORE_YAYIN_REHBERI.md` §12'de.

## Neden mağaza başına ayrı klasör

Play en fazla **2:1** en-boy oranına izin verir; buradaki App Store
kareleri 2,16:1 olduğu için Play yüklemede reddeder. Boyutlar tek klasörde
dururken "hangi boyut hangi mağaza" sorusu her yüklemede yeniden
soruluyordu. Artık `build_screenshots.py` her hedefi mağaza etiketiyle
taşıyor ve `android/` ile `ios/` klasörlerine ayrı yazıyor.
