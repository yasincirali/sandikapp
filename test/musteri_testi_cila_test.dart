import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/widgets/sozlesme_formu_ortak.dart';
import 'package:portfoy_takip/widgets/transaction_row.dart';

import 'helpers/kaynak.dart';

/// 2026-10-02 müşteri testi — cila bulguları (P3).
void main() {
  final l10n = lookupAppLocalizations(const Locale('tr'));

  Asset lot(AssetType tur, {AssetKind kind = AssetKind.buy}) => Asset(
        id: 'x',
        userId: 'u',
        name: 'TEST Enpara · Vadeli',
        ticker: tur == AssetType.mevduat ? 'MEVDUAT:abc' : 'THYAO.IS',
        type: tur,
        quantity: 100000,
        purchasePrice: 1,
        currency: 'TRY',
        notes: '',
        kind: kind,
      );

  group('hareket etiketi', () {
    test('mevduatta iç birim payı yazılmaz', () {
      expect(hareketTurEtiketi(l10n, lot(AssetType.mevduat, kind: AssetKind.sell)),
          l10n.txSell);
      expect(hareketTurEtiketi(l10n, lot(AssetType.mevduat)), l10n.txBuy);
    });

    test('diğer türlerde miktar yazılmaya devam eder', () {
      final e = hareketTurEtiketi(l10n, lot(AssetType.hisse));
      expect(e, startsWith('${l10n.txBuy} · '));
    });
  });

  testWidgets('vade çipi Wrap içinde metni kadar geniş', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400,
          child: Wrap(children: [
            SozlesmeCipi(
              icerigeGore: true,
              metin: '92 gün',
              secili: true,
              renk: Colors.blueGrey,
              secildi: () {},
            ),
          ]),
        ),
      ),
    ));
    expect(tester.getSize(find.byType(SozlesmeCipi)).width, lessThan(400));
  });

  test('tür dökümünde işaret ile tutar arasında kelime birleştirici', () {
    final src = ekranKaynagiSync(
        'lib/screens/portfolio_performance/tur_dokumu_karti.dart');
    // Kaynakta kaçış dizisi olarak durur (görünmez karakter düz yazılmaz).
    expect(src, contains(r'\u2060${fmt.format(v.abs())}'));
  });

  test('tür dökümü: pencere içinde alınmış, serisi olmayan tür atlanmaz', () {
    // Haftalık katmanda bu hafta alınan varlığın serisi boş gelir; satır
    // sessizce düşüyordu (1Y'de ₺237K kripto yoktu). Kural dar: simülasyonda
    // yok, TÜM lotlar pencere başından sonra, canlı değer > 0.
    final src = ekranKaynagiSync(
        'lib/screens/portfolio_performance/tur_dokumu_karti.dart');
    final i = src.indexOf('_pencereIciAlim(List<Asset> lotlar)');
    expect(i, greaterThan(0));
    final govde = src.substring(i, src.indexOf('\n  }\n', i));
    expect(govde, contains('widget.simulate'));
    expect(govde, contains('.every((a) => a.addedDate.millisecondsSinceEpoch > widget.tabanMs)'));
    expect(govde, contains('canli <= 0'));
    expect(src, contains('return _pencereIciAlim(lotlar);'));
    expect(src, contains('...turLotlari.keys'));
  });
}
