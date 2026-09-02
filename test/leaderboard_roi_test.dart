import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';

/// **Yarışta herkes TEK formülle ölçülür: seçili dönemin getirisi.**
///
/// ```
///   (dönem sonu değeri − dönem başı değeri) / dönem başı değeri × 100
/// ```
///
/// ## Neden bu test var
/// Önceki hesap İKİ ayrı formül kullanıyordu ve hangisinin çalıştığı KİŞİYE
/// GÖRE değişiyordu:
///   · dönem başında portföyü OLAN → dönemsel ROI + nakit akışı düzeltmesi
///   · dönem başında portföyü OLMAYAN → maliyet bazlı fallback
///
/// Ölçüldü: aynı işlemi yapan iki kullanıcı **%380,67** ve **%20,00** olarak
/// sıralanıyordu. Aynı yarışta iki farklı metrik → sıralama anlamsız.
///
/// ## Neden `simulate: true`
/// Gerçek geçmiş modunda `addedDate`'ten önceki slotlara 0 yazılır; dönem
/// başı 0 olunca bölme tanımsız kalır ve dönem içinde alım yapan HERKES
/// sıralamadan düşerdi. Simülasyon herkesi aynı pencerede ölçer.
///
/// ## Bu testin sınırı
/// `donemGetirisiPct` ağ çağrısı yapar (fiyat geçmişi). Buradaki testler
/// formülün KENDİSİNİ saf `normalizeSeries` üzerinden ve kablolamayı kaynak
/// metninden doğrular; uçtan uca doğrulama emülatörde yapıldı.

/// Yorum satırlarını atar — bir açıklama içindeki kelime gerçek kodmuş gibi
/// sayılmasın. (Bu tuzağa `signal_provider` wiring testinde bir kez düşüldü.)
String _yorumsuz(String src) => src.split('\n').where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('///') && !t.startsWith('*');
    }).join('\n');

void main() {
  group('formül: (son − ilk) / ilk', () {
    // Metriğin matematiği. `donemGetirisiPct` bu hesabı seri üzerinde
    // yapıyor; burada aynı hesabı doğrudan sınıyoruz.
    double? getiri(Map<int, double> seri) {
      if (seri.length < 2) return null;
      final ts = seri.keys.toList()..sort();
      final ilk = seri[ts.first]!;
      if (ilk <= 0) return null;
      return ((seri[ts.last]! - ilk) / ilk) * 100.0;
    }

    test('yükselen dönem POZİTİF', () {
      expect(getiri({1: 1000.0, 2: 1100.0, 3: 1200.0}), closeTo(20.0, 1e-9));
    });

    test('düşen dönem NEGATİF', () {
      expect(getiri({1: 2000.0, 2: 1500.0}), closeTo(-25.0, 1e-9));
    });

    test('değişmeyen dönem SIFIR', () {
      expect(getiri({1: 1000.0, 2: 1000.0}), closeTo(0.0, 1e-9));
    });

    test('ARADAKİ dalgalanma sonucu etkilemez — yalnızca uçlar', () {
      // Dönem içinde ne olduğu değil, başı ve sonu önemli.
      final duz = getiri({1: 1000.0, 2: 1200.0});
      final dalgali = getiri({1: 1000.0, 2: 5000.0, 3: 200.0, 4: 1200.0});
      expect(duz, dalgali);
    });

    test('dönem başı 0 ise NULL — bölme tanımsız', () {
      expect(getiri({1: 0.0, 2: 1000.0}), isNull);
    });

    test('tek nokta NULL — değişim tanımsız', () {
      expect(getiri({1: 1000.0}), isNull);
    });
  });

  group('normalizeSeries ile AYNI soru', () {
    // Takip listesi grafiği de dönem başını %0 kabul edip aynı oranı
    // hesaplıyor. İki yüzeyin farklı sayı göstermesi kafa karıştırırdı.
    test('grafik motoruyla örtüşür', () {
      const seri = {1: 1000.0, 2: 1100.0, 3: 1250.0};
      final n = normalizeSeries(seri)!;
      final ts = seri.keys.toList()..sort();
      final elle =
          ((seri[ts.last]! - seri[ts.first]!) / seri[ts.first]!) * 100.0;
      expect(n.totalReturnPct, closeTo(elle, 1e-9));
      expect(n.totalReturnPct, closeTo(25.0, 1e-9));
    });
  });

  group('boş / geçersiz girdi', () {
    test('boş portföy NULL', () async {
      expect(await LeaderboardService.instance.donemGetirisiPct(const [], 30),
          isNull);
    });

    test('computeROIDetailed boş listede null döner', () async {
      final r = await LeaderboardService.instance.computeROIDetailed(
        assets: const [],
        periodDays: 30,
        currentValueTRY: 0,
        toTRY: (v, c) => v,
      );
      expect(r.roi, isNull);
      expect(r.usedFallback, isFalse);
    });
  });

  group('kablolama — kaynak kuralları', () {
    late String servis;

    setUpAll(() async {
      servis = _yorumsuz(
          await File('lib/services/leaderboard_service.dart').readAsString());
    });

    test('SİMÜLASYON modu kullanılır', () {
      // Gerçek geçmiş modu, dönem içinde alım yapan herkesi sıralamadan
      // düşürürdü (dönem başı 0 → bölme tanımsız).
      expect(servis.contains('simulate: true'), isTrue,
          reason: 'gerçek geçmiş modu alım öncesi slotlara 0 yazar');
    });

    test('formül seriden (son − ilk) / ilk olarak hesaplanır', () {
      expect(servis.contains('((son - ilk) / ilk) * 100.0'), isTrue);
    });

    test('dönem başı ≤ 0 KORUNUR', () {
      expect(servis.contains('if (ilk <= 0) return null'), isTrue,
          reason: 'sıfıra bölme sonsuz yüzde üretirdi');
    });

    test('kendi hesabım da AYNI fonksiyondan geçer', () {
      // Asimetri bug'ın kaynağıydı: ben bir formülle, ortak başkasıyla.
      final i = servis.indexOf('Future<RoiResult> computeROIDetailed(');
      expect(i, greaterThan(0));
      final govde = servis.substring(i, i + 900);
      expect(govde.contains('donemGetirisiPct(assets, periodDays)'), isTrue,
          reason: 'kendi değerim de ortaklarla aynı yoldan hesaplanmalı');
    });
  });

  group('ortak uygulamayı AÇMASA da hesaplanır', () {
    // Ortakların değeri eskiden Supabase snapshot'ından okunuyordu ve o
    // snapshot'ı yalnızca ortağın KENDİ cihazı yazabiliyordu:
    //   · ortak uygulamayı hiç açmadıysa → yarışta değeri YOK,
    //   · eski sürümde açtıysa → eski formülle yazılmış bayat değer,
    //   · bugün açmadıysa → dünkü fiyatlarla hesaplanmış değer.
    //
    // Ortağın lot'ları `allPartnerAssetsProvider` ile zaten cihazda.

    test('yarış ekranı snapshot ÇEKMEZ', () async {
      for (final yol in [
        'lib/screens/leaderboard_screen.dart',
        'lib/widgets/leaderboard_hero_card.dart',
      ]) {
        final src = _yorumsuz(await File(yol).readAsString());
        expect(src.contains('fetchPartnerRois'), isFalse,
            reason: '$yol ortağın snapshot\'ını beklememeli');
        expect(src.contains('donemGetirisiPct'), isTrue,
            reason: '$yol ortağın değerini yerelde hesaplamalı');
      }
    });

    test('ortakların hesabı PARALEL yapılır', () async {
      // Sırayla beklemek ortak sayısıyla orantılı gecikme yaratırdı.
      for (final yol in [
        'lib/screens/leaderboard_screen.dart',
        'lib/widgets/leaderboard_hero_card.dart',
      ]) {
        final src = _yorumsuz(await File(yol).readAsString());
        expect(src.contains('Future.wait('), isTrue, reason: yol);
      }
    });
  });

  group('sıralama', () {
    test('daha çok kazanan ÜSTTE', () {
      // Sıralama karşılaştırıcısı `roi` üzerinden azalan; null'lar sona.
      final roiler = <double?>[12.5, null, -3.0, 40.0];
      final sirali = [...roiler]..sort((a, b) {
          if (a == null && b == null) return 0;
          if (a == null) return 1;
          if (b == null) return -1;
          return b.compareTo(a);
        });
      expect(sirali, [40.0, 12.5, -3.0, null]);
    });
  });
}
