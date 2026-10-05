import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/csv_import_service.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_ice_aktarma.dart';
import 'package:portfoy_takip/services/ekstre/ekstre_tablosu.dart';
import 'package:portfoy_takip/services/ekstre/tablo_okuyucular.dart';

/// AI sütun eşleme (2026-10-05, 0121). Sunucu yalnız sütun numarası döner;
/// değerler cihazda belgeden okunur ve içerik kapısından geçer.
void main() {
  // Motorun sözlüğünde olmayan başlıklar: "Enstrüman Kısaltması" sembol
  // diye tanınır ama "Elde Tutulan" / "Birim Maliyet Bedeli" tanınmayabilir.
  const tablo = EkstreTablosu(kaynak: 'PDF', satirlar: [
    ['Müşteri', 'Ad Soyad'],
    [],
    ['Kıymet Tanımı', 'Elde Tutulan', 'Ortalama Edinim', 'Piyasa'],
    ['THYAO', '100', '312,40', '29.875,00'],
    ['ASELS', '1.250', '45,20', '76.312,50'],
    ['Genel Toplam', '', '', '106.187,50'],
  ]);

  EkstreOkumaSonucu oku() => ekstreyiAnla(EkstreBicimi.pdf, [tablo], '');

  test('AI eşlemesi ham tablo numaralarıyla uygulanır', () {
    final s = oku().aiEslemesiyle([
      {
        'tablo': 1,
        'baslik_satiri': 2,
        'roller': {'sembol': 0, 'adet': 1, 'fiyat': 2},
      },
    ]);
    expect(s, isNotNull);
    expect(s!.aiOnerisi, isTrue);
    expect(s.ana!.eminDegil, isFalse);
    final r = CsvImportService.parse(s.kanonikMetin());
    expect(r.rows.map((x) => (x.ticker, x.quantity, x.price)), [
      ('THYAO.IS', 100.0, 312.40),
      ('ASELS.IS', 1250.0, 45.20),
    ]);
  });

  test('içerik kapısı: yanlış sütun, olmayan tablo, eksik rol düşer', () {
    // Adet diye metin sütunu gösterilmiş.
    expect(
        oku().aiEslemesiyle([
          {'tablo': 1, 'baslik_satiri': 2, 'roller': {'sembol': 1, 'adet': 0}},
        ]),
        isNull);
    expect(
        oku().aiEslemesiyle([
          {'tablo': 5, 'baslik_satiri': 0, 'roller': {'sembol': 0, 'adet': 1}},
        ]),
        isNull);
    expect(
        oku().aiEslemesiyle([
          {'tablo': 1, 'baslik_satiri': 2, 'roller': {'sembol': 0}},
        ]),
        isNull);
    expect(
        oku().aiEslemesiyle([
          {'tablo': 1, 'baslik_satiri': 2, 'roller': {'sembol': 0, 'adet': 9}},
        ]),
        isNull);
  });

  test('fon adı sembol sütunundaysa tablo adla tanımlı olur', () {
    const fon = EkstreTablosu(kaynak: 'PDF', satirlar: [
      ['Ürün', 'Miktar (Pay)', 'Değer'],
      ['GARANTİ PORTFÖY ALTIN KATILIM FONU', '1.000', '3.000,00'],
      ['DENİZ PORTFÖY PARA PİYASASI (TL) FONU', '100', '500,00'],
    ]);
    final s = ekstreyiAnla(EkstreBicimi.pdf, [fon], '').aiEslemesiyle([
      {'tablo': 1, 'baslik_satiri': 0, 'roller': {'sembol': 0, 'adet': 1, 'tutar': 2}},
    ])!;
    expect(s.ana!.adlaTanimli, isTrue);
    expect(s.cozulecekFonAdlari, hasLength(2));
  });

  test('iskelet sunucu kapısını geçer: tablo hücrelerinde yalnız 9 rakamı',
      () {
    // `_shared/ekstre_esleme.ts` `iskeletiDogrula` ile aynı kural: veri
    // satırlarında (satır_no<TAB>…) 0–8 rakamı varsa sunucu reddeder.
    final iskelet = ekstreIskeleti(oku());
    expect(iskelet.split('\n').first, 'sandık ekstre iskeleti v1');
    for (final s in iskelet.split('\n')) {
      final m = RegExp(r'^(\d+)\t(.*)$').firstMatch(s);
      if (m == null) continue;
      expect(m.group(2), isNot(matches(RegExp(r'[0-8]'))), reason: s);
    }
    expect(iskelet, contains('## tablo 1 (PDF) · 6 satır × 4 sütun'));
  });
}
