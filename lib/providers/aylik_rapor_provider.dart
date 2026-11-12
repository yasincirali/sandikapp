import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/asset.dart';
import '../services/aylik_rapor_ozeti.dart';
import '../services/aylik_rapor_yukleyici.dart';
import '../services/daily_summary.dart';
import '../services/varlik_analizi.dart' show AnalizOzeti;
import 'analiz_provider.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// Sahibin etkin defter satırları (aylık rapor + PDF ortak girdisi).
///
/// Yalnız KENDİ lotları: ortak lot'lar başka kullanıcının portföyüdür
/// (`partner_aggregation_invariant`). `isActive` silinmişi eler, kapanmış
/// pozisyonun satışını TUTAR — rapor geçmişi sorar.
List<Asset> aylikRaporLotlari(PortfolioState durum) => [
      for (final a in durum.assets)
        if (a.userId == durum.ownerId && a.isActive) a
    ];

/// Aylık raporun sayısal bölümleri (2026-11-07). `null`: portföy henüz
/// yüklenmedi. Hesap `build()` dışında, burada bir kez.
final aylikRaporOzetiProvider = FutureProvider.autoDispose
    .family<AylikRaporOzeti?, DateTime>((ref, donem) async {
  // Fiyat turu her birkaç dakikada state'i yeniler; ayın serisi ve olay
  // sorguları her turda yeniden koşmasın. Defter değişince (sahip ya da
  // satır sayısı) yeniden hesaplanır.
  ref.watch(portfolioProvider.select((v) => switch (v.valueOrNull) {
        final d? => '${d.ownerId}|${d.assets.length}',
        null => null,
      }));
  final durum = ref.read(portfolioProvider).valueOrNull;
  if (durum == null) return null;
  final lotlar = aylikRaporLotlari(durum);
  return AylikRaporYukleyici.hazirla(
    donem: donem,
    lotlar: lotlar,
    canliToplam: DailySummary.kapsamToplami(durum, lotlar),
  );
});

/// Kilitli aylık rapor kartının kişisel satırı (2026-11-12). `null`:
/// oturum ya da portföy yok. Ağ: yalnız not başlıkları (ücretsiz katman,
/// `notOzetleriProvider`, haftanın özetiyle aynı önbellek); seri ya da
/// olay sorgusu çekilmez — o maliyet raporu açan Premium kullanıcının.
/// Not okuması düşerse not sayısı 0 olur ve cümleden o parça çıkar
/// ("notun yok" denmez).
final aylikRaporKancasiProvider = FutureProvider.autoDispose
    .family<AylikRaporKancasi?, DateTime>((ref, donem) async {
  if (ref.watch(authProvider).valueOrNull?.id == null) return null;
  ref.watch(portfolioProvider.select((v) => switch (v.valueOrNull) {
        final d? => '${d.ownerId}|${d.assets.length}',
        null => null,
      }));
  final durum = ref.read(portfolioProvider).valueOrNull;
  if (durum == null) return null;
  final anahtarlar = ref.watch(tutulanNotAnahtarlariProvider);
  final notlar = anahtarlar.isEmpty
      ? const <String, AnalizOzeti>{}
      : await ref.watch(
          notOzetleriProvider(notKumesi(anahtarlar, 'aylik')).future);
  return aylikRaporKancasi(
    lotlar: aylikRaporLotlari(durum),
    donem: donem,
    simdi: DateTime.now(),
    notlar: notlar.values,
  );
});

