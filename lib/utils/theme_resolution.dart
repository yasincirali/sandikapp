// `ThemeMode` material katmanında tanımlı; `widgets.dart` yetmez.
import 'package:flutter/material.dart';

/// Kullanıcının tema tercihini SOMUT bir aydınlık/karanlık kararına çevirir.
///
/// ## Neden gerekli
/// Uygulama dışı yüzeyler — iOS kilit ekranı uzantısı ve ana ekran widget'ı —
/// uygulamanın `ThemeMode` tercihini **göremez**. Görebildikleri tek şey
/// cihazın görünümüdür: iOS'ta `@Environment(\.colorScheme)`, Android'de
/// `values` ↔ `values-night` kaynak seçimi.
///
/// Bu yüzden ikisi de bugüne kadar yanlış şeyi izliyordu:
///   · iOS kilit ekranı hiç sormuyordu, palet sabit KOYUYDU;
///   · Android widget'ı **sistemin** karanlık modunu izliyordu.
///
/// Kullanıcı uygulamayı "Açık" yapıp cihazı koyu bıraktığında ikisi de koyu
/// kalıyordu. İstenen uygulamanın temasıdır — ve "Sistem"in ne anlama
/// geldiğini yalnızca Dart tarafı bilir. Karar burada verilir, native tarafa
/// çözülmüş bir bool gider.
///
/// [ThemeMode.system] seçiliyse cihazın görünümüne düşülür.
///
/// ## Neden `MediaQuery` değil
/// Bu fonksiyonun iki çağrı yeri de build DIŞINDA: bir `ref.listen` geri
/// çağrısı (`main.dart`) ve bir `onTap` (`settings_screen.dart`).
/// `MediaQuery.platformBrightnessOf` bir InheritedWidget bağımlılığı KAYDEDER
/// ve build ağacının dışında çağrılması kırılgandır — element o sırada
/// sökülmüş olabilir. Platform doğrudan okunur; değer aynıdır, tek fark
/// testlerdeki `MediaQuery` geçersiz kılmalarını görmemesidir. Saf karar
/// tablosu [resolveThemeIsLightWith] ile test edilir.
///
/// `Theme.of(context)` de doğru araç DEĞİLDİR: o zaten çözülmüş sonucu verir
/// ve bu fonksiyon tam olarak o çözümü yapıyor.
bool resolveThemeIsLightNow(ThemeMode mode) => resolveThemeIsLightWith(
      mode,
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
    );

/// [resolveThemeIsLightNow]'ın cihaz görünümü dışarıdan verilen hâli.
/// Testlerde ve saf karar tablosunu doğrularken kullanılır.
bool resolveThemeIsLightWith(ThemeMode mode, Brightness platformBrightness) {
  switch (mode) {
    case ThemeMode.light:
      return true;
    case ThemeMode.dark:
      return false;
    case ThemeMode.system:
      return platformBrightness == Brightness.light;
  }
}
