import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/pref_keys.dart';
import '../config/surum_notlari.dart';

/// "Yenilikler" ekranının kararını veren servis.
///
/// Soru: kullanıcı bu açılışta sürüm notunu görmeli mi, görecekse hangi
/// sürümlerin notunu? Karar iki girdiye dayanır — ÇALIŞAN sürüm (paketten)
/// ve kullanıcının en son gördüğü sürüm (`shared_preferences`).
///
/// **Neden sürüm paketten okunuyor:** `pubspec.yaml`'daki değer CI'da
/// fastlane tarafından bump ediliyor ve uygulama içinde elle yazılan bir
/// sabit bayatlıyor — Ayarlar ekranı buna bir örnekti, gerçek sürüm 1.1.4
/// iken "sürüm 1.0.0" yazıyordu. `PackageInfo` her zaman gerçekten kurulu
/// olanı söyler.
class SurumNotuService {
  SurumNotuService._();
  static final SurumNotuService instance = SurumNotuService._();

  String? _surumCache;

  /// Çalışan uygulamanın sürümü ('1.2.0'), build numarası olmadan.
  Future<String> calisanSurum() async {
    final cached = _surumCache;
    if (cached != null) return cached;
    final info = await PackageInfo.fromPlatform();
    _surumCache = info.version;
    return info.version;
  }

  /// Bu açılışta gösterilecek notlar — boşsa gösterilecek bir şey yok.
  ///
  /// [otomatikAcilis] true ise ("uygulama yeni açıldı") yalnızca
  /// [SurumNotu.onemli] sürümler döner: yama sürümleri için kullanıcının
  /// önüne modal koymak, üçüncü seferde kapatılan bir şeye dönerdi.
  /// Ayarlar'dan elle açıldığında ([otomatikAcilis] false) tüm liste döner.
  Future<List<SurumNotu>> gosterilecekler({
    bool otomatikAcilis = true,
  }) async {
    final surum = await calisanSurum();
    final prefs = await SharedPreferences.getInstance();
    final gorulen = prefs.getString(PrefKeys.sonGorulenSurumNotu);

    if (!otomatikAcilis) return surumNotlari;

    return yeniNotlar(
      notlar: surumNotlari,
      calisanSurum: surum,
      sonGorulen: gorulen,
    );
  }

  /// Kullanıcı notları gördü — bu sürüm bir daha otomatik açılmaz.
  Future<void> goruldu() async {
    final surum = await calisanSurum();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(PrefKeys.sonGorulenSurumNotu, surum);
  }

  /// Test/geliştirme için: işareti sil, not yeniden açılsın.
  Future<void> sifirla() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(PrefKeys.sonGorulenSurumNotu);
  }
}

/// Otomatik açılışta gösterilecek notları seçer — **saf fonksiyon**.
///
/// Kurallar ve her birinin gerekçesi:
///
/// 1. **Çalışan sürümün notu listede yoksa hiçbir şey gösterilmez.** Not
///    yazmayı unutmuş olabiliriz; boş ya da yanlış sürümün notunu göstermek
///    yanlış bilgi vermekten kötüdür.
/// 2. **İlk kurulumda gösterilmez** ([sonGorulen] null). Yeni kullanıcı
///    zaten tanıtım turunu görüyor; üstüne "yenilikler" koymak, hiç
///    kullanmadığı bir şeyin neyinin değiştiğini anlatmak olurdu.
/// 3. **Aynı sürüm ikinci kez gösterilmez.**
/// 4. **Atlanan sürümler birikir:** kullanıcı 1.0'dan 1.2'ye atladıysa
///    1.1 ve 1.2'nin notları birlikte gösterilir — aradaki sürümü hiç
///    açmamış olması o yenilikleri görmemesi anlamına gelmemeli.
/// 5. **Yalnızca `onemli` olanlar otomatik açar.** Araya giren yama
///    sürümlerinin notu listede kalır ama modal açmaz.
List<SurumNotu> yeniNotlar({
  required List<SurumNotu> notlar,
  required String calisanSurum,
  required String? sonGorulen,
}) {
  // (1) Çalışan sürümün notu yazılmamışsa sus.
  final calisanIndex = notlar.indexWhere((n) => n.surum == calisanSurum);
  if (calisanIndex < 0) return const [];

  // (2) İlk kurulum.
  if (sonGorulen == null) return const [];

  // (3) Aynı sürüm.
  if (sonGorulen == calisanSurum) return const [];

  // Kullanıcının en son gördüğü sürüm listede yoksa (o sürümün notu hiç
  // yazılmamış, ya da kayıt bozuk/downgrade) "son görülene kadar topla"
  // döngüsü TÜM GEÇMİŞİ döndürürdü. Bu durumda yalnızca çalışan sürümü
  // göstermek doğru: eskiyi bilmiyoruz, uydurmuyoruz.
  //
  // Bu kontrol birikim döngüsünden ÖNCE gelmeli — sonra gelirse döngü
  // zaten yanlış listeyi kurmuş olur.
  final sonGorulenVar = notlar.any((n) => n.surum == sonGorulen);
  if (!sonGorulenVar) {
    return notlar[calisanIndex].onemli ? [notlar[calisanIndex]] : const [];
  }

  // (4) Son görülenden bu yana çıkanlar. Liste en yeni önce sıralı:
  // çalışan sürümden başla, son görülene kadar geriye topla.
  final birikmis = <SurumNotu>[];
  for (var i = calisanIndex; i < notlar.length; i++) {
    if (notlar[i].surum == sonGorulen) break;
    birikmis.add(notlar[i]);
  }

  // (5) Hiçbiri önemli değilse otomatik açma.
  if (!birikmis.any((n) => n.onemli)) return const [];
  return birikmis;
}
