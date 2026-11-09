import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/destek.dart';
import '../utils/friendly_error.dart';
import 'crash_reporter.dart';

/// Hata ekranındaki "Sorun sürüyorsa bize yaz" e-postası (2026-10-24, rapor
/// 2026-10-24_2115 §2).
///
/// ## Gövdede NE VAR, ne YOK
/// Yalnız dört bilgi: sürüm + build, platform, ekran adı, hata SINIFI
/// ([hataSinifi]). Hata nesnesinin metni ASLA yazılmaz: sunucu yanıtı,
/// sembol, tutar ya da başka bir kullanıcının e-postası taşıyabilir ve
/// kullanıcı onu kendi adıyla gönderir. Kullanıcının e-postası da imzaya
/// eklenmez (Ayarlar'daki "Bize ulaş"tan farkı): gönderen adres zaten
/// odur, gövdeye ikinci kez yazmak gereksiz kişisel veri. Yeni veri
/// aktarımı yok: e-postayı kullanıcı kendi uygulamasından kendisi yollar.
/// Kilit `destek_maili_test`.
///
/// Konu/gövde Türkçe ve sabit: okuyan destek (yasin), arayüz metni değil.
Uri destekHataMaili({
  required Object error,
  required String surum,
  required String build,
  required String platform,
  String? ekran,
}) {
  final sinif = hataSinifi(error);
  final ekranAdi = _sade(ekran);
  final govde = [
    'Merhaba, uygulamada bir hata görüyorum ve "Tekrar dene" işe yaramadı.',
    '',
    '(Ne yapıyordun? İstersen buraya yazabilirsin.)',
    '',
    '---',
    'Sürüm: ${_sade(surum) ?? '-'} (${_sade(build) ?? '-'})',
    'Platform: ${_sade(platform) ?? '-'}',
    'Ekran: ${ekranAdi ?? '-'}',
    'Hata sınıfı: $sinif',
  ].join('\n');
  return Uri(
    scheme: 'mailto',
    path: kDestekEposta,
    query: [
      'subject=${Uri.encodeComponent('sandık — hata bildirimi ($sinif)')}',
      'body=${Uri.encodeComponent(govde)}',
    ].join('&'),
  );
}

/// Ekran/sürüm alanı geliştiricinin sabitidir (rota adı, paket sürümü);
/// yine de yalnız güvenli karakterler geçer ve kısa tutulur ki bir çağıran
/// yanlışlıkla serbest metin verirse e-postaya taşınmasın.
String? _sade(String? s) {
  if (s == null) return null;
  final t = s.replaceAll(RegExp(r'[^A-Za-z0-9_.\- ]'), '').trim();
  if (t.isEmpty) return null;
  return t.length > 40 ? t.substring(0, 40) : t;
}

/// Çalışan platformun kısa adı (`ios`, `android`…). `dart:io` yerine
/// `defaultTargetPlatform`: testte `debugDefaultTargetPlatformOverride` ile
/// sınanabilir.
String destekPlatformu() => defaultTargetPlatform.name;

/// Sürüm ve build: paketten okunur, elle yazılmaz (Ayarlar'daki sürüm
/// satırıyla aynı kaynak). Okunamazsa `-` (uydurma sürüm yazılmaz).
Future<({String surum, String build})> destekSurumu() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return (surum: info.version, build: info.buildNumber);
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'destek_maili.surum');
    return (surum: '-', build: '-');
  }
}
