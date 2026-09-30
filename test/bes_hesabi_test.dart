import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/sozlesme.dart';
import 'package:portfoy_takip/services/bes_hesabi.dart';

/// BES kuralları — hak ediş, devlet katkısı ve katkının bölünmesi.
void main() {
  final giris = DateTime(2019, 5, 10);

  test('hak ediş basamakları: %0 / %15 / %35 / %60', () {
    expect(BesHesabi.hakEdisOrani(giris, DateTime(2022, 5, 9)), 0);
    expect(BesHesabi.hakEdisOrani(giris, DateTime(2022, 5, 10)), 15);
    expect(BesHesabi.hakEdisOrani(giris, DateTime(2026, 9, 30)), 35);
    expect(BesHesabi.hakEdisOrani(giris, DateTime(2029, 5, 10)), 60);
  });

  test('sonraki basamak: 7. yılda "3 yıl sonra %60"; son basamakta yok', () {
    final s = BesHesabi.sonrakiBasamak(giris, DateTime(2026, 9, 30))!;
    expect(s.yil, 3);
    expect(s.oran, 60);
    expect(BesHesabi.sonrakiBasamak(giris, DateTime(2030)), isNull);
  });

  test('devlet katkısı oranı: 2026 ve sonrası %20, 2022–2025 %30', () {
    expect(BesHesabi.devletKatkisiOrani(DateTime(2026, 2, 1)), 20);
    expect(BesHesabi.devletKatkisiOrani(DateTime(2025, 12, 31)), 30);
    expect(BesHesabi.devletKatkisiOrani(DateTime(2021, 6, 1)), 25);
  });

  test('devlet katkısı yıllık sınıra kırpılır (2026: ₺79.272)', () {
    final t = DateTime(2026, 9, 30);
    final normal =
        BesHesabi.devletKatkisi(katki: 10000, tarih: t, buYilAlinan: 0);
    expect(normal.tutar, 2000);
    expect(normal.sinirDoldu, isFalse);

    final kirp =
        BesHesabi.devletKatkisi(katki: 10000, tarih: t, buYilAlinan: 78000);
    expect(kirp.tutar, closeTo(1272, 1e-9));
    expect(kirp.sinirDoldu, isTrue);

    final dolu =
        BesHesabi.devletKatkisi(katki: 10000, tarih: t, buYilAlinan: 79272);
    expect(dolu.tutar, 0);
  });

  test('sınırı bilinmeyen yılda sınır UYDURULMAZ', () {
    final r = BesHesabi.devletKatkisi(
        katki: 10000, tarih: DateTime(2027, 2, 1), buYilAlinan: 0);
    expect(r.sinirBilinmiyor, isTrue);
    expect(r.tutar, 2000);
  });

  test('katkı dağılıma bölünür, toplam korunur (Σ parça == bütün)', () {
    const d = [
      FonPayi(kod: 'AH5', oran: 60),
      FonPayi(kod: 'AEA', oran: 30),
      FonPayi(kod: 'AH0', oran: 10),
    ];
    final p = BesHesabi.katkiyiBol(5000, d);
    expect(p['AH5'], closeTo(3000, 1e-9));
    expect(p['AEA'], closeTo(1500, 1e-9));
    expect(p.values.fold<double>(0, (a, b) => a + b), 5000);
    // Toplamı 100 olmayan dağılım oranlanır.
    final q = BesHesabi.katkiyiBol(
        900, const [FonPayi(kod: 'A', oran: 1), FonPayi(kod: 'B', oran: 2)]);
    expect(q['A'], closeTo(300, 1e-9));
    expect(q.values.fold<double>(0, (a, b) => a + b), 900);
  });

  test('dağılım geçerliliği: en az bir fon, toplam %100', () {
    expect(BesHesabi.dagilimGecerli(const []), isFalse);
    expect(
        BesHesabi.dagilimGecerli(const [FonPayi(kod: 'A', oran: 100)]), isTrue);
    expect(BesHesabi.dagilimGecerli(const [FonPayi(kod: 'A', oran: 90)]),
        isFalse);
  });

  test('bu ayın katkısı bekleniyor mu', () {
    final s = Sozlesme(
      id: 's',
      userId: 'u',
      tur: SozlesmeTuru.bes,
      kurum: 'X',
      baslangic: giris,
      aylikKatki: 5000,
      katkiGunu: 15,
    );
    final ay = DateTime(2026, 9, 20);
    expect(
        BesHesabi.katkiBekleniyor(s: s, simdi: ay, katkiTarihleri: const []),
        isTrue);
    expect(
        BesHesabi.katkiBekleniyor(
            s: s, simdi: DateTime(2026, 9, 10), katkiTarihleri: const []),
        isFalse,
        reason: 'katkı günü gelmedi');
    expect(
        BesHesabi.katkiBekleniyor(
            s: s, simdi: ay, katkiTarihleri: [DateTime(2026, 9, 15)]),
        isFalse,
        reason: 'bu ay eklendi');
  });

  group('sunucu parametreleri (0089) — elle yıl eklemek gerekmez', () {
    tearDown(() => BesHesabi.uzakParametreler(const {}));

    test('tabloda olmayan yıl sunucudan gelince sınır bilinir', () {
      expect(BesHesabi.yillikSinir(2027), isNull,
          reason: 'yedek tabloda 2027 yok — uydurma sınır olmamalı');
      BesHesabi.uzakParametreler({2027: (sinir: 95000, oran: 20)});
      expect(BesHesabi.yillikSinir(2027), 95000);
      final r = BesHesabi.devletKatkisi(
          katki: 10000, tarih: DateTime(2027, 2, 1), buYilAlinan: 94000);
      expect(r.tutar, 1000, reason: 'kalan sınıra kırpılır');
      expect(r.sinirBilinmiyor, isFalse);
    });

    test('sunucu oranı merdiveni ezer (yıl içi karar değişikliği)', () {
      BesHesabi.uzakParametreler({2027: (sinir: 95000, oran: 25)});
      expect(BesHesabi.devletKatkisiOrani(DateTime(2027, 3, 1)), 25);
      // Başka yıllar etkilenmez.
      expect(BesHesabi.devletKatkisiOrani(DateTime(2026, 3, 1)), 20);
    });

    test('sunucu boşsa yedek tablo çalışır', () {
      BesHesabi.uzakParametreler(const {});
      expect(BesHesabi.yillikSinir(2026), 79272);
    });
  });
}
