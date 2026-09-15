import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';

import 'helpers/kaynak.dart';
import 'package:portfoy_takip/services/insight_metrics_service.dart';

/// Yatırımcı seviyesi — görünürlük tablosu ve ileri metrik cebri.
///
/// TECHNICAL_DEBT "Yatırımcı seviyesine göre görünüm yok": profilde alan
/// olmadığı için ertelenmişti; opsiyonel cihaz tercihi olarak kapandı.
/// Sabitlenen kurallar: varsayılan Orta = bugünkü görünüm (hiçbir şey
/// değişmez), Başlangıç yalnızca GİZLER, İleri yalnızca EKLER; hesaplar
/// seviyeden bağımsız.
void main() {
  group('YatirimciSeviyesi', () {
    test('varsayılan Orta — dokunmayan kullanıcı için değişiklik yok', () {
      expect(YatirimciSeviyesi.varsayilan, YatirimciSeviyesi.orta);
      expect(YatirimciSeviyesi.fromIndex(1), YatirimciSeviyesi.orta);
    });

    test('bozuk indeks varsayılana düşer, ekranı boşaltmaz', () {
      expect(YatirimciSeviyesi.fromIndex(-1), YatirimciSeviyesi.orta);
      expect(YatirimciSeviyesi.fromIndex(99), YatirimciSeviyesi.orta);
    });

    test('her seviyenin etiketi ve açıklaması iki dilde de var', () {
      for (final l in [AppLocalizationsTr(), AppLocalizationsEn()]) {
        for (final s in YatirimciSeviyesi.values) {
          expect(s.etiketOf(l).trim(), isNotEmpty);
          expect(s.aciklamaOf(l).trim(), isNotEmpty);
        }
      }
    });
  });

  group('seviyeGorunurlugu', () {
    test('Orta = bugünkü küme (ileri kart hariç her şey açık)', () {
      final g = seviyeGorunurlugu(YatirimciSeviyesi.orta);
      expect(
        g,
        (
          saglik: true,
          xirr: true,
          percentile: true,
          teknikSinyaller: true,
          ileri: false
        ),
      );
    });

    test('Başlangıç yalnızca gizler', () {
      final g = seviyeGorunurlugu(YatirimciSeviyesi.baslangic);
      expect(g.saglik, isFalse);
      expect(g.xirr, isFalse);
      expect(g.percentile, isFalse);
      expect(g.teknikSinyaller, isFalse);
      expect(g.ileri, isFalse);
    });

    test('İleri, Orta\'nın üstüne yalnızca ekler', () {
      final orta = seviyeGorunurlugu(YatirimciSeviyesi.orta);
      final ileri = seviyeGorunurlugu(YatirimciSeviyesi.ileri);
      expect(ileri.saglik, orta.saglik);
      expect(ileri.xirr, orta.xirr);
      expect(ileri.percentile, orta.percentile);
      expect(ileri.teknikSinyaller, orta.teknikSinyaller);
      expect(ileri.ileri, isTrue);
    });

    test('Başlangıç ilk açılışta GÖRÜNEN yüzeyleri de kapatır', () {
      // Asıl şikâyet buydu (2026-09-15): tablo yalnızca 1Y'ye bağlı Özet
      // kartlarını süzerken, bir yıllık geçmişi olmayan kullanıcı seviye
      // değiştirince hiçbir fark görmüyordu. Ana ekran yüzdelik şeridi ve
      // teknik sinyal yüzeyleri dönemden ve havuz eşiğinden bağımsız.
      final b = seviyeGorunurlugu(YatirimciSeviyesi.baslangic);
      expect(b.teknikSinyaller, isFalse,
          reason: 'ana ekran sinyal zili + tekil varlık sinyal kartı/paneli');
      expect(b.percentile, isFalse, reason: 'ana ekran yüzdelik şeridi');
    });
  });

  group('IleriMetrikler.hesapla', () {
    test('risk-ayarlı getiri = getiri / oynaklık', () {
      final m = IleriMetrikler.hesapla(
          getiriPct: 30, volatilitePct: 15, xirrPct: null, drawdown: null)!;
      expect(m.riskAyarliGetiri, closeTo(2.0, 1e-9));
      expect(m.zamanlamaEtkisi, isNull);
    });

    test('oynaklık sıfır/negatif/NaN ise oran UYDURULMAZ', () {
      for (final v in [0.0, -1.0, double.nan]) {
        final m = IleriMetrikler.hesapla(
            getiriPct: 30, volatilitePct: v, xirrPct: 25, drawdown: null)!;
        expect(m.riskAyarliGetiri, isNull, reason: 'vol=$v');
      }
    });

    test('zamanlama etkisi = XIRR − piyasa getirisi (işaretli)', () {
      final m = IleriMetrikler.hesapla(
          getiriPct: 20, volatilitePct: null, xirrPct: 17.5, drawdown: null)!;
      expect(m.zamanlamaEtkisi, closeTo(-2.5, 1e-9));
    });

    test('toparlanma: gün varsa gün; yoksa "toparlanmadı" bayrağı', () {
      const dd = Drawdown(yuzde: 12, zirveTs: 1, dipTs: 2, toparlanmaGun: 40);
      final a = IleriMetrikler.hesapla(
          getiriPct: null, volatilitePct: null, xirrPct: null, drawdown: dd)!;
      expect(a.toparlanmaGun, 40);
      expect(a.toparlanmadi, isFalse);

      const acik = Drawdown(yuzde: 12, zirveTs: 1, dipTs: 2);
      final b = IleriMetrikler.hesapla(
          getiriPct: null, volatilitePct: null, xirrPct: null, drawdown: acik)!;
      expect(b.toparlanmaGun, isNull);
      expect(b.toparlanmadi, isTrue);
    });

    test('hiçbir metrik yoksa null — kart çizilmez', () {
      expect(
        IleriMetrikler.hesapla(
            getiriPct: null, volatilitePct: null, xirrPct: null, drawdown: null),
        isNull,
      );
    });
  });

  // ── Bağlantı denetimi: tablo GERÇEKTEN ekranlara bağlı mı ────────────────
  //
  // Karar tablosunun doğru olması yetmez; şikâyetin kökü tablonun yalnızca
  // tek bir (ve çoğu kullanıcıda boş kalan) yüzeye bağlı olmasıydı. Bu grup
  // bağlantının kendisini kilitler.
  group('ekranlara bağlı', () {
    test('ana ekran: yüzdelik şeridi ve sinyal zili seviyeye bakar', () {
      final src = ekranKaynagiSync('lib/screens/home_screen.dart');
      expect(src.contains('seviyeGorunurlugu'), isTrue,
          reason: 'ana ekran seviye tablosunu okumuyor');
      expect(RegExp(r'\.percentile\)\s*\n\s*SliverToBoxAdapter\(\s*\n\s*child: PercentileStrip')
          .hasMatch(src), isTrue,
          reason: 'yüzdelik şeridi seviyeye bağlı değil');
      expect(src.contains('.teknikSinyaller) ...['), isTrue,
          reason: 'sinyal zili seviyeye bağlı değil');
    });

    test('tekil varlık: sinyal kartı ve gösterge paneli seviyeye bakar', () {
      final src = ekranKaynagiSync('lib/screens/asset_detail_screen.dart');
      expect(src.contains('_sinyalYuzeyleri'), isTrue);
      expect(src.contains('if (_sinyalYuzeyleri)\n                  AssetSignalCard'),
          isTrue,
          reason: 'sinyal kartı seviyeye bağlı değil');
      expect(src.contains('if (_sinyalYuzeyleri) ...[\n                  const SizedBox(height: 24),\n                  TechnicalSignalPanel'),
          isTrue,
          reason: 'gösterge paneli seviyeye bağlı değil');
    });

    test('Özet: dört kart da seviyeye bakar', () {
      final src =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      for (final alan in ['gorunur.saglik', 'gorunur.ileri', 'gorunur.percentile', 'gorunur.xirr']) {
        expect(src.contains(alan), isTrue, reason: '$alan bağlı değil');
      }
    });
  });
}
