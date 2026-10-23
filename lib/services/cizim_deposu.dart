import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../config/pref_keys.dart';
import '../models/grafik_cizimi.dart';
import 'crash_reporter.dart';

/// Grafik çizimlerinin cihazdaki deposu — sembol başına liste.
///
/// Tek anahtar ([PrefKeys.grafikCizimleri]) altında `{sembol: [çizim…]}`
/// JSON'u. Sunucuya gitmez (benchmark kararı 2026-10-23: telefonda saklama
/// ücretsiz, cihazlar arası eşitleme Premium adımı). Çizim kişisel veri
/// değildir ama hesaba da bağlanmaz: aynı telefonda hesap değişse de
/// grafik çizgileri sembole aittir, TradingView'in misafir modu gibi.
///
/// Sınırlar: sembol başına [enCokCizim], toplam [enCokSembol] sembol (en
/// eski dokunulan düşer). Tercih dosyası şişip açılışı yavaşlatmasın.
class CizimDeposu {
  CizimDeposu._();
  static final CizimDeposu instance = CizimDeposu._();

  static const enCokCizim = 50;
  static const enCokSembol = 100;

  static String anahtar(String sembol) => sembol.trim().toUpperCase();

  Future<Map<String, Object?>> _hepsi(SharedPreferences sp) async {
    final ham = sp.getString(PrefKeys.grafikCizimleri);
    if (ham == null || ham.isEmpty) return {};
    try {
      final j = jsonDecode(ham);
      return j is Map ? Map<String, Object?>.from(j) : {};
    } catch (e, st) {
      // Bozuk JSON: çizimler kaybolur ama grafik açılır. Sessiz kalmasın.
      CrashReporter.report(e, st, reason: 'CizimDeposu.oku');
      return {};
    }
  }

  Future<List<GrafikCizimi>> oku(String sembol) async {
    final sp = await SharedPreferences.getInstance();
    final liste = (await _hepsi(sp))[anahtar(sembol)];
    if (liste is! List) return const [];
    return [
      for (final j in liste)
        if (GrafikCizimi.fromJson(j) case final c?) c,
    ];
  }

  Future<void> yaz(String sembol, List<GrafikCizimi> cizimler) async {
    final sp = await SharedPreferences.getInstance();
    final hepsi = await _hepsi(sp);
    final k = anahtar(sembol);
    // Yeniden ekleme sırayı tazeler: en son dokunulan sonda kalır.
    hepsi.remove(k);
    if (cizimler.isNotEmpty) {
      final son = cizimler.length > enCokCizim
          ? cizimler.sublist(cizimler.length - enCokCizim)
          : cizimler;
      hepsi[k] = [for (final c in son) c.toJson()];
    }
    while (hepsi.length > enCokSembol) {
      hepsi.remove(hepsi.keys.first);
    }
    await sp.setString(PrefKeys.grafikCizimleri, jsonEncode(hepsi));
  }
}
