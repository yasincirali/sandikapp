import 'package:flutter/foundation.dart' show immutable, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../models/elde_tutma.dart';
import '../services/aylik_getiri_tablosu.dart';
import '../services/crash_reporter.dart';
import '../services/history_service.dart';
import '../services/inflation_service.dart';

/// Aylık getiri tablosunun isteği. Eşitlik yalnız [anahtar]la: lot
/// listeleri her build'de yeni nesne olarak gelir; anahtar (kapsam + defter
/// imzası) değişmedikçe aynı istektir ve önbellekteki tablo döner.
@immutable
class AylikGetiriIstegi {
  const AylikGetiriIstegi({
    required this.anahtar,
    required this.seriLotlari,
    required this.hesapLotlari,
  });

  final String anahtar;

  /// Seriyi kuran lotlar (Performans'ın `chartAssets`'i: seriye girebilen).
  final List<Asset> seriLotlari;

  /// Akış defteri (Performans'ın `targetAssets`'i) — Özet'le aynı ikili.
  final List<Asset> hesapLotlari;

  @override
  bool operator ==(Object other) =>
      other is AylikGetiriIstegi && other.anahtar == anahtar;

  @override
  int get hashCode => anahtar.hashCode;
}

/// Testte seri çekimini değiştirmek için (ağ yok).
@visibleForTesting
Future<Map<int, double>> Function(List<Asset> lotlar, DateTime simdi)?
    aylikGetiriSeriTestCekici;

/// Aylık getiri tablosu — önbellekli (2026-11-11, Premium).
///
/// ## Neden provider
/// Tablo beş yıla kadar seri ve defter tarar; Performans her tick'te
/// yeniden kurulur. Sonuç anahtara bağlı önbellekte durur: dönem çipi,
/// tür süzgeci olmayan yeniden çizimler tabloyu yeniden hesaplatmaz.
/// `autoDispose`: ekran kapanınca bırakılır, açılışta güncel seriyle
/// yeniden kurulur (bu ayın hücresi bugüne kadar).
///
/// ## Seri
/// 5 yıl haftalık + son yıl günlük, birleşik (`uzunSeriyiBirlestir`;
/// gerekçe orada). İkisi de `HistoryService`'in çözünürlük önbelleğinden
/// gelir; Özet'in 5Y/1Y ısıtması onları zaten indirmiş olur.
///
/// `null`: tablo yok (ilk alım yok ya da seri boş).
///
/// ## TÜFE
/// Yıl satırının "TÜFE · reel" parçası aynı provider'da eklenir
/// (`aylikGetiriYilReelleri`); endeks hatası tabloyu düşürmez.
///
/// ## Hata: yutulmaz, taşınır (2026-11-12)
/// Hata Crashlytics'e non-fatal gider ve YENİDEN fırlatılır. Eskiden
/// `null`a çevriliyordu: Premium kullanıcının parasını verdiği kart seri
/// hatasında sessizce siliniyordu, "yok" ile "hesaplanamadı" ayırt
/// edilemiyordu. Kart hatada kalır ve tek satırla söyler; Performans'ın
/// aşağı çekip yenilemesi aileyi geçersiz kılar (`_retryChartData`), hata
/// önbellekte takılı kalmaz.
final aylikGetiriProvider = FutureProvider.autoDispose
    .family<AylikGetiriTablosu?, AylikGetiriIstegi>((ref, istek) async {
  if (istek.seriLotlari.isEmpty || istek.hesapLotlari.isEmpty) return null;
  final simdi = DateTime.now();
  try {
    final test = aylikGetiriSeriTestCekici;
    final Map<int, double> seri;
    if (test != null) {
      seri = await test(istek.seriLotlari, simdi);
    } else {
      final h = HistoryService.instance;
      final sonuc = await Future.wait([
        h.getPortfolioHistoryBreakdownAtResolution(
          assets: istek.seriLotlari,
          from: DateTime(simdi.year - 5, simdi.month),
          to: simdi,
          tier: ResolutionTier.weekly,
        ),
        h.getPortfolioHistoryBreakdownAtResolution(
          assets: istek.seriLotlari,
          from: DateTime(simdi.year - 1, simdi.month, simdi.day),
          to: simdi,
          tier: ResolutionTier.daily,
        ),
      ]);
      seri =
          uzunSeriyiBirlestir(haftalik: sonuc[0].total, gunluk: sonuc[1].total);
    }
    if (seri.isEmpty) return null;
    final tablo = await aylikGetiriTablosuHesapla(
        seri: seri, lotlar: istek.hesapLotlari, simdi: simdi);
    if (tablo == null) return null;
    return tablo.reelIle(aylikGetiriYilReelleri(tablo, await _tufeEndeksi()));
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'aylikGetiriProvider');
    rethrow;
  }
});

/// TÜFE endeksi — Özet'in reel kartıyla aynı kaynak ve 12 saatlik önbellek
/// (`InflationService`; yeni ağ yok). Endeks okunamazsa tablo yine çizilir,
/// yalnız yıl satırları reel yazmaz: TÜFE yan bilgi, tabloyu düşürmez.
Future<Map<DateTime, double>> _tufeEndeksi() async {
  try {
    return await InflationService.instance.indexSeries();
  } catch (e, st) {
    CrashReporter.report(e, st, reason: 'aylikGetiriProvider.tufe');
    return const {};
  }
}

/// TÜFE endeksi, Performans dışındaki yüzeyler için (2026-11-13: varlık
/// ekranının elde tutma satırı). Kaynak [aylikGetiriProvider]'ın yıl
/// satırlarıyla AYNI `_tufeEndeksi` (InflationService, 12 saatlik önbellek):
/// yeni ağ kaynağı yok, Performans endeksi zaten çektiyse istek de yok.
/// Hata Crashlytics'e gider ve boş endeks döner: TÜFE yan bilgidir, satır
/// çizilmez ama ekran düşmez.
final tufeEndeksiProvider =
    FutureProvider.autoDispose<Map<DateTime, double>>((ref) => _tufeEndeksi());

/// Elde tutma satırının "Aynı sürede TÜFE yıllık … · reel …" parçası.
/// Hesap `eldeTutmaTufesi`'nde (saf, model katmanı); bu provider yalnız
/// endeksi bağlar ki widget `build()`'inde hesap olmasın. Senkron: endeks
/// gelene kadar `null` (satır yok), fiyat tik'inde özet değişince yeniden
/// hesaplanır ama endeks yeniden yüklenmez (yükleme anı titremesi yok).
final eldeTutmaTufeProvider = Provider.autoDispose
    .family<EldeTutmaTufe?, EldeTutma>((ref, ozet) {
  final endeks = ref.watch(tufeEndeksiProvider).valueOrNull;
  if (endeks == null) return null;
  return eldeTutmaTufesi(
    baslangic: ozet.baslangic,
    yillikPct: ozet.yillikPct,
    endeks: endeks,
    simdi: DateTime.now(),
  );
});
