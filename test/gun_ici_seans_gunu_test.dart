import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';

/// **"GÜNLÜK" sekmesi DÜMDÜZ bir çizgi çiziyordu.**
///
/// Kullanıcı bildirimi (2026-09-07): "günlük grafik için data
/// alınamıyor olabilir mi, normalde yüksek precision ile göstermesi
/// gerekirdi. Dümdüz çizgi sebebi nedir."
///
/// İki bağımsız sebep vardı ve ikisi de burada kilitleniyor:
///
/// 1. **Izgara her zaman BUGÜNE kuruluyordu.** Piyasa kapalıyken (hafta
///    sonu, tatil) Yahoo'nun `range=1d` yanıtı son seansa aittir; o
///    noktalar bugünün 288 slotuna yayılınca seri tek bir değere
///    dönüşüyordu. Karar artık `HistoryService.seansGunu` içinde ve saf
///    olduğu için hafta içi koşan bir testte de doğrulanabiliyor.
///
/// 2. **Y ekseninin asgari bandı %8'di.** Portföyün gün içi hareketi
///    tipik olarak ±%0,5–2 olduğundan gerçek dalgalanma grafik
///    yüksekliğinin onda birine sıkışıyordu.
void main() {
  int ts(DateTime d) => d.millisecondsSinceEpoch;

  group('seans günü — hangi gün çizilir', () {
    test('veri bugüne aitse bugün çizilir', () {
      final now = DateTime(2026, 9, 4, 15, 30); // Cuma
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 4, 15, 25)),
      );
      expect(gun, DateTime(2026, 9, 4));
    });

    // ── KARAR DEĞİŞTİ (2026-09-13) ────────────────────────────────────
    //
    // Aşağıdaki üç test eskiden "son seans çizilmeli" diyordu. Kullanıcı
    // kararıyla tersine döndü: "Ayın 13'ünde günlük tabında 12 Eylül
    // verisini görmemeliyim."
    //
    // Eski kural iki yeni sorun doğurmuştu:
    //   1. Sekme adı yalan söylüyordu — "GÜNLÜK" başka bir günü gösteriyor.
    //   2. Seri son seansın son damgasında bitiyor, ekran ucuna CANLI
    //      toplamı ekliyordu; arada nokta olmadığı için grafik düz gidip
    //      "şimdi"ye ATLIYORDU (ekran görüntüsüyle bildirildi).
    //
    // Düz çizgi artık kabul edilebilir çünkü onu AÇIKLAYAN bir rozet var
    // (`piyasa_kapali_etiketi.dart`). 2026-09-07'de o rozet yoktu; düz
    // çizgi sessizdi ve bu yüzden korkutucuydu.
    //
    // Ayrıntılı gerekçe ve sınır durumları: `gunluk_sekmesi_bugun_test`.

    test('PAZAR günü de BUGÜN çizilir — sekme adı dürüst olmalı', () {
      final now = DateTime(2026, 9, 6, 11, 0); // Pazar
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 4, 18, 5)), // Cuma kapanışı
      );
      expect(gun, DateTime(2026, 9, 6),
          reason: 'GÜNLÜK sekmesi içinde bulunulan günü çizer');
    });

    test('PAZARTESİ açılıştan ÖNCE de bugün çizilir', () {
      // Gün Pazartesi ama BIST henüz açılmamış. Seri düz olacak — bu
      // DOĞRU ve rozet bunu açıklıyor.
      final now = DateTime(2026, 9, 7, 9, 30);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 4, 18, 5)),
      );
      expect(gun, DateTime(2026, 9, 7));
    });

    test('PAZARTESİ seans başladıysa bugün çizilir', () {
      final now = DateTime(2026, 9, 7, 11, 0);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 7, 10, 55)),
      );
      expect(gun, DateTime(2026, 9, 7));
    });

    test('resmî tatilde de BUGÜN çizilir — tatil listesi gerekmez', () {
      // Tatil takvimi tutmuyoruz ve artık gerekmiyor: kural "her zaman
      // bugün" olduğu için tatilin hafta içine düşmesi fark etmiyor.
      final now = DateTime(2026, 4, 23, 12, 0);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 4, 22, 18, 5)),
      );
      expect(gun, DateTime(2026, 4, 23));
    });

    test('hiç veri yoksa bugüne düşülür — boş ızgara üretilmez', () {
      final now = DateTime(2026, 9, 6, 11, 0);
      expect(
        HistoryService.seansGunu(now: now, enSonVeriTs: null),
        DateTime(2026, 9, 6),
      );
    });

    test('gelecek tarihli veri ileri bir güne ızgara kurmaz', () {
      // Saat dilimi kayması Yahoo damgasını bir gün ileri atabilir.
      // Yarına ızgara kurmak "gelecek slotları çizme" kuralıyla
      // birleşince BOŞ grafik demek olurdu.
      final now = DateTime(2026, 9, 4, 15, 0);
      final gun = HistoryService.seansGunu(
        now: now,
        enSonVeriTs: ts(DateTime(2026, 9, 5, 2, 0)),
      );
      expect(gun, DateTime(2026, 9, 4));
    });
  });

  group('Y ekseni — gün içi hareket ezilmez', () {
    // 250.000 TL'lik portföy, gün içinde %1 hareket (2.500 TL).
    const double ortalama = 250000;
    const double alt = 248750;
    const double ust = 251250;

    ({double minY, double maxY, double interval}) bant(double oran) =>
        gorunurYBandi(
          dataMinY: alt,
          dataMaxY: ust,
          avgY: ortalama,
          asgariBantOrani: oran,
        );

    test('%1 hareket bandın anlamlı bir kısmını doldurur', () {
      final b = bant(gunIciAsgariBantOrani);
      final bantYuksekligi = b.maxY - b.minY;
      const hareket = ust - alt;
      // Hareket, bandın en az beşte birini kaplamalı. Eski %8'lik taban
      // bunu ~%10'a düşürüyordu ve çizgi düz görünüyordu.
      expect(hareket / bantYuksekligi, greaterThan(0.2),
          reason: 'gün içi hareket grafikte okunabilir olmalı');
    });

    test('eski %8 tabanı aynı veriyi ezerdi — regresyon kilidi', () {
      final yeni = bant(gunIciAsgariBantOrani);
      final eski = bant(0.08);
      expect(yeni.maxY - yeni.minY, lessThan(eski.maxY - eski.minY),
          reason: 'gün içi bandı daralmalı');
    });

    test('veri HER ZAMAN bandın içinde kalır', () {
      for (final oran in [gunIciAsgariBantOrani, 0.08]) {
        final b = bant(oran);
        expect(b.minY, lessThanOrEqualTo(alt));
        expect(b.maxY, greaterThanOrEqualTo(ust));
      }
    });

    test('gerçekten düz seride bant kapanmaz (sıfıra bölme yok)', () {
      // Tek fiyat: dataRange 0. Taban olmasaydı band sıfır genişlikte
      // olur ve gürültü tuvale yayılırdı.
      final b = gorunurYBandi(
        dataMinY: ortalama,
        dataMaxY: ortalama,
        avgY: ortalama,
        asgariBantOrani: gunIciAsgariBantOrani,
      );
      expect(b.maxY, greaterThan(b.minY));
      expect(b.interval, greaterThan(0));
    });

    test('sıfır ortalamada band çökmez', () {
      final b = gorunurYBandi(
        dataMinY: 0,
        dataMaxY: 0,
        avgY: 0,
        asgariBantOrani: gunIciAsgariBantOrani,
      );
      expect(b.maxY, greaterThan(b.minY));
      expect(b.minY, greaterThanOrEqualTo(0));
    });
  });

  group('altın gün içi serisi — tek arıza noktası kalmamalı', () {
    // Kullanıcı doğrudan sordu: "altın değeri mi alınamıyor acaba".
    //
    // Gün içi altın yalnızca `GC=F` (vadeli, USD/ons) üzerinden
    // çözülüyordu. Yahoo o sözleşme için 5 dakikalık veriyi vermediğinde
    // altının HİÇBİR slotu fiyatlanamıyor, her slot son bilinen fiyata
    // (seed) düşüyor ve altın ağırlıklı portföyün grafiği gün boyu düz
    // çiziliyordu — üstelik sessizce, çünkü seed slotu "kapsanmış" sayar.
    //
    // Ağ mock'lanamadığı için (servis singleton + private http.Client)
    // kaynak sırası doğrulanır; `watchlist_axis_sync_test` de aynı
    // yaklaşımı izliyor.
    test('gün içi altın ÖNCE XAUTRY=X dener, GC=F yedektir', () async {
      final src =
          await File('lib/services/history_service.dart').readAsString();

      expect(src.contains("getHistorySafe('XAUTRY=X')"), isTrue,
          reason: 'doğrudan TRY kaynağı birincil olmalı — kur çevrimi '
              'gerektirmez ve GC=F düşse bile altın düz çizgiye inmez');
      expect(src.contains("getHistorySafe('GC=F')"), isTrue,
          reason: 'yedek kaynak korunmalı');
    });

    test('kur bilinmiyorken 40.0 sabiti UYDURULMAZ', () {
      // Eski yedek yol `closestOrNull(usdTrySlots, ts) ?? 40.0` yazıyordu.
      // Gerçek kurdan sapan bu sayı altını olduğundan ucuz/pahalı gösteren
      // yapay bir basamak üretir; slotu atlamak doğru davranıştır.
      //
      // ## KURAL TAŞINDI (2026-09-17)
      // Bu iki değişmez (uydurma kur yok + yedek yalnızca birincisi boşken)
      // gün içi bloğunun içinde yaşıyordu ve uzun dönem yolları onları
      // görmüyordu: orada `35.0` ve `40.0` sabitleri duruyor, spot kaynak
      // hiç denenmiyordu. Kural artık `altinGramSerisi`'nde ve dört yol da
      // oradan geçiyor. Test o tek yere bakar; davranışın kendisi
      // `altin_seri_kaynagi_test.dart`'ta ölçülür.
      final src = File('lib/services/history_service.dart').readAsStringSync();
      final imza = src.indexOf('}) altinGramSerisi({');
      expect(imza, greaterThan(0), reason: 'altın kaynak merdiveni bulunamadı');
      // Gövde parametre listesinden SONRA başlar (`}) {`), yoksa aşağıdaki
      // "satır başındaki ilk `}`" araması parametre listesini kapatan
      // parantezi bulur ve blok boş kalır.
      final govde = src.indexOf('}) {', imza);
      final son = src.indexOf('\n}', govde);
      expect(son, greaterThan(govde));
      final goldBlock = src.substring(govde, son);

      expect(goldBlock.contains('?? 40.0'), isFalse,
          reason: 'altın çevriminde uydurma kur kalmış');
      expect(goldBlock.contains('35.0'), isFalse,
          reason: 'altın çevriminde uydurma kur kalmış');
      expect(goldBlock.contains('if (kur == null || kur <= 0) continue;'),
          isTrue,
          reason: 'kuru bilinmeyen nokta artık atlanmıyor');
      // Yedek yol yalnızca spot yetersizken çalışır (karışım yok).
      expect(goldBlock.contains('spotYeterli'), isTrue,
          reason: 'yedek kaynak yalnızca birincisi boş/yetersizken çalışmalı');
    });

    test('CANLI altın yedeği portföyün bileşimine bağlı DEĞİL', () {
      // Asıl üretim hatası (2026-09-07): yedek yol `usdTry > 0` kapısının
      // arkasındaydı ve `USDTRY=X` yalnızca kullanıcının DÖVİZ varlığı
      // varsa çekiliyordu. Altını olup dövizi olmayan kullanıcıda kur hiç
      // dolmuyor, truncgil düştüğü an altın fiyatsız kalıyordu.
      final src = File('lib/services/price_service.dart').readAsStringSync();

      expect(src.contains('_resolveUsdTry'), isTrue,
          reason: 'yedek yol kendi kurunu arayabilmeli');
      expect(src.contains("_fetchOneChart('XAUTRY=X')"), isTrue,
          reason: 'kur çevrimi gerektirmeyen doğrudan kaynak birincil olmalı');

      // Kapının geri gelmediğini kanıtla: çağrı yeri koşulsuz olmalı.
      final cagri = src.substring(
        src.indexOf('final missingGold ='),
        src.indexOf('// ── TEFAS + Yahoo'),
      );
      expect(cagri.contains('if (usdTry > 0)'), isFalse,
          reason: 'altın yedeğini kura bağlayan kapı geri gelmiş');
    });
  });
}
