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

  /// No description provided for @lockNoDeviceCredential.
  ///
  /// In tr, this message translates to:
  /// **'Cihazında ekran kilidi (Face ID, parmak izi ya da şifre) tanımlı değil. Doğrulama yapılamıyor.'**
  String get lockNoDeviceCredential;

  /// No description provided for @lockDisableAndContinue.
  ///
  /// In tr, this message translates to:
  /// **'Kilidi kapat ve devam et'**
  String get lockDisableAndContinue;

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
  /// **'İngilizce beta: yasal metinler, tanıtım turu ve altın/fon alt kategori adları Türkçe kalır.'**
  String get languageNote;

  /// No description provided for @investorLevel.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcı seviyesi'**
  String get investorLevel;

  /// No description provided for @investorLevelNote.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca hangi metriklerin GÖSTERİLECEĞİNİ değiştirir; hesaplar ve verilerin aynı kalır.'**
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
  /// **'Sade görünüm: teknik sinyaller, yüzdelik dilim, sağlık ve XIRR kartları gizlenir.'**
  String get levelBeginnerDesc;

  /// No description provided for @levelIntermediateDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü görünüm: teknik sinyaller, yüzdelik dilim, sağlık kartı ve paranın getirisi (XIRR).'**
  String get levelIntermediateDesc;

  /// No description provided for @levelAdvancedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Orta + risk-ayarlı getiri, zamanlama etkisi ve toparlanma (Özet › 1Y).'**
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

  /// No description provided for @scopeCategory.
  ///
  /// In tr, this message translates to:
  /// **'Kategori: {label}'**
  String scopeCategory(String label);

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

  /// No description provided for @refreshPrices.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatları yenile'**
  String get refreshPrices;

  /// No description provided for @assetAllocation.
  ///
  /// In tr, this message translates to:
  /// **'VARLIK DAĞILIMI'**
  String get assetAllocation;

  /// No description provided for @portfolioActivity.
  ///
  /// In tr, this message translates to:
  /// **'PORTFÖY HAREKETLERİ'**
  String get portfolioActivity;

  /// No description provided for @seeAllTransactions.
  ///
  /// In tr, this message translates to:
  /// **'Tüm hareketleri gör'**
  String get seeAllTransactions;

  /// No description provided for @seeAllCount.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Gör ({count})'**
  String seeAllCount(int count);

  /// No description provided for @signalDeleteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim silinemedi. Bağlantını kontrol et.'**
  String get signalDeleteFailed;

  /// No description provided for @permanentDelete.
  ///
  /// In tr, this message translates to:
  /// **'Kalıcı sil'**
  String get permanentDelete;

  /// No description provided for @signalDeleteChoice.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişte {past}, aktif {active} bildirim var. Ne silinsin?'**
  String signalDeleteChoice(int past, int active);

  /// No description provided for @cancelShort.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç'**
  String get cancelShort;

  /// No description provided for @onlyHistory.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca geçmiş'**
  String get onlyHistory;

  /// No description provided for @clearAllSignals.
  ///
  /// In tr, this message translates to:
  /// **'Tüm sinyalleri temizle'**
  String get clearAllSignals;

  /// No description provided for @clearAllLower.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü temizle'**
  String get clearAllLower;

  /// No description provided for @clearAllSignalsBody.
  ///
  /// In tr, this message translates to:
  /// **'{count} bildirim geçmişe taşınacak. Kalıcı silmek için geçmişteki \"Geçmişi Sil\" düğmesini kullan.'**
  String clearAllSignalsBody(int count);

  /// No description provided for @clearVerb.
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clearVerb;

  /// No description provided for @clearAllUpper.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Temizle'**
  String get clearAllUpper;

  /// No description provided for @noActiveSignals.
  ///
  /// In tr, this message translates to:
  /// **'Şu an aktif sinyal yok'**
  String get noActiveSignals;

  /// No description provided for @historyUpper.
  ///
  /// In tr, this message translates to:
  /// **'GEÇMİŞ'**
  String get historyUpper;

  /// No description provided for @deleteHistoryCount.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişteki {count} bildirimi kalıcı olarak sil'**
  String deleteHistoryCount(int count);

  /// No description provided for @deleteHistoryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişi sil'**
  String get deleteHistoryTitle;

  /// No description provided for @deleteHistoryBody.
  ///
  /// In tr, this message translates to:
  /// **'{count} bildirim KALICI olarak silinecek. Geri alınamaz.'**
  String deleteHistoryBody(int count);

  /// No description provided for @permanentDeleteUpper.
  ///
  /// In tr, this message translates to:
  /// **'Kalıcı Sil'**
  String get permanentDeleteUpper;

  /// No description provided for @deleteHistoryButton.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişi Sil'**
  String get deleteHistoryButton;

  /// No description provided for @signalNeutral.
  ///
  /// In tr, this message translates to:
  /// **'NÖTR'**
  String get signalNeutral;

  /// No description provided for @signalDeletedAt.
  ///
  /// In tr, this message translates to:
  /// **'{date} · silindi'**
  String signalDeletedAt(String date);

  /// No description provided for @signalConfidence.
  ///
  /// In tr, this message translates to:
  /// **'{count} gösterge · {pct} güven'**
  String signalConfidence(int count, String pct);

  /// No description provided for @showBalance.
  ///
  /// In tr, this message translates to:
  /// **'Bakiyeyi göster'**
  String get showBalance;

  /// No description provided for @hideBalance.
  ///
  /// In tr, this message translates to:
  /// **'Bakiyeyi gizle'**
  String get hideBalance;

  /// No description provided for @sortCriterion.
  ///
  /// In tr, this message translates to:
  /// **'SIRALAMA KRİTERİ'**
  String get sortCriterion;

  /// No description provided for @tabSemanticsCount.
  ///
  /// In tr, this message translates to:
  /// **'{label}, {count} varlık'**
  String tabSemanticsCount(String label, int count);

  /// No description provided for @noChange.
  ///
  /// In tr, this message translates to:
  /// **'Değişim yok'**
  String get noChange;

  /// No description provided for @buyAction.
  ///
  /// In tr, this message translates to:
  /// **'Al'**
  String get buyAction;

  /// No description provided for @sellAction.
  ///
  /// In tr, this message translates to:
  /// **'Sat'**
  String get sellAction;

  /// No description provided for @deleteAction.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get deleteAction;

  /// No description provided for @activeAlertsCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} aktif fiyat alarmı'**
  String activeAlertsCount(int count);

  /// No description provided for @lastMonth.
  ///
  /// In tr, this message translates to:
  /// **'Son 1 ay'**
  String get lastMonth;

  /// No description provided for @firstPurchase.
  ///
  /// In tr, this message translates to:
  /// **'İlk Alış'**
  String get firstPurchase;

  /// No description provided for @avgCost.
  ///
  /// In tr, this message translates to:
  /// **'Ort. Maliyet'**
  String get avgCost;

  /// No description provided for @totalCost.
  ///
  /// In tr, this message translates to:
  /// **'Toplam Maliyet'**
  String get totalCost;

  /// No description provided for @currentValue.
  ///
  /// In tr, this message translates to:
  /// **'Güncel Tutar'**
  String get currentValue;

  /// No description provided for @lotSummary.
  ///
  /// In tr, this message translates to:
  /// **'{buys} alım · {sells} çıkarma'**
  String lotSummary(int buys, int sells);

  /// No description provided for @sortMarketValue.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa Değeri'**
  String get sortMarketValue;

  /// No description provided for @sortHighToLow.
  ///
  /// In tr, this message translates to:
  /// **'Büyükten Küçüğe'**
  String get sortHighToLow;

  /// No description provided for @sortLowToHigh.
  ///
  /// In tr, this message translates to:
  /// **'Küçükten Büyüğe'**
  String get sortLowToHigh;

  /// No description provided for @sortGainTry.
  ///
  /// In tr, this message translates to:
  /// **'Kazanç (TL)'**
  String get sortGainTry;

  /// No description provided for @sortGainPct.
  ///
  /// In tr, this message translates to:
  /// **'Kazanç (%)'**
  String get sortGainPct;

  /// No description provided for @sortHighestFirst.
  ///
  /// In tr, this message translates to:
  /// **'En Yüksek Önce'**
  String get sortHighestFirst;

  /// No description provided for @sortLowestFirst.
  ///
  /// In tr, this message translates to:
  /// **'En Düşük Önce'**
  String get sortLowestFirst;

  /// No description provided for @assetFullName.
  ///
  /// In tr, this message translates to:
  /// **'Tam Adı'**
  String get assetFullName;

  /// No description provided for @assetTypeStock.
  ///
  /// In tr, this message translates to:
  /// **'Hisse'**
  String get assetTypeStock;

  /// No description provided for @assetTypeFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon'**
  String get assetTypeFund;

  /// No description provided for @assetTypeFx.
  ///
  /// In tr, this message translates to:
  /// **'Döviz'**
  String get assetTypeFx;

  /// No description provided for @assetTypeGold.
  ///
  /// In tr, this message translates to:
  /// **'Altın'**
  String get assetTypeGold;

  /// No description provided for @assetTypeCommodity.
  ///
  /// In tr, this message translates to:
  /// **'Emtia'**
  String get assetTypeCommodity;

  /// No description provided for @assetTypeOther.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get assetTypeOther;

  /// No description provided for @tickerHintStock.
  ///
  /// In tr, this message translates to:
  /// **'Örn: THYAO.IS, GARAN.IS  (Borsa İstanbul için .IS ekleyin)'**
  String get tickerHintStock;

  /// No description provided for @tickerHintFund.
  ///
  /// In tr, this message translates to:
  /// **'Yahoo Finance kodu yoksa boş bırakın, fiyatı manuel girin'**
  String get tickerHintFund;

  /// No description provided for @tickerHintFx.
  ///
  /// In tr, this message translates to:
  /// **'Örn: USDTRY=X, EURTRY=X, GBPTRY=X'**
  String get tickerHintFx;

  /// No description provided for @tickerHintGold.
  ///
  /// In tr, this message translates to:
  /// **'Örn: XAUTRY=X (gram altın TL) veya GC=F (ons, USD)'**
  String get tickerHintGold;

  /// No description provided for @tickerHintCommodity.
  ///
  /// In tr, this message translates to:
  /// **'Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)'**
  String get tickerHintCommodity;

  /// No description provided for @tickerHintOther.
  ///
  /// In tr, this message translates to:
  /// **'Yahoo Finance sembolü veya boş bırakın'**
  String get tickerHintOther;

  /// No description provided for @assetTypeSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{type} türü'**
  String assetTypeSemantics(String type);

  /// No description provided for @total.
  ///
  /// In tr, this message translates to:
  /// **'toplam'**
  String get total;

  /// No description provided for @bulkAdd.
  ///
  /// In tr, this message translates to:
  /// **'Toplu ekle'**
  String get bulkAdd;

  /// No description provided for @quickEntryVoice.
  ///
  /// In tr, this message translates to:
  /// **'Sesli / Hızlı giriş'**
  String get quickEntryVoice;

  /// No description provided for @orNotInList.
  ///
  /// In tr, this message translates to:
  /// **'veya listede yok'**
  String get orNotInList;

  /// No description provided for @symbolHint.
  ///
  /// In tr, this message translates to:
  /// **'Sembol yaz (örn: AAPL, THYAO.IS)'**
  String get symbolHint;

  /// No description provided for @companyNameHint.
  ///
  /// In tr, this message translates to:
  /// **'Şirket adı (opsiyonel — semboldan otomatik çekilir)'**
  String get companyNameHint;

  /// No description provided for @goldSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{kind} altın'**
  String goldSemantics(String kind);

  /// No description provided for @commissionNote.
  ///
  /// In tr, this message translates to:
  /// **'Alım-satım komisyonu maliyete eklenir — kâr/zarar gerçek rakamı gösterir.'**
  String get commissionNote;

  /// No description provided for @costPreviewHint.
  ///
  /// In tr, this message translates to:
  /// **'Miktar girince toplam maliyet burada görünecek.'**
  String get costPreviewHint;

  /// No description provided for @totalCostUpper.
  ///
  /// In tr, this message translates to:
  /// **'TOPLAM MALİYET'**
  String get totalCostUpper;

  /// No description provided for @transactionDate.
  ///
  /// In tr, this message translates to:
  /// **'İşlem tarihi'**
  String get transactionDate;

  /// No description provided for @addNote.
  ///
  /// In tr, this message translates to:
  /// **'Not ekle'**
  String get addNote;

  /// No description provided for @notesHint.
  ///
  /// In tr, this message translates to:
  /// **'Notlarınız...'**
  String get notesHint;

  /// No description provided for @quantitySemantics.
  ///
  /// In tr, this message translates to:
  /// **'Miktar {value}'**
  String quantitySemantics(String value);

  /// No description provided for @quickEntryTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı Giriş'**
  String get quickEntryTitle;

  /// No description provided for @quickEntryHelp.
  ///
  /// In tr, this message translates to:
  /// **'Her satıra bir varlık yazın. Fiyat opsiyonel — boş bırakırsanız güncel fiyat otomatik çekilir.\nÖrn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet'**
  String get quickEntryHelp;

  /// No description provided for @quickEntryPlaceholder.
  ///
  /// In tr, this message translates to:
  /// **'100 dolar\n10 gram altın 4500 lira\nGARAN 500 adet 105 lira'**
  String get quickEntryPlaceholder;

  /// No description provided for @saveNAssets.
  ///
  /// In tr, this message translates to:
  /// **'{count} varlığı kaydet'**
  String saveNAssets(int count);

  /// No description provided for @fillTheForm.
  ///
  /// In tr, this message translates to:
  /// **'Formu doldur'**
  String get fillTheForm;

  /// No description provided for @bistStocks.
  ///
  /// In tr, this message translates to:
  /// **'BIST Hisseleri'**
  String get bistStocks;

  /// No description provided for @tefasFunds.
  ///
  /// In tr, this message translates to:
  /// **'TEFAS Fonları'**
  String get tefasFunds;

  /// No description provided for @fundsLoading.
  ///
  /// In tr, this message translates to:
  /// **'Fonlar yükleniyor...'**
  String get fundsLoading;

  /// No description provided for @pleaseWait.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bekleyin'**
  String get pleaseWait;

  /// No description provided for @fundsLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fonlar yüklenemedi'**
  String get fundsLoadFailed;

  /// No description provided for @searchEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Ara...'**
  String get searchEllipsis;

  /// No description provided for @clearSearch.
  ///
  /// In tr, this message translates to:
  /// **'Aramayı temizle'**
  String get clearSearch;

  /// No description provided for @pickStockPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir hisse seçin'**
  String get pickStockPrompt;

  /// No description provided for @pickStock.
  ///
  /// In tr, this message translates to:
  /// **'Hisse seç'**
  String get pickStock;

  /// No description provided for @pickStockTap.
  ///
  /// In tr, this message translates to:
  /// **'Hisse seçmek için dokunun...'**
  String get pickStockTap;

  /// No description provided for @pickFundPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Lütfen bir fon seçin'**
  String get pickFundPrompt;

  /// No description provided for @pickFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon seç'**
  String get pickFund;

  /// No description provided for @pickFundTap.
  ///
  /// In tr, this message translates to:
  /// **'Fon seçmek için dokunun...'**
  String get pickFundTap;

  /// No description provided for @noResults.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç bulunamadı'**
  String get noResults;

  /// No description provided for @priceNotAvailable.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat bilgisi yok'**
  String get priceNotAvailable;

  /// No description provided for @assetFallbackName.
  ///
  /// In tr, this message translates to:
  /// **'Varlık'**
  String get assetFallbackName;

  /// No description provided for @commodityHint.
  ///
  /// In tr, this message translates to:
  /// **'Örn: Petrol (Brent)'**
  String get commodityHint;

  /// No description provided for @identityStock.
  ///
  /// In tr, this message translates to:
  /// **'Hisse'**
  String get identityStock;

  /// No description provided for @identityFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon'**
  String get identityFund;

  /// No description provided for @identityGoldKind.
  ///
  /// In tr, this message translates to:
  /// **'Altın Türü'**
  String get identityGoldKind;

  /// No description provided for @identityCurrency.
  ///
  /// In tr, this message translates to:
  /// **'Para Birimi'**
  String get identityCurrency;

  /// No description provided for @identityCommodity.
  ///
  /// In tr, this message translates to:
  /// **'Emtia'**
  String get identityCommodity;

  /// No description provided for @noResultsFor.
  ///
  /// In tr, this message translates to:
  /// **'\"{q}\" bulunamadı'**
  String noResultsFor(String q);

  /// No description provided for @periodDaily.
  ///
  /// In tr, this message translates to:
  /// **'GÜNLÜK'**
  String get periodDaily;

  /// No description provided for @period1W.
  ///
  /// In tr, this message translates to:
  /// **'1H'**
  String get period1W;

  /// No description provided for @period1M.
  ///
  /// In tr, this message translates to:
  /// **'1A'**
  String get period1M;

  /// No description provided for @period6M.
  ///
  /// In tr, this message translates to:
  /// **'6A'**
  String get period6M;

  /// No description provided for @period1Y.
  ///
  /// In tr, this message translates to:
  /// **'1Y'**
  String get period1Y;

  /// No description provided for @assetPerformanceSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Performans: {name}'**
  String assetPerformanceSemantics(String name);

  /// No description provided for @setPriceAlert.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmı kur'**
  String get setPriceAlert;

  /// No description provided for @priceHistoryFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlığın fiyat geçmişi şu an çekilemedi. Bağlantını kontrol edip tekrar dene.'**
  String get priceHistoryFailed;

  /// No description provided for @totalQuantityUpper.
  ///
  /// In tr, this message translates to:
  /// **'TOPLAM MİKTAR'**
  String get totalQuantityUpper;

  /// No description provided for @otherTab.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get otherTab;

  /// No description provided for @periodChangeUpper.
  ///
  /// In tr, this message translates to:
  /// **'{period} DEĞİŞİM'**
  String periodChangeUpper(String period);

  /// No description provided for @buyPerUnit.
  ///
  /// In tr, this message translates to:
  /// **'ALIŞ / {unit}'**
  String buyPerUnit(String unit);

  /// No description provided for @todayPerUnit.
  ///
  /// In tr, this message translates to:
  /// **'BUGÜN / {unit}'**
  String todayPerUnit(String unit);

  /// No description provided for @noResultsShort.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç yok.'**
  String get noResultsShort;

  /// No description provided for @compare.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştır'**
  String get compare;

  /// No description provided for @clearShort.
  ///
  /// In tr, this message translates to:
  /// **'Temizle'**
  String get clearShort;

  /// No description provided for @searchTickerOrName.
  ///
  /// In tr, this message translates to:
  /// **'Ticker veya isim ara…'**
  String get searchTickerOrName;

  /// No description provided for @myPortfolioTab.
  ///
  /// In tr, this message translates to:
  /// **'Portföyüm'**
  String get myPortfolioTab;

  /// No description provided for @deleteAccountTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabını silmek üzeresin'**
  String get deleteAccountTitle;

  /// No description provided for @deleteAccountBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem GERİ ALINAMAZ.\n\nTüm portföy kayıtların, performans geçmişin ve ortaklık bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\nDevam etmek istiyor musun?'**
  String get deleteAccountBody;

  /// No description provided for @continueAction.
  ///
  /// In tr, this message translates to:
  /// **'Devam et'**
  String get continueAction;

  /// No description provided for @verifyIdentityTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kimliğini doğrula'**
  String get verifyIdentityTitle;

  /// No description provided for @verifyIdentityBody.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın Apple/Google ile açılmış. Silmeden önce aynı hesapla bir kez daha giriş yapman istenecek.'**
  String get verifyIdentityBody;

  /// No description provided for @confirmWithPassword.
  ///
  /// In tr, this message translates to:
  /// **'Şifrenle onayla'**
  String get confirmWithPassword;

  /// No description provided for @confirmWithPasswordBody.
  ///
  /// In tr, this message translates to:
  /// **'Güvenliğin için şifrenle onay vermen gerekiyor.'**
  String get confirmWithPasswordBody;

  /// No description provided for @deleteAccountUpper.
  ///
  /// In tr, this message translates to:
  /// **'HESABI SİL'**
  String get deleteAccountUpper;

  /// No description provided for @accountDeletedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın silindi'**
  String get accountDeletedTitle;

  /// No description provided for @accountDeletedBody.
  ///
  /// In tr, this message translates to:
  /// **'Görüşmek üzere.'**
  String get accountDeletedBody;

  /// No description provided for @investmentDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Yatırım Tavsiyesi Reddi'**
  String get investmentDisclaimer;

  /// No description provided for @close.
  ///
  /// In tr, this message translates to:
  /// **'Kapat'**
  String get close;

  /// No description provided for @feedbackTitle.
  ///
  /// In tr, this message translates to:
  /// **'Şikayet & Tavsiye'**
  String get feedbackTitle;

  /// No description provided for @feedbackHint.
  ///
  /// In tr, this message translates to:
  /// **'Mesajınızı yazın…'**
  String get feedbackHint;

  /// No description provided for @send.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get send;

  /// No description provided for @deletingAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın siliniyor…'**
  String get deletingAccount;

  /// No description provided for @deletingAccountBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu işlem birkaç saniye sürebilir. Uygulamayı kapatma.'**
  String get deletingAccountBody;

  /// No description provided for @diagnosticsUpper.
  ///
  /// In tr, this message translates to:
  /// **'TANILAMA'**
  String get diagnosticsUpper;

  /// No description provided for @pushDiagnostics.
  ///
  /// In tr, this message translates to:
  /// **'Push Teşhisi'**
  String get pushDiagnostics;

  /// No description provided for @pushDiagnosticsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bildirim zincirinin neresi kopuk; cihaz APNs/FCM token durumu'**
  String get pushDiagnosticsSubtitle;

  /// No description provided for @notificationsUpper.
  ///
  /// In tr, this message translates to:
  /// **'BİLDİRİMLER'**
  String get notificationsUpper;

  /// No description provided for @signalNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyal bildirimleri'**
  String get signalNotifications;

  /// No description provided for @signalNotificationsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'AL/SAT göstergesi tetiklendiğinde bildirim al'**
  String get signalNotificationsSubtitle;

  /// No description provided for @signalSettings.
  ///
  /// In tr, this message translates to:
  /// **'Sinyal ayarları'**
  String get signalSettings;

  /// No description provided for @signalSettingsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Her varlık türü için gösterge seçimi + Premium'**
  String get signalSettingsSubtitle;

  /// No description provided for @priceAlerts.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmları'**
  String get priceAlerts;

  /// No description provided for @partnerInviteNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık daveti bildirimleri'**
  String get partnerInviteNotifications;

  /// No description provided for @partnerInviteNotificationsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni ortaklık isteği geldiğinde bildirim al'**
  String get partnerInviteNotificationsSubtitle;

  /// No description provided for @liveActivitiesUpper.
  ///
  /// In tr, this message translates to:
  /// **'CANLI ETKİNLİKLER'**
  String get liveActivitiesUpper;

  /// No description provided for @biometricLock.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kilit'**
  String get biometricLock;

  /// No description provided for @downloadMyData.
  ///
  /// In tr, this message translates to:
  /// **'Verilerimi İndir'**
  String get downloadMyData;

  /// No description provided for @downloadMyDataSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm verilerini JSON dosyası olarak al (KVKK Madde 11)'**
  String get downloadMyDataSubtitle;

  /// No description provided for @deleteMyAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabımı Sil'**
  String get deleteMyAccount;

  /// No description provided for @deleteMyAccountSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Tüm verilerin kalıcı olarak silinir'**
  String get deleteMyAccountSubtitle;

  /// No description provided for @supportUpper.
  ///
  /// In tr, this message translates to:
  /// **'DESTEK'**
  String get supportUpper;

  /// No description provided for @contactUs.
  ///
  /// In tr, this message translates to:
  /// **'Bize Ulaş'**
  String get contactUs;

  /// No description provided for @replayTour.
  ///
  /// In tr, this message translates to:
  /// **'Tanıtım turunu yeniden izle'**
  String get replayTour;

  /// No description provided for @replayTourSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Ekranların ne işe yaradığını hatırla'**
  String get replayTourSubtitle;

  /// No description provided for @feedbackSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Görüşünü bize ilet'**
  String get feedbackSubtitle;

  /// No description provided for @legalUpper.
  ///
  /// In tr, this message translates to:
  /// **'YASAL'**
  String get legalUpper;

  /// No description provided for @privacyPolicy.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik Politikası'**
  String get privacyPolicy;

  /// No description provided for @privacyPolicySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Verilerin nasıl işleniyor'**
  String get privacyPolicySubtitle;

  /// No description provided for @termsOfUse.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları'**
  String get termsOfUse;

  /// No description provided for @termsOfUseSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Hizmet sözleşmesi'**
  String get termsOfUseSubtitle;

  /// No description provided for @kvkkNotice.
  ///
  /// In tr, this message translates to:
  /// **'KVKK Aydınlatma Metni'**
  String get kvkkNotice;

  /// No description provided for @kvkkNoticeSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kişisel veri işleme aydınlatması'**
  String get kvkkNoticeSubtitle;

  /// No description provided for @disclaimerSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Onayladığın yasal uyarı metnini görüntüle'**
  String get disclaimerSubtitle;

  /// No description provided for @themeSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} tema'**
  String themeSemantics(String name);

  /// No description provided for @baseCurrencySemantics.
  ///
  /// In tr, this message translates to:
  /// **'Baz para birimi {name}'**
  String baseCurrencySemantics(String name);

  /// No description provided for @levelSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} seviye'**
  String levelSemantics(String name);

  /// No description provided for @showAllDay.
  ///
  /// In tr, this message translates to:
  /// **'Gün boyu göster'**
  String get showAllDay;

  /// No description provided for @showAllDaySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken yalnızca seçtiğin saat aralığında görünür.'**
  String get showAllDaySubtitle;

  /// No description provided for @displayWindow.
  ///
  /// In tr, this message translates to:
  /// **'Gösterim aralığı'**
  String get displayWindow;

  /// No description provided for @startTime.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get startTime;

  /// No description provided for @endTime.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş'**
  String get endTime;

  /// No description provided for @showOnWeekend.
  ///
  /// In tr, this message translates to:
  /// **'Hafta sonu da göster'**
  String get showOnWeekend;

  /// No description provided for @showOnWeekendSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Hafta sonu BIST kapalıdır; banner son kapanışı \"Piyasa kapalı\" etiketiyle gösterir.'**
  String get showOnWeekendSubtitle;

  /// No description provided for @showAmounts.
  ///
  /// In tr, this message translates to:
  /// **'Tutarları göster'**
  String get showAmounts;

  /// No description provided for @showAmountsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Kapalıyken yalnızca günlük yüzde ve grafik görünür. Kilit ekranı telefonunuz açılmadan görülebildiği için varsayılan olarak kapalıdır.'**
  String get showAmountsSubtitle;

  /// No description provided for @partnerActivityNotifications.
  ///
  /// In tr, this message translates to:
  /// **'Ortak hareketi bildirimleri'**
  String get partnerActivityNotifications;

  /// No description provided for @partnerActivityNotificationsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Ortağın portföyüne ekleme yaptığında günlük özette an'**
  String get partnerActivityNotificationsSubtitle;

  /// No description provided for @quietHours.
  ///
  /// In tr, this message translates to:
  /// **'Sessiz saatler'**
  String get quietHours;

  /// No description provided for @biometricLockSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı açarken Face ID / parmak izi / cihaz PIN\'i iste'**
  String get biometricLockSubtitle;

  /// No description provided for @doneTitle.
  ///
  /// In tr, this message translates to:
  /// **'Tamamlandı'**
  String get doneTitle;

  /// No description provided for @alreadyPartners.
  ///
  /// In tr, this message translates to:
  /// **'Zaten Ortaksınız'**
  String get alreadyPartners;

  /// No description provided for @ownCode.
  ///
  /// In tr, this message translates to:
  /// **'Kendi Kodun'**
  String get ownCode;

  /// No description provided for @expiredTitle.
  ///
  /// In tr, this message translates to:
  /// **'Süresi Doldu'**
  String get expiredTitle;

  /// No description provided for @waitABit.
  ///
  /// In tr, this message translates to:
  /// **'Biraz Bekle'**
  String get waitABit;

  /// No description provided for @somethingWentWrong.
  ///
  /// In tr, this message translates to:
  /// **'Bir sorun oluştu'**
  String get somethingWentWrong;

  /// No description provided for @cancelInviteTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteğini iptal et'**
  String get cancelInviteTitle;

  /// No description provided for @cancelInviteBody.
  ///
  /// In tr, this message translates to:
  /// **'Gönderdiğin ortaklık isteğini iptal etmek istediğine emin misin?'**
  String get cancelInviteBody;

  /// No description provided for @yesCancel.
  ///
  /// In tr, this message translates to:
  /// **'Evet, iptal et'**
  String get yesCancel;

  /// No description provided for @settingsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get settingsTitle;

  /// No description provided for @partnerActionsUpper.
  ///
  /// In tr, this message translates to:
  /// **'ORTAKLIK İŞLEMLERİ'**
  String get partnerActionsUpper;

  /// No description provided for @myPartnersUpper.
  ///
  /// In tr, this message translates to:
  /// **'ORTAKLARIM'**
  String get myPartnersUpper;

  /// No description provided for @generateInviteCode.
  ///
  /// In tr, this message translates to:
  /// **'Davet Kodu Üret'**
  String get generateInviteCode;

  /// No description provided for @generateInviteCodeBody.
  ///
  /// In tr, this message translates to:
  /// **'Kodu ortağınıza gönderin. Ortak kodu girince size onay isteği gelir.'**
  String get generateInviteCodeBody;

  /// No description provided for @enterPartnerCode.
  ///
  /// In tr, this message translates to:
  /// **'Ortak Kodunu Gir'**
  String get enterPartnerCode;

  /// No description provided for @enterPartnerCodeBody.
  ///
  /// In tr, this message translates to:
  /// **'Ortağınızın size gönderdiği kodu girin (örn: KRHNJ-8P2SW). Onay vermesi beklenir.'**
  String get enterPartnerCodeBody;

  /// No description provided for @tooManyAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla deneme — {wait} sonra tekrar deneyebilirsin.'**
  String tooManyAttempts(String wait);

  /// No description provided for @awaitingApproval.
  ///
  /// In tr, this message translates to:
  /// **'{name} onayı bekleniyor...'**
  String awaitingApproval(String name);

  /// No description provided for @cancelWord.
  ///
  /// In tr, this message translates to:
  /// **'İptal'**
  String get cancelWord;

  /// No description provided for @noPartnersYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ortağınız yok'**
  String get noPartnersYet;

  /// No description provided for @removePartnerSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Ortağı sil'**
  String get removePartnerSemantics;

  /// No description provided for @removePartnerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklığı kaldır'**
  String get removePartnerTitle;

  /// No description provided for @removePartnerBody.
  ///
  /// In tr, this message translates to:
  /// **'{name} ile ortaklığı kaldırmak istediğine emin misin?'**
  String removePartnerBody(String name);

  /// No description provided for @removeWord.
  ///
  /// In tr, this message translates to:
  /// **'Kaldır'**
  String get removeWord;

  /// No description provided for @pendingRequestsUpper.
  ///
  /// In tr, this message translates to:
  /// **'BEKLEYEN ORTAKLIK İSTEKLERİ'**
  String get pendingRequestsUpper;

  /// No description provided for @wantsToPartner.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık istiyor'**
  String get wantsToPartner;

  /// No description provided for @rejectRequest.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteğini reddet'**
  String get rejectRequest;

  /// No description provided for @acceptRequest.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteğini kabul et'**
  String get acceptRequest;

  /// No description provided for @sandikPremium.
  ///
  /// In tr, this message translates to:
  /// **'Sandık Premium'**
  String get sandikPremium;

  /// No description provided for @premiumPitch.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız varlık, premium göstergeler, günde 2 sinyal analizi'**
  String get premiumPitch;

  /// No description provided for @premiumActive.
  ///
  /// In tr, this message translates to:
  /// **'Premium aktif'**
  String get premiumActive;

  /// No description provided for @premiumActiveBody.
  ///
  /// In tr, this message translates to:
  /// **'Tüm gelişmiş özellikler açık'**
  String get premiumActiveBody;

  /// No description provided for @codeCopied.
  ///
  /// In tr, this message translates to:
  /// **'Kod üretildi ve panoya kopyalandı'**
  String get codeCopied;

  /// No description provided for @tooManyFailedAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla başarısız deneme.\n{wait} sonra tekrar deneyebilirsin.'**
  String tooManyFailedAttempts(String wait);

  /// No description provided for @partnershipCreated.
  ///
  /// In tr, this message translates to:
  /// **'{name} ile ortaklık kuruldu!'**
  String partnershipCreated(String name);

  /// No description provided for @requestRejected.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteği reddedildi.'**
  String get requestRejected;

  /// No description provided for @requestCancelled.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteği iptal edildi.'**
  String get requestCancelled;

  /// No description provided for @partnershipAccepted.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık kabul edildi!'**
  String get partnershipAccepted;

  /// No description provided for @sendingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get sendingEllipsis;

  /// No description provided for @waitFor.
  ///
  /// In tr, this message translates to:
  /// **'Bekle — {wait}'**
  String waitFor(String wait);

  /// No description provided for @requestPartnership.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık İste'**
  String get requestPartnership;

  /// No description provided for @generatingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Üretiliyor...'**
  String get generatingEllipsis;

  /// No description provided for @generateCode.
  ///
  /// In tr, this message translates to:
  /// **'Kod Üret'**
  String get generateCode;

  /// No description provided for @switchToDark.
  ///
  /// In tr, this message translates to:
  /// **'Koyu temaya geç'**
  String get switchToDark;

  /// No description provided for @switchToLight.
  ///
  /// In tr, this message translates to:
  /// **'Açık temaya geç'**
  String get switchToLight;

  /// No description provided for @tabChart.
  ///
  /// In tr, this message translates to:
  /// **'Grafik'**
  String get tabChart;

  /// No description provided for @tabSummary.
  ///
  /// In tr, this message translates to:
  /// **'Özet'**
  String get tabSummary;

  /// No description provided for @modeReal.
  ///
  /// In tr, this message translates to:
  /// **'Gerçek'**
  String get modeReal;

  /// No description provided for @modeSim.
  ///
  /// In tr, this message translates to:
  /// **'Simülasyon'**
  String get modeSim;

  /// No description provided for @modeInfoSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{mode} modu hakkında bilgi'**
  String modeInfoSemantics(String mode);

  /// No description provided for @noChartData.
  ///
  /// In tr, this message translates to:
  /// **'Grafik verisi yok'**
  String get noChartData;

  /// No description provided for @noAssetsYetTitle.
  ///
  /// In tr, this message translates to:
  /// **'Henüz varlığın yok'**
  String get noAssetsYetTitle;

  /// No description provided for @noAssetsOfTypeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünde {type} yok'**
  String noAssetsOfTypeTitle(String type);

  /// No description provided for @noAssetsChartBody.
  ///
  /// In tr, this message translates to:
  /// **'Varlık ekledikçe portföyünün performansı burada grafiğe dönüşecek.'**
  String get noAssetsChartBody;

  /// No description provided for @noAssetsOfTypeChartBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu türden bir varlık eklediğinde performansı burada görünecek. Başka bir tür seçebilirsin.'**
  String get noAssetsOfTypeChartBody;

  /// No description provided for @noHistoryAllBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyündeki varlıkların fiyat geçmişi izlenmiyor; değerleri toplamda görünür ama zaman grafiği çizilemiyor.'**
  String get noHistoryAllBody;

  /// No description provided for @noHistoryTypeBody.
  ///
  /// In tr, this message translates to:
  /// **'{type} için fiyat geçmişi izlenmiyor. Değeri portföy toplamına dahil, ama zaman grafiği çizilemiyor.'**
  String noHistoryTypeBody(String type);

  /// No description provided for @simModeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Simülasyon Modu'**
  String get simModeTitle;

  /// No description provided for @realModeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Gerçek Mod'**
  String get realModeTitle;

  /// No description provided for @simModeBody.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş olsaydın grafik nasıl görünürdü — geçmişteki alım/satış kararlarını yok sayar, sadece güncel pozisyonun fiyat değişimini gösterir.'**
  String get simModeBody;

  /// No description provided for @realModeBody.
  ///
  /// In tr, this message translates to:
  /// **'Her günün grafikteki değeri, o gün elinde olan net miktara göre hesaplanır. Bir noktaya dokununca o günkü portföy değeri ve varsa alım / satış tutarları görünür — böylece grafiğin neden yükseldiğini veya düştüğünü net görebilirsin.'**
  String get realModeBody;

  /// No description provided for @portfolioPerformance.
  ///
  /// In tr, this message translates to:
  /// **'Portföy Performans'**
  String get portfolioPerformance;

  /// No description provided for @chartDataFailed.
  ///
  /// In tr, this message translates to:
  /// **'Grafik verisi alınamadı'**
  String get chartDataFailed;

  /// No description provided for @chartDataFailedBody.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat geçmişi şu an getirilemedi. Bağlantını kontrol edip tekrar deneyebilirsin.'**
  String get chartDataFailedBody;

  /// No description provided for @intradayMissingBody.
  ///
  /// In tr, this message translates to:
  /// **'{names} için gün içi fiyat verisi alınamadı. Bu varlıklar grafikte son bilinen fiyatlarıyla SABİT çizildi — çizginin düz olması piyasanın durgun olduğu anlamına gelmez.'**
  String intradayMissingBody(String names);

  /// No description provided for @retryLower.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar dene'**
  String get retryLower;

  /// No description provided for @raceUpper.
  ///
  /// In tr, this message translates to:
  /// **'YARIŞ'**
  String get raceUpper;

  /// No description provided for @changeByTypeUpper.
  ///
  /// In tr, this message translates to:
  /// **'TÜRE GÖRE DEĞİŞİM'**
  String get changeByTypeUpper;

  /// No description provided for @noData.
  ///
  /// In tr, this message translates to:
  /// **'Veri yok'**
  String get noData;

  /// No description provided for @tooltipReturn.
  ///
  /// In tr, this message translates to:
  /// **'\nGetiri '**
  String get tooltipReturn;

  /// No description provided for @tooltipBuy.
  ///
  /// In tr, this message translates to:
  /// **'\nAlım  +'**
  String get tooltipBuy;

  /// No description provided for @tooltipSell.
  ///
  /// In tr, this message translates to:
  /// **'\nSatış −'**
  String get tooltipSell;

  /// No description provided for @tooltipNet.
  ///
  /// In tr, this message translates to:
  /// **'\nNet '**
  String get tooltipNet;

  /// No description provided for @tooltipInvested.
  ///
  /// In tr, this message translates to:
  /// **'\nToplam yatırım '**
  String get tooltipInvested;

  /// No description provided for @tradeVolumeUpper.
  ///
  /// In tr, this message translates to:
  /// **'İŞLEM HACMİ'**
  String get tradeVolumeUpper;

  /// No description provided for @performanceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Performans'**
  String get performanceTitle;

  /// No description provided for @intervalWeekly.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık'**
  String get intervalWeekly;

  /// No description provided for @intervalMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık'**
  String get intervalMonthly;

  /// No description provided for @intervalYearly.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık'**
  String get intervalYearly;

  /// No description provided for @lastNWeeksNet.
  ///
  /// In tr, this message translates to:
  /// **'son {n} hafta · net'**
  String lastNWeeksNet(int n);

  /// No description provided for @lastNMonthsNet.
  ///
  /// In tr, this message translates to:
  /// **'son {n} ay · net'**
  String lastNMonthsNet(int n);

  /// No description provided for @lastNYearsNet.
  ///
  /// In tr, this message translates to:
  /// **'son {n} yıl · net'**
  String lastNYearsNet(int n);

  /// No description provided for @avgContributingWeek.
  ///
  /// In tr, this message translates to:
  /// **'Katkı yaptığın hafta ortalaması'**
  String get avgContributingWeek;

  /// No description provided for @avgContributingMonth.
  ///
  /// In tr, this message translates to:
  /// **'Katkı yaptığın ay ortalaması'**
  String get avgContributingMonth;

  /// No description provided for @avgContributingYear.
  ///
  /// In tr, this message translates to:
  /// **'Katkı yaptığın yıl ortalaması'**
  String get avgContributingYear;

  /// No description provided for @vsLastWeek.
  ///
  /// In tr, this message translates to:
  /// **'Geçen haftaya göre'**
  String get vsLastWeek;

  /// No description provided for @vsLastMonth.
  ///
  /// In tr, this message translates to:
  /// **'Geçen aya göre'**
  String get vsLastMonth;

  /// No description provided for @vsLastYear.
  ///
  /// In tr, this message translates to:
  /// **'Geçen yıla göre'**
  String get vsLastYear;

  /// No description provided for @ongoingWeek.
  ///
  /// In tr, this message translates to:
  /// **', devam eden hafta'**
  String get ongoingWeek;

  /// No description provided for @ongoingMonth.
  ///
  /// In tr, this message translates to:
  /// **', devam eden ay'**
  String get ongoingMonth;

  /// No description provided for @ongoingYear.
  ///
  /// In tr, this message translates to:
  /// **', devam eden yıl'**
  String get ongoingYear;

  /// No description provided for @trendUpWeek.
  ///
  /// In tr, this message translates to:
  /// **'Son hafta önceki katkılarının üzerinde.'**
  String get trendUpWeek;

  /// No description provided for @trendUpMonth.
  ///
  /// In tr, this message translates to:
  /// **'Son ay önceki katkılarının üzerinde.'**
  String get trendUpMonth;

  /// No description provided for @trendUpYear.
  ///
  /// In tr, this message translates to:
  /// **'Son yıl önceki katkılarının üzerinde.'**
  String get trendUpYear;

  /// No description provided for @trendDownWeek.
  ///
  /// In tr, this message translates to:
  /// **'Son hafta önceki katkılarının altında.'**
  String get trendDownWeek;

  /// No description provided for @trendDownMonth.
  ///
  /// In tr, this message translates to:
  /// **'Son ay önceki katkılarının altında.'**
  String get trendDownMonth;

  /// No description provided for @trendDownYear.
  ///
  /// In tr, this message translates to:
  /// **'Son yıl önceki katkılarının altında.'**
  String get trendDownYear;

  /// No description provided for @trendFlatWeek.
  ///
  /// In tr, this message translates to:
  /// **'Katkın haftadan haftaya istikrarlı.'**
  String get trendFlatWeek;

  /// No description provided for @trendFlatMonth.
  ///
  /// In tr, this message translates to:
  /// **'Katkın aydan aya istikrarlı.'**
  String get trendFlatMonth;

  /// No description provided for @trendFlatYear.
  ///
  /// In tr, this message translates to:
  /// **'Katkın yıldan yıla istikrarlı.'**
  String get trendFlatYear;

  /// No description provided for @biggestMoverToday.
  ///
  /// In tr, this message translates to:
  /// **'Günün en çok hareket edeni'**
  String get biggestMoverToday;

  /// No description provided for @weekExtremes.
  ///
  /// In tr, this message translates to:
  /// **'Haftanın uçları'**
  String get weekExtremes;

  /// No description provided for @lastMonthPeriod.
  ///
  /// In tr, this message translates to:
  /// **'son 1 ay'**
  String get lastMonthPeriod;

  /// No description provided for @last6MonthsPeriod.
  ///
  /// In tr, this message translates to:
  /// **'son 6 ay'**
  String get last6MonthsPeriod;

  /// No description provided for @sixMonthExtremes.
  ///
  /// In tr, this message translates to:
  /// **'Altı ayın uçları'**
  String get sixMonthExtremes;

  /// No description provided for @lastYearPeriod.
  ///
  /// In tr, this message translates to:
  /// **'son 1 yıl'**
  String get lastYearPeriod;

  /// No description provided for @yearCurve.
  ///
  /// In tr, this message translates to:
  /// **'Yıl eğrisi'**
  String get yearCurve;

  /// No description provided for @periodMarketReturn.
  ///
  /// In tr, this message translates to:
  /// **'{period} piyasa getirisi'**
  String periodMarketReturn(String period);

  /// No description provided for @whereItCameFrom.
  ///
  /// In tr, this message translates to:
  /// **'Nereden geldi'**
  String get whereItCameFrom;

  /// No description provided for @periodStart.
  ///
  /// In tr, this message translates to:
  /// **'Dönem başı'**
  String get periodStart;

  /// No description provided for @yourContribution.
  ///
  /// In tr, this message translates to:
  /// **'Katkın'**
  String get yourContribution;

  /// No description provided for @marketWord.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa'**
  String get marketWord;

  /// No description provided for @cashDividend.
  ///
  /// In tr, this message translates to:
  /// **'Bunun nakit temettüsü'**
  String get cashDividend;

  /// No description provided for @commissionPaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödenen komisyon'**
  String get commissionPaid;

  /// No description provided for @contributionNotReturn.
  ///
  /// In tr, this message translates to:
  /// **'Mavi çubuk senin paran — getiri sayılmaz. Yüzde yalnızca piyasa çubuğundan hesaplanır.'**
  String get contributionNotReturn;

  /// No description provided for @periodCourse.
  ///
  /// In tr, this message translates to:
  /// **'Dönem içi seyir'**
  String get periodCourse;

  /// No description provided for @greenDaysOfTotal.
  ///
  /// In tr, this message translates to:
  /// **'{total} işlem gününün {up}\'ü artıda kapandı.'**
  String greenDaysOfTotal(int total, int up);

  /// No description provided for @againstInflation.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyona karşı'**
  String get againstInflation;

  /// No description provided for @realReturnPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Reel getiri · {period}'**
  String realReturnPeriod(String period);

  /// No description provided for @nominalReturn.
  ///
  /// In tr, this message translates to:
  /// **'Senin getirin'**
  String get nominalReturn;

  /// TÜFE karşılaştırmasının gerçek pencere uçları
  ///
  /// In tr, this message translates to:
  /// **'Ölçüm aralığı: {start} – {end}'**
  String cpiWindowRange(String start, String end);

  /// No description provided for @periodCpi.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyon (TÜFE)'**
  String get periodCpi;

  /// No description provided for @pointDifference.
  ///
  /// In tr, this message translates to:
  /// **'Aradaki fark'**
  String get pointDifference;

  /// No description provided for @realReturn.
  ///
  /// In tr, this message translates to:
  /// **'Reel getiri'**
  String get realReturn;

  /// No description provided for @cpiNotLoaded.
  ///
  /// In tr, this message translates to:
  /// **'TÜFE verisi henüz yüklenmedi.'**
  String get cpiNotLoaded;

  /// No description provided for @cpiNotLoadedBody.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyon endeksi geldiğinde portföyünün reel getirisi burada görünecek. Tahmini bir sayı gösterilmiyor.'**
  String get cpiNotLoadedBody;

  /// No description provided for @allocationChange.
  ///
  /// In tr, this message translates to:
  /// **'Dağılım değişimi'**
  String get allocationChange;

  /// No description provided for @sixMonthComparison.
  ///
  /// In tr, this message translates to:
  /// **'Altı aylık karşılaştırma'**
  String get sixMonthComparison;

  /// No description provided for @portfolioCharacter.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünün karakteri'**
  String get portfolioCharacter;

  /// No description provided for @mostPatientAsset.
  ///
  /// In tr, this message translates to:
  /// **'En sabırlı varlığın'**
  String get mostPatientAsset;

  /// No description provided for @nDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün'**
  String nDays(int n);

  /// No description provided for @shareSummary.
  ///
  /// In tr, this message translates to:
  /// **'Özetini paylaş'**
  String get shareSummary;

  /// No description provided for @savingDiscipline.
  ///
  /// In tr, this message translates to:
  /// **'Birikim disiplinin'**
  String get savingDiscipline;

  /// No description provided for @noNewMoney.
  ///
  /// In tr, this message translates to:
  /// **'Bu pencerede portföyüne yeni para girmemiş.'**
  String get noNewMoney;

  /// No description provided for @highestWord.
  ///
  /// In tr, this message translates to:
  /// **'En yüksek'**
  String get highestWord;

  /// No description provided for @contributingPeriods.
  ///
  /// In tr, this message translates to:
  /// **'Katkı yapılan dönem'**
  String get contributingPeriods;

  /// No description provided for @portfolioHealthPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Portföy sağlığı · {period}'**
  String portfolioHealthPeriod(String period);

  /// No description provided for @maxDrawdown.
  ///
  /// In tr, this message translates to:
  /// **'En büyük düşüş'**
  String get maxDrawdown;

  /// No description provided for @volatility.
  ///
  /// In tr, this message translates to:
  /// **'Oynaklık'**
  String get volatility;

  /// No description provided for @volatilityBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünün değeri yıl boyunca ortalama bu ölçüde dalgalandı. Yüksek olması iyi ya da kötü değil — daha çok inip çıktığı anlamına gelir.'**
  String get volatilityBody;

  /// No description provided for @concentration.
  ///
  /// In tr, this message translates to:
  /// **'Yoğunlaşma'**
  String get concentration;

  /// No description provided for @moneyReturnAnnual.
  ///
  /// In tr, this message translates to:
  /// **'Paranın getirisi (yıllık)'**
  String get moneyReturnAnnual;

  /// No description provided for @xirrBody.
  ///
  /// In tr, this message translates to:
  /// **'Yatırdığın paranın, yatırdığın TARİHLER dikkate alınarak hesaplanan yıllık bileşik getirisi.'**
  String get xirrBody;

  /// No description provided for @periodMarketReturnLabel.
  ///
  /// In tr, this message translates to:
  /// **'Dönem piyasa getirisi'**
  String get periodMarketReturnLabel;

  /// No description provided for @xirrVsMarketBody.
  ///
  /// In tr, this message translates to:
  /// **'İki sayı çelişmez: üstteki senin ne zaman alım yaptığını da hesaba katar, alttaki yalnızca piyasanın hareketini ölçer.'**
  String get xirrVsMarketBody;

  /// No description provided for @advancedMetricsYear.
  ///
  /// In tr, this message translates to:
  /// **'İleri metrikler · son 1 yıl'**
  String get advancedMetricsYear;

  /// No description provided for @notEnoughHistory.
  ///
  /// In tr, this message translates to:
  /// **'{period} için yeterli geçmiş yok'**
  String notEnoughHistory(String period);

  /// No description provided for @notEnoughHistoryBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönem dolduğunda özet kendiliğinden görünür.'**
  String get notEnoughHistoryBody;

  /// No description provided for @nAssetsPeriod.
  ///
  /// In tr, this message translates to:
  /// **'{count} VARLIK · {period}'**
  String nAssetsPeriod(int count, String period);

  /// No description provided for @chartLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Grafik yüklenemedi.'**
  String get chartLoadFailed;

  /// No description provided for @notEnoughPriceHistory.
  ///
  /// In tr, this message translates to:
  /// **'Grafik için yeterli fiyat geçmişi yok.'**
  String get notEnoughPriceHistory;

  /// No description provided for @portfolioLineNote.
  ///
  /// In tr, this message translates to:
  /// **'{name} çizgisi, bugünkü varlıklarını dönem başından beri tutsaydın senaryosudur — gerçekleşmiş getirin değildir.'**
  String portfolioLineNote(String name);

  /// No description provided for @openDetailSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} detayını aç'**
  String openDetailSemantics(String name);

  /// No description provided for @addToPortfolioSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} portföyüme ekle'**
  String addToPortfolioSemantics(String name);

  /// No description provided for @noWatchlistYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz izlediğin varlık yok'**
  String get noWatchlistYet;

  /// No description provided for @noWatchlistBody.
  ///
  /// In tr, this message translates to:
  /// **'Almadan önce takibe al. Fiyatını portföyüne dokunmadan izle.'**
  String get noWatchlistBody;

  /// No description provided for @addToWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Takibe varlık ekle'**
  String get addToWatchlist;

  /// No description provided for @whyWatchlistUpper.
  ///
  /// In tr, this message translates to:
  /// **'NEDEN TAKİP LİSTESİ?'**
  String get whyWatchlistUpper;

  /// No description provided for @whyWatchlistBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir varlığı satın almadan fiyatını izleyebilirsin. Takip listesi portföyüne girmez; toplam değerini ve kâr/zararını etkilemez.'**
  String get whyWatchlistBody;

  /// No description provided for @notInPortfolioNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlıklar portföyüne dahil değildir.'**
  String get notInPortfolioNote;

  /// No description provided for @addAssetsToCompare.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştırmak için varlık ekleyin'**
  String get addAssetsToCompare;

  /// No description provided for @addAssetsToCompareBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünüzde olmayan varlıkları da ekleyebilirsiniz.'**
  String get addAssetsToCompareBody;

  /// No description provided for @inMyPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'Portföyümde'**
  String get inMyPortfolio;

  /// No description provided for @noDataShort.
  ///
  /// In tr, this message translates to:
  /// **'veri yok'**
  String get noDataShort;

  /// No description provided for @addToMyPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'Portföyüme ekle'**
  String get addToMyPortfolio;

  /// No description provided for @comparisonDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Geçmiş performans gelecek getiri için gösterge değildir. Grafikteki değerler dönem başına göre yüzde değişimi gösterir; komisyon, vergi ve temettü dahil değildir.'**
  String get comparisonDisclaimer;

  /// No description provided for @searchAssetsHint.
  ///
  /// In tr, this message translates to:
  /// **'Hisse, fon, altın veya endeks ara'**
  String get searchAssetsHint;

  /// No description provided for @noResultsFound.
  ///
  /// In tr, this message translates to:
  /// **'Sonuç bulunamadı'**
  String get noResultsFound;

  /// No description provided for @portfolioSeriesNote.
  ///
  /// In tr, this message translates to:
  /// **'Portföyler hesaplanan serilerdir — piyasada kote değiller. Getirileri, tıpkı bir varlık gibi dönem başına göre yüzde olarak çizilir.'**
  String get portfolioSeriesNote;

  /// No description provided for @portfolioActivityTitle.
  ///
  /// In tr, this message translates to:
  /// **'Portföy Hareketleri'**
  String get portfolioActivityTitle;

  /// No description provided for @clearFilters.
  ///
  /// In tr, this message translates to:
  /// **'Filtreleri temizle'**
  String get clearFilters;

  /// No description provided for @loadingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Yükleniyor…'**
  String get loadingEllipsis;

  /// No description provided for @widenDateRangeHint.
  ///
  /// In tr, this message translates to:
  /// **'Tarih aralığını genişletmeyi veya aramayı temizlemeyi dene.'**
  String get widenDateRangeHint;

  /// No description provided for @priceAlertsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat Alarmları'**
  String get priceAlertsTitle;

  /// No description provided for @createAlert.
  ///
  /// In tr, this message translates to:
  /// **'Alarm kur'**
  String get createAlert;

  /// No description provided for @noAlertsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz alarmın yok'**
  String get noAlertsYet;

  /// No description provided for @noAlertsBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir varlığın ekranındaki zile dokun ya da buradan kur; uygulama kapalıyken bile haber verelim.'**
  String get noAlertsBody;

  /// No description provided for @recreateAlert.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden kur'**
  String get recreateAlert;

  /// No description provided for @raceTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yarış'**
  String get raceTitle;

  /// No description provided for @raceOptions.
  ///
  /// In tr, this message translates to:
  /// **'Yarış seçenekleri'**
  String get raceOptions;

  /// No description provided for @leaveRace.
  ///
  /// In tr, this message translates to:
  /// **'Yarıştan ayrıl'**
  String get leaveRace;

  /// No description provided for @leaveRaceBody.
  ///
  /// In tr, this message translates to:
  /// **'Sıralamadan çıkarsın; ortakların yüzdeni artık göremez. İstediğin zaman yeniden katılabilirsin.'**
  String get leaveRaceBody;

  /// No description provided for @leaveWord.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıl'**
  String get leaveWord;

  /// No description provided for @howReturnCalculated.
  ///
  /// In tr, this message translates to:
  /// **'Getiri nasıl hesaplanıyor?'**
  String get howReturnCalculated;

  /// No description provided for @selectedPeriodReturn.
  ///
  /// In tr, this message translates to:
  /// **'Seçili dönemin getirisi'**
  String get selectedPeriodReturn;

  /// No description provided for @depositsDontChangeRank.
  ///
  /// In tr, this message translates to:
  /// **'Para yatırmak sıralamayı değiştirmez'**
  String get depositsDontChangeRank;

  /// No description provided for @everyoneMeasuredSame.
  ///
  /// In tr, this message translates to:
  /// **'Herkes aynı şekilde ölçülür'**
  String get everyoneMeasuredSame;

  /// No description provided for @rankVsPortfolioNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu sayı, Portföy ekranındaki kâr/zarar yüzdesinden FARKLI olabilir — orası ilk alımından bugüne olan toplam kâr/zararı gösterir, burası ise yalnızca seçtiğin dönemde ne olduğunu.'**
  String get rankVsPortfolioNote;

  /// No description provided for @rankSwapNote.
  ///
  /// In tr, this message translates to:
  /// **'Dönem içinde bir varlığı tamamen satıp yerine başkasını aldıysan, sonuç \"yeni varlığı dönem başından beri tutsaydın\" senaryosunu gösterir. Fiyat geçmişi bulunamayan portföyler sıralamada yer almaz.'**
  String get rankSwapNote;

  /// No description provided for @notInRace.
  ///
  /// In tr, this message translates to:
  /// **'Yarış\'a katılmadın'**
  String get notInRace;

  /// No description provided for @notInRaceBody.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklarınla getiri sıralamasında yer almak için katılmayı aç. Sadece kaydolan ortaklar birbirinin yüzdesini görebilir. Varlıkların ve toplam TRY değerin asla paylaşılmaz.'**
  String get notInRaceBody;

  /// No description provided for @joinRace.
  ///
  /// In tr, this message translates to:
  /// **'Yarış\'a katıl'**
  String get joinRace;

  /// No description provided for @addPartnerToRace.
  ///
  /// In tr, this message translates to:
  /// **'Ortak ekle, aranızda da yarış'**
  String get addPartnerToRace;

  /// No description provided for @raceNoListShared.
  ///
  /// In tr, this message translates to:
  /// **'Kimsenin varlık listesi paylaşılmaz — yalnız getiri yüzdeleri sıralanır.'**
  String get raceNoListShared;

  /// No description provided for @yourReturnUpper.
  ///
  /// In tr, this message translates to:
  /// **'SENİN GETİRİN'**
  String get yourReturnUpper;

  /// No description provided for @dataNotReady.
  ///
  /// In tr, this message translates to:
  /// **'Veri hazır değil.'**
  String get dataNotReady;

  /// No description provided for @leaderUpper.
  ///
  /// In tr, this message translates to:
  /// **'LİDER'**
  String get leaderUpper;

  /// No description provided for @loadingUpper.
  ///
  /// In tr, this message translates to:
  /// **'YÜKLENİYOR'**
  String get loadingUpper;

  /// No description provided for @globalRanking.
  ///
  /// In tr, this message translates to:
  /// **'Genel Sıralama'**
  String get globalRanking;

  /// No description provided for @checkingAnonPool.
  ///
  /// In tr, this message translates to:
  /// **'Anonim havuz kontrol ediliyor…'**
  String get checkingAnonPool;

  /// No description provided for @comingSoonUpper.
  ///
  /// In tr, this message translates to:
  /// **'YAKINDA'**
  String get comingSoonUpper;

  /// No description provided for @globalRankingSoon.
  ///
  /// In tr, this message translates to:
  /// **'Yeterli katılımcı olunca sıran açılacak — anonim, KVKK uyumlu'**
  String get globalRankingSoon;

  /// No description provided for @topPercentile.
  ///
  /// In tr, this message translates to:
  /// **'{period} sıralamada ilk %{pct}\'desin'**
  String topPercentile(String period, int pct);

  /// No description provided for @topPortfolios.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedeki Portföyler'**
  String get topPortfolios;

  /// No description provided for @topGainersAllocation.
  ///
  /// In tr, this message translates to:
  /// **'{period} en çok kazananların dağılımı'**
  String topGainersAllocation(String period);

  /// No description provided for @anonymousUpper.
  ///
  /// In tr, this message translates to:
  /// **'ANONİM'**
  String get anonymousUpper;

  /// No description provided for @topPortfoliosSoon.
  ///
  /// In tr, this message translates to:
  /// **'Yeterli katılımcı olunca zirve portföyler burada görünecek. Anonim havuz oluşuyor…'**
  String get topPortfoliosSoon;

  /// No description provided for @nthPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'{n}. portföy'**
  String nthPortfolio(int n);

  /// No description provided for @selectedPeriodReturnBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünün dönem sonundaki değeri, dönem başındaki değeriyle karşılaştırılır:\n\n(dönem sonu − dönem başı) ÷ dönem başı\n\nYukarıdaki 7G / 30G / 1Y seçimi sonucu doğrudan değiştirir.'**
  String get selectedPeriodReturnBody;

  /// No description provided for @depositsDontChangeRankBody.
  ///
  /// In tr, this message translates to:
  /// **'Ölçülen tek şey, varlıklarının piyasada ne kadar değer kazandığı. Dönem içinde yaptığın alım ve satımlar oranı ETKİLEMEZ.\n\nHesap, bugünkü varlıklarını dönem başından beri tutmuşsun gibi yapılır. Bu yüzden portföyünü büyütmek getirini yükseltmez — 1 lot da tutsan 10.000 lot da tutsan aynı yüzdeyi görürsün.'**
  String get depositsDontChangeRankBody;

  /// No description provided for @everyoneMeasuredSameBody.
  ///
  /// In tr, this message translates to:
  /// **'Sen ve ortakların aynı formülle, aynı anda, aynı fiyatlarla hesaplanırsınız.\n\nOrtağının uygulamayı açmasını beklemene gerek yok — hesap bu cihazda yapılır.'**
  String get everyoneMeasuredSameBody;

  /// No description provided for @planYearly.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık'**
  String get planYearly;

  /// No description provided for @planYearlySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'7 gün ücretsiz dene, sonra otomatik yenilenir'**
  String get planYearlySubtitle;

  /// No description provided for @planMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık'**
  String get planMonthly;

  /// No description provided for @planMonthlySubtitle.
  ///
  /// In tr, this message translates to:
  /// **'İstediğin zaman iptal edebilirsin'**
  String get planMonthlySubtitle;

  /// No description provided for @subscriptionTerms.
  ///
  /// In tr, this message translates to:
  /// **'Abonelik App Store hesabına yansır. Otomatik yenilenir, iptal için Ayarlar → Apple ID → Abonelikler menüsünden yönetebilirsin. Yıllık abonelikte ilk 7 gün ücretsiz denemedir; iptal etmezsen deneme sonunda ücret tahsil edilir.'**
  String get subscriptionTerms;

  /// No description provided for @premiumUnlocked.
  ///
  /// In tr, this message translates to:
  /// **'Premium açıldı'**
  String get premiumUnlocked;

  /// No description provided for @premiumUnlockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız varlık, günde 2 sinyal analizi, premium göstergeler ve daha fazlası açıldı.'**
  String get premiumUnlockedBody;

  /// No description provided for @greatWord.
  ///
  /// In tr, this message translates to:
  /// **'Harika'**
  String get greatWord;

  /// No description provided for @sandikPremiumUpper.
  ///
  /// In tr, this message translates to:
  /// **'SANDIK PREMIUM'**
  String get sandikPremiumUpper;

  /// No description provided for @paywallHeadline.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünü daha derinlemesine\ntakip et'**
  String get paywallHeadline;

  /// No description provided for @paywallSubhead.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız varlık, gelişmiş göstergeler ve günde 2 sinyal analizi.'**
  String get paywallSubhead;

  /// No description provided for @restorePurchase.
  ///
  /// In tr, this message translates to:
  /// **'Satın alımı geri yükle'**
  String get restorePurchase;

  /// No description provided for @recapTitle.
  ///
  /// In tr, this message translates to:
  /// **'sandık Özetin'**
  String get recapTitle;

  /// No description provided for @recapInYear.
  ///
  /// In tr, this message translates to:
  /// **'{year} yılında'**
  String recapInYear(int year);

  /// No description provided for @recapSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bir yılın kısa hikâyesi.'**
  String get recapSubtitle;

  /// No description provided for @recapPoints.
  ///
  /// In tr, this message translates to:
  /// **'{n} puan'**
  String recapPoints(String n);

  /// No description provided for @recapDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün'**
  String recapDays(int n);

  /// No description provided for @myRecapYear.
  ///
  /// In tr, this message translates to:
  /// **'Özetim {year}'**
  String myRecapYear(int year);

  /// No description provided for @recapReady.
  ///
  /// In tr, this message translates to:
  /// **'{year} Özetin hazır'**
  String recapReady(int year);

  /// No description provided for @recapCardSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bir yılın kısa hikâyesi — {character}'**
  String recapCardSubtitle(String character);

  /// No description provided for @medianAhead.
  ///
  /// In tr, this message translates to:
  /// **'medyandan {pts} puan önde'**
  String medianAhead(String pts);

  /// No description provided for @returnRanking.
  ///
  /// In tr, this message translates to:
  /// **'Getiri sıralaması'**
  String get returnRanking;

  /// No description provided for @returnRankingWith.
  ///
  /// In tr, this message translates to:
  /// **'Getiri sıralaması · {detail}'**
  String returnRankingWith(String detail);

  /// No description provided for @percentileSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 günde katılımcıların yüzde {pct} kadarının üstündesin. {detail}'**
  String percentileSemantics(int pct, String detail);

  /// No description provided for @last30DaysLike.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 günde senin gibi '**
  String get last30DaysLike;

  /// No description provided for @nPeople.
  ///
  /// In tr, this message translates to:
  /// **'{n} kişi'**
  String nPeople(int n);

  /// No description provided for @medianBehind.
  ///
  /// In tr, this message translates to:
  /// **'medyandan {pts} puan geride'**
  String medianBehind(String pts);

  /// No description provided for @realReturnSemanticsAhead.
  ///
  /// In tr, this message translates to:
  /// **'Son bir yılda portföyün enflasyonu yüzde {pts} puan geçti'**
  String realReturnSemanticsAhead(String pts);

  /// No description provided for @lastYearInflation.
  ///
  /// In tr, this message translates to:
  /// **'Son bir yılda enflasyonun '**
  String get lastYearInflation;

  /// No description provided for @pointsAhead.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan önündesin'**
  String pointsAhead(String pts);

  /// No description provided for @realReturnSemanticsBehind.
  ///
  /// In tr, this message translates to:
  /// **'Son bir yılda portföyün enflasyonun yüzde {pts} puan gerisinde kaldı'**
  String realReturnSemanticsBehind(String pts);

  /// No description provided for @pointsBehind.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan gerisindesin'**
  String pointsBehind(String pts);

  /// No description provided for @realReturnPointsUnit.
  ///
  /// In tr, this message translates to:
  /// **'puan'**
  String get realReturnPointsUnit;

  /// No description provided for @realReturnAheadOfInflation.
  ///
  /// In tr, this message translates to:
  /// **'enflasyonun önündesin'**
  String get realReturnAheadOfInflation;

  /// No description provided for @realReturnBehindInflation.
  ///
  /// In tr, this message translates to:
  /// **'enflasyonun gerisindesin'**
  String get realReturnBehindInflation;

  /// No description provided for @realReturnLastYear.
  ///
  /// In tr, this message translates to:
  /// **'son bir yıl'**
  String get realReturnLastYear;

  /// No description provided for @realReturnYours.
  ///
  /// In tr, this message translates to:
  /// **'Senin'**
  String get realReturnYours;

  /// No description provided for @realReturnCpi.
  ///
  /// In tr, this message translates to:
  /// **'TÜFE'**
  String get realReturnCpi;

  /// No description provided for @weeklyFlatSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta portföyün piyasa getirisi değişmedi'**
  String get weeklyFlatSemantics;

  /// No description provided for @thisWeekFromMarket.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta piyasadan '**
  String get thisWeekFromMarket;

  /// No description provided for @noChangeLower.
  ///
  /// In tr, this message translates to:
  /// **'değişim yok'**
  String get noChangeLower;

  /// No description provided for @pctDown.
  ///
  /// In tr, this message translates to:
  /// **'%{pct} eksi'**
  String pctDown(String pct);

  /// No description provided for @weeklyDownSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta portföyün piyasa getirisi yüzde {pct} ekside'**
  String weeklyDownSemantics(String pct);

  /// No description provided for @weeklyUpSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta portföyün piyasa getirisi yüzde {pct} artıda'**
  String weeklyUpSemantics(String pct);

  /// No description provided for @pctUp.
  ///
  /// In tr, this message translates to:
  /// **'%{pct} artı'**
  String pctUp(String pct);

  /// No description provided for @totalNetHidden.
  ///
  /// In tr, this message translates to:
  /// **'Toplam net varlık gizli'**
  String get totalNetHidden;

  /// No description provided for @totalNetWorth.
  ///
  /// In tr, this message translates to:
  /// **'Toplam net varlık {amount}'**
  String totalNetWorth(String amount);

  /// No description provided for @realisedFromSales.
  ///
  /// In tr, this message translates to:
  /// **'Satışlardan gerçekleşen: '**
  String get realisedFromSales;

  /// No description provided for @deletedNRecords.
  ///
  /// In tr, this message translates to:
  /// **'Silindi · {n} kayıt'**
  String deletedNRecords(int n);

  /// No description provided for @txSell.
  ///
  /// In tr, this message translates to:
  /// **'Satım'**
  String get txSell;

  /// No description provided for @txDividend.
  ///
  /// In tr, this message translates to:
  /// **'Temettü'**
  String get txDividend;

  /// No description provided for @txBuy.
  ///
  /// In tr, this message translates to:
  /// **'Alım'**
  String get txBuy;

  /// No description provided for @gainWord.
  ///
  /// In tr, this message translates to:
  /// **'kazanç'**
  String get gainWord;

  /// No description provided for @lossWord.
  ///
  /// In tr, this message translates to:
  /// **'kayıp'**
  String get lossWord;

  /// No description provided for @realisedFromSalesSemantics.
  ///
  /// In tr, this message translates to:
  /// **'satışlardan gerçekleşen '**
  String get realisedFromSalesSemantics;

  /// No description provided for @raceNoPartnerBody.
  ///
  /// In tr, this message translates to:
  /// **'Henüz ortağın yok. Kendi dönem getirini ve küresel dilimini şimdiden görebilirsin.'**
  String get raceNoPartnerBody;

  /// No description provided for @viewWord.
  ///
  /// In tr, this message translates to:
  /// **'Gör'**
  String get viewWord;

  /// No description provided for @newUpper.
  ///
  /// In tr, this message translates to:
  /// **'YENİ'**
  String get newUpper;

  /// No description provided for @racePitch.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklarınla getiri sıralaması. Kim daha iyi kazanıyor?'**
  String get racePitch;

  /// No description provided for @joinWord.
  ///
  /// In tr, this message translates to:
  /// **'Katıl'**
  String get joinWord;

  /// No description provided for @raceCalculating.
  ///
  /// In tr, this message translates to:
  /// **'Yarış hesaplanıyor…'**
  String get raceCalculating;

  /// No description provided for @rankFirst.
  ///
  /// In tr, this message translates to:
  /// **'{period} sıralamada 1.\'sin'**
  String rankFirst(String period);

  /// No description provided for @rankNth.
  ///
  /// In tr, this message translates to:
  /// **'{period} sıralamada {rank} sıradasın'**
  String rankNth(String period, String rank);

  /// No description provided for @widenTheGap.
  ///
  /// In tr, this message translates to:
  /// **'Farkı büyüt — ikinci +{gap}% geride'**
  String widenTheGap(String gap);

  /// No description provided for @atTheTop.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedesin — farkı koru'**
  String get atTheTop;

  /// No description provided for @toPassPerson.
  ///
  /// In tr, this message translates to:
  /// **'{name}\'i geçmen için +{diff}%'**
  String toPassPerson(String name, String diff);

  /// No description provided for @higherInOtherPeriods.
  ///
  /// In tr, this message translates to:
  /// **'Diğer periyotlarda daha üsttesin — dokun, bak'**
  String get higherInOtherPeriods;

  /// No description provided for @deleteAssetTitle.
  ///
  /// In tr, this message translates to:
  /// **'Varlığı Sil'**
  String get deleteAssetTitle;

  /// No description provided for @deleteAssetMulti.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" için {n} işlem kaydı (alım/satım/temettü) kalıcı olarak silinsin mi?'**
  String deleteAssetMulti(String name, int n);

  /// No description provided for @deleteAssetSingle.
  ///
  /// In tr, this message translates to:
  /// **'\"{name}\" kalıcı olarak silinsin mi?'**
  String deleteAssetSingle(String name);

  /// No description provided for @deleteAnyway.
  ///
  /// In tr, this message translates to:
  /// **'Yine de sil'**
  String get deleteAnyway;

  /// No description provided for @deleteAssetWarning.
  ///
  /// In tr, this message translates to:
  /// **'Bu bir satış değil — varlık portföyden çıkar, toplamlardan ve geçmiş grafiğinden düşer. İşlem kayıtları \"Portföy Hareketleri\"nde kalır. Sattıysan bunun yerine \"Sat\" kullan; realize kâr/zararın hesaba dahil olur.'**
  String get deleteAssetWarning;

  /// No description provided for @alarmAlsoDeleteTitle.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{Alarm da silinsin mi?} other{{n} alarm da silinsin mi?}}'**
  String alarmAlsoDeleteTitle(int n);

  /// No description provided for @alarmAlsoDeleteBody.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{{name} silindi. Bu sembol için kurduğun alarm duruyor. Portföyünde olmasa da fiyatı izlemeye devam edebilir.} other{{name} silindi. Bu sembol için kurduğun {n} alarm duruyor. Portföyünde olmasa da fiyatı izlemeye devam edebilirler.}}'**
  String alarmAlsoDeleteBody(int n, String name);

  /// No description provided for @alarmAlsoDeleteConfirm.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{Alarmı sil} other{Alarmları sil}}'**
  String alarmAlsoDeleteConfirm(int n);

  /// No description provided for @alarmKeep.
  ///
  /// In tr, this message translates to:
  /// **'Alarm kalsın'**
  String get alarmKeep;

  /// No description provided for @alarmDeleteFailed.
  ///
  /// In tr, this message translates to:
  /// **'Alarmlar silinemedi'**
  String get alarmDeleteFailed;

  /// No description provided for @assetDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Varlık silindi'**
  String get assetDeleted;

  /// No description provided for @undoFailed.
  ///
  /// In tr, this message translates to:
  /// **'Geri alınamadı'**
  String get undoFailed;

  /// No description provided for @enterValidAmount.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir tutar girin'**
  String get enterValidAmount;

  /// No description provided for @dividendSaved.
  ///
  /// In tr, this message translates to:
  /// **'Temettü kaydedildi'**
  String get dividendSaved;

  /// No description provided for @dividendPayDate.
  ///
  /// In tr, this message translates to:
  /// **'Temettü ödeme tarihi'**
  String get dividendPayDate;

  /// No description provided for @addDividend.
  ///
  /// In tr, this message translates to:
  /// **'Temettü Ekle'**
  String get addDividend;

  /// No description provided for @netAmountReceived.
  ///
  /// In tr, this message translates to:
  /// **'{name} · ele geçen net tutar'**
  String netAmountReceived(String name);

  /// No description provided for @paymentDate.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme tarihi: {date}'**
  String paymentDate(String date);

  /// No description provided for @dividendNote.
  ///
  /// In tr, this message translates to:
  /// **'Temettü miktarı değiştirmez; toplam getirine eklenir.'**
  String get dividendNote;

  /// No description provided for @enterValidQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir miktar gir'**
  String get enterValidQuantity;

  /// No description provided for @enterValidUnitPrice.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir birim fiyat gir'**
  String get enterValidUnitPrice;

  /// No description provided for @cannotExceedQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut miktarı ({qty}) aşamazsın'**
  String cannotExceedQuantity(String qty);

  /// No description provided for @boughtAmount.
  ///
  /// In tr, this message translates to:
  /// **'{qty} {unit} alındı'**
  String boughtAmount(String qty, String unit);

  /// No description provided for @soldAmount.
  ///
  /// In tr, this message translates to:
  /// **'{qty} {unit} satıldı'**
  String soldAmount(String qty, String unit);

  /// No description provided for @transactionFailed.
  ///
  /// In tr, this message translates to:
  /// **'İşlem başarısız. {error}'**
  String transactionFailed(String error);

  /// No description provided for @sellAllWarning.
  ///
  /// In tr, this message translates to:
  /// **'Tüm miktarı satıyorsun — pozisyon listeden kalkar ama bu bir satış kaydı olarak durur. İşlem geçmişin ve realize kâr/zararın korunur. Kaydı tamamen silmek istiyorsan varlık detayından \"Sil\"i kullan.'**
  String get sellAllWarning;

  /// No description provided for @saleValue.
  ///
  /// In tr, this message translates to:
  /// **'Satış değeri'**
  String get saleValue;

  /// No description provided for @noPriceAlert.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmı yok'**
  String get noPriceAlert;

  /// No description provided for @nActiveAlerts.
  ///
  /// In tr, this message translates to:
  /// **'{n} aktif fiyat alarmı'**
  String nActiveAlerts(int n);

  /// No description provided for @deleteAlertTitle.
  ///
  /// In tr, this message translates to:
  /// **'Alarmı sil'**
  String get deleteAlertTitle;

  /// No description provided for @deleteAlertAbove.
  ///
  /// In tr, this message translates to:
  /// **'{price} üstüne çıkınca alarmı silinsin mi?'**
  String deleteAlertAbove(String price);

  /// No description provided for @triggeredAlertSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Çalışmış alarm {price}, yeniden kurmak için dokun'**
  String triggeredAlertSemantics(String price);

  /// No description provided for @alertAboveSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Üstüne çıkınca {price}, silmek için dokun'**
  String alertAboveSemantics(String price);

  /// No description provided for @alertTriggered.
  ///
  /// In tr, this message translates to:
  /// **'{price} · çalıştı'**
  String alertTriggered(String price);

  /// No description provided for @deleteAlertBelow.
  ///
  /// In tr, this message translates to:
  /// **'{price} altına inince alarmı silinsin mi?'**
  String deleteAlertBelow(String price);

  /// No description provided for @alertBelowSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Altına inince {price}, silmek için dokun'**
  String alertBelowSemantics(String price);

  /// No description provided for @addAssetFirst.
  ///
  /// In tr, this message translates to:
  /// **'Önce portföyüne ya da takip listene bir varlık ekle.'**
  String get addAssetFirst;

  /// No description provided for @alertSetAbove.
  ///
  /// In tr, this message translates to:
  /// **'{name} için alarm kuruldu: {price} üstüne çıkınca'**
  String alertSetAbove(String name, String price);

  /// No description provided for @alertSetFailed.
  ///
  /// In tr, this message translates to:
  /// **'Alarm kurulamadı'**
  String get alertSetFailed;

  /// No description provided for @enterValidPrice.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir fiyat gir'**
  String get enterValidPrice;

  /// No description provided for @alertForAsset.
  ///
  /// In tr, this message translates to:
  /// **'{name} için alarm'**
  String alertForAsset(String name);

  /// No description provided for @currentlyPrice.
  ///
  /// In tr, this message translates to:
  /// **'Şu an {price}'**
  String currentlyPrice(String price);

  /// No description provided for @currentPriceUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Güncel fiyat bilinmiyor'**
  String get currentPriceUnknown;

  /// No description provided for @targetPctSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Hedef yüzde {sign} {pct}'**
  String targetPctSemantics(String sign, int pct);

  /// No description provided for @notifyWhenAbove.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat bu seviyeye çıkınca haber vereceğiz.'**
  String get notifyWhenAbove;

  /// No description provided for @notifyWhenBelow.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat bu seviyeye inince haber vereceğiz.'**
  String get notifyWhenBelow;

  /// No description provided for @setAlert.
  ///
  /// In tr, this message translates to:
  /// **'Alarmı kur'**
  String get setAlert;

  /// No description provided for @alertSetBelow.
  ///
  /// In tr, this message translates to:
  /// **'{name} için alarm kuruldu: {price} altına inince'**
  String alertSetBelow(String name, String price);

  /// No description provided for @plusWord.
  ///
  /// In tr, this message translates to:
  /// **'artı'**
  String get plusWord;

  /// No description provided for @minusWord.
  ///
  /// In tr, this message translates to:
  /// **'eksi'**
  String get minusWord;

  /// No description provided for @widgetStepHold.
  ///
  /// In tr, this message translates to:
  /// **'Ana ekranda boş bir yere basılı tut'**
  String get widgetStepHold;

  /// No description provided for @widgetStepPlus.
  ///
  /// In tr, this message translates to:
  /// **'Sol üstteki + işaretine dokun'**
  String get widgetStepPlus;

  /// No description provided for @widgetStepPickIos.
  ///
  /// In tr, this message translates to:
  /// **'Listeden \"sandık\"ı seç ve ekle'**
  String get widgetStepPickIos;

  /// No description provided for @widgetStepPickAndroid.
  ///
  /// In tr, this message translates to:
  /// **'\"sandık\"ı bulup ana ekrana sürükle'**
  String get widgetStepPickAndroid;

  /// No description provided for @widgetInstallTitle.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünü ana ekranda gör'**
  String get widgetInstallTitle;

  /// No description provided for @widgetInstallBody.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı açmadan toplamını ve günlük değişimini görürsün.'**
  String get widgetInstallBody;

  /// No description provided for @gotIt.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get gotIt;

  /// No description provided for @widgetStepWidgetsTab.
  ///
  /// In tr, this message translates to:
  /// **'\"Widget\'lar\"a dokun'**
  String get widgetStepWidgetsTab;

  /// No description provided for @disclaimerText.
  ///
  /// In tr, this message translates to:
  /// **'Bu uygulama yalnızca bilgilendirme amaçlıdır. Gösterilen veriler, analizler ve bildirimler kesinlikle yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık niteliği taşımaz. Yatırım kararlarınızı yetkili bir mali danışmana danışarak veriniz. Geçmiş performans gelecekteki sonuçları garanti etmez.'**
  String get disclaimerText;

  /// No description provided for @justNow.
  ///
  /// In tr, this message translates to:
  /// **'az önce'**
  String get justNow;

  /// No description provided for @minutesAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n} dk önce'**
  String minutesAgo(int n);

  /// No description provided for @hoursAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n} sa önce'**
  String hoursAgo(int n);

  /// No description provided for @daysAgo.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün önce'**
  String daysAgo(int n);

  /// No description provided for @signalCalculating.
  ///
  /// In tr, this message translates to:
  /// **'Sinyal hesaplanıyor…'**
  String get signalCalculating;

  /// No description provided for @trendUp.
  ///
  /// In tr, this message translates to:
  /// **'YUKARI TREND'**
  String get trendUp;

  /// No description provided for @trendDown.
  ///
  /// In tr, this message translates to:
  /// **'AŞAĞI TREND'**
  String get trendDown;

  /// No description provided for @trendFlat.
  ///
  /// In tr, this message translates to:
  /// **'YATAY'**
  String get trendFlat;

  /// No description provided for @indicatorsConfidence.
  ///
  /// In tr, this message translates to:
  /// **'{lehte}/{total} gösterge · güven %{pct}'**
  String indicatorsConfidence(int lehte, int total, int pct);

  /// No description provided for @confidenceOnly.
  ///
  /// In tr, this message translates to:
  /// **'güven %{pct}'**
  String confidenceOnly(int pct);

  /// No description provided for @technicalOutlookUpper.
  ///
  /// In tr, this message translates to:
  /// **'TEKNİK GÖRÜNÜM'**
  String get technicalOutlookUpper;

  /// No description provided for @nowUpper.
  ///
  /// In tr, this message translates to:
  /// **'ŞU AN'**
  String get nowUpper;

  /// No description provided for @arrowUp.
  ///
  /// In tr, this message translates to:
  /// **'▲ yukarı'**
  String get arrowUp;

  /// No description provided for @arrowDown.
  ///
  /// In tr, this message translates to:
  /// **'▼ aşağı'**
  String get arrowDown;

  /// No description provided for @arrowFlat.
  ///
  /// In tr, this message translates to:
  /// **'◆ yatay'**
  String get arrowFlat;

  /// No description provided for @indicatorsCalculating.
  ///
  /// In tr, this message translates to:
  /// **'Göstergeler hesaplanıyor…'**
  String get indicatorsCalculating;

  /// No description provided for @indicatorsNoHistory.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlığın fiyat geçmişi şu an çekilemedi — göstergeler hesaplanamıyor.'**
  String get indicatorsNoHistory;

  /// No description provided for @noIndicatorsSelected.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık türü için hiçbir gösterge seçilmemiş. Profil → Sinyal Ayarları\'ndan aktifleştir.'**
  String get noIndicatorsSelected;

  /// No description provided for @technicalAnalysisUpper.
  ///
  /// In tr, this message translates to:
  /// **'TEKNİK ANALİZ'**
  String get technicalAnalysisUpper;

  /// No description provided for @nOfMIndicators.
  ///
  /// In tr, this message translates to:
  /// **'· {on}/{all} gösterge'**
  String nOfMIndicators(int on, int all);

  /// No description provided for @configureIndicators.
  ///
  /// In tr, this message translates to:
  /// **'Göstergeleri Ayarla'**
  String get configureIndicators;

  /// No description provided for @buySellNeutralCounts.
  ///
  /// In tr, this message translates to:
  /// **'{buy} AL · {sell} SAT · {neutral} NÖTR'**
  String buySellNeutralCounts(int buy, int sell, int neutral);

  /// No description provided for @confidenceWord.
  ///
  /// In tr, this message translates to:
  /// **'güven'**
  String get confidenceWord;

  /// No description provided for @csvRowsAddedToCart.
  ///
  /// In tr, this message translates to:
  /// **'{n} satır sepete eklendi'**
  String csvRowsAddedToCart(int n);

  /// No description provided for @csvImportTitle.
  ///
  /// In tr, this message translates to:
  /// **'CSV ile içe aktar'**
  String get csvImportTitle;

  /// No description provided for @csvImportBody.
  ///
  /// In tr, this message translates to:
  /// **'Aracı kurum ekstresini ya da Excel tablosunu kopyalayıp yapıştır. Başlık satırı olsun; sütun sırası önemli değil.'**
  String get csvImportBody;

  /// No description provided for @pasteHere.
  ///
  /// In tr, this message translates to:
  /// **'Buraya yapıştır'**
  String get pasteHere;

  /// No description provided for @preview.
  ///
  /// In tr, this message translates to:
  /// **'Önizle'**
  String get preview;

  /// No description provided for @csvRowsRead.
  ///
  /// In tr, this message translates to:
  /// **'{n} satır okundu'**
  String csvRowsRead(int n);

  /// No description provided for @csvRowsSkipped.
  ///
  /// In tr, this message translates to:
  /// **', {n} satır atlandı'**
  String csvRowsSkipped(int n);

  /// No description provided for @closePriceWillBeFetched.
  ///
  /// In tr, this message translates to:
  /// **'kapanış çekilecek'**
  String get closePriceWillBeFetched;

  /// No description provided for @unitPiece.
  ///
  /// In tr, this message translates to:
  /// **'adet'**
  String get unitPiece;

  /// No description provided for @assetLimitReachedFor.
  ///
  /// In tr, this message translates to:
  /// **'{name}: varlık limitine ulaşıldı'**
  String assetLimitReachedFor(String name);

  /// No description provided for @someAssetsNotAdded.
  ///
  /// In tr, this message translates to:
  /// **'Bazı Varlıklar Eklenemedi'**
  String get someAssetsNotAdded;

  /// No description provided for @clearCartConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Sepetteki tüm varlıklar silinecek. Emin misin?'**
  String get clearCartConfirm;

  /// No description provided for @pasteCsv.
  ///
  /// In tr, this message translates to:
  /// **'CSV yapıştır'**
  String get pasteCsv;

  /// No description provided for @cartEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Sepet boş'**
  String get cartEmpty;

  /// No description provided for @cartEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Aşağıdaki + Varlık Ekle butonuyla art arda varlık ekleyip hepsini tek seferde kaydedebilirsin.'**
  String get cartEmptyBody;

  /// No description provided for @pasteFromStatement.
  ///
  /// In tr, this message translates to:
  /// **'Ekstreden / CSV\'den yapıştır'**
  String get pasteFromStatement;

  /// No description provided for @saveAllCount.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü Kaydet ({n})'**
  String saveAllCount(int n);

  /// No description provided for @removeFromWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'Takipten çıkar'**
  String get removeFromWatchlist;

  /// No description provided for @removeFromWatchlistConfirm.
  ///
  /// In tr, this message translates to:
  /// **'{name} takip listenden kaldırılsın mı?'**
  String removeFromWatchlistConfirm(String name);

  /// No description provided for @removeWord2.
  ///
  /// In tr, this message translates to:
  /// **'Çıkar'**
  String get removeWord2;

  /// No description provided for @removeFromWatchlistFailed.
  ///
  /// In tr, this message translates to:
  /// **'Takipten çıkarılamadı. Bağlantını kontrol et.'**
  String get removeFromWatchlistFailed;

  /// No description provided for @currentPriceUpper.
  ///
  /// In tr, this message translates to:
  /// **'GÜNCEL FİYAT'**
  String get currentPriceUpper;

  /// No description provided for @periodNoChange.
  ///
  /// In tr, this message translates to:
  /// **'{period} · değişim yok'**
  String periodNoChange(String period);

  /// No description provided for @unitPriceDiffNote.
  ///
  /// In tr, this message translates to:
  /// **'Değişim birim fiyat farkıdır — bu varlığa sahip değilsin.'**
  String get unitPriceDiffNote;

  /// No description provided for @notEnoughHistoryForAsset.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık için yeterli fiyat geçmişi yok.'**
  String get notEnoughHistoryForAsset;

  /// No description provided for @notInYourPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık portföyüne dahil değildir.'**
  String get notInYourPortfolio;

  /// No description provided for @searchingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Aranıyor…'**
  String get searchingEllipsis;

  /// No description provided for @startTypingToSearch.
  ///
  /// In tr, this message translates to:
  /// **'Aramak için yazmaya başla.'**
  String get startTypingToSearch;

  /// No description provided for @noResultForQuery.
  ///
  /// In tr, this message translates to:
  /// **'\"{q}\" için sonuç yok.'**
  String noResultForQuery(String q);

  /// No description provided for @inYourPortfolioUpper.
  ///
  /// In tr, this message translates to:
  /// **'PORTFÖYÜNDE'**
  String get inYourPortfolioUpper;

  /// No description provided for @searchAllAssetsHint.
  ///
  /// In tr, this message translates to:
  /// **'Hisse, fon, endeks, emtia, döviz veya altın ara'**
  String get searchAllAssetsHint;

  /// No description provided for @alreadyInPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'{name}, zaten portföyünde'**
  String alreadyInPortfolio(String name);

  /// No description provided for @addedToWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'{name} takibe alındı'**
  String addedToWatchlist(String name);

  /// No description provided for @watchlistLimitFree.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz planda en fazla {n} varlık takip edebilirsin.'**
  String watchlistLimitFree(int n);

  /// No description provided for @partnershipAcceptedShort.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık kabul edildi.'**
  String get partnershipAcceptedShort;

  /// No description provided for @partnershipRejectedShort.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık isteği reddedildi.'**
  String get partnershipRejectedShort;

  /// No description provided for @partnershipApprovalTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık Onayı'**
  String get partnershipApprovalTitle;

  /// No description provided for @partnershipApprovalBody.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık kodunu giren kişileri buradan görüp onaylayabilirsin.'**
  String get partnershipApprovalBody;

  /// No description provided for @noPendingRequests.
  ///
  /// In tr, this message translates to:
  /// **'Bekleyen ortaklık isteği yok.'**
  String get noPendingRequests;

  /// No description provided for @userWord.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı'**
  String get userWord;

  /// No description provided for @enteredYourCode.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklık kodunuzu girdi ve onay bekliyor.'**
  String get enteredYourCode;

  /// No description provided for @portfolioChange.
  ///
  /// In tr, this message translates to:
  /// **'Portföy değişimi'**
  String get portfolioChange;

  /// No description provided for @aheadOfInflationPts.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyonun {pts} puan önünde'**
  String aheadOfInflationPts(String pts);

  /// No description provided for @betterThanPctInvestors.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcıların %{pct}\'inden iyi'**
  String betterThanPctInvestors(int pct);

  /// No description provided for @nDaysTracked.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün takip'**
  String nDaysTracked(int n);

  /// No description provided for @trackingWithSandik.
  ///
  /// In tr, this message translates to:
  /// **'sandık ile takip ediyorum'**
  String get trackingWithSandik;

  /// No description provided for @shareCardNoAmounts.
  ///
  /// In tr, this message translates to:
  /// **'Kartta tutar yok; yalnızca yüzde ve etiketler.'**
  String get shareCardNoAmounts;

  /// No description provided for @preparingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Hazırlanıyor…'**
  String get preparingEllipsis;

  /// No description provided for @shareAsImage.
  ///
  /// In tr, this message translates to:
  /// **'Görsel olarak paylaş'**
  String get shareAsImage;

  /// No description provided for @shareAsText.
  ///
  /// In tr, this message translates to:
  /// **'Metin olarak paylaş'**
  String get shareAsText;

  /// No description provided for @behindInflationPts.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyonun {pts} puan gerisinde'**
  String behindInflationPts(String pts);

  /// No description provided for @assetNotFound.
  ///
  /// In tr, this message translates to:
  /// **'Varlık bulunamadı'**
  String get assetNotFound;

  /// No description provided for @myMarketReturn.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa getirim'**
  String get myMarketReturn;

  /// No description provided for @dataExported.
  ///
  /// In tr, this message translates to:
  /// **'Verilerin JSON dosyası olarak hazırlandı ve paylaşıldı.'**
  String get dataExported;

  /// No description provided for @mailAppFailed.
  ///
  /// In tr, this message translates to:
  /// **'Mail uygulaması açılamadı. Lütfen {email} adresine yaz.'**
  String mailAppFailed(String email);

  /// No description provided for @notifSubtitleIos.
  ///
  /// In tr, this message translates to:
  /// **'Sinyaller, fiyat alarmları, sessiz saatler, Canlı Etkinlik'**
  String get notifSubtitleIos;

  /// No description provided for @notifSubtitleAndroid.
  ///
  /// In tr, this message translates to:
  /// **'Sinyaller, fiyat alarmları, sessiz saatler'**
  String get notifSubtitleAndroid;

  /// No description provided for @alertSetFromAssetScreen.
  ///
  /// In tr, this message translates to:
  /// **'Varlık ekranındaki zil ile kurulur'**
  String get alertSetFromAssetScreen;

  /// No description provided for @noBiometricOnDevice.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazda biyometrik doğrulama ya da PIN tanımlı değil.'**
  String get noBiometricOnDevice;

  /// No description provided for @biometricPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Biyometrik kilidi açmak için kimliğini doğrula'**
  String get biometricPrompt;

  /// No description provided for @rateNotFetched.
  ///
  /// In tr, this message translates to:
  /// **'Kur henüz çekilmedi; tutarlar şimdilik ₺ görünür.'**
  String get rateNotFetched;

  /// No description provided for @baseCurrencyNote.
  ///
  /// In tr, this message translates to:
  /// **'Tutarlar bugünkü kurla {unit} cinsinden gösterilir; hesaplar ₺ üzerinden yapılır.'**
  String baseCurrencyNote(String unit);

  /// No description provided for @startHour.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç saati'**
  String get startHour;

  /// No description provided for @endHour.
  ///
  /// In tr, this message translates to:
  /// **'Bitiş saati'**
  String get endHour;

  /// No description provided for @liveActivityIosNote.
  ///
  /// In tr, this message translates to:
  /// **'iOS, Live Activity oturumunu en fazla 8 saat açık tutar. Uygulamayı açtıkça süre yenilenir; hiç açmazsanız kilit ekranından düşebilir.'**
  String get liveActivityIosNote;

  /// No description provided for @marketClosedNote.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa kapalıyken son kapanış gösterilir.'**
  String get marketClosedNote;

  /// No description provided for @hiddenWeekend.
  ///
  /// In tr, this message translates to:
  /// **'Şu an görünmüyor: hafta sonu gösterimi kapalı. Açmak için yukarıdaki anahtarı kullanın.'**
  String get hiddenWeekend;

  /// No description provided for @hiddenOutsideWindow.
  ///
  /// In tr, this message translates to:
  /// **'Şu an görünmüyor: saat {start}–{end} aralığının dışındasınız. Banner {start}\'da görünecek. Hemen görmek için \"Gün boyu göster\"i açın.'**
  String hiddenOutsideWindow(String start, String end);

  /// No description provided for @quietStart.
  ///
  /// In tr, this message translates to:
  /// **'Sessizlik başlangıcı'**
  String get quietStart;

  /// No description provided for @quietEnd.
  ///
  /// In tr, this message translates to:
  /// **'Sessizlik bitişi'**
  String get quietEnd;

  /// No description provided for @quietHoursOn.
  ///
  /// In tr, this message translates to:
  /// **'Brifing, özet, takvim ve alarm push\'ları {start}–{end} arası gönderilmez'**
  String quietHoursOn(String start, String end);

  /// No description provided for @quietHoursOff.
  ///
  /// In tr, this message translates to:
  /// **'Gece belirli saatlerde hiçbir proaktif bildirim gelmesin'**
  String get quietHoursOff;

  /// No description provided for @passwordLabel.
  ///
  /// In tr, this message translates to:
  /// **'Şifre'**
  String get passwordLabel;

  /// No description provided for @aheadOfInflationPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönem enflasyonun {pts} puan önünde.'**
  String aheadOfInflationPeriod(String pts);

  /// No description provided for @realReturnPositive.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün enflasyonun üzerinde reel getiri sağladı — alım gücün arttı.'**
  String get realReturnPositive;

  /// No description provided for @percentileSentence.
  ///
  /// In tr, this message translates to:
  /// **'Katılımcıların %{pct} kadarının üstündesin.'**
  String percentileSentence(int pct);

  /// No description provided for @noDrawdown.
  ///
  /// In tr, this message translates to:
  /// **'Bu pencerede portföyün zirvesinden gerilemedi.'**
  String get noDrawdown;

  /// No description provided for @concentrationBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünün %{pct}\'i {label} içinde; toplam {n} pozisyonun var.{tail}'**
  String concentrationBody(String pct, String label, int n, String tail);

  /// No description provided for @riskAdjustedReturn.
  ///
  /// In tr, this message translates to:
  /// **'Risk-ayarlı getiri'**
  String get riskAdjustedReturn;

  /// No description provided for @riskAdjustedBody.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık getiri ÷ yıllık oynaklık. Sharpe oranının risksiz oransız hâli: aldığın her birim dalgalanma için kaç puan getiri.'**
  String get riskAdjustedBody;

  /// No description provided for @timingEffectBody.
  ///
  /// In tr, this message translates to:
  /// **'Paranın getirisi (XIRR) − piyasa getirisi. Pozitifse alım tarihlerin piyasayı yendi; negatifse pahalıya girmişsin.'**
  String get timingEffectBody;

  /// No description provided for @recoveryDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün'**
  String recoveryDays(int n);

  /// No description provided for @recoveryBody.
  ///
  /// In tr, this message translates to:
  /// **'En büyük düşüşün dibinden eski zirveye dönüş süresi.'**
  String get recoveryBody;

  /// No description provided for @notYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz yok'**
  String get notYet;

  /// No description provided for @notRecoveredBody.
  ///
  /// In tr, this message translates to:
  /// **'En büyük düşüşün ardından eski zirveye henüz dönülmedi.'**
  String get notRecoveredBody;

  /// No description provided for @timingEffect.
  ///
  /// In tr, this message translates to:
  /// **'Zamanlama etkisi'**
  String get timingEffect;

  /// No description provided for @recoveryWord.
  ///
  /// In tr, this message translates to:
  /// **'Toparlanma'**
  String get recoveryWord;

  /// No description provided for @intradayWord.
  ///
  /// In tr, this message translates to:
  /// **'Gün içi'**
  String get intradayWord;

  /// No description provided for @todayWord.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get todayWord;

  /// No description provided for @nowWord.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi'**
  String get nowWord;

  /// No description provided for @behindInflationPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönem enflasyonun {pts} puan gerisinde.'**
  String behindInflationPeriod(String pts);

  /// No description provided for @realReturnNegative.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün enflasyonun altında kaldı — alım gücün geriledi.'**
  String get realReturnNegative;

  /// No description provided for @nPeopleParen.
  ///
  /// In tr, this message translates to:
  /// **'({n} kişi)'**
  String nPeopleParen(int n);

  /// No description provided for @recoveredInDays.
  ///
  /// In tr, this message translates to:
  /// **' ve {n} günde toparladı'**
  String recoveredInDays(int n);

  /// No description provided for @notRecoveredYet.
  ///
  /// In tr, this message translates to:
  /// **' ve henüz o seviyeye dönmedi'**
  String get notRecoveredYet;

  /// No description provided for @singleAssetHeavy.
  ///
  /// In tr, this message translates to:
  /// **'Tek varlığın hareketi portföyünü belirgin etkiler.'**
  String get singleAssetHeavy;

  /// No description provided for @drawdownBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün, gördüğü en yüksek seviyeden en fazla %{pct} geriledi{tail}.'**
  String drawdownBody(String pct, String tail);

  /// No description provided for @rangeAllTime.
  ///
  /// In tr, this message translates to:
  /// **'Tüm zamanlar'**
  String get rangeAllTime;

  /// No description provided for @rangeLast7.
  ///
  /// In tr, this message translates to:
  /// **'Son 7 gün'**
  String get rangeLast7;

  /// No description provided for @rangeLast30.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 gün'**
  String get rangeLast30;

  /// No description provided for @rangeLast90.
  ///
  /// In tr, this message translates to:
  /// **'Son 90 gün'**
  String get rangeLast90;

  /// No description provided for @rangeThisYear.
  ///
  /// In tr, this message translates to:
  /// **'Bu yıl'**
  String get rangeThisYear;

  /// No description provided for @rangeCustom.
  ///
  /// In tr, this message translates to:
  /// **'Özel'**
  String get rangeCustom;

  /// No description provided for @searchAssetOrSymbol.
  ///
  /// In tr, this message translates to:
  /// **'Varlık adı veya sembol ara'**
  String get searchAssetOrSymbol;

  /// No description provided for @noRecords.
  ///
  /// In tr, this message translates to:
  /// **'Kayıt yok'**
  String get noRecords;

  /// No description provided for @nRecords.
  ///
  /// In tr, this message translates to:
  /// **'{n} kayıt'**
  String nRecords(int n);

  /// No description provided for @nShown.
  ///
  /// In tr, this message translates to:
  /// **' · {n} gösteriliyor'**
  String nShown(int n);

  /// No description provided for @noMatchingRecords.
  ///
  /// In tr, this message translates to:
  /// **'Filtreye uyan kayıt yok'**
  String get noMatchingRecords;

  /// No description provided for @noTransactionsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz işlem yok'**
  String get noTransactionsYet;

  /// No description provided for @todaysBalanceChange.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü birikim değişimi'**
  String get todaysBalanceChange;

  /// No description provided for @sinceDateToToday.
  ///
  /// In tr, this message translates to:
  /// **'{date} → bugün'**
  String sinceDateToToday(String date);

  /// No description provided for @balanceChangeSince.
  ///
  /// In tr, this message translates to:
  /// **'{date} birikim değişimi'**
  String balanceChangeSince(String date);

  /// No description provided for @periodChangeSim.
  ///
  /// In tr, this message translates to:
  /// **'{period} değişim · simülasyon'**
  String periodChangeSim(String period);

  /// No description provided for @periodBalanceChange.
  ///
  /// In tr, this message translates to:
  /// **'{period} birikim değişimi'**
  String periodBalanceChange(String period);

  /// No description provided for @inflowIncludedNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönemde {amount} tutarında alım yapıldı ve yukarıdaki rakam bunu İÇERİR. Yalnızca piyasa hareketi: {market}.'**
  String inflowIncludedNote(String amount, String market);

  /// No description provided for @outflowIncludedNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönemde {amount} tutarında satış yapıldı ve yukarıdaki rakam bunu İÇERİR. Yalnızca piyasa hareketi: {market}.'**
  String outflowIncludedNote(String amount, String market);

  /// No description provided for @rowExpandedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{label}, açık. Kapatmak için çift dokun.'**
  String rowExpandedSemantics(String label);

  /// No description provided for @gainAmount.
  ///
  /// In tr, this message translates to:
  /// **'kazanç {amount}'**
  String gainAmount(String amount);

  /// No description provided for @flowBuyLower.
  ///
  /// In tr, this message translates to:
  /// **'dönem içi alım {amount}'**
  String flowBuyLower(String amount);

  /// No description provided for @rowCollapsedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{label}, kapalı. İçindeki ürünleri görmek için çift dokun.'**
  String rowCollapsedSemantics(String label);

  /// No description provided for @lossAmount.
  ///
  /// In tr, this message translates to:
  /// **'kayıp {amount}'**
  String lossAmount(String amount);

  /// No description provided for @flowSellLower.
  ///
  /// In tr, this message translates to:
  /// **'dönem içi satış {amount}'**
  String flowSellLower(String amount);

  /// No description provided for @flowSellUpper.
  ///
  /// In tr, this message translates to:
  /// **'Dönem içi satış {amount}'**
  String flowSellUpper(String amount);

  /// No description provided for @flowBuyUpper.
  ///
  /// In tr, this message translates to:
  /// **'Dönem içi alım {amount}'**
  String flowBuyUpper(String amount);

  /// No description provided for @raceFooterGlobal.
  ///
  /// In tr, this message translates to:
  /// **'Getiri, seçili dönemin başı ile sonu karşılaştırılarak hesaplanır. Sıralamalar ve dağılımlar anonimdir — kimlik, miktar ve TL bilgisi asla paylaşılmaz.'**
  String get raceFooterGlobal;

  /// No description provided for @calculatingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Hesaplanıyor…'**
  String get calculatingEllipsis;

  /// No description provided for @nThousandPeople.
  ///
  /// In tr, this message translates to:
  /// **'{n}K KİŞİ'**
  String nThousandPeople(String n);

  /// No description provided for @nPeopleUpper.
  ///
  /// In tr, this message translates to:
  /// **'{n} KİŞİ'**
  String nPeopleUpper(int n);

  /// No description provided for @toneTop5.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedeki azınlıktasın'**
  String get toneTop5;

  /// No description provided for @toneTop10.
  ///
  /// In tr, this message translates to:
  /// **'Sandık\'ın en iyi %10\'undasın'**
  String get toneTop10;

  /// No description provided for @toneTop25.
  ///
  /// In tr, this message translates to:
  /// **'Ortalamanın çok üstündesin'**
  String get toneTop25;

  /// No description provided for @toneTop50.
  ///
  /// In tr, this message translates to:
  /// **'Ortalamanın üstündesin'**
  String get toneTop50;

  /// No description provided for @toneTop75.
  ///
  /// In tr, this message translates to:
  /// **'Ortalamaya yakınsın'**
  String get toneTop75;

  /// No description provided for @toneRest.
  ///
  /// In tr, this message translates to:
  /// **'Daha iyisini yapabilirsin — 30G takip et'**
  String get toneRest;

  /// No description provided for @raceFooterPartners.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama, seçili dönemin getirisidir (%). Herkes aynı formülle ölçülür; kimsenin varlık listesi görünmez.'**
  String get raceFooterPartners;

  /// No description provided for @recapYourPortfolio.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün'**
  String get recapYourPortfolio;

  /// No description provided for @recapGrewThisYear.
  ///
  /// In tr, this message translates to:
  /// **'Bu yıl böyle büyüdün.'**
  String get recapGrewThisYear;

  /// No description provided for @recapToughYear.
  ///
  /// In tr, this message translates to:
  /// **'Zor bir yıl oldu.'**
  String get recapToughYear;

  /// No description provided for @recapVsInflation.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyona karşı · son 12 ay'**
  String get recapVsInflation;

  /// No description provided for @recapKeptPower.
  ///
  /// In tr, this message translates to:
  /// **'Alım gücünü korudun ve üstüne koydun.'**
  String get recapKeptPower;

  /// No description provided for @recapInflationWon.
  ///
  /// In tr, this message translates to:
  /// **'Son 12 ayda enflasyon öndeydi.'**
  String get recapInflationWon;

  /// Yil sonu ozetinde enflasyon karsilastirmasinin gercek pencere uclari
  ///
  /// In tr, this message translates to:
  /// **'Ölçüm: {start} – {end} (TÜFE aylık yayımlandığı için pencere son açıklanan ayda biter)'**
  String recapInflationWindow(String start, String end);

  /// No description provided for @recapBestAsset.
  ///
  /// In tr, this message translates to:
  /// **'En çok kazandıran'**
  String get recapBestAsset;

  /// No description provided for @recapReturnedPct.
  ///
  /// In tr, this message translates to:
  /// **'Bugüne kadar %{pct} getirdi.'**
  String recapReturnedPct(String pct);

  /// No description provided for @recapMostPatient.
  ///
  /// In tr, this message translates to:
  /// **'En sabırlı olduğun'**
  String get recapMostPatient;

  /// No description provided for @recapInPortfolioDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gündür portföyünde.'**
  String recapInPortfolioDays(int n);

  /// No description provided for @recapTypeCount.
  ///
  /// In tr, this message translates to:
  /// **'{n} türde varlık ile.'**
  String recapTypeCount(int n);

  /// No description provided for @recapForAYear.
  ///
  /// In tr, this message translates to:
  /// **'Bir yıl boyunca.'**
  String get recapForAYear;

  /// No description provided for @recapShareTitle.
  ///
  /// In tr, this message translates to:
  /// **'sandık Özetim {year}'**
  String recapShareTitle(int year);

  /// No description provided for @shareWord.
  ///
  /// In tr, this message translates to:
  /// **'Paylaş'**
  String get shareWord;

  /// No description provided for @scopeTogether.
  ///
  /// In tr, this message translates to:
  /// **'Birlikte'**
  String get scopeTogether;

  /// No description provided for @scopeMe.
  ///
  /// In tr, this message translates to:
  /// **'Ben'**
  String get scopeMe;

  /// No description provided for @scopeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kapsam'**
  String get scopeLabel;

  /// No description provided for @scopeWho.
  ///
  /// In tr, this message translates to:
  /// **'Kimin portföyü'**
  String get scopeWho;

  /// No description provided for @scopePartners.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklar'**
  String get scopePartners;

  /// No description provided for @chartTypeTooltip.
  ///
  /// In tr, this message translates to:
  /// **'Grafik tipi'**
  String get chartTypeTooltip;

  /// No description provided for @fullscreenChart.
  ///
  /// In tr, this message translates to:
  /// **'Grafiği tam ekran aç'**
  String get fullscreenChart;

  /// No description provided for @whatsNewTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yenilikler'**
  String get whatsNewTitle;

  /// No description provided for @whatsNewSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürümde neler değişti'**
  String get whatsNewSubtitle;

  /// No description provided for @whatsNewEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Bu sürüm için not yok.'**
  String get whatsNewEmpty;

  /// No description provided for @appVersionLabel.
  ///
  /// In tr, this message translates to:
  /// **'sandık — sürüm {surum}'**
  String appVersionLabel(String surum);

  /// No description provided for @shareCardBest.
  ///
  /// In tr, this message translates to:
  /// **'En iyi'**
  String get shareCardBest;

  /// No description provided for @shareCardWorst.
  ///
  /// In tr, this message translates to:
  /// **'En zayıf'**
  String get shareCardWorst;

  /// No description provided for @shareCardUpDays.
  ///
  /// In tr, this message translates to:
  /// **'Artıda gün'**
  String get shareCardUpDays;

  /// No description provided for @shareCardUpDaysValue.
  ///
  /// In tr, this message translates to:
  /// **'{up}/{total}'**
  String shareCardUpDaysValue(int up, int total);

  /// No description provided for @shareCardReal.
  ///
  /// In tr, this message translates to:
  /// **'reel {pct}'**
  String shareCardReal(String pct);

  /// No description provided for @shareCardXirr.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık (XIRR)'**
  String get shareCardXirr;

  /// No description provided for @shareCardDrawdown.
  ///
  /// In tr, this message translates to:
  /// **'En derin düşüş'**
  String get shareCardDrawdown;

  /// No description provided for @shareCardPatient.
  ///
  /// In tr, this message translates to:
  /// **'En sabırlı'**
  String get shareCardPatient;

  /// No description provided for @shareCardAllocation.
  ///
  /// In tr, this message translates to:
  /// **'Dağılım'**
  String get shareCardAllocation;

  /// No description provided for @shareCardTracked.
  ///
  /// In tr, this message translates to:
  /// **'Takip'**
  String get shareCardTracked;

  /// No description provided for @shareCardInvestors.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcıların'**
  String get shareCardInvestors;

  /// No description provided for @shareCardBetterThanPct.
  ///
  /// In tr, this message translates to:
  /// **'%{pct}\'inden iyi'**
  String shareCardBetterThanPct(int pct);

  /// No description provided for @shareCardRange.
  ///
  /// In tr, this message translates to:
  /// **'{start} – {end}'**
  String shareCardRange(String start, String end);

  /// No description provided for @notifTypePartner.
  ///
  /// In tr, this message translates to:
  /// **'ORTAKLIK'**
  String get notifTypePartner;

  /// No description provided for @notifTypeDailyBrief.
  ///
  /// In tr, this message translates to:
  /// **'GÜNLÜK'**
  String get notifTypeDailyBrief;

  /// No description provided for @notifTypeWeekly.
  ///
  /// In tr, this message translates to:
  /// **'HAFTALIK'**
  String get notifTypeWeekly;

  /// No description provided for @notifTypeReminder.
  ///
  /// In tr, this message translates to:
  /// **'HATIRLATMA'**
  String get notifTypeReminder;

  /// No description provided for @notifToday.
  ///
  /// In tr, this message translates to:
  /// **'Bugün {time}'**
  String notifToday(String time);

  /// No description provided for @reviewPromptTitle.
  ///
  /// In tr, this message translates to:
  /// **'sandık\'ı seviyor musun?'**
  String get reviewPromptTitle;

  /// No description provided for @reviewPromptBody.
  ///
  /// In tr, this message translates to:
  /// **'Kısa bir puan, uygulamanın daha çok yatırımcıya ulaşmasını sağlar. İstersen sonra da verebilirsin.'**
  String get reviewPromptBody;

  /// No description provided for @reviewPromptYes.
  ///
  /// In tr, this message translates to:
  /// **'Evet, değerlendir'**
  String get reviewPromptYes;

  /// No description provided for @reviewPromptLater.
  ///
  /// In tr, this message translates to:
  /// **'Sonra'**
  String get reviewPromptLater;

  /// No description provided for @reviewPromptIssue.
  ///
  /// In tr, this message translates to:
  /// **'Bir sorun var'**
  String get reviewPromptIssue;

  /// No description provided for @rateAppTitle.
  ///
  /// In tr, this message translates to:
  /// **'sandık\'ı değerlendir'**
  String get rateAppTitle;

  /// No description provided for @rateAppSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Mağazada puan ver'**
  String get rateAppSubtitle;

  /// No description provided for @todayTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get todayTitle;

  /// No description provided for @todayUp.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · %{pct} artıda'**
  String todayUp(String amount, String pct);

  /// No description provided for @todayDown.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · %{pct} eksi'**
  String todayDown(String amount, String pct);

  /// No description provided for @todayFlat.
  ///
  /// In tr, this message translates to:
  /// **'Bugün değişmedi'**
  String get todayFlat;

  /// No description provided for @todayAt.
  ///
  /// In tr, this message translates to:
  /// **'bugün {time}'**
  String todayAt(String time);

  /// No description provided for @todayMarketClosed.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa kapalı · {when} açılır'**
  String todayMarketClosed(String when);

  /// No description provided for @todayGreenShare.
  ///
  /// In tr, this message translates to:
  /// **'{green}/{total} varlığın artıda'**
  String todayGreenShare(int green, int total);

  /// No description provided for @todayGoalSet.
  ///
  /// In tr, this message translates to:
  /// **'Bir hedef belirle'**
  String get todayGoalSet;

  /// No description provided for @todayGoalSetHint.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün için bir tutar seç; ne kadar kaldığını her gün burada gör.'**
  String get todayGoalSetHint;

  /// No description provided for @todayGoalProgress.
  ///
  /// In tr, this message translates to:
  /// **'Hedefe %{pct} · {left} kaldı'**
  String todayGoalProgress(int pct, String left);

  /// No description provided for @todayGoalReached.
  ///
  /// In tr, this message translates to:
  /// **'Hedefine ulaştın: {goal}'**
  String todayGoalReached(String goal);

  /// No description provided for @todayWordToday.
  ///
  /// In tr, this message translates to:
  /// **'bugün'**
  String get todayWordToday;

  /// No description provided for @todayWordTomorrow.
  ///
  /// In tr, this message translates to:
  /// **'yarın'**
  String get todayWordTomorrow;

  /// No description provided for @todayInDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün sonra'**
  String todayInDays(int n);

  /// No description provided for @todayEventCpi.
  ///
  /// In tr, this message translates to:
  /// **'TÜİK enflasyonu {when} açıklıyor'**
  String todayEventCpi(String when);

  /// No description provided for @todayEventHoliday.
  ///
  /// In tr, this message translates to:
  /// **'Borsa {when} kapalı (resmî tatil)'**
  String todayEventHoliday(String when);

  /// No description provided for @todayEventMonthEnd.
  ///
  /// In tr, this message translates to:
  /// **'Ay {when} bitiyor; aylık özetin hazır olacak'**
  String todayEventMonthEnd(String when);

  /// No description provided for @todayMonthlySummary.
  ///
  /// In tr, this message translates to:
  /// **'{month} özetin hazır'**
  String todayMonthlySummary(String month);

  /// No description provided for @todayMonthlySummaryHint.
  ///
  /// In tr, this message translates to:
  /// **'Getirin, enflasyon farkı ve en iyi varlığın'**
  String get todayMonthlySummaryHint;

  /// No description provided for @goalTitle.
  ///
  /// In tr, this message translates to:
  /// **'Portföy hedefi'**
  String get goalTitle;

  /// No description provided for @goalHint.
  ///
  /// In tr, this message translates to:
  /// **'Yalnızca gösterim için; hesapları değiştirmez.'**
  String get goalHint;

  /// No description provided for @goalInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir tutar gir'**
  String get goalInvalid;

  /// No description provided for @goalRemove.
  ///
  /// In tr, this message translates to:
  /// **'Hedefi kaldır'**
  String get goalRemove;

  /// No description provided for @goalSettingsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Bir tutar belirle; ilerlemeyi ana ekrandaki Bugün kartında gör'**
  String get goalSettingsSubtitle;

  /// No description provided for @partnerInviteMessage.
  ///
  /// In tr, this message translates to:
  /// **'Merhaba! sandık portföy uygulamasında seninle ortak olmak istiyorum.\n\nOrtak kodun: {code}\n\nUygulamayı indir, Profil → \"Ortak Kodu Gir\" bölümünden bu kodu gir:\n{link}'**
  String partnerInviteMessage(String code, String link);

  /// No description provided for @partnerInviteSubject.
  ///
  /// In tr, this message translates to:
  /// **'sandık ortak daveti'**
  String get partnerInviteSubject;

  /// No description provided for @notifTypeMonthly.
  ///
  /// In tr, this message translates to:
  /// **'AYLIK'**
  String get notifTypeMonthly;

  /// No description provided for @raceJoinedCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi bugün yarışta · sıralama {min} kişide açılır'**
  String raceJoinedCount(int count, int min);

  /// No description provided for @raceRunningCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} kişi bugün yarışıyor'**
  String raceRunningCount(int count);

  /// No description provided for @emptyPasteHint.
  ///
  /// In tr, this message translates to:
  /// **'Aracı kurum ekstreni kopyala ve yapıştır; her satır bir varlık olur.'**
  String get emptyPasteHint;

  /// No description provided for @marketDollar.
  ///
  /// In tr, this message translates to:
  /// **'Dolar'**
  String get marketDollar;

  /// No description provided for @marketEuro.
  ///
  /// In tr, this message translates to:
  /// **'Euro'**
  String get marketEuro;

  /// No description provided for @marketGold.
  ///
  /// In tr, this message translates to:
  /// **'Gram altın'**
  String get marketGold;

  /// No description provided for @marketBist.
  ///
  /// In tr, this message translates to:
  /// **'BIST 100'**
  String get marketBist;

  /// No description provided for @notifTypeWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'TAKİP'**
  String get notifTypeWatchlist;

  /// No description provided for @notifTypeInflation.
  ///
  /// In tr, this message translates to:
  /// **'TÜFE'**
  String get notifTypeInflation;

  /// No description provided for @alarmSuggest.
  ///
  /// In tr, this message translates to:
  /// **'{name} eklendi. Fiyatı izlemek için alarm kur?'**
  String alarmSuggest(String name);

  /// No description provided for @alarmSuggestAction.
  ///
  /// In tr, this message translates to:
  /// **'Alarm kur'**
  String get alarmSuggestAction;

  /// No description provided for @briefSlotTitle.
  ///
  /// In tr, this message translates to:
  /// **'Brifing saati'**
  String get briefSlotTitle;

  /// No description provided for @briefSlotSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Portföyündeki günlük hareket özeti ne zaman gelsin'**
  String get briefSlotSubtitle;

  /// No description provided for @briefSlotMorning.
  ///
  /// In tr, this message translates to:
  /// **'Sabah 09:45'**
  String get briefSlotMorning;

  /// No description provided for @briefSlotEvening.
  ///
  /// In tr, this message translates to:
  /// **'Akşam 18:30 (kapanış)'**
  String get briefSlotEvening;

  /// No description provided for @todayRealReturnAhead.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan enflasyonun önündesin · yıllık'**
  String todayRealReturnAhead(String pts);

  /// No description provided for @todayRealReturnBehind.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan enflasyonun gerisindesin · yıllık'**
  String todayRealReturnBehind(String pts);

  /// No description provided for @todayWeeklyUp.
  ///
  /// In tr, this message translates to:
  /// **'Geçen hafta piyasadan +{pct} · özetin hazır'**
  String todayWeeklyUp(String pct);

  /// No description provided for @todayWeeklyDown.
  ///
  /// In tr, this message translates to:
  /// **'Geçen hafta piyasadan −{pct} · özetin hazır'**
  String todayWeeklyDown(String pct);

  /// No description provided for @sectionThisPeriod.
  ///
  /// In tr, this message translates to:
  /// **'BU DÖNEM'**
  String get sectionThisPeriod;

  /// No description provided for @sectionAssets.
  ///
  /// In tr, this message translates to:
  /// **'VARLIKLAR'**
  String get sectionAssets;

  /// No description provided for @sectionDepth.
  ///
  /// In tr, this message translates to:
  /// **'DERİNLİK'**
  String get sectionDepth;

  /// No description provided for @sectionDepthHint.
  ///
  /// In tr, this message translates to:
  /// **'XIRR, sağlık, ileri metrikler, karakter'**
  String get sectionDepthHint;

  /// No description provided for @myAlarms.
  ///
  /// In tr, this message translates to:
  /// **'Alarmlarım'**
  String get myAlarms;

  /// No description provided for @viewChipLabel.
  ///
  /// In tr, this message translates to:
  /// **'Görünüm'**
  String get viewChipLabel;
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
