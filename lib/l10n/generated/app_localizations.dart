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
