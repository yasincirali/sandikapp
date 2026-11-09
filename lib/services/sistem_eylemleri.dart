import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/asset.dart';
import '../models/position.dart';
import '../models/varlik_kimligi.dart';
import 'crash_reporter.dart';
import 'hizli_eylemler.dart';
import 'notification_service.dart';

/// Siri Kestirmeleri ve Spotlight'ın Dart ucu (2026-10-19, iOS).
///
/// ## Neden
/// yasin (Ar-Ge fikir turu 1): "arkadaşını getir dışındakileri uygula".
/// İkon kısayolları (#219) ilk adımdı; bu dosya aynı işi Siri cümlesine ve
/// Spotlight aramasına açar. Swift ucu `ios/Runner/SistemEylemleri.swift`.
///
/// ## Yönlendirme tek yoldan
/// Siri'nin "varlık ekle / alarm kur / ara" eylemleri ikon kısayoluyla AYNI
/// isteğe (`HizliEylemler.istek`) düşer; Spotlight'ta bir varlığa dokunmak
/// derin bağlantıyla AYNI hedefe (`openAssetPerformance`) gider. İkisi de
/// kilidi atlatmaz (kabuk / `kilitKapisi` bekletir). Yeni bir gezinme yolu
/// kurulmadı.
///
/// ## Spotlight'a ne yazılır
/// Yalnız açık pozisyonların adı ve sembolü — tutar YOK. Uygulama kilidi
/// açıksa hiçbir şey yazılmaz ve dizin silinir: kilit isteyen kişi
/// varlıklarının adının bile kilitsiz arama ekranında çıkmasını istemez.
/// Oturum kapanınca da silinir (aynı cihazda başka hesap açılabilir).
class SistemEylemleri {
  SistemEylemleri._();

  static const _kanal = MethodChannel('com.sandik.app/sistem_eylemleri');
  static const varlikOnek = 'varlik:';

  static bool _kuruldu = false;

  /// Son yazılan Spotlight imzası: portföy dakikada birkaç kez yayınlanır,
  /// dizin yalnız liste değişince yeniden yazılır.
  static String? _sonImza;

  static bool get _destekli => !kIsWeb && Platform.isIOS;

  /// Kanalı dinler ve soğuk açılışta bırakılmış eylemi alır.
  static Future<void> baslat() async {
    if (!_destekli || _kuruldu) return;
    _kuruldu = true;
    _kanal.setMethodCallHandler((call) async {
      if (call.method == 'geldi') await cek();
    });
    await cek();
  }

  /// Bekleyen eylemi tüketir. Öne dönüşte de çağrılır: Siri eylemi uygulama
  /// arkadayken bırakılmış olabilir.
  static Future<void> cek() async {
    if (!_destekli) return;
    try {
      final e = await _kanal.invokeMethod<String>('al');
      final h = cozumle(e);
      switch (h) {
        case SistemEylemiVarlik(:final id):
          NotificationService.instance.openAssetPerformance(
            id,
            // Spotlight dizini eski olabilir (varlık başka cihazda silindi):
            // dokunan kişiye hiçbir şey olmaması "bozuk" hissi verir.
            onNotFound: NotificationService.instance.showAssetNotFound,
          );
        case SistemEylemiKisayol(:final eylem):
          HizliEylemler.istek.value = eylem;
        case null:
          break;
      }
    } catch (e, st) {
      CrashReporter.report(e, st, reason: 'SistemEylemleri.cek');
    }
  }

  /// Swift'in bıraktığı metni hedefe çevirir (saf; test edilir).
  static SistemEylemi? cozumle(String? ham) {
    if (ham == null || ham.isEmpty) return null;
    if (ham.startsWith(varlikOnek)) {
      final id = ham.substring(varlikOnek.length);
      return id.isEmpty ? null : SistemEylemiVarlik(id);
    }
    final k = HizliEylemler.cozumle(ham);
    return k == null ? null : SistemEylemiKisayol(k);
  }

  /// Spotlight'a yazılacak öğeler (saf; test edilir): kullanıcının KENDİ açık
  /// pozisyonları, varlık başına bir öğe, kimlik o varlığın ilk alış lotu
  /// (`openAssetPerformance` lot id'siyle açar). Ortak (partner) lotları
  /// girmez: aranınca başkasının pozisyonu açılmasın.
  @visibleForTesting
  static List<Map<String, String>> spotlightOgeleri(
      Iterable<Asset> assets, String userId) {
    final gorulen = <String>{};
    final ogeler = <Map<String, String>>[];
    for (final a in aktifLotlar(assets.where((a) => a.userId == userId))) {
      if (!a.isBuy) continue;
      final anahtar = varlikAnahtari(
          type: a.type, ticker: a.ticker, subCategory: a.subCategory);
      if (!gorulen.add(anahtar)) continue;
      final ad = a.name.trim();
      final sembol = a.ticker.trim();
      final baslik = ad.isNotEmpty ? ad : sembol;
      if (baslik.isEmpty) continue;
      ogeler.add({
        'id': a.id,
        'baslik': baslik,
        if (sembol.isNotEmpty) 'sembol': sembol,
        'aciklama': (sembol.isNotEmpty && sembol != baslik)
            ? '$sembol · Sandık'
            : 'Sandık',
      });
    }
    return ogeler;
  }

  /// Dizini o anki portföye eşitler; [userId] null ya da [kilitli] ise siler.
  static Future<void> spotlightEsitle({
    required Iterable<Asset>? assets,
    required String? userId,
    required bool kilitli,
  }) async {
    if (!_destekli) return;
    final ogeler = (assets == null || userId == null || kilitli)
        ? const <Map<String, String>>[]
        : spotlightOgeleri(assets, userId);
    final imza = ogeler.map((o) => '${o['id']}|${o['baslik']}').join(';');
    if (imza == _sonImza) return;
    _sonImza = imza;
    try {
      if (ogeler.isEmpty) {
        await _kanal.invokeMethod<void>('spotlightTemizle');
      } else {
        await _kanal.invokeMethod<void>('spotlightYaz', ogeler);
      }
    } catch (e, st) {
      _sonImza = null; // bir sonraki yayında yeniden dene
      CrashReporter.report(e, st, reason: 'SistemEylemleri.spotlight');
    }
  }
}

/// Swift'ten gelen bekleyen eylemin hedefi.
sealed class SistemEylemi {
  const SistemEylemi();
}

/// Spotlight'ta dokunulan varlık.
class SistemEylemiVarlik extends SistemEylemi {
  const SistemEylemiVarlik(this.id);
  final String id;
}

/// Siri'nin uygulamayı açan eylemi — ikon kısayoluyla aynı istek.
class SistemEylemiKisayol extends SistemEylemi {
  const SistemEylemiKisayol(this.eylem);
  final HizliEylem eylem;
}
