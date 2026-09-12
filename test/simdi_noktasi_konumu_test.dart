import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// "ŞİMDİ" noktası GERÇEK şu ana konumlanmalı — son kovanın gün başına
/// değil.
///
/// ## Yakaladığı hata (kullanıcı bildirimi 2026-09-12)
/// "Bu tüm time intervallarla olacak, hâlâ tümünün şu an noktasında
/// 11 Eylül yazıyor."
///
/// Ölçüldü — veri katmanı doğruydu:
///   1H  → son nokta 12/9 21:00
///   1A  → son nokta 12/9 **00:00**
///   1Y  → son nokta 12/9 **00:00**
///
/// Günlük seride son kova GÜN BAŞINA normalize ediliyor. Ekran canlı
/// toplamı yazarken yalnızca Y'yi güncelliyor, X'e bilinçli olarak
/// DOKUNMUYORDU ("zigzag olmasın" gerekçesiyle). Sonuç: "ŞİMDİ" dikey
/// çizgisi 12 Eylül 00:00'a düşüyor ve 11 Eylül'e bitişik duruyordu —
/// kullanıcı tüm dönemlerde 11 Eylül görüyordu.
///
/// ## Neden zigzag riski yok
/// X yalnızca İLERİ taşınıyor (`nowX > last.x`) ve Y aynı kalıyor: son
/// segment gün başından şu ana YATAY uzar. Geri taşıma olsaydı seri
/// kendi üstüne katlanırdı — `max` koruması tam bunun için.
void main() {
  final kaynak = File('lib/screens/portfolio_performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  group('son nokta şu ana taşınır', () {
    test('gerçek seri dalında X güncelleniyor', () {
      expect(kaynak.contains('final yeniX = nowX > last.x ? nowX : last.x;'),
          isTrue,
          reason: 'Son nokta hâlâ gün başında kalıyor — "ŞİMDİ" çizgisi '
              'bir önceki güne bitişik görünür.');
      expect(kaynak.contains('FlSpot(yeniX, currentTotalOverride)'), isTrue,
          reason: 'Yeni X kullanılmıyor.');
    });

    test('eski "X\'e dokunma" davranışı GERİ GELMEZ', () {
      expect(kaynak.contains('FlSpot(last.x, currentTotalOverride)'), isFalse,
          reason: 'X sabit bırakan sürüm geri gelmiş.');
    });

    test('X yalnızca İLERİ taşınır — geri katlanma yok', () {
      // `nowX > last.x` koruması olmadan, verinin ileri tarihli olduğu
      // bir durumda (saat dilimi kayması) seri kendi üstüne katlanırdı.
      final sayi = 'nowX > last.x ? nowX : last.x'.allMatches(kaynak).length;
      expect(sayi, 2,
          reason: 'İki dal (gerçek + simülasyon) korunmalı, $sayi bulundu.');
    });
  });

  test('simülasyon dalı da AYNI davranır', () {
    // İki kopyanın ayrışması bu projede yaşanmış bir hata sınıfı: aynı
    // grafik simülasyon modunda farklı bir yerde bitiyordu.
    final ilk = kaynak.indexOf('final yeniX = nowX > last.x');
    final son = kaynak.lastIndexOf('final yeniX = nowX > last.x');
    expect(ilk, isNot(-1));
    expect(ilk != son, isTrue, reason: 'Dallardan biri hizalanmamış.');
  });

  test('boş seride nokta ŞU ANA eklenir', () {
    // Hiç geçmiş yoksa tek nokta "şimdi"de durmalı; gün başına
    // eklemek grafiği bir gün geriye kaydırırdı.
    expect(kaynak.contains('spots.add(FlSpot(nowX, currentTotalOverride))'),
        isTrue);
    expect(
        kaynak.contains('activeSpots.add(FlSpot(nowX, currentTotalOverride))'),
        isTrue);
  });
}
