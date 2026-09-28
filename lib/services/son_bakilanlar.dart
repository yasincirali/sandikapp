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
/// Fiyat TUTULMAZ — yalnızca kimlik. Eski bir fiyatı "son baktığın" diye
/// göstermek uydurma sayı olurdu (fiyat kaynağı sözleşmesi); satır fiyatı
/// ekranda o an çekilir.
class SonBakilanlar {
  SonBakilanlar._();
  static final instance = SonBakilanlar._();

  static const enFazla = 8;
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
