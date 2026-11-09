import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/grafik_alarm_cizgisi.dart';
import 'package:portfoy_takip/models/price_alert.dart';

/// Varlık grafiğinde fiyat alarmı çizgisi (Ar-Ge 29 Eki 20:45 #2) — hangi
/// alarm gösterilir, nerede. Ekran bu kararı vermez; burada kilitli.
PriceAlert _a(String id, double hedef,
        {String yon = 'above', bool acik = true, DateTime? caldi}) =>
    PriceAlert(
      id: id,
      userId: 'u',
      symbol: 'ALTIN_GRAM',
      label: 'Gram Altın',
      targetPrice: hedef,
      direction: yon,
      enabled: acik,
      triggeredAt: caldi,
      createdAt: DateTime(2026, 10, 1),
    );

void main() {
  test('aralık içi çizilir, dışı üstünde/altında; Y genişletilmez', () {
    final r = grafikAlarmCizgileri(
      [_a('ic', 4300), _a('ust', 5000), _a('alt', 3000, yon: 'below')],
      minY: 4000,
      maxY: 4500,
    );
    expect({
      for (final c in r) c.alarm.id: c.konum
    }, {
      'ic': AlarmCizgiKonumu.icinde,
      'ust': AlarmCizgiKonumu.ustunde,
      'alt': AlarmCizgiKonumu.altinda,
    });
    expect(r.where((c) => c.cizilir).map((c) => c.alarm.id), ['ic']);
  });

  test('sınırdaki hedef içeride sayılır', () {
    final r = grafikAlarmCizgileri([_a('a', 4000), _a('b', 4500)],
        minY: 4000, maxY: 4500);
    expect(r.every((c) => c.cizilir), isTrue);
  });

  test('yalnız etkin alarm: kapalı ve çalmış gösterilmez', () {
    final r = grafikAlarmCizgileri([
      _a('kapali', 4300, acik: false),
      _a('caldi', 4300, caldi: DateTime(2026, 10, 2)),
      _a('etkin', 4200),
    ], minY: 4000, maxY: 4500);
    expect(r.map((c) => c.alarm.id), ['etkin']);
  });

  test('en çok 3, güncel fiyata en yakın önce (eşitlikte liste sırası)', () {
    final r = grafikAlarmCizgileri([
      _a('uzak', 4490),
      _a('yakin', 4310),
      _a('esit1', 4250, yon: 'below'),
      _a('esit2', 4350),
      _a('cokUzak', 9000),
    ], minY: 4000, maxY: 4500, guncelFiyat: 4300);
    expect(r.map((c) => c.alarm.id), ['yakin', 'esit1', 'esit2']);
  });

  test('güncel fiyat bilinmiyorsa liste sırası korunur (mesafe uydurulmaz)',
      () {
    final r = grafikAlarmCizgileri(
        [_a('1', 4490), _a('2', 4100), _a('3', 4200), _a('4', 4300)],
        minY: 4000, maxY: 4500);
    expect(r.map((c) => c.alarm.id), ['1', '2', '3']);
  });

  test('geçersiz aralık ve geçersiz hedef boş/atlanır', () {
    expect(
        grafikAlarmCizgileri([_a('a', 4300)], minY: 4500, maxY: 4000), isEmpty);
    expect(
        grafikAlarmCizgileri([_a('a', 4300)],
            minY: double.negativeInfinity, maxY: 4500),
        isEmpty);
    expect(
        grafikAlarmCizgileri([_a('sifir', 0), _a('nan', double.nan)],
            minY: -1, maxY: 4500),
        isEmpty);
  });
}
