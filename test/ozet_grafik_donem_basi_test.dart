import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';

import 'helpers/kaynak.dart';

/// Kullanıcı bildirimi (2026-09-23, ekran görüntüsüyle): aynı dönem
/// (16→23 Eyl), aynı kapsam ("Ben"), **iki farklı rakam**:
///
/// | | Özet sekmesi | Grafik sekmesi |
/// |---|---|---|
/// | Piyasa etkisi | +₺46.143 (%1,89) | ₺142.461 |
/// | Toplam değişim | — | +₺223.660 (%9,50) |
/// | Katkı (alım) | +₺81.199 | +₺81.199 |
///
/// ## İkisi de KENDİ İÇİNDE tutarlıydı
/// ```
///   Özet  : 2.354.650 + 81.199 +  46.143 = 2.481.992  ✓ ("Şimdi")
///   Grafik:              81.199 + 142.461 =   223.660  ✓ (üst rakam)
/// ```
///
/// ## Kök neden: FARKLI dönem başı
/// Ters mühendislikle ölçüldü:
/// ```
///   Özet  tabanı = 2.481.992 − (46.143 + 81.199) = 2.354.650
///   Grafik tabanı = 2.481.992 − (142.461 + 81.199) = 2.258.332
///   FARK                                          =    96.318
/// ```
///
/// `PeriodSummaryService.uclar` seriyi `fromMs` ile KIRPAR (dönem
/// penceresi). `_periodEndpoints` ise `spots.first`'ı olduğu gibi alıyordu.
/// Seri çekme penceresi dönem penceresinden GENİŞ olabiliyor (günlük
/// çözünürlükte kenar noktalar; `clipToPeriod` son VERİ noktasına
/// çapalanır) ve o fazladan noktalar tabanı geriye çekiyordu.
void main() {
  group('dönem başı TEK pencereden', () {
    final simdi = DateTime(2026, 9, 23, 14, 0);

    test('fetch penceresi GENİŞSE bile taban dönem başından', () {
      final p = PeriodSummaryService.pencere(SummaryPeriod.birHafta, simdi);

      // Seri 13 Eylül'den başlıyor ama dönem 16 Eylül'de.
      final seri = <int, double>{};
      for (var g = 13; g <= 23; g++) {
        seri[DateTime(2026, 9, g).millisecondsSinceEpoch] =
            2258332.0 + (g - 13) * 22000.0;
      }

      final u = PeriodSummaryService.uclar(seri,
          fromMs: p.start.millisecondsSinceEpoch,
          toMs: p.end.millisecondsSinceEpoch);

      final seriIlk = seri[(seri.keys.toList()..sort()).first]!;

      expect(u!.first, isNot(closeTo(seriIlk, 0.01)),
          reason: 'önkoşul: serinin ilk noktası dönem başından ÖNCE');
      expect(u.first, closeTo(2324332.0, 0.01),
          reason: '16 Eylül noktası — dönem başı');
    });

    test('v <= 0 slotlar İKİ yüzeyde de elenir', () {
      // Borsa açılmadan önceki boş slot dönem başı sanılırsa getiri
      // sonsuza giderdi.
      final t0 = DateTime(2026, 9, 16).millisecondsSinceEpoch;
      final t1 = DateTime(2026, 9, 17).millisecondsSinceEpoch;
      final t2 = DateTime(2026, 9, 23).millisecondsSinceEpoch;
      final u = PeriodSummaryService.uclar({t0: 0.0, t1: 2354650.0, t2: 2481992.0},
          fromMs: t0, toMs: t2);
      expect(u!.first, 2354650.0, reason: 'sıfır slot taban olamaz');
    });
  });

  group('grafik kartı: ÇİZİLENİ ölçer', () {
    test('imza: yalnızca `start` — üst sınır YOK', () {
      // **Üst sınır CANLI UÇ NOKTASINI eliyordu** (kullanıcı bildirimi
      // 2026-09-23, ekran görüntüsüyle): grafik YÜKSELİŞLE bitiyor
      // (₺2,57M → ₺2,58M) ama kart −₺5.875 diyordu.
      //
      // Sebep: `end` build anında `DateTime.now()`, canlı uç ise segment
      // kurulurken yine `DateTime.now()` — birkaç ms SONRA. `s.x > ustX`
      // o tek nokta için doğru çıkıyor ve yeşil nokta düşüyordu.
      //
      // Üst sınıra gerek de yok: `_convertHistoryToSegments` gelecek
      // slotları zaten çizmiyor (`if (ts > nowMs) break`).
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          // `firstX` 2026-09-23'te eklendi: dönem kartı katkıyı tabanın
          // ölçüldüğü andan sonra sayıyor (`piyasaEtkisi` kuralı).
          // `firstTs`/`intraday` 2026-09-24'te eklendi: taban anını eksen
          // birimini bilen tek yer hesaplar. Üst sınır parametresi YOK.
          tek.contains('({double first, double last, double firstX, int? firstTs})? '
              '_periodEndpoints( '
              'List<TransactionSegment> segments, { DateTime? start, '
              'bool intraday = false, })'),
          isTrue,
          reason: 'üst sınır geri gelirse canlı uç yeniden elenir');
      expect(tek.contains('if (s.x > ustX) break;'), isFalse,
          reason: 'üst sınır KALMAMALI');
    });

    test('alt sınır KALIR — dönem öncesi noktalar tabanı çekmesin', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('if (altX != null && s.x < altX) continue;'), isTrue,
          reason: 'seri çekme penceresi dönemden geniş olabiliyor — '
              'ölçüldü: ₺96.318 fark');
    });

    test('`v <= 0` elemesi `uclar` ile AYNI', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('if (s.y <= 0) continue;'), isTrue,
          reason: 'iki yüzey aynı slotları elemeli');
    });

    test('İKİ çağrı da yalnızca `start` geçiyor', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance/kartlar.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          tek.contains(
              '_periodEndpoints(segments, start: start, intraday: intraday)'),
          isTrue,
          reason: 'dönem değişim kartı');
      expect(
          tek.contains('_periodEndpoints(segments, '
              'start: cizimBaslangici, intraday: isIntraday)'),
          isTrue,
          reason: 'tür dökümü üst kartla AYNI tabandan beslenmeli');
    });
  });

  group('kullanıcının kuralı: "baş ile son arasındaki fark"', () {
    /// `_periodEndpoints` ile AYNI mantık (private olduğu için yeniden).
    ({double first, double last})? uclar(List<({double x, double y})> spots) {
      double? first;
      double? last;
      for (final s in spots) {
        if (s.x < 0) continue;
        // Baştaki sıfırlar atlanır; ilk dolu noktadan sonraki sıfır bir
        // ölçümdür (her şey satıldı, 2026-09-24).
        if (first == null && s.y <= 0) continue;
        first ??= s.y;
        last = s.y;
      }
      if (first == null || last == null) return null;
      return (first: first, last: last);
    }

    test('canlı uç SON nokta olarak saydırılır', () {
      // Ekran görüntüsündeki şekil: plato → seans → dip → canlı uç.
      final spots = <({double x, double y})>[
        (x: 0, y: 2570000),      // plato (gece)
        (x: 480, y: 2578000),    // seans zirvesi
        (x: 700, y: 2562000),    // dip
        (x: 845.2, y: 2580000),  // CANLI UÇ (yeşil nokta)
      ];
      final u = uclar(spots)!;
      expect(u.first, 2570000);
      expect(u.last, 2580000, reason: 'yeşil nokta SON olmalı');
      expect(u.last - u.first, 10000,
          reason: 'grafik yükselişle bitiyorsa kart da ARTI demeli');
    });

    test('ÜST SINIR olsaydı ne olurdu (regresyon kanıtı)', () {
      final spots = <({double x, double y})>[
        (x: 0, y: 2570000),
        (x: 480, y: 2578000),
        (x: 700, y: 2562000),
        (x: 845.2, y: 2580000),
      ];
      // `end` build anında alındı -> ustX = 845.0, canlı uç 845.2'de.
      const ustX = 845.0;
      double? first;
      double? last;
      for (final s in spots) {
        if (s.x > ustX) break;
        if (s.y <= 0) continue;
        first ??= s.y;
        last = s.y;
      }
      expect(last, 2562000, reason: 'canlı uç elendi — son nokta DİP oldu');
      expect(last! - first!, -8000,
          reason: 'grafik artıda biterken kart EKSİ yazıyordu '
              '(ölçülen belirti: −₺5.875)');
    });

    test('her şey satıldıysa son nokta 0 — satış öncesi değer DEĞİL', () {
      final spots = <({double x, double y})>[
        (x: 0, y: 0), // veri yok
        (x: 1, y: 30000),
        (x: 7, y: 0), // bugün hepsi satıldı
      ];
      final u = uclar(spots)!;
      expect(u.first, 30000);
      expect(u.last, 0,
          reason: 'satış geliri katkıdan düşülürken uç satış öncesinde '
              'kalırsa piyasa etkisi satış tutarı kadar şişer');
    });

    test('dönem öncesi noktalar tabanı ÇEKMEZ', () {
      final spots = <({double x, double y})>[
        (x: -120, y: 2258332), // dönem ÖNCESİ
        (x: 0, y: 2354650),    // dönem başı
        (x: 845, y: 2481992),
      ];
      final u = uclar(spots)!;
      expect(u.first, 2354650, reason: 'alt sınır çalışmalı');
      expect(u.last, 2481992);
    });
  });

  group('GÜNLÜK: ana sayfayla PARİTE (kullanıcı kararı 2026-09-24)', () {
    // 2026-09-23: GÜNLÜK'te ana rakam arındırılmışa çevrilmişti ("ana
    // sayfa günlük kısmıyla aynı olmalı"). 2026-09-24: kullanıcı kartı
    // görüp geri aldı — *"total birikim değişimine alımlar bu ekranda
    // eklenmeli; altına da bugün sadece piyasanın toplam portföye etkisi
    // yazılmalı."* Parite artık ayrı satırda: "Sadece piyasa etkisi"
    // ana sayfa Bugün kartı ve Özet ile aynı formül ve tabandır.
    test('ana rakam her dönemde HAM birikim', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance/kartlar.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('final change = grossChange;'), isTrue,
          reason: 'başlık "birikim" diyorsa alımlar rakamın içinde olmalı');
      expect(tek.contains('final pctBase = firstY;'), isTrue);
    });

    test('piyasa satırı ana sayfayla AYNI formül ve taban', () {
      // `DailySummary.from`: piyasa = (son − ilk) − akış;
      // taban = gün başı + POZİTİF akış.
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance/kartlar.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('final piyasa = grossChange - netInflow;'), isTrue);
      expect(
          tek.contains(
              'final piyasaPctBase = firstY + (netInflow > 0 ? netInflow : 0);'),
          isTrue,
          reason: 'tutar eşitlenip yüzde ayrışırsa çelişki sürer');
      expect(tek.contains('context.l10n.marketOnlyRow'), isTrue,
          reason: 'piyasa etkisi ayrı satır olarak yazılmalı');
    });

    test('alt kat: Katkın + Sadece piyasa etkisi kalemleri, not yok', () {
      // "Birikim = katkın + piyasa" yerleşimle anlatılır (2026-09-24,
      // tasarım turu): iki eşit kalem, uzun not satırı kalktı.
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance/kartlar.dart');
      final tek = src.replaceAll(RegExp(r'\s+'), ' ');
      expect(tek.contains('etiket: context.l10n.yourContribution,'), isTrue);
      expect(tek.contains('etiket: context.l10n.marketOnlyRow,'), isTrue);
      expect(tek.contains('IncludedNote('), isFalse,
          reason: 'not satırı kalktı, kalemler anlatıyor');
      expect(tek.contains('ExcludedNote('), isFalse,
          reason: 'ham rakamın yanında "içermez" yazmak yanlış olurdu');
    });

    test('formül: alım yapılan günde iki yüzey AYNI', () {
      // Gün ₺2.570.000 ile açtı, ₺100.000'lik alım yapıldı,
      // şu an ₺2.680.000. Gerçek piyasa hareketi: +₺10.000.
      const ilk = 2570000.0;
      const son = 2680000.0;
      const akis = 100000.0;

      final grafik = (son - ilk) - akis; // "Sadece piyasa etkisi" satırı
      final anaSayfa = (son - ilk) - akis; // DailySummary
      expect(grafik, closeTo(anaSayfa, 0.01));
      expect(grafik, closeTo(10000, 0.01), reason: 'saf piyasa hareketi');

      // Ana rakam (birikim): ₺110.000, alım dahil — 2026-09-24 kararıyla
      // kartın başlığındaki rakam bu; piyasa satırı ₺10.000 der.
      expect(son - ilk, closeTo(110000, 0.01),
          reason: 'birikim = piyasa + alım');
    });

    test('alım YAPILMAYAN günde davranış DEĞİŞMEDİ', () {
      const ilk = 2570000.0;
      const son = 2580000.0;
      const akis = 0.0;
      expect((son - ilk) - akis, closeTo(son - ilk, 0.01),
          reason: 'akış yoksa arındırma etkisizdir — regresyon');
    });
  });

  group('köprü aritmetiği (kullanıcının ekranı)', () {
    test('Özet bileşenleri "Şimdi"yi verir', () {
      const donemBasi = 2354650.0;
      const katki = 81199.0;
      const piyasa = 46143.0;
      expect(donemBasi + katki + piyasa, closeTo(2481992.0, 0.01),
          reason: 'Σ parça == bütün');
    });

    test('düzeltmeden SONRA grafik de aynı tabandan beslenir', () {
      // Aynı taban kullanılınca grafik kartının "piyasa hareketi" satırı
      // Özet'in "piyasa" satırıyla eşit olmalı.
      const donemBasi = 2354650.0;
      const simdiDeger = 2481992.0;
      const katki = 81199.0;

      final brut = simdiDeger - donemBasi;
      final piyasa = brut - katki;

      expect(piyasa, closeTo(46143.0, 0.01),
          reason: 'grafik artık ₺142.461 değil ₺46.143 demeli');
    });
  });
}
