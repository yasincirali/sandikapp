import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/theme/sandik.dart';

/// "Hareketi azalt" (reduce motion) erişilebilirlik koruması.
///
/// iOS HIG (Accessibility → Motion, #103/#77) bunu **High severity** sayar:
/// hareket duyarlılığı olan kullanıcıda animasyon baş dönmesi ve mide
/// bulantısı tetikleyebilir. Flutter karşılığı `MediaQuery.disableAnimationsOf`.
///
/// Denetimde (2026-08-09) 40 implicit animasyonun yalnızca 6'sı korumalıydı
/// (%15). En yoğun animasyonlu ekranlar — charts, performance, portfolio —
/// tam da korumasız olanlardı. Koruma [SandikMotion.of] ve türevlerinde
/// merkezileştirildi.
///
/// Buradaki ikinci test bir **kaynak taramasıdır**: yeni bir `Animated*`
/// widget'ı ham `Duration` ile eklenirse başarısız olur. Amaç, korumayı
/// gözden kaçırmayı derleme değil test seviyesinde yakalamak.
void main() {
  group('SandikMotion.of — davranış', () {
    testWidgets('reduce-motion KAPALI iken süre olduğu gibi geçer',
        (tester) async {
      late Duration seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: false),
          child: Builder(
            builder: (context) {
              seen = SandikMotion.of(context, SandikMotion.state);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, SandikMotion.state);
    });

    testWidgets('reduce-motion AÇIK iken süre sıfırlanır', (tester) async {
      late Duration seen;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              seen = SandikMotion.of(context, SandikMotion.state);
              return const SizedBox();
            },
          ),
        ),
      );
      expect(seen, Duration.zero,
          reason: 'HIG High severity: hareket tercihi yok sayılmamalı');
    });

    testWidgets('kısayollar (pressOf/stateOf/surfaceOf) aynı kurala uyar',
        (tester) async {
      for (final reduce in [false, true]) {
        late Duration p, s, sf;
        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Builder(
              builder: (context) {
                p = SandikMotion.pressOf(context);
                s = SandikMotion.stateOf(context);
                sf = SandikMotion.surfaceOf(context);
                return const SizedBox();
              },
            ),
          ),
        );
        if (reduce) {
          expect([p, s, sf], everyElement(Duration.zero));
        } else {
          expect(p, SandikMotion.press);
          expect(s, SandikMotion.state);
          expect(sf, SandikMotion.surface);
        }
      }
    });

    testWidgets('animasyon reduce-motion açıkken tek karede tamamlanır',
        (tester) async {
      Widget build(bool expanded, bool reduce) => MediaQuery(
            data: MediaQueryData(disableAnimations: reduce),
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Builder(
                builder: (context) => AnimatedContainer(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.enter,
                  width: expanded ? 200 : 100,
                  height: 10,
                ),
              ),
            ),
          );

      await tester.pumpWidget(build(false, true));
      await tester.pumpWidget(build(true, true));
      await tester.pump(); // tek kare — ara değer olmamalı

      final box = tester.widget<AnimatedContainer>(
          find.byType(AnimatedContainer));
      expect(box.duration, Duration.zero);
    });
  });

  group('kaynak taraması — koruma kapsamı', () {
    test('her Animated* widget\'ı reduce-motion farkındalıklı süre kullanır',
        () {
      final widgetPattern = RegExp(
        r'Animated(?:Container|Opacity|Switcher|Positioned|DefaultTextStyle'
        r'|Size|Scale|Rotation|Align|Padding)\(',
      );
      final durationPattern = RegExp(r'duration:\s*([^,\n]+)');

      final offenders = <String>[];
      var total = 0;

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final src = entity.readAsStringSync();
        // Dosya korumayı kendi içinde elle kuruyorsa (SandikTappable gibi)
        // kabul et — merkezî yardımcıdan önce yazılmış geçerli desen.
        final manualGuard = src.contains('disableAnimationsOf');

        for (final m in widgetPattern.allMatches(src)) {
          // Widget çağrısının gövdesini parantez dengesiyle bul.
          //
          // Pencere sınırı YOK: `AnimatedOpacity`/`AnimatedContainer` gövdeleri
          // (dekorasyon + child ağacı) rahatlıkla birkaç bin karakteri geçiyor.
          // Sabit bir pencere kullanıldığında `duration:` sınırın dışında
          // kalıp "koruma yok" gibi okunuyordu — kod doğruyken test kırmızı
          // yanıyordu (paywall_screen:392, performance_screen:1246).
          var depth = 0;
          var end = src.length;
          for (var j = m.end - 1; j < src.length; j++) {
            if (src[j] == '(') depth++;
            if (src[j] == ')') {
              depth--;
              if (depth == 0) {
                end = j;
                break;
              }
            }
          }
          final body = src.substring(m.end - 1, end);
          total++;

          // Bu widget'ın KENDİ `duration:` parametresi — gövdedeki ilk
          // eşleşme. Child ağacında iç içe başka bir `Animated*` varsa onun
          // duration'ı daha sonra gelir ve zaten kendi turunda ayrıca
          // denetlenir, o yüzden ilk eşleşmeyi almak yeterli.
          final d = durationPattern.firstMatch(body)?.group(1)?.trim() ?? '';
          final guarded = d.contains('Of(context)') ||
              d.contains('SandikMotion.of(') ||
              manualGuard;

          if (!guarded) {
            final line = '\n'.allMatches(src.substring(0, m.start)).length + 1;
            offenders.add('${entity.path}:$line — duration: $d');
          }
        }
      }

      expect(total, greaterThan(30),
          reason: 'tarama çalışmıyor olabilir — widget bulunamadı');
      expect(
        offenders,
        isEmpty,
        reason: 'Bu Animated* widget\'ları "hareketi azalt" ayarını yok '
            'sayıyor. Düzeltme: duration olarak SandikMotion.stateOf(context) '
            '(veya .of(context, ...)) kullan.\n${offenders.join('\n')}',
      );
    });
  });
}
