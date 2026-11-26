import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_en.dart';
import 'package:portfoy_takip/l10n/generated/app_localizations_tr.dart';
import 'package:portfoy_takip/models/signal_frequency.dart';

import 'helpers/kaynak.dart';

/// Ar-Ge 23 Kas 22:03 (UI/UX tur 18): sinyal ve bildirim Premium
/// kapılarında satın alma sonrası devam.
///
/// Ortak kırık an: kişi bir seçim yaparken Premium alıyor, paywall
/// kapanıyor, seçim uygulanmıyordu (paywall ateşle-unut açılıp `return`
/// ediliyordu). Kural: `PaywallScreen.show` sonucu beklenir, `true` ise
/// kilitsiz dokunuşla AYNI yol çalışır. Kilit/slot build'den kalma
/// olabilir (bayat kilit, tur 12): satın alma sonucuna güvenilir.
///
/// Paywall gerçek mağaza akışı açtığı için ekran kaynağı taranır; ön ayar
/// kartının davranışı `bildirim_on_ayar_test`'te widget testiyle kilitli
/// ("satın alınca Çok uygulanır").
void main() {
  final ayar = ekranKaynagiSync('lib/screens/signal_settings_screen.dart');

  group('sinyal ayarları (#1-#3)', () {
    test('ortak paywall yardımcısı satın alma sonucunu döner', () {
      expect(
          ayar.contains(
              'return await PaywallScreen.show(context, source: source) == true;'),
          isTrue);
      // Ateşle-unut çağrı kalmadı: her paywall yardımcıdan geçer.
      expect('PaywallScreen.show('.allMatches(ayar).length, 1);
    });

    test('#1 sıklık: satın alınca seçilen sıklık yazılır', () {
      final i = ayar.indexOf('onFrequencyChanged: (f) async {');
      expect(i, greaterThan(0));
      final govde = ayar.substring(i, i + 900);
      expect(govde.contains("_premiumAl(context, source: 'signal_frequency')"), isTrue);
      expect(govde.contains('.setFrequency(type, f)'), isTrue);
    });

    test('#2 ön ayar kartı: onPaywall bool döner, sonra ön ayar uygulanır',
        () {
      expect(ayar.contains('final Future<bool> Function() onPaywall;'), isTrue);
      expect(ayar.contains("onPaywall: () => _premiumAl(context, source: 'signal_on_ayar')"),
          isTrue);
      expect(
          ayar.contains('if (!await onPaywall() || !context.mounted) return;'),
          isTrue);
      expect(ayar.contains('await sinyalOnAyariUygula(ref, a);'), isTrue);
    });

    test('#3 kilitli gösterge ve periyot: satın alınca aynı yol', () {
      expect(ayar.contains("_premiumAl(context, source: 'signal_settings_\$id',"),
          isTrue);
      expect(ayar.contains("_premiumAl(context, source: 'gosterge_parametre')"), isTrue);
      expect(ayar.contains('await _parametreSheet(context, id);'), isTrue);
      // Zaten seçili göstergeyi satın alma sonrası kapatmaz.
      expect(ayar.contains('selected.contains(id)) {'), isTrue);
    });
  });

  test('#2 Ayarlar › Bildirimler ön ayar kartı satın alma sonucunu bekler',
      () {
    final kart = ekranKaynagiSync('lib/widgets/bildirim_on_ayar_karti.dart');
    expect(kart.contains('final Future<bool> Function() onPaywall;'), isTrue);
    expect(kart.contains('if (!await widget.onPaywall() || !mounted'), isTrue);
    final ayarlar = ekranKaynagiSync('lib/screens/settings_screen.dart');
    final i = ayarlar.indexOf('BildirimOnAyarKarti(');
    final govde = ayarlar.substring(i, i + 600);
    expect(govde.contains('onPaywall: () async {'), isTrue);
    expect(govde.contains('true;'), isTrue);
  });

  test('#4 takip listesi dolu kartı: satın alınca ekleme sayfası açılır', () {
    final takip = ekranKaynagiSync('lib/screens/watchlist_screen.dart');
    final i = takip.indexOf('await takipSiniriBekle(context, ref, limit)');
    expect(i, greaterThan(0));
    expect(takip.substring(i, i + 160).contains('_ekle(context);'), isTrue);
    expect(takip.contains('takipSiniriUyarisi('), isFalse);
  });

  group('#5 metin gerçek davranışı söyler', () {
    test('Premium en sık seçenek saatlik (sınırsız değil)', () {
      // Sunucu eşi `analyze-signals` GUNLUK_EN_FAZLA / PERIOD_HOURS:
      // Premium'da kapı yok, en sık sıklık saat başı, pencere 10-18.
      final enSik = SignalFrequency.values
          .map((f) => f.gunlukEnFazla)
          .reduce((a, b) => a > b ? a : b);
      expect(enSik, SignalFrequency.hourly.gunlukEnFazla);
      expect(SignalFrequency.hourly.gunlukEnFazla,
          kSignalWindowEnd - kSignalWindowStart + 1);
    });

    test('sinyal metinleri "sınırsız" demez', () {
      final tr = AppLocalizationsTr();
      final en = AppLocalizationsEn();
      for (final m in [tr.pwdSinyalPremium, tr.sgnPremiumGostergeSatiri]) {
        expect(m.contains('sınırsız'), isFalse, reason: m);
        expect(m.contains('saatlik'), isTrue, reason: m);
      }
      for (final m in [en.pwdSinyalPremium, en.sgnPremiumGostergeSatiri]) {
        expect(m.contains('unlimited'), isFalse, reason: m);
        expect(m.contains('hourly'), isTrue, reason: m);
      }
    });
  });

  test('Premium açık bilgisi tek satır: degrade kart yok (yasin 26 Kas)', () {
    // Ar-Ge 23 Kas 22:03 açık sorusu, yasin "Önerini yap": aynı bilgi,
    // süssüz satır; ≥44 pt ve tek erişilebilirlik etiketi.
    expect(ayar.contains('class _PremiumCard'), isFalse);
    expect(ayar.contains('LinearGradient'), isFalse);
    final i = ayar.indexOf('class _PremiumSatiri');
    expect(i, greaterThan(0));
    final govde = ayar.substring(i, ayar.indexOf('class _CategorySection'));
    expect(govde.contains('minHeight: SandikTouch.min'), isTrue);
    expect(govde.contains('l10n.sgnPremiumAktifGovde'), isTrue);
    expect(govde.contains("label: '\${l10n.sgnPremiumAktif}"), isTrue);
    expect(govde.contains('FontWeight.w700'), isFalse);
  });
}
