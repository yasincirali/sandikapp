# Kurulum Büyüme Planı — sandık (2026-09)

**Amaç:** App Store ve Play kurulum sayısını artırmak; bunu yaparken ücretli
kanalda kurulum başı maliyeti (CPI) düşük tutmak. Plan üç kaldıraca dayanır:
**bulunma** (arama sıralaması), **dönüşüm** (sayfayı gören yükler mi),
**tekrar** (puan, paylaşım, geri dönüş). Sıra öyle seçildi ki her adım bir
sonrakinin ölçümünü mümkün kılsın.

Ölçüm tarihi: 2026-09-18. Veri kaynağı: iTunes Search API (`tool/aso_siralama.py`)
ve App Store Connect'te görünen alanlar.

---

## 1. Mevcut durum (ölçülen, tahmin değil)

| Gösterge | Değer | Anlamı |
|---|---|---|
| App Store puanı / yorum | **0 / 0** (yayın: 2026-07-10) | Dönüşümün en güçlü sinyali boş. Rakip paramla 4,5 / 5.280 |
| Ürün sayfası dilleri | **yalnızca EN** | Türkçe metin İngilizce yerelleştirmesine girilmiş. Sayfada "Diller: İngilizce" görünüyor; ikinci keyword alanı kullanılmıyor |
| "portföy takibi" sırası | 52 / 192 | Kategori sorgusunda görünmez bölge |
| "portföy" sırası | listede yok (178) | — |
| "sandık" (noktasız ı) | **listede yok** | Apple tarafı ı katlaması + popülerlik; metadata ile düzelmez (bkz. bellek notu) |
| "sandik" / "SANDIK" | 1. sıra | Anahtar kelime alanındaki `sandik` çalışıyor |
| "sandık portföy" | 1. sıra / 17 | İki kelimeli marka araması sağlam |
| Ekran görüntüsü / önizleme videosu | 10 / **yok** | Video `store_listing/preview_video/` altında üretimde |
| Uygulama içi puan istemi | **yok** (`in_app_review` paketi yok) | Puan sıfırda kalmasının doğrudan sebebi |
| Paylaşım kartı | var (`share_card_service`) | Organik yayılma için hazır kanal, mağaza linki taşıyor mu kontrol et |
| Kilometre taşı kutlaması | var (`_kilometreTasiKontrol`) | Puan istemi için hazır "aha anı" tetikleyicisi |
| Asgari iOS | 17.0 | iOS 16 cihazlar aramada göremez; bilinçli kısıt, dokunma |

**Rakip kıyası ("portföy takibi" ilk 14, App Store TR):**

| Uygulama | Puan | Yorum | İlk yayın |
|---|---|---|---|
| paramla | 4,5 | 5.280 | 2021 |
| Merkez - Döviz & Altın | 4,5 | 2.115 | 2015 |
| Portfoy: Hisse, Fon & Borsa | 4,5 | 182 | 2025-02 |
| Parafokus | 4,3 | 130 | 2024-08 |
| Cüzdan: Yatırım Takibi | 4,5 | 77 | 2024-08 |
| Bistify | 5,0 | 12 | 2026-05 |
| PortTrack | 4,7 | 9 | 2026-09 |
| Yastık Altı | 4,6 | 8 | 2026-03 |
| **sandık** | **0** | **0** | 2026-07 |

Çıkarım: 2026'da çıkan rakipler 1-4 ayda 8-12 yoruma ulaşmış; sandık iki ayda
sıfırda. Fark ürün değil, **istem yok**. İlk 10-20 yorum eşik etkisi yaratır:
yıldız göstergesi sayfada belirir, sıralama sinyali başlar.

---

## 2. Hedef göstergeler (haftalık takip)

App Store Connect → Analytics → Metrics:

| Gösterge | Nerede | Başlangıç | 30 gün | 90 gün |
|---|---|---|---|---|
| Ürün sayfası dönüşümü (sayfa görüntüleme → yükleme) | ASC Analytics, "Conversion Rate" | ölç | +%20 göreli | sektör ortancası ~%26-33 aralığına yaklaş |
| Puan sayısı (TR) | ASC Ratings | 0 | 15 | 60 |
| "portföy takibi" sırası | `tool/aso_siralama.py` | 52 | ≤30 | ≤15 |
| "enflasyon" sırası | aynı | yok | ≤20 | ≤10 |
| Marka araması "sandık" | aynı | yok | reklamla 1 | organik görünür |
| Search Ads CPI (marka) | Apple Ads | — | ölç, tavan koy | düşür |
| Search Ads CPI (genel) | Apple Ads | — | ölç | CPP ile −%15 |

Dönüşüm oranı ilk üç hafta ölçülmeden hiçbir görsel değiştirilmez; aksi halde
neyin işe yaradığı bilinemez.

---

## 3. Plan

### Faz 0 — Bu hafta, kod yok (App Store Connect + Apple Ads)

1. **Türkçe yerelleştirme ekle.** ASC → App Information → Localizations →
   Turkish. Mevcut Türkçe metni buraya taşı; İngilizce (U.S.) alanına
   `store_listing/en-US/` metnini koy. İki kazanç: ürün sayfasında "Türkçe"
   görünür (dönüşüm), ve **ikinci 100 karakterlik keyword alanı** açılır
   (bulunma). Türkiye vitrini birden fazla yerelleştirmeyi indeksler; hangi
   ikincil dilin indekslendiğini ASC'de test et (İngilizce U.K. çoğu vitrinde
   ikincildir). İngilizce keyword alanına Türkçe kelimelerin **farklı**
   kümesini yaz, tekrar etme: `portfoy,hisse takip,fon takip,kar zarar,
   reel getiri,tufe,dolar,euro,gram altin,ons` (şapkasız yazımlar — Türk
   klavyesi olmayan kullanıcıyı yakalar; `sandik` dersinin genellemesi).
2. **Subtitle** (30 kr, indekslenir): `Hisse, Fon, Altın Takibi`. Başlıkta
   olmayan kelimeler; "sandık portföy"ün başarısı çok kelimeli aramanın
   çalıştığını gösteriyor.
3. **Promotional Text** indekslenmez; kampanya cümlesi. Enflasyon açıklama
   haftasında (her ayın 3'ü) "Ağustos TÜFE %x — portföyün geçti mi?" yap.
4. **Apple Search Ads — marka kampanyası.** Exact match: `sandık`, `sandik`,
   `sandık portföy`, `sandık uygulama`. Rakip yok, tıklama ucuz. Bu, "sandık"
   aramasında görünmemenin **tek** anında çözümüdür (bkz. §1). Günlük tavan
   koy, 2 hafta sonra CPI'a bak. Küresel finans ortanca CPT ~3,5 $; TR marka
   terimlerinde bunun çok altı beklenir, ölçmeden bütçe artırma.
5. **Google Play** tarafında aynı kontrol: Console'daki başlık
   `store_listing/tr-TR/title.txt` ile aynı mı, İngilizce listeleme ayrı
   girilmiş mi. Play açıklamayı indeksler; metin zaten uygun.

### Faz 1 — 1-2 hafta, kod (puan ve paylaşım döngüsü)

6. **Uygulama içi puan istemi** (`in_app_review`) — **YAPILDI 2026-09-18**
   (`review_prompt_service` + `review_prompt_sheet`). Kurulan tetikleyiciler:
   - Kilometre taşı sheet'i kapandıktan sonra.
   - Paylaşım kartı gerçekten paylaşılıp kapandıktan sonra.
   - ≥3 varlıklı toplu ekleme hatasız bitince.
   Kapılar: kurulum ≥3 gün + ≥3 aktif gün; portföy zararda değil; "Sonra"
   30 gün; toplam 3 istem; "Bir sorun var" → destek maili + 90 gün sessiz.
   Analytics olayı `review_prompt` (`action` × `moment`).
   **Kullanıcı kararı:** plandaki "ön soru yazma" uyarısına rağmen ön soru
   ("sandık'ı seviyor musun?" — Evet / Sonra / Bir sorun var) İSTENDİ ve
   kuruldu; gerekçe memnun olmayanı mağazaya değil desteğe yönlendirmek.
   Mağaza incelemesinde takılırsa `review_prompt_soft_gate=false` ön soruyu
   atlar, doğrudan sistem kartı açılır (yayın gerekmez). Ana bayrak
   `review_prompt_enabled`. Ayarlar'da elle "sandık'ı değerlendir" satırı var.
7. **Paylaşım kartı → mağaza linki.** `share_card_service` çıktısına
   `https://apps.apple.com/tr/app/id6786837699` ve Play linki (kısa link +
   UTM) ekle. Kart zaten enflasyon karşılaştırması gösteriyorsa bu, tek
   organik UGC kanalıdır; "sandık ara" yerine link yayılır (marka arama sorunu
   da böyle aşılır).
8. **Ortak portföy daveti**, var olan viral döngü. Davet metnine mağaza linki
   + "davet kodu" ekli mi kontrol et; davet kabulünü Analytics'te say.
9. **Sürüm notu + tur** (CLAUDE.md "Yenilikler" kuralı) puan istemi için
   gerekmez; kullanıcıya görünen özellik değil.

### Faz 2 — 2-4 hafta, ürün sayfası dönüşümü

10. **Product Page Optimization (A/B).** Üç varyant, aynı anda:
    - A: mevcut `set_b`
    - B: `set_a`
    - C: yeni — **ilk kare enflasyon karşılaştırması** (kırmızı/yeşil puan
      farkı), ikinci kare "komisyon + temettü dahil gerçek kâr", üçüncü kare
      ortak portföy. Başlıklar en küçük önizlemede okunur büyüklükte.
    İlk iki karenin dönüşümün çoğunu belirlediği ölçülmüş; Apple "belirsiz"
    diyene kadar testi durdurma (en az 2 hafta).
11. **Önizleme videosu** yükle (`store_listing/preview_video/brag-output-2026-09-18-store/`).
    İlk 3 saniye sessiz ve altyazılı olsun; otomatik oynatma sessizdir.
12. **İkon testi** (PPO'nun ikinci turu). Küçük boyutta finans kategorisinin
    mavi/yeşil kalabalığında amber ayrışıyor mu; yalnızca ölç.

### Faz 3 — Aylık ritim (In-App Events + Custom Product Pages)

13. **In-App Event: "Enflasyon günü".** Her ayın 3'ü TÜİK TÜFE açıklaması.
    Etkinlik kartı arama sonuçlarında ve Today'de ayrı görünür; mevcut
    kullanıcıya geri dönüş bildirimi de sayılır. Metin: "Eylül TÜFE açıklandı.
    Portföyün geçti mi?" 14 gün önce planla, ASC onayı gerekir.
14. **Custom Product Pages (en fazla 70).** Üç sayfa:
    - **Enflasyon**: Search Ads kelime grubu `enflasyon, reel getiri, tüfe,
      alım gücü` → ilk kare TÜFE karşılaştırması.
    - **Temettü**: `temettü takip, temettü hesaplama` → temettü kazanç karesi.
    - **Ortak portföy**: `aile bütçesi, ortak yatırım` → Birlikte sekmesi.
    Kelimeyle eşleşen CPP aynı bütçede ~%23 daha fazla yükleme ve Apple
    2025'te CPP'lerin organik aramada da çıkabildiğini duyurdu. Sayfa başına
    ekran görüntüsü seti `store_listing/ios/screenshots/cpp_<ad>/` olarak
    üretilir (`build_screenshots.py`'ye hedef eklenir).
15. **Search Ads genel kampanya**, CPP'lerle. Küçük bir Discovery (broad)
    kampanyası arama terimlerini toplar; 2 haftada bir dönüştürenleri exact
    kampanyaya taşı, dönüştürmeyenleri negatif ekle. Finans CPI'ı yüksek
    olduğu için marka + niş (enflasyon/temettü) dışına çıkma; "portföy"
    genel teriminde paramla ile fiyat yarışına girme.

### Faz 4 — Sürekli, ücretsiz kanallar (Türkiye'ye özgü)

16. **X (Twitter) finans topluluğu.** Enflasyon günü ve BIST kapanışında
    paylaşım kartı görseliyle "nominal %x, TÜFE %y, reel %z" gönderisi.
    Sayı üretimi uygulamanın kendisinden; her gönderi mağaza linki taşır.
17. **Ekşi Sözlük** "sandık (uygulama)" başlığı; ilk entry geliştiriciden,
    dürüst ve kısa. Marka araması kırık olduğu için başlık **linkli** olmalı.
18. **Reddit r/borsa, r/Turkey finans başlıkları**; "kendi uygulamam" etiketiyle.
19. **YouTube küçük finans kanalları** (10-50k): ücretsiz ömür boyu hesap yok
    (paywall kapalı zaten), karşılığında dürüst inceleme. Enflasyon açısı
    onların içerik takvimiyle örtüşür.
20. **Teşvik araştırması.** 2026'da Türkiye'de mobil uygulama reklam ve
    platform komisyonu desteği olduğu haberleri var (kaynak listede); şirket
    yapısı ve uygunluk **doğrulanmadı**, YAPMAN_GEREKENLER §2 (tüzel kişilik)
    ile birlikte değerlendir.

---

## 4. Sıra ve bağımlılık

```
Hafta 1   Faz 0 (ASC yerelleştirme, subtitle, marka Search Ads)  ── ölçüm başlar
Hafta 2-3 Faz 1 (puan istemi, paylaşım linki)                    ── puan akışı
Hafta 3-6 Faz 2 (PPO A/B, video)                                 ── dönüşüm
Ay 2+     Faz 3 (IAE her ayın 3'ü, CPP + Search Ads niş)         ── ölçekli kazanım
Sürekli   Faz 4                                                  ── organik hacim
```

Faz 2, Faz 1'den **sonra** gelir: puan yıldızı olmadan yapılan görsel testi
düşük dönüşümde çalışır ve sonuçları yanıltır.

## 5. Yapılmayacaklar

- Başlığa/keyword'e marka varyantı yığmak (2.3.7 reddi).
- "Beğendin mi?" ön eleme diyaloğu (puan kapılama yasak).
- Satın alınmış yorum, yükleme kampanyası (kalıcı sıralama cezası).
- Dönüşüm ölçülmeden ikon/ekran görüntüsü değiştirmek.
- Genel "portföy" teriminde yüksek teklif (finans CPI'ı sektörün en pahalısı).

## 6. Kaynaklar

- [Appbot — PPO + CPP 2026 rehberi](https://appbot.co/blog/product-page-optimization/)
- [MobileAction — PPO A/B testleri](https://www.mobileaction.co/blog/product-page-optimization/)
- [Adapty — Custom product pages 2026](https://adapty.io/blog/custom-product-pages-app-store/)
- [MobileAction — CPP organik aramada](https://www.mobileaction.co/blog/custom-product-pages-meet-organic-search/)
- [RespectASO — CPP limitleri 2026](https://respectaso.com/blog/custom-product-pages-app-store-guide-2026/)
- [Strataigize — Dönüşümü ne artırıyor 2026](https://www.strataigize.com/blog/app-store-conversion-rate-optimization)
- [AppTweak — Apple Ads benchmark 2026](https://www.apptweak.com/en/aso-blog/apple-ads-benchmarks)
- [Adapty — Apple Ads benchmark, 90 ülke](https://adapty.io/blog/apple-ads-benchmarks-2026/)
- [Business of Apps — Apple Search Ads maliyetleri](https://www.businessofapps.com/marketplace/apple-search-ads/research/apple-search-ads-costs/)
- [aso.dev — Cross-localization](https://aso.dev/metadata/cross-localization/)
- [AppTweak — Primary/secondary localization](https://www.apptweak.com/en/aso-blog/how-to-benefit-from-cross-localization-on-the-app-store)
- [AppFollow — Ülke bazlı keyword yerelleştirmeleri](https://appfollow.io/app-store-keywords-localizations)
- [Appbot — Puan istemi: erken mi, aha anı mı](https://appbot.co/blog/prompting-for-ratings-prompt-early-or-wait/)
- [Apple — Requesting App Store reviews](https://developer.apple.com/documentation/storekit/requesting-app-store-reviews)
- [Apple — Ratings, reviews, and responses](https://developer.apple.com/app-store/ratings-and-reviews/)
- [AppFollow — Puanı yükseltme 2025](https://appfollow.io/blog/how-to-improve-app-ratings-and-get-5-stars)
- [Moburst — Organik pazarlama 2026](https://www.moburst.com/blog/app-organic-marketing-playbook/)
- [Evren Özmen — Türkiye mobil uygulama teşvikleri 2026](https://evrenozmen.com.tr/mobile-app-incentives-turkey-2026)
