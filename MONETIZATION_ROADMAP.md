# sandık — Monetizasyon & Engagement Yol Haritası

**Tarih:** 2026-07-09
**Durum:** Uygulama App Store review'da, temel işlevler tamam. Bu doküman: para kazanma + kullanıcı bağlılığı için 6-8 haftalık implementation planı.

---

## 0. Mevcut Durum Özeti

### Ne var?
- **19 ekran**, 6 varlık tipi (hisse, fon, altın, döviz, emtia, diğer)
- **Riverpod** state management, **Supabase** backend
- **Teknik analiz**: 8 gösterge (RSI, MACD, Bollinger, EMA, Stochastic + ADX/Williams %R/CCI premium olarak etiketlenmiş)
- **Partner paylaşımı** (davet kodu ile), **push bildirim** altyapısı (FCM)
- **KVKK uyumu**: disclaimer sistemi, veri export

### Ne yok (kritik eksikler)?
- ❌ **Analytics tracking** — hiçbir kullanıcı davranışı ölçülmüyor (körüz)
- ❌ **In-app purchase** — `premiumUnlockedProvider` var ama SharedPreferences toggle'ı, gerçek IAP yok
- ❌ **Feature flag / remote config** — A/B test yapılamıyor
- ❌ **Paywall UI** — premium göstergeler sessizce atlanıyor, kullanıcıya "premium'a geç" denmiyor
- ❌ **Scheduled notifications** — streak reminder, fiyat alarmı için altyapı yok
- ❌ **Engagement mekanizmaları** — rozet, streak, portföy sağlık skoru yok

### Kritik teknik bulgu
`premiumUnlockedProvider` ([preferences_provider.dart:112](lib/providers/preferences_provider.dart#L112)) **zaten mevcut** ve teknik analiz servisine bağlı ([technical_analysis_service.dart:382](lib/services/technical_analysis_service.dart#L382)). Yani entitlement mimarisi hazır — sadece RevenueCat'e bağlanacak.

---

## 1. Stratejik Karar: Freemium + Aylık/Yıllık Abonelik

### Neden freemium (reklamsız değil)?
- **2026 fintech standardı**: 7 günlük trial + subscription en yüksek konversiyon
- **Değerleme**: Abonelik gelirini yatırımcılar reklam gelirinin **4-8x**'i olarak değerliyor
- **Türkiye pazarı**: Fintech'te reklam güven düşürüyor, abonelik daha uygun
- **Ortalama ABD tüketicisi 6.7 aktif aboneliği var**; Türkiye'de bu sayı düşük ama yükseliyor

### Fiyat önerisi (Türk piyasası için)
| Plan | Fiyat | Konum |
|------|-------|-------|
| **Free** | 0₺ | Kalıcı, temel işlev |
| **Premium Aylık** | 49₺/ay | Deneme sonrası varsayılan |
| **Premium Yıllık** | 349₺/yıl (~29₺/ay) | **%40 tasarruf** rozetiyle vurgula |
| **7-gün ücretsiz deneme** | — | Yıllık planla başlar |

**Neden bu fiyat?** Netflix Türkiye 149₺, Spotify 60₺, YouTube Premium 57₺. Fintech niş olduğu için orta segmentte konumlan. İleride yükseltilebilir.

### Free vs Premium — Feature Ayrımı

**Free katman (kalıcı ücretsiz):**
- Portföy takibi (maks. **10 varlık**)
- Hisse, döviz, altın (3 tip)
- Standart göstergeler (RSI, MACD, EMA, Bollinger, Stochastic)
- Manuel fiyat güncelleme
- **1 partner** paylaşımı
- Son **30 günlük** grafik geçmişi
- **Günde 1 sinyal analizi** (TR 11:00) — sabit saat, özelleştirilemez
- Sadece **AL/SAT** bildirimleri; nötr sinyaller sadece geçmişte görünür

**Premium katman:**
- ✅ **Sınırsız varlık ve tüm tipler** (fon + emtia dahil)
- ✅ **Premium göstergeler** (ADX, Williams %R, CCI) — kod hazır!
- ✅ **Günde 2 sinyal analizi** (TR 11:00 + 15:00) — hazır: `analyze-signals` edge function
- ✅ **Nötr sinyal push bildirimi** (istersen aç, market kilitli / trendsiz olduğunda haber ver)
- ✅ **Asset türü başına eşik ayarı** (%50/%70/%85 — sıkı/gevşek sinyal filtresi)
- ✅ **Ayda 1 canlı analiz kotası** (istediğin zaman tetikle — "şimdi analiz et")
- ✅ **AI portföy raporu** (aylık, Claude API ile — güçlü/zayıf yönler, öneriler)
- ✅ **Fiyat alarmları** ("USD 35₺ olduğunda haber ver")
- ✅ **Vergi/KVK raporu PDF** (yıl sonu kâr-zarar)
- ✅ **Sınırsız partner paylaşımı**
- ✅ **5 yıl grafik geçmişi**
- ✅ **Reklamsız** (ileride free'ye reklam eklerken)
- ✅ **Öncelikli müşteri desteği**

### 🔔 Sinyal Bildirim Mimarisi (hazır, 2026-07-13)

Cron-tabanlı sinyal bildirimi altyapısı devrede:
- **Server:** `supabase/functions/analyze-signals/index.ts` — pg_cron ile
  TR 11:00 & 15:00'te tüm push token'lara `signal_analyze_request` data-message
  atar (sessiz).
- **Client:** `_AuthGate._triggerSignalAnalysis` — data-message'ı yakalar,
  `signalProvider.analyzePortfolio()` çağırır. Sinyal önceki push'tan farklıysa
  `signal_notifications` tablosuna yazar + local push. Aynı sinyal tekrar edilmez.
- **Persistence:** `signal_notifications` tablosu (RLS'li). Kullanıcı silse bile
  statü değişmedikçe yeni push atılmaz. Bell sheet'te aktif + geçmiş bölümleri.
- **Threshold + neutral toggle:** `signalThresholdProvider` (per AssetType) +
  `signalNeutralPushProvider` (Ayarlar → Sinyal Ayarları).

**Premium ile fark:**
- Free: cron her iki slot'ta da atar ama client 15:00'te sadece nötr sinyalleri
  DB'ye yazar, push göndermez (premium değil kontrolü client tarafında).
  → **TODO Faz 2'de eklenmesi gereken bir gate:**
  `if (!premium && slot == 'afternoon' && signal != neutral) skip push`
- Premium: iki slot da tam sinyal + kullanıcı istediği zaman "Şimdi analiz et"
  butonu (rate-limited, aylık N kez).

---

## 2. Yol Haritası — 4 Faz, 6-8 Hafta

### 📊 FAZ 0: Ölçüm & Altyapı (1 hafta)
**Amaç:** Para kazanmadan önce körlükten çık.

#### Görevler
1. **Firebase Analytics kurulumu**
   - `firebase_analytics: ^11.x` ekle
   - `AnalyticsService` singleton oluştur ([lib/services/analytics_service.dart])
   - Kritik event'leri instrument et:
     - `app_open`, `screen_view` (otomatik)
     - `asset_added` (tip, miktar aralığı)
     - `signal_viewed`, `signal_dismissed`
     - `premium_gate_shown` (hangi feature)
     - `premium_upgrade_started`, `premium_upgrade_completed`
     - `onboarding_step_completed`
     - `partner_invite_sent`, `partner_accepted`

2. **Firebase Remote Config**
   - `firebase_remote_config: ^5.x` ekle
   - `RemoteConfigService` oluştur
   - İlk flag'ler:
     - `premium_enabled` (boolean) — acil kapatma anahtarı
     - `paywall_variant` (string: 'A', 'B') — A/B test
     - `free_asset_limit` (int, default 10) — server-side ayarlanabilir
     - `premium_price_monthly` (string) — dinamik gösterim

3. **Sentry veya Crashlytics event log**
   - Zaten Crashlytics var, custom key/log ekle:
     - `user_type: free|premium`
     - `asset_count`, `days_since_install`

4. **Analytics dashboard hazırla**
   - Firebase Console'da funnel: install → onboarding → asset_added → 7-day retention
   - GA4 audience: "engaged_users" (3+ oturum), "premium_intent" (paywall_shown 2+ kez)

#### Kabul kriterleri
- [ ] Firebase Analytics DebugView'da event'ler görünüyor
- [ ] Remote Config değişikliği 5 dk içinde uygulamaya yansıyor
- [ ] `premium_gate_shown` event'i teknik analiz ekranından tetiklenebiliyor

---

### 💳 FAZ 1: IAP Altyapısı + Paywall (2 hafta)
**Amaç:** Kullanıcılar gerçek para ödeyebilsin.

#### Görevler

1. **RevenueCat entegrasyonu**
   - Hesap aç: [app.revenuecat.com](https://app.revenuecat.com)
   - App Store Connect'te subscription products oluştur:
     - `sandik_premium_monthly` — 49₺/ay
     - `sandik_premium_yearly` — 349₺/yıl (7-day trial)
   - Google Play Console'da aynı ürünler
   - RevenueCat'te entitlement: `premium` (aylık + yıllık products'a bağla)
   - `purchases_flutter: ^8.x` ekle
   - `PurchaseService` singleton oluştur ([lib/services/purchase_service.dart])
     ```
     - init() — app start'ta config
     - getOfferings() — paywall için ürünler
     - purchasePackage() — satın alma
     - restorePurchases() — Apple zorunlu
     - customerInfo listener — entitlement değiştiğinde premiumUnlockedProvider güncelle
     ```

2. **`premiumUnlockedProvider` refactor**
   - Şu an SharedPreferences → RevenueCat CustomerInfo'ya bağla
   - `AsyncNotifierProvider<bool>` yap
   - `PurchaseService.customerInfoStream` dinle
   - Offline durumda son bilinen entitlement'ı SharedPreferences'ta cache'le

3. **Paywall UI**
   - `PaywallScreen` oluştur ([lib/screens/paywall_screen.dart])
     - Hero bölüm: portfolio grafiği + "Premium'la daha derinlemesine analiz"
     - Feature list (checkmark'lı 6-7 madde)
     - Plan seçici (yıllık default seçili, "%40 tasarruf" rozeti)
     - "7 gün ücretsiz dene" primary button
     - Restore purchases link
     - Küçük footer: fiyat detayı, otomatik yenileme uyarısı (Apple zorunlu)
   - RevenueCat'in `purchases_ui_flutter` template'lerini de değerlendir (dashboard'dan güncellenebilir)

4. **Paywall tetikleyicileri (context-aware)**
   - Premium indicator seçildiğinde ([signal_settings_screen.dart])
   - 11. varlık eklenmeye çalışıldığında
   - Ana ekranda "Premium özellikleri keşfet" sabit banner
   - Onboarding step 3'ten sonra (opsiyonel modal)
   - Profil ekranında "Premium" satırı

5. **`PremiumGate` widget'ı**
   ```
   PremiumGate(
     feature: 'premium_indicator_adx',
     child: AdxChart(),  // premium ise göster
     fallback: PremiumTeaser('ADX göstergesi Premium'da'),
   )
   ```
   Kullanım kolaylığı ve merkezi kontrol için.

#### Kabul kriterleri
- [ ] Sandbox test hesabıyla iOS'ta satın alma tamamlanıyor
- [ ] Google Play test hesabıyla Android'de aynı
- [ ] Restore purchases çalışıyor
- [ ] Premium olan kullanıcı ADX/Williams %R göstergelerini görüyor
- [ ] Trial dönemi 7 gün olarak App Store'da görünüyor

---

### 🎯 FAZ 2: Premium Feature'lar (2-3 hafta)
**Amaç:** Premium'un "değer" tarafını inşa et.

#### 2.1 Portföy Sağlık Skoru (0-100)
**Yer:** Ana ekran, PortfolioSummaryWidget altında ([home_screen.dart:302](lib/screens/home_screen.dart#L302))

**Formül:**
- **Çeşitlendirme (40 puan)**: Kaç varlık tipi, tek varlıkta yoğunlaşma yüzdesi
- **Risk dengesi (30 puan)**: Volatilite (hisse) vs stabil (altın/döviz) oranı
- **Performans (20 puan)**: Son 90 günde reel getiri
- **Aktivite (10 puan)**: Son 7 günde giriş, güncelleme

**Free**: Sadece skor gösterilir (0-100)
**Premium**: Skor + detaylı breakdown + iyileştirme önerileri ("Portföyünüz %68 hisseye bağlı, %20 altın eklemeyi düşünün")

#### 2.2 Fiyat Alarmları
**Yer:** Yeni ekran `PriceAlertsScreen`, ayrıca Asset Detail'de "Alarm kur" butonu

- Supabase'de `price_alerts` tablosu:
  ```
  id, user_id, asset_ticker, condition (above/below), target_price, created_at, triggered_at
  ```
- Supabase Edge Function (cron her 5 dk):
  - Aktif alarmları çek
  - PriceService'ten güncel fiyatları al
  - Koşulu sağlayanlara FCM push gönder
  - `triggered_at` işaretle
- Free: 1 aktif alarm, Premium: sınırsız

#### 2.3 Premium Teknik Göstergeler (görünür hale getir)
- Şu an sessizce atlanıyor ([technical_analysis_service.dart:382](lib/services/technical_analysis_service.dart#L382))
- SignalSettingsScreen'de premium göstergelerin yanına 🔒 ikonu koy
- Tıklandığında paywall aç
- Premium açılınca otomatik göster

#### 2.4 AI Portföy Raporu (Aylık)
**Yer:** Profil ekranında "Aylık Rapor" satırı (sadece premium)

- Ayda 1 kez tetikle (kullanıcı manuel de talep edebilir, max 3/ay)
- Supabase Edge Function → Claude API çağrısı
- Prompt template:
  ```
  Kullanıcı portföyü: {assets JSON}
  Son 30 gün performans: {gains JSON}
  Türk piyasa bağlamı: {BIST, USD/TRY, altın trend}

  Türkçe olarak ver:
  1. Portföy güçlü yönleri (2 madde)
  2. Riskler (2 madde)
  3. Somut öneriler (3 madde, TR piyasasına uygun)
  4. Sonraki ay için 1 dikkat noktası
  ```
- Response'u Supabase'de sakla, PDF olarak da export edilebilsin
- İlk raporu ücretsiz göster (upsell hook)

#### 2.5 Vergi Raporu (KVK PDF)
**Yer:** Profil → "Yıllık Rapor İndir"

- Yıl seç, tüm işlemleri çek
- PDF üret (kullan `pdf: ^3.x` paketi):
  - Kullanıcı bilgi, dönem
  - Varlık tipine göre alım-satım listesi
  - Türk vergi mevzuatı formatına yakın (danışman şart uyarısıyla)
  - Toplam kâr/zarar, ortalama maliyet
- Muhasebeciye gönderilebilir kalitede

**Not:** Vergi hesabı iddia etme, "bilgilendirme amaçlı" disclaimer koy.

#### Kabul kriterleri
- [ ] Sağlık skoru her portföy için hesaplanıyor, ana ekranda görünüyor
- [ ] Fiyat alarmı kurulup tetiklenebiliyor (end-to-end)
- [ ] Premium user ADX/Williams/CCI görüyor, free 🔒 görüyor
- [ ] AI raporu Türkçe, mantıklı, portföye özgü içerik üretiyor
- [ ] Vergi PDF'i indirilebiliyor ve okunabilir

---

### 🎮 FAZ 3: Engagement & Retention (2 hafta)
**Amaç:** Kullanıcı geri gelsin, streak oluştursun, viral olsun.

#### 3.1 Streak Sistemi
**Metrik:** Kullanıcı ardışık gün sayısı (app açma + en az bir işlem)

- Supabase'de `user_streaks` tablosu:
  ```
  user_id, current_streak, longest_streak, last_active_date, freezes_available
  ```
- Free: 3 gün grace period yok, streak sıfırlanır
- Premium: **Streak Freeze** — ayda 2 kez pas geçme hakkı

**UI:**
- Ana ekran header'da 🔥 ikonu + gün sayısı
- Streak kırılınca "Kaybettin ama Premium olsan freeze kullanabilirdin" (soft upsell)

**Bildirim:**
- Perşembe akşam 20:00 (Pazar değil! Kritik gün): "Bu haftaki streak'ini koruma zamanı 🔥"
- Streak kırılmadan 1 gün önce: "24 saatin kaldı"

#### 3.2 Rozet/Başarım Sistemi
**Yer:** Yeni ekran `AchievementsScreen`, Profil'den erişim

**Rozet kategorileri:**
- **Portföy**: "İlk 10K", "100K Milestone", "1M Milestone"
- **Çeşitlendirme**: "5 varlık tipi", "10 farklı hisse"
- **Sabır**: "1 yıl sabır", "3 yıl portföy"
- **Türk kültürü**: "Çeyrek Altın Koleksiyoncusu", "Ata Altın Sahibi", "Cumhuriyet Uzmanı"
- **Sosyal**: "İlk Partner", "5 Partner", "Davet Şampiyonu"
- **Streak**: "7 gün", "30 gün", "100 gün", "365 gün"

**Kazanım anı:** Ana ekrana alt sağdan slide-in confetti animasyonu + "Rozet kazandın" bottom sheet

#### 3.3 Portföy Sağlık Skoru — Gamification'a bağla
- Skor değiştiğinde bildir: "Bugün skorunu 3 puan artırdın 📈"
- Haftalık özet push: "Bu hafta skorun 75→82. Devam et!"
- Skor 90+ olan kullanıcılara özel rozet: "Portföy Ustası"

#### 3.4 Haftalık Özet Bildirimi
**Zaman:** Perşembe akşam 20:00 (kritik gün — Pazar değil)

**İçerik varyantları (Remote Config ile A/B):**
- Variant A: "Bu hafta portföyün %2.3 arttı 📈"
- Variant B: "3 sinyal alındı: 2 alış, 1 satış. Detay için tıkla"
- Variant C: "Streak: 12 gün 🔥 Devam!"

Supabase Edge Function ile FCM scheduled push (server-side cron).

#### 3.5 Referral Sistemi
**Konsept:** Partner davet ederse ve o kullanıcı 7 gün aktif olursa → **1 ay ücretsiz Premium**

- Zaten partner invite sistemi var, üzerine kur
- Supabase'de `referrals` tablosu: `referrer_id, referred_id, activated_at, reward_granted_at`
- 7 günlük aktivite kontrolü Edge Function ile
- Premium eklendiğinde bildir: "Arkadaşın {name} sayesinde 1 ay Premium kazandın 🎁"

**Neden viral olur:** Türkiye'de tavsiye-güven çok yüksek, kişisel öneri iş yapar.

#### Kabul kriterleri
- [ ] Streak sayacı doğru artıyor, kırılıyor, freeze çalışıyor (premium)
- [ ] En az 10 rozet çalışır durumda, unlock animasyonu var
- [ ] Perşembe haftalık push scheduled ve teslim ediliyor
- [ ] Referral akışı end-to-end test edildi (2 test hesabıyla)

---

## 3. Ölçüm Planı (KPI'lar)

Faz 0'da kurduğun analytics ile şunları izle:

### North Star Metric
**Weekly Active Users (WAU)** — bu ölçek, hem retention hem büyüme sinyali.

### Faz 1 (IAP) sonrası
- **Trial start rate**: Paywall gören / Trial başlatan (hedef %8-12)
- **Trial → paid conversion**: 7. gün sonunda kalış (hedef %30-45)
- **Overall paid conversion**: Install → paid (hedef %2-4)

### Faz 2 (feature'lar) sonrası
- **Premium feature adoption**: Premium olan / feature'ı kullanan (hedef %60+)
- **AI report request rate**: Ayda kaç premium user rapor istiyor
- **Alert usage**: Premium başına ortalama aktif alarm sayısı

### Faz 3 (engagement) sonrası
- **D7 retention**: %25+ (fintech ortalaması %20)
- **D30 retention**: %15+
- **Streak median length**: 7+ gün
- **Referral rate**: Premium user başına ortalama davet sayısı

---

## 4. Riskler & Karşı Önlemler

| Risk | Olasılık | Etki | Önlem |
|------|----------|------|-------|
| App Store premium subscription reddederse | Orta | Yüksek | Test hesabıyla önce sandbox valide et, review notu detaylı yaz |
| Türk kullanıcı 349₺ pahalı bulursa | Orta | Yüksek | Remote Config ile fiyat ayarlanabilir, %50 indirim kampanyası A/B test |
| AI rapor Claude API maliyetli olursa | Düşük | Orta | Ayda 3 rapor limit, prompt cache, sadece premium user |
| Free tier fazla kısıtlı olursa (10 varlık) | Orta | Yüksek | Remote Config'ten limit ayarla, launch'ta 20 ile başla, gerekirse düşür |
| Streak/rozet gimmick gibi görülürse | Düşük | Düşük | Fintech'e uygun tonda tut, çocuksu emoji spam'i yapma |
| Vergi raporu yanlış hesap iddia edilirse | Düşük | Yüksek | "Bilgilendirme amaçlıdır, resmi beyan için muhasebecinize danışın" disclaimer |
| KVKK: AI rapor kullanıcı verisini Claude'a gönderiyor | Yüksek | Orta | Aydınlatma metnine ekle, anonim ID kullan, opt-in tut |

---

## 5. Rakip Analizi (Kısa)

### Türkiye'deki rakipler
- **Foreks Mobil**: Ücretsiz, reklamli, teknik analiz zayıf. Sen daha temiz UX ile öne çıkarsın.
- **Matriks IQ**: Profesyonel, pahalı (~500₺/ay). Sen "her kullanıcıya premium" ile pozisyonlan.
- **Getir Finans / Investing.com TR**: Genel finans, portföy odağı zayıf.

### Farklılaşma noktan
1. **Türk kültürüne özel altın alt kategorileri** (Çeyrek/Yarım/Ata/Reşat/Cumhuriyet — kimsede yok)
2. **Partner paylaşımı** (aile portföyü konsepti — Türkiye'de eş/aile ortak yatırım yaygın)
3. **AI rapor Türkçe + TR piyasa bağlamı**
4. **Enflasyon karşılaştırma widget** (Faz 4 idea — "portföyün TÜFE'yi yendi mi?")

---

## 6. Uygulama Sırası — Bir Sonraki Oturumda Başlayacağın Adım

**Faz 0'dan başla — Analytics kurulumu.** Sıralı checklist:

1. [ ] `pubspec.yaml`'a `firebase_analytics: ^11.x` ve `firebase_remote_config: ^5.x` ekle
2. [ ] `flutter pub get`
3. [ ] Firebase Console'da Analytics'i aktif et (proje zaten var)
4. [ ] [lib/services/analytics_service.dart] oluştur — event enum + logEvent metodu
5. [ ] [lib/services/remote_config_service.dart] oluştur — flag getter'ları
6. [ ] Ana yerlerde event log'u ekle (min 5 event)
7. [ ] Test build al, Firebase DebugView'da event'leri doğrula
8. [ ] Commit + push

**Sonra Faz 1** — RevenueCat entegrasyonu (2 hafta plan). Ondan önce:
- App Store Connect'te subscription products oluştur (bu manuel iş, Apple'ın onayı gerekiyor, önden başlat)
- Google Play Console'da aynı ürünleri oluştur

---

## 7. Efor Tahmini

| Faz | Süre | Bağımlılık |
|-----|------|------------|
| Faz 0 (Analytics) | 3-5 gün | Yok |
| Faz 1 (IAP + Paywall) | 10-14 gün | Faz 0, Apple/Google subscription onayı (paralel) |
| Faz 2 (Premium features) | 12-18 gün | Faz 1 |
| Faz 3 (Engagement) | 8-12 gün | Faz 0 (analytics), opsiyonel Faz 1 |

**Toplam:** ~6-8 hafta full-focus. Yarı zamanlı çalışırsan 3-4 ay.

---

## 8. Ek Notlar

- **KVKK check:** Her yeni feature'da (özellikle AI rapor) aydınlatma metnini güncelle
- **App Store submission:** Subscription tanıtım metinlerini net yaz, "auto-renewal" bilgisini eksik bırakma (yaygın reddedilme sebebi)
- **Play Store subscription:** Google, subscription açıklamasında fiyatı net göstermeni istiyor
- **Refund policy:** Türkiye'de mesafeli satış → 14 gün cayma hakkı. Uygulamada da bahset.
- **Muhasebe:** Aylık gelir 5000₺'yi aşınca vergi mükellefiyeti başlıyor (2026 sınırı). Şahıs şirketi + KDV kaydı düşün.

---

**Son güncelleme:** 2026-07-09
**Sonraki oturum:** Faz 0 adım 1'den başla
