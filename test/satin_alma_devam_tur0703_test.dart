import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/providers/portfolio_provider.dart';
import 'package:portfoy_takip/services/disa_aktarim/rapor_belgeleri.dart';
import 'package:portfoy_takip/widgets/raporlar_kapisi.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 23 Kas 0703 (UI/UX turu 15): satın alma sonrası kaldığı yerden
/// devam. Ortak hata: kullanıcı Premium'u alıyor, paywall kapanıyor, istediği
/// iş yapılmıyor. Ana sinyal `PaywallScreen.show(...) == true` (Varlık Ekle
/// tekli kaydı, `kayit.dart` `yenidenDene`).
Asset _lot(String id, String ticker, AssetKind kind, {DateTime? silindi}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: ticker,
      ticker: ticker,
      type: AssetType.hisse,
      quantity: 10,
      purchasePrice: 100,
      currency: 'TRY',
      notes: '',
      isManualPrice: false,
      kind: kind,
      sellPrice: kind == AssetKind.sell ? 120 : null,
      dividendAmount: kind == AssetKind.dividend ? 5 : 0,
      deletedAt: silindi,
      addedDate: DateTime(2025, 6, 1),
    );

void main() {
  group('#1 ve #7 Portföy dökümü', () {
    final k = ekranKaynagiSync('lib/widgets/portfoy_dokumu.dart');

    test('satın alma sonrası akış sürer (biçim sorusuna düşer)', () {
      expect(
          k,
          contains(
              "final aldi = await PaywallScreen.show(context, source: 'portfoy_disa_aktar');"));
      expect(k, contains('if (aldi != true || !context.mounted) return;'));
      expect(
          RegExp(r"source: 'portfoy_disa_aktar'\);\s*return;").hasMatch(k),
          isFalse,
          reason: 'satın almadan sonra koşulsuz return ölü uçtu');
    });

    test('portföy beklenir, oturum yoksa hata gösterilir (sessiz dönüş yok)',
        () {
      expect(k, contains('await kap.read(portfolioProvider.future)'));
      expect(k, isNot(contains('portfolioProvider).valueOrNull')));
      expect(k, contains('AuthException(context.l10n.hataOturumDoldu)'));
      expect(k, isNot(contains('if (durum == null || kullanici == null) return;')));
    });
  });

  test('#2 Anaparam çipi: sonuç beklenir, satın alınca alan dolar', () {
    final k = ekranKaynagiSync('lib/widgets/quick_adjust_dialog.dart');
    expect(k, contains('Future<void> _anaparamPaywall() async'));
    expect(k,
        contains("final aldi = await PaywallScreen.show(context, source: 'anaparam');"));
    final govde = k.substring(k.indexOf('Future<void> _anaparamPaywall()'));
    expect(govde, contains('if (aldi != true || !mounted) return;'));
    expect(govde, contains('_qtyCtrl.text = _fmt(adet)'));
  });

  group('#3/#4 sözleşme formları: satın alınca TEK yeniden deneme', () {
    for (final yol in [
      'lib/screens/add_asset/bes_formu.dart',
      'lib/screens/add_asset/mevduat_formu.dart',
    ]) {
      test(yol, () {
        final k = ekranKaynagiSync(yol);
        expect(k, contains('bool satinAlmaSonrasi = false'));
        expect(k, contains("await PaywallScreen.show(context, source: 'asset_limit_\${e.limit}');"));
        expect(k, contains('if (aldi == true && !satinAlmaSonrasi && mounted)'));
        expect(k,
            contains('return kaydet(portfoyId: portfoyId, satinAlmaSonrasi: true);'));
      });
    }
  });

  group('#5 hızlı giriş toplu kaydı: yalnız kalan satırlar', () {
    test('kaynak: kesilen satırdan devam, tek satır kalsa da kaydedilir', () {
      final k = ekranKaynagiSync('lib/screens/add_asset_screen.dart');
      expect(k, contains('await siraylaKaydet(entries, (entry) async {'));
      expect(k, contains('on TopluSinirAsildi catch (e)'));
      expect(k,
          contains('_saveBatch(entries.sublist(e.kaydedilen), kalanlar: true)'));
      expect(k, contains('if (entries.length == 1 && !kalanlar)'));
      // Eski yol: sonucu atılan paywall.
      expect(k, isNot(contains('on AssetLimitExceededException catch (e) {\n'
          '            // Sınıra kadar olanlar eklendi')));
    });

    test('12 satır, sınır 10: satın alma sonrası 12 kayıt, çift yok', () async {
      final satirlar = List.generate(12, (i) => 'satir$i');
      final yazilan = <String>[];
      var premium = false;
      Future<void> kaydet(String s) async {
        // `addAsset` gibi: sınır yazmadan ÖNCE denetlenir.
        if (!premium && yazilan.length >= 10) {
          throw const AssetLimitExceededException(10, 10);
        }
        yazilan.add(s);
      }

      TopluSinirAsildi? kesinti;
      try {
        await siraylaKaydet(satirlar, kaydet);
      } on TopluSinirAsildi catch (e) {
        kesinti = e;
      }
      expect(kesinti, isNotNull);
      expect(kesinti!.kaydedilen, 10);
      expect(kesinti.sebep.limit, 10);
      expect(yazilan, hasLength(10));

      premium = true; // paywall `true`
      await siraylaKaydet(satirlar.sublist(kesinti.kaydedilen), kaydet);
      expect(yazilan, satirlar);
      expect(yazilan.toSet(), hasLength(12));
    });

    test('sınır dışı hata sarılmadan geçer (genel hata yolu okur)', () async {
      final hata = StateError('ağ');
      await expectLater(
        siraylaKaydet([1, 2], (_) async => throw hata),
        throwsA(same(hata)),
      );
    });
  });

  test('#6 kilitli Raporlar satırı ekran okuyucuda kilidi söyler', () {
    final k = ekranKaynagiSync('lib/widgets/raporlar_kapisi.dart');
    expect(k, contains(r"kilitli ? '$baslik, ${context.l10n.kilitli}' : baslik"));
    expect(k, isNot(contains('semanticLabel: baslik,')));
  });

  group('Premium\'a teşvik: Portföy dökümü alt metni kendi sayısıyla', () {
    test('sayım belgeyle aynı süzgeç', () {
      final s = portfoyDokumuSayilari([
        // İki alış, bir satış: pozisyon açık kalır (tamamen satılmış
        // pozisyon `aggregatePositions`'a girmez, belgede de yok).
        _lot('a0', 'THYAO.IS', AssetKind.buy),
        _lot('a1', 'THYAO.IS', AssetKind.buy),
        _lot('a2', 'THYAO.IS', AssetKind.sell),
        _lot('a3', 'THYAO.IS', AssetKind.dividend),
        _lot('b1', 'ASELS.IS', AssetKind.buy),
        // Silinmiş lot ve silme kaydı sayılmaz.
        _lot('c1', 'SISE.IS', AssetKind.buy, silindi: DateTime(2025, 7, 1)),
        _lot('d1', 'KCHOL.IS', AssetKind.deleteLog),
      ]);
      expect(s.varlik, 2);
      expect(s.islem, 5);
      expect(portfoyDokumuSayilari(const []), (varlik: 0, islem: 0));
    });

    test('metin: sayı varsa kendi sayısı, yoksa genel metin', () {
      final tr = AppLocalizationsTr();
      final en = AppLocalizationsEn();
      expect(portfoyDokumuAlti(tr, (varlik: 14, islem: 63)),
          '14 varlık, 63 işlem; PDF ya da Excel');
      expect(portfoyDokumuAlti(tr, null), tr.dsPortfoyAlt);
      expect(portfoyDokumuAlti(en, (varlik: 1, islem: 1)),
          '1 asset, 1 transaction; PDF or Excel');
      expect(portfoyDokumuAlti(en, (varlik: 14, islem: 63)),
          '14 assets, 63 transactions; PDF or Excel');
    });

    test('kilitsizken sağlayıcıya sorulmaz, sayılar sağlayıcıdan', () {
      final k = ekranKaynagiSync('lib/widgets/raporlar_kapisi.dart');
      expect(k,
          contains('kilitli ? ref.watch(portfoyDokumuSayilariProvider) : null'));
    });
  });
}
