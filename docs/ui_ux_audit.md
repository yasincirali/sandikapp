# Flutter iOS UI/UX Analiz ve İyileştirme Görevi

## 🎯 Hedef
Bu projedeki Flutter UI bileşenlerini taramak, iOS (Apple HIG - Human Interface Guidelines) standartlarına uygunluğunu detaylıca irdelemek ve eyleme geçirilebilir bir iyileştirme planı (kod örnekleriyle) sunmak.

## 🔍 Adım 1: Tarama ve Veri Toplama
Lütfen aşağıdaki adımları sırasıyla uygula:
1. `lib/screens`, `lib/widgets`, `lib/core/ui` ve `lib/theme` klasörlerindeki (ya da projedeki eşdeğer UI) dosyaları analiz et.
2. Projede kullanılan state yapılarını, butonları, listeleri (ListView/Sliver), form elemanlarını ve navigasyon kurgusunu tespit et.
3. Terminalde `flutter analyze` komutunu çalıştır ve varsa UI ile ilgili uyarıları hafızana al.

## 🧠 Adım 2: UI/UX İrdeleme Kriterleri (iOS Odaklı)
Bileşenleri şu kriterlere göre katı bir şekilde değerlendir:
- **Dokunma Alanları (Tap Targets):** Etkileşimli elemanlar iOS standardı olan minimum 44x44 pt kuralına uyuyor mu? (Örn: IconButton'ların `splashRadius` veya boyutları).
- **Safe Area & Çentik:** Dynamic Island, alt Home Indicator ve çentikli ekranlar için `SafeArea` doğru/gerektiği gibi konumlandırılmış mı?
- **Navigasyon ve Hissiyat:** iOS geri dönüş (swipe-to-go-back) kurgusunu engelleyen `WillPopScope` hataları var mı? Platforma uygun geçiş animasyonları (Cupertino transition) kullanılıyor mu?
- **Bileşen Uygunluğu (Suitability):** Material widget'lar (örneğin Android tarzı dalgalanma efekti - InkWell) iOS'ta sırıtıyor mu? Bunların yerine adaptif veya platforma nötr tasarımlar yapılmış mı?
- **Temalandırma (Theming):** Renk, padding ve font büyüklükleri kodun içine "hardcoded" olarak mı yazılmış, yoksa merkezi bir `ThemeData` üzerinden mi yönetiliyor?

## 📝 Adım 3: Çıktı Formatı (Raporlama)
İncelemen bittiğinde bana kesinlikle aşağıdaki yapıda bir rapor sun:

### 1. 🛑 Tespit Edilen Kritik UI/UX Hataları
*(Dosya adı ve satır numarası belirterek, bileşenin iOS standartlarına neden uymadığını açıkla.)*

### 2. ⚖️ Komponent Uygunluk Analizi
*(Hangi bileşenler çok karmaşık? Hangileri mobil ekranı yoruyor? Görsel hiyerarşi problemleri neler?)*

### 3. ✅ İyileştirme ve Yeniden Yazım Planı (Actionable Plan)
*(Bana adım adım, hangi dosyada neyi değiştirmem gerektiğini söyle. Önemli düzeltmeler için optimize edilmiş Flutter / Dart kod bloklarını doğrudan paylaş.)*