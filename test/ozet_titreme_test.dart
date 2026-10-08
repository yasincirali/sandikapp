import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'helpers/kaynak.dart';

/// Performans › Özet titremesi (kullanıcı bildirimi 2026-10-02):
/// "Performansta grafikten özete geçerken ekran flick oluyor; Özet'teyken
/// diğer filtrelere de tıklayınca titreme oluyor … anlık görüntü gelip
/// gidiyor, muhtemelen loading/empty state anlık gösteriliyor."
///
/// Üç kök neden vardı, üçü de "her kurulumda sıfırdan başla" deseni:
///   1. `_OzetSerisi` her dönem/kapsam/sekme geçişinde yeni State ile
///      `_seri == null` başlıyor → en az bir kare iskelet (liste iki kısa
///      karta çöküp yeniden uzuyordu).
///   2. `_OzetYanVeri` (TÜFE, köprü, 1Y bağlamı, sağlık) özetten SONRA
///      gelip kartları tek tek ekliyordu.
///   3. `pStateAsync.when(...)` yeniden yüklemede (ortak listesi/oturum
///      tazelenince) tam ekran yükleme çiziyordu.
///
/// Davranış `SonucBellegi`'nde birim testle (`sonuc_bellegi_test.dart`),
/// bağlantılar burada kaynak taramasıyla korunur.
void main() {
  late String src;

  setUpAll(() {
    src = ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart')
        .replaceAll(RegExp(r'\s+'), ' ');
  });

  test('Özet serisi bellekten EŞZAMANLI okunur (ilk karede iskelet yok)', () {
    expect(src.contains('_seri = widget.bellek.seriler.oku(_anahtar);'), isTrue,
        reason: 'initState belleği await etmeden okumalı');
    expect(src.contains('await widget.bellek.seriler.yukle('), isTrue,
        reason: 'ekranın isteği ısıtmayla aynı uçuşan isteği paylaşmalı');
    // Bellekten çizilmiş seri boş tazelemeyle iskelete dönmemeli.
    expect(
        src.contains('if (bd.total.isEmpty && _seri != null) return;'), isTrue);
  });

  test('anahtar seriyi belirleyen her girdiyi taşır (yanlış sayı yok)', () {
    expect(
        src.contains("'\$_view|\${_typeFilter?.name}|\$_simulate|"
            "\$_ozetYenileme'"),
        isTrue,
        reason: 'kapsam, tür, simülasyon ve yenileme anahtarda olmalı');
    // Kimlik tek başına yetmez: miktarı düzeltilen lot aynı kimliği taşır.
    expect(src.contains("'\${a.id}:\${a.quantity}:"), isTrue);
  });

  test('yan veri ilk ölçüme kadar iskelet; bellekte varsa beklemez', () {
    expect(src.contains('if (!_hazir) return widget.iskelet;'), isTrue,
        reason: 'kartlar özetten sonra belirip listeyi itmesin');
    expect(src.contains('_hazir = bellekte != null;'), isTrue);
    // İskelet sınırlı: ağ yavaşsa özet yine gelir.
    expect(src.contains('static const _azamiBekleme = Duration(seconds: 1);'),
        isTrue);
  });

  test('Grafik ve Özet ısıtmayı tetikler', () {
    expect(
        src.contains(
            '_ozetiIsit(chartAssets: chartAssets, targetAssets: targetAssets);'),
        isTrue);
    expect(src.contains('if (_isitilan == kume) return;'), isTrue,
        reason: 'her build aynı ısıtmayı yeniden kurmamalı (30 sn tiki)');
  });

  test('kullanıcı yenilemesi belleği bırakır', () {
    expect(src.contains('_ozetYenileme++; _ozetBellek.temizle();'), isTrue);
  });

  test('bağlam cümlesi yalnız kayıptaki kısa dönemde gösterilir', () {
    // Ölçüm her dönemde var (ısıtma işareti bilmiyor); kapı gösterimde.
    expect(
        src.contains('uzunDonemPct: s.isNegative && '
            'widget.period != SummaryPeriod.birYil ? v.uzunDonem : null,'),
        isTrue);
  });

  test('yeniden yüklemede tam ekran yükleme çizilmez', () {
    final perf = RegExp(r'\.when\( (// [^\n]*? )*skipLoadingOnReload: true,')
        .allMatches(src)
        .length;
    expect(perf, 2, reason: 'portföy + ortak varlıkları when\'leri');
    final portfoy = File('lib/screens/portfolio_screen.dart')
        .readAsStringSync()
        .replaceAll(RegExp(r'\s+'), ' ');
    expect(
        RegExp(r'pStateAsync\.when\( (// [^\n]*? )*skipLoadingOnReload: true,')
            .hasMatch(portfoy),
        isTrue,
        reason: 'aynı desen Portföy sekmesinde de kapatılmalı');
  });
}
