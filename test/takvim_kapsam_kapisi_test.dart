import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/bist_calendar.dart';
import 'package:portfoy_takip/services/seni_ilgilendiren_gunler.dart';

/// Takvim yıl sonu kapısı (müşteri raporu 10 Kas).
///
/// İki elle tutulan takvim yıl dönerken sessizce eskir: BIST dinî bayramları
/// (`BistTakvimi.sonKapsananYil`, sunucu kopyası `bist_tatil.ts`) ve TCMB PPK
/// günleri (`makroTakvim`). Eskiyince hata vermezler; bayram günü "Canlı"
/// yazılır, "Seni ilgilendiren günler" PPK'yı göstermez. Bu kapı takvim
/// tarihine bağlı olarak BİLEREK kırılır: 1 Aralık'tan sonra (PPK için
/// 20 Aralık) güncelleme yapılmadıysa CI kırmızıya döner ve mesaj ne
/// yapılacağını söyler. Eski "tarihe bağlı test yok" kararı (bist_calendar)
/// bunun için değişti: hatırlatma `YAPMAN_GEREKENLER.md`'de kalıyordu ve
/// kaçırılabiliyordu; kırmızı CI kaçırılamaz. Kural mantığı sabit
/// tarihlerle ayrıca sınanır; gerçek tarih bir kez sorulur.

/// BIST takvimi yeterince ileriyi kapsıyor mu? Kapsamıyorsa yapılacakları
/// anlatan mesaj, kapsıyorsa `null`.
String? bistKapisi(DateTime now, int sonKapsananYil) {
  final y = now.year;
  final aralik = DateTime(y, 12, 1);
  if (now.isBefore(aralik) || sonKapsananYil >= y + 1) return null;
  return 'BIST tatil takvimi ${y + 1} yılını kapsamıyor '
      '(sonKapsananYil = $sonKapsananYil). Resmî kaynaktan (Borsa İstanbul '
      '"resmî tatiller" duyurusu ya da Resmî Gazete / Diyanet ${y + 1} dinî '
      'günler takvimi) ${y + 1} Ramazan ve Kurban Bayramı günlerini ve '
      'arifelerini al; lib/services/bist_calendar.dart (_diniTamGun, '
      '_diniYarimGun, sonKapsananYil) ve '
      'supabase/functions/_shared/bist_tatil.ts (diniTamGun, diniYarimGun, '
      'sonKapsananYil) dosyalarına birlikte yaz, kaynağı yoruma ekle, '
      'test/bist_tatil_parite_test.dart yeşil kalsın. Tarih tahmin edilmez.';
}

/// TCMB PPK listesi bir sonraki yılın ikinci yarısını da kapsıyor mu?
String? ppkKapisi(DateTime now, Iterable<DateTime> ppkGunleri) {
  final y = now.year;
  if (now.isBefore(DateTime(y, 12, 20))) return null;
  final ikinciYari = ppkGunleri.any((g) => g.year == y + 1 && g.month >= 7);
  if (ikinciYari) return null;
  return 'TCMB PPK listesinde ${y + 1} ikinci yarısından tarih yok. TCMB '
      '"${y + 1} Yılı Para ve Kur Politikası" metniyle yayımlanan toplantı '
      'takvimini (tcmb.gov.tr) al; lib/services/seni_ilgilendiren_gunler.dart '
      'içindeki makroTakvim TCMB listesine ${y + 1} Temmuz–Aralık günlerini '
      've ${y + 2} ilk yarısını ekle, kaynak ve doğrulama tarihini yoruma '
      'yaz. Tarih tahmin edilmez.';
}

void main() {
  group('BIST kapısı', () {
    test('Kasım sonuna kadar sessiz', () {
      expect(bistKapisi(DateTime(2026, 11, 30, 23, 59), 2026), isNull);
    });
    test('1 Aralık\'tan sonra sonraki yıl yoksa kırar', () {
      final m = bistKapisi(DateTime(2026, 12, 1), 2026);
      expect(m, isNotNull);
      expect(m, contains('bist_calendar.dart'));
      expect(m, contains('bist_tatil.ts'));
      expect(m, contains('bist_tatil_parite_test'));
    });
    test('sonraki yıl girildiyse geçer', () {
      expect(bistKapisi(DateTime(2026, 12, 15), 2027), isNull);
      expect(bistKapisi(DateTime(2027, 3, 1), 2027), isNull);
    });
  });

  group('PPK kapısı', () {
    final ilkYari = [DateTime.utc(2027, 1, 21), DateTime.utc(2027, 6, 10)];
    test('20 Aralık\'tan önce sessiz', () {
      expect(ppkKapisi(DateTime(2026, 12, 19), ilkYari), isNull);
    });
    test('20 Aralık\'tan sonra ikinci yarı yoksa kırar', () {
      final m = ppkKapisi(DateTime(2026, 12, 20), ilkYari);
      expect(m, isNotNull);
      expect(m, contains('seni_ilgilendiren_gunler.dart'));
    });
    test('ikinci yarı girildiyse geçer', () {
      expect(
          ppkKapisi(
              DateTime(2026, 12, 20), [...ilkYari, DateTime.utc(2027, 7, 22)]),
          isNull);
    });
  });

  test('gerçek tarih: takvimler güncel', () {
    final now = DateTime.now();
    final bist = bistKapisi(now, BistTakvimi.sonKapsananYil);
    final ppk = ppkKapisi(now, [
      for (final o in makroTakvim)
        if (o.tur == GunOlayiTuru.tcmb) o.gun
    ]);
    expect(bist, isNull, reason: bist);
    expect(ppk, isNull, reason: ppk);
  });
}
