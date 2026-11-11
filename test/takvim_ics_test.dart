import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/halka_arz.dart';
import 'package:portfoy_takip/providers/preferences_provider.dart'
    show premiumKilitliProvider;
import 'package:portfoy_takip/providers/temettu_tahmini_provider.dart';
import 'package:portfoy_takip/screens/temettu_tahmini_screen.dart';
import 'package:portfoy_takip/services/halka_arz_takvim.dart';
import 'package:portfoy_takip/services/takvim_ics.dart';
import 'package:portfoy_takip/services/temettu_tahmini.dart';
import 'package:portfoy_takip/theme/sandik.dart';
import 'package:portfoy_takip/widgets/takvime_ekle_dugmesi.dart';

/// Genel "Takvime ekle" üreticisi (2026-11-11): halka arzdan ayrıldı;
/// mevduat vadesi, Eurobond kuponu ve beklenen temettü de kullanır.

final _simdi = DateTime.utc(2026, 11, 8, 7, 5, 9);

List<String> _acik(String ics) =>
    ics.replaceAll('\r\n ', '').split('\r\n')..removeLast();

void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  group('takvimIcs (saf)', () {
    test('boş liste → null (boş dosya paylaşılmaz)', () {
      expect(takvimIcs(etkinlikler: const [], simdi: _simdi), isNull);
    });

    test('tüm gün: DATE değeri, DTEND ertesi gün, ay sonu taşar', () {
      final ics = takvimIcs(etkinlikler: [
        TakvimEtkinligi(uid: 'x', gun: DateTime(2026, 12, 31), baslik: 'B'),
      ], simdi: _simdi)!;
      final s = _acik(ics);
      expect(s, contains('DTSTART;VALUE=DATE:20261231'));
      expect(s, contains('DTEND;VALUE=DATE:20270101'));
      expect(s, contains('UID:x@sandik'));
      expect(s, contains('DTSTAMP:20261108T070509Z'));
      expect(s.where((l) => l.startsWith('DESCRIPTION')), isEmpty,
          reason: 'açıklama verilmediyse satır yazılmaz');
      expect(ics.endsWith('\r\n'), isTrue);
    });

    test('kaçış: başlık ve açıklamada virgül, noktalı virgül, satır sonu', () {
      final s = _acik(takvimIcs(etkinlikler: [
        TakvimEtkinligi(
            uid: 'k',
            gun: DateTime(2027, 1, 15),
            baslik: 'A, B; C',
            aciklama: 'satır\nikinci'),
      ], simdi: _simdi)!);
      expect(s, contains(r'SUMMARY:A\, B\; C'));
      expect(s, contains(r'DESCRIPTION:satır\nikinci'));
    });

    test('çoklu etkinlik ve şemasız URL yazılmaz', () {
      final ics = takvimIcs(etkinlikler: [
        TakvimEtkinligi(
            uid: 'a', gun: DateTime(2027, 1, 1), baslik: '1', url: 'ornek'),
        TakvimEtkinligi(
            uid: 'b',
            gun: DateTime(2027, 2, 1),
            baslik: '2',
            url: 'https://o.test'),
      ], simdi: _simdi)!;
      final s = _acik(ics);
      expect(s.where((l) => l == 'BEGIN:VEVENT').length, 2);
      expect(s.where((l) => l.startsWith('URL:')), ['URL:https://o.test']);
      expect(s, contains('PRODID:-//sandik//takvim//TR'));
    });
  });

  test('halka arz çıktısı genel üreticiye geçince birebir aynı', () {
    final ics = halkaArzIcs(
      arz: HalkaArz(
        kod: 'NETGL',
        sirket: 'Örnek, A.Ş.',
        kaynak: 'https://ornek.test/netgl',
        talepBitis: DateTime(2026, 11, 20),
        islemBaslangic: DateTime(2026, 11, 27),
      ),
      talepSonBaslik: 'NETGL talep son günü',
      islemBaslik: 'NETGL işlem başlangıcı',
      simdi: _simdi,
    );
    // Ayrıştırmadan önceki üreticinin çıktısı (2026-11-11'de eski kodla
    // karşılaştırılıp sabitlendi).
    const olay = [
      ('talep-son', '20261120', '20261121', 'NETGL talep son günü'),
      ('islem-baslangic', '20261127', '20261128', 'NETGL işlem başlangıcı'),
    ];
    final beklenen = [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//sandik//halka arz takvimi//TR',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      for (final (t, b, s, ad) in olay) ...[
        'BEGIN:VEVENT',
        'UID:NETGL-$t-$b@sandik',
        'DTSTAMP:20261108T070509Z',
        'DTSTART;VALUE=DATE:$b',
        'DTEND;VALUE=DATE:$s',
        'SUMMARY:$ad',
        r'DESCRIPTION:Örnek\, A.Ş.\nhttps://ornek.test/netgl',
        'URL:https://ornek.test/netgl',
        'TRANSP:TRANSPARENT',
        'END:VEVENT',
      ],
      'END:VCALENDAR',
    ];
    expect(ics, '${beklenen.map(icsKatla).join('\r\n')}\r\n');
  });

  group('TakvimeEkleDugmesi', () {
    Future<void> ciz(WidgetTester t, List<TakvimEtkinligi> e) =>
        t.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
            body: Center(
              child:
                  TakvimeEkleDugmesi(etkinlikler: e, dosyaAdi: 'x', konu: 'k'),
            ),
          ),
        ));

    testWidgets('tarih varken görünür, 44 pt, etiketli', (t) async {
      await ciz(t, [
        TakvimEtkinligi(uid: 'v', gun: DateTime(2027, 3, 1), baslik: 'Vade'),
      ]);
      final d = find.byTooltip('Takvime ekle');
      expect(d, findsOneWidget);
      final boy = t.getSize(find.byType(IconButton));
      expect(boy.width, greaterThanOrEqualTo(SandikTouch.min));
      expect(boy.height, greaterThanOrEqualTo(SandikTouch.min));
    });

    testWidgets('tarih yokken çizilmez (uydurma tarih yok)', (t) async {
      await ciz(t, const []);
      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('temettü tahmini ekranı', () {
    Future<void> ciz(WidgetTester t, List<DateTime> hakGunleri) =>
        t.pumpWidget(ProviderScope(
          overrides: [
            premiumKilitliProvider.overrideWithValue(false),
            temettuTahminiProvider.overrideWith((ref) async => TemettuTahmini(
                  satirlar: [
                    TahminSatiri(
                      ad: 'THYAO',
                      sembol: 'THYAO.IS',
                      lot: 10,
                      brutPay: 5,
                      brutTry: 50,
                      netTry: 45,
                      aylar: const [6],
                      hakGunleri: hakGunleri,
                    ),
                  ],
                  aylik: List.filled(12, 0),
                )),
          ],
          child: MaterialApp(
              theme: ThemeData.light(), home: const TemettuTahminiScreen()),
        ));

    testWidgets('geçen yılın hak günü varsa düğme var', (t) async {
      final n = DateTime.now();
      // Geçen yıl, bugünden bir ay sonrası → yıl dönümü önümüzde.
      await ciz(t,
          [DateTime.utc(n.year - 1, n.month, 1).add(const Duration(days: 40))]);
      await t.pump();
      await t.pump();
      expect(find.byTooltip('Takvime ekle'), findsOneWidget);
    });

    testWidgets('hak günü bilinmiyorsa düğme yok', (t) async {
      await ciz(t, const []);
      await t.pump();
      await t.pump();
      expect(find.text('THYAO'), findsOneWidget);
      expect(find.byTooltip('Takvime ekle'), findsNothing);
    });
  });
}
