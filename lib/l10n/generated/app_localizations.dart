import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_tr.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('tr')
  ];

  /// No description provided for @appName.
  ///
  /// In tr, this message translates to:
  /// **'sandık'**
  String get appName;

  /// No description provided for @loginTagline.
  ///
  /// In tr, this message translates to:
  /// **'Hazineni birlikte büyüt.'**
  String get loginTagline;

  /// No description provided for @email.
  ///
  /// In tr, this message translates to:
  /// **'E-posta'**
  String get email;

  /// No description provided for @emailInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli e-posta girin'**
  String get emailInvalid;

  /// No description provided for @password.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get password;

  /// No description provided for @passwordShow.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi göster'**
  String get passwordShow;

  /// No description provided for @passwordHide.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi gizle'**
  String get passwordHide;

  /// No description provided for @passwordMin6.
  ///
  /// In tr, this message translates to:
  /// **'En az 6 karakter'**
  String get passwordMin6;

  /// No description provided for @passwordRequired.
  ///
  /// In tr, this message translates to:
  /// **'Şifre gerekli'**
  String get passwordRequired;

  /// No description provided for @rememberMe.
  ///
  /// In tr, this message translates to:
  /// **'Beni hatırla'**
  String get rememberMe;

  /// No description provided for @forgotPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi unuttum'**
  String get forgotPassword;

  /// No description provided for @signIn.
  ///
  /// In tr, this message translates to:
  /// **'Giriş Yap'**
  String get signIn;

  /// No description provided for @noAccountRegister.
  ///
  /// In tr, this message translates to:
  /// **'Hesabınız yok mu? Kayıt olun'**
  String get noAccountRegister;

  /// No description provided for @register.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt Ol'**
  String get register;

  /// No description provided for @registerWelcome.
  ///
  /// In tr, this message translates to:
  /// **'Sandığına hoş geldin.'**
  String get registerWelcome;

  /// No description provided for @registerSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Birkaç adımda hesabını oluştur.'**
  String get registerSubtitle;

  /// No description provided for @fullName.
  ///
  /// In tr, this message translates to:
  /// **'Ad Soyad'**
  String get fullName;

  /// No description provided for @fullNameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad girin'**
  String get fullNameRequired;

  /// No description provided for @passwordRepeat.
  ///
  /// In tr, this message translates to:
  /// **'Şifre Tekrar'**
  String get passwordRepeat;

  /// No description provided for @passwordsMismatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler eşleşmiyor'**
  String get passwordsMismatch;

  /// No description provided for @haveAccountSignIn.
  ///
  /// In tr, this message translates to:
  /// **'Zaten hesabınız var mı? Giriş yapın'**
  String get haveAccountSignIn;

  /// No description provided for @exitAppTitle.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamadan çık'**
  String get exitAppTitle;

  /// No description provided for @exitAppMessage.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamadan çıkmak istediğine emin misin?'**
  String get exitAppMessage;

  /// No description provided for @exit.
  ///
  /// In tr, this message translates to:
  /// **'Çık'**
  String get exit;

  /// No description provided for @tabHome.
  ///
  /// In tr, this message translates to:
  /// **'Ana'**
  String get tabHome;

  /// No description provided for @tabPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'Portföy'**
  String get tabPortfolio;

  /// No description provided for @tabPerformance.
  ///
  /// In tr, this message translates to:
  /// **'Performans'**
  String get tabPerformance;

  /// No description provided for @tabProfile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get tabProfile;

  /// No description provided for @addAsset.
  ///
  /// In tr, this message translates to:
  /// **'Varlık ekle'**
  String get addAsset;

  /// No description provided for @lockTitle.
  ///
  /// In tr, this message translates to:
  /// **'sandık kilitli'**
  String get lockTitle;

  /// No description provided for @lockFailed.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulama yapılamadı. Tekrar dene.'**
  String get lockFailed;

  /// No description provided for @lockPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünü görmek için kimliğini doğrula.'**
  String get lockPrompt;

  /// No description provided for @lockVerifying.
  ///
  /// In tr, this message translates to:
  /// **'Doğrulanıyor…'**
  String get lockVerifying;

  /// No description provided for @unlock.
  ///
  /// In tr, this message translates to:
  /// **'Kilidi aç'**
  String get unlock;

  /// No description provided for @disclaimerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yasal Uyarı'**
  String get disclaimerTitle;

  /// No description provided for @disclaimerIntro.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı kullanmaya devam etmek için lütfen aşağıdaki yasal uyarıyı okuyun ve onaylayın.'**
  String get disclaimerIntro;

  /// No description provided for @disclaimerAcceptRow.
  ///
  /// In tr, this message translates to:
  /// **'Yukarıdaki yasal uyarıyı okudum ve kabul ediyorum.'**
  String get disclaimerAcceptRow;

  /// No description provided for @disclaimerMustAccept.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için yasal uyarıyı kabul etmelisin.'**
  String get disclaimerMustAccept;

  /// No description provided for @accept.
  ///
  /// In tr, this message translates to:
  /// **'Kabul Ediyorum'**
  String get accept;

  /// No description provided for @forgotTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şifremi Unuttum'**
  String get forgotTitle;

  /// No description provided for @forgotIntro.
  ///
  /// In tr, this message translates to:
  /// **'Kod göndereceğimiz e-posta adresini gir.'**
  String get forgotIntro;

  /// No description provided for @sendCode.
  ///
  /// In tr, this message translates to:
  /// **'Kod Gönder'**
  String get sendCode;

  /// No description provided for @codeSentTo.
  ///
  /// In tr, this message translates to:
  /// **'{email} adresine kod gönderdik. Kodu ve yeni şifreni gir.'**
  String codeSentTo(String email);

  /// No description provided for @code.
  ///
  /// In tr, this message translates to:
  /// **'Kod'**
  String get code;

  /// No description provided for @codeInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Kod eksik veya geçersiz'**
  String get codeInvalid;

  /// No description provided for @newPassword.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre'**
  String get newPassword;

  /// No description provided for @newPasswordRepeat.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Şifre Tekrar'**
  String get newPasswordRepeat;

  /// No description provided for @updatePassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifreyi Güncelle'**
  String get updatePassword;

  /// No description provided for @tryAnotherEmail.
  ///
  /// In tr, this message translates to:
  /// **'Farklı bir e-posta ile tekrar dene'**
  String get tryAnotherEmail;

  /// No description provided for @passwordUpdatedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şifre güncellendi'**
  String get passwordUpdatedTitle;

  /// No description provided for @passwordUpdatedMessage.
  ///
  /// In tr, this message translates to:
  /// **'Yeni şifrenle giriş yapabilirsin. Şimdi ana ekrana yönlendirileceksin.'**
  String get passwordUpdatedMessage;

  /// No description provided for @otpTitle.
  ///
  /// In tr, this message translates to:
  /// **'E-postanı doğrula'**
  String get otpTitle;

  /// No description provided for @otpExpired.
  ///
  /// In tr, this message translates to:
  /// **'Kodun süresi doldu. Yeni kod iste.'**
  String get otpExpired;

  /// No description provided for @otpEnterFull.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen 6 haneli kodu tam olarak girin.'**
  String get otpEnterFull;

  /// No description provided for @otpSentTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kod gönderildi'**
  String get otpSentTitle;

  /// No description provided for @otpSentMessage.
  ///
  /// In tr, this message translates to:
  /// **'Yeni 6 haneli kod e-postana gönderildi.'**
  String get otpSentMessage;

  /// No description provided for @otpExpiredShort.
  ///
  /// In tr, this message translates to:
  /// **'Kodun süresi doldu'**
  String get otpExpiredShort;

  /// No description provided for @otpExpiresIn.
  ///
  /// In tr, this message translates to:
  /// **'Kod {time} sonra geçersiz olur'**
  String otpExpiresIn(String time);

  /// No description provided for @sending.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor…'**
  String get sending;

  /// No description provided for @requestNewCode.
  ///
  /// In tr, this message translates to:
  /// **'Yeni Kod İste'**
  String get requestNewCode;

  /// No description provided for @verify.
  ///
  /// In tr, this message translates to:
  /// **'Doğrula'**
  String get verify;

  /// No description provided for @otpNotReceived.
  ///
  /// In tr, this message translates to:
  /// **'Kodu almadın mı? '**
  String get otpNotReceived;

  /// No description provided for @resend.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden gönder'**
  String get resend;

  /// No description provided for @resendIn.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden gönder ({seconds}s)'**
  String resendIn(int seconds);

  /// No description provided for @otpWrongEmail.
  ///
  /// In tr, this message translates to:
  /// **'Yanlış e-posta mı girdin? Geri dönüp tekrar deneyebilirsin.'**
  String get otpWrongEmail;

  /// No description provided for @settings.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settings;

  /// No description provided for @settingsAppearance.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get settingsAppearance;

  /// No description provided for @settingsNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get settingsNotifications;

  /// No description provided for @settingsAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap & Güvenlik'**
  String get settingsAccount;

  /// No description provided for @settingsHelp.
  ///
  /// In tr, this message translates to:
  /// **'Yardım & Yasal'**
  String get settingsHelp;

  /// No description provided for @settingsAppearanceSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tema, baz para birimi, dil, yatırımcı seviyesi'**
  String get settingsAppearanceSubtitle;

  /// No description provided for @settingsAccountSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kilit, verilerini indir, hesabını sil'**
  String get settingsAccountSubtitle;

  /// No description provided for @settingsHelpSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bize ulaş, tanıtım turu, gizlilik ve koşullar'**
  String get settingsHelpSubtitle;

  /// No description provided for @themeSystem.
  ///
  /// In tr, this message translates to:
  /// **'Sistem'**
  String get themeSystem;

  /// No description provided for @themeLight.
  ///
  /// In tr, this message translates to:
  /// **'Açık'**
  String get themeLight;

  /// No description provided for @themeDark.
  ///
  /// In tr, this message translates to:
  /// **'Koyu'**
  String get themeDark;

  /// No description provided for @language.
  ///
  /// In tr, this message translates to:
  /// **'Dil'**
  String get language;

  /// No description provided for @languageSystem.
  ///
  /// In tr, this message translates to:
  /// **'Sistem'**
  String get languageSystem;

  /// No description provided for @languageTurkish.
  ///
  /// In tr, this message translates to:
  /// **'Türkçe'**
  String get languageTurkish;

  /// No description provided for @languageEnglish.
  ///
  /// In tr, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// No description provided for @languageNote.
  ///
  /// In tr, this message translates to:
  /// **'İngilizce beta: bazı ekranlar henüz Türkçe.'**
  String get languageNote;

  /// No description provided for @investorLevel.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcı seviyesi'**
  String get investorLevel;

  /// No description provided for @investorLevelNote.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca Performans › Özet\'in kart kümesini değiştirir; hesaplar aynı kalır.'**
  String get investorLevelNote;

  /// No description provided for @levelBeginner.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get levelBeginner;

  /// No description provided for @levelIntermediate.
  ///
  /// In tr, this message translates to:
  /// **'Orta'**
  String get levelIntermediate;

  /// No description provided for @levelAdvanced.
  ///
  /// In tr, this message translates to:
  /// **'İleri'**
  String get levelAdvanced;

  /// No description provided for @levelBeginnerDesc.
  ///
  /// In tr, this message translates to:
  /// **'Sade özet: getiri, enflasyon ve katkı. Sağlık, XIRR ve yüzdelik yok.'**
  String get levelBeginnerDesc;

  /// No description provided for @levelIntermediateDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü görünüm: sağlık kartı, paranın getirisi (XIRR), yüzdelik dilim.'**
  String get levelIntermediateDesc;

  /// No description provided for @levelAdvancedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Orta + risk-ayarlı getiri, zamanlama etkisi ve toparlanma.'**
  String get levelAdvancedDesc;

  /// No description provided for @noAssetsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz varlık eklenmemiş'**
  String get noAssetsYet;

  /// No description provided for @noAssetsOfType.
  ///
  /// In tr, this message translates to:
  /// **'Bu türde varlık yok'**
  String get noAssetsOfType;

  /// No description provided for @noAssetsYetHint.
  ///
  /// In tr, this message translates to:
  /// **'İlk varlığını ekleyerek sandığını oluşturmaya başla.'**
  String get noAssetsYetHint;

  /// No description provided for @noAssetsOfTypeHint.
  ///
  /// In tr, this message translates to:
  /// **'Filtreyi değiştir ya da bu türden bir varlık ekle.'**
  String get noAssetsOfTypeHint;

  /// No description provided for @addFirstAsset.
  ///
  /// In tr, this message translates to:
  /// **'İlk Varlığını Ekle'**
  String get addFirstAsset;

  /// No description provided for @addAssetTitle.
  ///
  /// In tr, this message translates to:
  /// **'Varlık Ekle'**
  String get addAssetTitle;

  /// No description provided for @editAsset.
  ///
  /// In tr, this message translates to:
  /// **'Düzenle'**
  String get editAsset;

  /// No description provided for @add.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get add;

  /// No description provided for @update.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get update;

  /// No description provided for @save.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get save;

  /// No description provided for @assetType.
  ///
  /// In tr, this message translates to:
  /// **'Varlık Türü'**
  String get assetType;

  /// No description provided for @assetName.
  ///
  /// In tr, this message translates to:
  /// **'Varlık adı'**
  String get assetName;

  /// No description provided for @nameRequired.
  ///
  /// In tr, this message translates to:
  /// **'Ad zorunlu'**
  String get nameRequired;

  /// No description provided for @quantity.
  ///
  /// In tr, this message translates to:
  /// **'Miktar'**
  String get quantity;

  /// No description provided for @quantityInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli miktar'**
  String get quantityInvalid;

  /// No description provided for @purchasePrice.
  ///
  /// In tr, this message translates to:
  /// **'Alış Fiyatı'**
  String get purchasePrice;

  /// No description provided for @optional.
  ///
  /// In tr, this message translates to:
  /// **'· opsiyonel'**
  String get optional;

  /// No description provided for @auto.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik'**
  String get auto;

  /// No description provided for @invalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçersiz'**
  String get invalid;

  /// No description provided for @commission.
  ///
  /// In tr, this message translates to:
  /// **'Komisyon / Masraf'**
  String get commission;

  /// No description provided for @cannotBeNegative.
  ///
  /// In tr, this message translates to:
  /// **'Negatif olamaz'**
  String get cannotBeNegative;

  /// No description provided for @allTypes.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get allTypes;

  /// No description provided for @retry.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar Dene'**
  String get retry;

  /// No description provided for @cancel.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get cancel;

  /// No description provided for @delete.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get delete;

  /// No description provided for @sell.
  ///
  /// In tr, this message translates to:
  /// **'Sat'**
  String get sell;

  /// No description provided for @dividend.
  ///
  /// In tr, this message translates to:
  /// **'Temettü'**
  String get dividend;

  /// No description provided for @profile.
  ///
  /// In tr, this message translates to:
  /// **'Profil'**
  String get profile;

  /// No description provided for @portfolio.
  ///
  /// In tr, this message translates to:
  /// **'Portföy'**
  String get portfolio;

  /// No description provided for @myAssets.
  ///
  /// In tr, this message translates to:
  /// **'Varlıklarım'**
  String get myAssets;

  /// No description provided for @watchlist.
  ///
  /// In tr, this message translates to:
  /// **'Takip Listesi'**
  String get watchlist;

  /// No description provided for @priceUpdateFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatlar güncellenemedi — eski veriler gösteriliyor.'**
  String get priceUpdateFailed;

  /// No description provided for @otpSentPrefix.
  ///
  /// In tr, this message translates to:
  /// **'6 haneli kodu\n'**
  String get otpSentPrefix;

  /// No description provided for @otpSentSuffix.
  ///
  /// In tr, this message translates to:
  /// **'\nadresine gönderdik.'**
  String get otpSentSuffix;

  /// No description provided for @registerNameMissing.
  ///
  /// In tr, this message translates to:
  /// **'Ad soyad girin.'**
  String get registerNameMissing;

  /// No description provided for @registerEmailInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta girin.'**
  String get registerEmailInvalid;

  /// No description provided for @registerPasswordsMismatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler eşleşmiyor.'**
  String get registerPasswordsMismatch;

  /// No description provided for @termsMustAccept.
  ///
  /// In tr, this message translates to:
  /// **'Yasal koşulları kabul etmelisin.'**
  String get termsMustAccept;

  /// No description provided for @consentMustAccept.
  ///
  /// In tr, this message translates to:
  /// **'Yurt dışı veri aktarımına açık rıza vermelisin.'**
  String get consentMustAccept;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
