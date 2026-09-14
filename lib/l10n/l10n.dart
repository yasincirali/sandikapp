import 'package:flutter/widgets.dart';

import 'generated/app_localizations.dart';
import 'generated/app_localizations_tr.dart';

export 'generated/app_localizations.dart';

/// `context.l10n` — arayüz metinlerinin tek kapısı (3.20).
///
/// Delegate yoksa (delegate'siz `MaterialApp` kuran widget testleri, erken
/// bir overlay) TÜRKÇE sınıfa düşer: uygulamanın ana dili Türkçe, "metin
/// bulunamadı" diye çökmek yerine Türkçe göstermek doğru geri dönüş.
///
/// Türkçe şablon, İngilizce çeviri `app_en.arb`'da. İngilizce henüz BETA:
/// yalnızca giriş/kayıt, gezinme, kilit, yasal uyarı, Ayarlar hub'ı ve
/// Görünüm, ana ekran/portföy boş durumları ve varlık ekleme formu
/// çevrildi; kalan ekranlar Türkçe kalır (`docs/YOL_HARITASI_ILERLEME.md`
/// 3.20 satırı). Yeni metin: önce `app_tr.arb` + `app_en.arb`, sonra
/// `flutter gen-l10n`, sonra `context.l10n.anahtar`.
extension L10nX on BuildContext {
  AppLocalizations get l10n =>
      AppLocalizations.of(this) ?? AppLocalizationsTr();
}
