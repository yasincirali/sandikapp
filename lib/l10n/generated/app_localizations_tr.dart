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
      'Yalnızca hangi metriklerin GÖSTERİLECEĞİNİ değiştirir; hesaplar ve verilerin aynı kalır.';

  @override
  String get levelBeginner => 'Başlangıç';

  @override
  String get levelIntermediate => 'Orta';

  @override
  String get levelAdvanced => 'İleri';

  @override
  String get levelBeginnerDesc =>
      'Sade görünüm: teknik sinyaller, yüzdelik dilim, sağlık ve XIRR kartları gizlenir.';

  @override
  String get levelIntermediateDesc =>
      'Bugünkü görünüm: teknik sinyaller, yüzdelik dilim, sağlık kartı ve paranın getirisi (XIRR).';

  @override
  String get levelAdvancedDesc =>
      'Orta + risk-ayarlı getiri, zamanlama etkisi ve toparlanma (Özet › 1Y).';

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

  @override
  String get refreshPrices => 'Fiyatları yenile';

  @override
  String get assetAllocation => 'VARLIK DAĞILIMI';

  @override
  String get portfolioActivity => 'PORTFÖY HAREKETLERİ';

  @override
  String get seeAllTransactions => 'Tüm hareketleri gör';

  @override
  String seeAllCount(int count) {
    return 'Tümünü Gör ($count)';
  }

  @override
  String get signalDeleteFailed =>
      'Bildirim silinemedi. Bağlantını kontrol et.';

  @override
  String get permanentDelete => 'Kalıcı sil';

  @override
  String signalDeleteChoice(int past, int active) {
    return 'Geçmişte $past, aktif $active bildirim var. Ne silinsin?';
  }

  @override
  String get cancelShort => 'Vazgeç';

  @override
  String get onlyHistory => 'Yalnızca geçmiş';

  @override
  String get clearAllSignals => 'Tüm sinyalleri temizle';

  @override
  String get clearAllLower => 'Tümünü temizle';

  @override
  String clearAllSignalsBody(int count) {
    return '$count bildirim geçmişe taşınacak. Kalıcı silmek için geçmişteki \"Geçmişi Sil\" düğmesini kullan.';
  }

  @override
  String get clearVerb => 'Temizle';

  @override
  String get clearAllUpper => 'Tümünü Temizle';

  @override
  String get noActiveSignals => 'Şu an aktif sinyal yok';

  @override
  String get historyUpper => 'GEÇMİŞ';

  @override
  String deleteHistoryCount(int count) {
    return 'Geçmişteki $count bildirimi kalıcı olarak sil';
  }

  @override
  String get deleteHistoryTitle => 'Geçmişi sil';

  @override
  String deleteHistoryBody(int count) {
    return '$count bildirim KALICI olarak silinecek. Geri alınamaz.';
  }

  @override
  String get permanentDeleteUpper => 'Kalıcı Sil';

  @override
  String get deleteHistoryButton => 'Geçmişi Sil';

  @override
  String get signalNeutral => 'NÖTR';

  @override
  String signalDeletedAt(String date) {
    return '$date · silindi';
  }

  @override
  String signalConfidence(int count, String pct) {
    return '$count gösterge · $pct güven';
  }

  @override
  String get showBalance => 'Bakiyeyi göster';

  @override
  String get hideBalance => 'Bakiyeyi gizle';

  @override
  String get sortCriterion => 'SIRALAMA KRİTERİ';

  @override
  String tabSemanticsCount(String label, int count) {
    return '$label, $count varlık';
  }

  @override
  String get noChange => 'Değişim yok';

  @override
  String get buyAction => 'Al';

  @override
  String get sellAction => 'Sat';

  @override
  String get deleteAction => 'Sil';

  @override
  String activeAlertsCount(int count) {
    return '$count aktif fiyat alarmı';
  }

  @override
  String get lastMonth => 'Son 1 ay';

  @override
  String get firstPurchase => 'İlk Alış';

  @override
  String get avgCost => 'Ort. Maliyet';

  @override
  String get totalCost => 'Toplam Maliyet';

  @override
  String get currentValue => 'Güncel Tutar';

  @override
  String lotSummary(int buys, int sells) {
    return '$buys alım · $sells çıkarma';
  }

  @override
  String get sortMarketValue => 'Piyasa Değeri';

  @override
  String get sortHighToLow => 'Büyükten Küçüğe';

  @override
  String get sortLowToHigh => 'Küçükten Büyüğe';

  @override
  String get sortGainTry => 'Kazanç (TL)';

  @override
  String get sortGainPct => 'Kazanç (%)';

  @override
  String get sortHighestFirst => 'En Yüksek Önce';

  @override
  String get sortLowestFirst => 'En Düşük Önce';

  @override
  String get assetFullName => 'Tam Adı';

  @override
  String get assetTypeStock => 'Hisse';

  @override
  String get assetTypeFund => 'Fon';

  @override
  String get assetTypeFx => 'Döviz';

  @override
  String get assetTypeGold => 'Altın';

  @override
  String get assetTypeCommodity => 'Emtia';

  @override
  String get assetTypeOther => 'Diğer';

  @override
  String get tickerHintStock =>
      'Örn: THYAO.IS, GARAN.IS  (Borsa İstanbul için .IS ekleyin)';

  @override
  String get tickerHintFund =>
      'Yahoo Finance kodu yoksa boş bırakın, fiyatı manuel girin';

  @override
  String get tickerHintFx => 'Örn: USDTRY=X, EURTRY=X, GBPTRY=X';

  @override
  String get tickerHintGold =>
      'Örn: XAUTRY=X (gram altın TL) veya GC=F (ons, USD)';

  @override
  String get tickerHintCommodity =>
      'Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)';

  @override
  String get tickerHintOther => 'Yahoo Finance sembolü veya boş bırakın';

  @override
  String assetTypeSemantics(String type) {
    return '$type türü';
  }

  @override
  String get total => 'toplam';

  @override
  String get bulkAdd => 'Toplu ekle';

  @override
  String get quickEntryVoice => 'Sesli / Hızlı giriş';

  @override
  String get orNotInList => 'veya listede yok';

  @override
  String get symbolHint => 'Sembol yaz (örn: AAPL, THYAO.IS)';

  @override
  String get companyNameHint =>
      'Şirket adı (opsiyonel — semboldan otomatik çekilir)';

  @override
  String goldSemantics(String kind) {
    return '$kind altın';
  }

  @override
  String get commissionNote =>
      'Alım-satım komisyonu maliyete eklenir — kâr/zarar gerçek rakamı gösterir.';

  @override
  String get costPreviewHint =>
      'Miktar girince toplam maliyet burada görünecek.';

  @override
  String get totalCostUpper => 'TOPLAM MALİYET';

  @override
  String get transactionDate => 'İşlem tarihi';

  @override
  String get addNote => 'Not ekle';

  @override
  String get notesHint => 'Notlarınız...';

  @override
  String quantitySemantics(String value) {
    return 'Miktar $value';
  }

  @override
  String get quickEntryTitle => 'Hızlı Giriş';

  @override
  String get quickEntryHelp =>
      'Her satıra bir varlık yazın. Fiyat opsiyonel — boş bırakırsanız güncel fiyat otomatik çekilir.\nÖrn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet';

  @override
  String get quickEntryPlaceholder =>
      '100 dolar\n10 gram altın 4500 lira\nGARAN 500 adet 105 lira';

  @override
  String saveNAssets(int count) {
    return '$count varlığı kaydet';
  }

  @override
  String get fillTheForm => 'Formu doldur';

  @override
  String get bistStocks => 'BIST Hisseleri';

  @override
  String get tefasFunds => 'TEFAS Fonları';

  @override
  String get fundsLoading => 'Fonlar yükleniyor...';

  @override
  String get pleaseWait => 'Lütfen bekleyin';

  @override
  String get fundsLoadFailed => 'Fonlar yüklenemedi';

  @override
  String get searchEllipsis => 'Ara...';

  @override
  String get clearSearch => 'Aramayı temizle';

  @override
  String get pickStockPrompt => 'Lütfen bir hisse seçin';

  @override
  String get pickStock => 'Hisse seç';

  @override
  String get pickStockTap => 'Hisse seçmek için dokunun...';

  @override
  String get pickFundPrompt => 'Lütfen bir fon seçin';

  @override
  String get pickFund => 'Fon seç';

  @override
  String get pickFundTap => 'Fon seçmek için dokunun...';

  @override
  String get noResults => 'Sonuç bulunamadı';

  @override
  String get priceNotAvailable => 'Fiyat bilgisi yok';

  @override
  String get assetFallbackName => 'Varlık';

  @override
  String get commodityHint => 'Örn: Petrol (Brent)';

  @override
  String get identityStock => 'Hisse';

  @override
  String get identityFund => 'Fon';

  @override
  String get identityGoldKind => 'Altın Türü';

  @override
  String get identityCurrency => 'Para Birimi';

  @override
  String get identityCommodity => 'Emtia';

  @override
  String noResultsFor(String q) {
    return '\"$q\" bulunamadı';
  }

  @override
  String get periodDaily => 'GÜNLÜK';

  @override
  String get period1W => '1H';

  @override
  String get period1M => '1A';

  @override
  String get period6M => '6A';

  @override
  String get period1Y => '1Y';

  @override
  String assetPerformanceSemantics(String name) {
    return 'Performans: $name';
  }

  @override
  String get setPriceAlert => 'Fiyat alarmı kur';

  @override
  String get priceHistoryFailed =>
      'Bu varlığın fiyat geçmişi şu an çekilemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get totalQuantityUpper => 'TOPLAM MİKTAR';

  @override
  String get otherTab => 'Diğer';

  @override
  String periodChangeUpper(String period) {
    return '$period DEĞİŞİM';
  }

  @override
  String buyPerUnit(String unit) {
    return 'ALIŞ / $unit';
  }

  @override
  String todayPerUnit(String unit) {
    return 'BUGÜN / $unit';
  }

  @override
  String get noResultsShort => 'Sonuç yok.';

  @override
  String get compare => 'Karşılaştır';

  @override
  String get clearShort => 'Temizle';

  @override
  String get searchTickerOrName => 'Ticker veya isim ara…';

  @override
  String get myPortfolioTab => 'Portföyüm';

  @override
  String get deleteAccountTitle => 'Hesabını silmek üzeresin';

  @override
  String get deleteAccountBody =>
      'Bu işlem GERİ ALINAMAZ.\n\nTüm portföy kayıtların, performans geçmişin ve ortaklık bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\nDevam etmek istiyor musun?';

  @override
  String get continueAction => 'Devam et';

  @override
  String get verifyIdentityTitle => 'Kimliğini doğrula';

  @override
  String get verifyIdentityBody =>
      'Hesabın Apple/Google ile açılmış. Silmeden önce aynı hesapla bir kez daha giriş yapman istenecek.';

  @override
  String get confirmWithPassword => 'Şifrenle onayla';

  @override
  String get confirmWithPasswordBody =>
      'Güvenliğin için şifrenle onay vermen gerekiyor.';

  @override
  String get deleteAccountUpper => 'HESABI SİL';

  @override
  String get accountDeletedTitle => 'Hesabın silindi';

  @override
  String get accountDeletedBody => 'Görüşmek üzere.';

  @override
  String get investmentDisclaimer => 'Yatırım Tavsiyesi Reddi';

  @override
  String get close => 'Kapat';

  @override
  String get feedbackTitle => 'Şikayet & Tavsiye';

  @override
  String get feedbackHint => 'Mesajınızı yazın…';

  @override
  String get send => 'Gönder';

  @override
  String get deletingAccount => 'Hesabın siliniyor…';

  @override
  String get deletingAccountBody =>
      'Bu işlem birkaç saniye sürebilir. Uygulamayı kapatma.';

  @override
  String get diagnosticsUpper => 'TANILAMA';

  @override
  String get pushDiagnostics => 'Push Teşhisi';

  @override
  String get pushDiagnosticsSubtitle =>
      'Bildirim zincirinin neresi kopuk; cihaz APNs/FCM token durumu';

  @override
  String get notificationsUpper => 'BİLDİRİMLER';

  @override
  String get signalNotifications => 'Teknik sinyal bildirimleri';

  @override
  String get signalNotificationsSubtitle =>
      'AL/SAT göstergesi tetiklendiğinde bildirim al';

  @override
  String get signalSettings => 'Sinyal ayarları';

  @override
  String get signalSettingsSubtitle =>
      'Her varlık türü için gösterge seçimi + Premium';

  @override
  String get priceAlerts => 'Fiyat alarmları';

  @override
  String get partnerInviteNotifications => 'Ortaklık daveti bildirimleri';

  @override
  String get partnerInviteNotificationsSubtitle =>
      'Yeni ortaklık isteği geldiğinde bildirim al';

  @override
  String get liveActivitiesUpper => 'CANLI ETKİNLİKLER';

  @override
  String get biometricLock => 'Biyometrik kilit';

  @override
  String get downloadMyData => 'Verilerimi İndir';

  @override
  String get downloadMyDataSubtitle =>
      'Tüm verilerini JSON dosyası olarak al (KVKK Madde 11)';

  @override
  String get deleteMyAccount => 'Hesabımı Sil';

  @override
  String get deleteMyAccountSubtitle => 'Tüm verilerin kalıcı olarak silinir';

  @override
  String get supportUpper => 'DESTEK';

  @override
  String get contactUs => 'Bize Ulaş';

  @override
  String get replayTour => 'Tanıtım turunu yeniden izle';

  @override
  String get replayTourSubtitle => 'Ekranların ne işe yaradığını hatırla';

  @override
  String get feedbackSubtitle => 'Görüşünü bize ilet';

  @override
  String get legalUpper => 'YASAL';

  @override
  String get privacyPolicy => 'Gizlilik Politikası';

  @override
  String get privacyPolicySubtitle => 'Verilerin nasıl işleniyor';

  @override
  String get termsOfUse => 'Kullanım Koşulları';

  @override
  String get termsOfUseSubtitle => 'Hizmet sözleşmesi';

  @override
  String get kvkkNotice => 'KVKK Aydınlatma Metni';

  @override
  String get kvkkNoticeSubtitle => 'Kişisel veri işleme aydınlatması';

  @override
  String get disclaimerSubtitle => 'Onayladığın yasal uyarı metnini görüntüle';

  @override
  String themeSemantics(String name) {
    return '$name tema';
  }

  @override
  String baseCurrencySemantics(String name) {
    return 'Baz para birimi $name';
  }

  @override
  String levelSemantics(String name) {
    return '$name seviye';
  }

  @override
  String get showAllDay => 'Gün boyu göster';

  @override
  String get showAllDaySubtitle =>
      'Kapalıyken yalnızca seçtiğin saat aralığında görünür.';

  @override
  String get displayWindow => 'Gösterim aralığı';

  @override
  String get startTime => 'Başlangıç';

  @override
  String get endTime => 'Bitiş';

  @override
  String get showOnWeekend => 'Hafta sonu da göster';

  @override
  String get showOnWeekendSubtitle =>
      'Hafta sonu BIST kapalıdır; banner son kapanışı \"Piyasa kapalı\" etiketiyle gösterir.';

  @override
  String get showAmounts => 'Tutarları göster';

  @override
  String get showAmountsSubtitle =>
      'Kapalıyken yalnızca günlük yüzde ve grafik görünür. Kilit ekranı telefonunuz açılmadan görülebildiği için varsayılan olarak kapalıdır.';

  @override
  String get partnerActivityNotifications => 'Ortak hareketi bildirimleri';

  @override
  String get partnerActivityNotificationsSubtitle =>
      'Ortağın portföyüne ekleme yaptığında günlük özette an';

  @override
  String get quietHours => 'Sessiz saatler';

  @override
  String get biometricLockSubtitle =>
      'Uygulamayı açarken Face ID / parmak izi / cihaz PIN\'i iste';

  @override
  String get doneTitle => 'Tamamlandı';

  @override
  String get alreadyPartners => 'Zaten Ortaksınız';

  @override
  String get ownCode => 'Kendi Kodun';

  @override
  String get expiredTitle => 'Süresi Doldu';

  @override
  String get waitABit => 'Biraz Bekle';

  @override
  String get somethingWentWrong => 'Bir sorun oluştu';

  @override
  String get cancelInviteTitle => 'Ortaklık isteğini iptal et';

  @override
  String get cancelInviteBody =>
      'Gönderdiğin ortaklık isteğini iptal etmek istediğine emin misin?';

  @override
  String get yesCancel => 'Evet, iptal et';

  @override
  String get settingsTitle => 'Ayarlar';

  @override
  String get partnerActionsUpper => 'ORTAKLIK İŞLEMLERİ';

  @override
  String get myPartnersUpper => 'ORTAKLARIM';

  @override
  String get generateInviteCode => 'Davet Kodu Üret';

  @override
  String get generateInviteCodeBody =>
      'Kodu ortağınıza gönderin. Ortak kodu girince size onay isteği gelir.';

  @override
  String get enterPartnerCode => 'Ortak Kodunu Gir';

  @override
  String get enterPartnerCodeBody =>
      'Ortağınızın size gönderdiği kodu girin (örn: KRHNJ-8P2SW). Onay vermesi beklenir.';

  @override
  String tooManyAttempts(String wait) {
    return 'Çok fazla deneme — $wait sonra tekrar deneyebilirsin.';
  }

  @override
  String awaitingApproval(String name) {
    return '$name onayı bekleniyor...';
  }

  @override
  String get cancelWord => 'İptal';

  @override
  String get noPartnersYet => 'Henüz ortağınız yok';

  @override
  String get removePartnerSemantics => 'Ortağı sil';

  @override
  String get removePartnerTitle => 'Ortaklığı kaldır';

  @override
  String removePartnerBody(String name) {
    return '$name ile ortaklığı kaldırmak istediğine emin misin?';
  }

  @override
  String get removeWord => 'Kaldır';

  @override
  String get pendingRequestsUpper => 'BEKLEYEN ORTAKLIK İSTEKLERİ';

  @override
  String get wantsToPartner => 'Ortaklık istiyor';

  @override
  String get rejectRequest => 'Ortaklık isteğini reddet';

  @override
  String get acceptRequest => 'Ortaklık isteğini kabul et';

  @override
  String get sandikPremium => 'Sandık Premium';

  @override
  String get premiumPitch =>
      'Sınırsız varlık, premium göstergeler, günde 2 sinyal analizi';

  @override
  String get premiumActive => 'Premium aktif';

  @override
  String get premiumActiveBody => 'Tüm gelişmiş özellikler açık';

  @override
  String get codeCopied => 'Kod üretildi ve panoya kopyalandı';

  @override
  String tooManyFailedAttempts(String wait) {
    return 'Çok fazla başarısız deneme.\n$wait sonra tekrar deneyebilirsin.';
  }

  @override
  String partnershipCreated(String name) {
    return '$name ile ortaklık kuruldu!';
  }

  @override
  String get requestRejected => 'Ortaklık isteği reddedildi.';

  @override
  String get requestCancelled => 'Ortaklık isteği iptal edildi.';

  @override
  String get partnershipAccepted => 'Ortaklık kabul edildi!';

  @override
  String get sendingEllipsis => 'Gönderiliyor...';

  @override
  String waitFor(String wait) {
    return 'Bekle — $wait';
  }

  @override
  String get requestPartnership => 'Ortaklık İste';

  @override
  String get generatingEllipsis => 'Üretiliyor...';

  @override
  String get generateCode => 'Kod Üret';

  @override
  String get switchToDark => 'Koyu temaya geç';

  @override
  String get switchToLight => 'Açık temaya geç';

  @override
  String get tabChart => 'Grafik';

  @override
  String get tabSummary => 'Özet';

  @override
  String get modeReal => 'Gerçek';

  @override
  String get modeSim => 'Simülasyon';

  @override
  String modeInfoSemantics(String mode) {
    return '$mode modu hakkında bilgi';
  }

  @override
  String get noChartData => 'Grafik verisi yok';

  @override
  String get noAssetsYetTitle => 'Henüz varlığın yok';

  @override
  String noAssetsOfTypeTitle(String type) {
    return 'Portföyünde $type yok';
  }

  @override
  String get noAssetsChartBody =>
      'Varlık ekledikçe portföyünün performansı burada grafiğe dönüşecek.';

  @override
  String get noAssetsOfTypeChartBody =>
      'Bu türden bir varlık eklediğinde performansı burada görünecek. Başka bir tür seçebilirsin.';

  @override
  String get noHistoryAllBody =>
      'Portföyündeki varlıkların fiyat geçmişi izlenmiyor; değerleri toplamda görünür ama zaman grafiği çizilemiyor.';

  @override
  String noHistoryTypeBody(String type) {
    return '$type için fiyat geçmişi izlenmiyor. Değeri portföy toplamına dahil, ama zaman grafiği çizilemiyor.';
  }

  @override
  String get simModeTitle => 'Simülasyon Modu';

  @override
  String get realModeTitle => 'Gerçek Mod';

  @override
  String get simModeBody =>
      'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş olsaydın grafik nasıl görünürdü — geçmişteki alım/satış kararlarını yok sayar, sadece güncel pozisyonun fiyat değişimini gösterir.';

  @override
  String get realModeBody =>
      'Her günün grafikteki değeri, o gün elinde olan net miktara göre hesaplanır. Bir noktaya dokununca o günkü portföy değeri ve varsa alım / satış tutarları görünür — böylece grafiğin neden yükseldiğini veya düştüğünü net görebilirsin.';

  @override
  String get portfolioPerformance => 'Portföy Performans';

  @override
  String get chartDataFailed => 'Grafik verisi alınamadı';

  @override
  String get chartDataFailedBody =>
      'Fiyat geçmişi şu an getirilemedi. Bağlantını kontrol edip tekrar deneyebilirsin.';

  @override
  String intradayMissingBody(String names) {
    return '$names için gün içi fiyat verisi alınamadı. Bu varlıklar grafikte son bilinen fiyatlarıyla SABİT çizildi — çizginin düz olması piyasanın durgun olduğu anlamına gelmez.';
  }

  @override
  String get retryLower => 'Tekrar dene';

  @override
  String get raceUpper => 'YARIŞ';

  @override
  String get changeByTypeUpper => 'TÜRE GÖRE DEĞİŞİM';

  @override
  String get noData => 'Veri yok';

  @override
  String get tooltipReturn => '\nGetiri ';

  @override
  String get tooltipBuy => '\nAlım  +';

  @override
  String get tooltipSell => '\nSatış −';

  @override
  String get tooltipNet => '\nNet ';

  @override
  String get tooltipInvested => '\nToplam yatırım ';

  @override
  String get tradeVolumeUpper => 'İŞLEM HACMİ';

  @override
  String get performanceTitle => 'Performans';

  @override
  String get intervalWeekly => 'Haftalık';

  @override
  String get intervalMonthly => 'Aylık';

  @override
  String get intervalYearly => 'Yıllık';

  @override
  String lastNWeeksNet(int n) {
    return 'son $n hafta · net';
  }

  @override
  String lastNMonthsNet(int n) {
    return 'son $n ay · net';
  }

  @override
  String lastNYearsNet(int n) {
    return 'son $n yıl · net';
  }

  @override
  String get avgContributingWeek => 'Katkı yaptığın hafta ortalaması';

  @override
  String get avgContributingMonth => 'Katkı yaptığın ay ortalaması';

  @override
  String get avgContributingYear => 'Katkı yaptığın yıl ortalaması';

  @override
  String get vsLastWeek => 'Geçen haftaya göre';

  @override
  String get vsLastMonth => 'Geçen aya göre';

  @override
  String get vsLastYear => 'Geçen yıla göre';

  @override
  String get ongoingWeek => ', devam eden hafta';

  @override
  String get ongoingMonth => ', devam eden ay';

  @override
  String get ongoingYear => ', devam eden yıl';

  @override
  String get trendUpWeek => 'Son hafta önceki katkılarının üzerinde.';

  @override
  String get trendUpMonth => 'Son ay önceki katkılarının üzerinde.';

  @override
  String get trendUpYear => 'Son yıl önceki katkılarının üzerinde.';

  @override
  String get trendDownWeek => 'Son hafta önceki katkılarının altında.';

  @override
  String get trendDownMonth => 'Son ay önceki katkılarının altında.';

  @override
  String get trendDownYear => 'Son yıl önceki katkılarının altında.';

  @override
  String get trendFlatWeek => 'Katkın haftadan haftaya istikrarlı.';

  @override
  String get trendFlatMonth => 'Katkın aydan aya istikrarlı.';

  @override
  String get trendFlatYear => 'Katkın yıldan yıla istikrarlı.';

  @override
  String get biggestMoverToday => 'Günün en çok hareket edeni';

  @override
  String get weekExtremes => 'Haftanın uçları';

  @override
  String get lastMonthPeriod => 'son 1 ay';

  @override
  String get last6MonthsPeriod => 'son 6 ay';

  @override
  String get sixMonthExtremes => 'Altı ayın uçları';

  @override
  String get lastYearPeriod => 'son 1 yıl';

  @override
  String get yearCurve => 'Yıl eğrisi';

  @override
  String periodMarketReturn(String period) {
    return '$period piyasa getirisi';
  }

  @override
  String get whereItCameFrom => 'Nereden geldi';

  @override
  String get periodStart => 'Dönem başı';

  @override
  String get yourContribution => 'Katkın';

  @override
  String get marketWord => 'Piyasa';

  @override
  String get cashDividend => 'Bunun nakit temettüsü';

  @override
  String get commissionPaid => 'Ödenen komisyon';

  @override
  String get contributionNotReturn =>
      'Mavi çubuk senin paran — getiri sayılmaz. Yüzde yalnızca piyasa çubuğundan hesaplanır.';

  @override
  String get periodCourse => 'Dönem içi seyir';

  @override
  String greenDaysOfTotal(int total, int up) {
    return '$total işlem gününün $up\'ü artıda kapandı.';
  }

  @override
  String get againstInflation => 'Enflasyona karşı';

  @override
  String realReturnPeriod(String period) {
    return 'Reel getiri · $period';
  }

  @override
  String get nominalReturn => 'Nominal getiri';

  @override
  String get periodCpi => 'Dönem TÜFE';

  @override
  String get pointDifference => 'Puan farkı';

  @override
  String get realReturn => 'Reel getiri';

  @override
  String get cpiNotLoaded => 'TÜFE verisi henüz yüklenmedi.';

  @override
  String get cpiNotLoadedBody =>
      'Enflasyon endeksi geldiğinde portföyünün reel getirisi burada görünecek. Tahmini bir sayı gösterilmiyor.';

  @override
  String get allocationChange => 'Dağılım değişimi';

  @override
  String get sixMonthComparison => 'Altı aylık karşılaştırma';

  @override
  String get portfolioCharacter => 'Portföyünün karakteri';

  @override
  String get mostPatientAsset => 'En sabırlı varlığın';

  @override
  String nDays(int n) {
    return '$n gün';
  }

  @override
  String get shareSummary => 'Özetini paylaş';

  @override
  String get savingDiscipline => 'Birikim disiplinin';

  @override
  String get noNewMoney => 'Bu pencerede portföyüne yeni para girmemiş.';

  @override
  String get highestWord => 'En yüksek';

  @override
  String get contributingPeriods => 'Katkı yapılan dönem';

  @override
  String portfolioHealthPeriod(String period) {
    return 'Portföy sağlığı · $period';
  }

  @override
  String get maxDrawdown => 'En büyük düşüş';

  @override
  String get volatility => 'Oynaklık';

  @override
  String get volatilityBody =>
      'Portföyünün değeri yıl boyunca ortalama bu ölçüde dalgalandı. Yüksek olması iyi ya da kötü değil — daha çok inip çıktığı anlamına gelir.';

  @override
  String get concentration => 'Yoğunlaşma';

  @override
  String get moneyReturnAnnual => 'Paranın getirisi (yıllık)';

  @override
  String get xirrBody =>
      'Yatırdığın paranın, yatırdığın TARİHLER dikkate alınarak hesaplanan yıllık bileşik getirisi.';

  @override
  String get periodMarketReturnLabel => 'Dönem piyasa getirisi';

  @override
  String get xirrVsMarketBody =>
      'İki sayı çelişmez: üstteki senin ne zaman alım yaptığını da hesaba katar, alttaki yalnızca piyasanın hareketini ölçer.';

  @override
  String get advancedMetricsYear => 'İleri metrikler · son 1 yıl';

  @override
  String notEnoughHistory(String period) {
    return '$period için yeterli geçmiş yok';
  }

  @override
  String get notEnoughHistoryBody =>
      'Bu dönem dolduğunda özet kendiliğinden görünür.';

  @override
  String nAssetsPeriod(int count, String period) {
    return '$count VARLIK · $period';
  }

  @override
  String get chartLoadFailed => 'Grafik yüklenemedi.';

  @override
  String get notEnoughPriceHistory => 'Grafik için yeterli fiyat geçmişi yok.';

  @override
  String portfolioLineNote(String name) {
    return '$name çizgisi, bugünkü varlıklarını dönem başından beri tutsaydın senaryosudur — gerçekleşmiş getirin değildir.';
  }

  @override
  String openDetailSemantics(String name) {
    return '$name detayını aç';
  }

  @override
  String addToPortfolioSemantics(String name) {
    return '$name portföyüme ekle';
  }

  @override
  String get noWatchlistYet => 'Henüz izlediğin varlık yok';

  @override
  String get noWatchlistBody =>
      'Almadan önce takibe al. Fiyatını portföyüne dokunmadan izle.';

  @override
  String get addToWatchlist => 'Takibe varlık ekle';

  @override
  String get whyWatchlistUpper => 'NEDEN TAKİP LİSTESİ?';

  @override
  String get whyWatchlistBody =>
      'Bir varlığı satın almadan fiyatını izleyebilirsin. Takip listesi portföyüne girmez; toplam değerini ve kâr/zararını etkilemez.';

  @override
  String get notInPortfolioNote => 'Bu varlıklar portföyüne dahil değildir.';

  @override
  String get addAssetsToCompare => 'Karşılaştırmak için varlık ekleyin';

  @override
  String get addAssetsToCompareBody =>
      'Portföyünüzde olmayan varlıkları da ekleyebilirsiniz.';

  @override
  String get inMyPortfolio => 'Portföyümde';

  @override
  String get noDataShort => 'veri yok';

  @override
  String get addToMyPortfolio => 'Portföyüme ekle';

  @override
  String get comparisonDisclaimer =>
      'Geçmiş performans gelecek getiri için gösterge değildir. Grafikteki değerler dönem başına göre yüzde değişimi gösterir; komisyon, vergi ve temettü dahil değildir.';

  @override
  String get searchAssetsHint => 'Hisse, fon, altın veya endeks ara';

  @override
  String get noResultsFound => 'Sonuç bulunamadı';

  @override
  String get portfolioSeriesNote =>
      'Portföyler hesaplanan serilerdir — piyasada kote değiller. Getirileri, tıpkı bir varlık gibi dönem başına göre yüzde olarak çizilir.';

  @override
  String get portfolioActivityTitle => 'Portföy Hareketleri';

  @override
  String get clearFilters => 'Filtreleri temizle';

  @override
  String get loadingEllipsis => 'Yükleniyor…';

  @override
  String get widenDateRangeHint =>
      'Tarih aralığını genişletmeyi veya aramayı temizlemeyi dene.';

  @override
  String get priceAlertsTitle => 'Fiyat Alarmları';

  @override
  String get createAlert => 'Alarm kur';

  @override
  String get noAlertsYet => 'Henüz alarmın yok';

  @override
  String get noAlertsBody =>
      'Bir varlığın ekranındaki zile dokun ya da buradan kur; uygulama kapalıyken bile haber verelim.';

  @override
  String get recreateAlert => 'Yeniden kur';

  @override
  String get raceTitle => 'Yarış';

  @override
  String get raceOptions => 'Yarış seçenekleri';

  @override
  String get leaveRace => 'Yarıştan ayrıl';

  @override
  String get leaveRaceBody =>
      'Sıralamadan çıkarsın; ortakların yüzdeni artık göremez. İstediğin zaman yeniden katılabilirsin.';

  @override
  String get leaveWord => 'Ayrıl';

  @override
  String get howReturnCalculated => 'Getiri nasıl hesaplanıyor?';

  @override
  String get selectedPeriodReturn => 'Seçili dönemin getirisi';

  @override
  String get depositsDontChangeRank => 'Para yatırmak sıralamayı değiştirmez';

  @override
  String get everyoneMeasuredSame => 'Herkes aynı şekilde ölçülür';

  @override
  String get rankVsPortfolioNote =>
      'Bu sayı, Portföy ekranındaki kâr/zarar yüzdesinden FARKLI olabilir — orası ilk alımından bugüne olan toplam kâr/zararı gösterir, burası ise yalnızca seçtiğin dönemde ne olduğunu.';

  @override
  String get rankSwapNote =>
      'Dönem içinde bir varlığı tamamen satıp yerine başkasını aldıysan, sonuç \"yeni varlığı dönem başından beri tutsaydın\" senaryosunu gösterir. Fiyat geçmişi bulunamayan portföyler sıralamada yer almaz.';

  @override
  String get notInRace => 'Yarış\'a katılmadın';

  @override
  String get notInRaceBody =>
      'Ortaklarınla getiri sıralamasında yer almak için katılmayı aç. Sadece kaydolan ortaklar birbirinin yüzdesini görebilir. Varlıkların ve toplam TRY değerin asla paylaşılmaz.';

  @override
  String get joinRace => 'Yarış\'a katıl';

  @override
  String get addPartnerToRace => 'Ortak ekle, aranızda da yarış';

  @override
  String get raceNoListShared =>
      'Kimsenin varlık listesi paylaşılmaz — yalnız getiri yüzdeleri sıralanır.';

  @override
  String get yourReturnUpper => 'SENİN GETİRİN';

  @override
  String get dataNotReady => 'Veri hazır değil.';

  @override
  String get leaderUpper => 'LİDER';

  @override
  String get loadingUpper => 'YÜKLENİYOR';

  @override
  String get globalRanking => 'Genel Sıralama';

  @override
  String get checkingAnonPool => 'Anonim havuz kontrol ediliyor…';

  @override
  String get comingSoonUpper => 'YAKINDA';

  @override
  String get globalRankingSoon =>
      'Yeterli katılımcı olunca sıran açılacak — anonim, KVKK uyumlu';

  @override
  String topPercentile(String period, int pct) {
    return '$period sıralamada ilk %$pct\'desin';
  }

  @override
  String get topPortfolios => 'Zirvedeki Portföyler';

  @override
  String topGainersAllocation(String period) {
    return '$period en çok kazananların dağılımı';
  }

  @override
  String get anonymousUpper => 'ANONİM';

  @override
  String get topPortfoliosSoon =>
      'Yeterli katılımcı olunca zirve portföyler burada görünecek. Anonim havuz oluşuyor…';

  @override
  String nthPortfolio(int n) {
    return '$n. portföy';
  }

  @override
  String get selectedPeriodReturnBody =>
      'Portföyünün dönem sonundaki değeri, dönem başındaki değeriyle karşılaştırılır:\n\n(dönem sonu − dönem başı) ÷ dönem başı\n\nYukarıdaki 7G / 30G / 1Y seçimi sonucu doğrudan değiştirir.';

  @override
  String get depositsDontChangeRankBody =>
      'Ölçülen tek şey, varlıklarının piyasada ne kadar değer kazandığı. Dönem içinde yaptığın alım ve satımlar oranı ETKİLEMEZ.\n\nHesap, bugünkü varlıklarını dönem başından beri tutmuşsun gibi yapılır. Bu yüzden portföyünü büyütmek getirini yükseltmez — 1 lot da tutsan 10.000 lot da tutsan aynı yüzdeyi görürsün.';

  @override
  String get everyoneMeasuredSameBody =>
      'Sen ve ortakların aynı formülle, aynı anda, aynı fiyatlarla hesaplanırsınız.\n\nOrtağının uygulamayı açmasını beklemene gerek yok — hesap bu cihazda yapılır.';

  @override
  String get planYearly => 'Yıllık';

  @override
  String get planYearlySubtitle =>
      '7 gün ücretsiz dene, sonra otomatik yenilenir';

  @override
  String get planMonthly => 'Aylık';

  @override
  String get planMonthlySubtitle => 'İstediğin zaman iptal edebilirsin';

  @override
  String get subscriptionTerms =>
      'Abonelik App Store hesabına yansır. Otomatik yenilenir, iptal için Ayarlar → Apple ID → Abonelikler menüsünden yönetebilirsin. Yıllık abonelikte ilk 7 gün ücretsiz denemedir; iptal etmezsen deneme sonunda ücret tahsil edilir.';

  @override
  String get premiumUnlocked => 'Premium açıldı';

  @override
  String get premiumUnlockedBody =>
      'Sınırsız varlık, günde 2 sinyal analizi, premium göstergeler ve daha fazlası açıldı.';

  @override
  String get greatWord => 'Harika';

  @override
  String get sandikPremiumUpper => 'SANDIK PREMIUM';

  @override
  String get paywallHeadline => 'Portföyünü daha derinlemesine\ntakip et';

  @override
  String get paywallSubhead =>
      'Sınırsız varlık, gelişmiş göstergeler ve günde 2 sinyal analizi.';

  @override
  String get restorePurchase => 'Satın alımı geri yükle';

  @override
  String get recapTitle => 'sandık Özetin';

  @override
  String recapInYear(int year) {
    return '$year yılında';
  }

  @override
  String get recapSubtitle => 'Bir yılın kısa hikâyesi.';

  @override
  String recapPoints(String n) {
    return '$n puan';
  }

  @override
  String recapDays(int n) {
    return '$n gün';
  }

  @override
  String myRecapYear(int year) {
    return 'Özetim $year';
  }

  @override
  String recapReady(int year) {
    return '$year Özetin hazır';
  }

  @override
  String recapCardSubtitle(String character) {
    return 'Bir yılın kısa hikâyesi — $character';
  }
}
