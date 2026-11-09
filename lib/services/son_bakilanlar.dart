import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/asset_type.dart';
import '../models/varlik_kimligi.dart';
import 'crash_reporter.dart';

/// "Son baktıkların" — arama ekranının boş hâlinde gösterilen, kullanıcının
/// yakın zamanda varlık sayfasını açtığı varlıklar.
///
/// ## Kararlar (kullanıcı onayı, 2026-09-28 arama tasarımı)
/// - **Yalnızca cihazda.** Hesaba senkron sunucu ister (tablo + RLS); ilk
///   sürümde gerekmiyor. Anahtar kullanıcı kimliğiyle ayrılır: aynı cihazda
///   başka hesaba geçen biri öncekinin baktıklarını görmez.
/// - **En çok [enFazla].** Liste bir geçmiş değil, kısayol; uzadıkça aranan
///   şey kaybolur.
/// - **Temizlenebilir.** Kullanıcının neye baktığı kişisel bir iz.
///
/// ## Genel arama (2026-10-26)
/// Genel aramanın boş hâli de aynı listeyi gösterir — ikinci bir depo
/// yazılmadı; kayıt yine tek noktada (`VarlikSayfasi.initState`, dört giriş
/// noktasının ortak yeri). Orada en çok [gosterimSiniri] satır, takipteki
/// ve portföydeki varlıklar SÜZÜLÜR ([gorunenler]): onların kendi yüzeyi
/// var, kısayol listesinde yer kaplamasınlar. Depo sınırı [enFazla] olarak
/// kalır ki süzülenler beşi eritmesin. Satır başına kaldırma [kaldir];
/// ayrı "Temizle" düğmesi orada yok (takibe alma ekranında var, kalır).
/// - **Çıkışta silinir** ([sil]): oturum kapanınca ve hesap cihazdan
///   kaldırılınca o hesabın listesi diskte kalmaz (çevrimdışı defterle aynı
///   kural). Hesaplar arası geçişte silinmez; her hesap kendi listesini görür.
///
/// Fiyat TUTULMAZ — yalnızca kimlik. Eski bir fiyatı "son baktığın" diye
/// göstermek uydurma sayı olurdu (fiyat kaynağı sözleşmesi); satır fiyatı
/// ekranda o an çekilir.
class SonBakilanlar {
  SonBakilanlar._();
  static final instance = SonBakilanlar._();

  static const enFazla = 8;

  /// Genel aramanın "Son baktıkların" bölümünde en çok kaç satır.
  static const gosterimSiniri = 5;
  static String _anahtar(String kullaniciId) => 'son_bakilanlar_v1_$kullaniciId';

  /// Yüklenmiş liste — en yeni başta. Ekran bunu dinler.
  final liste = ValueNotifier<List<VarlikKimligi>>(const []);
  String? _yuklenen;

  Future<void> yukle(String kullaniciId) async {
    if (_yuklenen == kullaniciId) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ham = prefs.getString(_anahtar(kullaniciId));
      _yuklenen = kullaniciId;
      liste.value = ham == null ? const [] : cozumle(ham);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SonBakilanlar.yukle');
    }
  }

  /// [k]'yı başa alır; aynı varlık tekrar eklenmez, yukarı taşınır.
  Future<void> kaydet(String kullaniciId, VarlikKimligi k) async {
    await yukle(kullaniciId);
    liste.value = ekle(liste.value, k);
    await _yaz(kullaniciId);
  }

  /// Tek satırı listeden çıkarır (genel aramada kaydır / özel eylem).
  Future<void> kaldir(String kullaniciId, VarlikKimligi k) async {
    await yukle(kullaniciId);
    liste.value = cikar(liste.value, k);
    await _yaz(kullaniciId);
  }

  /// Hesabın kaydını diskten siler (çıkış, hesabı cihazdan kaldırma).
  /// Bellekteki liste o hesabınsa boşalır; bir sonraki [yukle] diski okur.
  Future<void> sil(String kullaniciId) async {
    if (_yuklenen == kullaniciId) {
      _yuklenen = null;
      liste.value = const [];
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_anahtar(kullaniciId));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SonBakilanlar.sil');
    }
  }

  Future<void> temizle(String kullaniciId) async {
    liste.value = const [];
    await _yaz(kullaniciId);
  }

  Future<void> _yaz(String kullaniciId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_anahtar(kullaniciId), kodla(liste.value));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SonBakilanlar.yaz');
    }
  }

  /// Saf ekleme kuralı — test edilir.
  @visibleForTesting
  static List<VarlikKimligi> ekle(List<VarlikKimligi> once, VarlikKimligi k) =>
      [k, ...once.where((o) => o.key != k.key)].take(enFazla).toList();

  @visibleForTesting
  static List<VarlikKimligi> cikar(List<VarlikKimligi> once, VarlikKimligi k) =>
      [for (final o in once) if (o.key != k.key) o];

  /// Genel aramada görünenler: [haric] anahtarları (takip + bugünkü
  /// portföy, `VarlikKimligi.key` kuralı) süzülür, sonra ilk [enFazlaSatir].
  /// Sıra korunur (en yeni başta). Saf — test edilir.
  static List<VarlikKimligi> gorunenler(
    List<VarlikKimligi> l,
    Set<String> haric, {
    int enFazlaSatir = gosterimSiniri,
  }) =>
      l.where((k) => !haric.contains(k.key)).take(enFazlaSatir).toList();

  @visibleForTesting
  static String kodla(List<VarlikKimligi> l) => jsonEncode([
        for (final k in l)
          {
            't': k.ticker,
            'n': k.name,
            'y': k.type.name,
            if (k.subCategory != null) 's': k.subCategory,
            'c': k.currency,
          }
      ]);

  /// Bozuk ya da tanınmayan tür içeren kayıt atlanır — sürüm değişince
  /// eski bir tür adı listeyi bütünüyle düşürmesin.
  @visibleForTesting
  static List<VarlikKimligi> cozumle(String ham) {
    try {
      final l = jsonDecode(ham);
      if (l is! List) return const [];
      final turler = AssetType.values.asNameMap();
      return [
        for (final e in l)
          if (e is Map &&
              e['t'] is String &&
              e['n'] is String &&
              turler[e['y']] != null)
            VarlikKimligi(
              ticker: e['t'] as String,
              name: e['n'] as String,
              type: turler[e['y']]!,
              subCategory: e['s'] as String?,
              currency: (e['c'] as String?) ?? 'TRY',
            ),
      ].take(enFazla).toList();
    } catch (_) {
      return const [];
    }
  }

  @visibleForTesting
  void sifirlaTest() {
    _yuklenen = null;
    liste.value = const [];
  }
}
