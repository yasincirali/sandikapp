import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/models/asset_type.dart';
import 'package:portfoy_takip/services/technical_analysis_service.dart';

/// Gösterge periyotları (Premium, yasin 2026-10-10: "var olan göstergeler de
/// parametrik kullanılabilmeli premiumda").
///
/// Kilitler:
///  - Varsayılan ayar = ayarsız hesap (hesap fonksiyonlarındaki sabitlerle
///    `GostergeParametreleri.varsayilan` aynı); yoksa parametre ekranındaki
///    "varsayılan" bir yalan olurdu.
///  - Doğrulama: aralığa kırpar, anlamsız çifti (hızlı ≥ yavaş) atar.
///  - Sunucu tablosu (`_shared/technical_analysis.ts`) istemciyle aynı
///    sınırları taşır: ekrandaki sinyal ile push aynı periyotla hesaplanır.
void main() {
  // Sabit tohumlu yapay seri (rastgele yürüyüş, 300 gün).
  final r = Random(7);
  var p = 100.0;
  final seri = [
    for (var i = 0; i < 300; i++) p = max(1, p * (1 + (r.nextDouble() - 0.5) * 0.04))
  ];

  group('varsayılan = ayarsız', () {
    for (final tur in [
      AssetType.hisse,
      AssetType.doviz,
      AssetType.altin,
      AssetType.fon,
    ]) {
      test(tur.name, () {
        final hepsi = IndicatorId.all.toSet();
        final ayarsiz = TechnicalAnalysisService.analyzeSeries(seri, tur,
            enabledIds: hepsi, izinli: hepsi);
        final varsayilan = TechnicalAnalysisService.analyzeSeries(seri, tur,
            enabledIds: hepsi,
            izinli: hepsi,
            parametreler: {
              for (final id in IndicatorId.all)
                id: GostergeParametreleri.varsayilan(id, tur),
            });
        expect(varsayilan.length, ayarsiz.length);
        for (var i = 0; i < ayarsiz.length; i++) {
          expect(varsayilan[i].name, ayarsiz[i].name);
          expect(varsayilan[i].value, closeTo(ayarsiz[i].value, 1e-9),
              reason: ayarsiz[i].name);
          expect(varsayilan[i].signal, ayarsiz[i].signal);
        }
      });
    }
  });

  test('farklı periyot farklı sonuç (parametre gerçekten uygulanır)', () {
    final a = TechnicalAnalysisService.analyzeSeries(seri, AssetType.hisse,
        enabledIds: {IndicatorId.rsi});
    final b = TechnicalAnalysisService.analyzeSeries(seri, AssetType.hisse,
        enabledIds: {IndicatorId.rsi},
        parametreler: {
          IndicatorId.rsi: {'periyot': 5}
        });
    expect(a.single.value, isNot(closeTo(b.single.value, 1e-6)));
  });

  group('doğrula', () {
    test('aralığa kırpar, bilinmeyen anahtarı atar', () {
      expect(GostergeParametreleri.dogrula(IndicatorId.rsi, {'periyot': 999}),
          {'periyot': 50});
      expect(
          GostergeParametreleri.dogrula(
              IndicatorId.rsi, {'periyot': 1, 'x': 3}),
          {'periyot': 2});
      expect(GostergeParametreleri.dogrula(IndicatorId.rsi, {'x': 3}), isNull);
      expect(GostergeParametreleri.dogrula('yok', {'periyot': 3}), isNull);
    });

    test('anlamsız çift ayarın tümünü düşürür', () {
      expect(
          GostergeParametreleri.dogrula(
              IndicatorId.macd, {'hizli': 30, 'yavas': 20, 'sinyal': 9}),
          isNull);
      expect(
          GostergeParametreleri.dogrula(
              IndicatorId.ema, {'kisa': 50, 'uzun': 50}),
          isNull);
      expect(
          GostergeParametreleri.dogrula(
              IndicatorId.macd, {'hizli': 8, 'yavas': 21, 'sinyal': 5}),
          {'hizli': 8, 'yavas': 21, 'sinyal': 5});
    });
  });

  test('sunucu sınır tablosu istemciyle aynı', () {
    final ts = File('supabase/functions/_shared/technical_analysis.ts')
        .readAsStringSync();
    final blok = RegExp(r'PARAMETRE_TANIMLARI[^=]*= \{([\s\S]*?)\n\};')
        .firstMatch(ts)!
        .group(1)!;
    final sunucu = <String, Map<String, (int, int)>>{};
    for (final satir in RegExp(r'(\w+): \[(.*)\],').allMatches(blok)) {
      sunucu[satir.group(1)!] = {
        for (final m in RegExp(r"\['(\w+)', (\d+), (\d+)\]")
            .allMatches(satir.group(2)!))
          m.group(1)!: (int.parse(m.group(2)!), int.parse(m.group(3)!)),
      };
    }
    final istemci = {
      for (final e in GostergeParametreleri.tanimlar.entries)
        e.key: {for (final t in e.value) t.anahtar: (t.enAz, t.enCok)},
    };
    expect(sunucu, istemci);
  });
}
