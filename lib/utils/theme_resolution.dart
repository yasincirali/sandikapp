import 'package:flutter/widgets.dart';

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
/// [ThemeMode.system] seçiliyse cihazın görünümüne düşülür; bu da
/// `MediaQuery.platformBrightnessOf` ile okunur — `Theme.of(context)` DEĞİL,
/// çünkü o zaten çözülmüş sonucu verir ve bu fonksiyon tam olarak o çözümü
/// yapıyor.
bool resolveThemeIsLight(BuildContext context, ThemeMode mode) =>
    resolveThemeIsLightWith(mode, MediaQuery.platformBrightnessOf(context));

/// [resolveThemeIsLight]'ın context istemeyen hâli — cihaz görünümü dışarıdan
/// verilir. Servis ve testlerde widget ağacı kurmadan kullanılır.
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
