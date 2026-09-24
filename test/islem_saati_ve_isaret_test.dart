import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:portfoy_takip/models/asset.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/utils/islem_isaretleri.dart';
import 'package:portfoy_takip/utils/spot_lookup.dart';
import 'package:portfoy_takip/utils/tr_format.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı istekleri (2026-09-24, ekran görüntüsüyle):
///   1. *"Portföy hareketlerinde tasarımı bozmadan saat bilgisi de ekle."*
///   2. *"Grafikte gezinirken hangi saatteyim görmeliyim."*
///   3. *"Alış 6.163,57 gösteriliyor ancak yeşil noktaya geldiğimde değeri o
///      değil gibi; alış noktası hatalı yerde gösterilmemeli."*
void main() {
  setUpAll(() => initializeDateFormatting('tr_TR'));

  Asset lot({
    double qty = 100,
    double fiyat = 6163.5727,
    double? satis,
    required DateTime tarih,
    AssetKind kind = AssetKind.buy,
    DateTime? silindi,
  }) =>
      Asset(
        id: 'l',
        userId: 'u',
        name: '22 Ayar Gram Altın',
        ticker: 'ALTIN_GRAM',
        type: AssetType.altin,
        quantity: qty,
        purchasePrice: fiyat,
        currency: 'TRY',
        notes: '',
        addedDate: tarih,
        kind: kind,
        sellPrice: satis,
        deletedAt: silindi,
      );

  group('fmtTarihSaat — saat yalnızca BİLİNİYORSA', () {
    test('gerçek saatli işlem: tarih · saat', () {
      expect(fmtTarihSaat(DateTime(2026, 9, 23, 14, 32)), '23 Eyl 2026 · 14:32');
    });

    test('tarih seçiciyle girilen (00:00) işlemde uydurma saat YOK', () {
      expect(fmtTarihSaat(DateTime(2026, 9, 20)), '20 Eyl 2026');
      expect(saatBiliniyor(DateTime(2026, 9, 20)), isFalse);
    });

    test('grafik: saatlik çubuk saat taşır, günlük çubuk taşımaz', () {
      expect(fmtTarihSaat(DateTime(2026, 9, 17, 15)), '17 Eyl 2026 · 15:00');
      expect(fmtTarihSaat(DateTime(2026, 9, 17)), '17 Eyl 2026');
    });

    test('UTC nesne YEREL saatle yazılır', () {
      final utc = DateTime.utc(2026, 9, 23, 11, 32);
      expect(fmtTarihSaat(utc), fmtTarihSaat(utc.toLocal()));
    });
  });

  group('Asset.fromSupabase — timestamptz YEREL saate çevrilir', () {
    Map<String, dynamic> satir(String addedDate) => {
          'id': 'x',
          'user_id': 'u',
          'name': 'G',
          'ticker': 'ALTIN_GRAM',
          'type': 'altin',
          'quantity': 1,
          'purchase_price': 1,
          'current_price': 1,
          'currency': 'TRY',
          'added_date': addedDate,
        };

    test('an korunur, nesne yerel olur', () {
      final a = Asset.fromSupabase(satir('2026-09-23T11:32:00+00:00'));
      expect(a.addedDate.isUtc, isFalse,
          reason: 'UTC nesnede hour/day UTC alanıdır — saat 3 saat kayar');
      expect(a.addedDate.millisecondsSinceEpoch,
          DateTime.utc(2026, 9, 23, 11, 32).millisecondsSinceEpoch);
    });

    test('yazma → okuma: tarih seçicinin günü KAYMAZ', () {
      // Yerel 20 Eyl 00:00 yazılır (toUtc), geri okunur.
      final yerel = DateTime(2026, 9, 20);
      final yazilan = lot(tarih: yerel).toSupabase()['added_date'] as String;
      final okunan = Asset.fromSupabase(satir(yazilan)).addedDate;
      expect(okunan.day, 20, reason: 'UTC kalsaydı 19 Eyl 21:00 olurdu');
      expect(saatBiliniyor(okunan), isFalse,
          reason: 'saat yine "bilinmiyor" sayılmalı — uydurma 21:00 yok');
    });
  });

  group('islemIsaretleri — gerçek an, gerçek fiyat', () {
    final eksenBasi = DateTime(2026, 9, 17);

    test('EKRAN VAKASI: 23 Eyl 14:32 alım, alış 6.163,57', () {
      final m = islemIsaretleri(
        lotlar: [lot(tarih: DateTime(2026, 9, 23, 14, 32))],
        eksenBasi: eksenBasi,
        ilkX: 0,
        sonX: 7.1,
      );
      expect(m, hasLength(1));
      expect(m.single.birim, closeTo(6163.5727, 1e-9),
          reason: 'işaretin yüksekliği ALIŞ fiyatı, çizginin değeri değil');
      expect(m.single.x, closeTo(6 + (14 * 60 + 32) / 1440, 1e-9),
          reason: 'X işlem anı — 00:00 çubuğuna çekilmez');
    });

    test('satış işareti SATIŞ fiyatında', () {
      final m = islemIsaretleri(
        lotlar: [
          lot(
              kind: AssetKind.sell,
              fiyat: 9636.13,
              satis: 10825.77,
              tarih: DateTime(2026, 9, 23, 11)),
        ],
        eksenBasi: eksenBasi,
        ilkX: 0,
        sonX: 7.1,
      );
      expect(m.single.satis, isTrue);
      expect(m.single.birim, closeTo(10825.77, 1e-9));
    });

    test('temettü, silinmiş lot ve pencere öncesi işlem işaret ÜRETMEZ', () {
      final m = islemIsaretleri(
        lotlar: [
          lot(kind: AssetKind.dividend, tarih: DateTime(2026, 9, 20, 10)),
          lot(tarih: DateTime(2026, 9, 20, 10), silindi: DateTime(2026, 9, 21)),
          lot(tarih: DateTime(2026, 9, 10, 10)),
        ],
        eksenBasi: eksenBasi,
        ilkX: 0,
        sonX: 7.1,
      );
      expect(m, isEmpty);
    });

    test('veri başlamadan yapılan işlem eksenin İÇİNE yaslanır', () {
      final m = islemIsaretleri(
        lotlar: [lot(tarih: DateTime(2026, 9, 17, 0, 30))],
        eksenBasi: eksenBasi,
        ilkX: 0.05, // ilk nokta 01:12
        sonX: 1,
      );
      expect(m.single.x, 0.05);
    });
  });

  group('kaynak: yüzeyler ortak kurala bağlı', () {
    String kod(String yol) => ekranKaynagiSync(yol)
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join(' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    test('hareket satırı saati fmtTarihSaat ile yazar', () {
      expect(kod('lib/widgets/transaction_row.dart')
          .contains('fmtTarihSaat(asset.addedDate)'), isTrue);
    });

    test('grafik etiketleri gün içi dışında da saat gösterebilir', () {
      expect(kod('lib/screens/asset_detail_screen.dart')
          .contains(': fmtTarihSaat(date);'), isTrue);
      expect(kod('lib/screens/portfolio_performance/grafik_kabi.dart')
          .contains(': fmtTarihSaat(date);'), isTrue);
      expect(kod('lib/widgets/percent_comparison_chart.dart')
          .contains(': fmtTarihSaat(tarih)'), isTrue);
    });

    test("işlem noktası işlem ANINDA, ÇİZGİNİN ÜSTÜNDE; fiyat crosshair'da",
        () {
      final s = kod('lib/screens/asset_detail_screen.dart');
      expect(s.contains('islemIsaretleri('), isTrue);
      expect(s.contains('lotDayIsSell'), isFalse,
          reason: 'çubuğa yapıştırma işlemi gece yarısına çekiyordu');
      expect(s.contains('cizgiDegeri(cizgiSpots, t.x)'), isTrue,
          reason: 'nokta çizgiden kopuk durunca "dışarıda" görünüyordu '
              '(kullanıcı bildirimi 2026-09-24 sabah)');
      expect(s.contains('crosshairDetailsBuilder: islemler.isEmpty'), isTrue,
          reason: 'crosshair işlemin kendi zamanını ve fiyatını yazmalı');
    });
  });

  group("cizgiDegeri — düz çizginin x'teki yüksekliği", () {
    const spots = [FlSpot(0, 100), FlSpot(1, 110), FlSpot(2, 90)];

    test('iki nokta arasında doğrusal', () {
      expect(cizgiDegeri(spots, 0.5), closeTo(105, 1e-9));
      expect(cizgiDegeri(spots, 1.25), closeTo(105, 1e-9));
    });

    test('noktanın tam üstünde o noktanın değeri', () {
      expect(cizgiDegeri(spots, 1), 110);
    });

    test('aralık dışı uca yaslanır, boş liste null', () {
      expect(cizgiDegeri(spots, -1), 100);
      expect(cizgiDegeri(spots, 5), 90);
      expect(cizgiDegeri(const [], 1), isNull);
    });

    test('EKRAN VAKASI: 14:32 alımı çizginin o andaki değerinde; alış '
        'fiyatı crosshair için ayrı kalır', () {
      final m = islemIsaretleri(
        lotlar: [lot(tarih: DateTime(2026, 9, 23, 14, 32))],
        eksenBasi: DateTime(2026, 9, 17),
        ilkX: 0,
        sonX: 7.1,
      ).single;
      const cizgi = [FlSpot(6, 6300), FlSpot(7, 6400)];
      expect(cizgiDegeri(cizgi, m.x),
          closeTo(6300 + 100 * (14 * 60 + 32) / 1440, 1e-6));
      expect(m.birim, closeTo(6163.5727, 1e-9));
    });
  });
}
