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
    double? karZararOrani = 0.15,
  }) =>
      degerlendirmeSorulsunMu(
        an: an,
        durum: durum,
        kurulumGunu: kurulumGunu,
        aktifGun: aktifGun,
        karZararOrani: karZararOrani,
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
    test('kurulumdan 2 günden az geçtiyse sorulmaz', () {
      expect(sor(kurulumGunu: 1), isFalse);
      expect(sor(kurulumGunu: 2), isTrue);
    });

    test('2 aktif günden azsa sorulmaz — kurulum eski olsa bile', () {
      expect(sor(kurulumGunu: 60, aktifGun: 1), isFalse);
      expect(sor(kurulumGunu: 60, aktifGun: 2), isTrue);
    });
  });

  group('kırmızı ekran kapısı', () {
    test('portföy belirgin zarardaysa (%10 üstü) sorulmaz', () {
      expect(sor(karZararOrani: -0.11), isFalse);
      expect(sor(karZararOrani: -0.50), isFalse);
    });

    test('küçük eksi engel değil — olağan dalgalanma', () {
      expect(sor(karZararOrani: -0.01), isTrue);
      expect(sor(karZararOrani: -0.10), isTrue);
    });

    test('sıfır kâr/zarar engel değil — kayıp yok', () {
      expect(sor(karZararOrani: 0), isTrue);
    });

    test('kâr/zarar bilinmiyorsa (null) engel değil — anın kendisi olumlu',
        () {
      expect(sor(karZararOrani: null), isTrue);
    });
  });

  group('erteleme', () {
    test('"Sonra" dendikten 14 gün geçmeden tekrar sorulmaz', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 13)),
        sorulmaSayisi: 1,
      );
      expect(sor(durum: durum), isFalse);
    });

    test('14 gün geçince yeniden sorulur', () {
      final durum = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 14)),
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

    test('beş kez sorulduysa bir daha sorulmaz — beş "Sonra" bir "hayır"dır',
        () {
      final dort = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 400)),
        sorulmaSayisi: 4,
      );
      expect(sor(durum: dort), isTrue);
      final bes = ReviewDurumu(
        sonSorulmaMs: msOnce(const Duration(days: 400)),
        sorulmaSayisi: 5,
      );
      expect(sor(durum: bes), isFalse);
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

  // Apple'ın yılda 3 tavanı SİSTEM kartı içindir ve işletim sistemi uygular;
  // ön sorumuz o kotayı harcamaz. Buradaki alt sınırlar "bıktırma" korumasıdır:
  // kazara 1 güne / 50 isteme çekilirse test kırılsın.
  test('sabitler bıktırma sınırları içinde', () {
    expect(ReviewPromptService.maxSorulma, lessThanOrEqualTo(5));
    expect(ReviewPromptService.ertelemeAraligi.inDays, greaterThanOrEqualTo(14));
    expect(ReviewPromptService.minKurulumGunu, greaterThanOrEqualTo(1));
    expect(ReviewPromptService.maxZararOrani, lessThanOrEqualTo(0.10));
  });
}
