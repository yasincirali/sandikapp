import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

import 'helpers/kaynak.dart';

/// Native yüzeylerin ÜRETTİĞİ URI'ler ile Dart'ın BEKLEDİĞİ eşleme
/// birbirini tutmalı.
///
/// ## Neden kaynak denetimi
/// Bu üç dosya üç ayrı dilde (Swift, Kotlin, Dart) ve üçü de aynı sabiti
/// elle taşıyor. Biri değişip diğeri kalırsa dokunuş SESSİZCE ölür:
/// uygulama yine açılır, yalnızca yönlendirme olmaz — ne derleme kırılır
/// ne de bir hata düşer. Swift tarafı bu makinede derlenemediği için
/// (iOS SDK yok) tek erişilebilir güvence budur.
///
/// ## `?homeWidget` tuzağı
/// `home_widget` eklentisi iOS'ta gelen URL'leri `isWidgetUrl` ile süzüyor
/// ve yalnızca `homeWidget` adlı query parametresi taşıyanları kabul
/// ediyor (`HomeWidgetPlugin.swift:462`, paket 0.9.3). Parametresiz URL
/// eklentiye hiç ulaşmaz. Bu, kodu okuyarak değil paketin kaynağı
/// okunarak bulundu — bu yüzden testle kilitleniyor.
String _oku(String yol) =>
    File(yol).readAsStringSync().replaceAll('\r\n', '\n');

/// Bir metodun GÖVDESİ — imzadan bir sonraki üst düzey üye bildirimine
/// kadar.
///
/// Kaynak tarayan iddialar dosya geneli `contains` ile yapılırsa, aranan
/// metin başka bir metotta (ya da bir alan varsayılanında) geçtiği için
/// sessizce yeşil kalır. Kapsamı daraltmak iddiayı gerçekten metoda bağlar.
String _govde(String kaynak, String imza) {
  final i = kaynak.indexOf(imza);
  if (i == -1) return '';
  final sonrasi = kaynak.substring(i + imza.length);
  final son = RegExp(r'\n  (?:@override|void |Future|Widget |static |[A-Z])')
      .firstMatch(sonrasi);
  return sonrasi.substring(0, son?.start ?? sonrasi.length);
}

/// `URL(string: "...")` / `"..."` içinden URI'yi çeker.
String? _uriAyikla(String kaynak, String isim) {
  final i = kaynak.indexOf(isim);
  if (i == -1) return null;
  final m = RegExp(r'"(sandik://[^"]+)"').firstMatch(kaynak.substring(i));
  return m?.group(1);
}

void main() {
  group('iOS — Canlı Etkinlik', () {
    final swift = _oku('ios/SandikWidget/SandikLiveActivity.swift');

    test('dokunuş hedefi TANIMLI', () {
      // Canlı Etkinlik'te `.widgetURL` yoksa dokunuş uygulamayı açar ama
      // kullanıcı en son bıraktığı sekmede kalır — bulgunun kendisi buydu.
      expect(swift.contains('.widgetURL(liveActivityClickURL)'), isTrue,
          reason: 'Kilit ekranı / Dynamic Island dokunma hedefi kayıp.');
    });

    test('URI Dart eşlemesiyle UYUŞUYOR', () {
      final uri = _uriAyikla(swift, 'liveActivityClickURL');
      expect(uri, isNotNull, reason: 'liveActivityClickURL bulunamadı.');
      expect(DeepLinkRouter.hedefSekmeMetin(uri), isNotNull,
          reason: 'Swift "$uri" üretiyor ama Dart bunu tanımıyor.');
    });

    test('`?homeWidget` parametresi VAR', () {
      final uri = _uriAyikla(swift, 'liveActivityClickURL')!;
      expect(uri.contains('homeWidget'), isTrue,
          reason: 'Parametre yok — URL iOS eklentisinin süzgecinden '
              'geçemez ve dokunuş Dart\'a hiç ulaşmaz.');
    });
  });

  group('iOS — ana ekran widget\'ı', () {
    final swift = _oku('ios/SandikWidget/SandikHomeWidget.swift');

    test('URI Dart eşlemesiyle UYUŞUYOR', () {
      final uri = _uriAyikla(swift, 'widgetClickURL');
      expect(uri, isNotNull);
      expect(DeepLinkRouter.hedefSekmeMetin(uri), isNotNull,
          reason: 'Swift "$uri" üretiyor ama Dart bunu tanımıyor.');
    });

    test('`?homeWidget` parametresi VAR', () {
      expect(_uriAyikla(swift, 'widgetClickURL')!.contains('homeWidget'), isTrue,
          reason: 'Parametresiz URL iOS\'ta sessizce düşer.');
    });
  });

  group('Android — ana ekran widget\'ı', () {
    test('URI Dart sabitiyle BİREBİR aynı', () {
      final kotlin = _oku(
          'android/app/src/main/kotlin/com/sandik/app/SandikWidgetProvider.kt');
      final m =
          RegExp(r'WIDGET_CLICK_URI\s*=\s*"([^"]+)"').firstMatch(kotlin);
      expect(m, isNotNull, reason: 'WIDGET_CLICK_URI bulunamadı.');
      expect(m!.group(1), HomeWidgetService.widgetClickUri,
          reason: 'Kotlin ve Dart sabitleri ayrışmış — atıf ve '
              'yönlendirme bu eşleşmeye dayanıyor.');
    });
  });

  group('iOS — Info.plist', () {
    test('`sandik` URL şeması KAYITLI', () {
      // Şema kayıtlı değilse iOS URL'yi uygulamaya hiç teslim etmez.
      // Derleme başarılı olduğu için hata ancak cihazda görünür.
      final plist = _oku('ios/Runner/Info.plist');
      expect(plist.contains('CFBundleURLSchemes'), isTrue,
          reason: 'URL şeması bloğu yok.');
      expect(plist.contains('<string>sandik</string>'), isTrue,
          reason: '`sandik` şeması kayıtlı değil — derin bağlantı '
              'iOS\'ta sessizce çalışmaz.');
    });
  });

  // Dokunuştan SONRA görülen yüzey, dokunulan yüzeyle aynı şeyi anlatmalı.
  //
  // Kilit ekranı / widget `DailySummary` gösteriyor: kendi portföyü, tüm
  // türler, gün içi seri. Uygulama başka bir dönemde (1Y), başka bir
  // kapsamda (ortak sekmesi, tür filtresi) ya da Özet sekmesinde açılırsa
  // kullanıcı iki rakamı yan yana görüp hangisine güveneceğini bilemez.
  //
  // Ekran state'i `IndexedStack` içinde KORUNUYOR (bkz. `_AnimatedIndexedStack`),
  // yani `initialPeriodIdx` varsayılanına güvenmek yetmez — istek açıkça
  // taşınmalı ve tüketilmeli.
  group('dokunuş → GÜNLÜK görünüm', () {
    test('widget ve Canlı Etkinlik GÜNLÜK ister', () {
      expect(
          DeepLinkRouter.gunlukGorunumIster(
              Uri.parse('sandik://live-activity/summary?homeWidget=1')),
          isTrue);
      expect(
          DeepLinkRouter.gunlukGorunumIster(
              Uri.parse('sandik://widget/home?homeWidget=1')),
          isTrue);
    });

    test('varlık bağlantısı ve tanınmayan URI İSTEMEZ', () {
      // `sandik://asset/<id>` tekil varlık ekranına gider; portföy
      // toplamını anlatmadığı için performans dönemine dokunmamalı.
      expect(DeepLinkRouter.gunlukGorunumIster(Uri.parse('sandik://asset/42')),
          isFalse);
      expect(DeepLinkRouter.gunlukGorunumIster(Uri.parse('sandik://bilinmeyen')),
          isFalse);
      expect(DeepLinkRouter.gunlukGorunumIster(null), isFalse);
    });

    test('yönlendiren servis isteği YAZIYOR', () {
      final kaynak = ekranKaynagiSync('lib/services/home_widget_service.dart');
      expect(
          kaynak.contains('DeepLinkRouter.gunlukGorunumIster(uri)') &&
              kaynak.contains(
                  'PortfolioPerformanceScreen.gunlukIstegi.value = true'),
          isTrue,
          reason: 'Dokunuş sekmeyi değiştiriyor ama dönemi değiştirmiyor — '
              'kullanıcı 1Y kartına düşer.');
    });

    test('ekran isteği TÜKETİYOR ve kapsamı sıfırlıyor', () {
      final kaynak =
          ekranKaynagiSync('lib/screens/portfolio_performance_screen.dart');
      // Tüketilmezse ekran her yeniden kurulduğunda (tema/dil değişimi)
      // eski dokunuş yeniden uygulanır ve kullanıcının seçtiği dönem
      // elinden alınır.
      expect(
          kaynak.contains('PortfolioPerformanceScreen.gunlukIstegi.value = null'),
          isTrue,
          reason: 'İstek tüketilmiyor.');
      // Dinleyici statik notifier'a bağlı: kaldırılmazsa tek dokunuş
      // birden çok kez işlenir.
      expect(kaynak.contains('gunlukIstegi.removeListener'), isTrue,
          reason: 'Dinleyici bırakılmıyor — dokunuş çoğalır.');
      // Sıfırlamalar İŞLEYİCİNİN İÇİNDE aranır: alan varsayılanları
      // (`bool _simulate = false;`) aynı metni taşıyor ve dosya geneli
      // arama, işleyici hiçbir şey yapmasa bile yeşil kalırdı.
      final govde = _govde(kaynak, 'void _gunlukIstegiGeldi()');
      for (final beklenen in [
        '_selectedPeriodIdx = 0',
        '_ozetSekmesi = false',
        '_simulate = false',
        "_view = ''",
        '_typeFilter = null',
      ]) {
        expect(govde.contains(beklenen), isTrue,
            reason: '$beklenen sıfırlanmıyor — kilit ekranından FARKLI '
                'bir toplam görünür.');
      }
    });

    test('dokunuş fiyatları TAZELİYOR', () {
      // Sıcak dönüşte (uygulama arkada) hiçbir yol fiyat çekmiyordu:
      // `didChangeAppLifecycleState` çekmez, derin bağlantı yalnızca
      // sekmeyi değiştiriyordu. Kullanıcı kilit ekranındakinden ESKİ bir
      // rakam görüyordu.
      final kaynak =
          ekranKaynagiSync('lib/screens/main_navigation_screen.dart');
      final govde = _govde(kaynak, 'void _sekmeIstegiGeldi()');
      expect(govde.contains('refreshPrices()'), isTrue,
          reason: 'Dış yüzey dokunuşu fiyatları tazelemiyor.');
    });
  });
}
