# Android — Play Console'a yüklenecek görseller

Bu klasördeki her şey **türetilmiş çıktıdır** — elle düzenleme. Kaynak
değişirse (`assets/images/sandik_icon.png`, palet, slogan, ham ekran
görüntüleri) betiği yeniden koş:

```bash
cd store_listing
python build_store_graphics.py    # ikon + feature graphic
python build_screenshots.py       # ekran görüntüleri, set A
python build_screenshots.py --v2  # ekran görüntüleri, set B
```

Elle Canva'da yapılan bir grafik bir sonraki sürümde "hangi dosyadan
üretmiştik" sorusunu doğurur ve palet kayar.

## Play Console → Mağaza ayarları → Ana mağaza sayfası

| Console alanı | Dosya | Kural |
|---|---|---|
| Uygulama simgesi | `graphics/icon_512.png` | 512×512, 32-bit PNG, **alfa yok** ✓ |
| Öne çıkan grafik | `graphics/feature_graphic_1024x500.png` | tam 1024×500, alfa yok ✓ |
| Telefon ekran görüntüleri | `screenshots/set_a/1080x1920/` (7) **veya** `screenshots/set_b/1080x1920/` (8) | 1080×1920 = 1,78:1, 2:1 sınırının altında ✓ |

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
"aynı portföy tüm karelerde" tutarlılığını bozar — birini seç, hepsini
ondan yükle.

| Set | Kare | İçerik |
|---|---|---|
| `set_a` | 7 | ana sayfa, performans, komisyon, dağılım, ortak portföy, liderlik, varlık detayı |
| `set_b` | 8 | dağılım, karşılaştırma, portföy çizgisi, takip listesi, sinyal paneli, sinyal ayarları, canlı etkinlik, yarış |

Sıralama önemli — arama sonucunda **ilk iki görsel** görünür. Hangisinin
önce geleceği [`../SCREENSHOT_PLAN.md`](../SCREENSHOT_PLAN.md)'de yazılı.

## Neden bu tasarım kararları

**İkon — iki kez yuvarlanmış köşe tuzağı.** Kaynak PNG'nin köşeleri zaten
yuvarlak ve dışı şeffaf. Şeffaflık koyu zemine düzleştirilirse ikonun
çevresinde koyu bir çerçeve kalıyor ve Play kendi maskesini onun üstüne
uygulayınca logonun kenarı kesilip halka oluşuyor. Bu yüzden opak pikseller
`getbbox` ile kırpılıp tuval TAM dolduruluyor — Play'in maskesi logonun
kendi köşesiyle çakışsın diye. **Köşe yuvarlama uygulanmıyor.**

**Feature graphic — punto ölçümle seçiliyor.** Sabit punto yazmak yerine
metnin gerçek genişliği ölçülüp güvenli kenara (%8) sığana kadar
küçültülüyor. Slogan ileride değişirse grafik sessizce bozulmaz. İlk
denemede 38pt slogan sağ kenarı aşıyordu.

**Slogan finansal politika uyumlu.** "Gerçek kâr/zarar, tek ekranda" ürünün
ne yaptığını söylüyor; kazanç/getiri vaat etmiyor. Play'in finansal
uygulama politikası vaat eden metinlere sert davranıyor.

**Neden mağaza başına ayrı klasör.** Play en fazla **2:1** en-boy oranına
izin verir; App Store kareleri 2,16:1 olduğu için Play yüklemede reddeder.
Boyutlar tek klasörde dururken "hangi boyut hangi mağaza" sorusu her
yüklemede yeniden soruluyordu. Artık `build_screenshots.py` her hedefi
mağaza etiketiyle taşıyor ve `android/` ile `ios/` klasörlerine ayrı yazıyor.

## Kalan görsel işler (zorunlu değil)

- **Tablet görselleri** — zorunlu değil ama büyük ekran sıralamasında
  avantaj sağlıyor. 7" ve 10" için ayrı set.
- **Promo video** — opsiyonel, YouTube linki.
