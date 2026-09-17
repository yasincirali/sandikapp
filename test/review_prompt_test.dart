import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/review_prompt_service.dart';

/// `degerlendirmeSorulsunMu` saf karar fonksiyonunun sözleşmesi.
///
/// Her kuralın gerekçesi fonksiyonun doc yorumunda; burada yalnızca
/// davranış sabitlenir. Kuralı değiştirirken ilgili testi de değiştir —
/// test "kazara" kırıldıysa kural kazara değişmiştir.
void main() {
  final simdi = DateTime(2026, 9, 18, 12);
  int msOnce(Duration d) => simdi.subtract(d).millisecondsSinceEpoch;

  // Bütün kapıları geçen "olgun, kârda kullanıcı" — her test bir kapıyı
  // kapatıp yalnızca onun etkisini ölçer.
  bool sor({
    ReviewAni an = ReviewAni.kilometreTasi,
    ReviewDurumu durum = ReviewDurumu.bos,
    int kurulumGunu = 30,
    int aktifGun = 10,
    double? karZararTRY = 1500,
  }) =>
      degerlendirmeSorulsunMu(
        an: an,
        durum: durum,
        kurulumGunu: kurulumGunu,
        aktifGun: aktifGun,
        karZararTRY: karZararTRY,
        simdi: simdi,
      );

  test('olgun ve kârda kullanıcıya her mutlu anda sorulur', () {
    for (final an in ReviewAni.values) {
      expect(sor(an: an), isTrue, reason: an.name);
    }
  });

  test('bir kez değerlendiren bir daha görmez', () {
    expect(sor(durum: const ReviewDurumu(tamamlandi: true)), isFalse);
  });

  group('yeni kullanıcı kapısı', () {
    test('kurulumdan 3 günden az geçtiyse sorulmaz', () {
      expect(sor(kurulumGunu: 2), isFalse);
      expect(sor(kurulumGunu: 3), isTrue);
    });

    test('3 aktif günden azsa sorulmaz — kurulum eski olsa bile', () {
      expect(sor(kurulumGunu: 60, aktifGun: 2), isFalse);
      expect(sor(kurulumGunu: 60, aktifGun: 3), isTrue);
    });
  });

  group('kırmızı ekran kapısı', () {
    test('portföy zarardaysa sorulmaz', () {
      expect(sor(karZararTRY: -1), isFalse);
    });

    test('sıfır kâr/zarar engel değil — kayıp yok', () {
      expect(sor(karZararTRY: 0), isTrue);
    });

    test('kâr/zarar bilinmiyorsa (null) engel değil — anın kendisi olumlu',
        () {
      expect(sor(karZararTRY: null), isTrue);
    });
  });

  group('erteleme', () {
    test('"Sonra" dendikten 30 gün geçmeden tekrar sorulmaz', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 29)),
        sorulmaSayisi: 1,
      );
      expect(sor(durum: durum), isFalse);
    });

    test('30 gün geçince yeniden sorulur', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 30)),
        sorulmaSayisi: 1,
      );
      expect(sor(durum: durum), isTrue);
    });

    test('aynı gün ikinci mutlu an sessiz kalır', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(hours: 2)),
        sorulmaSayisi: 1,
      );
      expect(sor(an: ReviewAni.paylasim, durum: durum), isFalse);
    });

    test('üç kez sorulduysa bir daha sorulmaz — üç "Sonra" bir "hayır"dır',
        () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 400)),
        sorulmaSayisi: 3,
      );
      expect(sor(durum: durum), isFalse);
    });
  });

  group('sorun bildirimi', () {
    test('"Bir sorun var" dedikten sonra 90 gün sorulmaz', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 60)),
        sorulmaSayisi: 1,
        geriBildirimMs: msOnce(const Duration(days: 60)),
      );
      expect(sor(durum: durum), isFalse);
    });

    test('90 gün sonra yeniden sorulabilir', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 90)),
        sorulmaSayisi: 1,
        geriBildirimMs: msOnce(const Duration(days: 90)),
      );
      expect(sor(durum: durum), isTrue);
    });
  });

  test('sabitler mağaza tavanlarıyla uyumlu — Apple yılda en fazla 3', () {
    expect(ReviewPromptService.maxSorulma, lessThanOrEqualTo(3));
    expect(ReviewPromptService.ertelemeAraligi.inDays, greaterThanOrEqualTo(30));
  });
}
