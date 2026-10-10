import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/portfoy_grubu.dart';
import 'package:portfoy_takip/screens/portfolio_screen.dart';

/// Portföy sekmesindeki küçük halkanın lejantı (2026-10-09, yasin: "çeşit az
/// da çok da olsa eşit büyüklükte alan kaplamalı … müşteri kaydırabileceğini
/// anlamalı"): sığmayan türler saklanmaz, sayfalara bölünür. Küçük türler
/// de katlanmaz (2026-10-10, "hâlâ Diğer var"); katlama yalnız açık eşikle.

void main() {
  ({PortfoyGrubu grup, double tutar, double pay}) d(AssetType t, double pay) =>
      (grup: PortfoyGrubu(t), tutar: pay * 1000, pay: pay);

  group('lejantKatla', () {
    test('varsayılan: hiçbir tür katlanmaz, "Diğer (N)" yok', () {
      final s = lejantKatla([
        d(AssetType.hisse, 0.60),
        d(AssetType.fon, 0.37),
        d(AssetType.emtia, 0.019),
        d(AssetType.kripto, 0.011),
      ]);
      expect(s.map((o) => o.tur?.tur), [
        AssetType.hisse,
        AssetType.fon,
        AssetType.emtia,
        AssetType.kripto,
      ]);
      expect(s.any((o) => o.katlanmis), isFalse);
    });

    test('açık eşikle %2 altındaki dilimler "Diğer (N)" öğesine katlanır', () {
      final s = lejantKatla(esik: 0.02, [
        d(AssetType.hisse, 0.60),
        d(AssetType.fon, 0.37),
        d(AssetType.emtia, 0.019),
        d(AssetType.kripto, 0.011),
      ]);
      expect(s.length, 3);
      expect(s.map((o) => o.tur?.tur), [AssetType.hisse, AssetType.fon, null]);
      final diger = s.last;
      expect(diger.katlanmis, isTrue);
      expect(diger.sayi, 2);
      expect(diger.pay, closeTo(0.030, 1e-9));
      expect(diger.tutar, closeTo(30, 1e-9));
    });

    test('tek küçük dilim katlanmaz — adı saklanmasın', () {
      final s = lejantKatla(esik: 0.02, [
        d(AssetType.hisse, 0.985),
        d(AssetType.altin, 0.015),
      ]);
      expect(s.map((o) => o.tur?.tur), [AssetType.hisse, AssetType.altin]);
      expect(s.every((o) => !o.katlanmis), isTrue);
    });

    test('sıra korunur, katlanan öğe hep sonda', () {
      final s = lejantKatla(esik: 0.02, [
        d(AssetType.hisse, 0.5),
        d(AssetType.doviz, 0.01),
        d(AssetType.fon, 0.48),
        d(AssetType.bes, 0.01),
      ]);
      expect(s.map((o) => o.tur?.tur), [AssetType.hisse, AssetType.fon, null]);
    });

    test('boş girdi boş çıkar', () {
      expect(lejantKatla(const []), isEmpty);
    });
  });

  group('lejantSayfaSayisi', () {
    test('sığan tek sayfa, taşan bölünür; boşta bile 1', () {
      expect(lejantSayfaSayisi(0, 8), 1);
      expect(lejantSayfaSayisi(3, 8), 1);
      expect(lejantSayfaSayisi(8, 8), 1);
      expect(lejantSayfaSayisi(9, 8), 2);
      expect(lejantSayfaSayisi(10, 4), 3);
    });
  });
}
