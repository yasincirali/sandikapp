import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/utils/piyasa_kapali_etiketi.dart';
import 'helpers/kaynak.dart';

/// "Kapalı" ibaresi yalnızca TAMAMEN borsa portföyüne söylenir.
///
/// ## Kullanıcı kararı (2026-10-01)
/// "Kripto vs yüzünden altın sürekli değişiyor, kripto da değişiyor;
/// borsa kapalı sadece. Sadece borsadan oluşan portföyü olanlara
/// gösterebiliriz. Bu ifadeyi uygulama genelinde."
///
/// Önceki ara adım (2026-09-12) karışık portföye "BORSA KAPALI · DİĞERLERİ
/// SÜRÜYOR", borsasız portföye "SON VERİ" diyordu; ikisi de kalktı.
void main() {
  group('yalnizcaBorsa', () {
    test('hisse / fon / BES ve karışımları → true', () {
      expect(yalnizcaBorsa([AssetType.hisse]), isTrue);
      expect(yalnizcaBorsa([AssetType.fon]), isTrue);
      expect(yalnizcaBorsa([AssetType.bes]), isTrue);
      expect(yalnizcaBorsa([AssetType.hisse, AssetType.fon, AssetType.bes]),
          isTrue);
    });

    test('tek bir 7/24 ya da spot varlık → false', () {
      // Asıl karar: altın/kripto hafta sonu da işler.
      for (final t in [
        AssetType.altin,
        AssetType.doviz,
        AssetType.emtia,
        AssetType.kripto,
        AssetType.mevduat,
      ]) {
        expect(yalnizcaBorsa([AssetType.hisse, t]), isFalse,
            reason: 'hisse + $t karışık portföy — "kapalı" denmemeli.');
        expect(yalnizcaBorsa([t]), isFalse, reason: '$t tek başına');
      }
    });

    test('bilinmeyen tür (diger) → false', () {
      // Borsa takvimine bağlı olduğunu bilmediğimiz şeye "kapalı" demeyiz.
      expect(yalnizcaBorsa([AssetType.hisse, AssetType.diger]), isFalse);
    });

    test('boş portföy → false', () {
      expect(yalnizcaBorsa(const []), isFalse);
    });
  });

  group('rozet metni', () {
    test('yalnızca borsa → BORSA KAPALI', () {
      expect(piyasaKapaliEtiketi([AssetType.hisse, AssetType.fon]),
          'BORSA KAPALI');
    });

    test('karışık ya da borsasız → rozet YOK (null)', () {
      expect(piyasaKapaliEtiketi([AssetType.hisse, AssetType.altin]), isNull);
      expect(piyasaKapaliEtiketi([AssetType.kripto]), isNull);
      expect(piyasaKapaliEtiketi(const []), isNull);
    });
  });

  group('her yüzey aynı kuraldan sorar', () {
    // Kural tek yerde; bir yüzey kendi tür listesini kurarsa ayrışır ve
    // aynı anda biri "Piyasa kapalı", öbürü "Canlı" der.
    test('Performans rozeti', () {
      final kaynak = ekranKaynagiSync(
              'lib/screens/portfolio_performance_screen.dart')
          .replaceAll('\r\n', '\n');
      expect(kaynak.contains('piyasaKapaliEtiketiVarliklardan(targetAssets)'),
          isTrue);
      expect(kaynak.contains("'PİYASA KAPALI',"), isFalse);
    });

    test('Bugün kartı, ana ekran widget\'ı, Canlı Etkinlik', () {
      for (final yol in [
        'lib/widgets/bugun_karti.dart',
        'lib/services/home_widget_service.dart',
        'lib/services/live_activity_service.dart',
      ]) {
        expect(File(yol).readAsStringSync().contains('yalnizcaBorsaVarliklardan('),
            isTrue,
            reason: '$yol "kapalı" kararını ortak kuraldan almıyor.');
      }
    });

    test('native yüzeyler bayrağı okur (eksikse eski davranış)', () {
      expect(
          File('android/app/src/main/kotlin/com/sandik/app/SandikWidgetProvider.kt')
              .readAsStringSync()
              .contains('getBoolean("sandik_yalniz_borsa", true)'),
          isTrue);
      expect(
          File('ios/SandikWidget/SandikHomeWidget.swift')
              .readAsStringSync()
              .contains('"sandik_yalniz_borsa"'),
          isTrue);
      expect(
          File('supabase/functions/push-live-activity/index.ts')
              .readAsStringSync()
              .contains('yalnizBorsa: row.yalnizBorsa !== false'),
          isTrue,
          reason: 'Sunucu push\'u bayrağı taşımazsa uygulama kapalıyken '
              'kilit ekranı yine "Piyasa kapalı" der.');
    });
  });
}
