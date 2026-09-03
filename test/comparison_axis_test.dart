import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/utils/chart_axis.dart';

/// **Karşılaştırma ekranının Y ekseninde etiket çoklaması.**
///
/// ## Ne oluyordu
/// Eksen `interval` verilmeden çiziliyordu; `fl_chart` adımı kendi seçince
/// ham banttan türeyen ondalık bir sayı çıkıyor, etiket de
/// `toStringAsFixed(0)` ile tam sayıya yuvarlandığı için ardışık FARKLI
/// tick'ler AYNI metne düşüyordu: `+0%, +0%, +1%, +1%`. İki mevduat fonu gibi
/// dar bantlı (±%0,5) bir kıyasta eksenin tamamı `+0%` oluyordu.
///
/// Buna üç şey daha eşlik ediyordu: sınırlar yuvarlanmıyordu, ızgara adımı
/// etiket adımından bağımsızdı, ve kenar etiketleri bastırılmıyordu.
///
/// ## Neden ortak dosya
/// Aynı hata takip grafiğinde bir kez çözülmüştü (`yuzdeEkseni`), ama
/// Karşılaştır ekranı kendi eksenini ayrı çizdiği için düzeltmeden
/// faydalanmadı. Cebir `lib/utils/chart_axis.dart`'a taşındı; bu test iki
/// ekranın da ondan beslendiğini kilitler.
String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');

/// Verilen eksende basılacak etiket metinleri.
List<String> _etiketler(
    ({double min, double max, double interval, int ondalik}) e) {
  final out = <String>[];
  for (var v = e.min; v <= e.max + 1e-9; v += e.interval) {
    final yuvarlanmis = (v / e.interval).round() * e.interval;
    out.add('${yuvarlanmis >= 0 ? '+' : ''}'
        '${yuvarlanmis.toStringAsFixed(e.ondalik)}%');
  }
  return out;
}

void main() {
  group('dar bantta etiketler tekrar etmez', () {
    test('±%0,5 bandında her etiket BENZERSİZ', () {
      // Üretim vakası: iki mevduat fonu kıyaslandığında eksenin tamamı
      // "+0%" oluyordu.
      final e = yuzdeEkseni(-0.5, 0.5);
      final ets = _etiketler(e);

      expect(ets.toSet().length, ets.length,
          reason: 'tekrar eden etiket var: $ets');
    });

    test('çok dar bantta (±%0,05) bile tekrar yok', () {
      final e = yuzdeEkseni(-0.05, 0.05);
      final ets = _etiketler(e);
      expect(ets.toSet().length, ets.length, reason: 'tekrar: $ets');
    });

    test('geniş bantta da tekrar yok', () {
      final e = yuzdeEkseni(-40.0, 120.0);
      final ets = _etiketler(e);
      expect(ets.toSet().length, ets.length, reason: 'tekrar: $ets');
    });

    test('veri HER ZAMAN eksenin içinde kalır', () {
      // Sınır veriyi kesiyorsa çizgi kırpılır ve grafik yalan söyler.
      const alt = -3.31;
      const ust = 18.51;
      final e = yuzdeEkseni(alt, ust);
      expect(e.min, lessThanOrEqualTo(alt));
      expect(e.max, greaterThanOrEqualTo(ust));
    });
  });

  group('grafik bu ekseni KULLANIR', () {
    // Karşılaştır ve Takip aynı widget'ı çiziyor; denetim orada.
    late String ekran;

    setUpAll(() async {
      ekran = _yorumsuz(await File('lib/widgets/percent_comparison_chart.dart')
          .readAsString());
    });

    test('yuzdeEkseni çağrılıyor', () {
      expect(ekran.contains('yuzdeEkseni('), isTrue,
          reason: 'fonksiyon doğru olsa da bağlanmazsa hata sürer');
    });

    test('adım fl_chart a AÇIKÇA veriliyor', () {
      expect(ekran.contains('interval: eksen.interval'), isTrue,
          reason: 'verilmezse fl_chart kendi seçer — hatanın kaynağı buydu');
      expect(ekran.contains('horizontalInterval: eksen.interval'), isTrue,
          reason: 'ızgara çizgileri etiketlerle aynı adımda olmalı');
    });

    test('sınırlar yuvarlanmış eksenden geliyor', () {
      expect(ekran.contains('minY: eksen.min'), isTrue);
      expect(ekran.contains('maxY: eksen.max'), isTrue);
      expect(ekran.contains('minY: minY - pad'), isFalse,
          reason: 'ham sınırlar tick leri yuvarlak sayılara oturtmuyordu');
    });

    test('Karşılaştır ekranı kendi eksenini ÇİZMEZ', () async {
      // Kopya eksen, kopya hata demekti: düzeltme takip grafiğinde yapılmış,
      // burada unutulmuştu.
      final karsilastir = _yorumsuz(
          await File('lib/screens/comparison_screen.dart').readAsString());
      expect(karsilastir.contains('SideTitles('), isFalse,
          reason: 'eksen ortak widget ta kurulur');
    });

    test('etiket tam sayıya yuvarlanmıyor', () {
      expect(ekran.contains('value.toStringAsFixed(0)'), isFalse,
          reason: 'adım %1 in altındayken tam sayı etiket tekrar eder');
      expect(ekran.contains('eksen.ondalik'), isTrue,
          reason: 'ondalık basamak adıma göre seçilmeli');
    });

    test('kenar etiketleri bastırılıyor', () {
      expect(ekran.contains('meta.min') && ekran.contains('meta.max'), isTrue,
          reason: 'üst/alt etiket kırpılıp komşusuyla üst üste biniyordu');
    });
  });
}
