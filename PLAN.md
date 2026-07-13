# PortfoyTakip — Bug Fix & Yeni Özellik Planı

**Tarih:** 2026-07-05
**Durum:** Uygulama

## Gereksinimler

### 1. Varlıklar silinemiyor — BUG FIX (P0)
**Kök neden:** `AssetDetailScreen` içinde delete menüsü var ama uygulama varlığa tıklandığında bu ekrana değil `PerformanceScreen`'e gidiyor (bkz. home_screen.dart:71, charts_screen.dart:167, all_transactions_screen.dart:200). PerformanceScreen'de hiç sil butonu yok → kullanıcı silemiyor.

**Çözüm:**
- `PerformanceScreen` app-bar'ına PopupMenuButton ile "Sil" ekle
- Onay diyaloğu + `portfolioProvider.notifier.deleteAsset(asset.id)` + `Navigator.pop`
- Hata durumunda kullanıcıya SnackBar ile geri bildirim
- Bonus: `home_screen`'deki varlık listesinde `flutter_slidable` ile swipe-to-delete

### 2. Sinyal algoritma sayısı artırılabilir + in-app purchase
**Yaklaşım:**
- `TechnicalAnalysisService`'e 3 yeni gösterge ekle: **ADX**, **Williams %R**, **CCI** (Premium)
- `preferences_provider`'da `isPremium` flag'i (şimdilik SharedPreferences ile stub — gerçek IAP entegrasyonu ayrı iş)
- Premium olmayan kullanıcılara premium göstergeler kilitli ikon + "Premium'a Geç" CTA'sı
- Ödeme sağlayıcı entegrasyonu (`in_app_purchase` paketi) ileri fazada — şimdilik lokal toggle ile UX prototip

### 3. Kolay veri girişi — sesli komut
**Yaklaşım:**
- `AddAssetScreen`'e mikrofon butonu ekle
- `speech_to_text` paketi ekle (izinler: Android RECORD_AUDIO, iOS NSMicrophoneUsageDescription/NSSpeechRecognitionUsageDescription)
- Basit parse: "USDTRY 100 dolar 32 liradan" → doviz + USD + qty=100 + price=32
- İlk sürüm: sadece "miktar" ve "fiyat" alanlarını dolduran voice-to-text (basit rakam yakalama)

### 4. Al/Sat sinyalleri için yasal sınırlarda kal
**Yaklaşım:**
- Tüm sinyal gösterimlerine kalıcı legal footer ekle
  - "Bu içerik yatırım tavsiyesi değildir (SPK md. 25). Teknik analiz eğitim amaçlıdır."
- `SignalAlert` bildirimlerine bu metni ekle (kısaltılmış)
- `_TechnicalSignalPanel` içindeki `DisclaimerWidget` görünürlüğünü güçlendir (dismiss edilemez sabit banner)
- AL/SAT etiketlerini nötralize et → "Trend Yukarı / Aşağı / Yatay" gibi tanımlayıcı diller kullan (opsiyon)

### 5. Her gösterge için parametrik versiyon göster
**Yaklaşım:**
- Her `TechnicalIndicator.name`'a parametreleri açıkça yaz:
  - `RSI (14)`, `MACD (12,26,9)`, `Bollinger (20, 2σ)`, `EMA (20/50)`, `Stokastik %K(14)`
- `technical_analysis_service.dart` içindeki her metotta bu format'ı kullan
- `_TechnicalSignalPanel` UI'ında parametre subtitle olarak render

### 6. Her ürün kategorisi için hangi gösterge seçilebilsin
**Yaklaşım:**
- `preferences_provider`'a `Map<AssetType, Set<String>>` yeni state ekle
- Default: tüm göstergeler seçili
- Profil > Ayarlar altına "Sinyal Ayarları" ekranı ekle
- Her `AssetType` için checkbox listesi (hisse/fon/döviz/altın/emtia/diğer)
- `TechnicalAnalysisService.analyze` seçilenlere göre filtrele

---

## Uygulama Sırası

1. ✅ Plan dokümanını yaz (bu dosya)
2. 🔨 P0: Delete bug fix (PerformanceScreen'e sil butonu)
3. 🔨 P0: Legal disclaimer'ları sinyal ekranlarına ekle (item 4)
4. 🔨 Parametrik gösterge isimleri (item 5)
5. 🔨 Per-category gösterge seçimi (item 6)
6. 🔨 Premium sinyal gating (item 2 — IAP stub)
7. 🔨 Sesli veri girişi (item 3 — speech_to_text)
8. 🚀 Build + iki emülatöre deploy

---

## İzleme
Bu plan her önemli değişiklikten sonra güncellenecek. Tamamlanan maddeler ✅ ile işaretlenecek.

### İlerleme
- [x] Item 1 — Delete bug (PerformanceScreen popup menu → deleteAsset + SnackBar)
- [x] Item 2 — Premium sinyaller (ADX, Williams %R, CCI + `premiumUnlockedProvider` stub)
- [x] Item 3 — Sesli giriş (AddAssetScreen mic → parser: qty/price/type)
- [x] Item 4 — Legal disclaimer (DisclaimerWidget hem tepede hem altta; başlık AL/SAT → "YUKARI/AŞAĞI TREND"; bildirim metni sadeleşti)
- [x] Item 5 — Parametrik gösterge adları (RSI(14), MACD(12,26,9), Bollinger(20,2σ), EMA Kesişim(20/50), Stokastik %K(14) …)
- [x] Item 6 — Per-category gösterge seçimi (SignalSettingsScreen + indicatorPrefsProvider → SharedPreferences)

### Ek notlar
- `IndicatorId` enum-like class göstergeler için stable key sağlar (SharedPreferences persist için gerekli)
- Premium ID'ler `{adx, williams_r, cci}` — kilit UI'da lock ikonu ile gösterilir
- `analyze()` imzası artık `enabledIds` ve `premiumUnlocked` alıyor; caller'lar defaultlara geri düşer
- `summarize()` toplam gösterge sayısına göre oransal (≥%60) karar veriyor — değişken gösterge sayısını destekler
