import 'analytics_service.dart';

/// Hangi ayara dokunulduğunun sayımı (Ar-Ge 21 Eki 08:45 #2; yasin
/// "şerh düştüklerim dışında yap", 2026-10-21).
///
/// ## Neden
/// Ekran ölçümü (`EkranOlcumu`) Ayarlar'ın açıldığını görür, içindeki
/// satırları görmez. 19 Kasım karar turu "hiç değiştirilmeyen ayar"
/// listesini bu olaydan çıkarır; Ayarlar'ı kısaltma kararı tahmine değil
/// sayıya dayanır.
///
/// ## Ne gönderilir
/// Yalnız anahtarın GÖVDESİ (kişiye özel önek eklenmeden önceki ad), değer
/// asla. Aynı anahtar oturum başına bir kez: kaydırıcı ya da hızlı aç-kapa
/// olay yağdırmasın (müşteri raporu 21 Eki 09:15).
abstract final class AyarOlcumu {
  static final Set<String> _sayilan = {};

  static void degisti(String anahtar) {
    if (!_sayilan.add(anahtar)) return;
    AnalyticsService.instance.logAyarDegisti(anahtar);
  }

  /// Testte oturum belleğini sıfırlamak için.
  static void sifirlaTest() => _sayilan.clear();

  /// Bu oturumda sayılan anahtarlar (test).
  static Set<String> get sayilanlar => Set.unmodifiable(_sayilan);
}
