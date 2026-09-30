import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

/// Material bileşenlerinin Türkçe metinleri — **sen** hitabıyla.
///
/// ## Neden (2026-09-29 emülatör testi #19)
/// Material'ın kendi Türkçe çevirisi (`MaterialLocalizationTr`) **siz**
/// kipinde: tarih seçicide "Aralık seçin", "Yılı seçin", "Tarih Girin",
/// açılır kutuda "genişletmek için iki kez dokunun". Uygulamanın geri kalanı
/// "sen" der (CLAUDE.md i18n kuralı). Yerelleştirme YANLIŞ BAĞLANMIŞ
/// DEĞİLDİ — `GlobalMaterialLocalizations.delegate` doğru takılıydı, metin
/// Flutter'ın kendi çevirisiydi. Tek tek çağrı yerinde `helpText` vermek her
/// yeni seçicide unutulurdu; bu yüzden kök düzeltme delegate düzeyinde: yalnız
/// hitap taşıyan dizeler ezilir, gerisi (ay adları, biçimler) Flutter'ınki.
///
/// ## Bilinen, düzeltilemeyen kalıntı
/// Tarih ARALIĞI seçicinin ekran okuyucu etiketi Flutter'da sabit İngilizce
/// "to" ile kurulur (`'$helpText $startDateText to $endDateText'`,
/// `material/date_picker.dart`); yerelleştirme anahtarı yok. Görsel başlık
/// " – " yazar; "to" yalnızca TalkBack'te duyulur. Flutter yamalanmadan
/// düzeltilemez — raporlandı.
///
/// Sıra önemli: `Localizations` bir tür için İLK uyan delegate'i kullanır;
/// bu delegate `GlobalMaterialLocalizations.delegate`'ten ÖNCE listelenmeli.
class SenMaterialLocalizationsDelegate
    extends LocalizationsDelegate<MaterialLocalizations> {
  const SenMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'tr';

  @override
  Future<MaterialLocalizations> load(Locale locale) {
    // Önce Flutter'ın kendi yüklemesi: tarih sembollerini (`intl`) o yükler;
    // biçimleri aynı kaynaktan kurmak için ona yaslanıyoruz. Flutter'ın
    // yüklemesi `SynchronousFuture` döner; `then` de eşzamanlı kalır, ilk
    // karede yerelleştirme eksik olmaz.
    return GlobalMaterialLocalizations.delegate
        .load(locale)
        .then<MaterialLocalizations>((_) {
      const ad = 'tr';
      return SenMaterialLocalizationTr(
        fullYearFormat: intl.DateFormat.y(ad),
        compactDateFormat: intl.DateFormat.yMd(ad),
        shortDateFormat: intl.DateFormat.yMMMd(ad),
        mediumDateFormat: intl.DateFormat.MMMEd(ad),
        longDateFormat: intl.DateFormat.yMMMMEEEEd(ad),
        yearMonthFormat: intl.DateFormat.yMMMM(ad),
        shortMonthDayFormat: intl.DateFormat.MMMd(ad),
        decimalFormat: intl.NumberFormat.decimalPattern(ad),
        twoDigitZeroPaddedFormat: intl.NumberFormat('00', ad),
      );
    });
  }

  @override
  bool shouldReload(SenMaterialLocalizationsDelegate old) => false;
}

/// `MaterialLocalizationTr` + sen hitabı. Yalnız hitap taşıyan dizeler.
class SenMaterialLocalizationTr extends MaterialLocalizationTr {
  const SenMaterialLocalizationTr({
    required super.fullYearFormat,
    required super.compactDateFormat,
    required super.shortDateFormat,
    required super.mediumDateFormat,
    required super.longDateFormat,
    required super.yearMonthFormat,
    required super.shortMonthDayFormat,
    required super.decimalFormat,
    required super.twoDigitZeroPaddedFormat,
  });

  @override
  String get dateInputLabel => 'Tarih gir';
  @override
  String get datePickerHelpText => 'Tarih seç';
  @override
  String get dateRangePickerHelpText => 'Aralık seç';
  @override
  String get selectYearSemanticsLabel => 'Yılı seç';
  @override
  String get invalidTimeLabel => 'Geçerli bir saat gir';
  @override
  String get timePickerDialHelpText => 'Saat seç';
  @override
  String get timePickerHourModeAnnouncement => 'Saati seç';
  @override
  String get timePickerInputHelpText => 'Saat gir';
  @override
  String get timePickerMinuteModeAnnouncement => 'Dakikayı seç';
  @override
  String get expansionTileCollapsedHint => 'genişletmek için iki kez dokun';
  @override
  String get expansionTileCollapsedTapHint =>
      'Daha fazla ayrıntı için genişlet';
  @override
  String get expansionTileExpandedHint => 'daraltmak için iki kez dokun';
}
