import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/widgets/percentile_strip.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Yüzdelik dilim şeridinin **görünmediği** hâller.
///
/// Bu testin varlık sebebi: şeridin üretimdeki VARSAYILAN hâli gizli olmak.
/// Remote Config bayrağı kapalı doğuyor, kullanıcıların çoğu yarış opt-in'i
/// yapmıyor ve sunucu k-anonimlik eşiği dolmadan veri dönmüyor. Yani şerit
/// çoğu zaman hiç çizilmeyecek — ve gizliyken ana ekranda TEK PİKSEL yer
/// kaplamamalı.
///
/// Erken bir sürümde dolgu (`Padding`) çağıran tarafta duruyordu; şerit
/// gizlendiğinde bile 12 piksellik boşluk kalıyordu. Dolgu bu yüzden
/// widget'ın içine alındı ve bu test onu yerinde tutuyor.
void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<Size> pumpStrip(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PercentileStrip(
                  key: const Key('strip'),
                  myAssets: const [],
                  toTRY: (v, _) => v,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // postFrameCallback'teki yükleme denemesinin koşması için bir kare daha.
    await tester.pump();
    return tester.getSize(find.byKey(const Key('strip')));
  }

  testWidgets('Remote Config bayrağı kapalıyken hiç yer kaplamaz',
      (tester) async {
    final size = await pumpStrip(tester);
    expect(size.height, 0,
        reason: 'gizli şerit dolgusuyla birlikte yok olmalı');
  });

  testWidgets('gizliyken görünür hiçbir metin çizmez', (tester) async {
    await pumpStrip(tester);
    expect(find.textContaining('iyi getirdin'), findsNothing);
    expect(find.textContaining('kişi'), findsNothing);
  });

  test('karşılaştırma penceresi 30 gün', () {
    // 7 gün gürültülü, 365 gün yeni kullanıcıyı dışarıda bırakır.
    // Değer değişirse metin ("Son 30 günde...") ile birlikte güncellenmeli.
    expect(PercentileStrip.periodDays, 30);
  });
}
