import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/screens/all_transactions_screen.dart';
import 'package:portfoy_takip/services/contribution_history_service.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
import 'package:portfoy_takip/utils/money_format.dart';

/// Tüm hareketler ay başlığı "Net +₺X" (Ar-Ge 8 Kas #2).
///
/// Sabitlenenler: tanım Performans'ın katkı kuralıyla aynı (`flowOf`),
/// temettü sayılmaz, TL karşılığı bilinmeyen satır sayıyı düşürür ve eski
/// "N hareket" metni döner, silinenlerde eski metin, bakiye gizliyken maske,
/// hareket sayısı her durumda ekran okuyucu etiketinde.
Asset _a(
  String id, {
  AssetKind kind = AssetKind.buy,
  double q = 10,
  double fiyat = 100,
  double? satis,
  String currency = 'TRY',
  double kur = 1,
  double komisyon = 0,
  double temettu = 0,
  DateTime? t,
  DateTime? silindi,
}) =>
    Asset(
      id: id,
      userId: 'u1',
      name: id,
      ticker: id,
      type: AssetType.hisse,
      quantity: q,
      purchasePrice: fiyat,
      sellPrice: satis,
      currency: currency,
      purchaseFxRate: kur,
      commission: komisyon,
      dividendAmount: temettu,
      notes: '',
      isManualPrice: false,
      currentPrice: fiyat,
      addedDate: t ?? DateTime(2026, 11, 3, 10),
      kind: kind,
      deletedAt: silindi,
    );

void main() {
  final l = AppLocalizationsTr();
  const lira = BazPara.lira();

  group('netKatki', () {
    test('alım − satış; satış ele geçen tutarla', () {
      final net = ContributionHistoryService.netKatki([
        _a('al', q: 10, fiyat: 100, komisyon: 5), // +1005
        _a('sat', kind: AssetKind.sell, q: 2, fiyat: 100, satis: 150), // −300
      ]);
      expect(net, 705);
    });

    test('temettü sayılmaz', () {
      final net = ContributionHistoryService.netKatki([
        _a('al', q: 1, fiyat: 500),
        _a('tem', kind: AssetKind.dividend, q: 0, temettu: 80),
      ]);
      expect(net, 500);
    });

    test('silinen kayıt sayılmaz', () {
      final net = ContributionHistoryService.netKatki([
        _a('al', q: 1, fiyat: 500),
        _a('sil', q: 1, fiyat: 900, silindi: DateTime(2026, 11, 4)),
      ]);
      expect(net, 500);
    });

    test('dövizli kayıt kayıtlı kurla çevrilir', () {
      final net = ContributionHistoryService.netKatki([
        _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 34),
      ]);
      expect(net, 3400);
    });

    test('kuru bilinmeyen dövizli kayıt varsa null (uydurma sayı yok)', () {
      expect(
        ContributionHistoryService.netKatki([
          _a('al', q: 1, fiyat: 500),
          _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 1.0),
        ]),
        isNull,
      );
      expect(
        ContributionHistoryService.netKatki([
          _a('usd', q: 1, fiyat: 100, currency: 'USD', kur: 0),
        ]),
        isNull,
      );
    });

    test('kuru bilinmeyen dövizli TEMETTÜ sayıyı düşürmez (zaten sayılmaz)',
        () {
      expect(
        ContributionHistoryService.netKatki([
          _a('al', q: 1, fiyat: 500),
          _a('tem',
              kind: AssetKind.dividend, q: 0, temettu: 3, currency: 'USD'),
        ]),
        500,
      );
    });

    test('Performans ay kovasıyla aynı sayı (tek tanım)', () {
      final kayitlar = [
        _a('al1', q: 3, fiyat: 200, komisyon: 2, t: DateTime(2026, 10, 2)),
        _a('al2',
            q: 1,
            fiyat: 50,
            currency: 'EUR',
            kur: 38,
            t: DateTime(2026, 10, 15)),
        _a('sat',
            kind: AssetKind.sell,
            q: 1,
            fiyat: 200,
            satis: 260,
            t: DateTime(2026, 10, 20)),
        _a('tem',
            kind: AssetKind.dividend,
            q: 0,
            temettu: 40,
            t: DateTime(2026, 10, 25)),
      ];
      final performans = PeriodSummaryService.netInflow(
          kayitlar, DateTime(2026, 10, 1), DateTime(2026, 10, 31));
      expect(ContributionHistoryService.netKatki(kayitlar), performans);
      final kova = ContributionHistoryService.buckets(kayitlar,
              aralik: ContributionInterval.aylik,
              now: DateTime(2026, 11, 5),
              kovaSayisi: 2)
          .first;
      expect(kova.netTRY, performans);
    });
  });

  group('ayBasligiOzetleri', () {
    test('ay başına sayı ve net; süzülmüş listenin tamamı', () {
      final o = ayBasligiOzetleri([
        _a('k1', q: 1, fiyat: 100, t: DateTime(2026, 11, 5)),
        _a('k2', q: 1, fiyat: 200, t: DateTime(2026, 11, 1)),
        _a('e1',
            kind: AssetKind.sell,
            q: 1,
            fiyat: 100,
            satis: 400,
            t: DateTime(2026, 10, 9)),
      ]);
      expect(o[DateTime(2026, 11)], (sayi: 2, net: 300.0));
      expect(o[DateTime(2026, 10)], (sayi: 1, net: -400.0));
    });
  });

  test('silinenlerde kaplar silinme ayına göre; sayı aynı kaba yazılır', () {
    final o = ayBasligiOzetleri([
      _a('s1', t: DateTime(2026, 9, 3), silindi: DateTime(2026, 11, 2)),
    ], tarih: silinmeAni);
    expect(o.keys, [DateTime(2026, 11)]);
    expect(o[DateTime(2026, 11)]!.sayi, 1);
  });

  group('ayBasligiMetni', () {
    test('artı net: "Net +₺1.250", etikette sayı da var', () {
      final r = ayBasligiMetni(l,
          sayi: 3, net: 1250, silinenler: false, baz: lira, gizli: false);
      expect(r.metin, 'Net +₺1.250');
      expect(r.etiket, contains('3 hareket'));
      expect(r.etiket, contains('Net +₺1.250'));
    });

    test('eksi net U+2212 ile', () {
      final r = ayBasligiMetni(l,
          sayi: 1, net: -400, silinenler: false, baz: lira, gizli: false);
      expect(r.metin, 'Net −₺400');
    });

    test('sıfır işaretsiz', () {
      final r = ayBasligiMetni(l,
          sayi: 2, net: 0.2, silinenler: false, baz: lira, gizli: false);
      expect(r.metin, 'Net ₺0');
    });

    test('tutar bilinmiyorsa eski "N hareket"', () {
      final r = ayBasligiMetni(l,
          sayi: 8, net: null, silinenler: false, baz: lira, gizli: false);
      expect(r.metin, '8 hareket');
      expect(r.etiket, '8 hareket');
    });

    test('Silinenler görünümünde eski "N hareket"', () {
      final r = ayBasligiMetni(l,
          sayi: 4, net: 999, silinenler: true, baz: lira, gizli: false);
      expect(r.metin, '4 hareket');
    });

    test('bakiye gizliyken maskeli; etiket tutarı okumaz', () {
      final r = ayBasligiMetni(l,
          sayi: 3, net: 1250, silinenler: false, baz: lira, gizli: true);
      expect(r.metin, 'Net ₺••••');
      expect(r.metin, isNot(contains('1.250')));
      expect(r.etiket, '3 hareket');
      final r2 = ayBasligiMetni(l,
          sayi: 3,
          net: 1250,
          silinenler: false,
          baz: lira.gizlenmis(),
          gizli: false);
      expect(r2.metin, 'Net ₺••••');
    });
  });
}
