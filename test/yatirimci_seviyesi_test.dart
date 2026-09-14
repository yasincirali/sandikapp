import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/yatirimci_seviyesi.dart';
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
    test('Orta = bugünkü küme (sağlık, XIRR, yüzdelik açık; ileri kapalı)', () {
      final g = seviyeGorunurlugu(YatirimciSeviyesi.orta);
      expect(g, (saglik: true, xirr: true, percentile: true, ileri: false));
    });

    test('Başlangıç yalnızca gizler', () {
      final g = seviyeGorunurlugu(YatirimciSeviyesi.baslangic);
      expect(g.saglik, isFalse);
      expect(g.xirr, isFalse);
      expect(g.percentile, isFalse);
      expect(g.ileri, isFalse);
    });

    test('İleri, Orta\'nın üstüne yalnızca ekler', () {
      final orta = seviyeGorunurlugu(YatirimciSeviyesi.orta);
      final ileri = seviyeGorunurlugu(YatirimciSeviyesi.ileri);
      expect(ileri.saglik, orta.saglik);
      expect(ileri.xirr, orta.xirr);
      expect(ileri.percentile, orta.percentile);
      expect(ileri.ileri, isTrue);
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
}
