import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/fiyat_kaynagi.dart';
import '../services/price_service.dart';
import '../services/zekat_hesabi.dart';
import 'auth_provider.dart';
import 'portfolio_provider.dart';

/// Zekât nisabının dayandığı 24 ayar gram altın (TL); bilinmiyorsa `null`.
///
/// Sembol `FiyatKaynagi.gramAltin24` (fiyat kaynağı sözleşmesi madde 1):
/// piyasa bandıyla ve portföydeki "Gram Altın (24 Ayar)" ile AYNI sayı.
/// `PortfolioState.goldGramTry` kullanılmaz: o 22 ayardır ve yalnız baz
/// birim altınken çekilir (bkz. `zekat_hesabi.dart`). Kaynak yanıt
/// vermezse oturumda görülmüş son kotasyon; o da yoksa `null` — sheet
/// nisabı ve sonucu göstermez (uydurma sayı yok).
final zekatGramAltinProvider =
    FutureProvider.autoDispose<double?>((ref) async {
  const sembol = FiyatKaynagi.gramAltin24;
  final q = await PriceService.instance.fetchQuotes(const [sembol]);
  final canli = q[sembol]?.regularMarketPrice;
  if (canli != null && canli > 0) return canli;
  final son = PriceService.instance.sonBilinenFiyat(sembol);
  return (son != null && son > 0) ? son : null;
});

/// Sheet'in okuduğu hesap. [borc] bellek içi (kaydedilmez); family
/// anahtarıdır ki her yazışta hesap saf fonksiyondan yeniden türesin.
///
/// Bugünkü mülkiyet ve sahiplik: kullanıcının KENDİ lotları (`userId`),
/// ortağın lotu zekât hesabına girmez — zekât kişiseldir. `aktifLotlar`
/// `zekatHesapla` içinde.
final zekatSonucuProvider = Provider.autoDispose
    .family<AsyncValue<ZekatSonucu?>, double>((ref, borc) {
  final gram = ref.watch(zekatGramAltinProvider);
  final uid = ref.watch(authProvider).valueOrNull?.id;
  final ps = ref.watch(portfolioProvider).valueOrNull;
  return gram.whenData((g) {
    if (ps == null) return null;
    final lotlar =
        uid == null ? ps.assets : ps.assets.where((a) => a.userId == uid);
    return zekatHesapla(
      lotlar: lotlar,
      gramAltin24Try: g,
      toTRY: ps.toTRY,
      bugun: DateTime.now(),
      borc: borc,
    );
  });
});
