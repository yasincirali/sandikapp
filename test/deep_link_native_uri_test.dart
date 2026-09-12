import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/deep_link_router.dart';
import 'package:portfoy_takip/services/home_widget_service.dart';

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
}
