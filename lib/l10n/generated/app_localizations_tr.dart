// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String get appName => 'sandık';

  @override
  String get loginTagline => 'Hazineni birlikte büyüt.';

  @override
  String get email => 'E-posta';

  @override
  String get emailInvalid => 'Geçerli e-posta girin';

  @override
  String get password => 'Şifre';

  @override
  String get passwordShow => 'Şifreyi göster';

  @override
  String get passwordHide => 'Şifreyi gizle';

  @override
  String get passwordMin6 => 'En az 6 karakter';

  @override
  String get passwordRequired => 'Şifre gerekli';

  @override
  String get rememberMe => 'Beni hatırla';

  @override
  String get forgotPassword => 'Şifremi unuttum';

  @override
  String get signIn => 'Giriş Yap';

  @override
  String get noAccountRegister => 'Hesabınız yok mu? Kayıt olun';

  @override
  String get register => 'Kayıt Ol';

  @override
  String get registerWelcome => 'Sandığına hoş geldin.';

  @override
  String get registerSubtitle => 'Birkaç adımda hesabını oluştur.';

  @override
  String get fullName => 'Ad Soyad';

  @override
  String get fullNameRequired => 'Ad soyad girin';

  @override
  String get passwordRepeat => 'Şifre Tekrar';

  @override
  String get passwordsMismatch => 'Şifreler eşleşmiyor';

  @override
  String get haveAccountSignIn => 'Zaten hesabınız var mı? Giriş yapın';

  @override
  String get exitAppTitle => 'Uygulamadan çık';

  @override
  String get exitAppMessage => 'Uygulamadan çıkmak istediğine emin misin?';

  @override
  String get exit => 'Çık';

  @override
  String get tabHome => 'Ana';

  @override
  String get tabPortfolio => 'Portföy';

  @override
  String get tabPerformance => 'Performans';

  @override
  String get tabProfile => 'Profil';

  @override
  String get addAsset => 'Varlık ekle';

  @override
  String get lockTitle => 'sandık kilitli';

  @override
  String get lockFailed => 'Doğrulama yapılamadı. Tekrar dene.';

  @override
  String get lockPrompt => 'Portföyünü görmek için kimliğini doğrula.';

  @override
  String get lockVerifying => 'Doğrulanıyor…';

  @override
  String get unlock => 'Kilidi aç';

  @override
  String get disclaimerTitle => 'Yasal Uyarı';

  @override
  String get disclaimerIntro =>
      'Uygulamayı kullanmaya devam etmek için lütfen aşağıdaki yasal uyarıyı okuyun ve onaylayın.';

  @override
  String get disclaimerAcceptRow =>
      'Yukarıdaki yasal uyarıyı okudum ve kabul ediyorum.';

  @override
  String get disclaimerMustAccept =>
      'Devam etmek için yasal uyarıyı kabul etmelisin.';

  @override
  String get accept => 'Kabul Ediyorum';

  @override
  String get forgotTitle => 'Şifremi Unuttum';

  @override
  String get forgotIntro => 'Kod göndereceğimiz e-posta adresini gir.';

  @override
  String get sendCode => 'Kod Gönder';

  @override
  String codeSentTo(String email) {
    return '$email adresine kod gönderdik. Kodu ve yeni şifreni gir.';
  }

  @override
  String get code => 'Kod';

  @override
  String get codeInvalid => 'Kod eksik veya geçersiz';

  @override
  String get newPassword => 'Yeni Şifre';

  @override
  String get newPasswordRepeat => 'Yeni Şifre Tekrar';

  @override
  String get updatePassword => 'Şifreyi Güncelle';

  @override
  String get tryAnotherEmail => 'Farklı bir e-posta ile tekrar dene';

  @override
  String get passwordUpdatedTitle => 'Şifre güncellendi';

  @override
  String get passwordUpdatedMessage =>
      'Yeni şifrenle giriş yapabilirsin. Şimdi ana ekrana yönlendirileceksin.';

  @override
  String get otpTitle => 'E-postanı doğrula';

  @override
  String get otpExpired => 'Kodun süresi doldu. Yeni kod iste.';

  @override
  String get otpEnterFull => 'Lütfen 6 haneli kodu tam olarak girin.';

  @override
  String get otpSentTitle => 'Kod gönderildi';

  @override
  String get otpSentMessage => 'Yeni 6 haneli kod e-postana gönderildi.';

  @override
  String get otpExpiredShort => 'Kodun süresi doldu';

  @override
  String otpExpiresIn(String time) {
    return 'Kod $time sonra geçersiz olur';
  }

  @override
  String get sending => 'Gönderiliyor…';

  @override
  String get requestNewCode => 'Yeni Kod İste';

  @override
  String get verify => 'Doğrula';

  @override
  String get otpNotReceived => 'Kodu almadın mı? ';

  @override
  String get resend => 'Yeniden gönder';

  @override
  String resendIn(int seconds) {
    return 'Yeniden gönder (${seconds}s)';
  }

  @override
  String get otpWrongEmail =>
      'Yanlış e-posta mı girdin? Geri dönüp tekrar deneyebilirsin.';

  @override
  String get settings => 'Ayarlar';

  @override
  String get settingsAppearance => 'Görünüm';

  @override
  String get settingsNotifications => 'Bildirimler';

  @override
  String get settingsAccount => 'Hesap & Güvenlik';

  @override
  String get settingsHelp => 'Yardım & Yasal';

  @override
  String get settingsAppearanceSubtitle =>
      'Tema, baz para birimi, dil, yatırımcı seviyesi';

  @override
  String get settingsAccountSubtitle =>
      'Biyometrik kilit, verilerini indir, hesabını sil';

  @override
  String get settingsHelpSubtitle =>
      'Bize ulaş, tanıtım turu, gizlilik ve koşullar';

  @override
  String get themeSystem => 'Sistem';

  @override
  String get themeLight => 'Açık';

  @override
  String get themeDark => 'Koyu';

  @override
  String get language => 'Dil';

  @override
  String get languageSystem => 'Sistem';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageNote => 'İngilizce beta: bazı ekranlar henüz Türkçe.';

  @override
  String get investorLevel => 'Yatırımcı seviyesi';

  @override
  String get investorLevelNote =>
      'Yalnızca Performans › Özet\'in kart kümesini değiştirir; hesaplar aynı kalır.';

  @override
  String get levelBeginner => 'Başlangıç';

  @override
  String get levelIntermediate => 'Orta';

  @override
  String get levelAdvanced => 'İleri';

  @override
  String get levelBeginnerDesc =>
      'Sade özet: getiri, enflasyon ve katkı. Sağlık, XIRR ve yüzdelik yok.';

  @override
  String get levelIntermediateDesc =>
      'Bugünkü görünüm: sağlık kartı, paranın getirisi (XIRR), yüzdelik dilim.';

  @override
  String get levelAdvancedDesc =>
      'Orta + risk-ayarlı getiri, zamanlama etkisi ve toparlanma.';

  @override
  String get noAssetsYet => 'Henüz varlık eklenmemiş';

  @override
  String get noAssetsOfType => 'Bu türde varlık yok';

  @override
  String get noAssetsYetHint =>
      'İlk varlığını ekleyerek sandığını oluşturmaya başla.';

  @override
  String get noAssetsOfTypeHint =>
      'Filtreyi değiştir ya da bu türden bir varlık ekle.';

  @override
  String get addFirstAsset => 'İlk Varlığını Ekle';

  @override
  String get addAssetTitle => 'Varlık Ekle';

  @override
  String get editAsset => 'Düzenle';

  @override
  String get add => 'Ekle';

  @override
  String get update => 'Güncelle';

  @override
  String get save => 'Kaydet';

  @override
  String get assetType => 'Varlık Türü';

  @override
  String get assetName => 'Varlık adı';

  @override
  String get nameRequired => 'Ad zorunlu';

  @override
  String get quantity => 'Miktar';

  @override
  String get quantityInvalid => 'Geçerli miktar';

  @override
  String get purchasePrice => 'Alış Fiyatı';

  @override
  String get optional => '· opsiyonel';

  @override
  String get auto => 'Otomatik';

  @override
  String get invalid => 'Geçersiz';

  @override
  String get commission => 'Komisyon / Masraf';

  @override
  String get cannotBeNegative => 'Negatif olamaz';

  @override
  String get allTypes => 'Tümü';

  @override
  String get retry => 'Tekrar Dene';

  @override
  String get cancel => 'Vazgeç';

  @override
  String get delete => 'Sil';

  @override
  String get sell => 'Sat';

  @override
  String get dividend => 'Temettü';

  @override
  String get profile => 'Profil';

  @override
  String get portfolio => 'Portföy';

  @override
  String get myAssets => 'Varlıklarım';

  @override
  String get watchlist => 'Takip Listesi';

  @override
  String get priceUpdateFailed =>
      'Fiyatlar güncellenemedi — eski veriler gösteriliyor.';

  @override
  String get otpSentPrefix => '6 haneli kodu\n';

  @override
  String get otpSentSuffix => '\nadresine gönderdik.';

  @override
  String get registerNameMissing => 'Ad soyad girin.';

  @override
  String get registerEmailInvalid => 'Geçerli bir e-posta girin.';

  @override
  String get registerPasswordsMismatch => 'Şifreler eşleşmiyor.';

  @override
  String get termsMustAccept => 'Yasal koşulları kabul etmelisin.';

  @override
  String get consentMustAccept =>
      'Yurt dışı veri aktarımına açık rıza vermelisin.';
}
