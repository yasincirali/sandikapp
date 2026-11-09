import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'crash_reporter.dart';

/// Alarm listelerinin cihazdaki son kopyası (Ar-Ge 29 Eki 20:45 #3).
///
/// **Neden:** #257'den beri varlık şeridi, Portföy rozeti, takip çanı ve
/// varlık sayfası zili dört alarm listesini tek yerden okuyor. Liste
/// gelene kadar (soğuk açılışın ilk saniyeleri) ya da okuma hata verince
/// (zayıf mobil veri) alarm "yok" görünüyordu; kişi "silinmiş" sanıp
/// aynı alarmı ikinci kez kurabiliyordu.
///
/// **Ne:** her başarılı okumada ham satırlar kullanıcı anahtarlı yazılır.
/// Sağlayıcı açılışta önce bu kopyayı gösterir, sunucudan gelince yerine
/// koyar; okuma hatasında son bilinen kopya kalır ve [bayat] yanar
/// (Alarmlarım "Güncellenemedi" satırı). Kurma/silme yine yalnız sunucu
/// yanıtıyla: kopya yalnız okunur, sunucuya hiçbir şey ondan yazılmaz.
///
/// Oturum kapanınca [temizle] (`PortfolioCache` ile aynı kural: aynı
/// cihazdaki bir sonraki hesap öncekinin alarmlarını görmez).
class AlarmOnbellegi {
  AlarmOnbellegi._();

  static const _onek = 'alarm_onbellek_v1_';

  static String _anahtar(String tablo, String uid) => '$_onek${tablo}_$uid';

  /// Son okuma sunucudan gelemedi, ekrandaki liste cihazdaki kopya.
  static final ValueNotifier<bool> bayat = ValueNotifier(false);

  /// Cihazdaki kopya; hiç yazılmadıysa ya da okunamazsa `null`.
  static Future<List<Map<String, dynamic>>?> oku(
      String tablo, String uid) async {
    try {
      final p = await SharedPreferences.getInstance();
      final ham = p.getString(_anahtar(tablo, uid));
      if (ham == null) return null;
      return [
        for (final r in jsonDecode(ham) as List)
          (r as Map).cast<String, dynamic>(),
      ];
    } catch (e, st) {
      // Bozuk kopya: yokmuş gibi davranılır, sunucu yolu sürer.
      CrashReporter.report(e, st, reason: 'AlarmOnbellegi.oku');
      return null;
    }
  }

  static Future<void> _yaz(
      String tablo, String uid, List<Map<String, dynamic>> satirlar) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(_anahtar(tablo, uid), jsonEncode(satirlar));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AlarmOnbellegi.yaz');
    }
  }

  /// Sunucu okuması [sec]; başarıda kopyayı yazar. Hata verirse ve kopya
  /// varsa onu döndürür (hata Crashlytics'e gider, [bayat] yanar); kopya
  /// yoksa hatayı olduğu gibi fırlatır, çağıranın bugünkü kuralı geçerli.
  static Future<List<Map<String, dynamic>>> secOnbellekli(
    String tablo,
    String uid,
    Future<List<Map<String, dynamic>>> Function() sec,
  ) async {
    try {
      final satirlar = await sec();
      await _yaz(tablo, uid, satirlar);
      bayat.value = false;
      return satirlar;
    } catch (e, st) {
      final kopya = await oku(tablo, uid);
      if (kopya == null) rethrow;
      CrashReporter.report(e, st, reason: 'AlarmOnbellegi.$tablo');
      bayat.value = true;
      return kopya;
    }
  }

  /// Kurma/güncelleme sunucudan döndü: o satır kopyada yerine konur (yoksa
  /// başa eklenir). Kopya yalnız okuma anında yazılsaydı, yeni kurulan
  /// alarm bir sonraki çevrimdışı açılışta yine "kaybolmuş" görünürdü.
  static Future<void> satirYaz(String tablo, Map<String, dynamic> satir) =>
      _degistir(tablo, (liste) {
        final i = liste.indexWhere((r) => r['id'] == satir['id']);
        if (i >= 0) {
          liste[i] = satir;
        } else {
          liste.insert(0, satir);
        }
      }, uid: satir['user_id']?.toString());

  /// Sunucu yalnız başarı döndürdü (gövdesiz güncelleme): alanlar yamalanır.
  static Future<void> satirYamala(
          String tablo, String id, Map<String, dynamic> yama) =>
      _degistir(tablo, (liste) {
        final i = liste.indexWhere((r) => r['id'] == id);
        if (i >= 0) liste[i] = {...liste[i], ...yama};
      });

  /// Silme sunucudan döndü: satır kopyadan da çıkar.
  static Future<void> satirSil(String tablo, String id) =>
      _degistir(tablo, (liste) => liste.removeWhere((r) => r['id'] == id));

  /// [uid] bilinmiyorsa o tablonun tüm kopyalarına uygulanır (silme ve
  /// yamada yalnız `id` elde; kimlik benzersiz, başka hesabın kopyasında
  /// eşleşmez).
  static Future<void> _degistir(
      String tablo, void Function(List<Map<String, dynamic>>) islem,
      {String? uid}) async {
    try {
      final p = await SharedPreferences.getInstance();
      final anahtarlar = uid != null
          ? [_anahtar(tablo, uid)]
          : p.getKeys().where((k) => k.startsWith('$_onek${tablo}_')).toList();
      for (final k in anahtarlar) {
        final ham = p.getString(k);
        // Kopya hiç yazılmadıysa (ilk okuma gelmemiş) uydurulmaz.
        if (ham == null) continue;
        final liste = [
          for (final r in jsonDecode(ham) as List)
            (r as Map).cast<String, dynamic>(),
        ];
        islem(liste);
        await p.setString(k, jsonEncode(liste));
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AlarmOnbellegi.degistir');
    }
  }

  /// Oturum kapanışı: tüm alarm kopyaları silinir.
  static Future<void> temizle() async {
    try {
      final p = await SharedPreferences.getInstance();
      for (final k in p.getKeys().where((k) => k.startsWith(_onek)).toList()) {
        await p.remove(k);
      }
      bayat.value = false;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'AlarmOnbellegi.temizle');
    }
  }
}
