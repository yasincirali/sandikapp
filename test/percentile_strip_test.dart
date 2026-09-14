import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/period_summary_service.dart';
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

  group('sunucu kovaları istemciyle hizalı', () {
    // `get_percentile_bucket` bir ALLOWLIST taşıyor: listede olmayan bir
    // periyot SESSİZCE boş döner — hata değil, veri yokmuş gibi. İstemci
    // bir kova isteyip sunucu onu tanımıyorsa özellik hiç çalışmaz ve
    // hiçbir yerde hata görünmez. Bu yüzden ikisi teste bağlanıyor.
    final migration =
        File('supabase/migrations/0051_percentile_180d.sql').readAsStringSync();

    test('180 kovası hem tabloda hem iki RPC\'de açık', () {
      expect(migration.contains('CHECK (period_days IN (7, 30, 180, 365))'),
          isTrue,
          reason: 'tablo CHECK\'i 180\'i reddederse snapshot hiç yazılamaz');
      // İki RPC de aynı havuzu sayıyor; biri 180 tanırken öteki tanımasa
      // kullanıcı kendi dilimini görür ama Yarış listesi boş kalırdı.
      expect(
        'NOT IN (7, 30, 180, 365)'.allMatches(migration).length,
        2,
        reason: 'get_percentile_bucket ve get_top_gainers_allocation '
            'allowlist\'leri ayrışmamalı',
      );
    });

    test('k_min ve n_max değişmezi korunuyor', () {
      // 0031'in UYARI'sı: n_max = floor(k_min / 2). İkisi bağımsız
      // sabitler DEĞİL; biri değişirse öteki de değişmeli.
      expect(migration.contains('k_min INTEGER := 8'), isTrue);
      expect(migration.contains('n_max INTEGER := 4'), isTrue);
    });

    test('GRANT\'ler yeniden tanımlamadan sonra tazeleniyor', () {
      // `CREATE OR REPLACE` bazı durumlarda yetkileri düşürüyor; revoke
      // + grant çifti her iki fonksiyon için de tekrarlanmalı.
      expect('GRANT EXECUTE ON FUNCTION'.allMatches(migration).length, 2);
      expect(migration.contains('FROM public, anon'), isTrue,
          reason: 'anon da revoke edilmeli (0029/0031 deseni)');
    });

    test('6A dönemi 180 gün — sunucu kovasıyla aynı', () {
      expect(SummaryPeriod.altiAy.days, 180,
          reason: 'istemci başka bir gün sayısı isterse sunucu allowlist\'i '
              'onu tanımaz ve şerit sessizce hiç çizilmez');
    });
  });

  group('0061 medyan farkı — sözleşme', () {
    // `get_percentile_bucket` 0061'de DROP + CREATE ile yeniden tanımlandı.
    // Havuz ve eşikler 0059 ile aynı kalmalı; yalnızca iki sütun eklendi.
    final m = File('supabase/migrations/0061_percentile_median.sql')
        .readAsStringSync();

    test('istemcinin okuduğu sütun adları', () {
      // `fetchPercentile` bu adlarla okur; biri değişirse şerit medyansız
      // çizilir ve hiçbir yerde hata görünmez.
      for (final col in [
        'percentile INTEGER',
        'total_participants INTEGER',
        'median_roi_pct NUMERIC',
        'my_roi_pct NUMERIC',
      ]) {
        expect(m.contains(col), isTrue, reason: '$col dönüş tipinde olmalı');
      }
    });

    test('allowlist, k_min ve uygunluk kapısı 0059 ile aynı', () {
      expect(m.contains('NOT IN (7, 30, 180, 365)'), isTrue);
      expect(m.contains('k_min INTEGER := 8'), isTrue);
      expect(m.contains('leaderboard_eligible_users()'), isTrue,
          reason: 'Sybil kapısı (0059) yeniden tanımda düşmemeli');
    });

    test('DROP sonrası yetkiler kuruldu ve doğrulandı', () {
      // CREATE OR REPLACE dönüş tipini değiştiremediği için DROP şart;
      // DROP eski GRANT\'leri de siler. Doğrulama bloğu eksik GRANT\'i
      // migration anında patlatır (0036/0042 deseni).
      expect(m.contains('DROP FUNCTION IF EXISTS'), isTrue);
      expect(m.contains('FROM public, anon'), isTrue);
      expect(m.contains('TO authenticated'), isTrue);
      expect(m.contains("has_function_privilege("), isTrue);
      expect(m.contains('raise exception'), isTrue);
    });

    test('medyan bir ondalığa yuvarlanır', () {
      // Tekil eşleştirmeye yardım etmesin: "%12,3" yeter.
      expect(m.contains('percentile_cont(0.5)'), isTrue);
      expect(RegExp(r'ROUND\(percentile_cont[^;]*, 1\)').hasMatch(m), isTrue);
    });
  });
}
