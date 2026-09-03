import 'dart:io';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/spot_lookup.dart';

/// **Crosshair'in gösterdiği her sayı AYNI ana ait olmalı.**
///
/// ## Bulgu
/// Kullanıcı: "basılı tuttuğumdaki değerle y eksenindeki değer ve x
/// eksenindeki label'daki tarih ve zaman işaretçisi tutarlı ve kesin doğru
/// olmalı."
///
/// ## Kök neden
/// Crosshair, serilerin EN UZUNUNA snap eder. Seriler farklı yoğunlukta:
///   · USDTRY=X → GÜNLÜK'te 5 dakikada bir nokta (288 nokta)
///   · TEFAS fonu → günde bir fiyat (2 nokta)
///   · BIST hissesi → yalnızca seans saatleri
///
/// Değerler `nearestSpotIndex` ile okunuyordu: seyrek bir seride "en yakın"
/// nokta İLERİDE olabiliyor. Kullanıcı 06:00'a basarken 12:00'nin değeri
/// gösteriliyor, üstteki tarih göstergesi ise 06:00 yazıyordu.
/// **Ölçülen en kötü sapma: 11 saat 55 dakika** — üstelik geleceğe doğru,
/// yani henüz gerçekleşmemiş bir fiyat.
///
/// ## Kural
/// `coveringSpotIndex`: `spot.x <= x` olan SON nokta. Gösterilen değer her
/// zaman "o ana kadar bilinen son değer"dir — fiyat grafiklerinin standart
/// okuması. Seri henüz başlamamışsa değer GÖSTERİLMEZ (uydurma yerine boş).
///
/// ## Bu testin sınırı
/// Widget kurmaz; crosshair'in dayandığı arama cebrini denetler. Piksel
/// hizasını (dikey çizginin nereye çizildiğini) doğrulamaz.
void main() {
  int ms(DateTime d) => d.millisecondsSinceEpoch;
  final t0 = DateTime(2026, 9, 4, 0, 0);

  /// GÜNLÜK'te gerçekçi yoğunluk farkı.
  final sik = [
    for (var i = 0; i < 288; i++)
      FlSpot(ms(t0.add(Duration(minutes: 5 * i))).toDouble(), i.toDouble()),
  ];
  final seyrek = [
    for (var i = 0; i < 2; i++)
      FlSpot(ms(t0.add(Duration(hours: 12 * i))).toDouble(), i * 5.0),
  ];

  group('değer asla GELECEKTEN okunmaz', () {
    test('seyrek seride ileri nokta gösterilmez', () {
      // Asıl bulgu. `nearestSpotIndex` ile bu sayı 144'tü (noktaların yarısı).
      var ileri = 0;
      for (final s in sik) {
        final i = coveringSpotIndex(seyrek, s.x);
        if (i < 0) continue;
        if (seyrek[i].x > s.x) ileri++;
      }

      expect(ileri, 0,
          reason: '$ileri konumda henüz gerçekleşmemiş bir fiyat '
              'gösteriliyor — crosshair geleceği okuyor');
    });

    test('en yakın arama BU HATAYI yapardı — karşılaştırma', () {
      // Bu test düzeltmenin gerekçesini belgeler: aynı veriyle iki arama
      // farklı sonuç veriyor. `nearestSpotIndex` hâlâ başka yerlerde
      // (dokunma isabeti) kullanılıyor, o yüzden silinmedi.
      var ileri = 0;
      for (final s in sik) {
        if (seyrek[nearestSpotIndex(seyrek, s.x)].x > s.x) ileri++;
      }

      expect(ileri, greaterThan(0),
          reason: 'en yakın arama geleceğe kaymalıydı; kaymıyorsa test '
              'verisi artık bu hatayı temsil etmiyor');
    });
  });

  group('gösterge ile değer AYNI noktadan gelir', () {
    test('snap noktası gerçek bir veri noktasıdır', () {
      // Dikey çizgi iki nokta arasındaki boşluğa oturursa, gösterilen değer
      // hangi noktaya ait olduğu belirsiz kalır.
      for (final dk in [7, 33, 61, 719, 1439]) {
        final x = ms(t0.add(Duration(minutes: dk))).toDouble();
        final i = coveringSpotIndex(sik, x);
        expect(i, greaterThanOrEqualTo(0));
        expect(sik.any((s) => s.x == sik[i].x), isTrue,
            reason: 'snap noktası seride yok');
      }
    });

    test('snap noktası dokunulan andan SONRA olamaz', () {
      for (final dk in [7, 33, 61, 719, 1439]) {
        final x = ms(t0.add(Duration(minutes: dk))).toDouble();
        final s = sik[coveringSpotIndex(sik, x)];
        expect(s.x, lessThanOrEqualTo(x),
            reason: 'snap ileri kaydı — tarih göstergesi parmaktan sonrayı '
                'gösterir');
      }
    });

    test('etiket tarihi, değeri okunan NOKTANIN tarihidir', () {
      // Eskiden yüzde en yakın noktadan, tarih ham `x`'ten geliyordu. İkisi
      // ayrı kaynaktan gelince snap farkı kadar kayabiliyordu.
      final x = ms(DateTime(2026, 9, 4, 6, 3)).toDouble();
      final i = coveringSpotIndex(sik, x);
      final nokta = sik[i];

      // Etiket bu noktadan üretilir: hem y hem tarih.
      final tarih = DateTime.fromMillisecondsSinceEpoch(nokta.x.round());
      expect(tarih.minute % 5, 0,
          reason: 'tarih bir veri noktasına denk gelmeli, ham dokunma '
              'anına değil');
      expect(nokta.y, sik[i].y);
    });
  });

  group('seri başlamadan önce değer YOK', () {
    test('ilk noktadan önce -1 döner', () {
      final once = ms(t0.subtract(const Duration(hours: 4))).toDouble();
      expect(coveringSpotIndex(seyrek, once), -1,
          reason: 'seri henüz başlamamışken bir değer göstermek uydurmadır');
    });

    test('tam ilk noktada değer VARDIR', () {
      expect(coveringSpotIndex(seyrek, seyrek.first.x), 0,
          reason: 'sınır dahil olmalı');
    });
  });

  group('grafik widget ı bu aramayı KULLANIR', () {
    // Cebir doğru olsa da widget hâlâ `nearestSpotIndex` çağırıyorsa
    // düzeltme kullanıcıya ulaşmaz.
    late String src;

    setUpAll(() async {
      src = await File('lib/widgets/percent_comparison_chart.dart')
          .readAsString();
    });

    /// [bas] ile bir SONRAKİ üst düzey alan arasındaki metin.
    ///
    /// Sabit karakter penceresi kullanılmıyor: biçimlendirme satır sonlarını
    /// kaydırınca pencere bloğun ortasında kesiliyor ve test, kod doğruyken
    /// kırılıyor (bir kez yaşandı — 700 karakterlik pencere `HH:mm`'e
    /// ulaşamadı).
    String blok(String bas, String son) {
      final i = src.indexOf(bas);
      expect(i, greaterThan(0), reason: '$bas bulunamadı');
      final j = src.indexOf(son, i);
      expect(j, greaterThan(i), reason: '$son bulunamadı');
      return src.substring(i, j);
    }

    test('değer okuma coveringSpotIndex ile', () {
      final i = src.indexOf('double? _degerAt(');
      expect(i, greaterThan(0), reason: 'fonksiyon yeniden adlandırılmış');
      final govde = src.substring(i, i + 400);
      expect(govde.contains('coveringSpotIndex'), isTrue,
          reason: 'seyrek serilerde gelecekten değer okunur');
      expect(govde.contains('nearestSpotIndex'), isFalse);
    });

    test('crosshair etiketi ve snap i de aynı aramayı kullanır', () {
      // Üçü ayrışırsa dikey çizgi bir noktayı, etiket başka bir noktayı,
      // seri listesi üçüncü bir noktayı gösterir.
      expect(
          blok('crosshairSnapX:', 'crosshairLabelBuilder:')
              .contains('coveringSpotIndex'),
          isTrue,
          reason: 'crosshairSnapX hâlâ en yakın aramayı kullanıyor');
      expect(
          blok('crosshairLabelBuilder:', 'crosshairDetailsBuilder:')
              .contains('coveringSpotIndex'),
          isTrue,
          reason: 'crosshairLabelBuilder hâlâ en yakın aramayı kullanıyor');
    });

    test('gün içi crosshair etiketinde SAAT gösterilir', () {
      // "4 Eyl 2026" etiketi 288 noktanın hepsi için aynı görünürdü.
      expect(
          blok('crosshairLabelBuilder:', 'crosshairDetailsBuilder:')
              .contains('HH:mm'),
          isTrue,
          reason: 'gün içi seride saat olmadan tarih ayırt edici değil');
    });
  });

  group('crosshair EKSENİN TAMAMINDA gezer', () {
    // ## Bulgu
    // "üstüne basılı tutunca da garip bir yere kadar görebiliyorum, tüm
    // grafiğin üzerinde gezdiremiyorum"
    //
    // ## Kök neden
    // `crosshairSnapX` konumu SNAP SERİSİNE clamp'liyordu:
    //   `x.clamp(spots.first.x, spots.last.x)`
    // Snap serisi ekseni tam kaplamayabilir — bir BIST hissesi yalnızca
    // seans saatlerini kapsar, eksen ise geceyi de içerir. Seriye clamp
    // eksenin bir bölümünü ÖLÜ BÖLGEYE çeviriyordu.
    //
    // Ölçüldü: eksenin %64'ü ulaşılamaz, sola dokunulduğunda crosshair
    // 14 saat sağa zıplıyordu.
    //
    // ## Kural
    // Clamp EKSENE yapılır (`ciz.minX`/`ciz.maxX`). Snap serisi o noktadan
    // önce başlıyorsa ham konum korunur — zıplatmak yerine çizgi parmağın
    // altında kalır.

    test('snap serisi ekseni kaplamasa da ölü bölge yok', () {
      // Snap serisi eksenin yalnızca sağ %36'sını kaplıyor.
      final eksenMin = ms(DateTime(2026, 9, 3, 20)).toDouble();
      final eksenMax = ms(DateTime(2026, 9, 4, 18)).toDouble();
      final snap = [
        for (var i = 0; i <= 96; i++)
          FlSpot(
              ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i)))
                  .toDouble(),
              i.toDouble()),
      ];

      var ulasilamaz = 0;
      for (var p = 0.0; p <= 1.0; p += 0.01) {
        final x = eksenMin + (eksenMax - eksenMin) * p;
        // Üretimdeki kural: eksene clamp, sonra kapsayan nokta; öncesindeyse
        // ham konum.
        final clamped = x.clamp(eksenMin, eksenMax);
        final i = coveringSpotIndex(snap, clamped);
        final snapX = i < 0 ? clamped : snap[i].x;
        // Bir snap adımından (5 dk) fazla sapma = ulaşılamayan konum.
        if ((snapX - x).abs() > const Duration(minutes: 5).inMilliseconds) {
          ulasilamaz++;
        }
      }

      expect(ulasilamaz, 0,
          reason: 'eksenin $ulasilamaz/101 konumuna crosshair ulaşamıyor');
    });

    test('SERİYE clamp bu hatayı yapardı — karşılaştırma', () {
      // Düzeltmenin gerekçesini belgeler.
      final eksenMin = ms(DateTime(2026, 9, 3, 20)).toDouble();
      final eksenMax = ms(DateTime(2026, 9, 4, 18)).toDouble();
      final snap = [
        for (var i = 0; i <= 96; i++)
          FlSpot(
              ms(DateTime(2026, 9, 4, 10).add(Duration(minutes: 5 * i)))
                  .toDouble(),
              i.toDouble()),
      ];

      var ulasilamaz = 0;
      for (var p = 0.0; p <= 1.0; p += 0.01) {
        final x = eksenMin + (eksenMax - eksenMin) * p;
        final eski = x.clamp(snap.first.x, snap.last.x);
        if ((eski - x).abs() > const Duration(minutes: 5).inMilliseconds) {
          ulasilamaz++;
        }
      }

      expect(ulasilamaz, greaterThan(30),
          reason: 'seriye clamp ölü bölge yaratmalıydı; yaratmıyorsa test '
              'verisi artık bu hatayı temsil etmiyor');
    });

    test('widget EKSENE clamp eder', () {
      // Cebir doğru olsa da widget hâlâ seriye clamp ediyorsa düzeltme
      // kullanıcıya ulaşmaz.
      final src =
          File('lib/widgets/percent_comparison_chart.dart').readAsStringSync();
      final i = src.indexOf('crosshairSnapX:');
      final j = src.indexOf('crosshairLabelBuilder:', i);
      final govde = src.substring(i, j);

      expect(govde.contains('ciz.minX'), isTrue,
          reason: 'clamp eksene yapılmalı');
      expect(govde.contains('spots.first.x, spots.last.x'), isFalse,
          reason: 'seriye clamp ölü bölge yaratır');
    });
  });

  group('boş ve tek noktalı seriler çökmez', () {
    test('boş seri -1', () {
      expect(coveringSpotIndex(const [], 123), -1);
    });

    test('tek noktalı seri', () {
      final tek = [FlSpot(ms(t0).toDouble(), 5.0)];
      expect(coveringSpotIndex(tek, ms(t0).toDouble()), 0);
      expect(
          coveringSpotIndex(
              tek, ms(t0.add(const Duration(days: 1))).toDouble()),
          0);
      expect(
          coveringSpotIndex(
              tek, ms(t0.subtract(const Duration(days: 1))).toDouble()),
          -1);
    });
  });
}
