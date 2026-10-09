import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/history_service.dart';
import 'package:portfoy_takip/services/leaderboard_service.dart';
import 'helpers/kaynak.dart';

/// **Yarışta herkes TEK formülle ölçülür: seçimlerinin getirisi (TWR).**
///
/// 2026-10-01'den (0095, kullanıcı kararı R1) beri zaman ağırlıklı getiri:
/// dönem günlere bölünür, her gün tutulan varlıklar piyasa fiyatıyla
/// değerlenir, günler çarpılır (`secim_getirisi.dart`; senaryo testleri
/// `secim_getirisi_test.dart`). Öncesindeki simülasyon (bugünkü sepet dönem
/// başından beri tutulmuş sayılırdı) satıp başka varlık alanın kararını
/// görmüyordu. Aşağıdaki "ölçekten bağımsız" özellik TWR'de de geçerli.
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
/// ## Neden gerçek geçmiş modu (`simulate: false`) DEĞİL
/// Gerçek geçmiş modunda `addedDate`'ten önceki slotlara 0 yazılır; dönem
/// başı 0 olunca bölme tanımsız kalır ve dönem içinde alım yapan HERKES
/// sıralamadan düşerdi. TWR her günü o günün miktarıyla ölçer; geç giren
/// yalnız tuttuğu günlerle ölçülür.
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

  group('SAF PİYASA HAREKETİ — para akışı oranı etkilemez', () {
    // Yarışın sorusu "kim daha çok para koydu" değil, "kimin portföyü daha
    // çok değer kazandı". `simulate: true` bunu sağlıyor: bugünkü net
    // pozisyon dönemin tamamına yayıldığı için dönem başı da aynı oranda
    // büyüyor ve oran sabit kalıyor.
    //
    // Gerçek fiyat serisiyle ölçüldü (THYAO, 30 gün):
    //   10 adet, hiç dokunmadı           → −%7,34
    //   10 adet + 15 gün önce 10 daha    → −%7,34
    //   20 al, 10 sat (net 10)           → −%7,34
    //   1 adet / 10.000 adet             → −%7,34

    /// Simülasyonun özü: miktar k katına çıkınca seri de k katına çıkar,
    /// oran değişmez. Ağ olmadan bu değişmezi doğrudan sınıyoruz.
    double? oran(Map<int, double> seri) {
      final ts = seri.keys.toList()..sort();
      final ilk = seri[ts.first]!;
      if (ilk <= 0) return null;
      return ((seri[ts.last]! - ilk) / ilk) * 100.0;
    }

    test('miktar ÖLÇEKLENİNCE oran değişmez', () {
      const tek = {1: 3237.5, 2: 3100.0, 3: 3000.0};
      // Dönem içinde iki katına çıkarılmış portföy: her nokta 2×.
      final iki = {for (final e in tek.entries) e.key: e.value * 2};
      expect(oran(iki), closeTo(oran(tek)!, 1e-9),
          reason: 'yeni para girişi getiri gibi görünmemeli');
    });

    test('10.000 kat büyük portföy AYNI oranı verir', () {
      const kucuk = {1: 100.0, 2: 90.0};
      final buyuk = {for (final e in kucuk.entries) e.key: e.value * 10000};
      expect(oran(buyuk), closeTo(oran(kucuk)!, 1e-9),
          reason: 'portföy büyüklüğü sıralamayı etkilememeli');
    });

    test('negatif yönde de ölçekten bağımsız', () {
      const a = {1: 1000.0, 2: 800.0};
      final b = {for (final e in a.entries) e.key: e.value * 3.7};
      expect(oran(b), closeTo(-20.0, 1e-9));
      expect(oran(a), closeTo(-20.0, 1e-9));
    });

    test('ölçü KAYNAKTA tek yerde: seçimlerinin getirisi', () async {
      // Bir sonraki geliştirici "para eklemek neden yüzdemi değiştirmiyor?"
      // diye sorup Yarış'a para ağırlıklı ya da gerçek geçmiş moduna
      // dönmesin — R1 kararı.
      final servis = _yorumsuz(
          await File('lib/services/leaderboard_service.dart').readAsString());
      expect(
          RegExp(r'SecimGetirisi\.donemPct\(assets, periodDays,\s*kapsam: kapsam')
              .hasMatch(servis),
          isTrue);
      expect(servis.contains('simulate: true'), isFalse,
          reason: 'simülasyon 0095 ile emekli oldu');
    });

    test('KULLANICIYA da anlatılıyor — info sayfası', () async {
      // Kullanıcı "neden para yatırınca yüzdem değişmedi?" diye sormamalı.
      final ekran = _yorumsuz(
          await File('lib/screens/leaderboard_screen.dart').readAsString());
      expect(ekran.contains('l10n.depositsDontChangeRank'), isTrue,
          reason: 'metriğin en şaşırtıcı yanı açıkça yazılmalı');
      expect(trMetni('depositsDontChangeRank'), contains('sıralamayı değiştirmez'));
      // 3.20: metin sözlükte (`depositsDontChangeRankBody`).
      expect(ekran.contains('l10n.depositsDontChangeRankBody'), isTrue);
      expect(trMetni('depositsDontChangeRankBody'), contains('ETKİLEMEZ'));
      // Hesabın kendisi yazılı olmalı.
      expect(trMetni('selectedPeriodReturnBody'), contains('günlere bölünür'),
          reason: 'hesabın kendisi kullanıcıya gösterilmeli');
      // Hile kuralları ve sınır dürüstçe belirtilmeli.
      // Süre sunucudan (0128) — sayı yer tutucuyla, edinme tarihinden.
      expect(trMetni('everyoneMeasuredSameBody'), contains('en az {gun} gün'));
      expect(trMetni('everyoneMeasuredSameBody'), contains('edinmenin'));
      expect(trMetni('everyoneMeasuredSameBody'), contains('3 günden fazla'));
      expect(ekran.contains('l10n.rankSwapNote'), isTrue,
          reason: 'yeni katılan sınırı gizlenmemeli');
      expect(trMetni('rankSwapNote'), contains('tuttuğu süre kadar'));
      // Kendi satırında paranın getirisi — Performans ile aynı sayı.
      expect(ekran.contains('l10n.raceMoneyReturn('), isTrue);
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
      expect(await LeaderboardService.instance
              .donemGetirisiPct(const [], 30, kapsam: SiralamaKapsami.ortaklar),
          isNull);
    });

    test('computeROIDetailed boş listede null döner', () async {
      final r = await LeaderboardService.instance.computeROIDetailed(
        assets: const [],
        periodDays: 30,
        currentValueTRY: 0,
        toTRY: (v, c) => v,
        kapsam: SiralamaKapsami.ortaklar,
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

    test('Yarış ölçüsü TWR motorundan gelir, simülasyondan değil', () {
      expect(servis.contains('SecimGetirisi.donemPct('), isTrue);
      expect(servis.contains('simulate: true'), isFalse);
    });

    test('ROI anlık görüntüsünü istemci YAZMAZ (0095)', () {
      // Sunucuda istemci INSERT yetkisi geri alındı; yalnız cron yazar.
      expect(servis.contains("from('user_roi_snapshots').insert"), isFalse);
      for (final yol in [
        'lib/screens/leaderboard_screen.dart',
        'lib/widgets/leaderboard_hero_card.dart',
        'lib/widgets/percentile_strip.dart',
        'lib/screens/portfolio_performance/ozet_yan_veri.dart',
      ]) {
        expect(ekranKaynagiSync(yol).contains('uploadRoiSnapshot'), isFalse,
            reason: yol);
      }
    });

    test('paranın getirisi Özet yolundan (yeni XIRR yok)', () {
      final i = servis.indexOf('Future<double?> paraninGetirisiPct(');
      expect(i, greaterThan(0));
      final govde = servis.substring(i, i + 1500);
      expect(govde.contains('PeriodSummaryService.compute('), isTrue);
      expect(govde.contains('DailySummary.kapsamToplami('), isTrue,
          reason: 'sağ uç Performans › Özet ile aynı (canlı kapsam toplamı)');
    });

    test('kendi hesabım da AYNI fonksiyondan geçer', () {
      // Asimetri bug'ın kaynağıydı: ben bir formülle, ortak başkasıyla.
      final i = servis.indexOf('Future<RoiResult> computeROIDetailed(');
      expect(i, greaterThan(0));
      final govde = servis.substring(i, i + 900);
      expect(
          govde.contains(
              'donemGetirisiPct(assets, periodDays, kapsam: kapsam)'),
          isTrue,
          reason: 'kendi değerim de ortaklarla aynı yoldan hesaplanmalı');
      // Önbellek anahtarı kapsamı taşır: Yarış'ın değeri Zirve'nin yerine
      // geçmesin (geriye tarihli kayıtta iki kapsam farklı sayı verir).
      expect(govde.contains(r"'$cacheKey|$periodDays|${kapsam.name}'"), isTrue);
    });

    test('ortaklar arası Yarış beyan tarihine, Zirve kurala güvenir', () {
      final ekran = _yorumsuz(ekranKaynagiSync('lib/screens/leaderboard_screen.dart'));
      final i = ekran.indexOf('final partnerRois = await Future.wait(');
      expect(i, greaterThan(0));
      expect(ekran.substring(i, i + 400).contains('SiralamaKapsami.ortaklar'),
          isTrue);
      final zirve = _yorumsuz(
          ekranKaynagiSync('lib/screens/zirve_portfoyler_screen.dart'));
      expect(zirve.contains('SiralamaKapsami.ortaklar'), isFalse,
          reason: 'Zirve anonim: sunucuyla aynı geriye tarih kuralı');
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
