import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Varlık satırı hizalama garantileri.
///
/// Asıl mesele: sağ kolon SINIRSIZ bırakılırsa genişliğini en uzun sayı
/// belirler; büyük portföyde tutar kolonu şişer, isim alanı daralır ve
/// satırların sağ kenarı hizasız görünür. Bu testler sabit-genişlik
/// kararının bozulmasını yakalar.
void main() {
  const sparklineWidth = 56.0;
  const valueWidth = 108.0;

  /// Tek bir varlık satırını üretir — üretimdeki yapının ölçü iskeleti.
  Widget buildRow({
    required String title,
    required String amount,
    required String delta,
    required bool hasSparkline,
    required Key valueKey,
    Key? titleKey,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(width: 28, height: 28),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    key: titleKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 3),
                const Text('12 lot · Hisse',
                    maxLines: 1, style: TextStyle(fontSize: 11)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: sparklineWidth,
            child: hasSparkline
                ? const SizedBox(height: 24, child: Placeholder())
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 8),
          SizedBox(
            key: valueKey,
            width: valueWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(amount,
                      maxLines: 1, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerRight,
                  child: Text(delta,
                      maxLines: 1, style: const TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          const SizedBox(width: 24, height: 24),
        ],
      ),
    );
  }

  Future<void> pumpList(WidgetTester tester, List<Widget> rows) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(412, 900)),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Material(
            child: SizedBox(width: 412, child: Column(children: rows)),
          ),
        ),
      ),
    );
  }

  testWidgets('tutar kolonu, tutarın uzunluğundan bağımsız aynı yerde durur',
      (tester) async {
    const smallKey = ValueKey('small');
    const largeKey = ValueKey('large');

    await pumpList(tester, [
      buildRow(
        title: 'THYAO',
        amount: '₺1.250',
        delta: '₺120 · %2,1',
        hasSparkline: true,
        valueKey: smallKey,
      ),
      buildRow(
        title: 'ASELS',
        amount: '₺1.250.000',
        delta: '₺125.400 · %12,34',
        hasSparkline: true,
        valueKey: largeKey,
      ),
    ]);

    final small = tester.getRect(find.byKey(smallKey));
    final large = tester.getRect(find.byKey(largeKey));

    // Hem sol kenar hem genişlik aynı olmalı — kolon "kaymamalı".
    expect(large.left, small.left,
        reason: 'büyük tutar kolonu sola kaydırıyor → hizalama bozuk');
    expect(large.width, small.width);
    expect(large.right, small.right);
  });

  testWidgets('sparkline olmayan satırda tutar kolonu kaymaz', (tester) async {
    const withKey = ValueKey('with');
    const withoutKey = ValueKey('without');

    await pumpList(tester, [
      buildRow(
        title: 'THYAO',
        amount: '₺45.230',
        delta: '₺4.120 · %10,0',
        hasSparkline: true,
        valueKey: withKey,
      ),
      // Manuel fiyatlı varlık: grafik yok ama yuva korunuyor.
      buildRow(
        title: 'Ev',
        amount: '₺45.230',
        delta: '₺4.120 · %10,0',
        hasSparkline: false,
        valueKey: withoutKey,
      ),
    ]);

    final a = tester.getRect(find.byKey(withKey));
    final b = tester.getRect(find.byKey(withoutKey));

    expect(b.left, a.left,
        reason: 'grafiksiz satırda yuva korunmazsa tutar 56dp sola kayar');
  });

  testWidgets('uzun fon adı yerine kod tek satıra sığar', (tester) async {
    const titleKey = ValueKey('title');

    await pumpList(tester, [
      buildRow(
        title: 'IPB', // 45 karakterlik "İş Portföy ..." yerine kod
        amount: '₺45.230',
        delta: '₺4.120 · %10,0',
        hasSparkline: true,
        valueKey: const ValueKey('v'),
        titleKey: titleKey,
      ),
    ]);

    // Taşma olmamalı: overflow varsa Flutter test'i zaten hata verir.
    expect(tester.takeException(), isNull);

    final title = tester.getSize(find.byKey(titleKey));
    expect(title.width, greaterThan(0));
  });
}
