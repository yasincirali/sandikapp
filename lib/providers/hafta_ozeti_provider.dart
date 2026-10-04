import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/position.dart';
import '../services/fon_akisi.dart';
import '../services/fon_karnesi.dart' show fonKoduOf;
import '../services/hisse_hacmi.dart';
import '../widgets/hacim_radari_karti.dart' show bistSembolu, kriptoTickeri;
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

/// "Haftanın özeti"nde olağandışı hacim satırı: tutulan bir hisse ya da coin
/// ve son haftasındaki (en yeni) olağandışı hacim günü.
class HacimHaftasi {
  const HacimHaftasi(
      {required this.pozisyon, required this.olay, required this.kripto});

  final Position pozisyon;
  final HacimOlayi olay;

  /// Tutar USDT mi (kripto) TL mi (hisse).
  final bool kripto;
}

/// Tutulan hisse ve coinlerde son 7 günün olağandışı hacim günleri (B2/B3).
/// Kartların kullandığı AYNI provider'lar okunur; olayı olmayan varlık
/// listeye girmez. Yalnız kendi pozisyonları (fon listesiyle aynı kural).
final haftaHacimProvider =
    FutureProvider.autoDispose<List<HacimHaftasi>>((ref) async {
  final durum = ref.watch(portfolioProvider).valueOrNull;
  if (durum == null) return const [];
  final kendi = [
    for (final a in durum.assets)
      if (a.userId == durum.ownerId) a,
  ];

  final isler = <Future<HacimHaftasi?>>[];
  final gorulen = <String>{};
  for (final p in aggregatePositions(kendi)) {
    final v = p.representative;
    final hisse = bistSembolu(tur: v.type, ticker: v.ticker);
    final coin = kriptoTickeri(tur: v.type, ticker: v.ticker);
    final anahtar = hisse ?? coin;
    if (anahtar == null || !gorulen.add(anahtar)) continue;
    final ozet = hisse != null
        ? ref.watch(hisseHacmiProvider(hisse).future)
        : ref.watch(kriptoBaskiProvider(coin!).future);
    isler.add(ozet.then((o) {
      final olay = o == null ? null : sonHaftaHacimOlayi(o);
      return olay == null
          ? null
          : HacimHaftasi(pozisyon: p, olay: olay, kripto: coin != null);
    }));
  }
  final liste = (await Future.wait(isler)).nonNulls.toList()
    ..sort((a, b) => b.olay.tarih.compareTo(a.olay.tarih));
  return liste;
});
