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
  /// **'Geçerli bir e-posta gir'**
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
  /// **'Hesabın yok mu? Kayıt ol'**
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
  /// **'Ad soyad gir'**
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

  /// No description provided for @sifreKuralUzunluk.
  ///
  /// In tr, this message translates to:
  /// **'En az 8 karakter'**
  String get sifreKuralUzunluk;

  /// No description provided for @sifreKuralHarf.
  ///
  /// In tr, this message translates to:
  /// **'En az bir harf'**
  String get sifreKuralHarf;

  /// No description provided for @sifreKuralRakam.
  ///
  /// In tr, this message translates to:
  /// **'En az bir rakam'**
  String get sifreKuralRakam;

  /// No description provided for @haveAccountSignIn.
  ///
  /// In tr, this message translates to:
  /// **'Zaten hesabın var mı? Giriş yap'**
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

  /// No description provided for @lockSwitchAccount.
  ///
  /// In tr, this message translates to:
  /// **'Farklı hesapla giriş yap'**
  String get lockSwitchAccount;

  /// No description provided for @lockSwitchAccountTitle.
  ///
  /// In tr, this message translates to:
  /// **'Oturumu kapat'**
  String get lockSwitchAccountTitle;

  /// No description provided for @lockSwitchAccountBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesaptan çıkılacak ve giriş ekranına döneceksin. Verilerin silinmez; tekrar giriş yaptığında yerinde olur.'**
  String get lockSwitchAccountBody;

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
  /// **'Uygulamayı kullanmaya devam etmek için aşağıdaki yasal uyarıyı oku ve onayla.'**
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
  /// **'6 haneli kodun tamamını gir.'**
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
  /// **'Biyometrik kilit, kayıtlı cihazlar, verilerini indir, hesabını sil'**
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

  /// No description provided for @textSize.
  ///
  /// In tr, this message translates to:
  /// **'Yazı boyutu'**
  String get textSize;

  /// No description provided for @textSizeSmall.
  ///
  /// In tr, this message translates to:
  /// **'Küçük'**
  String get textSizeSmall;

  /// No description provided for @textSizeNormal.
  ///
  /// In tr, this message translates to:
  /// **'Normal'**
  String get textSizeNormal;

  /// No description provided for @textSizeLarge.
  ///
  /// In tr, this message translates to:
  /// **'Büyük'**
  String get textSizeLarge;

  /// No description provided for @textSizeXLarge.
  ///
  /// In tr, this message translates to:
  /// **'Çok büyük'**
  String get textSizeXLarge;

  /// No description provided for @textSizeNote.
  ///
  /// In tr, this message translates to:
  /// **'Telefonunun yazı boyutu ayarının üstüne uygulanır. Ekranlar bozulmasın diye büyütmenin bir sınırı var.'**
  String get textSizeNote;

  /// No description provided for @textSizeSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} yazı boyutu'**
  String textSizeSemantics(String name);

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

  /// No description provided for @levelIntermediateDesc.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü görünüm: teknik sinyaller, yüzdelik dilim, sağlık kartı ve başlangıçtan beri yıllık getiri.'**
  String get levelIntermediateDesc;

  /// No description provided for @levelAdvancedDesc.
  ///
  /// In tr, this message translates to:
  /// **'Orta + riske göre getiri, alım zamanlamanın etkisi ve düşüşten toparlanma (Özet › 1 yıl).'**
  String get levelAdvancedDesc;

  /// No description provided for @noAssetsYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz varlık eklenmemiş'**
  String get noAssetsYet;

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

  /// Hızlı Al/Sat diyaloğu: eldeki miktarın tamamını seçen çip.
  ///
  /// In tr, this message translates to:
  /// **'Hepsi ({qty})'**
  String quickAllChip(String qty);

  /// No description provided for @quickHolding.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut'**
  String get quickHolding;

  /// Hızlı Al/Sat: ortalama birim maliyet kısaltması.
  ///
  /// In tr, this message translates to:
  /// **'ort. {price}'**
  String quickAvgShort(String price);

  /// No description provided for @quickUnitPrice.
  ///
  /// In tr, this message translates to:
  /// **'Birim fiyat'**
  String get quickUnitPrice;

  /// No description provided for @quickTotalCost.
  ///
  /// In tr, this message translates to:
  /// **'Toplam maliyet'**
  String get quickTotalCost;

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
  /// **'Fiyatlar güncellenemedi, eski veriler gösteriliyor.'**
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
  /// **'Ad soyad gir.'**
  String get registerNameMissing;

  /// No description provided for @registerEmailInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli bir e-posta gir.'**
  String get registerEmailInvalid;

  /// No description provided for @registerPasswordsMismatch.
  ///
  /// In tr, this message translates to:
  /// **'Şifreler eşleşmiyor.'**
  String get registerPasswordsMismatch;

  /// No description provided for @refreshPrices.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatları yenile'**
  String get refreshPrices;

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

  /// No description provided for @dividendReceived.
  ///
  /// In tr, this message translates to:
  /// **'Tahsil Edilen Temettü'**
  String get dividendReceived;

  /// No description provided for @lotSummary.
  ///
  /// In tr, this message translates to:
  /// **'{sells, plural, =0{{buys} alım} other{{buys} alım · {sells} çıkarma}}'**
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

  /// No description provided for @fundReportTitleUpper.
  ///
  /// In tr, this message translates to:
  /// **'FON KARNESİ'**
  String get fundReportTitleUpper;

  /// No description provided for @fundReportCategory.
  ///
  /// In tr, this message translates to:
  /// **'{category} · {count} fon'**
  String fundReportCategory(String category, String count);

  /// No description provided for @fundReportPeriod1m.
  ///
  /// In tr, this message translates to:
  /// **'1 ay'**
  String get fundReportPeriod1m;

  /// No description provided for @fundReportPeriodYtd.
  ///
  /// In tr, this message translates to:
  /// **'Yılbaşından beri'**
  String get fundReportPeriodYtd;

  /// No description provided for @fundReportPeriod1y.
  ///
  /// In tr, this message translates to:
  /// **'1 yıl'**
  String get fundReportPeriod1y;

  /// No description provided for @fundReportRank.
  ///
  /// In tr, this message translates to:
  /// **'{count} fondan {rank}.'**
  String fundReportRank(String count, String rank);

  /// No description provided for @fundReportReturnVsMedian.
  ///
  /// In tr, this message translates to:
  /// **'Getirisi {ret} · kategori ortancası {median}'**
  String fundReportReturnVsMedian(String ret, String median);

  /// No description provided for @fundReportAboveMedian.
  ///
  /// In tr, this message translates to:
  /// **'Ortancanın {pts} puan üstünde'**
  String fundReportAboveMedian(String pts);

  /// No description provided for @fundReportBelowMedian.
  ///
  /// In tr, this message translates to:
  /// **'Ortancanın {pts} puan altında'**
  String fundReportBelowMedian(String pts);

  /// No description provided for @fundReportAtMedian.
  ///
  /// In tr, this message translates to:
  /// **'Ortancayla aynı'**
  String get fundReportAtMedian;

  /// No description provided for @fundReportFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak: TEFAS. Getiriler TEFAS\'ın açıkladığı rakamlardır; TEFAS\'ın hesap günleri grafikteki dönemle birebir örtüşmez, bu yüzden yukarıdaki dönem getirisinden biraz farklı olabilir. Aynı kategorideki fonlarla kıyas; geçmiş getiri gelecekteki getiriyi göstermez.'**
  String get fundReportFootnote;

  /// No description provided for @fundReportPanelLine.
  ///
  /// In tr, this message translates to:
  /// **'Kategorisinde {count} fondan {rank}. ({period})'**
  String fundReportPanelLine(String count, String rank, String period);

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

  /// No description provided for @assetTypeCrypto.
  ///
  /// In tr, this message translates to:
  /// **'Kripto'**
  String get assetTypeCrypto;

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
  /// **'Örn: THYAO.IS, GARAN.IS  (Borsa İstanbul için .IS ekle)'**
  String get tickerHintStock;

  /// No description provided for @tickerHintFund.
  ///
  /// In tr, this message translates to:
  /// **'Yahoo Finance kodu yoksa boş bırak, fiyatı elle gir'**
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

  /// No description provided for @tickerHintCrypto.
  ///
  /// In tr, this message translates to:
  /// **'Listeden seç, örn. BTC, ETH'**
  String get tickerHintCrypto;

  /// No description provided for @tickerHintCommodity.
  ///
  /// In tr, this message translates to:
  /// **'Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)'**
  String get tickerHintCommodity;

  /// No description provided for @tickerHintOther.
  ///
  /// In tr, this message translates to:
  /// **'Yahoo Finance sembolü ya da boş bırak'**
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
  /// **'Şirket adı (opsiyonel, sembolden otomatik çekilir)'**
  String get companyNameHint;

  /// No description provided for @goldSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{kind} altın'**
  String goldSemantics(String kind);

  /// No description provided for @commissionNote.
  ///
  /// In tr, this message translates to:
  /// **'Alım-satım komisyonu maliyete eklenir; kâr/zarar gerçek rakamı gösterir.'**
  String get commissionNote;

  /// Dövizli alımın toplam maliyet kartında TL karşılığı ve kullanılan kur
  ///
  /// In tr, this message translates to:
  /// **'≈ {amount} · 1 {currency} = {rate}'**
  String totalCostTlEquivalent(String amount, String currency, String rate);

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
  /// **'Notların...'**
  String get notesHint;

  /// No description provided for @txHasNote.
  ///
  /// In tr, this message translates to:
  /// **'Not var'**
  String get txHasNote;

  /// No description provided for @txOpenNote.
  ///
  /// In tr, this message translates to:
  /// **'{name} işlemi, not ekle'**
  String txOpenNote(String name);

  /// No description provided for @txOpenNoteWithNote.
  ///
  /// In tr, this message translates to:
  /// **'{name} işlemi, notu var, notu aç'**
  String txOpenNoteWithNote(String name);

  /// No description provided for @noteSaved.
  ///
  /// In tr, this message translates to:
  /// **'Not kaydedildi'**
  String get noteSaved;

  /// No description provided for @noteRemoved.
  ///
  /// In tr, this message translates to:
  /// **'Not silindi'**
  String get noteRemoved;

  /// No description provided for @noteSaveFailed.
  ///
  /// In tr, this message translates to:
  /// **'Not kaydedilemedi'**
  String get noteSaveFailed;

  /// No description provided for @noteRemove.
  ///
  /// In tr, this message translates to:
  /// **'Notu sil'**
  String get noteRemove;

  /// No description provided for @noteNone.
  ///
  /// In tr, this message translates to:
  /// **'Bu işleme not yazılmamış.'**
  String get noteNone;

  /// No description provided for @noteAddHint.
  ///
  /// In tr, this message translates to:
  /// **'Neden aldın, hedefin ne? Kısa bir not yaz.'**
  String get noteAddHint;

  /// No description provided for @alertTargetAtCurrent.
  ///
  /// In tr, this message translates to:
  /// **'Hedef güncel fiyata eşit, alarm hemen çalışır. Biraz üstünü ya da altını yaz.'**
  String get alertTargetAtCurrent;

  /// No description provided for @notifTypeDividend.
  ///
  /// In tr, this message translates to:
  /// **'Temettü'**
  String get notifTypeDividend;

  /// No description provided for @dividendHistoryUpper.
  ///
  /// In tr, this message translates to:
  /// **'SON 12 AY TEMETTÜ'**
  String get dividendHistoryUpper;

  /// No description provided for @dividendRecordedTotal.
  ///
  /// In tr, this message translates to:
  /// **'Kaydettiğin: {amount}'**
  String dividendRecordedTotal(String amount);

  /// No description provided for @dividendEventLine.
  ///
  /// In tr, this message translates to:
  /// **'{lot} lot × {perShare}'**
  String dividendEventLine(String lot, String perShare);

  /// No description provided for @dividendGrossAmount.
  ///
  /// In tr, this message translates to:
  /// **'{amount} brüt'**
  String dividendGrossAmount(String amount);

  /// No description provided for @dividendRecorded.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedildi'**
  String get dividendRecorded;

  /// No description provided for @dividendRecordAction.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get dividendRecordAction;

  /// No description provided for @dividendSourceNote.
  ///
  /// In tr, this message translates to:
  /// **'Yahoo Finance\'e göre gerçekleşmiş temettüler, hak tarihindeki lotunla. Tutarlar brüt; \"Kaydet\" %15 stopaj düşülmüş neti hazır getirir, düzeltebilirsin.'**
  String get dividendSourceNote;

  /// No description provided for @dividendSuggestionLine.
  ///
  /// In tr, this message translates to:
  /// **'{ticker} · hak tarihi {date}'**
  String dividendSuggestionLine(String ticker, String date);

  /// No description provided for @dividendSuggestionGross.
  ///
  /// In tr, this message translates to:
  /// **'{lot} lot × {perShare} = {gross} brüt'**
  String dividendSuggestionGross(String lot, String perShare, String gross);

  /// No description provided for @dividendWithholdingAssumed.
  ///
  /// In tr, this message translates to:
  /// **'Stopaj {rate} (−{cut}) düşüldü: net {net}. Farklıysa düzelt.'**
  String dividendWithholdingAssumed(String rate, String cut, String net);

  /// No description provided for @dividendEnterNet.
  ///
  /// In tr, this message translates to:
  /// **'Brüt {gross}. Stopaj sonrası eline geçeni yaz.'**
  String dividendEnterNet(String gross);

  /// No description provided for @noteReadOnlyPartner.
  ///
  /// In tr, this message translates to:
  /// **'Bu kayıt ortağına ait; notunu yalnızca o düzenleyebilir.'**
  String get noteReadOnlyPartner;

  /// No description provided for @noteReadOnlyDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Silinmiş kaydın notu düzenlenemez.'**
  String get noteReadOnlyDeleted;

  /// No description provided for @notesSection.
  ///
  /// In tr, this message translates to:
  /// **'Notlar'**
  String get notesSection;

  /// No description provided for @moreNotesCount.
  ///
  /// In tr, this message translates to:
  /// **'+{count} not daha · Tüm Hareketler\'de'**
  String moreNotesCount(int count);

  /// No description provided for @searchAssetSymbolOrNote.
  ///
  /// In tr, this message translates to:
  /// **'Varlık, sembol veya not ara'**
  String get searchAssetSymbolOrNote;

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
  /// **'Her satıra bir varlık yaz. Fiyat opsiyonel; boş bırakırsan güncel fiyat otomatik çekilir.\nÖrn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet'**
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
  /// **'Lütfen bekle'**
  String get pleaseWait;

  /// No description provided for @breakdownUpAmount.
  ///
  /// In tr, this message translates to:
  /// **'artış {amount}'**
  String breakdownUpAmount(String amount);

  /// No description provided for @breakdownDownAmount.
  ///
  /// In tr, this message translates to:
  /// **'azalış {amount}'**
  String breakdownDownAmount(String amount);

  /// No description provided for @nominalReturnInWindow.
  ///
  /// In tr, this message translates to:
  /// **'Bu aralıkta senin getirin'**
  String get nominalReturnInWindow;

  /// No description provided for @cpiWindowNote.
  ///
  /// In tr, this message translates to:
  /// **'TÜFE ayda bir açıklanır; bu kart son açıklanan ayın sonunda biter, aralığı üstteki rakamdan farklı.'**
  String get cpiWindowNote;

  /// No description provided for @rangeChip.
  ///
  /// In tr, this message translates to:
  /// **'{start} - {end}'**
  String rangeChip(String start, String end);

  /// No description provided for @rangeToday.
  ///
  /// In tr, this message translates to:
  /// **'bugün'**
  String get rangeToday;

  /// No description provided for @rangeSinceFirstBuy.
  ///
  /// In tr, this message translates to:
  /// **'İlk alımdan bugüne'**
  String get rangeSinceFirstBuy;

  /// No description provided for @sinceCpiWindowEnd.
  ///
  /// In tr, this message translates to:
  /// **'{month} sonundan bugüne'**
  String sinceCpiWindowEnd(String month);

  /// No description provided for @sinceCpiWindowBody.
  ///
  /// In tr, this message translates to:
  /// **'Üstteki rakam bu süreyi içeriyor; {month} TÜFE\'si açıklanınca ({date}) bu kart güncellenir.'**
  String sinceCpiWindowBody(String month, String date);

  /// No description provided for @sinceCpiWindowBodyLate.
  ///
  /// In tr, this message translates to:
  /// **'Üstteki rakam bu süreyi içeriyor; {month} TÜFE\'si yüklenince bu kart güncellenir.'**
  String sinceCpiWindowBodyLate(String month);

  /// No description provided for @demoBannerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Örnek portföy'**
  String get demoBannerTitle;

  /// No description provided for @demoBannerSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Varlıklar örnek, fiyatlar canlı'**
  String get demoBannerSubtitle;

  /// No description provided for @demoCreateAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap oluştur'**
  String get demoCreateAccount;

  /// No description provided for @demoExit.
  ///
  /// In tr, this message translates to:
  /// **'Örnekten çık'**
  String get demoExit;

  /// No description provided for @demoAccountCardTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kendi portföyünü kur'**
  String get demoAccountCardTitle;

  /// No description provided for @demoAccountCardBody.
  ///
  /// In tr, this message translates to:
  /// **'Burada gördüğün her şey kendi varlıklarınla da çalışır. Varlık eklemek, not ve alarm kaydetmek için hesap oluştur.'**
  String get demoAccountCardBody;

  /// No description provided for @demoAccountCardSignIn.
  ///
  /// In tr, this message translates to:
  /// **'Zaten hesabım var'**
  String get demoAccountCardSignIn;

  /// No description provided for @demoSaveSheetTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kaydetmek için hesap oluştur'**
  String get demoSaveSheetTitle;

  /// No description provided for @demoSaveSheetBody.
  ///
  /// In tr, this message translates to:
  /// **'Bu bir örnek portföy; burada yaptığın değişiklik kaydedilmez. Kendi portföyünü kurmak için hesap oluştur.'**
  String get demoSaveSheetBody;

  /// No description provided for @demoSaveSheetContinue.
  ///
  /// In tr, this message translates to:
  /// **'Örneğe devam et'**
  String get demoSaveSheetContinue;

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
  /// **'Listeden bir hisse seç ya da sembolünü yaz'**
  String get pickStockPrompt;

  /// No description provided for @pickStock.
  ///
  /// In tr, this message translates to:
  /// **'Hisse seç'**
  String get pickStock;

  /// No description provided for @pickStockTap.
  ///
  /// In tr, this message translates to:
  /// **'Hisse seçmek için dokun...'**
  String get pickStockTap;

  /// No description provided for @pickFundPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bir fon seç'**
  String get pickFundPrompt;

  /// No description provided for @pickFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon seç'**
  String get pickFund;

  /// No description provided for @pickFundTap.
  ///
  /// In tr, this message translates to:
  /// **'Fon seçmek için dokun...'**
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

  /// No description provided for @pickGoldTap.
  ///
  /// In tr, this message translates to:
  /// **'Altın türü seçmek için dokun...'**
  String get pickGoldTap;

  /// No description provided for @goldSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Ara: çeyrek, 22 ayar, reşat…'**
  String get goldSearchHint;

  /// No description provided for @goldTypes.
  ///
  /// In tr, this message translates to:
  /// **'Altın Türleri'**
  String get goldTypes;

  /// No description provided for @goldQuickPick.
  ///
  /// In tr, this message translates to:
  /// **'Hızlı seçim'**
  String get goldQuickPick;

  /// No description provided for @goldGroupGram.
  ///
  /// In tr, this message translates to:
  /// **'Gram'**
  String get goldGroupGram;

  /// No description provided for @goldGroupZiynet.
  ///
  /// In tr, this message translates to:
  /// **'Ziynet'**
  String get goldGroupZiynet;

  /// No description provided for @goldGroupSikke.
  ///
  /// In tr, this message translates to:
  /// **'Sikke'**
  String get goldGroupSikke;

  /// No description provided for @goldGroupOns.
  ///
  /// In tr, this message translates to:
  /// **'Ons'**
  String get goldGroupOns;

  /// No description provided for @goldUnitGram.
  ///
  /// In tr, this message translates to:
  /// **'gr'**
  String get goldUnitGram;

  /// No description provided for @goldUnitOunce.
  ///
  /// In tr, this message translates to:
  /// **'ons'**
  String get goldUnitOunce;

  /// No description provided for @goldSelectedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Seçili altın türü: {kind}. Değiştirmek için çift dokun.'**
  String goldSelectedSemantics(String kind);

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
  /// **'Bugün'**
  String get periodDaily;

  /// No description provided for @period1W.
  ///
  /// In tr, this message translates to:
  /// **'1 hf'**
  String get period1W;

  /// No description provided for @period1M.
  ///
  /// In tr, this message translates to:
  /// **'1 ay'**
  String get period1M;

  /// No description provided for @period3M.
  ///
  /// In tr, this message translates to:
  /// **'3 ay'**
  String get period3M;

  /// No description provided for @period6M.
  ///
  /// In tr, this message translates to:
  /// **'6 ay'**
  String get period6M;

  /// No description provided for @period1Y.
  ///
  /// In tr, this message translates to:
  /// **'1 yıl'**
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

  /// No description provided for @otherTab.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get otherTab;

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
  /// **'Bu işlem GERİ ALINAMAZ.\n\nTüm portföy kayıtların, performans geçmişin ve ortaklık bağlantıların hemen ve kalıcı olarak silinecek.\n\nDevam etmek istiyor musun?'**
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

  /// No description provided for @deleteAccountSubscriptionNote.
  ///
  /// In tr, this message translates to:
  /// **'Not: App Store / Google Play aboneliğin hesap silinince kendiliğinden iptal olmaz. Yenilemeyi mağazanın abonelikler sayfasından kapat.'**
  String get deleteAccountSubscriptionNote;

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
  /// **'Mesajını yaz…'**
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
  /// **'Hafta sonu BIST kapalıdır. Portföyün yalnızca hisse ve fondan oluşuyorsa banner son kapanışı \"Piyasa kapalı\" etiketiyle gösterir; altın, döviz ya da kripto varsa canlı kalır.'**
  String get showOnWeekendSubtitle;

  /// No description provided for @showAmounts.
  ///
  /// In tr, this message translates to:
  /// **'Tutarları göster'**
  String get showAmounts;

  /// No description provided for @showAmountsSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Canlı Etkinlik ve kilit ekranı widget\'ı için geçerli. Kapalıyken yalnızca günlük yüzde ve grafik görünür. Kilit ekranı telefonun açılmadan görülebildiği için varsayılan olarak kapalıdır.'**
  String get showAmountsSubtitle;

  /// No description provided for @lockWidgetHowTo.
  ///
  /// In tr, this message translates to:
  /// **'Kilit ekranına da ekleyebilirsin: kilit ekranına basılı tut → Özelleştir → Kilit Ekranı → widget alanına dokun → sandık.'**
  String get lockWidgetHowTo;

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
  /// **'Kodu ortağına gönder. Ortağın kodu girince sana onay isteği gelir.'**
  String get generateInviteCodeBody;

  /// No description provided for @enterPartnerCode.
  ///
  /// In tr, this message translates to:
  /// **'Ortak Kodunu Gir'**
  String get enterPartnerCode;

  /// No description provided for @enterPartnerCodeBody.
  ///
  /// In tr, this message translates to:
  /// **'Ortağının sana gönderdiği kodu gir (örn: KRHNJ-8P2SW). Onay vermesi beklenir.'**
  String get enterPartnerCodeBody;

  /// No description provided for @tooManyAttempts.
  ///
  /// In tr, this message translates to:
  /// **'Çok fazla deneme. {wait} sonra tekrar deneyebilirsin.'**
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
  /// **'Henüz ortağın yok'**
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
  /// **'Sınırsız varlık ve premium göstergeler'**
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
  /// **'{name} ile ortaklık kuruldu.'**
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
  /// **'Ortaklık kabul edildi.'**
  String get partnershipAccepted;

  /// No description provided for @sendingEllipsis.
  ///
  /// In tr, this message translates to:
  /// **'Gönderiliyor...'**
  String get sendingEllipsis;

  /// No description provided for @waitFor.
  ///
  /// In tr, this message translates to:
  /// **'Bekle: {wait}'**
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

  /// No description provided for @youngPortfolioTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönem için henüz geçmiş yok'**
  String get youngPortfolioTitle;

  /// No description provided for @youngPortfolioBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün seçtiğin dönemden daha yeni. Grafik işlem günleri geçtikçe dolacak. Bugünkü hareketi “Bugün” görünümünde görebilirsin.'**
  String get youngPortfolioBody;

  /// No description provided for @forceUpdateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Güncelleme gerekli'**
  String get forceUpdateTitle;

  /// No description provided for @forceUpdateBody.
  ///
  /// In tr, this message translates to:
  /// **'Sandık\'ın bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı güncelle; verilerin yerinde.'**
  String get forceUpdateBody;

  /// No description provided for @forceUpdateButton.
  ///
  /// In tr, this message translates to:
  /// **'Güncelle'**
  String get forceUpdateButton;

  /// No description provided for @serverMovedTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sandık yenilendi'**
  String get serverMovedTitle;

  /// No description provided for @serverMovedBodyAndroid.
  ///
  /// In tr, this message translates to:
  /// **'Daha hızlı sunucumuza geçtik. Devam etmek için uygulamayı kapatıp yeniden aç. Bir kez giriş yapman istenecek; şifren ve verilerin aynı.'**
  String get serverMovedBodyAndroid;

  /// No description provided for @serverMovedBodyIos.
  ///
  /// In tr, this message translates to:
  /// **'Daha hızlı sunucumuza geçtik. Devam etmek için uygulamayı kapatıp (yukarı kaydırarak) yeniden aç. Bir kez giriş yapman istenecek; şifren ve verilerin aynı.'**
  String get serverMovedBodyIos;

  /// No description provided for @serverMovedCloseButton.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı kapat'**
  String get serverMovedCloseButton;

  /// No description provided for @noHistoryTypeBody.
  ///
  /// In tr, this message translates to:
  /// **'{type} için fiyat geçmişi izlenmiyor. Değeri portföy toplamına dahil, ama zaman grafiği çizilemiyor.'**
  String noHistoryTypeBody(String type);

  /// No description provided for @simModeTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü portföyle'**
  String get simModeTitle;

  /// No description provided for @simModeBody.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş olsaydın grafik nasıl görünürdü? Geçmişteki alım/satış kararlarını yok sayar, sadece güncel pozisyonun fiyat değişimini gösterir.'**
  String get simModeBody;

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
  /// **'{names} için gün içi fiyat verisi alınamadı. Bu varlıklar grafikte son bilinen fiyatlarıyla SABİT çizildi. Çizginin düz olması piyasanın durgun olduğu anlamına gelmez.'**
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
  /// **'TÜRE GÖRE · FİYAT ETKİSİ'**
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

  /// Grafik crosshair: çubuğa düşen alım işlemi — zaman ve birim fiyat.
  ///
  /// In tr, this message translates to:
  /// **'Alım {when} · {price}'**
  String chartTxBuy(String when, String price);

  /// No description provided for @chartTxSell.
  ///
  /// In tr, this message translates to:
  /// **'Satış {when} · {price}'**
  String chartTxSell(String when, String price);

  /// No description provided for @tradeVolumeUpper.
  ///
  /// In tr, this message translates to:
  /// **'ALIM · SATIŞ'**
  String get tradeVolumeUpper;

  /// No description provided for @crosshairNetBuy.
  ///
  /// In tr, this message translates to:
  /// **'Net alım +{amount}'**
  String crosshairNetBuy(String amount);

  /// No description provided for @crosshairNetSell.
  ///
  /// In tr, this message translates to:
  /// **'Net satış −{amount}'**
  String crosshairNetSell(String amount);

  /// No description provided for @crosshairNetFlat.
  ///
  /// In tr, this message translates to:
  /// **'Net değişim yok'**
  String get crosshairNetFlat;

  /// No description provided for @crosshairTxCount.
  ///
  /// In tr, this message translates to:
  /// **'{count} işlem'**
  String crosshairTxCount(int count);

  /// No description provided for @crosshairBuySellDetail.
  ///
  /// In tr, this message translates to:
  /// **'Alım {buy} · Satış {sell}'**
  String crosshairBuySellDetail(String buy, String sell);

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

  /// No description provided for @last3MonthsPeriod.
  ///
  /// In tr, this message translates to:
  /// **'son 3 ay'**
  String get last3MonthsPeriod;

  /// No description provided for @threeMonthExtremes.
  ///
  /// In tr, this message translates to:
  /// **'Üç ayın uçları'**
  String get threeMonthExtremes;

  /// No description provided for @last5YearsPeriod.
  ///
  /// In tr, this message translates to:
  /// **'son 5 yıl'**
  String get last5YearsPeriod;

  /// No description provided for @fiveYearExtremes.
  ///
  /// In tr, this message translates to:
  /// **'Beş yılın uçları'**
  String get fiveYearExtremes;

  /// No description provided for @fiveYearCurve.
  ///
  /// In tr, this message translates to:
  /// **'Beş yıl eğrisi'**
  String get fiveYearCurve;

  /// No description provided for @moneyReturnPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Paranın getirisi · {period}'**
  String moneyReturnPeriod(String period);

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
  /// **'Net katkın'**
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
  /// **'Yüzde yalnızca fiyat etkisinden hesaplanır. Nakit temettü de getiriye dahildir; cebine girdiği için köprüde ayrı satırda, çıkış olarak durur.'**
  String get contributionNotReturn;

  /// No description provided for @annualRatePct.
  ///
  /// In tr, this message translates to:
  /// **'{pct} yıllık'**
  String annualRatePct(String pct);

  /// No description provided for @periodTotalPct.
  ///
  /// In tr, this message translates to:
  /// **'Dönem toplamı {pct}'**
  String periodTotalPct(String pct);

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

  /// No description provided for @nominalReturn.
  ///
  /// In tr, this message translates to:
  /// **'Senin getirin'**
  String get nominalReturn;

  /// TÜFE karşılaştırmasının gerçek pencere uçları
  ///
  /// In tr, this message translates to:
  /// **'Ölçüm aralığı: {start} - {end}'**
  String cpiWindowRange(String start, String end);

  /// Tek aylık TÜFE karşılaştırmasının ölçtüğü ay
  ///
  /// In tr, this message translates to:
  /// **'Ölçülen ay: {month}'**
  String cpiWindowMonth(String month);

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
  /// **'Portföyünün değeri yıl boyunca ortalama bu ölçüde dalgalandı. Yüksek olması iyi ya da kötü değil; daha çok inip çıktığı anlamına gelir.'**
  String get volatilityBody;

  /// No description provided for @concentration.
  ///
  /// In tr, this message translates to:
  /// **'Yoğunlaşma'**
  String get concentration;

  /// No description provided for @moneyReturnAnnual.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıçtan beri (yıllık)'**
  String get moneyReturnAnnual;

  /// No description provided for @xirrBody.
  ///
  /// In tr, this message translates to:
  /// **'Yatırdığın paranın, yatırdığın TARİHLER dikkate alınarak hesaplanan yıllık bileşik getirisi.'**
  String get xirrBody;

  /// No description provided for @periodMarketReturnLabel.
  ///
  /// In tr, this message translates to:
  /// **'Seçili dönemin getirisi'**
  String get periodMarketReturnLabel;

  /// No description provided for @xirrVsMarketBody.
  ///
  /// In tr, this message translates to:
  /// **'İki sayı çelişmez: üstteki ilk alımından bugüne, alım zamanlarını da hesaba katarak ölçer; alttaki yalnızca seçili dönemde piyasanın hareketini ölçer.'**
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

  /// No description provided for @portfolioLineInfoDaily.
  ///
  /// In tr, this message translates to:
  /// **'Günlük görünümde {name} çizgisi gerçek değerini gösterir: Performans ekranındaki günlük grafiğin aynısı.'**
  String portfolioLineInfoDaily(String name);

  /// No description provided for @portfolioLineInfoSim.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık ve daha uzun dönemlerde {name} çizgisi bir simülasyondur: bugünkü varlıklarını dönem başından beri tutsaydın ne olurdu. Alım-satım tarihlerin hesaba katılmaz; gerçekleşmiş getirin değildir. Böylece izlediğin varlıklarla aynı pencerede kıyaslanır.'**
  String portfolioLineInfoSim(String name);

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
  /// **'Karşılaştırmak için varlık ekle'**
  String get addAssetsToCompare;

  /// No description provided for @addAssetsToCompareBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünde olmayan varlıkları da ekleyebilirsin.'**
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
  /// **'Portföyler hesaplanan serilerdir, piyasada kote değiller. Getirileri, tıpkı bir varlık gibi dönem başına göre yüzde olarak çizilir.'**
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

  /// No description provided for @watchlistRowUp.
  ///
  /// In tr, this message translates to:
  /// **'artış {pct}'**
  String watchlistRowUp(String pct);

  /// No description provided for @watchlistRowDown.
  ///
  /// In tr, this message translates to:
  /// **'düşüş {pct}'**
  String watchlistRowDown(String pct);

  /// No description provided for @watchlistRowFollowing.
  ///
  /// In tr, this message translates to:
  /// **'takip ediliyor'**
  String get watchlistRowFollowing;

  /// No description provided for @notificationsNewCount.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =1{1 yeni bildirim} other{{count} yeni bildirim}}'**
  String notificationsNewCount(int count);

  /// No description provided for @signOutAction.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yap'**
  String get signOutAction;

  /// No description provided for @baseCurrencyNameLira.
  ///
  /// In tr, this message translates to:
  /// **'Lira'**
  String get baseCurrencyNameLira;

  /// No description provided for @baseCurrencyNameDollar.
  ///
  /// In tr, this message translates to:
  /// **'Dolar'**
  String get baseCurrencyNameDollar;

  /// No description provided for @baseCurrencyNameEuro.
  ///
  /// In tr, this message translates to:
  /// **'Euro'**
  String get baseCurrencyNameEuro;

  /// No description provided for @baseCurrencyNameGold.
  ///
  /// In tr, this message translates to:
  /// **'Gram altın'**
  String get baseCurrencyNameGold;

  /// No description provided for @datePickerHelp.
  ///
  /// In tr, this message translates to:
  /// **'Tarih seç'**
  String get datePickerHelp;

  /// No description provided for @datePickerConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Seç'**
  String get datePickerConfirm;

  /// No description provided for @sortAssetsSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Varlıkları sırala'**
  String get sortAssetsSemantics;

  /// No description provided for @showDetailsSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntıları göster'**
  String get showDetailsSemantics;

  /// No description provided for @hideDetailsSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntıları gizle'**
  String get hideDetailsSemantics;

  /// No description provided for @pricePreviewClose.
  ///
  /// In tr, this message translates to:
  /// **'{date} kapanışı. Kayıtta bu fiyat kullanılacak'**
  String pricePreviewClose(String date);

  /// No description provided for @pricePreviewLastTradingClose.
  ///
  /// In tr, this message translates to:
  /// **'Son işlem günü kapanışı ({date}). Kayıtta bu fiyat kullanılacak'**
  String pricePreviewLastTradingClose(String date);

  /// No description provided for @priceAssignedClose.
  ///
  /// In tr, this message translates to:
  /// **'{date} kapanışı {price} olarak atandı'**
  String priceAssignedClose(String date, String price);

  /// No description provided for @priceAssignedLastTradingClose.
  ///
  /// In tr, this message translates to:
  /// **'Son işlem günü ({date}) kapanışı {price} olarak atandı'**
  String priceAssignedLastTradingClose(String date, String price);

  /// Bugün kartı, 'Enflasyona göre' satırının değeri; yön kelimeyle, işaret yok (F3)
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan önde'**
  String todayRealAhead(String pts);

  /// No description provided for @todayRealBehind.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan geride'**
  String todayRealBehind(String pts);

  /// No description provided for @todayRealEven.
  ///
  /// In tr, this message translates to:
  /// **'başa baş'**
  String get todayRealEven;

  /// Yıl sonu özeti, enflasyon sayfası başlığı; eskiden işaretli çıplak '{n} puan' idi (F3)
  ///
  /// In tr, this message translates to:
  /// **'Enflasyonu {n} puan geçtin'**
  String recapPointsAhead(String n);

  /// No description provided for @recapPointsBehind.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyonun {n} puan gerisinde kaldın'**
  String recapPointsBehind(String n);

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
  /// **'Seçimlerinin getirisi'**
  String get selectedPeriodReturn;

  /// No description provided for @depositsDontChangeRank.
  ///
  /// In tr, this message translates to:
  /// **'Para eklemek sıralamayı değiştirmez'**
  String get depositsDontChangeRank;

  /// No description provided for @everyoneMeasuredSame.
  ///
  /// In tr, this message translates to:
  /// **'Herkes aynı şekilde ölçülür'**
  String get everyoneMeasuredSame;

  /// No description provided for @rankVsPortfolioNote.
  ///
  /// In tr, this message translates to:
  /// **'Kendi satırının altındaki \"Paranın getirisi\" Performans ekranındaki sayıdır: ne zaman, ne kadar para eklediğini de hesaba katar. Sıralama ise yalnız seçimlerini ölçer; iki sayı farklı olabilir.'**
  String get rankVsPortfolioNote;

  /// No description provided for @rankSwapNote.
  ///
  /// In tr, this message translates to:
  /// **'Yeni katılan, yalnız portföyünü tuttuğu süre kadar ölçülür. Fiyat geçmişi bulunamayan portföyler sıralamada yer almaz.'**
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
  /// **'Kimsenin varlık listesi paylaşılmaz, yalnız getiri yüzdeleri sıralanır.'**
  String get raceNoListShared;

  /// No description provided for @yourReturnUpper.
  ///
  /// In tr, this message translates to:
  /// **'SEÇİMLERİNİN GETİRİSİ'**
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
  /// **'Yeterli katılımcı olunca sıran açılacak. Anonim, KVKK uyumlu'**
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
  /// **'Dönem günlere bölünür. Her gün, o gün elinde olan varlıklar piyasa fiyatıyla değerlenir ve günlerin getirisi birbirine eklenir (çarpılır).\n\nSatıp başka bir varlık aldıysan ikisi de yalnız tuttuğun günlerde sayılır. Yukarıdaki dönem seçimi sonucu doğrudan değiştirir.'**
  String get selectedPeriodReturnBody;

  /// No description provided for @depositsDontChangeRankBody.
  ///
  /// In tr, this message translates to:
  /// **'Ölçülen şey seçimlerin: hangi varlığı, hangi günler tuttuğun. Ne zaman ve ne kadar para eklediğin oranı ETKİLEMEZ; 1 lot da tutsan 10.000 lot da tutsan aynı seçim aynı yüzdeyi verir.\n\nGirdiğin alış fiyatı kullanılmaz; her şey piyasa fiyatıyla değerlenir.'**
  String get depositsDontChangeRankBody;

  /// No description provided for @everyoneMeasuredSameBody.
  ///
  /// In tr, this message translates to:
  /// **'Sen ve ortakların aynı formülle, aynı fiyatlarla hesaplanırsınız; hesap bu cihazda yapılır. Ortaklar arasında girdiğin tarih geçerlidir: CSV ya da ekstreyle içe aktardığın geçmiş hemen sayılır.\n\nSıralamaya girmek için ilk varlığını edinmenin üzerinden en az {gun} gün geçmiş olmalı. Anonim sıralamalarda (Zirve, genel) bugünden 3 günden fazla geriye tarihli girilen alım ya da satışın getirisi girildiği günden ölçülür.'**
  String everyoneMeasuredSameBody(int gun);

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
  /// **'Ödeme App Store hesabından alınır. Abonelik, dönem bitmeden en az 24 saat önce iptal edilmezse aynı süre ve fiyatla otomatik yenilenir. Ayarlar › Apple ID › Abonelikler\'den yönetebilir ya da iptal edebilirsin.'**
  String get subscriptionTerms;

  /// No description provided for @premiumUnlocked.
  ///
  /// In tr, this message translates to:
  /// **'Premium açıldı'**
  String get premiumUnlocked;

  /// No description provided for @premiumUnlockedBody.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız varlık, premium göstergeler ve Premium ayrıntıların hepsi açıldı.'**
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
  /// **'Sınırsız varlık, yıllık rapor, temettü tahmini ve teknik sinyaller. Portföy takibi her zaman ücretsiz.'**
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
  /// **'Bir yılın kısa hikâyesi: {character}'**
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

  /// No description provided for @pointsBehind.
  ///
  /// In tr, this message translates to:
  /// **'{pts} puan gerisindesin'**
  String pointsBehind(String pts);

  /// No description provided for @noChangeLower.
  ///
  /// In tr, this message translates to:
  /// **'değişim yok'**
  String get noChangeLower;

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

  /// Ust kartin kar/zarar satirinin altinda: toplam getiriye dahil edilen nakit temettu.
  ///
  /// In tr, this message translates to:
  /// **'Bunun temettüsü: '**
  String get includedDividend;

  /// No description provided for @deletedNRecords.
  ///
  /// In tr, this message translates to:
  /// **'Silindi · {n} kayıt'**
  String deletedNRecords(int n);

  /// No description provided for @txDeleted.
  ///
  /// In tr, this message translates to:
  /// **'Silindi'**
  String get txDeleted;

  /// No description provided for @txVoided.
  ///
  /// In tr, this message translates to:
  /// **'silindi'**
  String get txVoided;

  /// No description provided for @seeAllShort.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü gör'**
  String get seeAllShort;

  /// No description provided for @nTransactions.
  ///
  /// In tr, this message translates to:
  /// **'{n} hareket'**
  String nTransactions(int n);

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

  /// No description provided for @costBasisGain.
  ///
  /// In tr, this message translates to:
  /// **'Maliyetine göre kâr'**
  String get costBasisGain;

  /// No description provided for @costBasisLoss.
  ///
  /// In tr, this message translates to:
  /// **'Maliyetine göre zarar'**
  String get costBasisLoss;

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
  /// **'Farkı büyüt, ikinci +{gap}% geride'**
  String widenTheGap(String gap);

  /// No description provided for @atTheTop.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedesin, farkı koru'**
  String get atTheTop;

  /// No description provided for @toPassPerson.
  ///
  /// In tr, this message translates to:
  /// **'{name}\'i geçmen için +{diff}%'**
  String toPassPerson(String name, String diff);

  /// No description provided for @higherInOtherPeriods.
  ///
  /// In tr, this message translates to:
  /// **'Diğer periyotlarda daha üsttesin. Dokun, bak'**
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
  /// **'Bu bir satış değil. Varlık portföyden çıkar, toplamlardan ve geçmiş grafiğinden düşer. İşlem kayıtları \"Portföy Hareketleri\"nde kalır. Sattıysan bunun yerine \"Sat\" kullan; realize kâr/zararın hesaba dahil olur.'**
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
  /// **'Geçerli bir tutar gir'**
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

  /// No description provided for @depositAmountLabel.
  ///
  /// In tr, this message translates to:
  /// **'Tutar'**
  String get depositAmountLabel;

  /// No description provided for @cannotExceedBalance.
  ///
  /// In tr, this message translates to:
  /// **'Mevcut bakiyeyi ({amount}) aşamazsın'**
  String cannotExceedBalance(String amount);

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
  /// **'Tüm miktarı satıyorsun. Pozisyon listeden kalkar ama bu bir satış kaydı olarak durur. İşlem geçmişin ve realize kâr/zararın korunur. Kaydı tamamen silmek istiyorsan varlık detayından \"Sil\"i kullan.'**
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
  /// **'{lehte}/{total} yön veren gösterge · güven %{pct}'**
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
  /// **'Bu varlığın fiyat geçmişi şu an çekilemedi, göstergeler hesaplanamıyor.'**
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
  /// **'· {on}/{all} gösterge açık'**
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
  /// **'Ekstreden içe aktar'**
  String get csvImportTitle;

  /// No description provided for @csvImportBody.
  ///
  /// In tr, this message translates to:
  /// **'Aracı kurum ya da banka ekstreni (PDF, Excel veya CSV) dosyadan seç ya da tabloyu kopyalayıp yapıştır. Sütunların adı ve sırası önemli değil: sembol, adet, fiyat, tarih ve alış/satış kendiliğinden bulunur. Alışlar ve satışlar tarihleriyle birlikte gelir.'**
  String get csvImportBody;

  /// No description provided for @pasteHere.
  ///
  /// In tr, this message translates to:
  /// **'Buraya yapıştır'**
  String get pasteHere;

  /// No description provided for @importPickFile.
  ///
  /// In tr, this message translates to:
  /// **'Dosyadan seç (PDF, Excel, CSV)'**
  String get importPickFile;

  /// No description provided for @importReading.
  ///
  /// In tr, this message translates to:
  /// **'Dosya okunuyor…'**
  String get importReading;

  /// No description provided for @importMappingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sütunlar böyle eşlendi'**
  String get importMappingTitle;

  /// No description provided for @importLowConfidence.
  ///
  /// In tr, this message translates to:
  /// **'Bu dosyanın sütunlarından tam emin değiliz; eşlemeyi kontrol et, gerekirse düzelt.'**
  String get importLowConfidence;

  /// No description provided for @importFixColumns.
  ///
  /// In tr, this message translates to:
  /// **'Sütunları düzelt'**
  String get importFixColumns;

  /// No description provided for @importCopyDiagnostic.
  ///
  /// In tr, this message translates to:
  /// **'Tanılama metnini kopyala'**
  String get importCopyDiagnostic;

  /// No description provided for @importDiagnosticHint.
  ///
  /// In tr, this message translates to:
  /// **'Okunamayan ekstreyi düzeltebilmemiz için tablonun yapısını kopyalar. Ad, numara ve tutarlar maskelenir.'**
  String get importDiagnosticHint;

  /// No description provided for @importDiagnosticCopied.
  ///
  /// In tr, this message translates to:
  /// **'Tanılama metni kopyalandı.'**
  String get importDiagnosticCopied;

  /// No description provided for @importAiButton.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekâyla eşle'**
  String get importAiButton;

  /// No description provided for @importAiHint.
  ///
  /// In tr, this message translates to:
  /// **'Tablonun yalnız yapısı gönderilir: ad, numara ve tutarlar gizlenir, belge telefonundan çıkmaz.'**
  String get importAiHint;

  /// No description provided for @importAiSuggested.
  ///
  /// In tr, this message translates to:
  /// **'Sütunları yapay zekâ önerdi; eşlemeyi kontrol et, gerekirse düzelt.'**
  String get importAiSuggested;

  /// No description provided for @importAiNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekâ da bu dosyada varlık tablosu bulamadı.'**
  String get importAiNoMatch;

  /// No description provided for @importAiLimit.
  ///
  /// In tr, this message translates to:
  /// **'Bugünlük yapay zekâ eşleme hakkın doldu; yarın yeniden dene.'**
  String get importAiLimit;

  /// No description provided for @importAiFailed.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekâ eşlemesi şu an yapılamadı. Biraz sonra yeniden dene.'**
  String get importAiFailed;

  /// No description provided for @importTradesApplied.
  ///
  /// In tr, this message translates to:
  /// **'{count} varlığın gerçek alış tarihi ve fiyatı hesap hareketlerinden alındı.'**
  String importTradesApplied(int count);

  /// No description provided for @importDepositRow.
  ///
  /// In tr, this message translates to:
  /// **'{name} · {amount} · {rate} faiz · {days} gün vade'**
  String importDepositRow(String name, String amount, String rate, int days);

  /// No description provided for @importFundNotRecognized.
  ///
  /// In tr, this message translates to:
  /// **'Fon tanınmadı, eklenmedi: {name}'**
  String importFundNotRecognized(String name);

  /// No description provided for @importFundListFailed.
  ///
  /// In tr, this message translates to:
  /// **'TEFAS fon listesi alınamadı; adıyla yazılmış fonlar eklenemedi. Bağlantını kontrol edip dosyayı yeniden seç.'**
  String get importFundListFailed;

  /// No description provided for @importDepositsFound.
  ///
  /// In tr, this message translates to:
  /// **'{n} vadeli mevduat bulundu (vadesiz hesaplar alınmaz)'**
  String importDepositsFound(int n);

  /// No description provided for @importStatementDate.
  ///
  /// In tr, this message translates to:
  /// **'Ekstre tarihi {date}: fonların maliyeti o günkü birim fiyat sayıldı.'**
  String importStatementDate(String date);

  /// No description provided for @cartDepositSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Vadeli · {rate} · {days} gün'**
  String cartDepositSubtitle(String rate, int days);

  /// No description provided for @importColumnNone.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get importColumnNone;

  /// No description provided for @importApply.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get importApply;

  /// No description provided for @importOrPaste.
  ///
  /// In tr, this message translates to:
  /// **'ya da tabloyu yapıştır'**
  String get importOrPaste;

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

  /// No description provided for @bulkAddSavingProgress.
  ///
  /// In tr, this message translates to:
  /// **'Kaydediliyor {saved} / {total}'**
  String bulkAddSavingProgress(int saved, int total);

  /// No description provided for @bulkAddPartialResult.
  ///
  /// In tr, this message translates to:
  /// **'{saved} varlık eklendi, {failed} varlık eklenemedi. Eklenemeyenler sepette duruyor; tekrar denersen yalnızca onlar eklenir.'**
  String bulkAddPartialResult(int saved, int failed);

  /// No description provided for @importSellExceedsHolding.
  ///
  /// In tr, this message translates to:
  /// **'{name}: satış miktarı o tarihte elindekinden fazla; kaydedilmedi.'**
  String importSellExceedsHolding(String name);

  /// No description provided for @importSellNoPrice.
  ///
  /// In tr, this message translates to:
  /// **'{name}: satış fiyatı bulunamadı; fiyatı yazıp tekrar dene.'**
  String importSellNoPrice(String name);

  /// No description provided for @cartSellTag.
  ///
  /// In tr, this message translates to:
  /// **'Satış'**
  String get cartSellTag;

  /// No description provided for @kapLinkLabel.
  ///
  /// In tr, this message translates to:
  /// **'KAP bildirimleri'**
  String get kapLinkLabel;

  /// No description provided for @kapLinkHint.
  ///
  /// In tr, this message translates to:
  /// **'Şirketin KAP sayfası tarayıcıda açılır'**
  String get kapLinkHint;

  /// No description provided for @kapLinkFailed.
  ///
  /// In tr, this message translates to:
  /// **'KAP sayfası açılamadı. İnternet bağlantını kontrol et.'**
  String get kapLinkFailed;

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
  /// **'Ekstreden içe aktar (PDF, Excel, CSV)'**
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
  /// **'Değişim birim fiyat farkıdır; bu varlığa sahip değilsin.'**
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

  /// No description provided for @watchlistInListLabel.
  ///
  /// In tr, this message translates to:
  /// **'Takipte'**
  String get watchlistInListLabel;

  /// No description provided for @watchlistFullShort.
  ///
  /// In tr, this message translates to:
  /// **'Dolu'**
  String get watchlistFullShort;

  /// No description provided for @watchlistCountOfLimit.
  ///
  /// In tr, this message translates to:
  /// **'{n}/{limit} takipte'**
  String watchlistCountOfLimit(int n, int limit);

  /// No description provided for @watchlistAddShort.
  ///
  /// In tr, this message translates to:
  /// **'Ekle'**
  String get watchlistAddShort;

  /// No description provided for @watchlistLimitReached.
  ///
  /// In tr, this message translates to:
  /// **'En fazla {n} varlık takip edebilirsin. Yeni eklemek için birini çıkar.'**
  String watchlistLimitReached(int n);

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

  /// ek = trSayiAyrilmaEki(pct): 30 → undan, 20 → sinden
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcıların %{pct}\'{ek} iyi'**
  String betterThanPctInvestors(int pct, String ek);

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

  /// No description provided for @sessionTimedOut.
  ///
  /// In tr, this message translates to:
  /// **'Güvenlik için oturumun kapatıldı. Ayarlar › Gizlilik\'ten kilidi açarsan bir daha kapanmaz.'**
  String get sessionTimedOut;

  /// No description provided for @lockOfferTitle.
  ///
  /// In tr, this message translates to:
  /// **'{yontem, select, faceId{Face ID ile koru} touchId{Touch ID ile koru} biyometrik{Biyometrik kilitle koru} other{Ekran kilidiyle koru}}'**
  String lockOfferTitle(String yontem);

  /// No description provided for @lockOfferBody.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün cebinde. Kilit açıkken uygulama araya girmeden seni tanır.'**
  String get lockOfferBody;

  /// No description provided for @lockOfferBenefitStay.
  ///
  /// In tr, this message translates to:
  /// **'Oturumun kapanmaz'**
  String get lockOfferBenefitStay;

  /// No description provided for @lockOfferBenefitStayBody.
  ///
  /// In tr, this message translates to:
  /// **'Kilit kapalıyken uygulamayı 10 dakika bırakınca güvenlik için çıkış yapılıyor ve şifreni yeniden girmen gerekiyor. Kilit açıkken oturumun yerinde kalır.'**
  String get lockOfferBenefitStayBody;

  /// No description provided for @lockOfferBenefitPush.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimlerin kesilmez'**
  String get lockOfferBenefitPush;

  /// No description provided for @lockOfferBenefitPushBody.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yapılınca fiyat alarmların ve günlük özetin de susar. Kilit açıkken gelmeye devam eder.'**
  String get lockOfferBenefitPushBody;

  /// No description provided for @lockOfferBenefitPrivacy.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün görünmez'**
  String get lockOfferBenefitPrivacy;

  /// No description provided for @lockOfferBenefitPrivacyBody.
  ///
  /// In tr, this message translates to:
  /// **'Telefonun başkasının eline geçerse tutarların senin doğrulaman olmadan açılmaz.'**
  String get lockOfferBenefitPrivacyBody;

  /// No description provided for @lockOfferAccept.
  ///
  /// In tr, this message translates to:
  /// **'{yontem, select, faceId{Face ID\'yi aç} touchId{Touch ID\'yi aç} biyometrik{Biyometrik kilidi aç} other{Uygulama kilidini aç}}'**
  String lockOfferAccept(String yontem);

  /// No description provided for @lockOfferDecline.
  ///
  /// In tr, this message translates to:
  /// **'Şimdi değil'**
  String get lockOfferDecline;

  /// No description provided for @lockOfferLater.
  ///
  /// In tr, this message translates to:
  /// **'Bunu sonra Ayarlar › Gizlilik\'ten açabilirsin.'**
  String get lockOfferLater;

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
  /// **'Borsa kapalıyken hisse ve fonlar son kapanıştan, altın, döviz ve kripto canlı gösterilir.'**
  String get marketClosedNote;

  /// No description provided for @hiddenWeekend.
  ///
  /// In tr, this message translates to:
  /// **'Şu an görünmüyor: hafta sonu gösterimi kapalı. Açmak için yukarıdaki anahtarı kullan.'**
  String get hiddenWeekend;

  /// No description provided for @hiddenOutsideWindow.
  ///
  /// In tr, this message translates to:
  /// **'Şu an görünmüyor: saat {start}-{end} aralığının dışındasın. Banner {start}\'da görünecek. Hemen görmek için \"Gün boyu göster\"i aç.'**
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
  /// **'Brifing, özet, takvim ve alarm push\'ları {start}-{end} arası gönderilmez'**
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
  /// **'Portföyün enflasyonun üzerinde reel getiri sağladı, alım gücün arttı.'**
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
  /// **'Portföyün enflasyonun altında kaldı, alım gücün geriledi.'**
  String get realReturnNegative;

  /// No description provided for @realReturnEven.
  ///
  /// In tr, this message translates to:
  /// **'Portföyün enflasyonla aynı oranda değerlendi, alım gücün korundu.'**
  String get realReturnEven;

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
  /// **'Bugünkü toplam değişim'**
  String get todaysBalanceChange;

  /// No description provided for @sinceDateToToday.
  ///
  /// In tr, this message translates to:
  /// **'{date} → bugün'**
  String sinceDateToToday(String date);

  /// No description provided for @balanceChangeSince.
  ///
  /// In tr, this message translates to:
  /// **'{date} toplam değişim'**
  String balanceChangeSince(String date);

  /// No description provided for @periodChangeSim.
  ///
  /// In tr, this message translates to:
  /// **'{period} değişim · bugünkü portföyle'**
  String periodChangeSim(String period);

  /// No description provided for @periodBalanceChange.
  ///
  /// In tr, this message translates to:
  /// **'{period} toplam değişim'**
  String periodBalanceChange(String period);

  /// No description provided for @marketOnlyRow.
  ///
  /// In tr, this message translates to:
  /// **'Sadece fiyat etkisi'**
  String get marketOnlyRow;

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
  /// **'Sıralama seçimlerinin getirisidir: her gün tuttuğun varlıklar piyasa fiyatıyla ölçülür, para ekleme zamanı etkilemez. Sıralamalar ve dağılımlar anonimdir; kimlik, miktar ve TL bilgisi asla paylaşılmaz.'**
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
  /// **'Daha iyisini yapabilirsin, 30G takip et'**
  String get toneRest;

  /// No description provided for @raceFooterPartners.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama, seçili dönemde seçimlerinin getirisidir (%): para ekleme zamanı etkilemez. Kimsenin varlık listesi görünmez.'**
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
  /// **'Ölçüm: {start} - {end} (TÜFE aylık yayımlandığı için pencere son açıklanan ayda biter)'**
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

  /// No description provided for @scopeSearch.
  ///
  /// In tr, this message translates to:
  /// **'Ortak ara'**
  String get scopeSearch;

  /// No description provided for @scopePeopleCount.
  ///
  /// In tr, this message translates to:
  /// **'{n} kişi'**
  String scopePeopleCount(int n);

  /// No description provided for @scopeSwipeHint.
  ///
  /// In tr, this message translates to:
  /// **'Kartı sağa/sola kaydırarak da geçebilirsin'**
  String get scopeSwipeHint;

  /// No description provided for @scopeNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen ortak yok'**
  String get scopeNoMatch;

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

  /// No description provided for @chartCandleChip.
  ///
  /// In tr, this message translates to:
  /// **'MUM'**
  String get chartCandleChip;

  /// No description provided for @chartIntervalM1.
  ///
  /// In tr, this message translates to:
  /// **'1 dk'**
  String get chartIntervalM1;

  /// No description provided for @chartIntervalH1.
  ///
  /// In tr, this message translates to:
  /// **'1 sa'**
  String get chartIntervalH1;

  /// No description provided for @chartIntervalH4.
  ///
  /// In tr, this message translates to:
  /// **'4 sa'**
  String get chartIntervalH4;

  /// No description provided for @chartIntervalD1.
  ///
  /// In tr, this message translates to:
  /// **'Gün'**
  String get chartIntervalD1;

  /// No description provided for @chartIntervalW1.
  ///
  /// In tr, this message translates to:
  /// **'Hafta'**
  String get chartIntervalW1;

  /// No description provided for @chartIntervalMo1.
  ///
  /// In tr, this message translates to:
  /// **'Ay'**
  String get chartIntervalMo1;

  /// No description provided for @chartIntervalM1Long.
  ///
  /// In tr, this message translates to:
  /// **'1 dakikalık'**
  String get chartIntervalM1Long;

  /// No description provided for @chartIntervalH1Long.
  ///
  /// In tr, this message translates to:
  /// **'1 saatlik'**
  String get chartIntervalH1Long;

  /// No description provided for @chartIntervalH4Long.
  ///
  /// In tr, this message translates to:
  /// **'4 saatlik'**
  String get chartIntervalH4Long;

  /// No description provided for @chartIntervalD1Long.
  ///
  /// In tr, this message translates to:
  /// **'günlük'**
  String get chartIntervalD1Long;

  /// No description provided for @chartIntervalW1Long.
  ///
  /// In tr, this message translates to:
  /// **'haftalık'**
  String get chartIntervalW1Long;

  /// No description provided for @chartIntervalMo1Long.
  ///
  /// In tr, this message translates to:
  /// **'aylık'**
  String get chartIntervalMo1Long;

  /// Mum aralığı seçicisi, ekran okuyucu.
  ///
  /// In tr, this message translates to:
  /// **'Mum aralığı: {aralik} mumlar'**
  String chartIntervalSemantics(String aralik);

  /// No description provided for @chartCandleFromCloses.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık günde tek fiyat yayımlar; mumlar günlük fiyatlardan kurulur.'**
  String get chartCandleFromCloses;

  /// Crosshair: imlecin altındaki mumun açılış, en yüksek, en düşük, kapanış fiyatı.
  ///
  /// In tr, this message translates to:
  /// **'A {acilis} · Y {yuksek} · D {dusuk} · K {kapanis}'**
  String chartOhlcLine(
      String acilis, String yuksek, String dusuk, String kapanis);

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
  /// **'sandık · sürüm {surum}'**
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
  /// **'Yıllık getiri'**
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

  /// ek = trSayiAyrilmaEki(pct): 30 → undan, 20 → sinden
  ///
  /// In tr, this message translates to:
  /// **'%{pct}\'{ek} iyi'**
  String shareCardBetterThanPct(int pct, String ek);

  /// No description provided for @shareCardRange.
  ///
  /// In tr, this message translates to:
  /// **'{start} - {end}'**
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

  /// No description provided for @todayMarketOnly.
  ///
  /// In tr, this message translates to:
  /// **'sadece fiyat etkisi'**
  String get todayMarketOnly;

  /// No description provided for @todaySessionOpen.
  ///
  /// In tr, this message translates to:
  /// **'Seans açık · {close} kapanış'**
  String todaySessionOpen(String close);

  /// No description provided for @todayOpensAt.
  ///
  /// In tr, this message translates to:
  /// **'{when} açılır'**
  String todayOpensAt(String when);

  /// No description provided for @todayClosedWord.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa kapalı'**
  String get todayClosedWord;

  /// No description provided for @todayLiveWord.
  ///
  /// In tr, this message translates to:
  /// **'Canlı'**
  String get todayLiveWord;

  /// No description provided for @todayLoading.
  ///
  /// In tr, this message translates to:
  /// **'Gün içi veri geliyor'**
  String get todayLoading;

  /// No description provided for @todayRealLabel.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyona göre'**
  String get todayRealLabel;

  /// No description provided for @todayRealHint.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık getirin ile TÜFE farkı'**
  String get todayRealHint;

  /// No description provided for @todayWeekHint.
  ///
  /// In tr, this message translates to:
  /// **'Piyasanın portföyüne etkisi · özet hazır'**
  String get todayWeekHint;

  /// No description provided for @todayGoalLabel.
  ///
  /// In tr, this message translates to:
  /// **'Hedef'**
  String get todayGoalLabel;

  /// No description provided for @todayGoalSetShort.
  ///
  /// In tr, this message translates to:
  /// **'Tutar seç, kalanı her gün gör'**
  String get todayGoalSetShort;

  /// No description provided for @todayGoalAction.
  ///
  /// In tr, this message translates to:
  /// **'Belirle'**
  String get todayGoalAction;

  /// No description provided for @todayGoalLeftHint.
  ///
  /// In tr, this message translates to:
  /// **'{goal} hedefe kalan'**
  String todayGoalLeftHint(String goal);

  /// No description provided for @todayGoalValue.
  ///
  /// In tr, this message translates to:
  /// **'%{pct} · {left}'**
  String todayGoalValue(int pct, String left);

  /// No description provided for @todayGoalDone.
  ///
  /// In tr, this message translates to:
  /// **'Ulaşıldı'**
  String get todayGoalDone;

  /// No description provided for @todayGoalDoneHint.
  ///
  /// In tr, this message translates to:
  /// **'Hedefin {goal} · yenisini seç'**
  String todayGoalDoneHint(String goal);

  /// No description provided for @todayOpenAction.
  ///
  /// In tr, this message translates to:
  /// **'Aç'**
  String get todayOpenAction;

  /// No description provided for @todayTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get todayTitle;

  /// Bugün kartının başındaki kapsam etiketi; Türkçede name ilgi ekiyle gelir (Ayşe'nin).
  ///
  /// In tr, this message translates to:
  /// **'{name} bugünü'**
  String todayScopeOf(String name);

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

  /// No description provided for @todayCloseAt.
  ///
  /// In tr, this message translates to:
  /// **'{close} kapanış'**
  String todayCloseAt(String close);

  /// No description provided for @todayClosedShort.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get todayClosedShort;

  /// No description provided for @todayMarketOnlyShort.
  ///
  /// In tr, this message translates to:
  /// **'fiyat etkisi'**
  String get todayMarketOnlyShort;

  /// No description provided for @todayGoalNewAction.
  ///
  /// In tr, this message translates to:
  /// **'Yenisini seç'**
  String get todayGoalNewAction;

  /// No description provided for @todayVerdictUp.
  ///
  /// In tr, this message translates to:
  /// **'Yükseldi'**
  String get todayVerdictUp;

  /// No description provided for @todayVerdictDown.
  ///
  /// In tr, this message translates to:
  /// **'Geriledi'**
  String get todayVerdictDown;

  /// No description provided for @todayVerdictFlat.
  ///
  /// In tr, this message translates to:
  /// **'Yerinde saydı'**
  String get todayVerdictFlat;

  /// No description provided for @todayChipWeek.
  ///
  /// In tr, this message translates to:
  /// **'Hafta'**
  String get todayChipWeek;

  /// No description provided for @todayChipMonth.
  ///
  /// In tr, this message translates to:
  /// **'Ay'**
  String get todayChipMonth;

  /// No description provided for @todayChipYear.
  ///
  /// In tr, this message translates to:
  /// **'Yıl'**
  String get todayChipYear;

  /// No description provided for @todayMoversTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bugün en çok oynayanlar'**
  String get todayMoversTitle;

  /// No description provided for @todayMoversAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get todayMoversAll;

  /// No description provided for @todayPurchasingQuestion.
  ///
  /// In tr, this message translates to:
  /// **'Paran fiyatlara yetişiyor mu?'**
  String get todayPurchasingQuestion;

  /// No description provided for @todayHundredBefore.
  ///
  /// In tr, this message translates to:
  /// **'Geçen yılki 100 liran bugün '**
  String get todayHundredBefore;

  /// No description provided for @todayHundredAmount.
  ///
  /// In tr, this message translates to:
  /// **'{amount} lira'**
  String todayHundredAmount(String amount);

  /// No description provided for @todayPricesAhead.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatlar önde'**
  String get todayPricesAhead;

  /// No description provided for @todayYouAhead.
  ///
  /// In tr, this message translates to:
  /// **'Sen öndesin'**
  String get todayYouAhead;

  /// No description provided for @todayPurchasingDetail.
  ///
  /// In tr, this message translates to:
  /// **'Paran {you} büyüdü, fiyatlar {cpi} arttı'**
  String todayPurchasingDetail(String you, String cpi);

  /// No description provided for @todayLast12Months.
  ///
  /// In tr, this message translates to:
  /// **'son 12 ay'**
  String get todayLast12Months;

  /// No description provided for @todayMoveLabel.
  ///
  /// In tr, this message translates to:
  /// **'Günün hareketi'**
  String get todayMoveLabel;

  /// No description provided for @todayRealYearly.
  ///
  /// In tr, this message translates to:
  /// **'yıllık'**
  String get todayRealYearly;

  /// No description provided for @todayGoalSetAction.
  ///
  /// In tr, this message translates to:
  /// **'Hedef belirle'**
  String get todayGoalSetAction;

  /// No description provided for @todayGoalSetSub.
  ///
  /// In tr, this message translates to:
  /// **'Kalanı her gün gör'**
  String get todayGoalSetSub;

  /// No description provided for @todayGoalProgressTitle.
  ///
  /// In tr, this message translates to:
  /// **'Hedefe %{pct}'**
  String todayGoalProgressTitle(int pct);

  /// No description provided for @todayGoalLeftShort.
  ///
  /// In tr, this message translates to:
  /// **'{left} kaldı'**
  String todayGoalLeftShort(String left);

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

  /// No description provided for @sectionResult.
  ///
  /// In tr, this message translates to:
  /// **'Ne oldu?'**
  String get sectionResult;

  /// No description provided for @sectionWhy.
  ///
  /// In tr, this message translates to:
  /// **'Neden böyle?'**
  String get sectionWhy;

  /// No description provided for @sectionDetail.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntılar'**
  String get sectionDetail;

  /// No description provided for @sectionDepth.
  ///
  /// In tr, this message translates to:
  /// **'Daha fazlası'**
  String get sectionDepth;

  /// No description provided for @sectionDepthHint.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık getiri, sağlık, karakter'**
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

  /// No description provided for @identityCrypto.
  ///
  /// In tr, this message translates to:
  /// **'Kripto Para'**
  String get identityCrypto;

  /// No description provided for @pickCryptoTap.
  ///
  /// In tr, this message translates to:
  /// **'Kripto seçmek için dokun'**
  String get pickCryptoTap;

  /// No description provided for @pickCryptoPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bir kripto para seç'**
  String get pickCryptoPrompt;

  /// No description provided for @cryptoSelectedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Seçili kripto: {name}. Değiştirmek için çift dokun.'**
  String cryptoSelectedSemantics(String name);

  /// No description provided for @cryptoPickerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Kripto Paralar'**
  String get cryptoPickerTitle;

  /// No description provided for @cryptoSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Ad ya da kod ara (BTC, Ethereum…)'**
  String get cryptoSearchHint;

  /// No description provided for @cryptoLoading.
  ///
  /// In tr, this message translates to:
  /// **'Kripto listesi yükleniyor'**
  String get cryptoLoading;

  /// No description provided for @cryptoLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Kripto listesi yüklenemedi'**
  String get cryptoLoadFailed;

  /// No description provided for @cryptoSourceNote.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatlar Binance\'ten, dakikada bir güncellenir. Yatırım tavsiyesi değildir.'**
  String get cryptoSourceNote;

  /// No description provided for @priceDelayed.
  ///
  /// In tr, this message translates to:
  /// **'Gecikmeli'**
  String get priceDelayed;

  /// No description provided for @priceDelayedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat gecikmeli, son güncelleme {time}'**
  String priceDelayedSemantics(String time);

  /// No description provided for @period5Y.
  ///
  /// In tr, this message translates to:
  /// **'5 yıl'**
  String get period5Y;

  /// No description provided for @vsPeriodReturnUpper.
  ///
  /// In tr, this message translates to:
  /// **'DÖNEM GETİRİSİ'**
  String get vsPeriodReturnUpper;

  /// No description provided for @vsTodayUpper.
  ///
  /// In tr, this message translates to:
  /// **'BUGÜN'**
  String get vsTodayUpper;

  /// No description provided for @vsMaxDrawdownUpper.
  ///
  /// In tr, this message translates to:
  /// **'EN BÜYÜK DÜŞÜŞ'**
  String get vsMaxDrawdownUpper;

  /// No description provided for @vsVolatilityUpper.
  ///
  /// In tr, this message translates to:
  /// **'OYNAKLIK (YILLIK)'**
  String get vsVolatilityUpper;

  /// No description provided for @vsPeriodLow.
  ///
  /// In tr, this message translates to:
  /// **'Dönem düşüğü'**
  String get vsPeriodLow;

  /// No description provided for @vsPeriodHigh.
  ///
  /// In tr, this message translates to:
  /// **'Dönem yükseği'**
  String get vsPeriodHigh;

  /// No description provided for @vsRangePosition.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat dönem aralığının %{pct} noktasında'**
  String vsRangePosition(String pct);

  /// No description provided for @vsVolatilityShortNote.
  ///
  /// In tr, this message translates to:
  /// **'Oynaklık 1 ay ve daha uzun dönemlerde hesaplanır.'**
  String get vsVolatilityShortNote;

  /// No description provided for @adPositionUpper.
  ///
  /// In tr, this message translates to:
  /// **'POZİSYONUN'**
  String get adPositionUpper;

  /// No description provided for @adPositionLine.
  ///
  /// In tr, this message translates to:
  /// **'Pozisyonun: {amount} ({pct})'**
  String adPositionLine(String amount, String pct);

  /// Grafikte gün içi dönem başı çizgisinin etiketi: açılış saati ve değeri.
  ///
  /// In tr, this message translates to:
  /// **'AÇILIŞ · {time} · {value}'**
  String chartOpenLabel(String time, String value);

  /// No description provided for @posQuantity.
  ///
  /// In tr, this message translates to:
  /// **'Miktar'**
  String get posQuantity;

  /// No description provided for @posBuyPrice.
  ///
  /// In tr, this message translates to:
  /// **'Alış fiyatın (ortalama)'**
  String get posBuyPrice;

  /// No description provided for @posTodayPrice.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü fiyat'**
  String get posTodayPrice;

  /// No description provided for @posTotalCost.
  ///
  /// In tr, this message translates to:
  /// **'Ödediğin toplam'**
  String get posTotalCost;

  /// No description provided for @posCurrentValue.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü değer'**
  String get posCurrentValue;

  /// No description provided for @posTotalPnl.
  ///
  /// In tr, this message translates to:
  /// **'Toplam kâr/zarar'**
  String get posTotalPnl;

  /// No description provided for @posPeriodPnl.
  ///
  /// In tr, this message translates to:
  /// **'{period} kâr/zarar'**
  String posPeriodPnl(String period);

  /// Grafikte dönem başı çizgisinin etiketi: dönem başı tarihi ve değeri.
  ///
  /// In tr, this message translates to:
  /// **'BAŞLANGIÇ · {date} · {value}'**
  String chartStartLabel(String date, String value);

  /// No description provided for @chartNowLabel.
  ///
  /// In tr, this message translates to:
  /// **'ŞİMDİ'**
  String get chartNowLabel;

  /// No description provided for @vsWatch.
  ///
  /// In tr, this message translates to:
  /// **'Takip et'**
  String get vsWatch;

  /// No description provided for @vsSelect.
  ///
  /// In tr, this message translates to:
  /// **'Bunu seç'**
  String get vsSelect;

  /// No description provided for @vsGoToPosition.
  ///
  /// In tr, this message translates to:
  /// **'Pozisyonuma git'**
  String get vsGoToPosition;

  /// No description provided for @vsOwnedNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık portföyünde. Al ve sat pozisyon ekranından yapılır.'**
  String get vsOwnedNote;

  /// No description provided for @vsRemovedFromWatchlist.
  ///
  /// In tr, this message translates to:
  /// **'{name} takipten çıkarıldı'**
  String vsRemovedFromWatchlist(String name);

  /// No description provided for @vsUndo.
  ///
  /// In tr, this message translates to:
  /// **'Geri al'**
  String get vsUndo;

  /// No description provided for @vsChartSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} fiyat grafiği, {period}'**
  String vsChartSemantics(String name, String period);

  /// No description provided for @vsOpenDetailSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} grafiğini ve istatistiklerini gör'**
  String vsOpenDetailSemantics(String name);

  /// No description provided for @vsWatchSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} takibe al'**
  String vsWatchSemantics(String name);

  /// No description provided for @vsUnwatchSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} takipten çıkar'**
  String vsUnwatchSemantics(String name);

  /// No description provided for @vsLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat geçmişi alınamadı. Bağlantını kontrol edip dönemi yeniden seç.'**
  String get vsLoadFailed;

  /// No description provided for @vsSheetSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} varlık sayfası'**
  String vsSheetSemantics(String name);

  /// No description provided for @searchRecentUpper.
  ///
  /// In tr, this message translates to:
  /// **'SON BAKTIKLARIN'**
  String get searchRecentUpper;

  /// No description provided for @searchMarketsUpper.
  ///
  /// In tr, this message translates to:
  /// **'PİYASALAR'**
  String get searchMarketsUpper;

  /// No description provided for @searchShowAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümü ({count})'**
  String searchShowAll(int count);

  /// No description provided for @searchInPortfolioTag.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünde'**
  String get searchInPortfolioTag;

  /// No description provided for @searchAssetsSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Varlık ara'**
  String get searchAssetsSemantics;

  /// No description provided for @searchChip.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get searchChip;

  /// No description provided for @searchShortHint.
  ///
  /// In tr, this message translates to:
  /// **'Hisse, fon, altın, döviz, kripto'**
  String get searchShortHint;

  /// No description provided for @kullaniciAdiBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adını seç'**
  String get kullaniciAdiBaslik;

  /// No description provided for @kullaniciAdiAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Ortağın seni bu adla görür, uygulamada da bu ad görünür. Sonra Ayarlar > Hesap\'tan değiştirebilirsin.'**
  String get kullaniciAdiAciklama;

  /// No description provided for @kullaniciAdiZorunluNot.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için bir kullanıcı adı gerekiyor. Uygun bir ad seçtiğin an devam edebilirsin.'**
  String get kullaniciAdiZorunluNot;

  /// No description provided for @kullaniciAdiUygunDevam.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad uygun. Devam edebilirsin.'**
  String get kullaniciAdiUygunDevam;

  /// No description provided for @kullaniciAdiEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı'**
  String get kullaniciAdiEtiket;

  /// No description provided for @kullaniciAdiKurallar.
  ///
  /// In tr, this message translates to:
  /// **'3-20 karakter: harf, rakam, nokta ve alt çizgi. Harfle başlar, boşluk olmaz.'**
  String get kullaniciAdiKurallar;

  /// No description provided for @kullaniciAdiHataBicim.
  ///
  /// In tr, this message translates to:
  /// **'3-20 karakter olmalı; harfle başlar, yalnız harf, rakam, . ve _ içerir.'**
  String get kullaniciAdiHataBicim;

  /// No description provided for @kullaniciAdiHataUygunsuz.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad uygun değil. Başka bir ad dene.'**
  String get kullaniciAdiHataUygunsuz;

  /// No description provided for @kullaniciAdiHataAyrilmis.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad ayrılmış. Başka bir ad dene.'**
  String get kullaniciAdiHataAyrilmis;

  /// No description provided for @kullaniciAdiHataAlinmis.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad alınmış. Başka bir ad dene.'**
  String get kullaniciAdiHataAlinmis;

  /// No description provided for @kullaniciAdiHataBilinmiyor.
  ///
  /// In tr, this message translates to:
  /// **'Kaydedilemedi. Biraz sonra tekrar dene.'**
  String get kullaniciAdiHataBilinmiyor;

  /// No description provided for @kullaniciAdiUygun.
  ///
  /// In tr, this message translates to:
  /// **'Bu ad kullanılabilir.'**
  String get kullaniciAdiUygun;

  /// No description provided for @kullaniciAdiDevam.
  ///
  /// In tr, this message translates to:
  /// **'Devam et'**
  String get kullaniciAdiDevam;

  /// No description provided for @kullaniciAdiKaydet.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get kullaniciAdiKaydet;

  /// No description provided for @kullaniciAdiKaydedildi.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adın güncellendi.'**
  String get kullaniciAdiKaydedildi;

  /// No description provided for @kullaniciAdiSecilmedi.
  ///
  /// In tr, this message translates to:
  /// **'Henüz seçilmedi'**
  String get kullaniciAdiSecilmedi;

  /// No description provided for @kullaniciAdiCikis.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yap'**
  String get kullaniciAdiCikis;

  /// No description provided for @registerUsernameMissing.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıcı adı gir.'**
  String get registerUsernameMissing;

  /// No description provided for @deletedFilter.
  ///
  /// In tr, this message translates to:
  /// **'Silinenler'**
  String get deletedFilter;

  /// No description provided for @deletedEmptyTitle.
  ///
  /// In tr, this message translates to:
  /// **'Silinmiş kayıt yok'**
  String get deletedEmptyTitle;

  /// No description provided for @deletedEmptyBody.
  ///
  /// In tr, this message translates to:
  /// **'Bir varlığı sildiğinde alım, satım ve silinme tarihleri burada durur; portföy toplamına girmez.'**
  String get deletedEmptyBody;

  /// No description provided for @ipoTitle.
  ///
  /// In tr, this message translates to:
  /// **'Halka arzlar'**
  String get ipoTitle;

  /// No description provided for @ipoProfileRowSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Takvim, fiyat ve katılım kaydı'**
  String get ipoProfileRowSubtitle;

  /// No description provided for @ipoGroupTalep.
  ///
  /// In tr, this message translates to:
  /// **'Talep toplanıyor'**
  String get ipoGroupTalep;

  /// No description provided for @ipoGroupYaklasan.
  ///
  /// In tr, this message translates to:
  /// **'Yaklaşan'**
  String get ipoGroupYaklasan;

  /// No description provided for @ipoGroupIslemBekliyor.
  ///
  /// In tr, this message translates to:
  /// **'İşlem görmeyi bekliyor'**
  String get ipoGroupIslemBekliyor;

  /// No description provided for @ipoGroupIslemGoruyor.
  ///
  /// In tr, this message translates to:
  /// **'İşlem görüyor'**
  String get ipoGroupIslemGoruyor;

  /// No description provided for @ipoGroupBilinmiyor.
  ///
  /// In tr, this message translates to:
  /// **'Tarihi belirsiz'**
  String get ipoGroupBilinmiyor;

  /// No description provided for @ipoOfflineNote.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışı: {tarih} tarihli liste gösteriliyor.'**
  String ipoOfflineNote(String tarih);

  /// No description provided for @ipoOfflineNoDate.
  ///
  /// In tr, this message translates to:
  /// **'Çevrimdışı: kayıtlı liste gösteriliyor.'**
  String get ipoOfflineNoDate;

  /// No description provided for @ipoListDate.
  ///
  /// In tr, this message translates to:
  /// **'Liste tarihi: {tarih}'**
  String ipoListDate(String tarih);

  /// No description provided for @ipoEmpty.
  ///
  /// In tr, this message translates to:
  /// **'Şu an listede halka arz yok.'**
  String get ipoEmpty;

  /// No description provided for @ipoDisclaimer.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi amaçlıdır, yatırım tavsiyesi değildir. Tarih ve fiyatı aracı kurumundan doğrula.'**
  String get ipoDisclaimer;

  /// No description provided for @ipoRowTalep.
  ///
  /// In tr, this message translates to:
  /// **'Talep: {aralik}'**
  String ipoRowTalep(String aralik);

  /// No description provided for @ipoRowIslem.
  ///
  /// In tr, this message translates to:
  /// **'İşlem: {tarih}'**
  String ipoRowIslem(String tarih);

  /// No description provided for @ipoFieldTalep.
  ///
  /// In tr, this message translates to:
  /// **'Talep toplama'**
  String get ipoFieldTalep;

  /// No description provided for @ipoFieldFiyat.
  ///
  /// In tr, this message translates to:
  /// **'Halka arz fiyatı'**
  String get ipoFieldFiyat;

  /// No description provided for @ipoFieldDagitim.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtım'**
  String get ipoFieldDagitim;

  /// No description provided for @ipoFieldIslem.
  ///
  /// In tr, this message translates to:
  /// **'İşlem başlangıcı'**
  String get ipoFieldIslem;

  /// No description provided for @ipoFieldPazar.
  ///
  /// In tr, this message translates to:
  /// **'Pazar'**
  String get ipoFieldPazar;

  /// No description provided for @ipoFieldGuncelleme.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi tarihi'**
  String get ipoFieldGuncelleme;

  /// No description provided for @ipoDagitimEsit.
  ///
  /// In tr, this message translates to:
  /// **'Eşit'**
  String get ipoDagitimEsit;

  /// No description provided for @ipoDagitimOransal.
  ///
  /// In tr, this message translates to:
  /// **'Oransal'**
  String get ipoDagitimOransal;

  /// No description provided for @ipoOpenSource.
  ///
  /// In tr, this message translates to:
  /// **'Kaynağı aç'**
  String get ipoOpenSource;

  /// No description provided for @ipoSourceFailed.
  ///
  /// In tr, this message translates to:
  /// **'Bağlantı açılamadı.'**
  String get ipoSourceFailed;

  /// No description provided for @ipoParticipate.
  ///
  /// In tr, this message translates to:
  /// **'Katıldım, portföye ekle'**
  String get ipoParticipate;

  /// No description provided for @ipoParticipateHint.
  ///
  /// In tr, this message translates to:
  /// **'Sana düşen lot sayısını yaz; alış fiyatı ve tarih hazır gelir. İşlem başlayana kadar hisse portföyünde halka arz fiyatıyla görünür.'**
  String get ipoParticipateHint;

  /// No description provided for @ipoParticipateHintTraded.
  ///
  /// In tr, this message translates to:
  /// **'Sana düşen lot sayısını yaz; alış fiyatı (halka arz fiyatı) ve ilk işlem günü hazır gelir. Hisse portföyünde canlı fiyatıyla görünür.'**
  String get ipoParticipateHintTraded;

  /// No description provided for @ipoParticipateNoPrice.
  ///
  /// In tr, this message translates to:
  /// **'Halka arz fiyatı listede yok: formda alış fiyatını kendin yaz. İşlem görmeyen hissenin fiyatı bulunamaz; boş bırakırsan maliyet 0 kaydedilir.'**
  String get ipoParticipateNoPrice;

  /// No description provided for @ipoParticipateLater.
  ///
  /// In tr, this message translates to:
  /// **'Dağıtım sonuçları talep toplama bitince açıklanır. Katıldıysan o zaman buradan portföyüne ekleyebilirsin.'**
  String get ipoParticipateLater;

  /// No description provided for @ipoParticipationSaved.
  ///
  /// In tr, this message translates to:
  /// **'Halka arz lotun portföyüne eklendi.'**
  String get ipoParticipationSaved;

  /// No description provided for @txDateLabeled.
  ///
  /// In tr, this message translates to:
  /// **'{tur}: {tarih}'**
  String txDateLabeled(String tur, String tarih);

  /// No description provided for @deletedOnDate.
  ///
  /// In tr, this message translates to:
  /// **'Silinme: {tarih}'**
  String deletedOnDate(String tarih);

  /// No description provided for @pickGoldPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bir altın türü seç'**
  String get pickGoldPrompt;

  /// No description provided for @pickCurrencyPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bir döviz seç'**
  String get pickCurrencyPrompt;

  /// No description provided for @raceLive.
  ///
  /// In tr, this message translates to:
  /// **'Canlı'**
  String get raceLive;

  /// No description provided for @raceLiveJustNow.
  ///
  /// In tr, this message translates to:
  /// **'Canlı · az önce güncellendi'**
  String get raceLiveJustNow;

  /// No description provided for @raceLiveSecondsAgo.
  ///
  /// In tr, this message translates to:
  /// **'Canlı · {n} sn önce güncellendi'**
  String raceLiveSecondsAgo(int n);

  /// No description provided for @raceLiveMinutesAgo.
  ///
  /// In tr, this message translates to:
  /// **'Canlı · {n} dk önce güncellendi'**
  String raceLiveMinutesAgo(int n);

  /// No description provided for @raceYou.
  ///
  /// In tr, this message translates to:
  /// **'Sen'**
  String get raceYou;

  /// No description provided for @raceYouTag.
  ///
  /// In tr, this message translates to:
  /// **'SEN'**
  String get raceYouTag;

  /// No description provided for @raceVs.
  ///
  /// In tr, this message translates to:
  /// **'VS'**
  String get raceVs;

  /// No description provided for @raceGapToLeader.
  ///
  /// In tr, this message translates to:
  /// **'Lidere {fark} puan'**
  String raceGapToLeader(String fark);

  /// No description provided for @duelTied.
  ///
  /// In tr, this message translates to:
  /// **'Başa baş gidiyorsunuz'**
  String get duelTied;

  /// No description provided for @duelAhead.
  ///
  /// In tr, this message translates to:
  /// **'{adIyelik} {fark} puan önündesin'**
  String duelAhead(String ad, String adIyelik, String fark);

  /// No description provided for @raceRankUp.
  ///
  /// In tr, this message translates to:
  /// **'{n} sıra yükseldi'**
  String raceRankUp(int n);

  /// No description provided for @raceRankDown.
  ///
  /// In tr, this message translates to:
  /// **'{n} sıra düştü'**
  String raceRankDown(int n);

  /// No description provided for @filterButton.
  ///
  /// In tr, this message translates to:
  /// **'Filtrele'**
  String get filterButton;

  /// No description provided for @filterButtonActive.
  ///
  /// In tr, this message translates to:
  /// **'Filtrele, {n} etkin'**
  String filterButtonActive(int n);

  /// No description provided for @filterReset.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırla'**
  String get filterReset;

  /// No description provided for @filterPeriodHeader.
  ///
  /// In tr, this message translates to:
  /// **'DÖNEM'**
  String get filterPeriodHeader;

  /// No description provided for @filterTypeHeader.
  ///
  /// In tr, this message translates to:
  /// **'TÜR'**
  String get filterTypeHeader;

  /// No description provided for @filterShowN.
  ///
  /// In tr, this message translates to:
  /// **'{n} kaydı göster'**
  String filterShowN(int n);

  /// No description provided for @filterNoMatch.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen kayıt yok'**
  String get filterNoMatch;

  /// No description provided for @filterRemove.
  ///
  /// In tr, this message translates to:
  /// **'{ad} filtresini kaldır'**
  String filterRemove(String ad);

  /// No description provided for @assetTypeDeposit.
  ///
  /// In tr, this message translates to:
  /// **'Mevduat'**
  String get assetTypeDeposit;

  /// No description provided for @assetTypePension.
  ///
  /// In tr, this message translates to:
  /// **'BES'**
  String get assetTypePension;

  /// No description provided for @tickerHintDeposit.
  ///
  /// In tr, this message translates to:
  /// **'Sözleşmeden hesaplanır'**
  String get tickerHintDeposit;

  /// No description provided for @tickerHintPension.
  ///
  /// In tr, this message translates to:
  /// **'TEFAS emeklilik fonu kodu'**
  String get tickerHintPension;

  /// No description provided for @depositBank.
  ///
  /// In tr, this message translates to:
  /// **'Banka'**
  String get depositBank;

  /// No description provided for @depositBankHint.
  ///
  /// In tr, this message translates to:
  /// **'Örn. Enpara, Garanti BBVA'**
  String get depositBankHint;

  /// No description provided for @depositPrincipal.
  ///
  /// In tr, this message translates to:
  /// **'Yatırdığın tutar'**
  String get depositPrincipal;

  /// No description provided for @depositRate.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık faiz (brüt, %)'**
  String get depositRate;

  /// No description provided for @depositKindTerm.
  ///
  /// In tr, this message translates to:
  /// **'Vadeli'**
  String get depositKindTerm;

  /// No description provided for @depositKindDaily.
  ///
  /// In tr, this message translates to:
  /// **'Günlük faizli'**
  String get depositKindDaily;

  /// No description provided for @depositTerm.
  ///
  /// In tr, this message translates to:
  /// **'Vade'**
  String get depositTerm;

  /// No description provided for @depositDays.
  ///
  /// In tr, this message translates to:
  /// **'{n} gün'**
  String depositDays(int n);

  /// No description provided for @depositCustomDays.
  ///
  /// In tr, this message translates to:
  /// **'Özel'**
  String get depositCustomDays;

  /// No description provided for @depositCustomDaysHint.
  ///
  /// In tr, this message translates to:
  /// **'Gün sayısı'**
  String get depositCustomDaysHint;

  /// No description provided for @depositStart.
  ///
  /// In tr, this message translates to:
  /// **'Başlangıç'**
  String get depositStart;

  /// No description provided for @depositWithholding.
  ///
  /// In tr, this message translates to:
  /// **'Stopaj (%)'**
  String get depositWithholding;

  /// No description provided for @depositWithholdingHint.
  ///
  /// In tr, this message translates to:
  /// **'Vadeye göre önerildi. Bankan farklı uyguluyorsa düzelt.'**
  String get depositWithholdingHint;

  /// No description provided for @depositMaturity.
  ///
  /// In tr, this message translates to:
  /// **'Vade sonu'**
  String get depositMaturity;

  /// No description provided for @depositNetReturn.
  ///
  /// In tr, this message translates to:
  /// **'Net getiri'**
  String get depositNetReturn;

  /// No description provided for @depositAtMaturity.
  ///
  /// In tr, this message translates to:
  /// **'Vade sonunda'**
  String get depositAtMaturity;

  /// No description provided for @depositDailyNet.
  ///
  /// In tr, this message translates to:
  /// **'Günlük net'**
  String get depositDailyNet;

  /// No description provided for @depositErrorBank.
  ///
  /// In tr, this message translates to:
  /// **'Banka adını yaz.'**
  String get depositErrorBank;

  /// No description provided for @depositErrorPrincipal.
  ///
  /// In tr, this message translates to:
  /// **'Tutarı yaz.'**
  String get depositErrorPrincipal;

  /// No description provided for @depositErrorRate.
  ///
  /// In tr, this message translates to:
  /// **'Faiz oranını yaz.'**
  String get depositErrorRate;

  /// No description provided for @depositErrorDays.
  ///
  /// In tr, this message translates to:
  /// **'Vadeyi gün olarak yaz.'**
  String get depositErrorDays;

  /// No description provided for @depositErrorWithholding.
  ///
  /// In tr, this message translates to:
  /// **'Stopaj 0 ile 100 arasında olmalı.'**
  String get depositErrorWithholding;

  /// No description provided for @depositAccrualNote.
  ///
  /// In tr, this message translates to:
  /// **'Faiz vade sonunda anaparaya eklenir; o güne kadar değer anaparada kalır. Vadeyi erken bozarsan banka faizi ödemeyebilir.'**
  String get depositAccrualNote;

  /// No description provided for @depositCardTitle.
  ///
  /// In tr, this message translates to:
  /// **'Mevduat'**
  String get depositCardTitle;

  /// No description provided for @depositPeriodN.
  ///
  /// In tr, this message translates to:
  /// **'{n}. dönem'**
  String depositPeriodN(int n);

  /// No description provided for @depositDaysLeft.
  ///
  /// In tr, this message translates to:
  /// **'Vadeye {n} gün'**
  String depositDaysLeft(int n);

  /// No description provided for @depositMatured.
  ///
  /// In tr, this message translates to:
  /// **'Vadesi doldu'**
  String get depositMatured;

  /// No description provided for @depositMaturedBody.
  ///
  /// In tr, this message translates to:
  /// **'Faiz eklendi. Yeni dönemi başlatmak için yeni faizi gir; girmezsen değer olduğu gibi kalır.'**
  String get depositMaturedBody;

  /// No description provided for @depositThisPeriod.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönem net'**
  String get depositThisPeriod;

  /// No description provided for @depositTotalReturn.
  ///
  /// In tr, this message translates to:
  /// **'Toplam net getiri'**
  String get depositTotalReturn;

  /// No description provided for @depositRenew.
  ///
  /// In tr, this message translates to:
  /// **'Yenile'**
  String get depositRenew;

  /// No description provided for @depositWithdraw.
  ///
  /// In tr, this message translates to:
  /// **'Çektim'**
  String get depositWithdraw;

  /// No description provided for @depositRenewTitle.
  ///
  /// In tr, this message translates to:
  /// **'Yeni dönem'**
  String get depositRenewTitle;

  /// No description provided for @depositRenewSaved.
  ///
  /// In tr, this message translates to:
  /// **'Yeni dönem başladı'**
  String get depositRenewSaved;

  /// No description provided for @depositRateUpdate.
  ///
  /// In tr, this message translates to:
  /// **'Oranı güncelle'**
  String get depositRateUpdate;

  /// No description provided for @depositRateSaved.
  ///
  /// In tr, this message translates to:
  /// **'Oran güncellendi'**
  String get depositRateSaved;

  /// No description provided for @depositWithdrawTitle.
  ///
  /// In tr, this message translates to:
  /// **'Parayı çektin mi?'**
  String get depositWithdrawTitle;

  /// No description provided for @depositWithdrawBody.
  ///
  /// In tr, this message translates to:
  /// **'Mevduat bugünkü değeriyle ({amount}) satılmış olarak kaydedilir.'**
  String depositWithdrawBody(String amount);

  /// No description provided for @depositWithdrawConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Çektim, kapat'**
  String get depositWithdrawConfirm;

  /// No description provided for @depositWithdrawn.
  ///
  /// In tr, this message translates to:
  /// **'Mevduat kapatıldı'**
  String get depositWithdrawn;

  /// No description provided for @pensionCompany.
  ///
  /// In tr, this message translates to:
  /// **'Emeklilik şirketi'**
  String get pensionCompany;

  /// No description provided for @pensionCompanyHint.
  ///
  /// In tr, this message translates to:
  /// **'Örn. Anadolu Hayat'**
  String get pensionCompanyHint;

  /// No description provided for @pensionEntryDate.
  ///
  /// In tr, this message translates to:
  /// **'Sisteme giriş'**
  String get pensionEntryDate;

  /// No description provided for @pensionEntryDateHint.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısının hak ediş oranı buna bağlı.'**
  String get pensionEntryDateHint;

  /// No description provided for @pensionFunds.
  ///
  /// In tr, this message translates to:
  /// **'Fon dağılımı'**
  String get pensionFunds;

  /// No description provided for @pensionAddFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon ekle'**
  String get pensionAddFund;

  /// No description provided for @pensionShareTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam {pct}'**
  String pensionShareTotal(String pct);

  /// No description provided for @pensionShareError.
  ///
  /// In tr, this message translates to:
  /// **'Fon payları toplamı %100 olmalı.'**
  String get pensionShareError;

  /// No description provided for @pensionFundError.
  ///
  /// In tr, this message translates to:
  /// **'En az bir emeklilik fonu seç.'**
  String get pensionFundError;

  /// No description provided for @pensionGov.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı'**
  String get pensionGov;

  /// No description provided for @pensionGovFund.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı fonu'**
  String get pensionGovFund;

  /// No description provided for @pensionGovFundHint.
  ///
  /// In tr, this message translates to:
  /// **'Bilmiyorsan boş bırak; devlet katkısı eklenmez.'**
  String get pensionGovFundHint;

  /// No description provided for @pensionMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Aylık katkı'**
  String get pensionMonthly;

  /// No description provided for @pensionDay.
  ///
  /// In tr, this message translates to:
  /// **'Katkı günü'**
  String get pensionDay;

  /// No description provided for @pensionErrorCompany.
  ///
  /// In tr, this message translates to:
  /// **'Şirket adını yaz.'**
  String get pensionErrorCompany;

  /// No description provided for @pensionErrorBalance.
  ///
  /// In tr, this message translates to:
  /// **'Ana para ile getirinin toplamı sıfırdan büyük olmalı.'**
  String get pensionErrorBalance;

  /// No description provided for @pensionErrorGovFund.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı birikimi için fonu da seç.'**
  String get pensionErrorGovFund;

  /// No description provided for @pensionPriceMissing.
  ///
  /// In tr, this message translates to:
  /// **'{code} fonunun fiyatı alınamadı. Birazdan tekrar dene.'**
  String pensionPriceMissing(String code);

  /// No description provided for @pensionPickFund.
  ///
  /// In tr, this message translates to:
  /// **'Emeklilik fonu seç'**
  String get pensionPickFund;

  /// No description provided for @pensionPickGovFund.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı fonu seç'**
  String get pensionPickGovFund;

  /// No description provided for @pensionSearchFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon kodu ya da adı'**
  String get pensionSearchFund;

  /// No description provided for @pensionNoFundFound.
  ///
  /// In tr, this message translates to:
  /// **'Eşleşen emeklilik fonu yok'**
  String get pensionNoFundFound;

  /// No description provided for @pensionCardTitle.
  ///
  /// In tr, this message translates to:
  /// **'BES'**
  String get pensionCardTitle;

  /// No description provided for @pensionYear.
  ///
  /// In tr, this message translates to:
  /// **'{n}. yıl'**
  String pensionYear(int n);

  /// No description provided for @pensionTotal.
  ///
  /// In tr, this message translates to:
  /// **'Toplam birikim'**
  String get pensionTotal;

  /// No description provided for @pensionOwn.
  ///
  /// In tr, this message translates to:
  /// **'Senin katkın'**
  String get pensionOwn;

  /// No description provided for @pensionGovShort.
  ///
  /// In tr, this message translates to:
  /// **'Devlet'**
  String get pensionGovShort;

  /// No description provided for @pensionReturn.
  ///
  /// In tr, this message translates to:
  /// **'Getiri'**
  String get pensionReturn;

  /// No description provided for @pensionIfLeave.
  ///
  /// In tr, this message translates to:
  /// **'Bugün çıkarsan (vergi öncesi)'**
  String get pensionIfLeave;

  /// No description provided for @pensionVesting.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı hak ediş'**
  String get pensionVesting;

  /// No description provided for @currentValueUpper.
  ///
  /// In tr, this message translates to:
  /// **'GÜNCEL DEĞER'**
  String get currentValueUpper;

  /// No description provided for @depositCardRate.
  ///
  /// In tr, this message translates to:
  /// **'Faiz'**
  String get depositCardRate;

  /// No description provided for @depositCardRateValue.
  ///
  /// In tr, this message translates to:
  /// **'%{rate} brüt · stopaj %{wht}'**
  String depositCardRateValue(String rate, String wht);

  /// No description provided for @depositWithholdingManual.
  ///
  /// In tr, this message translates to:
  /// **'Bu oranı sen girdin; vade ya da tarih değişince öneri üstüne yazılmaz.'**
  String get depositWithholdingManual;

  /// No description provided for @depositAccrualNoteDaily.
  ///
  /// In tr, this message translates to:
  /// **'Faiz her gün sonunda net olarak eklenir; gün içinde değer değişmez.'**
  String get depositAccrualNoteDaily;

  /// No description provided for @depositAlreadyMatured.
  ///
  /// In tr, this message translates to:
  /// **'Bu dönemin vadesi {date} tarihinde dolmuş. Kaydettikten sonra karttan yeni dönemi başlatabilirsin.'**
  String depositAlreadyMatured(String date);

  /// No description provided for @depositRenewStartHint.
  ///
  /// In tr, this message translates to:
  /// **'Banka vadeli hesabı vade gününde yeniler. Başka bir günde yenilediysen tarihi değiştir; aradaki günler faizsiz sayılır.'**
  String get depositRenewStartHint;

  /// No description provided for @pensionVestingNextIn.
  ///
  /// In tr, this message translates to:
  /// **'{now} · {duration} sonra {next}'**
  String pensionVestingNextIn(String now, String duration, String next);

  /// No description provided for @pensionVestingSoon.
  ///
  /// In tr, this message translates to:
  /// **'{now} · bir ay içinde {next}'**
  String pensionVestingSoon(String now, String next);

  /// No description provided for @pensionYears.
  ///
  /// In tr, this message translates to:
  /// **'{n} yıl'**
  String pensionYears(int n);

  /// No description provided for @pensionMonths.
  ///
  /// In tr, this message translates to:
  /// **'{n} ay'**
  String pensionMonths(int n);

  /// No description provided for @pensionYearsMonths.
  ///
  /// In tr, this message translates to:
  /// **'{years} yıl {months} ay'**
  String pensionYearsMonths(int years, int months);

  /// No description provided for @dividendAboveGross.
  ///
  /// In tr, this message translates to:
  /// **'Net tutar brütten ({gross}) büyük olamaz. Alanı kontrol et.'**
  String dividendAboveGross(String gross);

  /// No description provided for @pensionAddContribution.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayın katkısını ekle'**
  String get pensionAddContribution;

  /// No description provided for @pensionContributionTitle.
  ///
  /// In tr, this message translates to:
  /// **'Katkı ekle'**
  String get pensionContributionTitle;

  /// No description provided for @pensionContributionAmount.
  ///
  /// In tr, this message translates to:
  /// **'Katkı tutarı'**
  String get pensionContributionAmount;

  /// No description provided for @pensionContributionGov.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı: {amount}'**
  String pensionContributionGov(String amount);

  /// No description provided for @pensionContributionGovCapped.
  ///
  /// In tr, this message translates to:
  /// **'Bu yılın devlet katkısı sınırı doldu.'**
  String get pensionContributionGovCapped;

  /// No description provided for @pensionContributionSaved.
  ///
  /// In tr, this message translates to:
  /// **'Katkı eklendi'**
  String get pensionContributionSaved;

  /// No description provided for @pensionContributionDue.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayın katkısı henüz eklenmedi.'**
  String get pensionContributionDue;

  /// No description provided for @pensionNoGovFund.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı fonu seçilmedi; devlet katkısı eklenmez.'**
  String get pensionNoGovFund;

  /// No description provided for @pensionPrincipal.
  ///
  /// In tr, this message translates to:
  /// **'Ana para (ödediğin katkı)'**
  String get pensionPrincipal;

  /// No description provided for @pensionPrincipalHint.
  ///
  /// In tr, this message translates to:
  /// **'Bugüne kadar cebinden yatırdığın toplam; ekstrende \"katkı payı\" diye geçer.'**
  String get pensionPrincipalHint;

  /// No description provided for @pensionGain.
  ///
  /// In tr, this message translates to:
  /// **'Getiri (kâr)'**
  String get pensionGain;

  /// No description provided for @pensionGainHint.
  ///
  /// In tr, this message translates to:
  /// **'Ekstrendeki getiri. Zarardaysan eksiyle yaz.'**
  String get pensionGainHint;

  /// No description provided for @pensionHistoryHint.
  ///
  /// In tr, this message translates to:
  /// **'Grafik, bugünkü fon paylarını fonlarının gerçek fiyat geçmişiyle değerler; geçmişte dağılımın farklıydıysa eski dönemler birebir tutmaz.'**
  String get pensionHistoryHint;

  /// No description provided for @pensionGovPrincipal.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı ana parası'**
  String get pensionGovPrincipal;

  /// No description provided for @pensionGovGain.
  ///
  /// In tr, this message translates to:
  /// **'Devlet katkısı getirisi'**
  String get pensionGovGain;

  /// No description provided for @pensionErrorPrincipal.
  ///
  /// In tr, this message translates to:
  /// **'Ana parayı yaz.'**
  String get pensionErrorPrincipal;

  /// No description provided for @pensionSwitchFunds.
  ///
  /// In tr, this message translates to:
  /// **'Fon değiştir'**
  String get pensionSwitchFunds;

  /// No description provided for @pensionSwitchTitle.
  ///
  /// In tr, this message translates to:
  /// **'Fon dağılımını değiştir'**
  String get pensionSwitchTitle;

  /// No description provided for @pensionSwitchHint.
  ///
  /// In tr, this message translates to:
  /// **'Birikimin bugünkü fiyatlarla yeni dağılıma taşınır. Ana para ve kâr değişmez; grafik bugünden sonra yeni fonlarla yürür.'**
  String get pensionSwitchHint;

  /// No description provided for @pensionSwitchContributions.
  ///
  /// In tr, this message translates to:
  /// **'Yeni katkılar da bu dağılımla gitsin'**
  String get pensionSwitchContributions;

  /// No description provided for @pensionSwitchCount.
  ///
  /// In tr, this message translates to:
  /// **'Bu yıl {n}/12 fon değişikliği'**
  String pensionSwitchCount(int n);

  /// No description provided for @pensionSwitchSaved.
  ///
  /// In tr, this message translates to:
  /// **'Fon dağılımı değişti'**
  String get pensionSwitchSaved;

  /// No description provided for @pensionSwitchSame.
  ///
  /// In tr, this message translates to:
  /// **'Dağılım zaten böyle.'**
  String get pensionSwitchSame;

  /// No description provided for @pensionSwitchNote.
  ///
  /// In tr, this message translates to:
  /// **'Fon değişikliği'**
  String get pensionSwitchNote;

  /// No description provided for @contractManagedNotice.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık sözleşmeden yönetilir. Değiştirmek için varlık sayfasındaki sözleşme kartını kullan.'**
  String get contractManagedNotice;

  /// Yarış, kendi satırının altında: XIRR, Performans › Özet ile aynı sayı (R1, 2026-10-01)
  ///
  /// In tr, this message translates to:
  /// **'Paranın getirisi {pct}'**
  String raceMoneyReturn(String pct);

  /// No description provided for @raceMoneyReturnHint.
  ///
  /// In tr, this message translates to:
  /// **'Para ekleme zamanı dahil · Performans ile aynı'**
  String get raceMoneyReturnHint;

  /// Kıyas kartı başlığı (Özet sekmesi)
  ///
  /// In tr, this message translates to:
  /// **'Başka yere koysaydın'**
  String get kiyasBaslik;

  /// Kıyas kartı açıklaması; satırların ne anlattığı
  ///
  /// In tr, this message translates to:
  /// **'Aynı paraları aynı günlerde buraya yatırsaydın.'**
  String get kiyasAciklama;

  /// Kıyas kartında kullanıcının kendi satırı
  ///
  /// In tr, this message translates to:
  /// **'Senin portföyün'**
  String get kiyasSenin;

  /// Kıyasla aradaki fark sıfıra yuvarlandığında
  ///
  /// In tr, this message translates to:
  /// **'Başa baş'**
  String get kiyasBasaBas;

  /// Dönemde nakit temettü varken kıyas kartının dipnotu
  ///
  /// In tr, this message translates to:
  /// **'Bu dönemdeki nakit temettüler iki tarafta da cebine giren para sayıldı.'**
  String get kiyasTemettuNotu;

  /// Kıyas kartı: hiçbir kıyas hesaplanamadığında
  ///
  /// In tr, this message translates to:
  /// **'Kıyas için fiyat verisi şu an alınamadı.'**
  String get kiyasVeriYok;

  /// No description provided for @pensionDayHint.
  ///
  /// In tr, this message translates to:
  /// **'Örn. 15'**
  String get pensionDayHint;

  /// No description provided for @pensionDayNote.
  ///
  /// In tr, this message translates to:
  /// **'Aylık katkının her ay hesabından çekildiği gün. 29-31 her ayda olmadığı için en fazla 28; ay sonunda çekiliyorsa 28 yaz.'**
  String get pensionDayNote;

  /// No description provided for @pensionDayError.
  ///
  /// In tr, this message translates to:
  /// **'1 ile 28 arasında bir gün yaz.'**
  String get pensionDayError;

  /// No description provided for @pensionAuto.
  ///
  /// In tr, this message translates to:
  /// **'Katkıyı otomatik ekle'**
  String get pensionAuto;

  /// No description provided for @pensionAutoNote.
  ///
  /// In tr, this message translates to:
  /// **'Katkı günü gelince aylık katkını o günün fon fiyatıyla ekleriz, sonra tutarı sana sorarız. Kapalıysa yalnızca hatırlatırız.'**
  String get pensionAutoNote;

  /// No description provided for @pensionAutoNeedsPlan.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik ekleme için aylık katkıyı ve katkı gününü yaz.'**
  String get pensionAutoNeedsPlan;

  /// No description provided for @pensionAutoLotNote.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik katkı'**
  String get pensionAutoLotNote;

  /// No description provided for @pensionAutoAdded.
  ///
  /// In tr, this message translates to:
  /// **'{date} katkın otomatik eklendi: {amount}. Tutarı güncellemek ister misin?'**
  String pensionAutoAdded(String date, String amount);

  /// No description provided for @pensionAutoConfirm.
  ///
  /// In tr, this message translates to:
  /// **'Tutar doğru'**
  String get pensionAutoConfirm;

  /// No description provided for @pensionAutoUpdate.
  ///
  /// In tr, this message translates to:
  /// **'Tutarı güncelle'**
  String get pensionAutoUpdate;

  /// No description provided for @pensionAutoUpdateTitle.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik katkıyı güncelle'**
  String get pensionAutoUpdateTitle;

  /// No description provided for @pensionAutoUpdatePlan.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki aylar da bu tutarla eklensin'**
  String get pensionAutoUpdatePlan;

  /// No description provided for @pensionAutoUpdated.
  ///
  /// In tr, this message translates to:
  /// **'Katkı güncellendi'**
  String get pensionAutoUpdated;

  /// No description provided for @pensionAutoSnack.
  ///
  /// In tr, this message translates to:
  /// **'{count, plural, =1{BES katkın otomatik eklendi. Tutarı BES kartından güncelleyebilirsin.} other{{count} aylık BES katkın otomatik eklendi. Tutarı BES kartından güncelleyebilirsin.}}'**
  String pensionAutoSnack(int count);

  /// No description provided for @pensionAddExtraContribution.
  ///
  /// In tr, this message translates to:
  /// **'Ek katkı ekle'**
  String get pensionAddExtraContribution;

  /// No description provided for @cpiSentenceMonth.
  ///
  /// In tr, this message translates to:
  /// **'{month} ayında birikimin {change}, aylık enflasyon {cpi} oldu.'**
  String cpiSentenceMonth(String month, String change, String cpi);

  /// No description provided for @cpiSentenceRange.
  ///
  /// In tr, this message translates to:
  /// **'{start} - {end} arasında birikimin {change}, enflasyon {cpi} oldu.'**
  String cpiSentenceRange(String start, String end, String change, String cpi);

  /// No description provided for @cpiSentenceYear.
  ///
  /// In tr, this message translates to:
  /// **'Son bir yılda ({start} - {end}) birikimin {change}, enflasyon {cpi} oldu.'**
  String cpiSentenceYear(String start, String end, String change, String cpi);

  /// No description provided for @cpiSentenceSinceFirstBuy.
  ///
  /// In tr, this message translates to:
  /// **'İlk alımından ({date}) {end} sonuna birikimin {change}, enflasyon {cpi} oldu.'**
  String cpiSentenceSinceFirstBuy(
      String date, String end, String change, String cpi);

  /// No description provided for @savingsRose.
  ///
  /// In tr, this message translates to:
  /// **'{pct} arttı'**
  String savingsRose(String pct);

  /// No description provided for @savingsFell.
  ///
  /// In tr, this message translates to:
  /// **'{pct} azaldı'**
  String savingsFell(String pct);

  /// No description provided for @savingsFlat.
  ///
  /// In tr, this message translates to:
  /// **'değişmedi'**
  String get savingsFlat;

  /// No description provided for @purchasingPowerUp.
  ///
  /// In tr, this message translates to:
  /// **'alım gücün arttı.'**
  String get purchasingPowerUp;

  /// No description provided for @purchasingPowerDown.
  ///
  /// In tr, this message translates to:
  /// **'alım gücün geriledi.'**
  String get purchasingPowerDown;

  /// No description provided for @purchasingPowerKept.
  ///
  /// In tr, this message translates to:
  /// **'alım gücün korundu.'**
  String get purchasingPowerKept;

  /// No description provided for @cpiNextNote.
  ///
  /// In tr, this message translates to:
  /// **'{month} TÜFE\'si {date} tarihinde açıklanınca karşılaştırma {month} ayını da kapsar.'**
  String cpiNextNote(String month, String date);

  /// No description provided for @cpiNextNoteLate.
  ///
  /// In tr, this message translates to:
  /// **'{month} TÜFE\'si yüklenince karşılaştırma {month} ayını da kapsar.'**
  String cpiNextNoteLate(String month);

  /// No description provided for @cpiShortenedNote.
  ///
  /// In tr, this message translates to:
  /// **'Bu kadar geriye giden TÜFE verisi yok; karşılaştırma {month} ayından başlıyor.'**
  String cpiShortenedNote(String month);

  /// No description provided for @cpiHowComputed.
  ///
  /// In tr, this message translates to:
  /// **'Nasıl hesaplandı'**
  String get cpiHowComputed;

  /// No description provided for @compoundRealReturn.
  ///
  /// In tr, this message translates to:
  /// **'Bileşik reel getiri'**
  String get compoundRealReturn;

  /// No description provided for @cpiSourceLabel.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak'**
  String get cpiSourceLabel;

  /// No description provided for @cpiSourceValue.
  ///
  /// In tr, this message translates to:
  /// **'TÜİK TÜFE'**
  String get cpiSourceValue;

  /// No description provided for @vsInflationIn.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyona göre ({window})'**
  String vsInflationIn(String window);

  /// No description provided for @investedRow.
  ///
  /// In tr, this message translates to:
  /// **'Yatırdığın'**
  String get investedRow;

  /// No description provided for @marketAddedRow.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat etkisi'**
  String get marketAddedRow;

  /// No description provided for @dividendPocketRow.
  ///
  /// In tr, this message translates to:
  /// **'Cebine aldığın temettü'**
  String get dividendPocketRow;

  /// No description provided for @flowBuyBalance.
  ///
  /// In tr, this message translates to:
  /// **'Alım +{flow} · toplam {change}'**
  String flowBuyBalance(String flow, String change);

  /// No description provided for @flowSellBalance.
  ///
  /// In tr, this message translates to:
  /// **'Satış −{flow} · toplam {change}'**
  String flowSellBalance(String flow, String change);

  /// No description provided for @ofLastNMonths.
  ///
  /// In tr, this message translates to:
  /// **'Son {n} ayın'**
  String ofLastNMonths(String n);

  /// No description provided for @ofLastNWeeks.
  ///
  /// In tr, this message translates to:
  /// **'Son {n} haftanın'**
  String ofLastNWeeks(String n);

  /// No description provided for @ofLastNYears.
  ///
  /// In tr, this message translates to:
  /// **'Son {n} yılın'**
  String ofLastNYears(String n);

  /// No description provided for @inMonthPhrase.
  ///
  /// In tr, this message translates to:
  /// **'{month} ayında'**
  String inMonthPhrase(String month);

  /// No description provided for @inWeekPhrase.
  ///
  /// In tr, this message translates to:
  /// **'{date} haftasında'**
  String inWeekPhrase(String date);

  /// No description provided for @inYearPhrase.
  ///
  /// In tr, this message translates to:
  /// **'{year} yılında'**
  String inYearPhrase(String year);

  /// No description provided for @singleContribution.
  ///
  /// In tr, this message translates to:
  /// **'{period} yalnızca birinde para yatırdın: {bucket} {amount}.'**
  String singleContribution(String period, String bucket, String amount);

  /// No description provided for @singleWithdrawal.
  ///
  /// In tr, this message translates to:
  /// **'{bucket} {amount} çektin.'**
  String singleWithdrawal(String bucket, String amount);

  /// No description provided for @onlySalesInWindow.
  ///
  /// In tr, this message translates to:
  /// **'Bu pencerede yeni para girmedi; satış var: {bucket} {amount}.'**
  String onlySalesInWindow(String bucket, String amount);

  /// No description provided for @onlySalesInWindowTotal.
  ///
  /// In tr, this message translates to:
  /// **'Bu pencerede yeni para girmedi; toplam {amount} satış var.'**
  String onlySalesInWindowTotal(String amount);

  /// No description provided for @marketPound.
  ///
  /// In tr, this message translates to:
  /// **'Sterlin'**
  String get marketPound;

  /// No description provided for @depositInterestAtMaturity.
  ///
  /// In tr, this message translates to:
  /// **'Vade sonunda net faiz'**
  String get depositInterestAtMaturity;

  /// No description provided for @depositInterestAdded.
  ///
  /// In tr, this message translates to:
  /// **'Eklenen net faiz'**
  String get depositInterestAdded;

  /// No description provided for @depositPaidAtMaturityNote.
  ///
  /// In tr, this message translates to:
  /// **'Faiz vade sonunda eklenir; o güne kadar değer anaparada kalır. Vade içinde oranı güncellersen kazanç son girdiğin orana göre hesaplanır.'**
  String get depositPaidAtMaturityNote;

  /// No description provided for @depositRateMidTermHint.
  ///
  /// In tr, this message translates to:
  /// **'Vade ve başlangıç aynı kalır. Vade sonundaki kazanç bu yeni orana göre hesaplanır.'**
  String get depositRateMidTermHint;

  /// No description provided for @depositRateSavedMidTerm.
  ///
  /// In tr, this message translates to:
  /// **'Oran %{rate} oldu. Vade sonundaki kazanç bu orana göre hesaplanacak.'**
  String depositRateSavedMidTerm(String rate);

  /// No description provided for @depositStripRate.
  ///
  /// In tr, this message translates to:
  /// **'%{rate} brüt faiz'**
  String depositStripRate(String rate);

  /// No description provided for @cihazOtpBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazı doğrula'**
  String get cihazOtpBaslik;

  /// No description provided for @cihazOtpAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın listede olmayan bir cihazda açılıyor. Güvenliğin için e-postana gönderdiğimiz kodu gir.'**
  String get cihazOtpAciklama;

  /// No description provided for @cihazOtpIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Bu sen değilsen vazgeç ve şifreni değiştir. Doğrulanan cihaz, diğer cihazlardaki oturumu kapatır.'**
  String get cihazOtpIpucu;

  /// No description provided for @cihazOtpVazgec.
  ///
  /// In tr, this message translates to:
  /// **'Vazgeç ve çıkış yap'**
  String get cihazOtpVazgec;

  /// No description provided for @cihazKapisiHata.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz doğrulanamadı. Bağlantını kontrol edip tekrar dene.'**
  String get cihazKapisiHata;

  /// No description provided for @baskaCihazdaAcildi.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın başka bir cihazda açıldı. Bu cihazda oturum kapatıldı.'**
  String get baskaCihazdaAcildi;

  /// No description provided for @kayitliCihazlar.
  ///
  /// In tr, this message translates to:
  /// **'Giriş yaptığın cihazlar'**
  String get kayitliCihazlar;

  /// No description provided for @kayitliCihazlarAlt.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın aynı anda tek cihazda açık kalır'**
  String get kayitliCihazlarAlt;

  /// No description provided for @kayitliCihazlarAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Hesabın aynı anda yalnızca bir cihazda açık olabilir. Listede olmayan bir cihazdan giriş yapılınca e-postana doğrulama kodu gönderilir. Tanımadığın bir cihazı kaldır ve şifreni değiştir.'**
  String get kayitliCihazlarAciklama;

  /// No description provided for @buCihaz.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihaz'**
  String get buCihaz;

  /// No description provided for @cihazSonKullanim.
  ///
  /// In tr, this message translates to:
  /// **'Son kullanım: {tarih}'**
  String cihazSonKullanim(String tarih);

  /// No description provided for @cihazKaldir.
  ///
  /// In tr, this message translates to:
  /// **'Kaldır'**
  String get cihazKaldir;

  /// No description provided for @cihazKaldirBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz kaldırılsın mı?'**
  String get cihazKaldirBaslik;

  /// No description provided for @cihazKaldirMesaj.
  ///
  /// In tr, this message translates to:
  /// **'{ad} bir sonraki girişte e-posta koduyla yeniden doğrulanmak zorunda kalır.'**
  String cihazKaldirMesaj(String ad);

  /// No description provided for @cihazKaldirildi.
  ///
  /// In tr, this message translates to:
  /// **'Cihaz kaldırıldı'**
  String get cihazKaldirildi;

  /// No description provided for @cihazListesiBos.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlı cihaz yok.'**
  String get cihazListesiBos;

  /// No description provided for @otpSpamIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Kod gelmediyse Gereksiz / Spam klasörüne de bak.'**
  String get otpSpamIpucu;

  /// No description provided for @welcomeSkip.
  ///
  /// In tr, this message translates to:
  /// **'Atla'**
  String get welcomeSkip;

  /// No description provided for @welcomeNext.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get welcomeNext;

  /// No description provided for @welcomeCreateAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesap oluştur'**
  String get welcomeCreateAccount;

  /// No description provided for @welcomeTryDemo.
  ///
  /// In tr, this message translates to:
  /// **'Örnek portföye göz at'**
  String get welcomeTryDemo;

  /// No description provided for @welcomeHaveAccount.
  ///
  /// In tr, this message translates to:
  /// **'Hesabım var, giriş yap'**
  String get welcomeHaveAccount;

  /// No description provided for @welcomePageOf.
  ///
  /// In tr, this message translates to:
  /// **'Tanıtım, sayfa {sayfa} / {toplam}'**
  String welcomePageOf(int sayfa, int toplam);

  /// No description provided for @welcomeP1Title.
  ///
  /// In tr, this message translates to:
  /// **'Tüm birikimin tek ekranda'**
  String get welcomeP1Title;

  /// No description provided for @welcomeP1Body.
  ///
  /// In tr, this message translates to:
  /// **'Ne aldığını bir kez yaz, fiyatları sandık güncellesin. Toplamını, kârını ve dağılımını her an gör.'**
  String get welcomeP1Body;

  /// No description provided for @welcomeP2Title.
  ///
  /// In tr, this message translates to:
  /// **'Gerçekten kazanıyor musun?'**
  String get welcomeP2Title;

  /// No description provided for @welcomeP2Body.
  ///
  /// In tr, this message translates to:
  /// **'Getirini enflasyonla, dolarla ve altınla kıyasla. Yeni alımlar değil, paranın kendisinin ne getirdiğini gör.'**
  String get welcomeP2Body;

  /// No description provided for @welcomeP3Title.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı açmadan takip et'**
  String get welcomeP3Title;

  /// No description provided for @welcomeP3Body.
  ///
  /// In tr, this message translates to:
  /// **'Ana ekran widget\'ı ve sabah özeti portföyünü sana getirir. iPhone\'da kilit ekranında canlı takip edersin.'**
  String get welcomeP3Body;

  /// No description provided for @welcomeP4Title.
  ///
  /// In tr, this message translates to:
  /// **'Alarm kur, birlikte takip et'**
  String get welcomeP4Title;

  /// No description provided for @welcomeP4Body.
  ///
  /// In tr, this message translates to:
  /// **'Hedef fiyata gelince haber verelim. Eşinle ya da ailenle ortak portföyü birlikte izle.'**
  String get welcomeP4Body;

  /// No description provided for @welcomeTagStock.
  ///
  /// In tr, this message translates to:
  /// **'Hisse'**
  String get welcomeTagStock;

  /// No description provided for @welcomeTagFund.
  ///
  /// In tr, this message translates to:
  /// **'Fon'**
  String get welcomeTagFund;

  /// No description provided for @welcomeTagGold.
  ///
  /// In tr, this message translates to:
  /// **'Altın'**
  String get welcomeTagGold;

  /// No description provided for @welcomeTagFx.
  ///
  /// In tr, this message translates to:
  /// **'Döviz'**
  String get welcomeTagFx;

  /// No description provided for @welcomeTagCrypto.
  ///
  /// In tr, this message translates to:
  /// **'Kripto'**
  String get welcomeTagCrypto;

  /// No description provided for @welcomeTagPension.
  ///
  /// In tr, this message translates to:
  /// **'BES'**
  String get welcomeTagPension;

  /// No description provided for @welcomeTagInflation.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyon'**
  String get welcomeTagInflation;

  /// No description provided for @welcomeTagUsd.
  ///
  /// In tr, this message translates to:
  /// **'Dolar'**
  String get welcomeTagUsd;

  /// No description provided for @welcomeTagWidget.
  ///
  /// In tr, this message translates to:
  /// **'Widget'**
  String get welcomeTagWidget;

  /// No description provided for @welcomeTagLock.
  ///
  /// In tr, this message translates to:
  /// **'Kilit ekranı'**
  String get welcomeTagLock;

  /// No description provided for @welcomeTagBrief.
  ///
  /// In tr, this message translates to:
  /// **'Sabah özeti'**
  String get welcomeTagBrief;

  /// No description provided for @welcomeTagAlarm.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmı'**
  String get welcomeTagAlarm;

  /// No description provided for @welcomeTagPartner.
  ///
  /// In tr, this message translates to:
  /// **'Ortak portföy'**
  String get welcomeTagPartner;

  /// No description provided for @levelBeginnerDescSade.
  ///
  /// In tr, this message translates to:
  /// **'Sade görünüm: yalnızca temel rakamlar. Teknik sinyaller, grafik araçları ve ileri metrikler gizlenir.'**
  String get levelBeginnerDescSade;

  /// No description provided for @levelSurveyIntro.
  ///
  /// In tr, this message translates to:
  /// **'Üç kısa soru; ekranları sana göre ayarlayalım.'**
  String get levelSurveyIntro;

  /// No description provided for @levelSurveyProgress.
  ///
  /// In tr, this message translates to:
  /// **'Soru {no} / {toplam}'**
  String levelSurveyProgress(int no, int toplam);

  /// No description provided for @levelSurveyQ1.
  ///
  /// In tr, this message translates to:
  /// **'Ne kadar süredir yatırım yapıyorsun?'**
  String get levelSurveyQ1;

  /// No description provided for @levelSurveyQ1A0.
  ///
  /// In tr, this message translates to:
  /// **'Yeni başlıyorum'**
  String get levelSurveyQ1A0;

  /// No description provided for @levelSurveyQ1A1.
  ///
  /// In tr, this message translates to:
  /// **'1-3 yıldır'**
  String get levelSurveyQ1A1;

  /// No description provided for @levelSurveyQ1A2.
  ///
  /// In tr, this message translates to:
  /// **'3 yıldan fazla'**
  String get levelSurveyQ1A2;

  /// No description provided for @levelSurveyQ2.
  ///
  /// In tr, this message translates to:
  /// **'Birikimin daha çok nerede?'**
  String get levelSurveyQ2;

  /// No description provided for @levelSurveyQ2A0.
  ///
  /// In tr, this message translates to:
  /// **'Altın, döviz, mevduat'**
  String get levelSurveyQ2A0;

  /// No description provided for @levelSurveyQ2A1.
  ///
  /// In tr, this message translates to:
  /// **'Fon ve hisse'**
  String get levelSurveyQ2A1;

  /// No description provided for @levelSurveyQ2A2.
  ///
  /// In tr, this message translates to:
  /// **'Aktif hisse ve kripto alım satımı'**
  String get levelSurveyQ2A2;

  /// No description provided for @levelSurveyQ3.
  ///
  /// In tr, this message translates to:
  /// **'Bu terimlerden hangileri sana tanıdık?'**
  String get levelSurveyQ3;

  /// No description provided for @levelSurveyQ3A0.
  ///
  /// In tr, this message translates to:
  /// **'Pek tanıdık değil'**
  String get levelSurveyQ3A0;

  /// No description provided for @levelSurveyQ3A1.
  ///
  /// In tr, this message translates to:
  /// **'Enflasyona göre getiri, dağılım'**
  String get levelSurveyQ3A1;

  /// No description provided for @levelSurveyQ3A2.
  ///
  /// In tr, this message translates to:
  /// **'Oynaklık, XIRR, RSI'**
  String get levelSurveyQ3A2;

  /// No description provided for @levelSurveyResult.
  ///
  /// In tr, this message translates to:
  /// **'Sana {seviye} görünümü uygun.'**
  String levelSurveyResult(String seviye);

  /// No description provided for @levelSurveyResultNote.
  ///
  /// In tr, this message translates to:
  /// **'İstediğin an Ayarlar › Görünüm\'den değiştirebilirsin.'**
  String get levelSurveyResultNote;

  /// No description provided for @levelSurveyRetake.
  ///
  /// In tr, this message translates to:
  /// **'Anketi yeniden yap'**
  String get levelSurveyRetake;

  /// No description provided for @levelSurveyOpen.
  ///
  /// In tr, this message translates to:
  /// **'3 soruyla seviyemi bul'**
  String get levelSurveyOpen;

  /// No description provided for @levelSurveyBack.
  ///
  /// In tr, this message translates to:
  /// **'Geri'**
  String get levelSurveyBack;

  /// No description provided for @todaysReturn.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü getirin'**
  String get todaysReturn;

  /// No description provided for @returnSince.
  ///
  /// In tr, this message translates to:
  /// **'{date} itibarıyla getirin'**
  String returnSince(String date);

  /// No description provided for @balanceChangeInclBuys.
  ///
  /// In tr, this message translates to:
  /// **'Toplam değişim (alımlar dahil)'**
  String get balanceChangeInclBuys;

  /// No description provided for @firstAssetPickTitle.
  ///
  /// In tr, this message translates to:
  /// **'Ne biriktiriyorsun?'**
  String get firstAssetPickTitle;

  /// No description provided for @firstAssetPickHint.
  ///
  /// In tr, this message translates to:
  /// **'Seç, miktarını yaz; fiyat kendiliğinden gelir.'**
  String get firstAssetPickHint;

  /// No description provided for @firstAssetGoldGram.
  ///
  /// In tr, this message translates to:
  /// **'Gram altın'**
  String get firstAssetGoldGram;

  /// No description provided for @firstAssetUsd.
  ///
  /// In tr, this message translates to:
  /// **'Dolar'**
  String get firstAssetUsd;

  /// No description provided for @firstAssetEur.
  ///
  /// In tr, this message translates to:
  /// **'Euro'**
  String get firstAssetEur;

  /// No description provided for @firstAssetFund.
  ///
  /// In tr, this message translates to:
  /// **'Bir fon'**
  String get firstAssetFund;

  /// No description provided for @firstAssetStock.
  ///
  /// In tr, this message translates to:
  /// **'Bir hisse'**
  String get firstAssetStock;

  /// No description provided for @firstAssetOtherType.
  ///
  /// In tr, this message translates to:
  /// **'Başka bir tür ekle'**
  String get firstAssetOtherType;

  /// No description provided for @addDetails.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntı ekle (komisyon, not)'**
  String get addDetails;

  /// No description provided for @addByTyping.
  ///
  /// In tr, this message translates to:
  /// **'Yazarak ekle'**
  String get addByTyping;

  /// No description provided for @importFromStatement.
  ///
  /// In tr, this message translates to:
  /// **'Ekstreden aktar'**
  String get importFromStatement;

  /// No description provided for @orWithEmail.
  ///
  /// In tr, this message translates to:
  /// **'veya e-postayla'**
  String get orWithEmail;

  /// No description provided for @todayTopMoverLabel.
  ///
  /// In tr, this message translates to:
  /// **'En çok oynayan'**
  String get todayTopMoverLabel;

  /// No description provided for @todayVsInflationYou.
  ///
  /// In tr, this message translates to:
  /// **'Getirin'**
  String get todayVsInflationYou;

  /// No description provided for @todayVsInflationCpi.
  ///
  /// In tr, this message translates to:
  /// **'TÜFE'**
  String get todayVsInflationCpi;

  /// No description provided for @vitrinWelcome.
  ///
  /// In tr, this message translates to:
  /// **'Hoş geldin'**
  String get vitrinWelcome;

  /// No description provided for @vitrinTitle.
  ///
  /// In tr, this message translates to:
  /// **'Neye sahipsin?'**
  String get vitrinTitle;

  /// No description provided for @vitrinHint.
  ///
  /// In tr, this message translates to:
  /// **'Dokun, miktarını yaz. Fiyat canlı gelir, sandığın kendini günceller.'**
  String get vitrinHint;

  /// No description provided for @vitrinLive.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatlar canlı'**
  String get vitrinLive;

  /// No description provided for @vitrinQuarterGold.
  ///
  /// In tr, this message translates to:
  /// **'Çeyrek altın'**
  String get vitrinQuarterGold;

  /// No description provided for @vitrinFundHint.
  ///
  /// In tr, this message translates to:
  /// **'TEFAS\'taki tüm fonlar'**
  String get vitrinFundHint;

  /// No description provided for @vitrinStockHint.
  ///
  /// In tr, this message translates to:
  /// **'Borsa İstanbul'**
  String get vitrinStockHint;

  /// No description provided for @vitrinOtherTypes.
  ///
  /// In tr, this message translates to:
  /// **'Kripto, emtia, mevduat, BES ve diğerleri'**
  String get vitrinOtherTypes;

  /// No description provided for @vitrinOtherTypesShort.
  ///
  /// In tr, this message translates to:
  /// **'Kripto, BES ve diğer türler'**
  String get vitrinOtherTypesShort;

  /// No description provided for @vitrinStatementHint.
  ///
  /// In tr, this message translates to:
  /// **'Aracı kurum PDF, Excel ya da CSV; hepsi tek seferde'**
  String get vitrinStatementHint;

  /// No description provided for @vitrinStatementHintShort.
  ///
  /// In tr, this message translates to:
  /// **'PDF, Excel ya da CSV; tek seferde'**
  String get vitrinStatementHintShort;

  /// No description provided for @vitrinTapToAdd.
  ///
  /// In tr, this message translates to:
  /// **'Eklemek için dokun'**
  String get vitrinTapToAdd;

  /// No description provided for @vitrinPriceUnknown.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat henüz yok'**
  String get vitrinPriceUnknown;

  /// No description provided for @rankingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama'**
  String get rankingTitle;

  /// No description provided for @rankingTabPartners.
  ///
  /// In tr, this message translates to:
  /// **'Ortaklarım'**
  String get rankingTabPartners;

  /// No description provided for @rankingTabEveryone.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedekiler'**
  String get rankingTabEveryone;

  /// No description provided for @todaysPortfolioBadge.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü portföyle'**
  String get todaysPortfolioBadge;

  /// No description provided for @todaysPortfolioBadgeHint.
  ///
  /// In tr, this message translates to:
  /// **'Bu görünümü Ayarlar › Görünüm\'den kapatabilirsin.'**
  String get todaysPortfolioBadgeHint;

  /// No description provided for @todaysPortfolioSettingTitle.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü portföyle göster'**
  String get todaysPortfolioSettingTitle;

  /// No description provided for @todaysPortfolioSettingSubtitle.
  ///
  /// In tr, this message translates to:
  /// **'Performans, bugünkü varlıklarını dönem boyunca elinde tutmuşsun gibi çizilir. Kapalıyken gerçek geçmişin görünür.'**
  String get todaysPortfolioSettingSubtitle;

  /// No description provided for @settingsGroupGeneral.
  ///
  /// In tr, this message translates to:
  /// **'GENEL'**
  String get settingsGroupGeneral;

  /// No description provided for @settingsGroupPortfolioView.
  ///
  /// In tr, this message translates to:
  /// **'PORTFÖY GÖRÜNÜMÜ'**
  String get settingsGroupPortfolioView;

  /// No description provided for @settingsGroupSecurityAccount.
  ///
  /// In tr, this message translates to:
  /// **'GÜVENLİK VE HESAP'**
  String get settingsGroupSecurityAccount;

  /// No description provided for @settingsGroupData.
  ///
  /// In tr, this message translates to:
  /// **'VERİ'**
  String get settingsGroupData;

  /// No description provided for @settingsGroupAbout.
  ///
  /// In tr, this message translates to:
  /// **'UYGULAMA HAKKINDA'**
  String get settingsGroupAbout;

  /// No description provided for @settingsAdvancedUpper.
  ///
  /// In tr, this message translates to:
  /// **'GELİŞMİŞ'**
  String get settingsAdvancedUpper;

  /// No description provided for @settingsAdvancedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Gelişmiş ayarlar'**
  String get settingsAdvancedSemantics;

  /// No description provided for @settingsThemeLabel.
  ///
  /// In tr, this message translates to:
  /// **'Tema'**
  String get settingsThemeLabel;

  /// No description provided for @settingsBaseCurrencyLabel.
  ///
  /// In tr, this message translates to:
  /// **'Baz para birimi'**
  String get settingsBaseCurrencyLabel;

  /// No description provided for @tekOnayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Yasal Koşullar'**
  String get tekOnayBaslik;

  /// Tek onay kutusunun açıklaması (kutu 1.1, 2026-10-05: açık rıza cümlesi çıktı — rıza yalnız Açık Rıza Metni'nin sonunda verilir). ulke = bağlanılan Supabase projesinin ülkesi (SunucuSecimi), bilinmiyorsa tekOnayUlkeBilinmiyor.
  ///
  /// In tr, this message translates to:
  /// **'Uygulama yatırım tavsiyesi değildir; gösterilen fiyatlar ve teknik analiz bilgi amaçlıdır. Verilerin Supabase ({ulke}) ve Firebase (ABD/Küresel) üzerinde saklanır; ayrıntısı Gizlilik Politikası ve KVKK Aydınlatma Metni\'nde.'**
  String tekOnayAciklama(String ulke);

  /// No description provided for @tekOnayUlkeBilinmiyor.
  ///
  /// In tr, this message translates to:
  /// **'yurt dışı'**
  String get tekOnayUlkeBilinmiyor;

  /// Kayıt formunun ve yeniden onay kapısının tek onay kutusu (kutu 1.1, 2026-10-05). Kullanım Koşulları sözleşmedir, kutuyla kabul edilir; Gizlilik ve KVKK bilgilendirmedir, 'kabul' değil 'bilgilendirildim' denir. AÇIK RIZA İÇERMEZ: rıza yalnız Açık Rıza Metni'nin sonunda verilir (başka beyanla paketlenmez). kosullar, gizlilik ve kvkk yerine dokunulabilir bağlantı metinleri gelir (tekOnayKosullarBaglanti, tekOnayGizlilikBaglanti, tekOnayKvkkBaglanti). Okunan cümle değişirse kutu sürümü artar (YasalMetinKatalogu.kutuSurumu).
  ///
  /// In tr, this message translates to:
  /// **'{kosullar}\'nı kabul ediyorum ve 18 yaşından büyüğüm. {gizlilik} ve {kvkk} ile bilgilendirildim.'**
  String tekOnayCumle(String kosullar, String gizlilik, String kvkk);

  /// No description provided for @tekOnayKosullarBaglanti.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları'**
  String get tekOnayKosullarBaglanti;

  /// No description provided for @tekOnayKvkkBaglanti.
  ///
  /// In tr, this message translates to:
  /// **'KVKK Aydınlatma Metni'**
  String get tekOnayKvkkBaglanti;

  /// No description provided for @tekOnayGerekli.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için kutuyu işaretleyip Kullanım Koşulları\'nı kabul etmelisin.'**
  String get tekOnayGerekli;

  /// No description provided for @arenaMeasuring.
  ///
  /// In tr, this message translates to:
  /// **'Fark ölçülüyor…'**
  String get arenaMeasuring;

  /// No description provided for @arenaBehind.
  ///
  /// In tr, this message translates to:
  /// **'{ad} {fark} puan önde · yetişebilirsin'**
  String arenaBehind(String ad, String fark);

  /// No description provided for @arenaNoDataYet.
  ///
  /// In tr, this message translates to:
  /// **'Henüz veri yok'**
  String get arenaNoDataYet;

  /// No description provided for @arenaWaiting.
  ///
  /// In tr, this message translates to:
  /// **'Getiriler ölçülünce düello başlar'**
  String get arenaWaiting;

  /// No description provided for @arenaStripDaily.
  ///
  /// In tr, this message translates to:
  /// **'Gün gün önde olan'**
  String get arenaStripDaily;

  /// No description provided for @arenaStripMonthly.
  ///
  /// In tr, this message translates to:
  /// **'Ay ay önde olan'**
  String get arenaStripMonthly;

  /// No description provided for @arenaSwaps.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =0{Yer hiç değişmedi} other{{n} kez yer değişti}}'**
  String arenaSwaps(int n);

  /// Yeniden onay kapısı (bayrak yeniden_onay_kapisi) başlığı: kullanıcı belgelerin eski bir sürümünü onaylamış, güncel sürüm onay bekliyor.
  ///
  /// In tr, this message translates to:
  /// **'Güncellenen belgeler'**
  String get yasalKapiBaslikGuncel;

  /// Yeniden onay kapısı başlığı: hiç onay kaydı olmayan kullanıcı (Apple/Google ile ilk giriş ya da onay kaydından önceki hesap).
  ///
  /// In tr, this message translates to:
  /// **'Yasal belgeler'**
  String get yasalKapiBaslikIlk;

  /// No description provided for @yasalKapiAciklamaGuncel.
  ///
  /// In tr, this message translates to:
  /// **'Yasal belgelerimizi güncelledik. Devam etmek için aşağıdaki adımları tamamla.'**
  String get yasalKapiAciklamaGuncel;

  /// No description provided for @yasalKapiAciklamaIlk.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamayı kullanmaya başlamadan önce aşağıdaki adımları tamamla.'**
  String get yasalKapiAciklamaIlk;

  /// No description provided for @yasalKapiNelerDegisti.
  ///
  /// In tr, this message translates to:
  /// **'Neler değişti'**
  String get yasalKapiNelerDegisti;

  /// Kapının 'Neler değişti' kartı. Belge sürümü (legal/tr/*.md 'Sürüm' satırı) her arttığında yeni sürümün değişikliklerine göre yeniden yazılır; uydurma iddia yazılmaz.
  ///
  /// In tr, this message translates to:
  /// **'Sürüm 1.9: Hesabını silince RevenueCat\'teki abone kaydının da silinmesi istenir. Hesap silmek mağaza aboneliğini iptal etmez; yenilemeyi App Store ya da Google Play\'den kapatırsın. Sürüm 1.8: Premium abonelik koşulları eklendi (fiyat, otomatik yenileme, iptal, iade). Premium satın alırsan aboneliğin RevenueCat (ABD) üzerinden doğrulanır; kart bilgin bize ulaşmaz. Bu yüzden Açık Rıza Metni\'ne RevenueCat eklendi. Fiyat kaynakları artık tek tek sayılmıyor, çünkü onlara kişisel veri gitmez. Bundan sonra kişisel veri işleyişini değiştirmeyen düzeltmeler için yeniden onay istenmeyecek. Sürüm 1.7: Eurobond fiyatları için iki yeni kaynak eklendi: Börse Frankfurt ve Ziraat Bankası. Bu kaynaklara yalnızca sunucumuz bağlanır ve yalnızca tahvilin ISIN kodunu sorar; kişisel bilgilerin gönderilmez. Sürüm 1.6: Ekstre içe aktarmada uygulama sütunlardan emin olamazsa \"Yapay zekâyla eşle\" seçeneği çıkar. Basarsan tablonun yalnızca anonim iskeleti (ad, numara, tutar ve tarihler gizli) yapay zekâya (Anthropic) gider; dosya telefonundan çıkmaz ve iskelet saklanmaz. Sürüm 1.5: Varlık notları eklendi. Portföyündeki varlıklar için haftalık notlar ve aylık rapor yapay zekâyla (Anthropic) yazılır; yapay zekâya kişisel verilerin gönderilmez, yalnızca varlığın piyasa ölçümleri gider. Notlar otomatik denetlenir ama hata içerebilir ve yatırım tavsiyesi değildir. Notlara verdiğin geri bildirim (oy, \"yanlış sayı\" işareti, açıklama) ve Premium hakkın hesabınla saklanır, hesabını silince silinir.'**
  String get yasalKapiDegisiklikNotu;

  /// No description provided for @yasalBelgeKosullar.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları'**
  String get yasalBelgeKosullar;

  /// No description provided for @yasalBelgeGizlilik.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik Politikası'**
  String get yasalBelgeGizlilik;

  /// No description provided for @yasalBelgeKvkk.
  ///
  /// In tr, this message translates to:
  /// **'KVKK Aydınlatma Metni'**
  String get yasalBelgeKvkk;

  /// No description provided for @yasalBelgeKvkkKisa.
  ///
  /// In tr, this message translates to:
  /// **'KVKK Metni'**
  String get yasalBelgeKvkkKisa;

  /// No description provided for @yasalBelgelerTurkce.
  ///
  /// In tr, this message translates to:
  /// **'Belgeler Türkçedir.'**
  String get yasalBelgelerTurkce;

  /// No description provided for @yasalKapiOnayla.
  ///
  /// In tr, this message translates to:
  /// **'Okudum, kabul ediyorum'**
  String get yasalKapiOnayla;

  /// No description provided for @yasalKapiOnaylaKisa.
  ///
  /// In tr, this message translates to:
  /// **'Kabul ediyorum'**
  String get yasalKapiOnaylaKisa;

  /// No description provided for @yasalKapiKayitHatasi.
  ///
  /// In tr, this message translates to:
  /// **'Onayın kaydedilemedi. Bağlantını kontrol edip tekrar dene.'**
  String get yasalKapiKayitHatasi;

  /// No description provided for @yasalKapiCikis.
  ///
  /// In tr, this message translates to:
  /// **'Çıkış yap'**
  String get yasalKapiCikis;

  /// legal/tr/ACIK_RIZA_METNI.md (yurt dışı aktarım açık rızası) — kayıttaki ve kapıdaki 'açık rıza' bağlantısı ile Ayarlar › Yasal bunu açar.
  ///
  /// In tr, this message translates to:
  /// **'Açık Rıza Metni'**
  String get yasalBelgeAcikRiza;

  /// No description provided for @yasalBelgeAcikRizaAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Yurt dışına veri aktarımı'**
  String get yasalBelgeAcikRizaAciklama;

  /// Zorunlu okuma (bayrak zorunlu_okuma): sona ulaşılana kadar ekranın altındaki ipucu. Onay düğmesi metnin sonunda.
  ///
  /// In tr, this message translates to:
  /// **'Onaylamak için metni sona kadar oku'**
  String get zorunluOkumaIpucu;

  /// No description provided for @zorunluOkumaIpucuKisa.
  ///
  /// In tr, this message translates to:
  /// **'Sona kadar oku'**
  String get zorunluOkumaIpucuKisa;

  /// No description provided for @zorunluOkumaIlerleme.
  ///
  /// In tr, this message translates to:
  /// **'Okuma ilerlemesi'**
  String get zorunluOkumaIlerleme;

  /// No description provided for @zorunluOkumaOnayla.
  ///
  /// In tr, this message translates to:
  /// **'Okudum ve onaylıyorum'**
  String get zorunluOkumaOnayla;

  /// No description provided for @zorunluOkumaOnaylaKisa.
  ///
  /// In tr, this message translates to:
  /// **'Onaylıyorum'**
  String get zorunluOkumaOnaylaKisa;

  /// No description provided for @zorunluOkumaRizaVer.
  ///
  /// In tr, this message translates to:
  /// **'Okudum ve açık rıza veriyorum'**
  String get zorunluOkumaRizaVer;

  /// No description provided for @zorunluOkumaRizaVerKisa.
  ///
  /// In tr, this message translates to:
  /// **'Açık rıza veriyorum'**
  String get zorunluOkumaRizaVerKisa;

  /// No description provided for @zorunluOkumaEksik.
  ///
  /// In tr, this message translates to:
  /// **'Devam etmek için şunları sonuna kadar okuyup onaylamalısın: {belgeler}'**
  String zorunluOkumaEksik(String belgeler);

  /// No description provided for @yasalBelgeYatirimUyarisi.
  ///
  /// In tr, this message translates to:
  /// **'Yatırım Uyarısı'**
  String get yasalBelgeYatirimUyarisi;

  /// No description provided for @flowTitleUpper.
  ///
  /// In tr, this message translates to:
  /// **'PARA AKIŞI'**
  String get flowTitleUpper;

  /// No description provided for @flowLastWeekIn.
  ///
  /// In tr, this message translates to:
  /// **'Son hafta net giriş'**
  String get flowLastWeekIn;

  /// No description provided for @flowLastWeekOut.
  ///
  /// In tr, this message translates to:
  /// **'Son hafta net çıkış'**
  String get flowLastWeekOut;

  /// No description provided for @flowLastWeekFlat.
  ///
  /// In tr, this message translates to:
  /// **'Son hafta net akış'**
  String get flowLastWeekFlat;

  /// Para akışı kartında son haftanın tarih aralığı: '29 Eyl - 2 Eki'.
  ///
  /// In tr, this message translates to:
  /// **'{from} - {to}'**
  String flowRange(String from, String to);

  /// No description provided for @flowChartCaption.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık net akış · son 8 hafta'**
  String get flowChartCaption;

  /// No description provided for @flowChartSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Son 8 haftanın haftalık net para akışı. Son hafta {amount}.'**
  String flowChartSemantics(String amount);

  /// No description provided for @flowWeekOf.
  ///
  /// In tr, this message translates to:
  /// **'{date} haftası'**
  String flowWeekOf(String date);

  /// No description provided for @flowFundSize.
  ///
  /// In tr, this message translates to:
  /// **'Fon büyüklüğü'**
  String get flowFundSize;

  /// No description provided for @flowInvestors.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcı sayısı'**
  String get flowInvestors;

  /// Yatırımcı sayısı ve bir önceki işlem gününe göre farkı: '40.518 (+12)'.
  ///
  /// In tr, this message translates to:
  /// **'{count} ({delta})'**
  String flowInvestorsDelta(String count, String delta);

  /// No description provided for @flowEventsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Büyük hareketler · son 30 gün'**
  String get flowEventsTitle;

  /// No description provided for @flowEventIn.
  ///
  /// In tr, this message translates to:
  /// **'Büyük giriş · {date}'**
  String flowEventIn(String date);

  /// No description provided for @flowEventOut.
  ///
  /// In tr, this message translates to:
  /// **'Büyük çıkış · {date}'**
  String flowEventOut(String date);

  /// Olayın kanıt satırı. amount işaretli tutar, pct yüzde, times bir ondalıklı kat.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · fon büyüklüğüne oranı {pct} · olağan günlük hareketin {times} katı'**
  String flowEventEvidence(String amount, String pct, String times);

  /// No description provided for @flowEventInvestors.
  ///
  /// In tr, this message translates to:
  /// **'Aynı gün yatırımcı sayısı {delta}'**
  String flowEventInvestors(String delta);

  /// No description provided for @flowNoEvents.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 günde olağandışı büyüklükte bir giriş ya da çıkış yok.'**
  String get flowNoEvents;

  /// No description provided for @flowExplain.
  ///
  /// In tr, this message translates to:
  /// **'Net akış, fona giren ve fondan çıkan paranın farkıdır; fiyat değişimi dahil değildir.'**
  String get flowExplain;

  /// No description provided for @flowFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak: TEFAS · veri tarihi {date}. Kimin alıp sattığı bu veriden bilinemez. Geçmişteki para akışı gelecekteki getiriyi göstermez; yatırım tavsiyesi değildir.'**
  String flowFootnote(String date);

  /// No description provided for @flowStreakIn.
  ///
  /// In tr, this message translates to:
  /// **'{count} haftadır üst üste net giriş'**
  String flowStreakIn(String count);

  /// No description provided for @flowStreakOut.
  ///
  /// In tr, this message translates to:
  /// **'{count} haftadır üst üste net çıkış'**
  String flowStreakOut(String count);

  /// No description provided for @flowPeriod1m.
  ///
  /// In tr, this message translates to:
  /// **'Son 1 ay'**
  String get flowPeriod1m;

  /// No description provided for @flowPeriod3m.
  ///
  /// In tr, this message translates to:
  /// **'Son 3 ay'**
  String get flowPeriod3m;

  /// Dönem akışı: işaretli tutar ve dönem başındaki fon büyüklüğüne oranı.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · {pct}'**
  String flowPeriodValue(String amount, String pct);

  /// No description provided for @flowPeriodNote.
  ///
  /// In tr, this message translates to:
  /// **'Yüzdeler, akışın dönem başındaki fon büyüklüğüne oranıdır.'**
  String get flowPeriodNote;

  /// No description provided for @flowDecompose.
  ///
  /// In tr, this message translates to:
  /// **'Son 1 ayda fon büyüklüğü {total} değişti: fiyat etkisi {price}, para akışı {flow}.'**
  String flowDecompose(String total, String price, String flow);

  /// No description provided for @flowEventEvidenceMulti.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · fon büyüklüğüne oranı {pct} · {days} işlem günü üst üste'**
  String flowEventEvidenceMulti(String amount, String pct, String days);

  /// No description provided for @weekTitle.
  ///
  /// In tr, this message translates to:
  /// **'Haftanın özeti'**
  String get weekTitle;

  /// No description provided for @weekIntro.
  ///
  /// In tr, this message translates to:
  /// **'Tuttuğun varlıklarda son haftanın öne çıkanları. Bir satıra dokununca ayrıntısı açılır.'**
  String get weekIntro;

  /// No description provided for @weekFundsUpper.
  ///
  /// In tr, this message translates to:
  /// **'FONLARINDA PARA AKIŞI'**
  String get weekFundsUpper;

  /// Haftanın özeti satırı: 'Net çıkış · 28 Eyl - 2 Eki'.
  ///
  /// In tr, this message translates to:
  /// **'{label} · {range}'**
  String weekRowRange(String label, String range);

  /// No description provided for @weekRowIn.
  ///
  /// In tr, this message translates to:
  /// **'Net giriş'**
  String get weekRowIn;

  /// No description provided for @weekRowOut.
  ///
  /// In tr, this message translates to:
  /// **'Net çıkış'**
  String get weekRowOut;

  /// No description provided for @weekRowFlat.
  ///
  /// In tr, this message translates to:
  /// **'Net akış'**
  String get weekRowFlat;

  /// No description provided for @weekRowBigIn.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta büyük giriş var'**
  String get weekRowBigIn;

  /// No description provided for @weekRowBigOut.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta büyük çıkış var'**
  String get weekRowBigOut;

  /// No description provided for @weekEmptyNoData.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta gösterecek bir şey yok. Portföyündeki fonların para akışı ve hisse ya da kriptolarındaki olağandışı hacim günleri, verisi geldiğinde burada görünür.'**
  String get weekEmptyNoData;

  /// No description provided for @weekFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak: TEFAS, Yahoo Finance, Binance. Net akış fona giren ve çıkan paranın farkıdır; kimin alıp sattığı bu veriden bilinemez. Portföyünün haftalık getirisi Performans sekmesindeki Özet\'te. Yatırım tavsiyesi değildir.'**
  String get weekFootnote;

  /// No description provided for @weekLink.
  ///
  /// In tr, this message translates to:
  /// **'Tüm fonlarımın haftası'**
  String get weekLink;

  /// No description provided for @volTitleUpper.
  ///
  /// In tr, this message translates to:
  /// **'HACİM RADARI'**
  String get volTitleUpper;

  /// No description provided for @volLastDay.
  ///
  /// In tr, this message translates to:
  /// **'Para hacmi · {date}'**
  String volLastDay(String date);

  /// No description provided for @volVsAverage.
  ///
  /// In tr, this message translates to:
  /// **'Önceki 20 günün ortalamasının {times} katı'**
  String volVsAverage(String times);

  /// No description provided for @volPriceSameDay.
  ///
  /// In tr, this message translates to:
  /// **'Aynı gün fiyat {pct}'**
  String volPriceSameDay(String pct);

  /// No description provided for @volChartCaption.
  ///
  /// In tr, this message translates to:
  /// **'Günlük para hacmi · son 20 işlem günü'**
  String get volChartCaption;

  /// No description provided for @volChartSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Son 20 işlem gününün günlük para hacmi. Son gün {amount}.'**
  String volChartSemantics(String amount);

  /// No description provided for @volExplain.
  ///
  /// In tr, this message translates to:
  /// **'Para hacmi, o gün el değiştiren hisselerin toplam tutarıdır. Her işlemin bir alıcısı ve bir satıcısı vardır; yüksek hacim tek başına para girişi ya da çıkışı demek değildir.'**
  String get volExplain;

  /// No description provided for @volEventsTitle.
  ///
  /// In tr, this message translates to:
  /// **'Olağandışı hacim günleri · son 30 gün'**
  String get volEventsTitle;

  /// No description provided for @volEventTitle.
  ///
  /// In tr, this message translates to:
  /// **'Olağandışı hacim · {date}'**
  String volEventTitle(String date);

  /// No description provided for @volEventEvidence.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · ortalamanın {times} katı · fiyat {pct}'**
  String volEventEvidence(String amount, String times, String pct);

  /// No description provided for @volNoEvents.
  ///
  /// In tr, this message translates to:
  /// **'Son 30 günde olağandışı hacim günü yok.'**
  String get volNoEvents;

  /// No description provided for @volFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak: Yahoo Finance gün sonu verisi · veri tarihi {date}. Kimin alıp sattığı bu veriden bilinemez. Yatırım tavsiyesi değildir.'**
  String volFootnote(String date);

  /// No description provided for @cryTitleUpper.
  ///
  /// In tr, this message translates to:
  /// **'ALICI BASKISI'**
  String get cryTitleUpper;

  /// No description provided for @cryShareLabel.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı payı · {date}'**
  String cryShareLabel(String date);

  /// No description provided for @cryShareAvg.
  ///
  /// In tr, this message translates to:
  /// **'Son 7 günün ortalaması {pct}'**
  String cryShareAvg(String pct);

  /// No description provided for @cryExplain.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı payı, o günkü işlem hacminin ne kadarının piyasa emriyle alım yapanlardan geldiğini gösterir. %50\'nin üstü alıcıların, altı satıcıların daha istekli olduğu anlamına gelir; para girişi ölçüsü değildir.'**
  String get cryExplain;

  /// No description provided for @cryVolumeLabel.
  ///
  /// In tr, this message translates to:
  /// **'İşlem hacmi {amount}'**
  String cryVolumeLabel(String amount);

  /// No description provided for @cryChartCaption.
  ///
  /// In tr, this message translates to:
  /// **'Günlük işlem hacmi (USDT) · son 20 gün'**
  String get cryChartCaption;

  /// No description provided for @cryChartSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Son 20 günün günlük işlem hacmi. Son gün {amount}.'**
  String cryChartSemantics(String amount);

  /// No description provided for @cryEventEvidence.
  ///
  /// In tr, this message translates to:
  /// **'{amount} · ortalamanın {times} katı · fiyat {pct} · alıcı payı {share}'**
  String cryEventEvidence(
      String amount, String times, String pct, String share);

  /// No description provided for @cryFootnote.
  ///
  /// In tr, this message translates to:
  /// **'Kaynak: Binance, USDT paritesi · veri tarihi {date}. Yalnız Binance\'teki işlemleri kapsar; kimin alıp sattığı bu veriden bilinemez. Yatırım tavsiyesi değildir.'**
  String cryFootnote(String date);

  /// No description provided for @weekVolumeUpper.
  ///
  /// In tr, this message translates to:
  /// **'OLAĞANDIŞI HACİM'**
  String get weekVolumeUpper;

  /// No description provided for @weekVolumeRow.
  ///
  /// In tr, this message translates to:
  /// **'Olağandışı hacim · {date}'**
  String weekVolumeRow(String date);

  /// No description provided for @tekOnayGizlilikBaglanti.
  ///
  /// In tr, this message translates to:
  /// **'Gizlilik Politikası'**
  String get tekOnayGizlilikBaglanti;

  /// Bilgilendirme belgesinin (Koşullar, Gizlilik, KVKK) satırında hafif iz: belge en az bir kez açıldı. Onay DEĞİL — onay işareti yalnız sonuna kadar okunan metinlerde.
  ///
  /// In tr, this message translates to:
  /// **'Açıldı'**
  String get yasalBelgeAcildi;

  /// Kayıt ekranındaki adım kartının başlığı (kullanıcı kararı 2026-10-05, seçenek C).
  ///
  /// In tr, this message translates to:
  /// **'Kayıt için {sayi} adım'**
  String yasalAdimKayitBaslik(int sayi);

  /// Yeniden onay kapısındaki adım kartının başlığı.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} adım'**
  String yasalAdimKapiBaslik(int sayi);

  /// No description provided for @yasalAdimUyariAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Uygulamanın yatırım tavsiyesi olmadığını anlatan kısa metin. Sonuna kadar okuyup en altta onayla.'**
  String get yasalAdimUyariAciklama;

  /// No description provided for @yasalAdimRizaAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Verilerinin yurt dışına aktarılmasına açık rıza. Sonuna kadar okuyup rızanı en altta ver.'**
  String get yasalAdimRizaAciklama;

  /// No description provided for @yasalAdimKutuBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Kullanım Koşulları\'nı kabul et'**
  String get yasalAdimKutuBaslik;

  /// Kapıda kutu adımının başlığı: güncellenen belge adları.
  ///
  /// In tr, this message translates to:
  /// **'{belgeler} güncellendi'**
  String yasalAdimGuncellendi(String belgeler);

  /// No description provided for @yasalAdimListeVe.
  ///
  /// In tr, this message translates to:
  /// **'{onceki} ve {son}'**
  String yasalAdimListeVe(String onceki, String son);

  /// No description provided for @yasalAdimKosulGuncelAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Değişiklikleri belgeden okuyabilirsin; okuman zorunlu değil. Devam etmek için kutuyu işaretle.'**
  String get yasalAdimKosulGuncelAciklama;

  /// No description provided for @yasalAdimBilgiGuncelAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Bilgilendirme amaçlıdır; okuman zorunlu değil. Kutuyu işaretleyerek bilgilendirildiğini belirt.'**
  String get yasalAdimBilgiGuncelAciklama;

  /// No description provided for @yasalAdimOkuOnayla.
  ///
  /// In tr, this message translates to:
  /// **'Oku ve onayla'**
  String get yasalAdimOkuOnayla;

  /// No description provided for @yasalAdimOkunduOnaylandi.
  ///
  /// In tr, this message translates to:
  /// **'Okundu ve onaylandı'**
  String get yasalAdimOkunduOnaylandi;

  /// Ekran okuyucu: adımlar sırayla okunur ("Adım 2/3, Açık Rıza Metni, bekliyor").
  ///
  /// In tr, this message translates to:
  /// **'Adım {sira}/{toplam}, {ad}, {durum}'**
  String yasalAdimSemantik(int sira, int toplam, String ad, String durum);

  /// No description provided for @yasalAdimDurumTamam.
  ///
  /// In tr, this message translates to:
  /// **'tamamlandı'**
  String get yasalAdimDurumTamam;

  /// No description provided for @yasalAdimDurumBekliyor.
  ///
  /// In tr, this message translates to:
  /// **'bekliyor'**
  String get yasalAdimDurumBekliyor;

  /// No description provided for @yasalAdimDurumSonra.
  ///
  /// In tr, this message translates to:
  /// **'sırası gelecek'**
  String get yasalAdimDurumSonra;

  /// No description provided for @yasalAdimDigerBelgeler.
  ///
  /// In tr, this message translates to:
  /// **'Diğer belgeler (bilgi amaçlı) · {sayi}'**
  String yasalAdimDigerBelgeler(int sayi);

  /// No description provided for @yasalAdimSayac.
  ///
  /// In tr, this message translates to:
  /// **'{tamam}/{toplam} adım tamamlandı'**
  String yasalAdimSayac(int tamam, int toplam);

  /// No description provided for @yasalKapiBaslikGuncelTek.
  ///
  /// In tr, this message translates to:
  /// **'Güncellenen belge'**
  String get yasalKapiBaslikGuncelTek;

  /// No description provided for @streakTitle.
  ///
  /// In tr, this message translates to:
  /// **'Birikim serin'**
  String get streakTitle;

  /// No description provided for @streakMonths.
  ///
  /// In tr, this message translates to:
  /// **'{n} ay art arda'**
  String streakMonths(String n);

  /// No description provided for @streakRestarted.
  ///
  /// In tr, this message translates to:
  /// **'Seri yeniden başladı'**
  String get streakRestarted;

  /// No description provided for @streakLongest.
  ///
  /// In tr, this message translates to:
  /// **'En uzun seri'**
  String get streakLongest;

  /// No description provided for @streakMonthsValue.
  ///
  /// In tr, this message translates to:
  /// **'{n} ay'**
  String streakMonthsValue(String n);

  /// No description provided for @streakPause.
  ///
  /// In tr, this message translates to:
  /// **'Mola hakkı'**
  String get streakPause;

  /// No description provided for @streakPauseAvailable.
  ///
  /// In tr, this message translates to:
  /// **'1 ay, kullanılabilir'**
  String get streakPauseAvailable;

  /// No description provided for @streakPauseUsed.
  ///
  /// In tr, this message translates to:
  /// **'Kullanıldı · {month} ayında açılır'**
  String streakPauseUsed(String month);

  /// No description provided for @streakOpenMonth.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay henüz ekleme yok; ay sonuna kadar açık.'**
  String get streakOpenMonth;

  /// No description provided for @streakExplain.
  ///
  /// In tr, this message translates to:
  /// **'Portföyüne para eklediğin ayları sayar. Son 12 ayda bir boş ay seriyi bozmaz.'**
  String get streakExplain;

  /// No description provided for @streakBesIncluded.
  ///
  /// In tr, this message translates to:
  /// **'BES otomatik katkıları dahil.'**
  String get streakBesIncluded;

  /// No description provided for @streakLegendSaving.
  ///
  /// In tr, this message translates to:
  /// **'birikim'**
  String get streakLegendSaving;

  /// No description provided for @streakLegendPause.
  ///
  /// In tr, this message translates to:
  /// **'mola'**
  String get streakLegendPause;

  /// No description provided for @streakLegendGap.
  ///
  /// In tr, this message translates to:
  /// **'ara'**
  String get streakLegendGap;

  /// No description provided for @streakLegendOpen.
  ///
  /// In tr, this message translates to:
  /// **'bu ay'**
  String get streakLegendOpen;

  /// No description provided for @streakStripSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Son {total} ay: {saved} birikim ayı'**
  String streakStripSemantics(String total, String saved);

  /// No description provided for @savingReminderTitle.
  ///
  /// In tr, this message translates to:
  /// **'Maaş günü hatırlatması'**
  String get savingReminderTitle;

  /// No description provided for @savingReminderOff.
  ///
  /// In tr, this message translates to:
  /// **'Kapalı'**
  String get savingReminderOff;

  /// No description provided for @savingReminderOn.
  ///
  /// In tr, this message translates to:
  /// **'Ayın {day}. günü, 10:30 · o ay ekleme yoksa'**
  String savingReminderOn(String day);

  /// No description provided for @savingReminderSheetBody.
  ///
  /// In tr, this message translates to:
  /// **'Seçtiğin gün, o ay portföyüne hiç ekleme yapmadıysan tek bir hatırlatma gelir. Ekleme yaptıysan gelmez. Seçtiğin gün o ayda yoksa (ör. Şubat\'ta 30) ayın son günü gelir.'**
  String get savingReminderSheetBody;

  /// No description provided for @savingReminderDay.
  ///
  /// In tr, this message translates to:
  /// **'Ayın {day}. günü'**
  String savingReminderDay(String day);

  /// No description provided for @rdrKademeSakin.
  ///
  /// In tr, this message translates to:
  /// **'sakin'**
  String get rdrKademeSakin;

  /// No description provided for @rdrKademeHareketli.
  ///
  /// In tr, this message translates to:
  /// **'hareketli'**
  String get rdrKademeHareketli;

  /// No description provided for @rdrKademeCok.
  ///
  /// In tr, this message translates to:
  /// **'çok hareketli'**
  String get rdrKademeCok;

  /// No description provided for @rdrHaftaSakin.
  ///
  /// In tr, this message translates to:
  /// **'Sakin hafta'**
  String get rdrHaftaSakin;

  /// No description provided for @rdrHaftaHareketli.
  ///
  /// In tr, this message translates to:
  /// **'Hareketli hafta'**
  String get rdrHaftaHareketli;

  /// No description provided for @rdrHaftaCok.
  ///
  /// In tr, this message translates to:
  /// **'Çok hareketli hafta'**
  String get rdrHaftaCok;

  /// No description provided for @rdrGunSakin.
  ///
  /// In tr, this message translates to:
  /// **'Sakin gün'**
  String get rdrGunSakin;

  /// No description provided for @rdrGunHareketli.
  ///
  /// In tr, this message translates to:
  /// **'Hareketli gün'**
  String get rdrGunHareketli;

  /// No description provided for @rdrGunCok.
  ///
  /// In tr, this message translates to:
  /// **'Çok hareketli gün'**
  String get rdrGunCok;

  /// No description provided for @rdrOlcekSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Kendi olağanına göre: {kademe}'**
  String rdrOlcekSemantics(String kademe);

  /// No description provided for @rdrAyrinti.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntı'**
  String get rdrAyrinti;

  /// No description provided for @rdrKaynakSatiri.
  ///
  /// In tr, this message translates to:
  /// **'{kaynak} · {tarih} · tavsiye değildir'**
  String rdrKaynakSatiri(String kaynak, String tarih);

  /// No description provided for @rdrYasal.
  ///
  /// In tr, this message translates to:
  /// **'Veriler {kaynak} kaynaklıdır ve kimin alıp sattığını göstermez. Geçmişteki hareket gelecekteki getiriyi göstermez; yatırım tavsiyesi değildir.'**
  String rdrYasal(String kaynak);

  /// No description provided for @rdrNasilOkunur.
  ///
  /// In tr, this message translates to:
  /// **'Nasıl okunur'**
  String get rdrNasilOkunur;

  /// No description provided for @rdrKoc1.
  ///
  /// In tr, this message translates to:
  /// **'Üstteki cümle bu varlığın son durumunu tek satırda anlatır. Altındaki sayı o cümlenin kanıtıdır.'**
  String get rdrKoc1;

  /// No description provided for @rdrKoc2.
  ///
  /// In tr, this message translates to:
  /// **'Ölçek, sayının bu varlığın kendi olağanına göre ne kadar büyük olduğunu gösterir: sakin, hareketli, çok hareketli.'**
  String get rdrKoc2;

  /// No description provided for @rdrKoc3.
  ///
  /// In tr, this message translates to:
  /// **'Altı noktalı kelimelere dokunursan ne anlama geldiğini görürsün.'**
  String get rdrKoc3;

  /// No description provided for @rdrKocAdim.
  ///
  /// In tr, this message translates to:
  /// **'{adim} / 3'**
  String rdrKocAdim(String adim);

  /// No description provided for @rdrIleri.
  ///
  /// In tr, this message translates to:
  /// **'İleri'**
  String get rdrIleri;

  /// No description provided for @rdrAnladim.
  ///
  /// In tr, this message translates to:
  /// **'Anladım'**
  String get rdrAnladim;

  /// No description provided for @rdrTerimNetAkis.
  ///
  /// In tr, this message translates to:
  /// **'Net akış'**
  String get rdrTerimNetAkis;

  /// No description provided for @rdrTerimNetAkisTanim.
  ///
  /// In tr, this message translates to:
  /// **'Fona giren paradan çıkan para düşülünce kalan tutar. Fon fiyatının artması ya da düşmesi buna girmez; yalnız yatırımcıların koyduğu ve çektiği para sayılır.'**
  String get rdrTerimNetAkisTanim;

  /// No description provided for @rdrTerimBuyukluk.
  ///
  /// In tr, this message translates to:
  /// **'Fon büyüklüğü'**
  String get rdrTerimBuyukluk;

  /// No description provided for @rdrTerimBuyuklukTanim.
  ///
  /// In tr, this message translates to:
  /// **'Fondaki toplam paranın bugünkü değeri. Hem yeni para girince hem de fonun içindekiler değer kazanınca büyür.'**
  String get rdrTerimBuyuklukTanim;

  /// No description provided for @rdrTerimAyristirma.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat ve yeni para'**
  String get rdrTerimAyristirma;

  /// No description provided for @rdrTerimAyristirmaTanim.
  ///
  /// In tr, this message translates to:
  /// **'Fon büyüklüğündeki değişim iki kaynaktan gelir: fondaki varlıkların değerinin değişmesi (fiyat) ve yatırımcıların koyup çektiği para (yeni para). İkisinin toplamı büyüklük değişimidir.'**
  String get rdrTerimAyristirmaTanim;

  /// No description provided for @rdrTerimYatirimci.
  ///
  /// In tr, this message translates to:
  /// **'Yatırımcı sayısı'**
  String get rdrTerimYatirimci;

  /// No description provided for @rdrTerimYatirimciTanim.
  ///
  /// In tr, this message translates to:
  /// **'Fonda payı olan kişi sayısı. Aynı tutar az kişiden büyük paralarla da, çok kişiden küçük paralarla da gelebilir; bu sayı farkı gösterir.'**
  String get rdrTerimYatirimciTanim;

  /// No description provided for @rdrTerimSira.
  ///
  /// In tr, this message translates to:
  /// **'Kategoride akış sırası'**
  String get rdrTerimSira;

  /// No description provided for @rdrTerimSiraTanim.
  ///
  /// In tr, this message translates to:
  /// **'Aynı TEFAS kategorisindeki fonların, aynı hafta en çok net para girişi olandan en çok net çıkışı olana sırası. Yalnız o haftanın her gününde verisi olan fonlar sıralanır.'**
  String get rdrTerimSiraTanim;

  /// No description provided for @rdrTerimBuyukHareket.
  ///
  /// In tr, this message translates to:
  /// **'Büyük hareket'**
  String get rdrTerimBuyukHareket;

  /// No description provided for @rdrTerimBuyukHareketTanim.
  ///
  /// In tr, this message translates to:
  /// **'Bir günde giren ya da çıkan paranın hem fon büyüklüğünün en az %3\'ü hem de fonun olağan günlük hareketinin en az 4 katı olması. İkisi birden olmadıkça işaretlenmez; ₺250 mn altındaki fonlarda ve para piyasası fonlarında hiç işaretlenmez.'**
  String get rdrTerimBuyukHareketTanim;

  /// No description provided for @rdrTerimOlcek.
  ///
  /// In tr, this message translates to:
  /// **'Ölçek'**
  String get rdrTerimOlcek;

  /// No description provided for @rdrTerimOlcekTanim.
  ///
  /// In tr, this message translates to:
  /// **'Sayının bu varlığın kendi geçmişine göre büyüklüğü. Fonda son hafta önceki haftaların ortalamasıyla, hissede son günün hacmi önceki 20 günün ortalamasıyla kıyaslanır. Kriptoda alıcı payının %50\'den uzaklığına bakılır: 2 puan hareketli, 5 puan çok hareketli. O gün büyük hareket ya da olağandışı hacim işaretlendiyse ölçek en üsttedir.'**
  String get rdrTerimOlcekTanim;

  /// No description provided for @rdrTerimHacim.
  ///
  /// In tr, this message translates to:
  /// **'Para hacmi'**
  String get rdrTerimHacim;

  /// No description provided for @rdrTerimHacimTanim.
  ///
  /// In tr, this message translates to:
  /// **'O gün el değiştiren hisselerin toplam tutarı. Her işlemin bir alıcısı ve bir satıcısı vardır; yüksek hacim tek başına para girişi demek değildir.'**
  String get rdrTerimHacimTanim;

  /// No description provided for @rdrTerimKat.
  ///
  /// In tr, this message translates to:
  /// **'Ortalamanın katı'**
  String get rdrTerimKat;

  /// No description provided for @rdrTerimKatTanim.
  ///
  /// In tr, this message translates to:
  /// **'Son günün hacminin önceki 20 işlem gününün ortalamasına oranı. 1 kat olağan bir gün demektir.'**
  String get rdrTerimKatTanim;

  /// No description provided for @rdrTerimOlagandisi.
  ///
  /// In tr, this message translates to:
  /// **'Olağandışı hacim'**
  String get rdrTerimOlagandisi;

  /// No description provided for @rdrTerimOlagandisiTanim.
  ///
  /// In tr, this message translates to:
  /// **'Hacmin önceki 20 günün ortalamasının en az 2 katı olduğu ve bu sıçramanın o varlığın olağan dalgalanmasının çok dışında kaldığı gün.'**
  String get rdrTerimOlagandisiTanim;

  /// No description provided for @rdrTerimAliciPayi.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı payı'**
  String get rdrTerimAliciPayi;

  /// No description provided for @rdrTerimAliciPayiTanim.
  ///
  /// In tr, this message translates to:
  /// **'İşlem hacminin ne kadarının hemen almak isteyenlerden (piyasa emriyle alanlardan) geldiği. %50\'nin üstü alıcıların, altı satıcıların daha istekli olduğunu gösterir. Para girişi ölçüsü değildir. Birden çok günde hacim ağırlıklıdır: işlemi çok olan gün daha çok sayılır.'**
  String get rdrTerimAliciPayiTanim;

  /// No description provided for @rdrTerimNetAlim.
  ///
  /// In tr, this message translates to:
  /// **'Net alım'**
  String get rdrTerimNetAlim;

  /// No description provided for @rdrTerimNetAlimTanim.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa emriyle alanların hacminden satanların hacmi düşülünce kalan tutar (USDT). Yalnız Binance\'teki işlemleri kapsar.'**
  String get rdrTerimNetAlimTanim;

  /// No description provided for @rdrTerimOrnek.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlıkta: {deger}'**
  String rdrTerimOrnek(String deger);

  /// No description provided for @rdrFonGirisSakin.
  ///
  /// In tr, this message translates to:
  /// **'Bu fona son hafta olağan ölçüde para girdi.'**
  String get rdrFonGirisSakin;

  /// No description provided for @rdrFonGirisHareketli.
  ///
  /// In tr, this message translates to:
  /// **'Bu fona son hafta olağandan fazla para girdi.'**
  String get rdrFonGirisHareketli;

  /// No description provided for @rdrFonGirisCok.
  ///
  /// In tr, this message translates to:
  /// **'Bu fona son hafta olağanın çok üstünde para girdi.'**
  String get rdrFonGirisCok;

  /// No description provided for @rdrFonCikisSakin.
  ///
  /// In tr, this message translates to:
  /// **'Bu fondan son hafta olağan ölçüde para çıktı.'**
  String get rdrFonCikisSakin;

  /// No description provided for @rdrFonCikisHareketli.
  ///
  /// In tr, this message translates to:
  /// **'Bu fondan son hafta olağandan fazla para çıktı.'**
  String get rdrFonCikisHareketli;

  /// No description provided for @rdrFonCikisCok.
  ///
  /// In tr, this message translates to:
  /// **'Bu fondan son hafta olağanın çok üstünde para çıktı.'**
  String get rdrFonCikisCok;

  /// No description provided for @rdrFonGiris.
  ///
  /// In tr, this message translates to:
  /// **'Bu fona son hafta para girdi.'**
  String get rdrFonGiris;

  /// No description provided for @rdrFonCikis.
  ///
  /// In tr, this message translates to:
  /// **'Bu fondan son hafta para çıktı.'**
  String get rdrFonCikis;

  /// No description provided for @rdrFonDenge.
  ///
  /// In tr, this message translates to:
  /// **'Bu fonda son hafta giren ve çıkan para dengedeydi.'**
  String get rdrFonDenge;

  /// No description provided for @rdrFonKarisik.
  ///
  /// In tr, this message translates to:
  /// **'Bu fonda son hafta büyük para hareketi oldu.'**
  String get rdrFonKarisik;

  /// No description provided for @rdrFonNetAralik.
  ///
  /// In tr, this message translates to:
  /// **'net akış · {aralik}'**
  String rdrFonNetAralik(String aralik);

  /// No description provided for @rdrSon8Hafta.
  ///
  /// In tr, this message translates to:
  /// **'son 8 hafta'**
  String get rdrSon8Hafta;

  /// No description provided for @rdrBuyukHareketSayisi.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} büyük hareket'**
  String rdrBuyukHareketSayisi(String sayi);

  /// No description provided for @rdrBuyukHareketYok.
  ///
  /// In tr, this message translates to:
  /// **'büyük hareket yok'**
  String get rdrBuyukHareketYok;

  /// No description provided for @rdrFonDetayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{kod} · Para akışı'**
  String rdrFonDetayBaslik(String kod);

  /// No description provided for @rdrHaftayaDokun.
  ///
  /// In tr, this message translates to:
  /// **'Bir haftaya dokun, o haftanın rakamı burada görünür.'**
  String get rdrHaftayaDokun;

  /// No description provided for @rdrSecilenHafta.
  ///
  /// In tr, this message translates to:
  /// **'{aralik} haftası'**
  String rdrSecilenHafta(String aralik);

  /// No description provided for @rdrVeriYok.
  ///
  /// In tr, this message translates to:
  /// **'veri yok'**
  String get rdrVeriYok;

  /// No description provided for @rdrAyristirmaCumle.
  ///
  /// In tr, this message translates to:
  /// **'Son 1 ayda fon büyüklüğü {yuzde} değişti.'**
  String rdrAyristirmaCumle(String yuzde);

  /// No description provided for @rdrFiyat.
  ///
  /// In tr, this message translates to:
  /// **'fiyat {yuzde}'**
  String rdrFiyat(String yuzde);

  /// No description provided for @rdrYeniPara.
  ///
  /// In tr, this message translates to:
  /// **'yeni para {yuzde}'**
  String rdrYeniPara(String yuzde);

  /// No description provided for @rdrOlaganinKati.
  ///
  /// In tr, this message translates to:
  /// **'olağan haftanın {kat} katı'**
  String rdrOlaganinKati(String kat);

  /// No description provided for @rdrDonemUpper.
  ///
  /// In tr, this message translates to:
  /// **'DÖNEM'**
  String get rdrDonemUpper;

  /// No description provided for @rdrBaglamUpper.
  ///
  /// In tr, this message translates to:
  /// **'BAĞLAM'**
  String get rdrBaglamUpper;

  /// No description provided for @rdrSiraUpper.
  ///
  /// In tr, this message translates to:
  /// **'KATEGORİDE AKIŞ SIRASI'**
  String get rdrSiraUpper;

  /// No description provided for @rdrSiraAlt.
  ///
  /// In tr, this message translates to:
  /// **'{kategori} · aynı haftanın net akışına göre sıra'**
  String rdrSiraAlt(String kategori);

  /// No description provided for @rdrSiraBuFon.
  ///
  /// In tr, this message translates to:
  /// **'bu fon'**
  String get rdrSiraBuFon;

  /// No description provided for @rdrSiraToplam.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} fon içinde'**
  String rdrSiraToplam(String sayi);

  /// No description provided for @rdrHareketlerUpper.
  ///
  /// In tr, this message translates to:
  /// **'BÜYÜK HAREKETLER · SON 30 GÜN'**
  String get rdrHareketlerUpper;

  /// No description provided for @rdrHisseSakin.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü bu hissede olağan miktarda işlem yapıldı.'**
  String rdrHisseSakin(String tarih);

  /// No description provided for @rdrHisseHareketli.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü bu hissede olağandan fazla işlem yapıldı.'**
  String rdrHisseHareketli(String tarih);

  /// No description provided for @rdrHisseCok.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü bu hissede olağanın çok üstünde işlem yapıldı.'**
  String rdrHisseCok(String tarih);

  /// No description provided for @rdrHisseYalin.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü bu hissede {tutar} tutarında işlem yapıldı.'**
  String rdrHisseYalin(String tarih, String tutar);

  /// No description provided for @rdrHacimAlt.
  ///
  /// In tr, this message translates to:
  /// **'para hacmi · fiyat {yuzde}'**
  String rdrHacimAlt(String yuzde);

  /// No description provided for @rdrHacimAltFiyatsiz.
  ///
  /// In tr, this message translates to:
  /// **'para hacmi'**
  String get rdrHacimAltFiyatsiz;

  /// No description provided for @rdrOrtalamaCizgisi.
  ///
  /// In tr, this message translates to:
  /// **'kesikli çizgi: önceki 20 günün ortalaması'**
  String get rdrOrtalamaCizgisi;

  /// No description provided for @rdrHacimDetayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{kod} · Hacim radarı'**
  String rdrHacimDetayBaslik(String kod);

  /// No description provided for @rdrGuneDokun.
  ///
  /// In tr, this message translates to:
  /// **'Bir güne dokun, o günün hacmi ve fiyatı burada görünür.'**
  String get rdrGuneDokun;

  /// No description provided for @rdrSecilenGun.
  ///
  /// In tr, this message translates to:
  /// **'{tarih}: {tutar} · fiyat {yuzde}'**
  String rdrSecilenGun(String tarih, String tutar, String yuzde);

  /// No description provided for @rdrSecilenGunFiyatsiz.
  ///
  /// In tr, this message translates to:
  /// **'{tarih}: {tutar}'**
  String rdrSecilenGunFiyatsiz(String tarih, String tutar);

  /// No description provided for @rdrOlagandisiUpper.
  ///
  /// In tr, this message translates to:
  /// **'OLAĞANDIŞI HACİM GÜNLERİ · SON 30 GÜN'**
  String get rdrOlagandisiUpper;

  /// No description provided for @rdrKriptoAlici.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü alanlar satanlardan daha istekliydi.'**
  String rdrKriptoAlici(String tarih);

  /// No description provided for @rdrKriptoAliciCok.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü alanlar satanlardan belirgin biçimde daha istekliydi.'**
  String rdrKriptoAliciCok(String tarih);

  /// No description provided for @rdrKriptoSatici.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü satanlar alanlardan daha istekliydi.'**
  String rdrKriptoSatici(String tarih);

  /// No description provided for @rdrKriptoSaticiCok.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü satanlar alanlardan belirgin biçimde daha istekliydi.'**
  String rdrKriptoSaticiCok(String tarih);

  /// No description provided for @rdrKriptoDenge.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} günü alanlar ile satanlar dengedeydi.'**
  String rdrKriptoDenge(String tarih);

  /// No description provided for @rdrAlici.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı {yuzde}'**
  String rdrAlici(String yuzde);

  /// No description provided for @rdrSatici.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı {yuzde}'**
  String rdrSatici(String yuzde);

  /// No description provided for @rdrYediGunOrt.
  ///
  /// In tr, this message translates to:
  /// **'7 günde alıcı payı: {yuzde}'**
  String rdrYediGunOrt(String yuzde);

  /// No description provided for @rdrSaatlikUpper.
  ///
  /// In tr, this message translates to:
  /// **'SON 24 SAAT · SAAT SAAT NET ALIM'**
  String get rdrSaatlikUpper;

  /// No description provided for @rdrEnIstekliSaat.
  ///
  /// In tr, this message translates to:
  /// **'{aralik} alıcıların en istekli olduğu saat · {tutar} net alım'**
  String rdrEnIstekliSaat(String aralik, String tutar);

  /// No description provided for @rdrIstekliSaatYok.
  ///
  /// In tr, this message translates to:
  /// **'Son 24 saatte alıcıların ağır bastığı bir saat olmadı.'**
  String get rdrIstekliSaatYok;

  /// No description provided for @rdrSonMum.
  ///
  /// In tr, this message translates to:
  /// **'son mum {saat}'**
  String rdrSonMum(String saat);

  /// No description provided for @rdrKriptoDetayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{kod} · Alıcı baskısı'**
  String rdrKriptoDetayBaslik(String kod);

  /// No description provided for @rdrIslemHacmiUpper.
  ///
  /// In tr, this message translates to:
  /// **'İŞLEM HACMİ · SON 20 GÜN'**
  String get rdrIslemHacmiUpper;

  /// No description provided for @rdrHaftaBaslikVar.
  ///
  /// In tr, this message translates to:
  /// **'Son haftada {sayi} varlığında olağandışı hareket var.'**
  String rdrHaftaBaslikVar(String sayi);

  /// No description provided for @rdrHaftaBaslikYok.
  ///
  /// In tr, this message translates to:
  /// **'Son haftada varlıklarında olağandışı bir hareket yok.'**
  String get rdrHaftaBaslikYok;

  /// No description provided for @rdrRozetBuyukGiris.
  ///
  /// In tr, this message translates to:
  /// **'Büyük giriş'**
  String get rdrRozetBuyukGiris;

  /// No description provided for @rdrRozetBuyukCikis.
  ///
  /// In tr, this message translates to:
  /// **'Büyük çıkış'**
  String get rdrRozetBuyukCikis;

  /// No description provided for @rdrRozetHacim.
  ///
  /// In tr, this message translates to:
  /// **'Olağandışı hacim'**
  String get rdrRozetHacim;

  /// No description provided for @rdrRozetAlici.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı istekli'**
  String get rdrRozetAlici;

  /// No description provided for @rdrRozetSatici.
  ///
  /// In tr, this message translates to:
  /// **'Satıcı istekli'**
  String get rdrRozetSatici;

  /// No description provided for @rdrRozetHareketli.
  ///
  /// In tr, this message translates to:
  /// **'Hareketli'**
  String get rdrRozetHareketli;

  /// No description provided for @rdrRozetSakin.
  ///
  /// In tr, this message translates to:
  /// **'Sakin'**
  String get rdrRozetSakin;

  /// No description provided for @rdrSatirFon.
  ///
  /// In tr, this message translates to:
  /// **'Net {tutar} · büyüklüğün {yuzde}'**
  String rdrSatirFon(String tutar, String yuzde);

  /// No description provided for @rdrSatirFonOransiz.
  ///
  /// In tr, this message translates to:
  /// **'Net {tutar}'**
  String rdrSatirFonOransiz(String tutar);

  /// No description provided for @rdrSatirHacim.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} · hacim {kat} kat · fiyat {yuzde}'**
  String rdrSatirHacim(String tarih, String kat, String yuzde);

  /// No description provided for @rdrSatirKripto.
  ///
  /// In tr, this message translates to:
  /// **'7 günde alıcı payı {ort} · son gün {yuzde}'**
  String rdrSatirKripto(String ort, String yuzde);

  /// No description provided for @rdrYatirimciHafta.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} · son hafta {fark}'**
  String rdrYatirimciHafta(String sayi, String fark);

  /// No description provided for @rdrKartHaftaOlayi.
  ///
  /// In tr, this message translates to:
  /// **'Son 7 günde olağandışı gün: {olay}'**
  String rdrKartHaftaOlayi(String olay);

  /// No description provided for @rdrDunAralik.
  ///
  /// In tr, this message translates to:
  /// **'Dün {aralik}'**
  String rdrDunAralik(String aralik);

  /// No description provided for @rdrSaateDokun.
  ///
  /// In tr, this message translates to:
  /// **'Bir saate dokun, o saatin net alımı ve alıcı payı burada görünür.'**
  String get rdrSaateDokun;

  /// No description provided for @anzYararli.
  ///
  /// In tr, this message translates to:
  /// **'İşime yaradı'**
  String get anzYararli;

  /// No description provided for @anzYararsiz.
  ///
  /// In tr, this message translates to:
  /// **'İşime yaramadı'**
  String get anzYararsiz;

  /// No description provided for @rdrSatirKriptoOrtsuz.
  ///
  /// In tr, this message translates to:
  /// **'Son gün alıcı payı {yuzde}'**
  String rdrSatirKriptoOrtsuz(String yuzde);

  /// No description provided for @rdrSatirNot.
  ///
  /// In tr, this message translates to:
  /// **'Not: {metin}'**
  String rdrSatirNot(String metin);

  /// No description provided for @rdrHaftaKaynak.
  ///
  /// In tr, this message translates to:
  /// **'Fon akışı TEFAS · hacim Yahoo Finance · kripto Binance · tavsiye değildir'**
  String get rdrHaftaKaynak;

  /// No description provided for @rdrAylikRaporSatir.
  ///
  /// In tr, this message translates to:
  /// **'{ay} raporu'**
  String rdrAylikRaporSatir(String ay);

  /// No description provided for @rdrOku.
  ///
  /// In tr, this message translates to:
  /// **'Oku'**
  String get rdrOku;

  /// No description provided for @rdrSeritSayi.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} varlığında son haftada olağandışı hareket var'**
  String rdrSeritSayi(String sayi);

  /// No description provided for @rdrAyarHareketSatiri.
  ///
  /// In tr, this message translates to:
  /// **'Pazartesi özetinde hareket satırı'**
  String get rdrAyarHareketSatiri;

  /// No description provided for @rdrAyarHareketSatiriAlt.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık bildirimde fonlarındaki büyük giriş-çıkışı ve olağandışı hacmi de yaz.'**
  String get rdrAyarHareketSatiriAlt;

  /// No description provided for @rdrAyarSakinGoster.
  ///
  /// In tr, this message translates to:
  /// **'Sakin varlıkları özette göster'**
  String get rdrAyarSakinGoster;

  /// No description provided for @rdrAyarSakinGosterAlt.
  ///
  /// In tr, this message translates to:
  /// **'Haftanın özetinde hareketsiz geçen varlıkları da listele.'**
  String get rdrAyarSakinGosterAlt;

  /// No description provided for @prmUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz'**
  String get prmUcretsiz;

  /// No description provided for @prmPremium.
  ///
  /// In tr, this message translates to:
  /// **'Premium'**
  String get prmPremium;

  /// No description provided for @prmSatirVarlik.
  ///
  /// In tr, this message translates to:
  /// **'Varlık'**
  String get prmSatirVarlik;

  /// No description provided for @prmSatirAkis.
  ///
  /// In tr, this message translates to:
  /// **'Para akışı'**
  String get prmSatirAkis;

  /// No description provided for @prmSatirHacim.
  ///
  /// In tr, this message translates to:
  /// **'Hacim radarı'**
  String get prmSatirHacim;

  /// No description provided for @prmSatirNot.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık not'**
  String get prmSatirNot;

  /// No description provided for @prmSatirAylik.
  ///
  /// In tr, this message translates to:
  /// **'Aylık rapor'**
  String get prmSatirAylik;

  /// No description provided for @prmSinirsiz.
  ///
  /// In tr, this message translates to:
  /// **'sınırsız'**
  String get prmSinirsiz;

  /// No description provided for @prmSatirSinyal.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyaller'**
  String get prmSatirSinyal;

  /// No description provided for @prmSinyalUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'1 varlık'**
  String get prmSinyalUcretsiz;

  /// No description provided for @prmSinyalPremium.
  ///
  /// In tr, this message translates to:
  /// **'8 gösterge, tüm varlıklar'**
  String get prmSinyalPremium;

  /// No description provided for @prmSatirTakip.
  ///
  /// In tr, this message translates to:
  /// **'Takip listesi'**
  String get prmSatirTakip;

  /// No description provided for @prmYillikTasarruf.
  ///
  /// In tr, this message translates to:
  /// **'%{oran} tasarruf'**
  String prmYillikTasarruf(String oran);

  /// No description provided for @prmVarErisim.
  ///
  /// In tr, this message translates to:
  /// **'Var'**
  String get prmVarErisim;

  /// No description provided for @prmYokErisim.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get prmYokErisim;

  /// No description provided for @prmAkisUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'son hafta'**
  String get prmAkisUcretsiz;

  /// No description provided for @prmAkisPremium.
  ///
  /// In tr, this message translates to:
  /// **'8 hafta + olaylar'**
  String get prmAkisPremium;

  /// No description provided for @prmHacimUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'son gün'**
  String get prmHacimUcretsiz;

  /// No description provided for @prmHacimPremium.
  ///
  /// In tr, this message translates to:
  /// **'20 gün'**
  String get prmHacimPremium;

  /// No description provided for @prmNotUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'ilk cümle'**
  String get prmNotUcretsiz;

  /// No description provided for @prmNotPremium.
  ///
  /// In tr, this message translates to:
  /// **'tamamı'**
  String get prmNotPremium;

  /// No description provided for @prmKilitAkis.
  ///
  /// In tr, this message translates to:
  /// **'8 haftalık seyir ve {sayi} büyük hareket Premium\'da'**
  String prmKilitAkis(String sayi);

  /// No description provided for @prmKilitAyrinti.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntılar Premium\'da'**
  String get prmKilitAyrinti;

  /// No description provided for @prmKilitNot.
  ///
  /// In tr, this message translates to:
  /// **'Notun tamamı Premium\'da'**
  String get prmKilitNot;

  /// No description provided for @prmKilitEkstreAi.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekâyla eşleme Premium\'da'**
  String get prmKilitEkstreAi;

  /// No description provided for @prmSatirEkstreAi.
  ///
  /// In tr, this message translates to:
  /// **'Ekstreyi yapay zekâyla okutma'**
  String get prmSatirEkstreAi;

  /// No description provided for @prmHediyeBaslik.
  ///
  /// In tr, this message translates to:
  /// **'İlk kullanıcılarımızdansın'**
  String get prmHediyeBaslik;

  /// No description provided for @prmHediyeGovde.
  ///
  /// In tr, this message translates to:
  /// **'{gun} gün Premium senin; kart bilgisi gerekmez. {tarih} tarihinde biter, bitince verilerinden hiçbiri silinmez.'**
  String prmHediyeGovde(String gun, String tarih);

  /// No description provided for @prmTesekkurler.
  ///
  /// In tr, this message translates to:
  /// **'Teşekkürler'**
  String get prmTesekkurler;

  /// No description provided for @prmAbonelikAylik.
  ///
  /// In tr, this message translates to:
  /// **'Premium · aylık'**
  String get prmAbonelikAylik;

  /// No description provided for @prmAbonelikYillik.
  ///
  /// In tr, this message translates to:
  /// **'Premium · yıllık'**
  String get prmAbonelikYillik;

  /// No description provided for @prmAbonelikHediye.
  ///
  /// In tr, this message translates to:
  /// **'Premium · erken kullanıcı hediyesi'**
  String get prmAbonelikHediye;

  /// No description provided for @prmYenileme.
  ///
  /// In tr, this message translates to:
  /// **'Yenileme {tarih} · {magaza}'**
  String prmYenileme(String tarih, String magaza);

  /// No description provided for @prmBitis.
  ///
  /// In tr, this message translates to:
  /// **'{tarih} tarihinde biter'**
  String prmBitis(String tarih);

  /// No description provided for @prmYonet.
  ///
  /// In tr, this message translates to:
  /// **'Yönet'**
  String get prmYonet;

  /// No description provided for @prmGeriYukle.
  ///
  /// In tr, this message translates to:
  /// **'Satın alımları geri yükle'**
  String get prmGeriYukle;

  /// No description provided for @anzNotUpper.
  ///
  /// In tr, this message translates to:
  /// **'HAFTALIK NOT · YAPAY ZEKÂ'**
  String get anzNotUpper;

  /// No description provided for @anzMeta.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} madde · {aralik}'**
  String anzMeta(String sayi, String aralik);

  /// No description provided for @anzNotuOku.
  ///
  /// In tr, this message translates to:
  /// **'Notu oku'**
  String get anzNotuOku;

  /// No description provided for @anzDetayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{kod} · haftalık not'**
  String anzDetayBaslik(String kod);

  /// No description provided for @anzAylikDetayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{kod} · aylık not'**
  String anzAylikDetayBaslik(String kod);

  /// No description provided for @anzAltSatir.
  ///
  /// In tr, this message translates to:
  /// **'Yapay zekâ ile oluşturuldu · girdi {kaynak}, {tarih} · yatırım tavsiyesi değildir'**
  String anzAltSatir(String kaynak, String tarih);

  /// No description provided for @anzIseYaradi.
  ///
  /// In tr, this message translates to:
  /// **'İşine yaradı mı?'**
  String get anzIseYaradi;

  /// No description provided for @anzYanlisSayi.
  ///
  /// In tr, this message translates to:
  /// **'Yanlış bir sayı gördüm'**
  String get anzYanlisSayi;

  /// No description provided for @anzYanlisIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Hangi sayı yanlış? (isteğe bağlı)'**
  String get anzYanlisIpucu;

  /// No description provided for @anzGonder.
  ///
  /// In tr, this message translates to:
  /// **'Gönder'**
  String get anzGonder;

  /// No description provided for @anzTesekkur.
  ///
  /// In tr, this message translates to:
  /// **'Teşekkürler, not incelenecek.'**
  String get anzTesekkur;

  /// No description provided for @anzAylikUpper.
  ///
  /// In tr, this message translates to:
  /// **'AYLIK RAPOR'**
  String get anzAylikUpper;

  /// No description provided for @anzAylikBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{ay} raporu'**
  String anzAylikBaslik(String ay);

  /// No description provided for @anzAylikOzetVar.
  ///
  /// In tr, this message translates to:
  /// **'Notu çıkan {toplam} varlığından {sayi} tanesinde ay boyunca belirgin hareket oldu.'**
  String anzAylikOzetVar(String toplam, String sayi);

  /// No description provided for @anzAylikEksik.
  ///
  /// In tr, this message translates to:
  /// **'{kodlar} için bu ay not çıkmadı; sayıları kendi sayfalarında.'**
  String anzAylikEksik(String kodlar);

  /// No description provided for @anzAylikOzetYok.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay varlıklarında belirgin bir hareket olmadı.'**
  String get anzAylikOzetYok;

  /// No description provided for @anzAylikBos.
  ///
  /// In tr, this message translates to:
  /// **'Bu ayın raporu henüz hazır değil.'**
  String get anzAylikBos;

  /// No description provided for @hkyDevam.
  ///
  /// In tr, this message translates to:
  /// **'Devam'**
  String get hkyDevam;

  /// No description provided for @hkyAtla.
  ///
  /// In tr, this message translates to:
  /// **'Atla'**
  String get hkyAtla;

  /// No description provided for @hkyAylikAcilis.
  ///
  /// In tr, this message translates to:
  /// **'Ayın hikâyesi'**
  String get hkyAylikAcilis;

  /// No description provided for @hkyAylikAcilisAlt.
  ///
  /// In tr, this message translates to:
  /// **'Varlıklarının bu ayı, kart kart.'**
  String get hkyAylikAcilisAlt;

  /// No description provided for @hkyAylikSayiUst.
  ///
  /// In tr, this message translates to:
  /// **'Bu ay notu çıkan varlığın'**
  String get hkyAylikSayiUst;

  /// No description provided for @hkyAylikHareketli.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} tanesinde belirgin hareket oldu.'**
  String hkyAylikHareketli(String sayi);

  /// No description provided for @hkyAylikSakin.
  ///
  /// In tr, this message translates to:
  /// **'Hiçbirinde belirgin hareket yok; sakin bir ay.'**
  String get hkyAylikSakin;

  /// No description provided for @hkyAylikOneCikan.
  ///
  /// In tr, this message translates to:
  /// **'Ayın öne çıkanı'**
  String get hkyAylikOneCikan;

  /// No description provided for @hkyAylikRaporuAc.
  ///
  /// In tr, this message translates to:
  /// **'Raporu aç'**
  String get hkyAylikRaporuAc;

  /// No description provided for @hkyAylikTekrar.
  ///
  /// In tr, this message translates to:
  /// **'Hikâye olarak izle'**
  String get hkyAylikTekrar;

  /// No description provided for @anzOkunamadi.
  ///
  /// In tr, this message translates to:
  /// **'Not şu an açılamadı.'**
  String get anzOkunamadi;

  /// No description provided for @sgnPremiumAktif.
  ///
  /// In tr, this message translates to:
  /// **'Premium göstergeler açık'**
  String get sgnPremiumAktif;

  /// No description provided for @sgnPremiumAktifGovde.
  ///
  /// In tr, this message translates to:
  /// **'ADX, Williams %R ve CCI sinyal analizine katılıyor.'**
  String get sgnPremiumAktifGovde;

  /// No description provided for @sgnPremiumKilitBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Premium göstergeler'**
  String get sgnPremiumKilitBaslik;

  /// No description provided for @sgnPremiumKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'ADX, Williams %R ve CCI, Premium ile sinyal analizine katılır.'**
  String get sgnPremiumKilitGovde;

  /// No description provided for @sgnPremiumGec.
  ///
  /// In tr, this message translates to:
  /// **'Premium\'a geç'**
  String get sgnPremiumGec;

  /// No description provided for @pwOzSinirsiz.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız varlık ve tüm varlık türleri'**
  String get pwOzSinirsiz;

  /// No description provided for @pwOzGosterge.
  ///
  /// In tr, this message translates to:
  /// **'Sinyal analizinde ADX, Williams %R ve CCI'**
  String get pwOzGosterge;

  /// No description provided for @pwOzSiklik.
  ///
  /// In tr, this message translates to:
  /// **'Tüm varlıklarında sinyal bildirimi, seçtiğin sıklıkta'**
  String get pwOzSiklik;

  /// No description provided for @pwOzKarsilastir.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştır\'da 5 seriye kadar'**
  String get pwOzKarsilastir;

  /// No description provided for @pwOzOrtak.
  ///
  /// In tr, this message translates to:
  /// **'Birden fazla ortakla portföy paylaşımı'**
  String get pwOzOrtak;

  /// No description provided for @sgnSlotNotu.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz sürümde sinyal bildirimi tek varlıkta ve her tür için günde 1 kez gelir; varlığı, varlığın ekranından seçersin. Premium\'da tüm varlıkların ve seçtiğin sıklık gelir.'**
  String get sgnSlotNotu;

  /// No description provided for @sgnVarlikAcik.
  ///
  /// In tr, this message translates to:
  /// **'Sinyal bildirimi bu varlıkta açık. Ücretsiz planda tek varlıkta gelir.'**
  String get sgnVarlikAcik;

  /// No description provided for @sgnVarlikKilit.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz planda sinyal bildirimi tek varlıkta: {ad}. Tüm varlıkların için Premium.'**
  String sgnVarlikKilit(String ad);

  /// No description provided for @sgnVarlikTasi.
  ///
  /// In tr, this message translates to:
  /// **'Sinyali buraya taşı'**
  String get sgnVarlikTasi;

  /// No description provided for @sgnSlotKilitli.
  ///
  /// In tr, this message translates to:
  /// **'{secenek}, Premium'**
  String sgnSlotKilitli(String secenek);

  /// No description provided for @cmpSinirPremium.
  ///
  /// In tr, this message translates to:
  /// **'Premium ile 5 seriye kadar'**
  String get cmpSinirPremium;

  /// No description provided for @cmpSinirDolu.
  ///
  /// In tr, this message translates to:
  /// **'En fazla 5 varlık'**
  String get cmpSinirDolu;

  /// No description provided for @pwOzRadar.
  ///
  /// In tr, this message translates to:
  /// **'Para akışı ve hacim radarının ayrıntısı, haftalık notun tamamı'**
  String get pwOzRadar;

  /// No description provided for @pwFiyatAylik.
  ///
  /// In tr, this message translates to:
  /// **'{fiyat}/ay'**
  String pwFiyatAylik(String fiyat);

  /// No description provided for @pwFiyatYillik.
  ///
  /// In tr, this message translates to:
  /// **'{fiyat}/yıl'**
  String pwFiyatYillik(String fiyat);

  /// No description provided for @pwDenemeAltyazi.
  ///
  /// In tr, this message translates to:
  /// **'{gun} gün ücretsiz, sonra otomatik yenilenir'**
  String pwDenemeAltyazi(int gun);

  /// No description provided for @pwYenilenirAltyazi.
  ///
  /// In tr, this message translates to:
  /// **'Otomatik yenilenir, istediğin zaman iptal edebilirsin'**
  String get pwYenilenirAltyazi;

  /// No description provided for @pwDenemeDugme.
  ///
  /// In tr, this message translates to:
  /// **'{gun} gün ücretsiz dene'**
  String pwDenemeDugme(int gun);

  /// No description provided for @pwAboneOl.
  ///
  /// In tr, this message translates to:
  /// **'Abone ol'**
  String get pwAboneOl;

  /// No description provided for @pwKosulAndroid.
  ///
  /// In tr, this message translates to:
  /// **'Ödeme Google Play hesabından alınır. Abonelik, dönem bitmeden iptal edilmezse aynı süre ve fiyatla otomatik yenilenir. Google Play › Ödemeler ve abonelikler › Abonelikler\'den yönetebilir ya da iptal edebilirsin.'**
  String get pwKosulAndroid;

  /// No description provided for @pwDenemeKosul.
  ///
  /// In tr, this message translates to:
  /// **'{gun} günlük ücretsiz deneme bitmeden iptal etmezsen deneme sonunda ücret alınır.'**
  String pwDenemeKosul(int gun);

  /// No description provided for @pwKullanilamaz.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma şu an kullanılamıyor. Biraz sonra yeniden dene.'**
  String get pwKullanilamaz;

  /// No description provided for @pwBeklemede.
  ///
  /// In tr, this message translates to:
  /// **'Ödemen onay bekliyor. Onaylanınca Premium kendiliğinden açılır.'**
  String get pwBeklemede;

  /// No description provided for @pwHata.
  ///
  /// In tr, this message translates to:
  /// **'Satın alma tamamlanamadı. Ücret alınmadıysa yeniden deneyebilirsin.'**
  String get pwHata;

  /// No description provided for @pwGeriYuklendi.
  ///
  /// In tr, this message translates to:
  /// **'Aboneliğin geri yüklendi.'**
  String get pwGeriYuklendi;

  /// No description provided for @pwGeriYukBulunamadi.
  ///
  /// In tr, this message translates to:
  /// **'Bu hesapta etkin bir abonelik bulunamadı.'**
  String get pwGeriYukBulunamadi;

  /// No description provided for @pwGeriYukHata.
  ///
  /// In tr, this message translates to:
  /// **'Geri yükleme şu an yapılamadı. Biraz sonra yeniden dene.'**
  String get pwGeriYukHata;

  /// No description provided for @assetTypeEurobond.
  ///
  /// In tr, this message translates to:
  /// **'Eurobond'**
  String get assetTypeEurobond;

  /// No description provided for @tickerHintEurobond.
  ///
  /// In tr, this message translates to:
  /// **'Listeden seç ya da ISIN yaz, örn. US900123DF45'**
  String get tickerHintEurobond;

  /// No description provided for @stockMarketBist.
  ///
  /// In tr, this message translates to:
  /// **'BIST'**
  String get stockMarketBist;

  /// No description provided for @stockMarketUs.
  ///
  /// In tr, this message translates to:
  /// **'ABD'**
  String get stockMarketUs;

  /// No description provided for @portfolioGroupBistStock.
  ///
  /// In tr, this message translates to:
  /// **'BIST Hisse'**
  String get portfolioGroupBistStock;

  /// No description provided for @portfolioGroupUsStock.
  ///
  /// In tr, this message translates to:
  /// **'ABD Hisse'**
  String get portfolioGroupUsStock;

  /// No description provided for @stockMarketSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Hisse pazarı: {market}'**
  String stockMarketSemantics(String market);

  /// No description provided for @usStocks.
  ///
  /// In tr, this message translates to:
  /// **'ABD Hisseleri'**
  String get usStocks;

  /// No description provided for @pickUsStock.
  ///
  /// In tr, this message translates to:
  /// **'ABD hissesi seç'**
  String get pickUsStock;

  /// No description provided for @pickUsStockTap.
  ///
  /// In tr, this message translates to:
  /// **'ABD hissesi seçmek için dokun...'**
  String get pickUsStockTap;

  /// No description provided for @usSymbolHint.
  ///
  /// In tr, this message translates to:
  /// **'Sembol yaz (örn: AAPL, BRK-B)'**
  String get usSymbolHint;

  /// No description provided for @selectedUsStockSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Seçili ABD hissesi: {name}. Değiştirmek için çift dokun.'**
  String selectedUsStockSemantics(String name);

  /// No description provided for @usStockCurrencyLocked.
  ///
  /// In tr, this message translates to:
  /// **'ABD hissesi dolarla kaydedilir'**
  String get usStockCurrencyLocked;

  /// No description provided for @costsUpper.
  ///
  /// In tr, this message translates to:
  /// **'MASRAFLAR'**
  String get costsUpper;

  /// No description provided for @costsPaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödenen'**
  String get costsPaid;

  /// No description provided for @costsEstimatedOnSale.
  ///
  /// In tr, this message translates to:
  /// **'Satarken tahmini'**
  String get costsEstimatedOnSale;

  /// No description provided for @costTagPaid.
  ///
  /// In tr, this message translates to:
  /// **'Ödendi'**
  String get costTagPaid;

  /// No description provided for @costTagEstimated.
  ///
  /// In tr, this message translates to:
  /// **'Tahmini'**
  String get costTagEstimated;

  /// No description provided for @costTagInfo.
  ///
  /// In tr, this message translates to:
  /// **'Bilgi'**
  String get costTagInfo;

  /// No description provided for @costsShowAll.
  ///
  /// In tr, this message translates to:
  /// **'Tümünü gör ({count})'**
  String costsShowAll(int count);

  /// No description provided for @costsShowLess.
  ///
  /// In tr, this message translates to:
  /// **'Daha az göster'**
  String get costsShowLess;

  /// No description provided for @identityEurobond.
  ///
  /// In tr, this message translates to:
  /// **'Tahvil'**
  String get identityEurobond;

  /// No description provided for @pickEurobondTap.
  ///
  /// In tr, this message translates to:
  /// **'Tahvil seçmek için dokun'**
  String get pickEurobondTap;

  /// No description provided for @pickEurobondPrompt.
  ///
  /// In tr, this message translates to:
  /// **'Bir eurobond seç'**
  String get pickEurobondPrompt;

  /// No description provided for @eurobondSelectedSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Seçili tahvil: {name}. Değiştirmek için çift dokun.'**
  String eurobondSelectedSemantics(String name);

  /// No description provided for @eurobondPickerTitle.
  ///
  /// In tr, this message translates to:
  /// **'Eurobondlar'**
  String get eurobondPickerTitle;

  /// No description provided for @eurobondLoading.
  ///
  /// In tr, this message translates to:
  /// **'Tahvil listesi yükleniyor'**
  String get eurobondLoading;

  /// No description provided for @eurobondLoadFailed.
  ///
  /// In tr, this message translates to:
  /// **'Tahvil listesi yüklenemedi'**
  String get eurobondLoadFailed;

  /// No description provided for @eurobondSourceNote.
  ///
  /// In tr, this message translates to:
  /// **'Şimdilik yalnız USD tahviller. Fiyat temiz fiyattır, nominalin yüzdesi. Yatırım tavsiyesi değildir.'**
  String get eurobondSourceNote;

  /// No description provided for @eurobondMaturityShort.
  ///
  /// In tr, this message translates to:
  /// **'Vade {date}'**
  String eurobondMaturityShort(String date);

  /// No description provided for @eurobondYieldShort.
  ///
  /// In tr, this message translates to:
  /// **'Getiri {pct}'**
  String eurobondYieldShort(String pct);

  /// No description provided for @eurobondIsinInvalid.
  ///
  /// In tr, this message translates to:
  /// **'Bu ISIN geçersiz: kontrol hanesi tutmuyor. Bir haneyi yanlış yazmış olabilirsin.'**
  String get eurobondIsinInvalid;

  /// No description provided for @eurobondIsinNotListed.
  ///
  /// In tr, this message translates to:
  /// **'Bu ISIN listede yok. Şimdilik yalnız listedeki USD tahvilleri ekleyebilirsin.'**
  String get eurobondIsinNotListed;

  /// No description provided for @eurobondCleanPrice.
  ///
  /// In tr, this message translates to:
  /// **'Temiz fiyat (%)'**
  String get eurobondCleanPrice;

  /// No description provided for @eurobondCleanPriceRequired.
  ///
  /// In tr, this message translates to:
  /// **'Temiz fiyatı yaz'**
  String get eurobondCleanPriceRequired;

  /// No description provided for @eurobondCurrencyLocked.
  ///
  /// In tr, this message translates to:
  /// **'Tahvilin para birimi'**
  String get eurobondCurrencyLocked;

  /// No description provided for @eurobondAccruedLine.
  ///
  /// In tr, this message translates to:
  /// **'İşlemiş faiz: {accrued} · Ödenen: {paid}'**
  String eurobondAccruedLine(String accrued, String paid);

  /// No description provided for @eurobondAccruedOnly.
  ///
  /// In tr, this message translates to:
  /// **'İşlemiş faiz: {accrued}'**
  String eurobondAccruedOnly(String accrued);

  /// No description provided for @eurobondTotalBreakdown.
  ///
  /// In tr, this message translates to:
  /// **'{nominal} nominal × kirli {dirty}'**
  String eurobondTotalBreakdown(String nominal, String dirty);

  /// No description provided for @bondInfoUpper.
  ///
  /// In tr, this message translates to:
  /// **'TAHVİL BİLGİLERİ'**
  String get bondInfoUpper;

  /// No description provided for @bondCleanPrice.
  ///
  /// In tr, this message translates to:
  /// **'Temiz fiyat'**
  String get bondCleanPrice;

  /// No description provided for @bondAccrued.
  ///
  /// In tr, this message translates to:
  /// **'İşlemiş faiz'**
  String get bondAccrued;

  /// No description provided for @bondDirtyPrice.
  ///
  /// In tr, this message translates to:
  /// **'Kirli fiyat'**
  String get bondDirtyPrice;

  /// No description provided for @bondPerNominalNote.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatlar 100 nominal başına.'**
  String get bondPerNominalNote;

  /// No description provided for @bondYtm.
  ///
  /// In tr, this message translates to:
  /// **'Vadeye getiri'**
  String get bondYtm;

  /// No description provided for @bondCoupon.
  ///
  /// In tr, this message translates to:
  /// **'Kupon'**
  String get bondCoupon;

  /// No description provided for @bondCouponValue.
  ///
  /// In tr, this message translates to:
  /// **'{rate} · yılda {count} kez'**
  String bondCouponValue(String rate, String count);

  /// No description provided for @bondNextCoupon.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki kupon'**
  String get bondNextCoupon;

  /// No description provided for @bondNextCouponValue.
  ///
  /// In tr, this message translates to:
  /// **'{date} · {amount}'**
  String bondNextCouponValue(String date, String amount);

  /// No description provided for @bondWithholding.
  ///
  /// In tr, this message translates to:
  /// **'Stopaj {rate}'**
  String bondWithholding(String rate);

  /// No description provided for @bondMaturity.
  ///
  /// In tr, this message translates to:
  /// **'Vade'**
  String get bondMaturity;

  /// No description provided for @bondMaturityValue.
  ///
  /// In tr, this message translates to:
  /// **'{date} · {days} gün kaldı'**
  String bondMaturityValue(String date, String days);

  /// No description provided for @bondIssuer.
  ///
  /// In tr, this message translates to:
  /// **'İhraççı'**
  String get bondIssuer;

  /// No description provided for @bondIssuerTreasury.
  ///
  /// In tr, this message translates to:
  /// **'Hazine'**
  String get bondIssuerTreasury;

  /// No description provided for @bondIssuerCorporate.
  ///
  /// In tr, this message translates to:
  /// **'Özel sektör'**
  String get bondIssuerCorporate;

  /// No description provided for @bondBankSellUpper.
  ///
  /// In tr, this message translates to:
  /// **'BANKAYA SATARSAN'**
  String get bondBankSellUpper;

  /// No description provided for @bondBankZiraat.
  ///
  /// In tr, this message translates to:
  /// **'Ziraat Bankası'**
  String get bondBankZiraat;

  /// No description provided for @bondBankUpdated.
  ///
  /// In tr, this message translates to:
  /// **'{bank} · {time}'**
  String bondBankUpdated(String bank, String time);

  /// No description provided for @bondBankBid.
  ///
  /// In tr, this message translates to:
  /// **'Banka alış'**
  String get bondBankBid;

  /// No description provided for @bondBankAsk.
  ///
  /// In tr, this message translates to:
  /// **'Banka satış'**
  String get bondBankAsk;

  /// No description provided for @bondBankSpread.
  ///
  /// In tr, this message translates to:
  /// **'Makas'**
  String get bondBankSpread;

  /// No description provided for @bondBankProceeds.
  ///
  /// In tr, this message translates to:
  /// **'Bugün satarsan eline geçen'**
  String get bondBankProceeds;

  /// No description provided for @bondBankNote.
  ///
  /// In tr, this message translates to:
  /// **'Banka fiyatları kirli fiyattır (işlemiş faiz dahil).'**
  String get bondBankNote;

  /// No description provided for @typePickerSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Ara: {examples}…'**
  String typePickerSearchHint(String examples);

  /// No description provided for @typePickerGroupMarkets.
  ///
  /// In tr, this message translates to:
  /// **'Borsa ve fon'**
  String get typePickerGroupMarkets;

  /// No description provided for @typePickerGroupFxPrecious.
  ///
  /// In tr, this message translates to:
  /// **'Döviz ve değerli'**
  String get typePickerGroupFxPrecious;

  /// No description provided for @typePickerGroupSavings.
  ///
  /// In tr, this message translates to:
  /// **'Birikim'**
  String get typePickerGroupSavings;

  /// No description provided for @typePickerUsStock.
  ///
  /// In tr, this message translates to:
  /// **'ABD hisse'**
  String get typePickerUsStock;

  /// No description provided for @typePickerChange.
  ///
  /// In tr, this message translates to:
  /// **'Değiştir'**
  String get typePickerChange;

  /// No description provided for @typePickerChangeSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Varlık türünü değiştir'**
  String get typePickerChangeSemantics;

  /// No description provided for @typePickerHintBistOpen.
  ///
  /// In tr, this message translates to:
  /// **'BIST açık'**
  String get typePickerHintBistOpen;

  /// No description provided for @typePickerHintBistClosed.
  ///
  /// In tr, this message translates to:
  /// **'BIST kapalı'**
  String get typePickerHintBistClosed;

  /// No description provided for @typePickerHint247.
  ///
  /// In tr, this message translates to:
  /// **'7/24'**
  String get typePickerHint247;

  /// No description provided for @s7AraSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Ara'**
  String get s7AraSemantics;

  /// No description provided for @s7AramaIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Varlık, sembol ya da işlem ara'**
  String get s7AramaIpucu;

  /// No description provided for @s7VarliklarimUpper.
  ///
  /// In tr, this message translates to:
  /// **'VARLIKLARIM'**
  String get s7VarliklarimUpper;

  /// No description provided for @s7PiyasaUpper.
  ///
  /// In tr, this message translates to:
  /// **'PİYASA'**
  String get s7PiyasaUpper;

  /// No description provided for @s7EylemlerUpper.
  ///
  /// In tr, this message translates to:
  /// **'EYLEMLER'**
  String get s7EylemlerUpper;

  /// No description provided for @s7EylemFiyatAlarmlari.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmları'**
  String get s7EylemFiyatAlarmlari;

  /// No description provided for @s7EylemSinyalAyarlari.
  ///
  /// In tr, this message translates to:
  /// **'Sinyal ayarları'**
  String get s7EylemSinyalAyarlari;

  /// No description provided for @s7EylemEkstreAktar.
  ///
  /// In tr, this message translates to:
  /// **'Ekstreden aktar (CSV)'**
  String get s7EylemEkstreAktar;

  /// No description provided for @s7EylemTopluEkle.
  ///
  /// In tr, this message translates to:
  /// **'Toplu ekle'**
  String get s7EylemTopluEkle;

  /// No description provided for @s7EylemTumHareketler.
  ///
  /// In tr, this message translates to:
  /// **'Tüm hareketler'**
  String get s7EylemTumHareketler;

  /// No description provided for @s7EylemKarsilastir.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştır'**
  String get s7EylemKarsilastir;

  /// No description provided for @s7EylemTakipListesi.
  ///
  /// In tr, this message translates to:
  /// **'Takibe al'**
  String get s7EylemTakipListesi;

  /// No description provided for @s7EylemBildirimler.
  ///
  /// In tr, this message translates to:
  /// **'Bildirimler'**
  String get s7EylemBildirimler;

  /// No description provided for @s7EylemAyarlar.
  ///
  /// In tr, this message translates to:
  /// **'Ayarlar'**
  String get s7EylemAyarlar;

  /// No description provided for @s4AnalysisUpper.
  ///
  /// In tr, this message translates to:
  /// **'ANALİZ'**
  String get s4AnalysisUpper;

  /// No description provided for @s4HistoryDocsUpper.
  ///
  /// In tr, this message translates to:
  /// **'GEÇMİŞ VE BELGELER'**
  String get s4HistoryDocsUpper;

  /// No description provided for @s4Details.
  ///
  /// In tr, this message translates to:
  /// **'Ayrıntı'**
  String get s4Details;

  /// No description provided for @s4RowSignals.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyaller'**
  String get s4RowSignals;

  /// No description provided for @s4RowFundReport.
  ///
  /// In tr, this message translates to:
  /// **'Fon karnesi'**
  String get s4RowFundReport;

  /// No description provided for @s4RowFlow.
  ///
  /// In tr, this message translates to:
  /// **'Para akışı'**
  String get s4RowFlow;

  /// No description provided for @s4RowVolume.
  ///
  /// In tr, this message translates to:
  /// **'Hacim radarı'**
  String get s4RowVolume;

  /// No description provided for @s4RowCrypto.
  ///
  /// In tr, this message translates to:
  /// **'Alıcı baskısı'**
  String get s4RowCrypto;

  /// No description provided for @s4RowNote.
  ///
  /// In tr, this message translates to:
  /// **'Analiz notu'**
  String get s4RowNote;

  /// No description provided for @s3DagilimBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Dağılım'**
  String get s3DagilimBaslik;

  /// No description provided for @s3HalkayiAc.
  ///
  /// In tr, this message translates to:
  /// **'Dağılımı büyük halkada aç'**
  String get s3HalkayiAc;

  /// No description provided for @s3DigerKatlanan.
  ///
  /// In tr, this message translates to:
  /// **'Diğer ({n})'**
  String s3DigerKatlanan(int n);

  /// No description provided for @s5OnAyarSoru.
  ///
  /// In tr, this message translates to:
  /// **'Ne sıklıkta haber verelim?'**
  String get s5OnAyarSoru;

  /// No description provided for @s5OnAyarAz.
  ///
  /// In tr, this message translates to:
  /// **'Az'**
  String get s5OnAyarAz;

  /// No description provided for @s5OnAyarDengeli.
  ///
  /// In tr, this message translates to:
  /// **'Dengeli'**
  String get s5OnAyarDengeli;

  /// No description provided for @s5OnAyarCok.
  ///
  /// In tr, this message translates to:
  /// **'Çok'**
  String get s5OnAyarCok;

  /// No description provided for @s5OnAyarOzel.
  ///
  /// In tr, this message translates to:
  /// **'Özel'**
  String get s5OnAyarOzel;

  /// No description provided for @s5OnAyarAzAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Yalnız güçlü sinyaller (%85 güven), günde 1 kez, RSI ve MACD ile.'**
  String get s5OnAyarAzAciklama;

  /// No description provided for @s5OnAyarDengeliAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Önerilen: %70 güven, günde 2 kez (11:00 ve 15:00), temel göstergelerin tümü.'**
  String get s5OnAyarDengeliAciklama;

  /// No description provided for @s5OnAyarCokAciklama.
  ///
  /// In tr, this message translates to:
  /// **'%50 güvenden itibaren, 2 saatte bir, temel göstergelerin tümü.'**
  String get s5OnAyarCokAciklama;

  /// No description provided for @s5OnAyarOzelAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Kategorilerde kendi ayarların var. Bir seçenek seçersen tüm kategorilere uygulanır.'**
  String get s5OnAyarOzelAciklama;

  /// No description provided for @s5KategoriyeGoreOzellestir.
  ///
  /// In tr, this message translates to:
  /// **'Kategoriye göre özelleştir'**
  String get s5KategoriyeGoreOzellestir;

  /// No description provided for @s2Filtre.
  ///
  /// In tr, this message translates to:
  /// **'Filtre'**
  String get s2Filtre;

  /// No description provided for @s2FiltreSayili.
  ///
  /// In tr, this message translates to:
  /// **'Filtre · {n}'**
  String s2FiltreSayili(int n);

  /// No description provided for @s2FiltreEtkin.
  ///
  /// In tr, this message translates to:
  /// **'Filtre, {n} etkin'**
  String s2FiltreEtkin(int n);

  /// No description provided for @s2FiltreKisi.
  ///
  /// In tr, this message translates to:
  /// **'Kişi'**
  String get s2FiltreKisi;

  /// No description provided for @s2FiltreKategori.
  ///
  /// In tr, this message translates to:
  /// **'Kategori'**
  String get s2FiltreKategori;

  /// No description provided for @s2FiltreSifirla.
  ///
  /// In tr, this message translates to:
  /// **'Sıfırla'**
  String get s2FiltreSifirla;

  /// No description provided for @s2FiltreUygula.
  ///
  /// In tr, this message translates to:
  /// **'Uygula'**
  String get s2FiltreUygula;

  /// No description provided for @s2FiltreYok.
  ///
  /// In tr, this message translates to:
  /// **'Yok'**
  String get s2FiltreYok;

  /// No description provided for @s2BakiyeArttiAlim.
  ///
  /// In tr, this message translates to:
  /// **'Bakiye {tutar} arttı; bunun {alim} kadarı yeni alım.'**
  String s2BakiyeArttiAlim(String tutar, String alim);

  /// No description provided for @s2BakiyeAzaldiAlim.
  ///
  /// In tr, this message translates to:
  /// **'Bakiye {tutar} azaldı; dönemde {alim} yeni alım yaptın.'**
  String s2BakiyeAzaldiAlim(String tutar, String alim);

  /// No description provided for @s2BakiyeArttiSatis.
  ///
  /// In tr, this message translates to:
  /// **'Bakiye {tutar} arttı; dönemde {satis} satış yaptın.'**
  String s2BakiyeArttiSatis(String tutar, String satis);

  /// No description provided for @s2BakiyeAzaldiSatis.
  ///
  /// In tr, this message translates to:
  /// **'Bakiye {tutar} azaldı; bunun {satis} kadarı satış.'**
  String s2BakiyeAzaldiSatis(String tutar, String satis);

  /// No description provided for @s6Raporlar.
  ///
  /// In tr, this message translates to:
  /// **'Raporlar'**
  String get s6Raporlar;

  /// No description provided for @s6HaftaOzetiAlt.
  ///
  /// In tr, this message translates to:
  /// **'Fonlarında ve hisselerinde bu hafta olanlar'**
  String get s6HaftaOzetiAlt;

  /// No description provided for @s6AylikRapor.
  ///
  /// In tr, this message translates to:
  /// **'Aylık rapor'**
  String get s6AylikRapor;

  /// No description provided for @s6YilOzeti.
  ///
  /// In tr, this message translates to:
  /// **'Yıl özeti'**
  String get s6YilOzeti;

  /// No description provided for @s6Siralama.
  ///
  /// In tr, this message translates to:
  /// **'Sıralama'**
  String get s6Siralama;

  /// No description provided for @s6SiralamaAlt.
  ///
  /// In tr, this message translates to:
  /// **'Zirvedeki portföyler ve ortaklarınla yarış'**
  String get s6SiralamaAlt;

  /// No description provided for @pwdSlogan.
  ///
  /// In tr, this message translates to:
  /// **'Sandığının içini aç.'**
  String get pwdSlogan;

  /// No description provided for @pwdOnceki.
  ///
  /// In tr, this message translates to:
  /// **'Önceki özellik'**
  String get pwdOnceki;

  /// No description provided for @pwdSonraki.
  ///
  /// In tr, this message translates to:
  /// **'Sonraki özellik'**
  String get pwdSonraki;

  /// No description provided for @pwdIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Sağa ya da sola kaydırarak diğer Premium özelliklerine geç'**
  String get pwdIpucu;

  /// No description provided for @pwdUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz: {deger}'**
  String pwdUcretsiz(String deger);

  /// No description provided for @pwdPremium.
  ///
  /// In tr, this message translates to:
  /// **'Premium: {deger}'**
  String pwdPremium(String deger);

  /// No description provided for @pwdVarlikEtiket.
  ///
  /// In tr, this message translates to:
  /// **'VARLIK SINIRI'**
  String get pwdVarlikEtiket;

  /// No description provided for @pwdVarlikBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} varlık ücretsiz. Gerisi Premium\'da.'**
  String pwdVarlikBaslik(int sayi);

  /// No description provided for @pwdVarlikCubuk.
  ///
  /// In tr, this message translates to:
  /// **'Ücretsiz sınır'**
  String get pwdVarlikCubuk;

  /// No description provided for @pwdVarlikUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'{varlik} varlık, {takip} takip'**
  String pwdVarlikUcretsiz(int varlik, int takip);

  /// No description provided for @pwdSinyalEtiket.
  ///
  /// In tr, this message translates to:
  /// **'SİNYAL'**
  String get pwdSinyalEtiket;

  /// No description provided for @pwdSinyalBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Sekiz gösterge ve her varlığında, seçtiğin saatte bildirim.'**
  String get pwdSinyalBaslik;

  /// No description provided for @pwdSinyalUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'günde {sayi}'**
  String pwdSinyalUcretsiz(int sayi);

  /// No description provided for @pwdSinyalUcretsizTek.
  ///
  /// In tr, this message translates to:
  /// **'günde {sayi}, tek varlık'**
  String pwdSinyalUcretsizTek(int sayi);

  /// No description provided for @pwdSinyalPremium.
  ///
  /// In tr, this message translates to:
  /// **'8 gösterge, tüm varlıklar'**
  String get pwdSinyalPremium;

  /// No description provided for @pwdKarsEtiket.
  ///
  /// In tr, this message translates to:
  /// **'KARŞILAŞTIR'**
  String get pwdKarsEtiket;

  /// No description provided for @pwdKarsRozet.
  ///
  /// In tr, this message translates to:
  /// **'{ucretsiz} → {premium} seri'**
  String pwdKarsRozet(int ucretsiz, int premium);

  /// No description provided for @pwdKarsBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Portföyünü altın, dolar ve endeksle aynı grafikte gör.'**
  String get pwdKarsBaslik;

  /// No description provided for @pwdSeri.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} seri'**
  String pwdSeri(int sayi);

  /// No description provided for @pwdOrtakEtiket.
  ///
  /// In tr, this message translates to:
  /// **'ORTAK'**
  String get pwdOrtakEtiket;

  /// No description provided for @pwdOrtakBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Eşinle, ailenle, ortağınla; birden fazla ortak.'**
  String get pwdOrtakBaslik;

  /// No description provided for @pwdOrtakSayi.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} ortak'**
  String pwdOrtakSayi(int sayi);

  /// No description provided for @pwdAkisEtiket.
  ///
  /// In tr, this message translates to:
  /// **'PARA AKIŞI'**
  String get pwdAkisEtiket;

  /// No description provided for @pwdAkisBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Fonuna para giriyor mu, 8 haftada gör.'**
  String get pwdAkisBaslik;

  /// No description provided for @pwdHacimEtiket.
  ///
  /// In tr, this message translates to:
  /// **'HACİM RADARI'**
  String get pwdHacimEtiket;

  /// No description provided for @pwdHacimBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü hacim olağandışı mı, 20 günle kıyasla.'**
  String get pwdHacimBaslik;

  /// No description provided for @pwdNotEtiket.
  ///
  /// In tr, this message translates to:
  /// **'HAFTALIK NOT'**
  String get pwdNotEtiket;

  /// No description provided for @pwdNotBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Haftalık notun devamı Premium\'da.'**
  String get pwdNotBaslik;

  /// No description provided for @pwdNotIlk.
  ///
  /// In tr, this message translates to:
  /// **'Bu hafta portföyündeki fonlara para girişi sürdü.'**
  String get pwdNotIlk;

  /// No description provided for @pwdNotDevam.
  ///
  /// In tr, this message translates to:
  /// **' Hangisinin öne çıktığı ve bunun ne anlattığı notun devamında okunur hâle gelir…'**
  String get pwdNotDevam;

  /// No description provided for @pwdEkstreEtiket.
  ///
  /// In tr, this message translates to:
  /// **'EKSTRE'**
  String get pwdEkstreEtiket;

  /// No description provided for @pwdEkstreBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Ekstreni yükle, satırları yapay zekâ eşlesin.'**
  String get pwdEkstreBaslik;

  /// No description provided for @pwdEkstrePremium.
  ///
  /// In tr, this message translates to:
  /// **'yapay zekâyla eşleme'**
  String get pwdEkstrePremium;

  /// No description provided for @pwdYillikAlt.
  ///
  /// In tr, this message translates to:
  /// **'Yılda bir kez ödenir · ayda {aylik}'**
  String pwdYillikAlt(String aylik);

  /// No description provided for @pwdYillikAltSade.
  ///
  /// In tr, this message translates to:
  /// **'Yılda bir kez ödenir'**
  String get pwdYillikAltSade;

  /// No description provided for @pwdYillikDenemeAlt.
  ///
  /// In tr, this message translates to:
  /// **'{gun} gün ücretsiz, sonra yılda bir kez {fiyat}'**
  String pwdYillikDenemeAlt(int gun, String fiyat);

  /// No description provided for @pwdAylikAlt.
  ///
  /// In tr, this message translates to:
  /// **'Her ay yenilenir, istediğin ay bırakırsın'**
  String get pwdAylikAlt;

  /// No description provided for @pwdAylikDenemeAlt.
  ///
  /// In tr, this message translates to:
  /// **'{gun} gün ücretsiz, sonra ayda {fiyat}'**
  String pwdAylikDenemeAlt(int gun, String fiyat);

  /// No description provided for @pwdBugun.
  ///
  /// In tr, this message translates to:
  /// **'Bugün'**
  String get pwdBugun;

  /// No description provided for @pwdHerSeyAcik.
  ///
  /// In tr, this message translates to:
  /// **'Her şey açık'**
  String get pwdHerSeyAcik;

  /// No description provided for @pwdGun.
  ///
  /// In tr, this message translates to:
  /// **'{gun}. gün'**
  String pwdGun(int gun);

  /// No description provided for @pwdIlkOdeme.
  ///
  /// In tr, this message translates to:
  /// **'İlk ödeme'**
  String get pwdIlkOdeme;

  /// No description provided for @pwdGuvenTakip.
  ///
  /// In tr, this message translates to:
  /// **'Portföy takibin her zaman ücretsiz'**
  String get pwdGuvenTakip;

  /// No description provided for @pwdGuvenIptal.
  ///
  /// In tr, this message translates to:
  /// **'İstediğin an iptal, dönem sonuna kadar açık'**
  String get pwdGuvenIptal;

  /// No description provided for @pwdYillikAboneOl.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık abone ol'**
  String get pwdYillikAboneOl;

  /// No description provided for @pwdAylikAboneOl.
  ///
  /// In tr, this message translates to:
  /// **'Aylık abone ol'**
  String get pwdAylikAboneOl;

  /// No description provided for @depositBankPick.
  ///
  /// In tr, this message translates to:
  /// **'Bankanı seç'**
  String get depositBankPick;

  /// No description provided for @depositBankSearchHint.
  ///
  /// In tr, this message translates to:
  /// **'Banka ara'**
  String get depositBankSearchHint;

  /// No description provided for @depositBankUseTyped.
  ///
  /// In tr, this message translates to:
  /// **'\"{ad}\" olarak kullan'**
  String depositBankUseTyped(String ad);

  /// No description provided for @depositBankSectionDeposit.
  ///
  /// In tr, this message translates to:
  /// **'Bankalar'**
  String get depositBankSectionDeposit;

  /// No description provided for @depositBankSectionParticipation.
  ///
  /// In tr, this message translates to:
  /// **'Katılım bankaları'**
  String get depositBankSectionParticipation;

  /// No description provided for @depositBankListUnavailable.
  ///
  /// In tr, this message translates to:
  /// **'Liste şu an yüklenemedi. Bankanın adını yazıp kullanabilirsin.'**
  String get depositBankListUnavailable;

  /// No description provided for @depositRateAnnualGross.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık brüt (%)'**
  String get depositRateAnnualGross;

  /// No description provided for @depositRateMonthlyGross.
  ///
  /// In tr, this message translates to:
  /// **'Aylık brüt (%)'**
  String get depositRateMonthlyGross;

  /// No description provided for @depositRateMarketAverage.
  ///
  /// In tr, this message translates to:
  /// **'Piyasa ortalaması (TCMB, {date} haftası), bankaya özel değil. Sana farklı bir oran verildiyse değiştir.'**
  String depositRateMarketAverage(String date);

  /// No description provided for @depositRateOwn.
  ///
  /// In tr, this message translates to:
  /// **'Bu oranı sen girdin; banka ya da vade değişince ortalama üstüne yazılmaz.'**
  String get depositRateOwn;

  /// No description provided for @depositRateParticipation.
  ///
  /// In tr, this message translates to:
  /// **'Katılım bankasında kâr payı önceden belli değil; bankanın bildirdiği oranı yaz.'**
  String get depositRateParticipation;

  /// No description provided for @depositNote.
  ///
  /// In tr, this message translates to:
  /// **'Not'**
  String get depositNote;

  /// No description provided for @depositNoteHint.
  ///
  /// In tr, this message translates to:
  /// **'Örn. kampanya faizi, hedef, şube'**
  String get depositNoteHint;

  /// No description provided for @sgnKilitBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyaller'**
  String get sgnKilitBaslik;

  /// No description provided for @sgnKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'RSI, MACD, Bollinger, EMA, Stokastik, ADX, Williams %R ve CCI: sekiz gösterge, tuttuğun her varlıkta seçtiğin sıklıkta bildirim ve varlık ekranında tam gösterge paneli.'**
  String get sgnKilitGovde;

  /// No description provided for @sgnKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyaller Premium\'da'**
  String get sgnKilitSatir;

  /// No description provided for @prmAylikKilitBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Aylık rapor'**
  String get prmAylikKilitBaslik;

  /// No description provided for @prmAylikKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'Tuttuğun her varlığın o ayki notu tek raporda: hangi varlıkta belirgin hareket oldu, ayın hikâyesi ve notların tamamı. Haftanın özeti ücretsiz kalır.'**
  String get prmAylikKilitGovde;

  /// No description provided for @prmAylikKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Aylık rapor Premium\'da'**
  String get prmAylikKilitSatir;

  /// No description provided for @costsBreakdownLocked.
  ///
  /// In tr, this message translates to:
  /// **'{count} kalemlik döküm Premium\'da'**
  String costsBreakdownLocked(int count);

  /// No description provided for @yrBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık rapor'**
  String get yrBaslik;

  /// No description provided for @yrSatirAlt.
  ///
  /// In tr, this message translates to:
  /// **'Kâr, temettü, stopaj ve masraf; PDF ya da Excel'**
  String get yrSatirAlt;

  /// No description provided for @yrKilitBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık kâr, temettü ve masraf raporu'**
  String get yrKilitBaslik;

  /// No description provided for @yrKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'Seçtiğin yılın satışlarından gerçekleşen kâr/zarar, temettülerin net ve brüt tutarı, stopaj ve komisyonlar tek raporda. Mali müşavirine PDF ya da Excel olarak gönderebilirsin.'**
  String get yrKilitGovde;

  /// No description provided for @yrKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık rapor Premium\'da'**
  String get yrKilitSatir;

  /// No description provided for @yrBos.
  ///
  /// In tr, this message translates to:
  /// **'Raporlanacak kayıt yok'**
  String get yrBos;

  /// No description provided for @yrBosAlt.
  ///
  /// In tr, this message translates to:
  /// **'Satış, temettü ya da komisyonlu alım girdiğinde o yılın raporu burada çıkar.'**
  String get yrBosAlt;

  /// No description provided for @yrGerceklesen.
  ///
  /// In tr, this message translates to:
  /// **'Gerçekleşen kâr/zarar'**
  String get yrGerceklesen;

  /// No description provided for @yrYurtDisi.
  ///
  /// In tr, this message translates to:
  /// **'Yurt dışı (ABD) hisse kısmı'**
  String get yrYurtDisi;

  /// No description provided for @yrYurtDisiEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Yurt dışı'**
  String get yrYurtDisiEtiket;

  /// No description provided for @yrTemettuNet.
  ///
  /// In tr, this message translates to:
  /// **'Temettü (net)'**
  String get yrTemettuNet;

  /// No description provided for @yrStopaj.
  ///
  /// In tr, this message translates to:
  /// **'Temettü stopajı'**
  String get yrStopaj;

  /// No description provided for @yrStopajBilinmiyor.
  ///
  /// In tr, this message translates to:
  /// **'oran bilinmiyor'**
  String get yrStopajBilinmiyor;

  /// No description provided for @yrStopajSatir.
  ///
  /// In tr, this message translates to:
  /// **'stopaj {tutar}'**
  String yrStopajSatir(String tutar);

  /// No description provided for @yrMasraf.
  ///
  /// In tr, this message translates to:
  /// **'İşlem masrafları'**
  String get yrMasraf;

  /// No description provided for @yrPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF'**
  String get yrPdf;

  /// No description provided for @yrExcel.
  ///
  /// In tr, this message translates to:
  /// **'Excel'**
  String get yrExcel;

  /// No description provided for @yrSatislarUpper.
  ///
  /// In tr, this message translates to:
  /// **'SATIŞLAR'**
  String get yrSatislarUpper;

  /// No description provided for @yrTemettulerUpper.
  ///
  /// In tr, this message translates to:
  /// **'TEMETTÜLER'**
  String get yrTemettulerUpper;

  /// No description provided for @yrFiyatsiz.
  ///
  /// In tr, this message translates to:
  /// **'Satış fiyatı kayıtlı olmayan {count} eski satış rapora alınmadı.'**
  String yrFiyatsiz(int count);

  /// No description provided for @yrDipnot.
  ///
  /// In tr, this message translates to:
  /// **'Kayıtlarından hazırlanır; vergi beyannamesi ya da vergi tavsiyesi değildir. Beyan için mali müşavirine danış. Ortağının işlemleri dahil değildir.'**
  String get yrDipnot;

  /// No description provided for @dsBicimBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Hangi biçimde?'**
  String get dsBicimBaslik;

  /// No description provided for @dsPdf.
  ///
  /// In tr, this message translates to:
  /// **'PDF'**
  String get dsPdf;

  /// No description provided for @dsPdfAlt.
  ///
  /// In tr, this message translates to:
  /// **'Okumak ve göndermek için'**
  String get dsPdfAlt;

  /// No description provided for @dsExcel.
  ///
  /// In tr, this message translates to:
  /// **'Excel'**
  String get dsExcel;

  /// No description provided for @dsExcelAlt.
  ///
  /// In tr, this message translates to:
  /// **'Tutarlar sayı olarak; toplanabilir, süzülebilir'**
  String get dsExcelAlt;

  /// No description provided for @dsPortfoyBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Portföyü dışa aktar'**
  String get dsPortfoyBaslik;

  /// No description provided for @dsPortfoyAlt.
  ///
  /// In tr, this message translates to:
  /// **'Varlıkların ve işlem geçmişin; PDF ya da Excel'**
  String get dsPortfoyAlt;

  /// No description provided for @ttBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Temettü tahmini'**
  String get ttBaslik;

  /// No description provided for @ttRaporAlt.
  ///
  /// In tr, this message translates to:
  /// **'Önümüzdeki 12 ayda beklenen temettü, ay ay'**
  String get ttRaporAlt;

  /// No description provided for @ttKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'BIST hisselerinin son 12 ayda dağıttığı temettü, bugünkü lotunla tekrarlansa önümüzdeki yıl ne kadar eder: ay ay çubuklar, varlık varlık liste, stopaj sonrası net.'**
  String get ttKilitGovde;

  /// No description provided for @ttKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Temettü tahmini Premium\'da'**
  String get ttKilitSatir;

  /// No description provided for @ttBos.
  ///
  /// In tr, this message translates to:
  /// **'Tahmin edilecek temettü yok'**
  String get ttBos;

  /// No description provided for @ttBosAlt.
  ///
  /// In tr, this message translates to:
  /// **'Son 12 ayda temettü dağıtmış bir BIST hissen olduğunda tahmin burada çıkar.'**
  String get ttBosAlt;

  /// No description provided for @ttToplamEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Önümüzdeki 12 ay, tahmini'**
  String get ttToplamEtiket;

  /// No description provided for @ttBrutNot.
  ///
  /// In tr, this message translates to:
  /// **'Brüt; stopaj oranı bilinmediği için net hesaplanmadı.'**
  String get ttBrutNot;

  /// No description provided for @ttNetNot.
  ///
  /// In tr, this message translates to:
  /// **'Stopaj sonrası net · brüt {brut}'**
  String ttNetNot(String brut);

  /// No description provided for @ttVarliklarUpper.
  ///
  /// In tr, this message translates to:
  /// **'VARLIKLAR'**
  String get ttVarliklarUpper;

  /// No description provided for @ttSatirAlt.
  ///
  /// In tr, this message translates to:
  /// **'pay başına {pay} · {aylar}'**
  String ttSatirAlt(String pay, String aylar);

  /// No description provided for @ttKural.
  ///
  /// In tr, this message translates to:
  /// **'Tahmin tek bir kurala dayanır: son 12 ayda gerçekleşen temettü, bugünkü lotunla aynı aylarda tekrarlansa. Şirket kararları, bölünme ve bedelsiz hesaba katılmaz. Yalnız BIST hisseleri; yatırım tavsiyesi değildir.'**
  String get ttKural;

  /// No description provided for @pwOzRapor.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık kâr, temettü ve stopaj raporu; portföyünü PDF ya da Excel olarak dışa aktar'**
  String get pwOzRapor;

  /// No description provided for @pwOzTemettu.
  ///
  /// In tr, this message translates to:
  /// **'Önümüzdeki 12 ayın temettü tahmini, ay ay'**
  String get pwOzTemettu;

  /// No description provided for @pwOzSinyalTam.
  ///
  /// In tr, this message translates to:
  /// **'Teknik sinyaller: 8 gösterge, her varlığında seçtiğin sıklıkta bildirim'**
  String get pwOzSinyalTam;

  /// No description provided for @pwOzMasraf.
  ///
  /// In tr, this message translates to:
  /// **'Varlık başına kalem kalem masraf dökümü'**
  String get pwOzMasraf;

  /// No description provided for @prmSatirAlarm.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat alarmı'**
  String get prmSatirAlarm;

  /// No description provided for @prmSatirYillik.
  ///
  /// In tr, this message translates to:
  /// **'Yıllık rapor'**
  String get prmSatirYillik;

  /// No description provided for @prmSatirDisaAktar.
  ///
  /// In tr, this message translates to:
  /// **'Dışa aktarma'**
  String get prmSatirDisaAktar;

  /// No description provided for @prmDisaAktarUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'JSON'**
  String get prmDisaAktarUcretsiz;

  /// No description provided for @prmDisaAktarPremium.
  ///
  /// In tr, this message translates to:
  /// **'PDF + Excel'**
  String get prmDisaAktarPremium;

  /// No description provided for @prmSatirTemettu.
  ///
  /// In tr, this message translates to:
  /// **'Temettü tahmini'**
  String get prmSatirTemettu;

  /// No description provided for @prmSatirMasraf.
  ///
  /// In tr, this message translates to:
  /// **'Masraflar'**
  String get prmSatirMasraf;

  /// No description provided for @prmMasrafUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'toplam'**
  String get prmMasrafUcretsiz;

  /// No description provided for @prmMasrafPremium.
  ///
  /// In tr, this message translates to:
  /// **'kalem kalem'**
  String get prmMasrafPremium;

  /// No description provided for @prmSatirKars.
  ///
  /// In tr, this message translates to:
  /// **'Karşılaştır'**
  String get prmSatirKars;

  /// No description provided for @prmSatirOrtak.
  ///
  /// In tr, this message translates to:
  /// **'Ortak'**
  String get prmSatirOrtak;

  /// No description provided for @pwdRaporEtiket.
  ///
  /// In tr, this message translates to:
  /// **'YILLIK RAPOR'**
  String get pwdRaporEtiket;

  /// No description provided for @pwdRaporBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Yılın kârı, temettüsü ve stopajı tek belgede; müşavirine gönder.'**
  String get pwdRaporBaslik;

  /// No description provided for @pwdRaporPremium.
  ///
  /// In tr, this message translates to:
  /// **'PDF ve Excel'**
  String get pwdRaporPremium;

  /// No description provided for @pwdTemettuEtiket.
  ///
  /// In tr, this message translates to:
  /// **'TEMETTÜ TAHMİNİ'**
  String get pwdTemettuEtiket;

  /// No description provided for @pwdTemettuBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Önümüzdeki 12 ayda ne kadar temettü gelir, ay ay gör.'**
  String get pwdTemettuBaslik;

  /// No description provided for @pwdTemettuPremium.
  ///
  /// In tr, this message translates to:
  /// **'12 aylık tahmin'**
  String get pwdTemettuPremium;

  /// No description provided for @pwdSinyalRozet.
  ///
  /// In tr, this message translates to:
  /// **'8 gösterge'**
  String get pwdSinyalRozet;

  /// No description provided for @xrKartBaslikUpper.
  ///
  /// In tr, this message translates to:
  /// **'FONUN İÇİNDE NE VAR'**
  String get xrKartBaslikUpper;

  /// No description provided for @xrSatirFonunIci.
  ///
  /// In tr, this message translates to:
  /// **'Fonun içi'**
  String get xrSatirFonunIci;

  /// No description provided for @xrKaynakTefas.
  ///
  /// In tr, this message translates to:
  /// **'TEFAS · {tarih}'**
  String xrKaynakTefas(String tarih);

  /// No description provided for @xrToplamSapiyor.
  ///
  /// In tr, this message translates to:
  /// **'Kaynaktaki sınıfların toplamı {toplam}; fark hiçbir sınıfa eklenmedi.'**
  String xrToplamSapiyor(String toplam);

  /// No description provided for @xrKilitBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Fon X-Ray'**
  String get xrKilitBaslik;

  /// No description provided for @xrKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'Fonun parası nerede duruyor: hisse, devlet tahvili, mevduat, altın, döviz… TEFAS\'ın günlük dağılımından, tarih ve kaynakla.'**
  String get xrKilitGovde;

  /// No description provided for @xrKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Fonun içinde ne var Premium\'da'**
  String get xrKilitSatir;

  /// No description provided for @xrKalemlerBaslik.
  ///
  /// In tr, this message translates to:
  /// **'En büyük {n} kalem'**
  String xrKalemlerBaslik(int n);

  /// No description provided for @xrKaynakKap.
  ///
  /// In tr, this message translates to:
  /// **'KAP Portföy Dağılım Raporu · {donem} sonu'**
  String xrKaynakKap(String donem);

  /// No description provided for @xrKapAc.
  ///
  /// In tr, this message translates to:
  /// **'Raporu KAP\'ta aç'**
  String get xrKapAc;

  /// No description provided for @xrKovaBistHisse.
  ///
  /// In tr, this message translates to:
  /// **'BIST hisse'**
  String get xrKovaBistHisse;

  /// No description provided for @xrKovaYabanciHisse.
  ///
  /// In tr, this message translates to:
  /// **'Yabancı hisse'**
  String get xrKovaYabanciHisse;

  /// No description provided for @xrKovaDevlet.
  ///
  /// In tr, this message translates to:
  /// **'Devlet borçlanması (TL)'**
  String get xrKovaDevlet;

  /// No description provided for @xrKovaOzel.
  ///
  /// In tr, this message translates to:
  /// **'Özel sektör borçlanması'**
  String get xrKovaOzel;

  /// No description provided for @xrKovaDovizBorc.
  ///
  /// In tr, this message translates to:
  /// **'Döviz / dış borçlanma'**
  String get xrKovaDovizBorc;

  /// No description provided for @xrKovaParaPiyasasi.
  ///
  /// In tr, this message translates to:
  /// **'Para piyasası / repo'**
  String get xrKovaParaPiyasasi;

  /// No description provided for @xrKovaMevduat.
  ///
  /// In tr, this message translates to:
  /// **'Mevduat / katılma hesabı'**
  String get xrKovaMevduat;

  /// No description provided for @xrKovaMaden.
  ///
  /// In tr, this message translates to:
  /// **'Kıymetli maden'**
  String get xrKovaMaden;

  /// No description provided for @xrKovaFon.
  ///
  /// In tr, this message translates to:
  /// **'Fon / BYF payı'**
  String get xrKovaFon;

  /// No description provided for @xrKovaGayrimenkul.
  ///
  /// In tr, this message translates to:
  /// **'Gayrimenkul / girişim'**
  String get xrKovaGayrimenkul;

  /// No description provided for @xrKovaDiger.
  ///
  /// In tr, this message translates to:
  /// **'Diğer'**
  String get xrKovaDiger;

  /// No description provided for @xrKovaEtiketsiz.
  ///
  /// In tr, this message translates to:
  /// **'Etiketsiz sınıf'**
  String get xrKovaEtiketsiz;

  /// No description provided for @xrKovaDoviz.
  ///
  /// In tr, this message translates to:
  /// **'Döviz'**
  String get xrKovaDoviz;

  /// No description provided for @xrKovaKripto.
  ///
  /// In tr, this message translates to:
  /// **'Kripto'**
  String get xrKovaKripto;

  /// No description provided for @xrKovaEmtia.
  ///
  /// In tr, this message translates to:
  /// **'Emtia'**
  String get xrKovaEmtia;

  /// No description provided for @xrEkranBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Portföy X-Ray'**
  String get xrEkranBaslik;

  /// No description provided for @xrRaporAlt.
  ///
  /// In tr, this message translates to:
  /// **'Fonlarının içi dahil, paran gerçekte nerede'**
  String get xrRaporAlt;

  /// No description provided for @xrToplamEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Bugünkü portföyün'**
  String get xrToplamEtiket;

  /// No description provided for @xrDagilimUpper.
  ///
  /// In tr, this message translates to:
  /// **'GERÇEK DAĞILIM'**
  String get xrDagilimUpper;

  /// No description provided for @xrDisi.
  ///
  /// In tr, this message translates to:
  /// **'X-Ray dışı'**
  String get xrDisi;

  /// No description provided for @xrDisiAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Dağılımı bulunamayan fonlar ve kaynak toplamının %100\'ü tutmadığı fonlardaki fark. Başka sınıflara dağıtılmadı.'**
  String get xrDisiAciklama;

  /// No description provided for @xrDisiFonlar.
  ///
  /// In tr, this message translates to:
  /// **'Dağılımı bulunamayan: {fonlar}'**
  String xrDisiFonlar(String fonlar);

  /// No description provided for @xrKaynakFonlar.
  ///
  /// In tr, this message translates to:
  /// **'Fonlar: TEFAS günlük dağılımı · {tarih}'**
  String xrKaynakFonlar(String tarih);

  /// No description provided for @xrKaynakDogrudan.
  ///
  /// In tr, this message translates to:
  /// **'Doğrudan tuttukların bugünkü fiyatla; ortaklarının varlıkları dahil değil.'**
  String get xrKaynakDogrudan;

  /// No description provided for @xrBos.
  ///
  /// In tr, this message translates to:
  /// **'X-Ray\'lenecek bir varlığın yok'**
  String get xrBos;

  /// No description provided for @xrBosAlt.
  ///
  /// In tr, this message translates to:
  /// **'Varlık ekleyince fonlarının içi dahil gerçek dağılımın burada görünür.'**
  String get xrBosAlt;

  /// No description provided for @xrEkranKilitGovde.
  ///
  /// In tr, this message translates to:
  /// **'Fonlarının içindeki hisse, tahvil, mevduat ve altın, doğrudan tuttuklarınla birlikte: paran gerçekte nerede. TEFAS\'ın günlük dağılımından, tarih ve kaynakla.'**
  String get xrEkranKilitGovde;

  /// No description provided for @xrEkranKilitSatir.
  ///
  /// In tr, this message translates to:
  /// **'Portföy X-Ray Premium\'da'**
  String get xrEkranKilitSatir;

  /// No description provided for @xrOrtusmeUpper.
  ///
  /// In tr, this message translates to:
  /// **'BİRDEN ÇOK YERDEN TUTTUKLARIN'**
  String get xrOrtusmeUpper;

  /// No description provided for @xrOrtusmeAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Aynı hisseyi birden çok fonunda (ya da hem fonunda hem doğrudan) tutuyorsan toplam payın.'**
  String get xrOrtusmeAciklama;

  /// No description provided for @xrOrtusmeKaynak.
  ///
  /// In tr, this message translates to:
  /// **'{n} yerden'**
  String xrOrtusmeKaynak(int n);

  /// No description provided for @xrDogrudan.
  ///
  /// In tr, this message translates to:
  /// **'doğrudan'**
  String get xrDogrudan;

  /// No description provided for @xrKaynakKalemler.
  ///
  /// In tr, this message translates to:
  /// **'Kalemler: KAP Portföy Dağılım Raporları · {donem} sonu'**
  String xrKaynakKalemler(String donem);

  /// No description provided for @pwOzXray.
  ///
  /// In tr, this message translates to:
  /// **'Fon X-Ray: fonlarının içi ve portföyünün gerçek dağılımı'**
  String get pwOzXray;

  /// No description provided for @prmSatirXray.
  ///
  /// In tr, this message translates to:
  /// **'Fon X-Ray'**
  String get prmSatirXray;

  /// No description provided for @pwdXrayEtiket.
  ///
  /// In tr, this message translates to:
  /// **'FON X-RAY'**
  String get pwdXrayEtiket;

  /// No description provided for @pwdXrayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Fonlarının içinde ne var, paran gerçekte nerede gör.'**
  String get pwdXrayBaslik;

  /// No description provided for @pwdXrayPremium.
  ///
  /// In tr, this message translates to:
  /// **'Fon ve portföy X-Ray'**
  String get pwdXrayPremium;

  /// No description provided for @portfoyTumu.
  ///
  /// In tr, this message translates to:
  /// **'Tümü'**
  String get portfoyTumu;

  /// No description provided for @portfoyAna.
  ///
  /// In tr, this message translates to:
  /// **'Ana'**
  String get portfoyAna;

  /// No description provided for @portfoyAnaUzun.
  ///
  /// In tr, this message translates to:
  /// **'Ana portföy'**
  String get portfoyAnaUzun;

  /// No description provided for @portfoyYeni.
  ///
  /// In tr, this message translates to:
  /// **'Yeni portföy'**
  String get portfoyYeni;

  /// No description provided for @portfoyYonet.
  ///
  /// In tr, this message translates to:
  /// **'Portföyleri yönet'**
  String get portfoyYonet;

  /// No description provided for @portfoySeciciEtiketi.
  ///
  /// In tr, this message translates to:
  /// **'Portföy'**
  String get portfoySeciciEtiketi;

  /// No description provided for @portfoyAdi.
  ///
  /// In tr, this message translates to:
  /// **'Portföy adı'**
  String get portfoyAdi;

  /// No description provided for @portfoyAdiIpucu.
  ///
  /// In tr, this message translates to:
  /// **'ör. Emeklilik, Çocuğum için'**
  String get portfoyAdiIpucu;

  /// No description provided for @portfoyAdiGecersiz.
  ///
  /// In tr, this message translates to:
  /// **'Ad 1 ile 40 karakter arasında olmalı.'**
  String get portfoyAdiGecersiz;

  /// No description provided for @portfoyAdiKullaniliyor.
  ///
  /// In tr, this message translates to:
  /// **'Bu adda bir portföyün zaten var.'**
  String get portfoyAdiKullaniliyor;

  /// No description provided for @portfoyOlustur.
  ///
  /// In tr, this message translates to:
  /// **'Oluştur'**
  String get portfoyOlustur;

  /// No description provided for @portfoyYenidenAdlandir.
  ///
  /// In tr, this message translates to:
  /// **'Yeniden adlandır'**
  String get portfoyYenidenAdlandir;

  /// No description provided for @portfoySil.
  ///
  /// In tr, this message translates to:
  /// **'Portföyü sil'**
  String get portfoySil;

  /// No description provided for @portfoySilBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{ad} silinsin mi?'**
  String portfoySilBaslik(String ad);

  /// No description provided for @portfoySilAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Varlıkların silinmez. Bu portföydeki {sayi} kayıt Ana portföye döner; toplamın değişmez.'**
  String portfoySilAciklama(int sayi);

  /// No description provided for @portfoySilindi.
  ///
  /// In tr, this message translates to:
  /// **'{ad} silindi, varlıkları Ana portföyde.'**
  String portfoySilindi(String ad);

  /// No description provided for @portfoySilinemedi.
  ///
  /// In tr, this message translates to:
  /// **'Portföy silinemedi'**
  String get portfoySilinemedi;

  /// No description provided for @portfoyKaydedilemedi.
  ///
  /// In tr, this message translates to:
  /// **'Portföy kaydedilemedi'**
  String get portfoyKaydedilemedi;

  /// No description provided for @portfoyYonetimiBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Portföyler'**
  String get portfoyYonetimiBaslik;

  /// No description provided for @portfoyYonetimiAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Varlıklarını amacına göre ayır: emeklilik, çocuğun için, deneme. Tümü görünümü ve ana sayfa toplamı değişmez; widget ve kilit ekranı da toplamı gösterir.'**
  String get portfoyYonetimiAciklama;

  /// No description provided for @portfoyAnaAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Portföy seçmeden eklediklerin burada.'**
  String get portfoyAnaAciklama;

  /// No description provided for @portfoySiralaIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Sırayı değiştirmek için basılı tutup sürükle.'**
  String get portfoySiralaIpucu;

  /// No description provided for @portfoyIslemSec.
  ///
  /// In tr, this message translates to:
  /// **'Hangi portföydeki pozisyon?'**
  String get portfoyIslemSec;

  /// No description provided for @portfoyIslemSecAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Bu varlık birden çok portföyde. İşlem seçtiğin portföyün pozisyonuna, onun maliyetiyle yazılır.'**
  String get portfoyIslemSecAciklama;

  /// No description provided for @portfoyTasi.
  ///
  /// In tr, this message translates to:
  /// **'Taşı'**
  String get portfoyTasi;

  /// No description provided for @portfoyTasiBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Hangi portföye taşınsın?'**
  String get portfoyTasiBaslik;

  /// No description provided for @portfoyTasiAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Geçmişiyle birlikte taşınır: alımlar, satışlar ve temettüler. Toplamın değişmez.'**
  String get portfoyTasiAciklama;

  /// No description provided for @portfoyTasindi.
  ///
  /// In tr, this message translates to:
  /// **'{ad} portföyüne taşındı.'**
  String portfoyTasindi(String ad);

  /// No description provided for @portfoyTasinamadi.
  ///
  /// In tr, this message translates to:
  /// **'Taşınamadı'**
  String get portfoyTasinamadi;

  /// No description provided for @portfoyKaynakSec.
  ///
  /// In tr, this message translates to:
  /// **'Hangi portföydeki pozisyon taşınsın?'**
  String get portfoyKaynakSec;

  /// No description provided for @pwOzPortfoy.
  ///
  /// In tr, this message translates to:
  /// **'Sınırsız portföy: emeklilik, çocuğun için, deneme ayrı ayrı; aralarında kısmi aktarım ve ortağın hangisini göreceğini seçme'**
  String get pwOzPortfoy;

  /// No description provided for @prmSatirPortfoy.
  ///
  /// In tr, this message translates to:
  /// **'Portföy'**
  String get prmSatirPortfoy;

  /// No description provided for @pwdGrafikEtiket.
  ///
  /// In tr, this message translates to:
  /// **'GRAFİK'**
  String get pwdGrafikEtiket;

  /// No description provided for @pwdGrafikBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Mum grafik, EMA50 ve EMA200; trendi tek bakışta gör.'**
  String get pwdGrafikBaslik;

  /// No description provided for @pwdGrafikPremium.
  ///
  /// In tr, this message translates to:
  /// **'mum, EMA50, EMA200'**
  String get pwdGrafikPremium;

  /// No description provided for @pwdPortfoyPremium.
  ///
  /// In tr, this message translates to:
  /// **'sınırsız, kısmi aktarım'**
  String get pwdPortfoyPremium;

  /// No description provided for @pwOzGrafik.
  ///
  /// In tr, this message translates to:
  /// **'Grafikte mum görünümü, EMA50 ve EMA200 çizgileri'**
  String get pwOzGrafik;

  /// No description provided for @pwOzEkstre.
  ///
  /// In tr, this message translates to:
  /// **'Banka ve aracı kurum ekstreni yapay zekâyla eşleme'**
  String get pwOzEkstre;

  /// No description provided for @prmSatirGrafik.
  ///
  /// In tr, this message translates to:
  /// **'Mum · EMA50 · EMA200'**
  String get prmSatirGrafik;

  /// No description provided for @pwdHesapEtiket.
  ///
  /// In tr, this message translates to:
  /// **'HESAPLAR'**
  String get pwdHesapEtiket;

  /// No description provided for @pwdHesapBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Kendi hesabın, şirketin, ailen; tek dokunuşla geç.'**
  String get pwdHesapBaslik;

  /// No description provided for @pwdHesapUcretsiz.
  ///
  /// In tr, this message translates to:
  /// **'1 hesap'**
  String get pwdHesapUcretsiz;

  /// No description provided for @pwdHesapPremium.
  ///
  /// In tr, this message translates to:
  /// **'ek hesap ve geçiş'**
  String get pwdHesapPremium;

  /// No description provided for @pwOzHesap.
  ///
  /// In tr, this message translates to:
  /// **'Aynı telefonda birden çok hesap, aralarında tek dokunuşla geçiş'**
  String get pwOzHesap;

  /// No description provided for @prmSatirHesap.
  ///
  /// In tr, this message translates to:
  /// **'Hesap'**
  String get prmSatirHesap;

  /// No description provided for @pwdPortfoyEtiket.
  ///
  /// In tr, this message translates to:
  /// **'PORTFÖY'**
  String get pwdPortfoyEtiket;

  /// No description provided for @pwdPortfoyBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Her amaca ayrı portföy; toplamın hep yerinde.'**
  String get pwdPortfoyBaslik;

  /// No description provided for @pwdPortfoySayi.
  ///
  /// In tr, this message translates to:
  /// **'{sayi} portföy'**
  String pwdPortfoySayi(int sayi);

  /// No description provided for @ortakGorurBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{ad} neyi görsün?'**
  String ortakGorurBaslik(String ad);

  /// No description provided for @ortakGorurAciklama.
  ///
  /// In tr, this message translates to:
  /// **'{ad} seçtiklerini tek liste olarak görür, portföy adlarını görmez. Seçmediklerin onun telefonuna hiç gitmez.'**
  String ortakGorurAciklama(String ad);

  /// No description provided for @ortakGorurHepsi.
  ///
  /// In tr, this message translates to:
  /// **'Hepsi'**
  String get ortakGorurHepsi;

  /// No description provided for @ortakGorurSecilenler.
  ///
  /// In tr, this message translates to:
  /// **'Seçtiklerim'**
  String get ortakGorurSecilenler;

  /// No description provided for @ortakGorurHepsiAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Bütün portföylerin, sonradan açacakların dahil.'**
  String get ortakGorurHepsiAciklama;

  /// No description provided for @ortakGorurSeciliAciklama.
  ///
  /// In tr, this message translates to:
  /// **'Yeni açtığın portföy, sen seçene kadar gizli kalır.'**
  String get ortakGorurSeciliAciklama;

  /// No description provided for @ortakGorurHicbiri.
  ///
  /// In tr, this message translates to:
  /// **'Hiçbirini seçmezsen {ad} varlıklarını göremez; ortaklık sürer.'**
  String ortakGorurHicbiri(String ad);

  /// No description provided for @ortakGorurKaydedilemedi.
  ///
  /// In tr, this message translates to:
  /// **'Seçim kaydedilemedi'**
  String get ortakGorurKaydedilemedi;

  /// No description provided for @ortakGorurSatir.
  ///
  /// In tr, this message translates to:
  /// **'Görebildiği portföyler'**
  String get ortakGorurSatir;

  /// No description provided for @ortakGorurSayi.
  ///
  /// In tr, this message translates to:
  /// **'{n} / {toplam} portföy'**
  String ortakGorurSayi(int n, int toplam);

  /// No description provided for @portfoyOrtakGoruyor.
  ///
  /// In tr, this message translates to:
  /// **'{ad} görüyor'**
  String portfoyOrtakGoruyor(String ad);

  /// No description provided for @portfoyOrtakGizli.
  ///
  /// In tr, this message translates to:
  /// **'{ad} görmüyor'**
  String portfoyOrtakGizli(String ad);

  /// No description provided for @portfoyOrtakBolum.
  ///
  /// In tr, this message translates to:
  /// **'ORTAĞIN NE GÖRÜR'**
  String get portfoyOrtakBolum;

  /// No description provided for @portfoyAktarBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Ne kadarı aktarılsın?'**
  String get portfoyAktarBaslik;

  /// No description provided for @portfoyAktarAciklama.
  ///
  /// In tr, this message translates to:
  /// **'{hedef} portföyüne. Bu portföyde {miktar} var.'**
  String portfoyAktarAciklama(String hedef, String miktar);

  /// No description provided for @portfoyAktarTamami.
  ///
  /// In tr, this message translates to:
  /// **'Tamamı'**
  String get portfoyAktarTamami;

  /// No description provided for @portfoyAktarBirKismi.
  ///
  /// In tr, this message translates to:
  /// **'Bir kısmı'**
  String get portfoyAktarBirKismi;

  /// No description provided for @portfoyAktarMiktar.
  ///
  /// In tr, this message translates to:
  /// **'Aktarılacak miktar'**
  String get portfoyAktarMiktar;

  /// No description provided for @portfoyAktarNot.
  ///
  /// In tr, this message translates to:
  /// **'Alımlar, satışlar ve temettüler aynı oranla bölünür. Ortalama maliyet ve getiri iki portföyde de aynı kalır, toplamın değişmez.'**
  String get portfoyAktarNot;

  /// No description provided for @portfoyAktarGecersiz.
  ///
  /// In tr, this message translates to:
  /// **'0 ile {miktar} arasında bir miktar yaz.'**
  String portfoyAktarGecersiz(String miktar);

  /// No description provided for @portfoyAktarDugme.
  ///
  /// In tr, this message translates to:
  /// **'Aktar'**
  String get portfoyAktarDugme;

  /// No description provided for @portfoyAktarPremium.
  ///
  /// In tr, this message translates to:
  /// **'Bir kısmını aktarmak Premium\'a özel.'**
  String get portfoyAktarPremium;

  /// No description provided for @portfoyAktarildi.
  ///
  /// In tr, this message translates to:
  /// **'{miktar}, {hedef} portföyüne aktarıldı.'**
  String portfoyAktarildi(String miktar, String hedef);

  /// No description provided for @ortakGorurOnizleme.
  ///
  /// In tr, this message translates to:
  /// **'{ad} görecek'**
  String ortakGorurOnizleme(String ad);

  /// No description provided for @ortakGorurHicbiriKisa.
  ///
  /// In tr, this message translates to:
  /// **'Hiçbiri'**
  String get ortakGorurHicbiriKisa;

  /// No description provided for @compareRemoveSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} karşılaştırmasını kaldır'**
  String compareRemoveSemantics(String name);

  /// No description provided for @chartPriceSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Fiyat grafiği'**
  String get chartPriceSemantics;

  /// No description provided for @chartPortfolioSemantics.
  ///
  /// In tr, this message translates to:
  /// **'Portföy değeri grafiği'**
  String get chartPortfolioSemantics;

  /// No description provided for @chartAssetSemantics.
  ///
  /// In tr, this message translates to:
  /// **'{name} fiyat grafiği'**
  String chartAssetSemantics(String name);

  /// No description provided for @cihazHesapAcikKalir.
  ///
  /// In tr, this message translates to:
  /// **'{ad} açık kalır. Yeni hesaba giriş yap ya da kayıt ol; sonra Profil\'den hesaplar arasında geçebilirsin.'**
  String cihazHesapAcikKalir(String ad);

  /// No description provided for @cihazHesaplari.
  ///
  /// In tr, this message translates to:
  /// **'Bu cihazdaki hesaplar'**
  String get cihazHesaplari;

  /// No description provided for @cihazHesapGeriDon.
  ///
  /// In tr, this message translates to:
  /// **'Geri dön'**
  String get cihazHesapGeriDon;

  /// No description provided for @cihazHesapDevamEt.
  ///
  /// In tr, this message translates to:
  /// **'Devam et'**
  String get cihazHesapDevamEt;

  /// No description provided for @cihazHesapTekrarGiris.
  ///
  /// In tr, this message translates to:
  /// **'Tekrar giriş gerekli · {eposta}'**
  String cihazHesapTekrarGiris(String eposta);

  /// No description provided for @cihazHesapBaskaHesapla.
  ///
  /// In tr, this message translates to:
  /// **'ya da başka bir hesapla giriş yap'**
  String get cihazHesapBaskaHesapla;

  /// No description provided for @ozgCipSemantik.
  ///
  /// In tr, this message translates to:
  /// **'Kendi göstergelerin'**
  String get ozgCipSemantik;

  /// No description provided for @ozgBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Göstergelerim'**
  String get ozgBaslik;

  /// No description provided for @ozgAciklama.
  ///
  /// In tr, this message translates to:
  /// **'TradingView\'deki Pine Script kodunu olduğu gibi yapıştır ya da kendin yaz. Grafikte seçili aralığın çubuklarında çalışır.'**
  String get ozgAciklama;

  /// No description provided for @ozgBos.
  ///
  /// In tr, this message translates to:
  /// **'Henüz gösterge yazmadın. Bir şablonla başlayabilirsin.'**
  String get ozgBos;

  /// No description provided for @ozgYeni.
  ///
  /// In tr, this message translates to:
  /// **'Yeni gösterge'**
  String get ozgYeni;

  /// No description provided for @ozgSablondan.
  ///
  /// In tr, this message translates to:
  /// **'Şablondan başla'**
  String get ozgSablondan;

  /// No description provided for @ozgFiyatUstunde.
  ///
  /// In tr, this message translates to:
  /// **'Fiyatın üstünde'**
  String get ozgFiyatUstunde;

  /// No description provided for @ozgAyriPanel.
  ///
  /// In tr, this message translates to:
  /// **'Ayrı panel'**
  String get ozgAyriPanel;

  /// No description provided for @ozgHatali.
  ///
  /// In tr, this message translates to:
  /// **'Hatalı, düzenle'**
  String get ozgHatali;

  /// No description provided for @ozgEditorYeni.
  ///
  /// In tr, this message translates to:
  /// **'Gösterge yaz'**
  String get ozgEditorYeni;

  /// No description provided for @ozgEditorDuzenle.
  ///
  /// In tr, this message translates to:
  /// **'Göstergeyi düzenle'**
  String get ozgEditorDuzenle;

  /// No description provided for @ozgAdEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Adı'**
  String get ozgAdEtiket;

  /// No description provided for @ozgAdIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Ör. Hızlı EMA kesişimi'**
  String get ozgAdIpucu;

  /// No description provided for @ozgKodEtiket.
  ///
  /// In tr, this message translates to:
  /// **'Pine Script kodu'**
  String get ozgKodEtiket;

  /// No description provided for @ozgGecerli.
  ///
  /// In tr, this message translates to:
  /// **'Geçerli · {sayi} çizgi · {yer}'**
  String ozgGecerli(int sayi, String yer);

  /// No description provided for @ozgHataSatir.
  ///
  /// In tr, this message translates to:
  /// **'Satır {satir}: {mesaj}'**
  String ozgHataSatir(int satir, String mesaj);

  /// No description provided for @ozgEksikVeri.
  ///
  /// In tr, this message translates to:
  /// **'Bu grafikte henüz yüksek, düşük ve hacim verisi yok. Bunları kullanan çizgiler boş kalır.'**
  String get ozgEksikVeri;

  /// No description provided for @ozgOnizleme.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme · {varlik} · son {sayi} çubuk'**
  String ozgOnizleme(String varlik, int sayi);

  /// No description provided for @ozgOnizlemeYok.
  ///
  /// In tr, this message translates to:
  /// **'Önizleme için bir varlığın grafiğinden aç.'**
  String get ozgOnizlemeYok;

  /// No description provided for @ozgFonksiyonlar.
  ///
  /// In tr, this message translates to:
  /// **'Fonksiyonlar'**
  String get ozgFonksiyonlar;

  /// No description provided for @ozgGuvenlik.
  ///
  /// In tr, this message translates to:
  /// **'Kod yalnız telefonunda, kapalı bir yorumlayıcıda çalışır. İnternete, dosyalara ya da hesabına erişemez.'**
  String get ozgGuvenlik;

  /// No description provided for @ozgKaydet.
  ///
  /// In tr, this message translates to:
  /// **'Kaydet'**
  String get ozgKaydet;

  /// No description provided for @ozgSil.
  ///
  /// In tr, this message translates to:
  /// **'Göstergeyi sil'**
  String get ozgSil;

  /// No description provided for @ozgSilBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Gösterge silinsin mi?'**
  String get ozgSilBaslik;

  /// No description provided for @ozgSilMesaj.
  ///
  /// In tr, this message translates to:
  /// **'{ad} kalıcı olarak silinir.'**
  String ozgSilMesaj(String ad);

  /// No description provided for @ozgSilOnay.
  ///
  /// In tr, this message translates to:
  /// **'Sil'**
  String get ozgSilOnay;

  /// No description provided for @ozgVazgecBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Değişiklikler kaydedilmedi'**
  String get ozgVazgecBaslik;

  /// No description provided for @ozgVazgecMesaj.
  ///
  /// In tr, this message translates to:
  /// **'Çıkarsan yazdıkların kaybolur.'**
  String get ozgVazgecMesaj;

  /// No description provided for @ozgVazgecOnay.
  ///
  /// In tr, this message translates to:
  /// **'Çık'**
  String get ozgVazgecOnay;

  /// No description provided for @ozgVazgecIptal.
  ///
  /// In tr, this message translates to:
  /// **'Düzenlemeye dön'**
  String get ozgVazgecIptal;

  /// No description provided for @ozgSinir.
  ///
  /// In tr, this message translates to:
  /// **'En fazla {sayi} gösterge kaydedebilirsin.'**
  String ozgSinir(int sayi);

  /// No description provided for @ozgAdGerekli.
  ///
  /// In tr, this message translates to:
  /// **'Bir ad yaz (en fazla 40 karakter).'**
  String get ozgAdGerekli;

  /// No description provided for @ozgGrafikteGoster.
  ///
  /// In tr, this message translates to:
  /// **'{ad}, grafikte göster'**
  String ozgGrafikteGoster(String ad);

  /// No description provided for @ozgPanelSemantik.
  ///
  /// In tr, this message translates to:
  /// **'{ad} göstergesi, ayrı panel'**
  String ozgPanelSemantik(String ad);

  /// No description provided for @ozgKaydedildi.
  ///
  /// In tr, this message translates to:
  /// **'Gösterge kaydedildi'**
  String get ozgKaydedildi;

  /// No description provided for @ozgNotCizimNesnesi.
  ///
  /// In tr, this message translates to:
  /// **'label, line, box ve table çizimleri gösterilmez; kodun geri kalanı çalışır.'**
  String get ozgNotCizimNesnesi;

  /// No description provided for @ozgNotBoyama.
  ///
  /// In tr, this message translates to:
  /// **'bgcolor ve barcolor boyamaları gösterilmez.'**
  String get ozgNotBoyama;

  /// No description provided for @ozgNotStrateji.
  ///
  /// In tr, this message translates to:
  /// **'Strateji emirleri (strategy.entry …) yürütülmez; yalnız çizimler gösterilir.'**
  String get ozgNotStrateji;

  /// No description provided for @ozgNotFazlaCizgi.
  ///
  /// In tr, this message translates to:
  /// **'İlk {sayi} çizgi gösterilir.'**
  String ozgNotFazlaCizgi(int sayi);

  /// No description provided for @ozgNotPaneldeIsaret.
  ///
  /// In tr, this message translates to:
  /// **'Ayrı paneldeki işaretler (plotshape) gösterilmez.'**
  String get ozgNotPaneldeIsaret;

  /// No description provided for @pwOzOzelGosterge.
  ///
  /// In tr, this message translates to:
  /// **'Kendi göstergeni yaz: formülün, seçtiğin zaman aralığında'**
  String get pwOzOzelGosterge;

  /// No description provided for @varlikGuncelleBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Varlığı güncelle'**
  String get varlikGuncelleBaslik;

  /// No description provided for @varlikGuncelleIpucu.
  ///
  /// In tr, this message translates to:
  /// **'Varlığı güncelle'**
  String get varlikGuncelleIpucu;

  /// No description provided for @varlikGuncelleKilitli.
  ///
  /// In tr, this message translates to:
  /// **'Varlığı güncelle, Premium'**
  String get varlikGuncelleKilitli;

  /// No description provided for @varlikGuncelleUyariBaslik.
  ///
  /// In tr, this message translates to:
  /// **'Tek kayıt olarak yeniden yazılır'**
  String get varlikGuncelleUyariBaslik;

  /// No description provided for @varlikGuncelleUyariGovde.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{Bu varlığın kaydı silinir ve buradaki bilgilerle yeniden eklenir. Varlığı silip yeniden eklemekle aynıdır.} other{Bu varlığın {n} hareketi (alış, satış, temettü) silinir, yerine buradaki bilgilerle tek bir kayıt kalır. Adım adım geçmiş artık bu varlıkta görünmez. Varlığı silip yeniden eklemekle aynıdır.}}'**
  String varlikGuncelleUyariGovde(int n);

  /// No description provided for @varlikGuncelleOnayBaslik.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{Kayıt yeniden yazılsın mı?} other{{n} hareket silinsin mi?}}'**
  String varlikGuncelleOnayBaslik(int n);

  /// No description provided for @varlikGuncelleOnayGovde.
  ///
  /// In tr, this message translates to:
  /// **'{n, plural, =1{\"{name}\" silinip bu bilgilerle yeniden eklenecek. Bu işlem geri alınamaz.} other{\"{name}\" için {n} hareket silinecek, yerine bu bilgilerle tek bir kayıt eklenecek. Bu işlem geri alınamaz.}}'**
  String varlikGuncelleOnayGovde(String name, int n);
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
