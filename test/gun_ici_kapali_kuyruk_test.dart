import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';

/// Gün içi grafiğin hafta sonu davranışı — "piyasa kapalı" kuyruğu.
///
/// ## Kullanıcı isteği (2026-09-12)
/// "C seçeneği olsun, örneğin Pazar gününde Cuma–Cmt–Pazar gözükecek.
/// Cmt ve Pazar günü için piyasa kapalı ibaresi olup gri şekilde
/// çizilecek."
///
/// Önceki davranış: seri son seansın KAPANIŞINDA kesiliyordu. Veri
/// doğruydu ama Pazar günü eksende yalnızca Cuma görünüyordu ve kullanıcı
/// "grafik dünde kalmış" diye okudu.
///
/// Yeni davranış: kapanış fiyatı bugüne kadar sabit kuyruk olarak uzar;
/// kuyruk gerçek işlem OLMADIĞI için ayrı damgalanır ve ekran onu gri +
/// kesikli çizer.
///
/// ## Neden saf fonksiyon testi
/// Hafta sonu dalı yalnızca Cmt/Pazar ortaya çıkar. `DateTime.now()`
/// fonksiyonun içinde olsaydı hafta içi koşan hiçbir test bu dalı
/// çalıştıramazdı — CI Salı günü yeşil, kullanıcı Pazar günü kırık.
int _slot5dk(int ms) {
  const bes = 5 * 60 * 1000;
  return (ms ~/ bes) * bes;
}

/// 11 Eylül 2026 Cuma, 18:10 — BIST kapanışından sonra.
final _cumaKapanis = DateTime(2026, 9, 11, 18, 10).millisecondsSinceEpoch;

void main() {
  group('bugünün seansı çiziliyor (piyasa açık)', () {
    test('kuyruk YOK — seri şimdide biter', () {
      final now = DateTime(2026, 9, 8, 14, 30); // Salı, seans içi
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: null, // bugün çiziliyor
        normalizeSlot: _slot5dk,
      );

      expect(r.piyasaKapali, isNull,
          reason: 'Piyasa açıkken "kapalı" bölgesi olmamalı.');
      expect(r.sagUc, _slot5dk(now.millisecondsSinceEpoch));
    });
  });

  group('hafta sonu — kuyruk BUGÜNE uzanır', () {
    test('Cumartesi: sağ uç bugün, kapalı bölge Cuma kapanışında başlar', () {
      final now = DateTime(2026, 9, 12, 15, 0); // Cumartesi
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: _cumaKapanis,
        normalizeSlot: _slot5dk,
      );

      expect(r.sagUc, _slot5dk(now.millisecondsSinceEpoch),
          reason: 'Seri bugüne uzanmalı — eksende Cmt görünsün.');
      expect(r.piyasaKapali, _slot5dk(_cumaKapanis),
          reason: 'Kapalı bölge Cuma kapanışında başlamalı.');
      expect(r.piyasaKapali! < r.sagUc, isTrue);
    });

    test('Pazar: eksen Cuma–Cmt–Pazar\'ı kapsar', () {
      // Kullanıcının verdiği örnek.
      final now = DateTime(2026, 9, 13, 11, 0); // Pazar
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: _cumaKapanis,
        normalizeSlot: _slot5dk,
      );

      final kapsananGun = Duration(
        milliseconds: r.sagUc - _slot5dk(_cumaKapanis),
      ).inDays;
      expect(kapsananGun >= 1, isTrue,
          reason: 'Pazar günü kuyruk en az bir tam günü kapsamalı.');
      expect(r.piyasaKapali, isNotNull);
    });

    test('Pazartesi açılış öncesi de kuyruk çizilir', () {
      // 00:10'da son seans hâlâ Cuma. Bu saat özellikle riskli: eski
      // kodda pencerenin tamamı hafta sonuna düşüp çizgi kaybolabiliyordu.
      final now = DateTime(2026, 9, 14, 0, 10); // Pazartesi
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: _cumaKapanis,
        normalizeSlot: _slot5dk,
      );

      expect(r.sagUc, _slot5dk(now.millisecondsSinceEpoch));
      expect(r.piyasaKapali, _slot5dk(_cumaKapanis));
    });
  });

  group('RESMÎ TATİL — hafta içi de kapsanır', () {
    // Kullanıcı isteği (2026-09-12): "bunu sadece hafta sonu değil, TR
    // için piyasa kapalı olan tüm özel tarihlerde yap."
    //
    // ## Neden ek bir tatil takvimi GEREKMEDİ
    // `gunIciSagUc` günün hangi gün olduğunu HİÇ sormuyor: yalnızca
    // "elimizdeki son veri ne zamana ait" diye bakıyor. Borsa kapalıysa
    // — sebebi hafta sonu, 29 Ekim, bayram ya da yarım gün olsun — veri
    // gelmez, damga eskide kalır ve kuyruk kendiliğinden çizilir.
    //
    // Takvim tabanlı bir çözüm daha kırılgan olurdu: her yıl güncellenmesi
    // gerekir, arefe/yarım gün kuralları değişir ve takvim eskidiğinde
    // hata SESSİZ olur (grafik yanlış çizilir, kimse fark etmez).

    test('29 Ekim Perşembe — hafta içi tatil kuyruğu çizilir', () {
      // 2026-10-29 Perşembe, Cumhuriyet Bayramı. Son seans 28 Ekim Çarşamba.
      final carsambaKapanis =
          DateTime(2026, 10, 28, 18, 10).millisecondsSinceEpoch;
      final now = DateTime(2026, 10, 29, 14, 0); // Perşembe, borsa KAPALI

      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: carsambaKapanis,
        normalizeSlot: _slot5dk,
      );

      expect(r.piyasaKapali, _slot5dk(carsambaKapanis),
          reason: 'Hafta içi tatilde kuyruk çizilmiyor — takvime bağlı '
              'bir kısıt sızmış olmalı.');
      expect(r.sagUc, _slot5dk(now.millisecondsSinceEpoch));
    });

    test('bayram + hafta sonu zinciri (4 gün)', () {
      // Uzun tatil: seri birkaç günü kapsayabilmeli.
      final sonSeans = DateTime(2026, 5, 15, 18, 10).millisecondsSinceEpoch;
      final now = DateTime(2026, 5, 19, 12, 0); // 4 gün sonra

      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: sonSeans,
        normalizeSlot: _slot5dk,
      );

      final gun =
          Duration(milliseconds: r.sagUc - r.piyasaKapali!).inDays;
      expect(gun >= 3, isTrue,
          reason: 'Uzun tatil zinciri kapsanmıyor ($gun gün).');
    });

    test('yarım gün (arefe) — erken kapanış da kuyruk üretir', () {
      // Arefe günleri BIST yarım gün çalışır; seans 13:00'te kapanır.
      final erkenKapanis =
          DateTime(2026, 3, 19, 13, 0).millisecondsSinceEpoch;
      final now = DateTime(2026, 3, 19, 17, 30); // aynı gün, kapanış sonrası

      final r = HistoryService.gunIciSagUc(
        now: now,
        // Aynı GÜN içinde olduğu için `seansGunu` bugünü döndürür ve
        // `seansSonuTs` null gelir — kuyruk üretilmez, doğru davranış:
        // bugünün seansı zaten çiziliyor.
        seansSonuTs: null,
        normalizeSlot: _slot5dk,
      );
      expect(r.piyasaKapali, isNull);
      expect(r.sagUc, _slot5dk(now.millisecondsSinceEpoch));

      // Ertesi gün bakıldığında ise kuyruk çıkar.
      final ertesi = DateTime(2026, 3, 20, 9, 0);
      final r2 = HistoryService.gunIciSagUc(
        now: ertesi,
        seansSonuTs: erkenKapanis,
        normalizeSlot: _slot5dk,
      );
      expect(r2.piyasaKapali, _slot5dk(erkenKapanis));
    });

    test('fonksiyon takvim BİLMİYOR — girdi yalnızca veri damgası', () {
      // Aynı damga + aynı "şimdi" farkı, günün adı ne olursa olsun AYNI
      // sonucu vermeli. Hafta içi/hafta sonu ayrımı yapılsaydı bu kırılırdı.
      final sonuclar = <int>{};
      for (var gun = 12; gun <= 18; gun++) {
        final kapanis =
            DateTime(2026, 9, gun, 18, 10).millisecondsSinceEpoch;
        final now = DateTime(2026, 9, gun + 1, 12, 0);
        final r = HistoryService.gunIciSagUc(
          now: now,
          seansSonuTs: kapanis,
          normalizeSlot: _slot5dk,
        );
        expect(r.piyasaKapali, isNotNull,
            reason: '$gun Eylül için kuyruk üretilmedi.');
        sonuclar.add(r.sagUc - r.piyasaKapali!);
      }
      expect(sonuclar.length, 1,
          reason: 'Günün adına göre farklı davranıyor — takvim bağımlılığı '
              'sızmış.');
    });
  });

  group('ÇOK GÜNLÜ pencere (1H) — kapalı günler ELENMEZ', () {
    // Kullanıcı bildirimi (2026-09-12): "1H'de 12 Eylül datasını
    // göremiyorum."
    //
    // Ölçüldü: `periodDays <= 7` seriyi SAATLİK ızgaraya düşürüyor ve o
    // ızgara Cmt/Pazar slotlarını tamamen eliyordu. Cumartesi bakıldığında
    // 12 Eylül HİÇ üretilmiyor, grafik 11 Eylül'de bitiyordu.
    //
    // Eleme kuralı 24 SAATLİK pencere için konmuştu (hafta sonunda pencere
    // boşalıp çizgi kaybolmasın). Çok günlü pencerede böyle bir risk yok.

    List<DateTime> gunler(List<int> slots) {
      final set = <int>{};
      final out = <DateTime>[];
      for (final ts in slots) {
        final d = DateTime.fromMillisecondsSinceEpoch(ts);
        final gun = DateTime(d.year, d.month, d.day);
        if (set.add(gun.millisecondsSinceEpoch)) out.add(gun);
      }
      return out;
    }

    test('Cumartesi bakıldığında 1H BUGÜNÜ içerir', () {
      final now = DateTime(2026, 9, 12, 18, 45); // Cumartesi
      final slots =
          HistoryService.gridSlotlari(now: now, periodDays: 7, hourly: true);

      final son = DateTime.fromMillisecondsSinceEpoch(slots.last);
      expect(son.day, 12,
          reason: 'Son slot 12 Eylül değil (${son.day}/${son.month}) — '
              'bugün yine eleniyor.');
    });

    test('hafta sonu günleri ızgarada DURUR', () {
      final now = DateTime(2026, 9, 12, 18, 45);
      final g = gunler(
          HistoryService.gridSlotlari(now: now, periodDays: 7, hourly: true));

      expect(g.any((d) => d.weekday == DateTime.saturday), isTrue,
          reason: 'Cumartesi elenmiş.');
      expect(g.any((d) => d.weekday == DateTime.sunday), isTrue,
          reason: 'Pazar elenmiş.');
    });

    test('pencere 7 günü TAM kapsar', () {
      final now = DateTime(2026, 9, 12, 18, 45);
      final g = gunler(
          HistoryService.gridSlotlari(now: now, periodDays: 7, hourly: true));
      expect(g.length, 8,
          reason: '7 gün + bugün = 8 takvim günü bekleniyor, ${g.length} var.');
    });

    test('GÜNLÜK (1 gün) pencerede eleme KORUNUR', () {
      // Bu kural kaldırılamaz: hafta sonunda 24 saatlik pencerenin tamamı
      // elenir ve çizgi kaybolurdu. Gün içi grafiğin hafta sonu davranışını
      // kuyruk mantığı (`gunIciSagUc`) yönetiyor.
      final now = DateTime(2026, 9, 12, 18, 45); // Cumartesi
      final slots =
          HistoryService.gridSlotlari(now: now, periodDays: 1, hourly: true);

      final son = DateTime.fromMillisecondsSinceEpoch(slots.last);
      expect(son.day, 11,
          reason: 'Tek günlük pencere son seansa çapalanmalı.');
      expect(slots.length, greaterThanOrEqualTo(24),
          reason: 'Pencere boşalmış — çizgi kaybolur.');
    });

    test('hafta içi bakıldığında 1H değişmez', () {
      // Regresyon kapısı: düzeltme yalnızca kapalı günleri etkilemeli.
      final now = DateTime(2026, 9, 9, 14, 0); // Çarşamba
      final slots =
          HistoryService.gridSlotlari(now: now, periodDays: 7, hourly: true);
      final son = DateTime.fromMillisecondsSinceEpoch(slots.last);
      expect(son.day, 9);
    });
  });

  group('savunma — bozuk girdi çökertmez', () {
    test('veri damgası GELECEKTE ise kuyruk üretilmez', () {
      // Saat dilimi kayması: kapanış "şimdi"den ileride görünebilir.
      // Negatif uzunlukta kuyruk ızgarayı ters kurardı.
      final now = DateTime(2026, 9, 12, 10, 0);
      final ileri = now.add(const Duration(hours: 3)).millisecondsSinceEpoch;

      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: ileri,
        normalizeSlot: _slot5dk,
      );

      expect(r.piyasaKapali, isNull,
          reason: 'Gelecek damga için kapalı bölge üretilmemeli.');
      expect(r.sagUc, _slot5dk(ileri),
          reason: 'Sağ uç en azından veriyi kapsamalı.');
    });

    test('kapanış ŞU ANA eşitse kuyruk yok', () {
      final now = DateTime(2026, 9, 12, 10, 0);
      final r = HistoryService.gunIciSagUc(
        now: now,
        seansSonuTs: now.millisecondsSinceEpoch,
        normalizeSlot: _slot5dk,
      );
      expect(r.piyasaKapali, isNull);
    });

    test('sağ uç HER ZAMAN kapanıştan küçük değildir', () {
      // Kaba tarama: seri asla geriye doğru kurulmamalı.
      for (var saat = 0; saat < 48; saat += 3) {
        final now = DateTime(2026, 9, 12).add(Duration(hours: saat));
        final r = HistoryService.gunIciSagUc(
          now: now,
          seansSonuTs: _cumaKapanis,
          normalizeSlot: _slot5dk,
        );
        expect(r.sagUc >= _slot5dk(_cumaKapanis), isTrue,
            reason: '$saat. saatte sağ uç kapanışın gerisinde.');
      }
    });
  });
}

