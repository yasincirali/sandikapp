import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Splash alt sınırı — açılış hızı.
///
/// Splash iki bağımsız kapıdan geçer:
///
///   1. `_splashMinimum` — marka karesi görülsün diye SABİT alt sınır.
///   2. `_veriHazir()`   — portföy/ortak verisi çözülene kadar bekler.
///
/// Hata şuydu: (1) 1800 ms'ti ve (2)'den bağımsız bir TABAN olarak
/// çalışıyordu. Veri 400 ms'de hazır olsa bile kullanıcı 1.8 sn splash'e
/// bakıyordu. Veri zaten `_warmUpData()` ile splash sırasında paralel
/// çekildiği için bu sürenin uzunluğu yavaş ağı telafi etmiyor, yalnızca
/// hızlı durumu yavaşlatıyordu.
///
/// Alt sınır 600 ms'ye indirildi. Yavaş ağda geçişi (2) geciktirmeye devam
/// eder; onun da emniyet supabı `_dataWaitTimer` (6 sn) vardır. Yani bu
/// değişiklik "veriyi beklemeden geç" DEĞİL, "gereksiz yere bekleme"dir.
///
/// Karar mantığının kendisi `splashVeriHazir` içinde saf fonksiyon olarak
/// zaten test ediliyor; burada kilitlenen şey alt sınırın büyümemesidir.
void main() {
  late String src;

  setUpAll(() {
    src = File('lib/main.dart').readAsStringSync();
  });

  test('splash alt sınırı 1 saniyeyi aşmamalı', () {
    final m = RegExp(
      r'_splashMinimum\s*=\s*Duration\(milliseconds:\s*(\d+)\)',
    ).firstMatch(src);

    expect(m, isNotNull,
        reason: 'Alt sınır adlandırılmış bir sabit olmalı — `initState` '
            'içine gömülü sihirli sayı ölçülemez ve gözden kaçar.');

    final ms = int.parse(m!.group(1)!);
    expect(ms, lessThanOrEqualTo(1000),
        reason: 'Splash alt sınırı $ms ms. Bu süre veri beklemez, yalnızca '
            'marka karesini gösterir; uzatmak açılışı doğrudan yavaşlatır. '
            'Veri yavaşsa geçişi `_veriHazir()` zaten geciktirir.');
    expect(ms, greaterThanOrEqualTo(300),
        reason: 'Çok kısa alt sınır logoyu "çakma" haline getirir.');
  });

  test('alt sınır veri kapısının YERİNE geçmemeli', () {
    // `_splashDone` tek başına yeterli olsaydı, veri hazır olmadan ana ekrana
    // geçilir ve HomeScreen kendi loading'ini açardı — düzeltilmiş olan
    // "arka arkaya iki loading" hatası geri gelirdi.
    expect(src.contains('!_dataWaitExpired'), isTrue,
        reason: 'Veri bekleme kapısı ve emniyet supabı korunmalı.');
    expect(src.contains('!veriHazir'), isTrue,
        reason: 'Veri hazır değilken splash sürmeye devam etmeli.');
  });

  test('sabit gecikme initState içine geri gömülmemeli', () {
    // Regresyon: eskiden `Future.delayed(const Duration(milliseconds: 1800))`
    // doğrudan initState'teydi.
    final inline = RegExp(
      r'Future\.delayed\(\s*const Duration\(milliseconds:\s*\d{4,}\)',
    );
    expect(inline.hasMatch(src), isFalse,
        reason: 'Açılış gecikmesi adlandırılmış sabitten okunmalı.');
  });
}
