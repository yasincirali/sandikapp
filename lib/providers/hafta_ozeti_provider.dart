import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/fon_akisi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import 'fon_akisi_provider.dart';
import 'portfolio_provider.dart';

/// "Haftanın özeti" ekranındaki bir satır: tutulan bir fon ve son haftası.
class FonHaftasi {
  const FonHaftasi({required this.pozisyon, required this.ozet});

  /// Kullanıcının BUGÜN açık olan pozisyonu (kapanmış pozisyon gelmez).
  final Position pozisyon;
  final FonAkisOzeti ozet;
}

/// Kullanıcının tuttuğu fonların son hafta akışı (Balina B4, 2026-10-04).
///
/// Yeni bir sorgu türü yok: her fon için kartın kullandığı AYNI provider
/// (`fonAkisiProvider`) okunur — ekran ile fon sayfasındaki kart aynı sayıyı
/// gösterir, ikinci bir hesap yolu açılmaz. Verisi olmayan (yeni, bayat)
/// fon listeye girmez; "veri yok" satırı uydurulmaz.
///
/// Yalnız KENDİ pozisyonları: ortak lot'ları başka bir kullanıcının
/// portföyüdür (`partner_aggregation_invariant`), haftalık bildirim de
/// yalnız sahibine gider.
final haftaOzetiProvider =
    FutureProvider.autoDispose<List<FonHaftasi>>((ref) async {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final kendi = [
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ];

  // Aynı fon iki pozisyon anahtarına düşse de (önekli/öneksiz kod) tek satır.
  final fonlar = <String, Position>{};
  for (final p in aggregatePositions(kendi)) {
    final kod = fonKoduOf(
        tur: p.representative.type, ticker: p.representative.ticker);
    if (kod != null) fonlar.putIfAbsent(kod, () => p);
  }

  final sonuc = await Future.wait([
    for (final e in fonlar.entries)
      ref.watch(fonAkisiProvider(e.key).future).then((ozet) =>
          ozet == null ? null : FonHaftasi(pozisyon: e.value, ozet: ozet)),
  ]);
  return haftaSirasi(sonuc.nonNulls.toList());
});

/// Sıra: önce son haftasında büyük hareket olanlar, sonra akışın fon
/// büyüklüğüne oranı (mutlak tutar değil — 50 mr'lik fonda ₺100 mn gürültü,
/// 500 mn'lik fonda haberdir).
List<FonHaftasi> haftaSirasi(List<FonHaftasi> liste) {
  double oran(FonHaftasi f) => f.ozet.sonHaftaNet.abs() / f.ozet.buyukluk;
  return [...liste]..sort((a, b) {
      final ao = sonHaftaOlayi(a.ozet) != null ? 1 : 0;
      final bo = sonHaftaOlayi(b.ozet) != null ? 1 : 0;
      if (ao != bo) return bo - ao;
      return oran(b).compareTo(oran(a));
    });
}
