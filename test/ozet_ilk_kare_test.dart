import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// İki ayrı tutarsızlık, tek kök: **aynı sayı iki farklı yoldan
/// hesaplanıyordu** (kullanıcı bildirimi 2026-09-22).
///
/// ## 1. Bugün kartının kâr/zararı toplamla tutmuyordu
/// "anasayfa toplamlar veriyor ancak aşağıdaki günlük kartında bugünkü
/// kâr zarar toplamları tutmuyor."
///
/// `DailySummary.liveTotalTRY` `sonFiyat`'ı KULLANIYOR (fiyatı düşmüş
/// ortak pozisyonunu son bilinen kotasyondan fiyatlar), ama
/// `DailySummary.from` içindeki `total` KULLANMIYORDU. Ana ekranın toplamı
/// birinci yoldan, Bugün kartının günlük kâr/zararı ikinci yoldan
/// geliyordu: toplam ortağı sayıyor, kâr/zarar saymıyordu.
///
/// ## 2. Özet açılışta yanlış değerle render oluyordu
/// "performans özet günlük tabında ekran render olup sonradan başka değere
/// güncelleniyor, direkt açılırken doğru şekilde açılmalı."
///
/// Grafik dalı `waiting`/`stale`/`hasData` kapılarını baştan beri
/// kullanıyordu; Özet dalı hiçbirini kullanmıyordu. İlk karede boş ya da
/// BAŞKA filtreye ait (`stale`) bir `breakdown` gerçek veri sanılıp tam bir
/// özet olarak çiziliyor, seri gelince rakamlar zıplıyordu.
void main() {
  test('DailySummary.from ile liveTotalTRY AYNI yolu kullanır', () {
    final src = File('lib/services/daily_summary.dart')
        .readAsStringSync()
        .replaceAll('\r\n', '\n')
        .replaceAll(RegExp(r'\s+'), ' ');

    // İki yol da `sonFiyat` taşımalı — ayrışırsa iki yüzey farklı
    // kümeleri ölçer. 2026-09-24'ten beri ikisi de TEK fonksiyondan
    // (`kapsamToplami`) geçiyor; Özet'in canlı ucu da onu kullanıyor.
    expect(
        src.contains('static double liveTotalTRY(PortfolioState state) => '
            'kapsamToplami(state, state.assets);'),
        isTrue,
        reason: 'liveTotalTRY ortak yoldan gitmeli');
    expect(src.contains('final total = kapsamToplami(state, kapsam);'), isTrue,
        reason: 'from() içindeki total ortak yoldan gitmeli');
    expect(
        RegExp(r'kapsamToplami\(PortfolioState state, List<Asset> kapsam\) '
                r'=> ownerScopedTotalValue\(lotlarSahibeGore\(kapsam\), '
                r'toTRY: state\.toTRY, '
                r'sonFiyat: PriceService\.instance\.sonBilinenFiyat\)')
            .hasMatch(src),
        isTrue,
        reason: 'ortak yol sonFiyat taşımalı');
  });

  group('Özet ilk karede sayı uydurmaz', () {
    late String src;

    setUpAll(() {
      src = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
          .replaceAll(RegExp(r'\s+'), ' ');
    });

    test('veri hazır değilken iskelet çizilir', () {
      expect(src.contains('if (!hasData || stale) _ozetIskeleti(context)'),
          isTrue,
          reason: 'yanlış sayı göstermektense iskelet göster');
    });

    test('iskelet gerçekten tanımlı', () {
      expect(src.contains('Widget _ozetIskeleti(BuildContext context)'), isTrue);
    });

    test('filtre değişimi gün içi TOHUMU atar (zoom yoluyla aynı davranış)',
        () {
      // Kullanıcı ipucu (2026-09-22): "diğer zaman aralıklarındaki gibi
      // çalışmalı, sadece günlükte hatalı." 1H/1A/6A/1Y doğru çünkü o yol
      // filtre değişince YENİ controller kuruyor ve tohumu `stale`
      // işaretleyip breakdown'ı boşaltıyor. Gün içi tohumu ise bir STATE
      // ALANI — atılmadıkça yaşıyordu.
      expect(src.contains('void _gunIciTohumuAt()'), isTrue,
          reason: 'ortak yardımcı tanımlı olmalı');
      // Filtreyi değiştiren ÜÇ giriş de çağırmalı: kapsam çipi, tür çipi,
      // bildirimden gelen GÜNLÜK isteği.
      final cagri = RegExp(r'_gunIciTohumuAt\(\);').allMatches(src).length;
      expect(cagri, greaterThanOrEqualTo(3),
          reason: 'kapsam, tür ve derin bağlantı yolları tohumu atmalı — '
              'biri unutulursa o yoldan girince arıza geri döner');
    });

    test('GÜNLÜK dalı tohumu kapsamla İZOLE eder', () {
      // `stale: ...` geçirmek yetmedi — Özet için doğru davranış başka
      // kapsamın verisini HİÇ kullanmamak (2026-09-22, üçüncü tur).
      expect(
          src.contains(
              'final tohum = _lastIntradayKey == intradayKey ? _lastIntradayData : null;'),
          isTrue,
          reason: 'başka kapsamın verisi tohum olmamalı');
    });

    test('tohum damgası yazılıyor', () {
      expect(src.contains('_lastIntradayKey = key'), isTrue,
          reason: 'damga yazılmazsa tohum hiç kullanılamaz');
    });

    test('hasData nokta sayısına bakar, nesne varlığına değil', () {
      // Seed dolu ama ÖLÇÜLMEMİŞ bir seri de null değildir; `data != null`
      // onu "veri var" sayıyordu ve iskelet kapısı hiç açılmıyordu.
      expect(src.contains('hasData: (data?.total.isNotEmpty ?? false)'), isTrue);
    });

    test('stale tek başına yeterli değil — hasData da kapı', () {
      // Tohum veri de "veri" sayılır ama `stale` iken BAŞKA bir kapsamın
      // serisidir. İkisi birlikte kapı olmalı.
      expect(src.contains('!hasData || stale'), isTrue,
          reason: 'yalnız hasData bakılsa bayat tohum gerçek sanılırdı');
    });
  });
}
