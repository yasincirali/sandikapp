import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../utils/money_format.dart';
import 'portfolio_provider.dart';
import 'preferences_provider.dart';

export '../utils/money_format.dart'
    show BaseCurrency, BazPara, ParaBicimi, kGoldGramSymbol;

/// Seçili baz para birimi.
final baseCurrencyProvider = Provider<BaseCurrency>(
  (ref) => BaseCurrency.fromIndex(ref.watch(baseCurrencyIndexProvider)),
);

/// Tercih + portföyün bildiği kur. Kur yoksa (ilk yenileme öncesi, ya da
/// altın kuru henüz çekilmedi) [BazPara.lira] true döner ve her yüzey ₺
/// yazar — yanlış kurla yazılmış tutar göstermektense doğru ₺ gösterilir.
final bazParaProvider = Provider<BazPara>((ref) {
  final birim = ref.watch(baseCurrencyProvider);
  final p = ref.watch(portfolioProvider).valueOrNull;
  final kur = switch (birim) {
    BaseCurrency.try_ => 1.0,
    BaseCurrency.usd => p?.usdTry ?? 0,
    BaseCurrency.eur => p?.eurTry ?? 0,
    BaseCurrency.gold => p?.goldGramTry ?? 0,
  };
  // `usdTry` varsayılanı 1.0 (kur çekilmeden önce): "1 dolar = 1 lira" ile
  // yazmak yanlış olur; kur 1'in üstüne çıkana kadar ₺'de kal.
  final gecerli = birim == BaseCurrency.try_ || kur > 1;
  return BazPara(birim, gecerli ? kur : 0);
});

/// Baz birimi değiştirir; altın seçildiyse kuru hemen çeker ki ekran ₺'de
/// takılı kalmasın (altın kuru yalnızca bu tercihle isteniyor).
Future<void> setBaseCurrency(WidgetRef ref, BaseCurrency birim) async {
  await ref.read(baseCurrencyIndexProvider.notifier).set(birim.index);
  if (birim == BaseCurrency.gold) {
    final p = ref.read(portfolioProvider).valueOrNull;
    if (p != null && !(p.goldGramTry > 0)) {
      await ref.read(portfolioProvider.notifier).refreshPrices();
    }
  }
}
