import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'crash_reporter.dart';
import 'secure_session_storage.dart' show SessionVault;
import 'sunucu_secimi.dart';

/// Cihazda oturumu saklı duran bir hesap (çoklu hesap, bayrak `coklu_hesap`).
///
/// Oturumun KENDİSİ burada değil, [HesapKasasi]'nda ayrı anahtarda durur:
/// liste ekranda gösterilir, oturum yalnızca geçişte okunur.
class KayitliHesap {
  final String uid;
  final String eposta;

  /// Seçicide görünen ad: kullanıcı adı, yoksa görünen ad.
  final String ad;
  final DateTime sonKullanim;

  /// Saklı oturum sunucuda geçersiz (başka telefonda açıldı, şifre
  /// değişti…). Listeden silinmez — kullanıcı tekrar girer ya da kaldırır.
  final bool oturumDustu;

  const KayitliHesap({
    required this.uid,
    required this.eposta,
    required this.ad,
    required this.sonKullanim,
    this.oturumDustu = false,
  });

  /// Avatar harfi — Türkçe büyük harf (i → İ).
  String get basHarf {
    final kaynak = ad.trim().isNotEmpty ? ad.trim() : eposta.trim();
    if (kaynak.isEmpty) return '?';
    final ilk = kaynak.substring(0, 1);
    if (ilk == 'i') return 'İ';
    if (ilk == 'ı') return 'I';
    return ilk.toUpperCase();
  }

  KayitliHesap kopya({
    String? eposta,
    String? ad,
    DateTime? sonKullanim,
    bool? oturumDustu,
  }) =>
      KayitliHesap(
        uid: uid,
        eposta: eposta ?? this.eposta,
        ad: ad ?? this.ad,
        sonKullanim: sonKullanim ?? this.sonKullanim,
        oturumDustu: oturumDustu ?? this.oturumDustu,
      );

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'eposta': eposta,
        'ad': ad,
        'son': sonKullanim.toUtc().toIso8601String(),
        'dustu': oturumDustu,
      };

  static KayitliHesap? fromJson(Object? j) {
    if (j is! Map) return null;
    final uid = j['uid'];
    if (uid is! String || uid.isEmpty) return null;
    return KayitliHesap(
      uid: uid,
      eposta: (j['eposta'] as String?) ?? '',
      ad: (j['ad'] as String?) ?? '',
      sonKullanim:
          DateTime.tryParse((j['son'] as String?) ?? '')?.toLocal() ??
              DateTime.fromMillisecondsSinceEpoch(0),
      oturumDustu: j['dustu'] == true,
    );
  }
}

class _GuvenliKasa implements SessionVault {
  static const _s = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _s.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _s.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _s.delete(key: key);
}

/// Cihazdaki hesapların listesi ve her birinin saklı Supabase oturumu.
///
/// ## Neden Keychain/Keystore
/// Saklı oturum = yenileme anahtarı; aktif oturumla AYNI hassasiyette
/// (`SecureSessionStorage` gerekçesi, 2026-09 M2). SharedPreferences'a
/// yazılsaydı yedekten/adb'den okunup hesap başka cihazda sürdürülebilirdi.
///
/// ## Neden anahtar sunucuya göre ayrı
/// Tokyo ve Frankfurt ayrı GoTrue'dur; birinin oturumu ötekinde geçersiz.
/// `SunucuSecimi` sunucu değiştirirse eski sunucunun hesap listesi görünmez
/// (aktif oturum anahtarıyla aynı kural, `defaultKeyFor`).
///
/// ## Sınır
/// [enCok] hesap (Instagram ile aynı, 5). Sunucudaki ek push satırı sınırı
/// da 5'tir (0137).
class HesapKasasi {
  HesapKasasi({
    @visibleForTesting SessionVault? kasa,
    @visibleForTesting String? onEk,
  })  : _kasa = kasa ?? _GuvenliKasa(),
        _onEkSabit = onEk;

  static final HesapKasasi instance = HesapKasasi();

  static const int enCok = 5;

  final SessionVault _kasa;
  final String? _onEkSabit;

  String get _onEk =>
      _onEkSabit ?? 'sandik_${SunucuSecimi.instance.aktifOrNull?.ref ?? 'yerel'}';
  String get _listeAnahtari => '${_onEk}_hesaplar_v1';
  String _oturumAnahtari(String uid) => '${_onEk}_hesap_oturumu_v1_$uid';

  /// Son kullanılan en üstte.
  Future<List<KayitliHesap>> liste() async {
    try {
      final ham = await _kasa.read(_listeAnahtari);
      if (ham == null || ham.isEmpty) return const [];
      final j = jsonDecode(ham);
      if (j is! List) return const [];
      final l = [
        for (final e in j)
          if (KayitliHesap.fromJson(e) case final h?) h,
      ];
      l.sort((a, b) => b.sonKullanim.compareTo(a.sonKullanim));
      return l;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.liste');
      return const [];
    }
  }

  Future<void> _listeyiYaz(List<KayitliHesap> l) async {
    await _kasa.write(
        _listeAnahtari, jsonEncode([for (final h in l) h.toJson()]));
  }

  /// Hesabı ekler ya da günceller; [oturumJson] verilirse oturumu da yazar.
  ///
  /// Sınır dolu ve hesap listede yoksa `false` döner (yazılmaz).
  Future<bool> kaydet(KayitliHesap hesap, {String? oturumJson}) async {
    try {
      final l = [...await liste()];
      final i = l.indexWhere((h) => h.uid == hesap.uid);
      if (i < 0 && l.length >= enCok) return false;
      if (i < 0) {
        l.add(hesap);
      } else {
        l[i] = hesap;
      }
      if (oturumJson != null) {
        await _kasa.write(_oturumAnahtari(hesap.uid), oturumJson);
      }
      await _listeyiYaz(l);
      return true;
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.kaydet');
      return false;
    }
  }

  /// Yalnız oturumu tazeler (yenileme anahtarı her yenilemede döner —
  /// rotation açık, `config.toml`). Hesap listede yoksa yazmaz: kasa,
  /// kullanıcının eklemediği bir hesabı kendiliğinden tutmamalı.
  Future<void> oturumuTazele(String uid, String oturumJson) async {
    try {
      final l = await liste();
      if (!l.any((h) => h.uid == uid)) return;
      await _kasa.write(_oturumAnahtari(uid), oturumJson);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.oturumuTazele');
    }
  }

  Future<String?> oturum(String uid) async {
    try {
      return await _kasa.read(_oturumAnahtari(uid));
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.oturum');
      return null;
    }
  }

  Future<void> isaretle(String uid, {required bool oturumDustu}) async {
    try {
      final l = [...await liste()];
      final i = l.indexWhere((h) => h.uid == uid);
      if (i < 0) return;
      l[i] = l[i].kopya(oturumDustu: oturumDustu);
      if (oturumDustu) await _kasa.delete(_oturumAnahtari(uid));
      await _listeyiYaz(l);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.isaretle');
    }
  }

  /// Hesabı ve saklı oturumunu cihazdan siler.
  Future<void> sil(String uid) async {
    try {
      final l = [...await liste()]..removeWhere((h) => h.uid == uid);
      await _kasa.delete(_oturumAnahtari(uid));
      await _listeyiYaz(l);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.sil');
    }
  }

  Future<void> hepsiniSil() async {
    for (final h in await liste()) {
      try {
        await _kasa.delete(_oturumAnahtari(h.uid));
      } catch (_) {}
    }
    try {
      await _kasa.delete(_listeAnahtari);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'HesapKasasi.hepsiniSil');
    }
  }
}

/// Bir hesaptan çıkılınca sıradaki hesap: oturumu düşmemiş, en son
/// kullanılan. Yoksa `null` (giriş ekranı). Saf — test edilir.
KayitliHesap? siradakiHesap(List<KayitliHesap> liste, String cikanUid) {
  final adaylar = [
    for (final h in liste)
      if (h.uid != cikanUid && !h.oturumDustu) h,
  ]..sort((a, b) => b.sonKullanim.compareTo(a.sonKullanim));
  return adaylar.isEmpty ? null : adaylar.first;
}
