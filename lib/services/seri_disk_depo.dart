import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Son BAŞARILI fiyat serisinin diskteki kopyası — "veri gelmedi, grafik
/// düz çizgiye döndü" şikâyetinin kalıcı ayağı (2026-10-03).
///
/// ## Neden
/// "Kripto varlık fiyatı her zaman çekilemiyor … düz çizgiye dönüyor, tüm
/// varlıklar için gerekli bu çözüm" (yasin, 2026-10-03). Grafik motoru
/// (`HistoryService.seriCek`) bir çekim başarısız olunca BOŞ liste döner ve
/// varlık `currentPrice` tohumuyla düz çizilir. Bellekteki son iyi seri
/// (`HistoryService._sonIyi`) aynı oturumdaki kesintiyi kapatır; ama uygulama
/// yeniden açıldığında ilk çekim de düşerse elde hiçbir şey yoktu. Bu depo o
/// boşluğu kapatır: bir kez ölçülmüş seri, kaynak geçici olarak yanıt
/// vermezken yeniden çizilir.
///
/// ## Neden uydurma değil
/// Fiyat kaynağı sözleşmesinin 3. maddesi (`fiyat_kaynagi.dart`) "bilinmeyen
/// sayı seriye girmez" der. Buradaki noktaların HER biri aynı kaynaktan,
/// aynı ölçekte ÖLÇÜLMÜŞTÜR; yalnızca daha eski bir çekimden gelir. Seri
/// gövdesinin birkaç dakika bayat olması, grafiğin son noktası zaten canlı
/// toplama sabitlendiği için (`currentTotalOverride`) ekranda fark yaratmaz.
///
/// ## Sınırlar
/// · [azamiYas]'tan eski kopya OKUNMAZ (aylarca açılmamış uygulamada eski
///   seri, yeni dönemin penceresine zaten düşmez ama dosya da tutulmasın).
/// · En çok [azamiDosya] dosya; fazlası en eski değiştirilme zamanına göre
///   silinir. 1m × 5g'lük en büyük seri ~180 KB → üst sınır birkaç MB.
/// · Hiçbir hata ana akışa sızmaz: disk okunamazsa `null`, yazılamazsa sessiz.
class SeriDiskDepo {
  SeriDiskDepo({Future<Directory> Function()? kokDizin})
      : _kokDizin = kokDizin ?? getApplicationSupportDirectory;

  final Future<Directory> Function() _kokDizin;
  Directory? _dizin;

  static const azamiYas = Duration(days: 7);
  static const azamiDosya = 80;
  static const _surum = 1;

  Future<Directory> _dizinAl() async {
    final d = _dizin;
    if (d != null) return d;
    final kok = await _kokDizin();
    final yeni = Directory('${kok.path}/seri_onbellek');
    if (!await yeni.exists()) await yeni.create(recursive: true);
    return _dizin = yeni;
  }

  /// Anahtar sembol içerir (`USDTRY=X`, `^XU100`, `TEFAS:AFA`); base64url
  /// dosya adında güvenlidir ve geri çözülebilir.
  static String dosyaAdi(String anahtar) =>
      '${base64Url.encode(utf8.encode(anahtar)).replaceAll('=', '')}.json';

  Future<List<(int, double)>?> oku(String anahtar) async {
    try {
      final f = File('${(await _dizinAl()).path}/${dosyaAdi(anahtar)}');
      if (!await f.exists()) return null;
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      if (m['v'] != _surum || m['k'] != anahtar) return null;
      final at = DateTime.tryParse(m['at'] as String? ?? '');
      if (at == null || DateTime.now().difference(at) > azamiYas) return null;
      final out = <(int, double)>[];
      for (final p in (m['p'] as List)) {
        final l = p as List;
        final t = (l[0] as num).toInt();
        final v = (l[1] as num).toDouble();
        if (v > 0 && v.isFinite) out.add((t, v));
      }
      return out.isEmpty ? null : out;
    } catch (e) {
      if (kDebugMode) debugPrint('[SeriDiskDepo] okunamadı: $e');
      return null;
    }
  }

  Future<void> yaz(String anahtar, List<(int, double)> seri) async {
    if (seri.isEmpty) return;
    try {
      final dizin = await _dizinAl();
      final f = File('${dizin.path}/${dosyaAdi(anahtar)}');
      await f.writeAsString(jsonEncode({
        'v': _surum,
        'k': anahtar,
        'at': DateTime.now().toUtc().toIso8601String(),
        'p': [
          for (final p in seri) [p.$1, p.$2]
        ],
      }));
      await _budar(dizin);
    } catch (e) {
      if (kDebugMode) debugPrint('[SeriDiskDepo] yazılamadı: $e');
    }
  }

  Future<void> _budar(Directory dizin) async {
    final dosyalar = await dizin
        .list()
        .where((e) => e is File && e.path.endsWith('.json'))
        .cast<File>()
        .toList();
    if (dosyalar.length <= azamiDosya) return;
    final zamanli = <(File, DateTime)>[
      for (final f in dosyalar) (f, (await f.stat()).modified),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    for (final (f, _) in zamanli.take(zamanli.length - azamiDosya)) {
      try {
        await f.delete();
      } catch (_) {}
    }
  }
}
