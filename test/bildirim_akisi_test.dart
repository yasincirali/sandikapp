import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/models/bildirim_akisi.dart';
import 'package:portfoy_takip/models/price_alert_notification.dart';
import 'package:portfoy_takip/models/signal_alert.dart';
import 'package:portfoy_takip/models/technical_signal.dart';

SignalAlert _sinyal(String id, DateTime t, {DateTime? dismissed}) => SignalAlert(
      id: id,
      assetId: 'a-$id',
      assetName: 'Varlık $id',
      assetTicker: 'TCK',
      assetType: AssetType.hisse,
      signal: SignalType.buy,
      buyCount: 3,
      sellCount: 1,
      confidence: 0.7,
      detectedAt: t,
      dismissedAt: dismissed,
    );

PriceAlertNotification _alarm(String id, DateTime t, {DateTime? dismissed}) =>
    PriceAlertNotification(
      id: id,
      symbol: 'ALTIN_GRAM',
      label: 'Gram Altın',
      targetPrice: 6700,
      triggeredPrice: 6710.67,
      direction: 'above',
      sentAt: t,
      dismissedAt: dismissed,
    );

void main() {
  final t0 = DateTime(2026, 9, 15, 10);
  final t1 = DateTime(2026, 9, 15, 11);
  final t2 = DateTime(2026, 9, 15, 12);

  test('iki tür tek akışta, en yeni önce', () {
    final akis = bildirimAkisi(
      [_sinyal('s1', t0), _sinyal('s2', t2)],
      [_alarm('p1', t1)],
    );
    expect(akis.map((e) => e.kimlik).toList(), ['s2', 'p1', 's1']);
  });

  test('tür ayrımı korunur — satır nasıl çizileceğini bilir', () {
    final akis = bildirimAkisi([_sinyal('s1', t0)], [_alarm('p1', t1)]);
    expect(akis.first, isA<FiyatAlarmiOgesi>());
    expect(akis.last, isA<SinyalOgesi>());
  });

  test('dismissEdilmis türden bağımsız okunur', () {
    final akis = bildirimAkisi(
      [_sinyal('s1', t2, dismissed: t2)],
      [_alarm('p1', t1)],
    );
    expect(akis[0].dismissEdilmis, isTrue);
    expect(akis[1].dismissEdilmis, isFalse);
  });

  test('kimliksiz sinyal listeye ALINMAZ — dokunulunca hiçbir şey olmazdı', () {
    final akis = bildirimAkisi(
      [_sinyal('', t2), SignalAlert(
        assetId: 'x', assetName: 'X', assetTicker: '',
        assetType: AssetType.hisse, signal: SignalType.buy,
        buyCount: 1, sellCount: 0, confidence: 0.5, detectedAt: t2,
      )],
      [_alarm('p1', t1)],
    );
    expect(akis.map((e) => e.kimlik).toList(), ['p1']);
  });

  test('eşit zamanda sıra KARARLI — liste titremez', () {
    final a = bildirimAkisi([_sinyal('bbb', t1)], [_alarm('aaa', t1)]);
    final b = bildirimAkisi([_sinyal('bbb', t1)], [_alarm('aaa', t1)]);
    expect(a.map((e) => e.kimlik).toList(), b.map((e) => e.kimlik).toList());
    expect(a.first.kimlik, 'aaa');
  });

  test('boş girdiler boş akış', () {
    expect(bildirimAkisi(const [], const []), isEmpty);
  });

  test('tek tür varken de çalışır', () {
    expect(bildirimAkisi([_sinyal('s1', t0)], const []).length, 1);
    expect(bildirimAkisi(const [], [_alarm('p1', t0)]).length, 1);
  });
}
