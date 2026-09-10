import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Üstteki sinyal şeridinin GÖRÜNÜMÜ.
///
/// Kullanıcı bildirimi (2026-09-10): "aşağı trend yazan kısmın işlevi
/// güzel… ancak tasarımı sayfa ve uygulamaya uygun olmalı, ahenk
/// bozulmamalı."
///
/// Şerit zeminini ve kenarlığını SİNYAL RENGİYLE boyuyordu; aşağı trendde
/// ekranın üstünde kırmızı bir uyarı kutusu duruyordu. Sayfanın geri kalanı
/// `surface1` + `hairline` sakin kartlardan oluşuyor.
///
/// Bu dosya kabuğun nötr kaldığını kilitler. Renk kaybolmadı — ikon,
/// başlık ve sol şerit hâlâ yön rengini taşıyor; anlamı renk taşır, zemin
/// taşımaz.
void main() {
  final kaynak = File('lib/screens/performance_screen.dart')
      .readAsStringSync()
      .replaceAll('\r\n', '\n');

  // Yalnızca `_kabuk` gövdesi — dosyanın geri kalanı saymasın.
  final bas = kaynak.indexOf('Widget _kabuk({required Color renk');
  final son = kaynak.indexOf('/// Tek satırlık sinyal özeti.');
  final kabuk = kaynak.substring(bas, son);

  group('sinyal şeridi kabuğu', () {
    test('zemin NÖTR — sinyal rengiyle boyanmaz', () {
      expect(kabuk.contains('color: context.c.surface1'), isTrue,
          reason: 'Kabuk sayfanın kart zeminini kullanmıyor.');
      expect(kabuk.contains('color: renk.withValues(alpha: 0.07)'), isFalse,
          reason: 'Renkli zemin geri gelmiş — şerit yine uyarı kutusuna '
              'dönüşür.');
    });

    test('kenarlık NÖTR — sayfanın hairline\'ı', () {
      expect(kabuk.contains('color: context.c.hairline'), isTrue);
      expect(kabuk.contains('renk.withValues(alpha: 0.28)'), isFalse,
          reason: 'Renkli kenarlık geri gelmiş.');
    });

    test('yön rengi KAYBOLMADI — sol şeritte taşınıyor', () {
      // Nötrleştirme, bilgiyi silmek değil doğru yere koymaktır: yön hâlâ
      // renkle okunabilmeli, yoksa renk körlüğü dışındaki herkes için de
      // ayırt edici kalmaz.
      expect(kabuk.contains('color: renk'), isTrue,
          reason: 'Sol yön şeridi rengi kullanmıyor.');
    });

    test('sol şerit içerikle birlikte uzar — sabit yükseklik yok', () {
      // Sabit `height` büyük sistem yazı tipinde içerikten kısa kalır ve
      // kart yarım çizgili görünür.
      expect(kabuk.contains('IntrinsicHeight'), isTrue);
      expect(kabuk.contains('height: 52'), isFalse,
          reason: 'Sabit yükseklik geri gelmiş.');
    });
  });

  group('sinyal şeridi başlığı', () {
    // Başlık ve ikon `_satir` içinde; ayrı bir dilim al.
    final sb = kaynak.indexOf('/// Tek satırlık sinyal özeti.');
    final ss = kaynak.indexOf('String _kisaYon(');
    final satir = kaynak.substring(sb, ss);

    test('başlık ağırlığı ölçülü — w800 değil', () {
      expect(satir.contains('fontWeight: FontWeight.w800'), isFalse,
          reason: 'Başlık yine en kalın ağırlıkta; ekranda bağırıyor.');
      expect(satir.contains('fontWeight: FontWeight.w700'), isTrue);
    });

    test('ikon yumuşak daire içinde — çıplak değil', () {
      // Nötr zeminde çıplak ikon havada duruyordu; ekranın gösterge
      // listesinde de ikonlar daire içinde.
      expect(satir.contains('shape: BoxShape.circle'), isTrue);
      expect(satir.contains('renk.withValues(alpha: 0.12)'), isTrue);
    });

    test('dokunma işlevi korundu', () {
      // Kullanıcı: "işlevi güzel, tıklayınca aşağı göstergelere gitmesi
      // doğru." Yeniden biçimlendirme sırasında düşürülmemeli.
      expect(kaynak.contains('onTap: widget.onTap'), isTrue);
      expect(kaynak.contains('_sinyalPaneliKey.currentContext'), isTrue);
    });
  });
}
