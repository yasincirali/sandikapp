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
  String get emailInvalid => 'Geçerli bir e-posta gir';

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
  String get noAccountRegister => 'Hesabın yok mu? Kayıt ol';

  @override
  String get register => 'Kayıt Ol';

  @override
  String get registerWelcome => 'Sandığına hoş geldin.';

  @override
  String get registerSubtitle => 'Birkaç adımda hesabını oluştur.';

  @override
  String get fullName => 'Ad Soyad';

  @override
  String get fullNameRequired => 'Ad soyad gir';

  @override
  String get passwordRepeat => 'Şifre Tekrar';

  @override
  String get passwordsMismatch => 'Şifreler eşleşmiyor';

  @override
  String get sifreKuralUzunluk => 'En az 8 karakter';

  @override
  String get sifreKuralHarf => 'En az bir harf';

  @override
  String get sifreKuralRakam => 'En az bir rakam';

  @override
  String get haveAccountSignIn => 'Zaten hesabın var mı? Giriş yap';

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
  String get lockNoDeviceCredential =>
      'Cihazında ekran kilidi (Face ID, parmak izi ya da şifre) tanımlı değil. Doğrulama yapılamıyor.';

  @override
  String get lockDisableAndContinue => 'Kilidi kapat ve devam et';

  @override
  String get lockSwitchAccount => 'Farklı hesapla giriş yap';

  @override
  String get lockSwitchAccountTitle => 'Oturumu kapat';

  @override
  String get lockSwitchAccountBody =>
      'Bu hesaptan çıkılacak ve giriş ekranına döneceksin. Verilerin silinmez; tekrar giriş yaptığında yerinde olur.';

  @override
  String get unlock => 'Kilidi aç';

  @override
  String get disclaimerTitle => 'Yasal Uyarı';

  @override
  String get disclaimerIntro =>
      'Uygulamayı kullanmaya devam etmek için aşağıdaki yasal uyarıyı oku ve onayla.';

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
  String get otpEnterFull => '6 haneli kodun tamamını gir.';

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
      'Biyometrik kilit, kayıtlı cihazlar, verilerini indir, hesabını sil';

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
  String get languageNote =>
      'İngilizce beta: yasal metinler, tanıtım turu ve altın/fon alt kategori adları Türkçe kalır.';

  @override
  String get textSize => 'Yazı boyutu';

  @override
  String get textSizeSmall => 'Küçük';

  @override
  String get textSizeNormal => 'Normal';

  @override
  String get textSizeLarge => 'Büyük';

  @override
  String get textSizeXLarge => 'Çok büyük';

  @override
  String get textSizeNote =>
      'Telefonunun yazı boyutu ayarının üstüne uygulanır. Ekranlar bozulmasın diye büyütmenin bir sınırı var.';

  @override
  String textSizeSemantics(String name) {
    return '$name yazı boyutu';
  }

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
  String get levelIntermediateDesc =>
      'Bugünkü görünüm: teknik sinyaller, yüzdelik dilim, sağlık kartı ve başlangıçtan beri yıllık getiri.';

  @override
  String get levelAdvancedDesc =>
      'Orta + riske göre getiri, alım zamanlamanın etkisi ve düşüşten toparlanma (Özet › 1 yıl).';

  @override
  String get noAssetsYet => 'Henüz varlık eklenmemiş';

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
  String scopeCategory(String label) {
    return 'Kategori: $label';
  }

  @override
  String get retry => 'Tekrar Dene';

  @override
  String get cancel => 'Vazgeç';

  @override
  String quickAllChip(String qty) {
    return 'Hepsi ($qty)';
  }

  @override
  String get quickHolding => 'Mevcut';

  @override
  String quickAvgShort(String price) {
    return 'ort. $price';
  }

  @override
  String get quickUnitPrice => 'Birim fiyat';

  @override
  String get quickTotalCost => 'Toplam maliyet';

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
      'Fiyatlar güncellenemedi, eski veriler gösteriliyor.';

  @override
  String get otpSentPrefix => '6 haneli kodu\n';

  @override
  String get otpSentSuffix => '\nadresine gönderdik.';

  @override
  String get registerNameMissing => 'Ad soyad gir.';

  @override
  String get registerEmailInvalid => 'Geçerli bir e-posta gir.';

  @override
  String get registerPasswordsMismatch => 'Şifreler eşleşmiyor.';

  @override
  String get refreshPrices => 'Fiyatları yenile';

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
  String get dividendReceived => 'Tahsil Edilen Temettü';

  @override
  String lotSummary(int buys, int sells) {
    String _temp0 = intl.Intl.pluralLogic(
      sells,
      locale: localeName,
      other: '$buys alım · $sells çıkarma',
      zero: '$buys alım',
    );
    return '$_temp0';
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
  String get fundReportTitleUpper => 'FON KARNESİ';

  @override
  String fundReportCategory(String category, String count) {
    return '$category · $count fon';
  }

  @override
  String get fundReportPeriod1m => '1 ay';

  @override
  String get fundReportPeriodYtd => 'Yılbaşından beri';

  @override
  String get fundReportPeriod1y => '1 yıl';

  @override
  String fundReportRank(String count, String rank) {
    return '$count fondan $rank.';
  }

  @override
  String fundReportReturnVsMedian(String ret, String median) {
    return 'Getirisi $ret · kategori ortancası $median';
  }

  @override
  String fundReportAboveMedian(String pts) {
    return 'Ortancanın $pts puan üstünde';
  }

  @override
  String fundReportBelowMedian(String pts) {
    return 'Ortancanın $pts puan altında';
  }

  @override
  String get fundReportAtMedian => 'Ortancayla aynı';

  @override
  String get fundReportFootnote =>
      'Kaynak: TEFAS. Getiriler TEFAS\'ın açıkladığı rakamlardır; TEFAS\'ın hesap günleri grafikteki dönemle birebir örtüşmez, bu yüzden yukarıdaki dönem getirisinden biraz farklı olabilir. Aynı kategorideki fonlarla kıyas; geçmiş getiri gelecekteki getiriyi göstermez.';

  @override
  String fundReportPanelLine(String count, String rank, String period) {
    return 'Kategorisinde $count fondan $rank. ($period)';
  }

  @override
  String get assetTypeStock => 'Hisse';

  @override
  String get assetTypeFund => 'Fon';

  @override
  String get assetTypeFx => 'Döviz';

  @override
  String get assetTypeGold => 'Altın';

  @override
  String get assetTypeCrypto => 'Kripto';

  @override
  String get assetTypeEurobond => 'Eurobond';

  @override
  String get assetTypeCommodity => 'Emtia';

  @override
  String get assetTypeOther => 'Diğer';

  @override
  String get tickerHintStock =>
      'Örn: THYAO.IS, GARAN.IS  (Borsa İstanbul için .IS ekle)';

  @override
  String get tickerHintFund =>
      'Yahoo Finance kodu yoksa boş bırak, fiyatı elle gir';

  @override
  String get tickerHintFx => 'Örn: USDTRY=X, EURTRY=X, GBPTRY=X';

  @override
  String get tickerHintGold =>
      'Örn: XAUTRY=X (gram altın TL) veya GC=F (ons, USD)';

  @override
  String get tickerHintCrypto => 'Listeden seç, örn. BTC, ETH';

  @override
  String get tickerHintEurobond =>
      'Listeden seç ya da ISIN yaz, örn. US900123DF45';

  @override
  String get tickerHintCommodity =>
      'Örn: CL=F (petrol), NG=F (doğalgaz), GC=F (altın ons)';

  @override
  String get tickerHintOther => 'Yahoo Finance sembolü ya da boş bırak';

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
      'Şirket adı (opsiyonel, semboldan otomatik çekilir)';

  @override
  String goldSemantics(String kind) {
    return '$kind altın';
  }

  @override
  String get commissionNote =>
      'Alım-satım komisyonu maliyete eklenir; kâr/zarar gerçek rakamı gösterir.';

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
  String get notesHint => 'Notların...';

  @override
  String get txHasNote => 'Not var';

  @override
  String txOpenNote(String name) {
    return '$name işlemi, not ekle';
  }

  @override
  String txOpenNoteWithNote(String name) {
    return '$name işlemi, notu var, notu aç';
  }

  @override
  String get noteSaved => 'Not kaydedildi';

  @override
  String get noteRemoved => 'Not silindi';

  @override
  String get noteSaveFailed => 'Not kaydedilemedi';

  @override
  String get noteRemove => 'Notu sil';

  @override
  String get noteNone => 'Bu işleme not yazılmamış.';

  @override
  String get noteAddHint => 'Neden aldın, hedefin ne? Kısa bir not yaz.';

  @override
  String get alertTargetAtCurrent =>
      'Hedef güncel fiyata eşit, alarm hemen çalışır. Biraz üstünü ya da altını yaz.';

  @override
  String get notifTypeDividend => 'Temettü';

  @override
  String get dividendHistoryUpper => 'SON 12 AY TEMETTÜ';

  @override
  String dividendRecordedTotal(String amount) {
    return 'Kaydettiğin: $amount';
  }

  @override
  String dividendEventLine(String lot, String perShare) {
    return '$lot lot × $perShare';
  }

  @override
  String dividendGrossAmount(String amount) {
    return '$amount brüt';
  }

  @override
  String get dividendRecorded => 'Kaydedildi';

  @override
  String get dividendRecordAction => 'Kaydet';

  @override
  String get dividendSourceNote =>
      'Yahoo Finance\'e göre gerçekleşmiş temettüler, hak tarihindeki lotunla. Tutarlar brüt; \"Kaydet\" %15 stopaj düşülmüş neti hazır getirir, düzeltebilirsin.';

  @override
  String dividendSuggestionLine(String ticker, String date) {
    return '$ticker · hak tarihi $date';
  }

  @override
  String dividendSuggestionGross(String lot, String perShare, String gross) {
    return '$lot lot × $perShare = $gross brüt';
  }

  @override
  String dividendWithholdingAssumed(String rate, String cut, String net) {
    return 'Stopaj $rate (−$cut) düşüldü: net $net. Farklıysa düzelt.';
  }

  @override
  String dividendEnterNet(String gross) {
    return 'Brüt $gross. Stopaj sonrası eline geçeni yaz.';
  }

  @override
  String get noteReadOnlyPartner =>
      'Bu kayıt ortağına ait; notunu yalnızca o düzenleyebilir.';

  @override
  String get noteReadOnlyDeleted => 'Silinmiş kaydın notu düzenlenemez.';

  @override
  String get notesSection => 'Notlar';

  @override
  String moreNotesCount(int count) {
    return '+$count not daha · Tüm Hareketler\'de';
  }

  @override
  String get searchAssetSymbolOrNote => 'Varlık, sembol veya not ara';

  @override
  String quantitySemantics(String value) {
    return 'Miktar $value';
  }

  @override
  String get quickEntryTitle => 'Hızlı Giriş';

  @override
  String get quickEntryHelp =>
      'Her satıra bir varlık yaz. Fiyat opsiyonel; boş bırakırsan güncel fiyat otomatik çekilir.\nÖrn:  100 dolar  /  10 gram altın 4500 lira  /  GARAN 500 adet';

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
  String get pleaseWait => 'Lütfen bekle';

  @override
  String breakdownUpAmount(String amount) {
    return 'artış $amount';
  }

  @override
  String breakdownDownAmount(String amount) {
    return 'azalış $amount';
  }

  @override
  String get nominalReturnInWindow => 'Bu aralıkta senin getirin';

  @override
  String get cpiWindowNote =>
      'TÜFE ayda bir açıklanır; bu kart son açıklanan ayın sonunda biter, aralığı üstteki rakamdan farklı.';

  @override
  String rangeChip(String start, String end) {
    return '$start - $end';
  }

  @override
  String get rangeToday => 'bugün';

  @override
  String get rangeSinceFirstBuy => 'İlk alımdan bugüne';

  @override
  String sinceCpiWindowEnd(String month) {
    return '$month sonundan bugüne';
  }

  @override
  String sinceCpiWindowBody(String month, String date) {
    return 'Üstteki rakam bu süreyi içeriyor; $month TÜFE\'si açıklanınca ($date) bu kart güncellenir.';
  }

  @override
  String sinceCpiWindowBodyLate(String month) {
    return 'Üstteki rakam bu süreyi içeriyor; $month TÜFE\'si yüklenince bu kart güncellenir.';
  }

  @override
  String get demoBannerTitle => 'Örnek portföy';

  @override
  String get demoBannerSubtitle => 'Varlıklar örnek, fiyatlar canlı';

  @override
  String get demoCreateAccount => 'Hesap oluştur';

  @override
  String get demoExit => 'Örnekten çık';

  @override
  String get demoAccountCardTitle => 'Kendi portföyünü kur';

  @override
  String get demoAccountCardBody =>
      'Burada gördüğün her şey kendi varlıklarınla da çalışır. Varlık eklemek, not ve alarm kaydetmek için hesap oluştur.';

  @override
  String get demoAccountCardSignIn => 'Zaten hesabım var';

  @override
  String get demoSaveSheetTitle => 'Kaydetmek için hesap oluştur';

  @override
  String get demoSaveSheetBody =>
      'Bu bir örnek portföy; burada yaptığın değişiklik kaydedilmez. Kendi portföyünü kurmak için hesap oluştur.';

  @override
  String get demoSaveSheetContinue => 'Örneğe devam et';

  @override
  String get fundsLoadFailed => 'Fonlar yüklenemedi';

  @override
  String get searchEllipsis => 'Ara...';

  @override
  String get clearSearch => 'Aramayı temizle';

  @override
  String get pickStockPrompt => 'Listeden bir hisse seç ya da sembolünü yaz';

  @override
  String get pickStock => 'Hisse seç';

  @override
  String get pickStockTap => 'Hisse seçmek için dokun...';

  @override
  String get pickFundPrompt => 'Bir fon seç';

  @override
  String get pickFund => 'Fon seç';

  @override
  String get pickFundTap => 'Fon seçmek için dokun...';

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
  String get pickGoldTap => 'Altın türü seçmek için dokun...';

  @override
  String get goldSearchHint => 'Ara: çeyrek, 22 ayar, reşat…';

  @override
  String get goldTypes => 'Altın Türleri';

  @override
  String get goldQuickPick => 'Hızlı seçim';

  @override
  String get goldGroupGram => 'Gram';

  @override
  String get goldGroupZiynet => 'Ziynet';

  @override
  String get goldGroupSikke => 'Sikke';

  @override
  String get goldGroupOns => 'Ons';

  @override
  String get goldUnitGram => 'gr';

  @override
  String get goldUnitOunce => 'ons';

  @override
  String goldSelectedSemantics(String kind) {
    return 'Seçili altın türü: $kind. Değiştirmek için çift dokun.';
  }

  @override
  String get identityCurrency => 'Para Birimi';

  @override
  String get identityCommodity => 'Emtia';

  @override
  String noResultsFor(String q) {
    return '\"$q\" bulunamadı';
  }

  @override
  String get periodDaily => 'Bugün';

  @override
  String get period1W => '1 hf';

  @override
  String get period1M => '1 ay';

  @override
  String get period3M => '3 ay';

  @override
  String get period6M => '6 ay';

  @override
  String get period1Y => '1 yıl';

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
  String get otherTab => 'Diğer';

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
      'Bu işlem GERİ ALINAMAZ.\n\nTüm portföy kayıtların, performans geçmişin ve ortaklık bağlantıların hemen ve kalıcı olarak silinecek.\n\nDevam etmek istiyor musun?';

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
  String get feedbackHint => 'Mesajını yaz…';

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
      'Hafta sonu BIST kapalıdır. Portföyün yalnızca hisse ve fondan oluşuyorsa banner son kapanışı \"Piyasa kapalı\" etiketiyle gösterir; altın, döviz ya da kripto varsa canlı kalır.';

  @override
  String get showAmounts => 'Tutarları göster';

  @override
  String get showAmountsSubtitle =>
      'Canlı Etkinlik ve kilit ekranı widget\'ı için geçerli. Kapalıyken yalnızca günlük yüzde ve grafik görünür. Kilit ekranı telefonun açılmadan görülebildiği için varsayılan olarak kapalıdır.';

  @override
  String get lockWidgetHowTo =>
      'Kilit ekranına da ekleyebilirsin: kilit ekranına basılı tut → Özelleştir → Kilit Ekranı → widget alanına dokun → sandık.';

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
      'Kodu ortağına gönder. Ortağın kodu girince sana onay isteği gelir.';

  @override
  String get enterPartnerCode => 'Ortak Kodunu Gir';

  @override
  String get enterPartnerCodeBody =>
      'Ortağının sana gönderdiği kodu gir (örn: KRHNJ-8P2SW). Onay vermesi beklenir.';

  @override
  String tooManyAttempts(String wait) {
    return 'Çok fazla deneme. $wait sonra tekrar deneyebilirsin.';
  }

  @override
  String awaitingApproval(String name) {
    return '$name onayı bekleniyor...';
  }

  @override
  String get cancelWord => 'İptal';

  @override
  String get noPartnersYet => 'Henüz ortağın yok';

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
    return '$name ile ortaklık kuruldu.';
  }

  @override
  String get requestRejected => 'Ortaklık isteği reddedildi.';

  @override
  String get requestCancelled => 'Ortaklık isteği iptal edildi.';

  @override
  String get partnershipAccepted => 'Ortaklık kabul edildi.';

  @override
  String get sendingEllipsis => 'Gönderiliyor...';

  @override
  String waitFor(String wait) {
    return 'Bekle: $wait';
  }

  @override
  String get requestPartnership => 'Ortaklık İste';

  @override
  String get generatingEllipsis => 'Üretiliyor...';

  @override
  String get generateCode => 'Kod Üret';

  @override
  String get tabChart => 'Grafik';

  @override
  String get tabSummary => 'Özet';

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
  String get youngPortfolioTitle => 'Bu dönem için henüz geçmiş yok';

  @override
  String get youngPortfolioBody =>
      'Portföyün seçtiğin dönemden daha yeni. Grafik işlem günleri geçtikçe dolacak. Bugünkü hareketi “Bugün” görünümünde görebilirsin.';

  @override
  String get forceUpdateTitle => 'Güncelleme gerekli';

  @override
  String get forceUpdateBody =>
      'Sandık\'ın bu sürümü artık desteklenmiyor. Devam etmek için uygulamayı güncelle; verilerin yerinde.';

  @override
  String get forceUpdateButton => 'Güncelle';

  @override
  String get serverMovedTitle => 'Sandık yenilendi';

  @override
  String get serverMovedBodyAndroid =>
      'Daha hızlı sunucumuza geçtik. Devam etmek için uygulamayı kapatıp yeniden aç. Bir kez giriş yapman istenecek; şifren ve verilerin aynı.';

  @override
  String get serverMovedBodyIos =>
      'Daha hızlı sunucumuza geçtik. Devam etmek için uygulamayı kapatıp (yukarı kaydırarak) yeniden aç. Bir kez giriş yapman istenecek; şifren ve verilerin aynı.';

  @override
  String get serverMovedCloseButton => 'Uygulamayı kapat';

  @override
  String noHistoryTypeBody(String type) {
    return '$type için fiyat geçmişi izlenmiyor. Değeri portföy toplamına dahil, ama zaman grafiği çizilemiyor.';
  }

  @override
  String get simModeTitle => 'Bugünkü portföyle';

  @override
  String get simModeBody =>
      'Bugünkü net portföyünü seçili dönem boyunca elinde tutmuş olsaydın grafik nasıl görünürdü? Geçmişteki alım/satış kararlarını yok sayar, sadece güncel pozisyonun fiyat değişimini gösterir.';

  @override
  String get portfolioPerformance => 'Portföy Performans';

  @override
  String get chartDataFailed => 'Grafik verisi alınamadı';

  @override
  String get chartDataFailedBody =>
      'Fiyat geçmişi şu an getirilemedi. Bağlantını kontrol edip tekrar deneyebilirsin.';

  @override
  String intradayMissingBody(String names) {
    return '$names için gün içi fiyat verisi alınamadı. Bu varlıklar grafikte son bilinen fiyatlarıyla SABİT çizildi. Çizginin düz olması piyasanın durgun olduğu anlamına gelmez.';
  }

  @override
  String get retryLower => 'Tekrar dene';

  @override
  String get raceUpper => 'YARIŞ';

  @override
  String get changeByTypeUpper => 'TÜRE GÖRE · FİYAT ETKİSİ';

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
  String chartTxBuy(String when, String price) {
    return 'Alım $when · $price';
  }

  @override
  String chartTxSell(String when, String price) {
    return 'Satış $when · $price';
  }

  @override
  String get tradeVolumeUpper => 'ALIM · SATIŞ';

  @override
  String crosshairNetBuy(String amount) {
    return 'Net alım +$amount';
  }

  @override
  String crosshairNetSell(String amount) {
    return 'Net satış −$amount';
  }

  @override
  String get crosshairNetFlat => 'Net değişim yok';

  @override
  String crosshairTxCount(int count) {
    return '$count işlem';
  }

  @override
  String crosshairBuySellDetail(String buy, String sell) {
    return 'Alım $buy · Satış $sell';
  }

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
  String get last3MonthsPeriod => 'son 3 ay';

  @override
  String get threeMonthExtremes => 'Üç ayın uçları';

  @override
  String get last5YearsPeriod => 'son 5 yıl';

  @override
  String get fiveYearExtremes => 'Beş yılın uçları';

  @override
  String get fiveYearCurve => 'Beş yıl eğrisi';

  @override
  String moneyReturnPeriod(String period) {
    return 'Paranın getirisi · $period';
  }

  @override
  String get whereItCameFrom => 'Nereden geldi';

  @override
  String get periodStart => 'Dönem başı';

  @override
  String get yourContribution => 'Net katkın';

  @override
  String get marketWord => 'Piyasa';

  @override
  String get cashDividend => 'Bunun nakit temettüsü';

  @override
  String get commissionPaid => 'Ödenen komisyon';

  @override
  String get contributionNotReturn =>
      'Yüzde yalnızca fiyat etkisinden hesaplanır. Nakit temettü de getiriye dahildir; cebine girdiği için köprüde ayrı satırda, çıkış olarak durur.';

  @override
  String annualRatePct(String pct) {
    return '$pct yıllık';
  }

  @override
  String periodTotalPct(String pct) {
    return 'Dönem toplamı $pct';
  }

  @override
  String get periodCourse => 'Dönem içi seyir';

  @override
  String greenDaysOfTotal(int total, int up) {
    return '$total işlem gününün $up\'ü artıda kapandı.';
  }

  @override
  String get againstInflation => 'Enflasyona karşı';

  @override
  String get nominalReturn => 'Senin getirin';

  @override
  String cpiWindowRange(String start, String end) {
    return 'Ölçüm aralığı: $start - $end';
  }

  @override
  String cpiWindowMonth(String month) {
    return 'Ölçülen ay: $month';
  }

  @override
  String get periodCpi => 'Enflasyon (TÜFE)';

  @override
  String get pointDifference => 'Aradaki fark';

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
      'Portföyünün değeri yıl boyunca ortalama bu ölçüde dalgalandı. Yüksek olması iyi ya da kötü değil; daha çok inip çıktığı anlamına gelir.';

  @override
  String get concentration => 'Yoğunlaşma';

  @override
  String get moneyReturnAnnual => 'Başlangıçtan beri (yıllık)';

  @override
  String get xirrBody =>
      'Yatırdığın paranın, yatırdığın TARİHLER dikkate alınarak hesaplanan yıllık bileşik getirisi.';

  @override
  String get periodMarketReturnLabel => 'Seçili dönemin getirisi';

  @override
  String get xirrVsMarketBody =>
      'İki sayı çelişmez: üstteki ilk alımından bugüne, alım zamanlarını da hesaba katarak ölçer; alttaki yalnızca seçili dönemde piyasanın hareketini ölçer.';

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
  String portfolioLineInfoDaily(String name) {
    return 'Günlük görünümde $name çizgisi gerçek değerini gösterir: Performans ekranındaki günlük grafiğin aynısı.';
  }

  @override
  String portfolioLineInfoSim(String name) {
    return 'Haftalık ve daha uzun dönemlerde $name çizgisi bir simülasyondur: bugünkü varlıklarını dönem başından beri tutsaydın ne olurdu. Alım-satım tarihlerin hesaba katılmaz; gerçekleşmiş getirin değildir. Böylece izlediğin varlıklarla aynı pencerede kıyaslanır.';
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
  String get addAssetsToCompare => 'Karşılaştırmak için varlık ekle';

  @override
  String get addAssetsToCompareBody =>
      'Portföyünde olmayan varlıkları da ekleyebilirsin.';

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
      'Portföyler hesaplanan serilerdir, piyasada kote değiller. Getirileri, tıpkı bir varlık gibi dönem başına göre yüzde olarak çizilir.';

  @override
  String get portfolioActivityTitle => 'Portföy Hareketleri';

  @override
  String get clearFilters => 'Filtreleri temizle';

  @override
  String watchlistRowUp(String pct) {
    return 'artış $pct';
  }

  @override
  String watchlistRowDown(String pct) {
    return 'düşüş $pct';
  }

  @override
  String get watchlistRowFollowing => 'takip ediliyor';

  @override
  String notificationsNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count yeni bildirim',
      one: '1 yeni bildirim',
    );
    return '$_temp0';
  }

  @override
  String get signOutAction => 'Çıkış yap';

  @override
  String get baseCurrencyNameLira => 'Lira';

  @override
  String get baseCurrencyNameDollar => 'Dolar';

  @override
  String get baseCurrencyNameEuro => 'Euro';

  @override
  String get baseCurrencyNameGold => 'Gram altın';

  @override
  String get datePickerHelp => 'Tarih seç';

  @override
  String get datePickerConfirm => 'Seç';

  @override
  String get sortAssetsSemantics => 'Varlıkları sırala';

  @override
  String get showDetailsSemantics => 'Ayrıntıları göster';

  @override
  String get hideDetailsSemantics => 'Ayrıntıları gizle';

  @override
  String pricePreviewClose(String date) {
    return '$date kapanışı. Kayıtta bu fiyat kullanılacak';
  }

  @override
  String pricePreviewLastTradingClose(String date) {
    return 'Son işlem günü kapanışı ($date). Kayıtta bu fiyat kullanılacak';
  }

  @override
  String priceAssignedClose(String date, String price) {
    return '$date kapanışı $price olarak atandı';
  }

  @override
  String priceAssignedLastTradingClose(String date, String price) {
    return 'Son işlem günü ($date) kapanışı $price olarak atandı';
  }

  @override
  String todayRealAhead(String pts) {
    return '$pts puan önde';
  }

  @override
  String todayRealBehind(String pts) {
    return '$pts puan geride';
  }

  @override
  String get todayRealEven => 'başa baş';

  @override
  String recapPointsAhead(String n) {
    return 'Enflasyonu $n puan geçtin';
  }

  @override
  String recapPointsBehind(String n) {
    return 'Enflasyonun $n puan gerisinde kaldın';
  }

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
  String get selectedPeriodReturn => 'Seçimlerinin getirisi';

  @override
  String get depositsDontChangeRank => 'Para eklemek sıralamayı değiştirmez';

  @override
  String get everyoneMeasuredSame => 'Herkes aynı şekilde ölçülür';

  @override
  String get rankVsPortfolioNote =>
      'Kendi satırının altındaki \"Paranın getirisi\" Performans ekranındaki sayıdır: ne zaman, ne kadar para eklediğini de hesaba katar. Sıralama ise yalnız seçimlerini ölçer; iki sayı farklı olabilir.';

  @override
  String get rankSwapNote =>
      'Yeni katılan, yalnız portföyünü tuttuğu süre kadar ölçülür. Fiyat geçmişi bulunamayan portföyler sıralamada yer almaz.';

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
      'Kimsenin varlık listesi paylaşılmaz, yalnız getiri yüzdeleri sıralanır.';

  @override
  String get yourReturnUpper => 'SEÇİMLERİNİN GETİRİSİ';

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
      'Yeterli katılımcı olunca sıran açılacak. Anonim, KVKK uyumlu';

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
      'Dönem günlere bölünür. Her gün, o gün elinde olan varlıklar piyasa fiyatıyla değerlenir ve günlerin getirisi birbirine eklenir (çarpılır).\n\nSatıp başka bir varlık aldıysan ikisi de yalnız tuttuğun günlerde sayılır. Yukarıdaki dönem seçimi sonucu doğrudan değiştirir.';

  @override
  String get depositsDontChangeRankBody =>
      'Ölçülen şey seçimlerin: hangi varlığı, hangi günler tuttuğun. Ne zaman ve ne kadar para eklediğin oranı ETKİLEMEZ; 1 lot da tutsan 10.000 lot da tutsan aynı seçim aynı yüzdeyi verir.\n\nGirdiğin alış fiyatı kullanılmaz; her şey piyasa fiyatıyla değerlenir.';

  @override
  String get everyoneMeasuredSameBody =>
      'Sen ve ortakların aynı formülle, aynı fiyatlarla hesaplanırsınız; hesap bu cihazda yapılır. Ortaklar arasında girdiğin tarih geçerlidir: CSV ya da ekstreyle içe aktardığın geçmiş hemen sayılır.\n\nSıralamaya girmek için en az 30 günlük geçmiş gerekir. Anonim sıralamalarda (Zirve, genel) bugünden 3 günden fazla geriye tarihli girilen alım ya da satış, girildiği gün yapılmış sayılır.';

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
    return 'Bir yılın kısa hikâyesi: $character';
  }

  @override
  String medianAhead(String pts) {
    return 'medyandan $pts puan önde';
  }

  @override
  String get returnRanking => 'Getiri sıralaması';

  @override
  String returnRankingWith(String detail) {
    return 'Getiri sıralaması · $detail';
  }

  @override
  String percentileSemantics(int pct, String detail) {
    return 'Son 30 günde katılımcıların yüzde $pct kadarının üstündesin. $detail';
  }

  @override
  String get last30DaysLike => 'Son 30 günde senin gibi ';

  @override
  String nPeople(int n) {
    return '$n kişi';
  }

  @override
  String medianBehind(String pts) {
    return 'medyandan $pts puan geride';
  }

  @override
  String get lastYearInflation => 'Son bir yılda enflasyonun ';

  @override
  String pointsAhead(String pts) {
    return '$pts puan önündesin';
  }

  @override
  String pointsBehind(String pts) {
    return '$pts puan gerisindesin';
  }

  @override
  String get noChangeLower => 'değişim yok';

  @override
  String get totalNetHidden => 'Toplam net varlık gizli';

  @override
  String totalNetWorth(String amount) {
    return 'Toplam net varlık $amount';
  }

  @override
  String get realisedFromSales => 'Satışlardan gerçekleşen: ';

  @override
  String get includedDividend => 'Bunun temettüsü: ';

  @override
  String deletedNRecords(int n) {
    return 'Silindi · $n kayıt';
  }

  @override
  String get txDeleted => 'Silindi';

  @override
  String get txVoided => 'silindi';

  @override
  String get seeAllShort => 'Tümünü gör';

  @override
  String nTransactions(int n) {
    return '$n hareket';
  }

  @override
  String get txSell => 'Satım';

  @override
  String get txDividend => 'Temettü';

  @override
  String get txBuy => 'Alım';

  @override
  String get gainWord => 'kazanç';

  @override
  String get costBasisGain => 'Maliyetine göre kâr';

  @override
  String get costBasisLoss => 'Maliyetine göre zarar';

  @override
  String get lossWord => 'kayıp';

  @override
  String get realisedFromSalesSemantics => 'satışlardan gerçekleşen ';

  @override
  String get raceNoPartnerBody =>
      'Henüz ortağın yok. Kendi dönem getirini ve küresel dilimini şimdiden görebilirsin.';

  @override
  String get viewWord => 'Gör';

  @override
  String get newUpper => 'YENİ';

  @override
  String get racePitch =>
      'Ortaklarınla getiri sıralaması. Kim daha iyi kazanıyor?';

  @override
  String get joinWord => 'Katıl';

  @override
  String get raceCalculating => 'Yarış hesaplanıyor…';

  @override
  String rankFirst(String period) {
    return '$period sıralamada 1.\'sin';
  }

  @override
  String rankNth(String period, String rank) {
    return '$period sıralamada $rank sıradasın';
  }

  @override
  String widenTheGap(String gap) {
    return 'Farkı büyüt, ikinci +$gap% geride';
  }

  @override
  String get atTheTop => 'Zirvedesin, farkı koru';

  @override
  String toPassPerson(String name, String diff) {
    return '$name\'i geçmen için +$diff%';
  }

  @override
  String get higherInOtherPeriods =>
      'Diğer periyotlarda daha üsttesin. Dokun, bak';

  @override
  String get deleteAssetTitle => 'Varlığı Sil';

  @override
  String deleteAssetMulti(String name, int n) {
    return '\"$name\" için $n işlem kaydı (alım/satım/temettü) kalıcı olarak silinsin mi?';
  }

  @override
  String deleteAssetSingle(String name) {
    return '\"$name\" kalıcı olarak silinsin mi?';
  }

  @override
  String get deleteAnyway => 'Yine de sil';

  @override
  String get deleteAssetWarning =>
      'Bu bir satış değil. Varlık portföyden çıkar, toplamlardan ve geçmiş grafiğinden düşer. İşlem kayıtları \"Portföy Hareketleri\"nde kalır. Sattıysan bunun yerine \"Sat\" kullan; realize kâr/zararın hesaba dahil olur.';

  @override
  String alarmAlsoDeleteTitle(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n alarm da silinsin mi?',
      one: 'Alarm da silinsin mi?',
    );
    return '$_temp0';
  }

  @override
  String alarmAlsoDeleteBody(int n, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$name silindi. Bu sembol için kurduğun $n alarm duruyor. Portföyünde olmasa da fiyatı izlemeye devam edebilirler.',
      one:
          '$name silindi. Bu sembol için kurduğun alarm duruyor. Portföyünde olmasa da fiyatı izlemeye devam edebilir.',
    );
    return '$_temp0';
  }

  @override
  String alarmAlsoDeleteConfirm(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Alarmları sil',
      one: 'Alarmı sil',
    );
    return '$_temp0';
  }

  @override
  String get alarmKeep => 'Alarm kalsın';

  @override
  String get alarmDeleteFailed => 'Alarmlar silinemedi';

  @override
  String get assetDeleted => 'Varlık silindi';

  @override
  String get undoFailed => 'Geri alınamadı';

  @override
  String get enterValidAmount => 'Geçerli bir tutar gir';

  @override
  String get dividendSaved => 'Temettü kaydedildi';

  @override
  String get dividendPayDate => 'Temettü ödeme tarihi';

  @override
  String get addDividend => 'Temettü Ekle';

  @override
  String netAmountReceived(String name) {
    return '$name · ele geçen net tutar';
  }

  @override
  String paymentDate(String date) {
    return 'Ödeme tarihi: $date';
  }

  @override
  String get dividendNote =>
      'Temettü miktarı değiştirmez; toplam getirine eklenir.';

  @override
  String get enterValidQuantity => 'Geçerli bir miktar gir';

  @override
  String get enterValidUnitPrice => 'Geçerli bir birim fiyat gir';

  @override
  String cannotExceedQuantity(String qty) {
    return 'Mevcut miktarı ($qty) aşamazsın';
  }

  @override
  String get depositAmountLabel => 'Tutar';

  @override
  String cannotExceedBalance(String amount) {
    return 'Mevcut bakiyeyi ($amount) aşamazsın';
  }

  @override
  String boughtAmount(String qty, String unit) {
    return '$qty $unit alındı';
  }

  @override
  String soldAmount(String qty, String unit) {
    return '$qty $unit satıldı';
  }

  @override
  String transactionFailed(String error) {
    return 'İşlem başarısız. $error';
  }

  @override
  String get sellAllWarning =>
      'Tüm miktarı satıyorsun. Pozisyon listeden kalkar ama bu bir satış kaydı olarak durur. İşlem geçmişin ve realize kâr/zararın korunur. Kaydı tamamen silmek istiyorsan varlık detayından \"Sil\"i kullan.';

  @override
  String get saleValue => 'Satış değeri';

  @override
  String get noPriceAlert => 'Fiyat alarmı yok';

  @override
  String nActiveAlerts(int n) {
    return '$n aktif fiyat alarmı';
  }

  @override
  String get deleteAlertTitle => 'Alarmı sil';

  @override
  String deleteAlertAbove(String price) {
    return '$price üstüne çıkınca alarmı silinsin mi?';
  }

  @override
  String triggeredAlertSemantics(String price) {
    return 'Çalışmış alarm $price, yeniden kurmak için dokun';
  }

  @override
  String alertAboveSemantics(String price) {
    return 'Üstüne çıkınca $price, silmek için dokun';
  }

  @override
  String alertTriggered(String price) {
    return '$price · çalıştı';
  }

  @override
  String deleteAlertBelow(String price) {
    return '$price altına inince alarmı silinsin mi?';
  }

  @override
  String alertBelowSemantics(String price) {
    return 'Altına inince $price, silmek için dokun';
  }

  @override
  String get addAssetFirst =>
      'Önce portföyüne ya da takip listene bir varlık ekle.';

  @override
  String alertSetAbove(String name, String price) {
    return '$name için alarm kuruldu: $price üstüne çıkınca';
  }

  @override
  String get alertSetFailed => 'Alarm kurulamadı';

  @override
  String get enterValidPrice => 'Geçerli bir fiyat gir';

  @override
  String alertForAsset(String name) {
    return '$name için alarm';
  }

  @override
  String currentlyPrice(String price) {
    return 'Şu an $price';
  }

  @override
  String get currentPriceUnknown => 'Güncel fiyat bilinmiyor';

  @override
  String targetPctSemantics(String sign, int pct) {
    return 'Hedef yüzde $sign $pct';
  }

  @override
  String get notifyWhenAbove => 'Fiyat bu seviyeye çıkınca haber vereceğiz.';

  @override
  String get notifyWhenBelow => 'Fiyat bu seviyeye inince haber vereceğiz.';

  @override
  String get setAlert => 'Alarmı kur';

  @override
  String alertSetBelow(String name, String price) {
    return '$name için alarm kuruldu: $price altına inince';
  }

  @override
  String get plusWord => 'artı';

  @override
  String get minusWord => 'eksi';

  @override
  String get widgetStepHold => 'Ana ekranda boş bir yere basılı tut';

  @override
  String get widgetStepPlus => 'Sol üstteki + işaretine dokun';

  @override
  String get widgetStepPickIos => 'Listeden \"sandık\"ı seç ve ekle';

  @override
  String get widgetStepPickAndroid => '\"sandık\"ı bulup ana ekrana sürükle';

  @override
  String get widgetInstallTitle => 'Portföyünü ana ekranda gör';

  @override
  String get widgetInstallBody =>
      'Uygulamayı açmadan toplamını ve günlük değişimini görürsün.';

  @override
  String get gotIt => 'Anladım';

  @override
  String get widgetStepWidgetsTab => '\"Widget\'lar\"a dokun';

  @override
  String get disclaimerText =>
      'Bu uygulama yalnızca bilgilendirme amaçlıdır. Gösterilen veriler, analizler ve bildirimler kesinlikle yatırım tavsiyesi, alım-satım önerisi veya finansal danışmanlık niteliği taşımaz. Yatırım kararlarınızı yetkili bir mali danışmana danışarak veriniz. Geçmiş performans gelecekteki sonuçları garanti etmez.';

  @override
  String get justNow => 'az önce';

  @override
  String minutesAgo(int n) {
    return '$n dk önce';
  }

  @override
  String hoursAgo(int n) {
    return '$n sa önce';
  }

  @override
  String daysAgo(int n) {
    return '$n gün önce';
  }

  @override
  String get signalCalculating => 'Sinyal hesaplanıyor…';

  @override
  String get trendUp => 'YUKARI TREND';

  @override
  String get trendDown => 'AŞAĞI TREND';

  @override
  String get trendFlat => 'YATAY';

  @override
  String indicatorsConfidence(int lehte, int total, int pct) {
    return '$lehte/$total yön veren gösterge · güven %$pct';
  }

  @override
  String confidenceOnly(int pct) {
    return 'güven %$pct';
  }

  @override
  String get technicalOutlookUpper => 'TEKNİK GÖRÜNÜM';

  @override
  String get nowUpper => 'ŞU AN';

  @override
  String get arrowUp => '▲ yukarı';

  @override
  String get arrowDown => '▼ aşağı';

  @override
  String get arrowFlat => '◆ yatay';

  @override
  String get indicatorsCalculating => 'Göstergeler hesaplanıyor…';

  @override
  String get indicatorsNoHistory =>
      'Bu varlığın fiyat geçmişi şu an çekilemedi, göstergeler hesaplanamıyor.';

  @override
  String get noIndicatorsSelected =>
      'Bu varlık türü için hiçbir gösterge seçilmemiş. Profil → Sinyal Ayarları\'ndan aktifleştir.';

  @override
  String get technicalAnalysisUpper => 'TEKNİK ANALİZ';

  @override
  String nOfMIndicators(int on, int all) {
    return '· $on/$all gösterge açık';
  }

  @override
  String get configureIndicators => 'Göstergeleri Ayarla';

  @override
  String buySellNeutralCounts(int buy, int sell, int neutral) {
    return '$buy AL · $sell SAT · $neutral NÖTR';
  }

  @override
  String get confidenceWord => 'güven';

  @override
  String csvRowsAddedToCart(int n) {
    return '$n satır sepete eklendi';
  }

  @override
  String get csvImportTitle => 'Ekstreden içe aktar';

  @override
  String get csvImportBody =>
      'Aracı kurum ya da banka ekstreni (PDF, Excel veya CSV) dosyadan seç ya da tabloyu kopyalayıp yapıştır. Sütunların adı ve sırası önemli değil: sembol, adet, fiyat, tarih ve alış/satış kendiliğinden bulunur. Alışlar ve satışlar tarihleriyle birlikte gelir.';

  @override
  String get pasteHere => 'Buraya yapıştır';

  @override
  String get importPickFile => 'Dosyadan seç (PDF, Excel, CSV)';

  @override
  String get importReading => 'Dosya okunuyor…';

  @override
  String get importMappingTitle => 'Sütunlar böyle eşlendi';

  @override
  String get importLowConfidence =>
      'Bu dosyanın sütunlarından tam emin değiliz; eşlemeyi kontrol et, gerekirse düzelt.';

  @override
  String get importFixColumns => 'Sütunları düzelt';

  @override
  String get importCopyDiagnostic => 'Tanılama metnini kopyala';

  @override
  String get importDiagnosticHint =>
      'Okunamayan ekstreyi düzeltebilmemiz için tablonun yapısını kopyalar. Ad, numara ve tutarlar maskelenir.';

  @override
  String get importDiagnosticCopied => 'Tanılama metni kopyalandı.';

  @override
  String get importAiButton => 'Yapay zekâyla eşle';

  @override
  String get importAiHint =>
      'Tablonun yalnız yapısı gönderilir: ad, numara ve tutarlar gizlenir, belge telefonundan çıkmaz.';

  @override
  String get importAiSuggested =>
      'Sütunları yapay zekâ önerdi; eşlemeyi kontrol et, gerekirse düzelt.';

  @override
  String get importAiNoMatch =>
      'Yapay zekâ da bu dosyada varlık tablosu bulamadı.';

  @override
  String get importAiLimit =>
      'Bugünlük yapay zekâ eşleme hakkın doldu; yarın yeniden dene.';

  @override
  String get importAiFailed =>
      'Yapay zekâ eşlemesi şu an yapılamadı. Biraz sonra yeniden dene.';

  @override
  String importTradesApplied(int count) {
    return '$count varlığın gerçek alış tarihi ve fiyatı hesap hareketlerinden alındı.';
  }

  @override
  String importDepositRow(String name, String amount, String rate, int days) {
    return '$name · $amount · $rate faiz · $days gün vade';
  }

  @override
  String importFundNotRecognized(String name) {
    return 'Fon tanınmadı, eklenmedi: $name';
  }

  @override
  String get importFundListFailed =>
      'TEFAS fon listesi alınamadı; adıyla yazılmış fonlar eklenemedi. Bağlantını kontrol edip dosyayı yeniden seç.';

  @override
  String importDepositsFound(int n) {
    return '$n vadeli mevduat bulundu (vadesiz hesaplar alınmaz)';
  }

  @override
  String importStatementDate(String date) {
    return 'Ekstre tarihi $date: fonların maliyeti o günkü birim fiyat sayıldı.';
  }

  @override
  String cartDepositSubtitle(String rate, int days) {
    return 'Vadeli · $rate · $days gün';
  }

  @override
  String get importColumnNone => 'Yok';

  @override
  String get importApply => 'Uygula';

  @override
  String get importOrPaste => 'ya da tabloyu yapıştır';

  @override
  String get preview => 'Önizle';

  @override
  String csvRowsRead(int n) {
    return '$n satır okundu';
  }

  @override
  String csvRowsSkipped(int n) {
    return ', $n satır atlandı';
  }

  @override
  String get closePriceWillBeFetched => 'kapanış çekilecek';

  @override
  String get unitPiece => 'adet';

  @override
  String assetLimitReachedFor(String name) {
    return '$name: varlık limitine ulaşıldı';
  }

  @override
  String get someAssetsNotAdded => 'Bazı Varlıklar Eklenemedi';

  @override
  String bulkAddSavingProgress(int saved, int total) {
    return 'Kaydediliyor $saved / $total';
  }

  @override
  String bulkAddPartialResult(int saved, int failed) {
    return '$saved varlık eklendi, $failed varlık eklenemedi. Eklenemeyenler sepette duruyor; tekrar denersen yalnızca onlar eklenir.';
  }

  @override
  String importSellExceedsHolding(String name) {
    return '$name: satış miktarı o tarihte elindekinden fazla; kaydedilmedi.';
  }

  @override
  String importSellNoPrice(String name) {
    return '$name: satış fiyatı bulunamadı; fiyatı yazıp tekrar dene.';
  }

  @override
  String get cartSellTag => 'Satış';

  @override
  String get kapLinkLabel => 'KAP bildirimleri';

  @override
  String get kapLinkHint => 'Şirketin KAP sayfası tarayıcıda açılır';

  @override
  String get kapLinkFailed =>
      'KAP sayfası açılamadı. İnternet bağlantını kontrol et.';

  @override
  String get clearCartConfirm =>
      'Sepetteki tüm varlıklar silinecek. Emin misin?';

  @override
  String get pasteCsv => 'CSV yapıştır';

  @override
  String get cartEmpty => 'Sepet boş';

  @override
  String get cartEmptyBody =>
      'Aşağıdaki + Varlık Ekle butonuyla art arda varlık ekleyip hepsini tek seferde kaydedebilirsin.';

  @override
  String get pasteFromStatement => 'Ekstreden içe aktar (PDF, Excel, CSV)';

  @override
  String saveAllCount(int n) {
    return 'Tümünü Kaydet ($n)';
  }

  @override
  String get removeFromWatchlist => 'Takipten çıkar';

  @override
  String removeFromWatchlistConfirm(String name) {
    return '$name takip listenden kaldırılsın mı?';
  }

  @override
  String get removeWord2 => 'Çıkar';

  @override
  String get removeFromWatchlistFailed =>
      'Takipten çıkarılamadı. Bağlantını kontrol et.';

  @override
  String get currentPriceUpper => 'GÜNCEL FİYAT';

  @override
  String periodNoChange(String period) {
    return '$period · değişim yok';
  }

  @override
  String get unitPriceDiffNote =>
      'Değişim birim fiyat farkıdır; bu varlığa sahip değilsin.';

  @override
  String get notEnoughHistoryForAsset =>
      'Bu varlık için yeterli fiyat geçmişi yok.';

  @override
  String get notInYourPortfolio => 'Bu varlık portföyüne dahil değildir.';

  @override
  String get searchingEllipsis => 'Aranıyor…';

  @override
  String get startTypingToSearch => 'Aramak için yazmaya başla.';

  @override
  String noResultForQuery(String q) {
    return '\"$q\" için sonuç yok.';
  }

  @override
  String get inYourPortfolioUpper => 'PORTFÖYÜNDE';

  @override
  String get searchAllAssetsHint =>
      'Hisse, fon, endeks, emtia, döviz veya altın ara';

  @override
  String alreadyInPortfolio(String name) {
    return '$name, zaten portföyünde';
  }

  @override
  String addedToWatchlist(String name) {
    return '$name takibe alındı';
  }

  @override
  String get watchlistInListLabel => 'Takipte';

  @override
  String get watchlistFullShort => 'Dolu';

  @override
  String watchlistCountOfLimit(int n, int limit) {
    return '$n/$limit takipte';
  }

  @override
  String get watchlistAddShort => 'Ekle';

  @override
  String watchlistLimitReached(int n) {
    return 'En fazla $n varlık takip edebilirsin. Yeni eklemek için birini çıkar.';
  }

  @override
  String watchlistLimitFree(int n) {
    return 'Ücretsiz planda en fazla $n varlık takip edebilirsin.';
  }

  @override
  String get partnershipAcceptedShort => 'Ortaklık kabul edildi.';

  @override
  String get partnershipRejectedShort => 'Ortaklık isteği reddedildi.';

  @override
  String get partnershipApprovalTitle => 'Ortaklık Onayı';

  @override
  String get partnershipApprovalBody =>
      'Ortaklık kodunu giren kişileri buradan görüp onaylayabilirsin.';

  @override
  String get noPendingRequests => 'Bekleyen ortaklık isteği yok.';

  @override
  String get userWord => 'Kullanıcı';

  @override
  String get enteredYourCode => 'Ortaklık kodunuzu girdi ve onay bekliyor.';

  @override
  String get portfolioChange => 'Portföy değişimi';

  @override
  String aheadOfInflationPts(String pts) {
    return 'Enflasyonun $pts puan önünde';
  }

  @override
  String betterThanPctInvestors(int pct) {
    return 'Yatırımcıların %$pct\'inden iyi';
  }

  @override
  String nDaysTracked(int n) {
    return '$n gün takip';
  }

  @override
  String get trackingWithSandik => 'sandık ile takip ediyorum';

  @override
  String get shareCardNoAmounts =>
      'Kartta tutar yok; yalnızca yüzde ve etiketler.';

  @override
  String get preparingEllipsis => 'Hazırlanıyor…';

  @override
  String get shareAsImage => 'Görsel olarak paylaş';

  @override
  String get shareAsText => 'Metin olarak paylaş';

  @override
  String behindInflationPts(String pts) {
    return 'Enflasyonun $pts puan gerisinde';
  }

  @override
  String get assetNotFound => 'Varlık bulunamadı';

  @override
  String get myMarketReturn => 'Piyasa getirim';

  @override
  String get dataExported =>
      'Verilerin JSON dosyası olarak hazırlandı ve paylaşıldı.';

  @override
  String mailAppFailed(String email) {
    return 'Mail uygulaması açılamadı. Lütfen $email adresine yaz.';
  }

  @override
  String get notifSubtitleIos =>
      'Sinyaller, fiyat alarmları, sessiz saatler, Canlı Etkinlik';

  @override
  String get notifSubtitleAndroid =>
      'Sinyaller, fiyat alarmları, sessiz saatler';

  @override
  String get alertSetFromAssetScreen => 'Varlık ekranındaki zil ile kurulur';

  @override
  String get sessionTimedOut =>
      'Güvenlik için oturumun kapatıldı. Ayarlar › Gizlilik\'ten kilidi açarsan bir daha kapanmaz.';

  @override
  String lockOfferTitle(String yontem) {
    String _temp0 = intl.Intl.selectLogic(
      yontem,
      {
        'faceId': 'Face ID ile koru',
        'touchId': 'Touch ID ile koru',
        'biyometrik': 'Biyometrik kilitle koru',
        'other': 'Ekran kilidiyle koru',
      },
    );
    return '$_temp0';
  }

  @override
  String get lockOfferBody =>
      'Portföyün cebinde. Kilit açıkken uygulama araya girmeden seni tanır.';

  @override
  String get lockOfferBenefitStay => 'Oturumun kapanmaz';

  @override
  String get lockOfferBenefitStayBody =>
      'Kilit kapalıyken uygulamayı 10 dakika bırakınca güvenlik için çıkış yapılıyor ve şifreni yeniden girmen gerekiyor. Kilit açıkken oturumun yerinde kalır.';

  @override
  String get lockOfferBenefitPush => 'Bildirimlerin kesilmez';

  @override
  String get lockOfferBenefitPushBody =>
      'Çıkış yapılınca fiyat alarmların ve günlük özetin de susar. Kilit açıkken gelmeye devam eder.';

  @override
  String get lockOfferBenefitPrivacy => 'Portföyün görünmez';

  @override
  String get lockOfferBenefitPrivacyBody =>
      'Telefonun başkasının eline geçerse tutarların senin doğrulaman olmadan açılmaz.';

  @override
  String lockOfferAccept(String yontem) {
    String _temp0 = intl.Intl.selectLogic(
      yontem,
      {
        'faceId': 'Face ID\'yi aç',
        'touchId': 'Touch ID\'yi aç',
        'biyometrik': 'Biyometrik kilidi aç',
        'other': 'Uygulama kilidini aç',
      },
    );
    return '$_temp0';
  }

  @override
  String get lockOfferDecline => 'Şimdi değil';

  @override
  String get lockOfferLater =>
      'Bunu sonra Ayarlar › Gizlilik\'ten açabilirsin.';

  @override
  String get noBiometricOnDevice =>
      'Bu cihazda biyometrik doğrulama ya da PIN tanımlı değil.';

  @override
  String get biometricPrompt =>
      'Biyometrik kilidi açmak için kimliğini doğrula';

  @override
  String get rateNotFetched =>
      'Kur henüz çekilmedi; tutarlar şimdilik ₺ görünür.';

  @override
  String baseCurrencyNote(String unit) {
    return 'Tutarlar bugünkü kurla $unit cinsinden gösterilir; hesaplar ₺ üzerinden yapılır.';
  }

  @override
  String get startHour => 'Başlangıç saati';

  @override
  String get endHour => 'Bitiş saati';

  @override
  String get liveActivityIosNote =>
      'iOS, Live Activity oturumunu en fazla 8 saat açık tutar. Uygulamayı açtıkça süre yenilenir; hiç açmazsanız kilit ekranından düşebilir.';

  @override
  String get marketClosedNote =>
      'Borsa kapalıyken hisse ve fonlar son kapanıştan, altın, döviz ve kripto canlı gösterilir.';

  @override
  String get hiddenWeekend =>
      'Şu an görünmüyor: hafta sonu gösterimi kapalı. Açmak için yukarıdaki anahtarı kullan.';

  @override
  String hiddenOutsideWindow(String start, String end) {
    return 'Şu an görünmüyor: saat $start-$end aralığının dışındasın. Banner $start\'da görünecek. Hemen görmek için \"Gün boyu göster\"i aç.';
  }

  @override
  String get quietStart => 'Sessizlik başlangıcı';

  @override
  String get quietEnd => 'Sessizlik bitişi';

  @override
  String quietHoursOn(String start, String end) {
    return 'Brifing, özet, takvim ve alarm push\'ları $start-$end arası gönderilmez';
  }

  @override
  String get quietHoursOff =>
      'Gece belirli saatlerde hiçbir proaktif bildirim gelmesin';

  @override
  String get passwordLabel => 'Şifre';

  @override
  String aheadOfInflationPeriod(String pts) {
    return 'Bu dönem enflasyonun $pts puan önünde.';
  }

  @override
  String get realReturnPositive =>
      'Portföyün enflasyonun üzerinde reel getiri sağladı, alım gücün arttı.';

  @override
  String percentileSentence(int pct) {
    return 'Katılımcıların %$pct kadarının üstündesin.';
  }

  @override
  String get noDrawdown => 'Bu pencerede portföyün zirvesinden gerilemedi.';

  @override
  String concentrationBody(String pct, String label, int n, String tail) {
    return 'Portföyünün %$pct\'i $label içinde; toplam $n pozisyonun var.$tail';
  }

  @override
  String get riskAdjustedReturn => 'Risk-ayarlı getiri';

  @override
  String get riskAdjustedBody =>
      'Yıllık getiri ÷ yıllık oynaklık. Sharpe oranının risksiz oransız hâli: aldığın her birim dalgalanma için kaç puan getiri.';

  @override
  String get timingEffectBody =>
      'Paranın getirisi (XIRR) − piyasa getirisi. Pozitifse alım tarihlerin piyasayı yendi; negatifse pahalıya girmişsin.';

  @override
  String recoveryDays(int n) {
    return '$n gün';
  }

  @override
  String get recoveryBody =>
      'En büyük düşüşün dibinden eski zirveye dönüş süresi.';

  @override
  String get notYet => 'Henüz yok';

  @override
  String get notRecoveredBody =>
      'En büyük düşüşün ardından eski zirveye henüz dönülmedi.';

  @override
  String get timingEffect => 'Zamanlama etkisi';

  @override
  String get recoveryWord => 'Toparlanma';

  @override
  String get intradayWord => 'Gün içi';

  @override
  String get todayWord => 'Bugün';

  @override
  String get nowWord => 'Şimdi';

  @override
  String behindInflationPeriod(String pts) {
    return 'Bu dönem enflasyonun $pts puan gerisinde.';
  }

  @override
  String get realReturnNegative =>
      'Portföyün enflasyonun altında kaldı, alım gücün geriledi.';

  @override
  String get realReturnEven =>
      'Portföyün enflasyonla aynı oranda değerlendi, alım gücün korundu.';

  @override
  String nPeopleParen(int n) {
    return '($n kişi)';
  }

  @override
  String recoveredInDays(int n) {
    return ' ve $n günde toparladı';
  }

  @override
  String get notRecoveredYet => ' ve henüz o seviyeye dönmedi';

  @override
  String get singleAssetHeavy =>
      'Tek varlığın hareketi portföyünü belirgin etkiler.';

  @override
  String drawdownBody(String pct, String tail) {
    return 'Portföyün, gördüğü en yüksek seviyeden en fazla %$pct geriledi$tail.';
  }

  @override
  String get rangeAllTime => 'Tüm zamanlar';

  @override
  String get rangeLast7 => 'Son 7 gün';

  @override
  String get rangeLast30 => 'Son 30 gün';

  @override
  String get rangeLast90 => 'Son 90 gün';

  @override
  String get rangeThisYear => 'Bu yıl';

  @override
  String get rangeCustom => 'Özel';

  @override
  String get noRecords => 'Kayıt yok';

  @override
  String nRecords(int n) {
    return '$n kayıt';
  }

  @override
  String nShown(int n) {
    return ' · $n gösteriliyor';
  }

  @override
  String get noMatchingRecords => 'Filtreye uyan kayıt yok';

  @override
  String get noTransactionsYet => 'Henüz işlem yok';

  @override
  String get todaysBalanceChange => 'Bugünkü toplam değişim';

  @override
  String sinceDateToToday(String date) {
    return '$date → bugün';
  }

  @override
  String balanceChangeSince(String date) {
    return '$date toplam değişim';
  }

  @override
  String periodChangeSim(String period) {
    return '$period değişim · bugünkü portföyle';
  }

  @override
  String periodBalanceChange(String period) {
    return '$period toplam değişim';
  }

  @override
  String get marketOnlyRow => 'Sadece fiyat etkisi';

  @override
  String rowExpandedSemantics(String label) {
    return '$label, açık. Kapatmak için çift dokun.';
  }

  @override
  String gainAmount(String amount) {
    return 'kazanç $amount';
  }

  @override
  String flowBuyLower(String amount) {
    return 'dönem içi alım $amount';
  }

  @override
  String rowCollapsedSemantics(String label) {
    return '$label, kapalı. İçindeki ürünleri görmek için çift dokun.';
  }

  @override
  String lossAmount(String amount) {
    return 'kayıp $amount';
  }

  @override
  String flowSellLower(String amount) {
    return 'dönem içi satış $amount';
  }

  @override
  String flowSellUpper(String amount) {
    return 'Dönem içi satış $amount';
  }

  @override
  String flowBuyUpper(String amount) {
    return 'Dönem içi alım $amount';
  }

  @override
  String get raceFooterGlobal =>
      'Sıralama seçimlerinin getirisidir: her gün tuttuğun varlıklar piyasa fiyatıyla ölçülür, para ekleme zamanı etkilemez. Sıralamalar ve dağılımlar anonimdir; kimlik, miktar ve TL bilgisi asla paylaşılmaz.';

  @override
  String get calculatingEllipsis => 'Hesaplanıyor…';

  @override
  String nThousandPeople(String n) {
    return '${n}K KİŞİ';
  }

  @override
  String nPeopleUpper(int n) {
    return '$n KİŞİ';
  }

  @override
  String get toneTop5 => 'Zirvedeki azınlıktasın';

  @override
  String get toneTop10 => 'Sandık\'ın en iyi %10\'undasın';

  @override
  String get toneTop25 => 'Ortalamanın çok üstündesin';

  @override
  String get toneTop50 => 'Ortalamanın üstündesin';

  @override
  String get toneTop75 => 'Ortalamaya yakınsın';

  @override
  String get toneRest => 'Daha iyisini yapabilirsin, 30G takip et';

  @override
  String get raceFooterPartners =>
      'Sıralama, seçili dönemde seçimlerinin getirisidir (%): para ekleme zamanı etkilemez. Kimsenin varlık listesi görünmez.';

  @override
  String get recapYourPortfolio => 'Portföyün';

  @override
  String get recapGrewThisYear => 'Bu yıl böyle büyüdün.';

  @override
  String get recapToughYear => 'Zor bir yıl oldu.';

  @override
  String get recapVsInflation => 'Enflasyona karşı · son 12 ay';

  @override
  String get recapKeptPower => 'Alım gücünü korudun ve üstüne koydun.';

  @override
  String get recapInflationWon => 'Son 12 ayda enflasyon öndeydi.';

  @override
  String recapInflationWindow(String start, String end) {
    return 'Ölçüm: $start - $end (TÜFE aylık yayımlandığı için pencere son açıklanan ayda biter)';
  }

  @override
  String get recapBestAsset => 'En çok kazandıran';

  @override
  String recapReturnedPct(String pct) {
    return 'Bugüne kadar %$pct getirdi.';
  }

  @override
  String get recapMostPatient => 'En sabırlı olduğun';

  @override
  String recapInPortfolioDays(int n) {
    return '$n gündür portföyünde.';
  }

  @override
  String recapTypeCount(int n) {
    return '$n türde varlık ile.';
  }

  @override
  String get recapForAYear => 'Bir yıl boyunca.';

  @override
  String recapShareTitle(int year) {
    return 'sandık Özetim $year';
  }

  @override
  String get shareWord => 'Paylaş';

  @override
  String get scopeTogether => 'Birlikte';

  @override
  String get scopeMe => 'Ben';

  @override
  String get scopeLabel => 'Kapsam';

  @override
  String get scopeSearch => 'Ortak ara';

  @override
  String scopePeopleCount(int n) {
    return '$n kişi';
  }

  @override
  String get scopeSwipeHint => 'Kartı sağa/sola kaydırarak da geçebilirsin';

  @override
  String get scopeNoMatch => 'Eşleşen ortak yok';

  @override
  String get scopeWho => 'Kimin portföyü';

  @override
  String get scopePartners => 'Ortaklar';

  @override
  String get chartTypeTooltip => 'Grafik tipi';

  @override
  String get fullscreenChart => 'Grafiği tam ekran aç';

  @override
  String get whatsNewTitle => 'Yenilikler';

  @override
  String get whatsNewSubtitle => 'Bu sürümde neler değişti';

  @override
  String get whatsNewEmpty => 'Bu sürüm için not yok.';

  @override
  String appVersionLabel(String surum) {
    return 'sandık · sürüm $surum';
  }

  @override
  String get shareCardBest => 'En iyi';

  @override
  String get shareCardWorst => 'En zayıf';

  @override
  String get shareCardUpDays => 'Artıda gün';

  @override
  String shareCardUpDaysValue(int up, int total) {
    return '$up/$total';
  }

  @override
  String shareCardReal(String pct) {
    return 'reel $pct';
  }

  @override
  String get shareCardXirr => 'Yıllık getiri';

  @override
  String get shareCardDrawdown => 'En derin düşüş';

  @override
  String get shareCardPatient => 'En sabırlı';

  @override
  String get shareCardAllocation => 'Dağılım';

  @override
  String get shareCardTracked => 'Takip';

  @override
  String get shareCardInvestors => 'Yatırımcıların';

  @override
  String shareCardBetterThanPct(int pct) {
    return '%$pct\'inden iyi';
  }

  @override
  String shareCardRange(String start, String end) {
    return '$start - $end';
  }

  @override
  String get notifTypePartner => 'ORTAKLIK';

  @override
  String get notifTypeDailyBrief => 'GÜNLÜK';

  @override
  String get notifTypeWeekly => 'HAFTALIK';

  @override
  String get notifTypeReminder => 'HATIRLATMA';

  @override
  String notifToday(String time) {
    return 'Bugün $time';
  }

  @override
  String get reviewPromptTitle => 'sandık\'ı seviyor musun?';

  @override
  String get reviewPromptBody =>
      'Kısa bir puan, uygulamanın daha çok yatırımcıya ulaşmasını sağlar. İstersen sonra da verebilirsin.';

  @override
  String get reviewPromptYes => 'Evet, değerlendir';

  @override
  String get reviewPromptLater => 'Sonra';

  @override
  String get reviewPromptIssue => 'Bir sorun var';

  @override
  String get rateAppTitle => 'sandık\'ı değerlendir';

  @override
  String get rateAppSubtitle => 'Mağazada puan ver';

  @override
  String get todayMarketOnly => 'sadece fiyat etkisi';

  @override
  String todaySessionOpen(String close) {
    return 'Seans açık · $close kapanış';
  }

  @override
  String todayOpensAt(String when) {
    return '$when açılır';
  }

  @override
  String get todayClosedWord => 'Piyasa kapalı';

  @override
  String get todayLiveWord => 'Canlı';

  @override
  String get todayLoading => 'Gün içi veri geliyor';

  @override
  String get todayRealLabel => 'Enflasyona göre';

  @override
  String get todayRealHint => 'Yıllık getirin ile TÜFE farkı';

  @override
  String get todayWeekHint => 'Piyasanın portföyüne etkisi · özet hazır';

  @override
  String get todayGoalLabel => 'Hedef';

  @override
  String get todayGoalSetShort => 'Tutar seç, kalanı her gün gör';

  @override
  String get todayGoalAction => 'Belirle';

  @override
  String todayGoalLeftHint(String goal) {
    return '$goal hedefe kalan';
  }

  @override
  String todayGoalValue(int pct, String left) {
    return '%$pct · $left';
  }

  @override
  String get todayGoalDone => 'Ulaşıldı';

  @override
  String todayGoalDoneHint(String goal) {
    return 'Hedefin $goal · yenisini seç';
  }

  @override
  String get todayOpenAction => 'Aç';

  @override
  String get todayTitle => 'Bugün';

  @override
  String todayScopeOf(String name) {
    return '$name bugünü';
  }

  @override
  String todayUp(String amount, String pct) {
    return '$amount · %$pct artıda';
  }

  @override
  String todayDown(String amount, String pct) {
    return '$amount · %$pct eksi';
  }

  @override
  String get todayFlat => 'Bugün değişmedi';

  @override
  String todayAt(String time) {
    return 'bugün $time';
  }

  @override
  String todayMarketClosed(String when) {
    return 'Piyasa kapalı · $when açılır';
  }

  @override
  String todayGreenShare(int green, int total) {
    return '$green/$total varlığın artıda';
  }

  @override
  String get todayGoalSet => 'Bir hedef belirle';

  @override
  String get todayGoalSetHint =>
      'Portföyün için bir tutar seç; ne kadar kaldığını her gün burada gör.';

  @override
  String todayGoalProgress(int pct, String left) {
    return 'Hedefe %$pct · $left kaldı';
  }

  @override
  String todayGoalReached(String goal) {
    return 'Hedefine ulaştın: $goal';
  }

  @override
  String todayInDays(int n) {
    return '$n gün sonra';
  }

  @override
  String todayEventCpi(String when) {
    return 'TÜİK enflasyonu $when açıklıyor';
  }

  @override
  String todayEventHoliday(String when) {
    return 'Borsa $when kapalı (resmî tatil)';
  }

  @override
  String todayEventMonthEnd(String when) {
    return 'Ay $when bitiyor; aylık özetin hazır olacak';
  }

  @override
  String todayMonthlySummary(String month) {
    return '$month özetin hazır';
  }

  @override
  String get todayMonthlySummaryHint =>
      'Getirin, enflasyon farkı ve en iyi varlığın';

  @override
  String todayCloseAt(String close) {
    return '$close kapanış';
  }

  @override
  String get todayClosedShort => 'Kapalı';

  @override
  String get todayMarketOnlyShort => 'fiyat etkisi';

  @override
  String get todayGoalNewAction => 'Yenisini seç';

  @override
  String get todayMoveLabel => 'Günün hareketi';

  @override
  String get todayRealYearly => 'yıllık';

  @override
  String get todayGoalSetAction => 'Hedef belirle';

  @override
  String get todayGoalSetSub => 'Kalanı her gün gör';

  @override
  String todayGoalProgressTitle(int pct) {
    return 'Hedefe %$pct';
  }

  @override
  String todayGoalLeftShort(String left) {
    return '$left kaldı';
  }

  @override
  String get goalTitle => 'Portföy hedefi';

  @override
  String get goalHint => 'Yalnızca gösterim için; hesapları değiştirmez.';

  @override
  String get goalInvalid => 'Geçerli bir tutar gir';

  @override
  String get goalRemove => 'Hedefi kaldır';

  @override
  String get goalSettingsSubtitle =>
      'Bir tutar belirle; ilerlemeyi ana ekrandaki Bugün kartında gör';

  @override
  String partnerInviteMessage(String code, String link) {
    return 'Merhaba! sandık portföy uygulamasında seninle ortak olmak istiyorum.\n\nOrtak kodun: $code\n\nUygulamayı indir, Profil → \"Ortak Kodu Gir\" bölümünden bu kodu gir:\n$link';
  }

  @override
  String get partnerInviteSubject => 'sandık ortak daveti';

  @override
  String get notifTypeMonthly => 'AYLIK';

  @override
  String raceJoinedCount(int count, int min) {
    return '$count kişi bugün yarışta · sıralama $min kişide açılır';
  }

  @override
  String raceRunningCount(int count) {
    return '$count kişi bugün yarışıyor';
  }

  @override
  String get marketDollar => 'Dolar';

  @override
  String get marketEuro => 'Euro';

  @override
  String get marketGold => 'Gram altın';

  @override
  String get marketBist => 'BIST 100';

  @override
  String get notifTypeWatchlist => 'TAKİP';

  @override
  String get notifTypeInflation => 'TÜFE';

  @override
  String alarmSuggest(String name) {
    return '$name eklendi. Fiyatı izlemek için alarm kur?';
  }

  @override
  String get alarmSuggestAction => 'Alarm kur';

  @override
  String get briefSlotTitle => 'Brifing saati';

  @override
  String get briefSlotSubtitle =>
      'Portföyündeki günlük hareket özeti ne zaman gelsin';

  @override
  String get briefSlotMorning => 'Sabah 09:45';

  @override
  String get briefSlotEvening => 'Akşam 18:30 (kapanış)';

  @override
  String todayRealReturnAhead(String pts) {
    return '$pts puan enflasyonun önündesin · yıllık';
  }

  @override
  String todayRealReturnBehind(String pts) {
    return '$pts puan enflasyonun gerisindesin · yıllık';
  }

  @override
  String todayWeeklyUp(String pct) {
    return 'Geçen hafta piyasadan +$pct · özetin hazır';
  }

  @override
  String todayWeeklyDown(String pct) {
    return 'Geçen hafta piyasadan −$pct · özetin hazır';
  }

  @override
  String get sectionResult => 'Ne oldu?';

  @override
  String get sectionWhy => 'Neden böyle?';

  @override
  String get sectionDetail => 'Ayrıntılar';

  @override
  String get sectionDepth => 'Daha fazlası';

  @override
  String get sectionDepthHint => 'Yıllık getiri, sağlık, karakter';

  @override
  String get myAlarms => 'Alarmlarım';

  @override
  String get viewChipLabel => 'Görünüm';

  @override
  String get identityCrypto => 'Kripto Para';

  @override
  String get pickCryptoTap => 'Kripto seçmek için dokun';

  @override
  String get pickCryptoPrompt => 'Bir kripto para seç';

  @override
  String cryptoSelectedSemantics(String name) {
    return 'Seçili kripto: $name. Değiştirmek için çift dokun.';
  }

  @override
  String get cryptoPickerTitle => 'Kripto Paralar';

  @override
  String get cryptoSearchHint => 'Ad ya da kod ara (BTC, Ethereum…)';

  @override
  String get cryptoLoading => 'Kripto listesi yükleniyor';

  @override
  String get cryptoLoadFailed => 'Kripto listesi yüklenemedi';

  @override
  String get cryptoSourceNote =>
      'Fiyatlar Binance\'ten, dakikada bir güncellenir. Yatırım tavsiyesi değildir.';

  @override
  String get priceDelayed => 'Gecikmeli';

  @override
  String priceDelayedSemantics(String time) {
    return 'Fiyat gecikmeli, son güncelleme $time';
  }

  @override
  String get period5Y => '5 yıl';

  @override
  String get vsPeriodReturnUpper => 'DÖNEM GETİRİSİ';

  @override
  String get vsTodayUpper => 'BUGÜN';

  @override
  String get vsMaxDrawdownUpper => 'EN BÜYÜK DÜŞÜŞ';

  @override
  String get vsVolatilityUpper => 'OYNAKLIK (YILLIK)';

  @override
  String get vsPeriodLow => 'Dönem düşüğü';

  @override
  String get vsPeriodHigh => 'Dönem yükseği';

  @override
  String vsRangePosition(String pct) {
    return 'Fiyat dönem aralığının %$pct noktasında';
  }

  @override
  String get vsVolatilityShortNote =>
      'Oynaklık 1 ay ve daha uzun dönemlerde hesaplanır.';

  @override
  String get adPositionUpper => 'POZİSYONUN';

  @override
  String adPositionLine(String amount, String pct) {
    return 'Pozisyonun: $amount ($pct)';
  }

  @override
  String chartOpenLabel(String time, String value) {
    return 'AÇILIŞ · $time · $value';
  }

  @override
  String get posQuantity => 'Miktar';

  @override
  String get posBuyPrice => 'Alış fiyatın (ortalama)';

  @override
  String get posTodayPrice => 'Bugünkü fiyat';

  @override
  String get posTotalCost => 'Ödediğin toplam';

  @override
  String get posCurrentValue => 'Bugünkü değer';

  @override
  String get posTotalPnl => 'Toplam kâr/zarar';

  @override
  String posPeriodPnl(String period) {
    return '$period kâr/zarar';
  }

  @override
  String chartStartLabel(String date, String value) {
    return 'BAŞLANGIÇ · $date · $value';
  }

  @override
  String get chartNowLabel => 'ŞİMDİ';

  @override
  String get vsWatch => 'Takip et';

  @override
  String get vsSelect => 'Bunu seç';

  @override
  String get vsGoToPosition => 'Pozisyonuma git';

  @override
  String get vsOwnedNote =>
      'Bu varlık portföyünde. Al ve sat pozisyon ekranından yapılır.';

  @override
  String vsRemovedFromWatchlist(String name) {
    return '$name takipten çıkarıldı';
  }

  @override
  String get vsUndo => 'Geri al';

  @override
  String vsChartSemantics(String name, String period) {
    return '$name fiyat grafiği, $period';
  }

  @override
  String vsOpenDetailSemantics(String name) {
    return '$name grafiğini ve istatistiklerini gör';
  }

  @override
  String vsWatchSemantics(String name) {
    return '$name takibe al';
  }

  @override
  String vsUnwatchSemantics(String name) {
    return '$name takipten çıkar';
  }

  @override
  String get vsLoadFailed =>
      'Fiyat geçmişi alınamadı. Bağlantını kontrol edip dönemi yeniden seç.';

  @override
  String vsSheetSemantics(String name) {
    return '$name varlık sayfası';
  }

  @override
  String get searchRecentUpper => 'SON BAKTIKLARIN';

  @override
  String get searchMarketsUpper => 'PİYASALAR';

  @override
  String searchShowAll(int count) {
    return 'Tümü ($count)';
  }

  @override
  String get searchInPortfolioTag => 'Portföyünde';

  @override
  String get searchAssetsSemantics => 'Varlık ara';

  @override
  String get searchChip => 'Ara';

  @override
  String get searchShortHint => 'Hisse, fon, altın, döviz, kripto';

  @override
  String get kullaniciAdiBaslik => 'Kullanıcı adını seç';

  @override
  String get kullaniciAdiAciklama =>
      'Ortağın seni bu adla görür, uygulamada da bu ad görünür. Sonra Ayarlar > Hesap\'tan değiştirebilirsin.';

  @override
  String get kullaniciAdiZorunluNot =>
      'Devam etmek için bir kullanıcı adı gerekiyor. Uygun bir ad seçtiğin an devam edebilirsin.';

  @override
  String get kullaniciAdiUygunDevam => 'Bu ad uygun. Devam edebilirsin.';

  @override
  String get kullaniciAdiEtiket => 'Kullanıcı adı';

  @override
  String get kullaniciAdiKurallar =>
      '3-20 karakter: harf, rakam, nokta ve alt çizgi. Harfle başlar, boşluk olmaz.';

  @override
  String get kullaniciAdiHataBicim =>
      '3-20 karakter olmalı; harfle başlar, yalnız harf, rakam, . ve _ içerir.';

  @override
  String get kullaniciAdiHataUygunsuz =>
      'Bu ad uygun değil. Başka bir ad dene.';

  @override
  String get kullaniciAdiHataAyrilmis => 'Bu ad ayrılmış. Başka bir ad dene.';

  @override
  String get kullaniciAdiHataAlinmis => 'Bu ad alınmış. Başka bir ad dene.';

  @override
  String get kullaniciAdiHataBilinmiyor =>
      'Kaydedilemedi. Biraz sonra tekrar dene.';

  @override
  String get kullaniciAdiUygun => 'Bu ad kullanılabilir.';

  @override
  String get kullaniciAdiDevam => 'Devam et';

  @override
  String get kullaniciAdiKaydet => 'Kaydet';

  @override
  String get kullaniciAdiKaydedildi => 'Kullanıcı adın güncellendi.';

  @override
  String get kullaniciAdiSecilmedi => 'Henüz seçilmedi';

  @override
  String get kullaniciAdiCikis => 'Çıkış yap';

  @override
  String get registerUsernameMissing => 'Kullanıcı adı gir.';

  @override
  String get deletedFilter => 'Silinenler';

  @override
  String get deletedEmptyTitle => 'Silinmiş kayıt yok';

  @override
  String get deletedEmptyBody =>
      'Bir varlığı sildiğinde alım, satım ve silinme tarihleri burada durur; portföy toplamına girmez.';

  @override
  String get ipoTitle => 'Halka arzlar';

  @override
  String get ipoProfileRowSubtitle => 'Takvim, fiyat ve katılım kaydı';

  @override
  String get ipoGroupTalep => 'Talep toplanıyor';

  @override
  String get ipoGroupYaklasan => 'Yaklaşan';

  @override
  String get ipoGroupIslemBekliyor => 'İşlem görmeyi bekliyor';

  @override
  String get ipoGroupIslemGoruyor => 'İşlem görüyor';

  @override
  String get ipoGroupBilinmiyor => 'Tarihi belirsiz';

  @override
  String ipoOfflineNote(String tarih) {
    return 'Çevrimdışı: $tarih tarihli liste gösteriliyor.';
  }

  @override
  String get ipoOfflineNoDate => 'Çevrimdışı: kayıtlı liste gösteriliyor.';

  @override
  String ipoListDate(String tarih) {
    return 'Liste tarihi: $tarih';
  }

  @override
  String get ipoEmpty => 'Şu an listede halka arz yok.';

  @override
  String get ipoDisclaimer =>
      'Bilgi amaçlıdır, yatırım tavsiyesi değildir. Tarih ve fiyatı aracı kurumundan doğrula.';

  @override
  String ipoRowTalep(String aralik) {
    return 'Talep: $aralik';
  }

  @override
  String ipoRowIslem(String tarih) {
    return 'İşlem: $tarih';
  }

  @override
  String get ipoFieldTalep => 'Talep toplama';

  @override
  String get ipoFieldFiyat => 'Halka arz fiyatı';

  @override
  String get ipoFieldDagitim => 'Dağıtım';

  @override
  String get ipoFieldIslem => 'İşlem başlangıcı';

  @override
  String get ipoFieldPazar => 'Pazar';

  @override
  String get ipoFieldGuncelleme => 'Bilgi tarihi';

  @override
  String get ipoDagitimEsit => 'Eşit';

  @override
  String get ipoDagitimOransal => 'Oransal';

  @override
  String get ipoOpenSource => 'Kaynağı aç';

  @override
  String get ipoSourceFailed => 'Bağlantı açılamadı.';

  @override
  String get ipoParticipate => 'Katıldım, portföye ekle';

  @override
  String get ipoParticipateHint =>
      'Sana düşen lot sayısını yaz; alış fiyatı ve tarih hazır gelir. İşlem başlayana kadar hisse portföyünde halka arz fiyatıyla görünür.';

  @override
  String get ipoParticipateHintTraded =>
      'Sana düşen lot sayısını yaz; alış fiyatı (halka arz fiyatı) ve ilk işlem günü hazır gelir. Hisse portföyünde canlı fiyatıyla görünür.';

  @override
  String get ipoParticipateNoPrice =>
      'Halka arz fiyatı listede yok: formda alış fiyatını kendin yaz. İşlem görmeyen hissenin fiyatı bulunamaz; boş bırakırsan maliyet 0 kaydedilir.';

  @override
  String get ipoParticipateLater =>
      'Dağıtım sonuçları talep toplama bitince açıklanır. Katıldıysan o zaman buradan portföyüne ekleyebilirsin.';

  @override
  String get ipoParticipationSaved => 'Halka arz lotun portföyüne eklendi.';

  @override
  String txDateLabeled(String tur, String tarih) {
    return '$tur: $tarih';
  }

  @override
  String deletedOnDate(String tarih) {
    return 'Silinme: $tarih';
  }

  @override
  String get pickGoldPrompt => 'Bir altın türü seç';

  @override
  String get pickCurrencyPrompt => 'Bir döviz seç';

  @override
  String get raceLive => 'Canlı';

  @override
  String get raceLiveJustNow => 'Canlı · az önce güncellendi';

  @override
  String raceLiveSecondsAgo(int n) {
    return 'Canlı · $n sn önce güncellendi';
  }

  @override
  String raceLiveMinutesAgo(int n) {
    return 'Canlı · $n dk önce güncellendi';
  }

  @override
  String get raceYou => 'Sen';

  @override
  String get raceYouTag => 'SEN';

  @override
  String get raceVs => 'VS';

  @override
  String raceGapToLeader(String fark) {
    return 'Lidere $fark puan';
  }

  @override
  String get duelTied => 'Başa baş gidiyorsunuz';

  @override
  String duelAhead(String ad, String adIyelik, String fark) {
    return '$adIyelik $fark puan önündesin';
  }

  @override
  String raceRankUp(int n) {
    return '$n sıra yükseldi';
  }

  @override
  String raceRankDown(int n) {
    return '$n sıra düştü';
  }

  @override
  String get filterButton => 'Filtrele';

  @override
  String filterButtonActive(int n) {
    return 'Filtrele, $n etkin';
  }

  @override
  String get filterReset => 'Sıfırla';

  @override
  String get filterPeriodHeader => 'DÖNEM';

  @override
  String get filterTypeHeader => 'TÜR';

  @override
  String filterShowN(int n) {
    return '$n kaydı göster';
  }

  @override
  String get filterNoMatch => 'Eşleşen kayıt yok';

  @override
  String filterRemove(String ad) {
    return '$ad filtresini kaldır';
  }

  @override
  String get assetTypeDeposit => 'Mevduat';

  @override
  String get assetTypePension => 'BES';

  @override
  String get tickerHintDeposit => 'Sözleşmeden hesaplanır';

  @override
  String get tickerHintPension => 'TEFAS emeklilik fonu kodu';

  @override
  String get depositBank => 'Banka';

  @override
  String get depositBankHint => 'Örn. Enpara, Garanti BBVA';

  @override
  String get depositPrincipal => 'Yatırdığın tutar';

  @override
  String get depositRate => 'Yıllık faiz (brüt, %)';

  @override
  String get depositKindTerm => 'Vadeli';

  @override
  String get depositKindDaily => 'Günlük faizli';

  @override
  String get depositTerm => 'Vade';

  @override
  String depositDays(int n) {
    return '$n gün';
  }

  @override
  String get depositCustomDays => 'Özel';

  @override
  String get depositCustomDaysHint => 'Gün sayısı';

  @override
  String get depositStart => 'Başlangıç';

  @override
  String get depositWithholding => 'Stopaj (%)';

  @override
  String get depositWithholdingHint =>
      'Vadeye göre önerildi. Bankan farklı uyguluyorsa düzelt.';

  @override
  String get depositMaturity => 'Vade sonu';

  @override
  String get depositNetReturn => 'Net getiri';

  @override
  String get depositAtMaturity => 'Vade sonunda';

  @override
  String get depositDailyNet => 'Günlük net';

  @override
  String get depositErrorBank => 'Banka adını yaz.';

  @override
  String get depositErrorPrincipal => 'Tutarı yaz.';

  @override
  String get depositErrorRate => 'Faiz oranını yaz.';

  @override
  String get depositErrorDays => 'Vadeyi gün olarak yaz.';

  @override
  String get depositErrorWithholding => 'Stopaj 0 ile 100 arasında olmalı.';

  @override
  String get depositAccrualNote =>
      'Faiz vade sonunda anaparaya eklenir; o güne kadar değer anaparada kalır. Vadeyi erken bozarsan banka faizi ödemeyebilir.';

  @override
  String get depositCardTitle => 'Mevduat';

  @override
  String depositPeriodN(int n) {
    return '$n. dönem';
  }

  @override
  String depositDaysLeft(int n) {
    return 'Vadeye $n gün';
  }

  @override
  String get depositMatured => 'Vadesi doldu';

  @override
  String get depositMaturedBody =>
      'Faiz eklendi. Yeni dönemi başlatmak için yeni faizi gir; girmezsen değer olduğu gibi kalır.';

  @override
  String get depositThisPeriod => 'Bu dönem net';

  @override
  String get depositTotalReturn => 'Toplam net getiri';

  @override
  String get depositRenew => 'Yenile';

  @override
  String get depositWithdraw => 'Çektim';

  @override
  String get depositRenewTitle => 'Yeni dönem';

  @override
  String get depositRenewSaved => 'Yeni dönem başladı';

  @override
  String get depositRateUpdate => 'Oranı güncelle';

  @override
  String get depositRateSaved => 'Oran güncellendi';

  @override
  String get depositWithdrawTitle => 'Parayı çektin mi?';

  @override
  String depositWithdrawBody(String amount) {
    return 'Mevduat bugünkü değeriyle ($amount) satılmış olarak kaydedilir.';
  }

  @override
  String get depositWithdrawConfirm => 'Çektim, kapat';

  @override
  String get depositWithdrawn => 'Mevduat kapatıldı';

  @override
  String get pensionCompany => 'Emeklilik şirketi';

  @override
  String get pensionCompanyHint => 'Örn. Anadolu Hayat';

  @override
  String get pensionEntryDate => 'Sisteme giriş';

  @override
  String get pensionEntryDateHint =>
      'Devlet katkısının hak ediş oranı buna bağlı.';

  @override
  String get pensionFunds => 'Fon dağılımı';

  @override
  String get pensionAddFund => 'Fon ekle';

  @override
  String pensionShareTotal(String pct) {
    return 'Toplam $pct';
  }

  @override
  String get pensionShareError => 'Fon payları toplamı %100 olmalı.';

  @override
  String get pensionFundError => 'En az bir emeklilik fonu seç.';

  @override
  String get pensionGov => 'Devlet katkısı';

  @override
  String get pensionGovFund => 'Devlet katkısı fonu';

  @override
  String get pensionGovFundHint =>
      'Bilmiyorsan boş bırak; devlet katkısı eklenmez.';

  @override
  String get pensionMonthly => 'Aylık katkı';

  @override
  String get pensionDay => 'Katkı günü';

  @override
  String get pensionErrorCompany => 'Şirket adını yaz.';

  @override
  String get pensionErrorBalance =>
      'Ana para ile getirinin toplamı sıfırdan büyük olmalı.';

  @override
  String get pensionErrorGovFund => 'Devlet katkısı birikimi için fonu da seç.';

  @override
  String pensionPriceMissing(String code) {
    return '$code fonunun fiyatı alınamadı. Birazdan tekrar dene.';
  }

  @override
  String get pensionPickFund => 'Emeklilik fonu seç';

  @override
  String get pensionPickGovFund => 'Devlet katkısı fonu seç';

  @override
  String get pensionSearchFund => 'Fon kodu ya da adı';

  @override
  String get pensionNoFundFound => 'Eşleşen emeklilik fonu yok';

  @override
  String get pensionCardTitle => 'BES';

  @override
  String pensionYear(int n) {
    return '$n. yıl';
  }

  @override
  String get pensionTotal => 'Toplam birikim';

  @override
  String get pensionOwn => 'Senin katkın';

  @override
  String get pensionGovShort => 'Devlet';

  @override
  String get pensionReturn => 'Getiri';

  @override
  String get pensionIfLeave => 'Bugün çıkarsan (vergi öncesi)';

  @override
  String get pensionVesting => 'Devlet katkısı hak ediş';

  @override
  String get currentValueUpper => 'GÜNCEL DEĞER';

  @override
  String get depositCardRate => 'Faiz';

  @override
  String depositCardRateValue(String rate, String wht) {
    return '%$rate brüt · stopaj %$wht';
  }

  @override
  String get depositWithholdingManual =>
      'Bu oranı sen girdin; vade ya da tarih değişince öneri üstüne yazılmaz.';

  @override
  String get depositAccrualNoteDaily =>
      'Faiz her gün sonunda net olarak eklenir; gün içinde değer değişmez.';

  @override
  String depositAlreadyMatured(String date) {
    return 'Bu dönemin vadesi $date tarihinde dolmuş. Kaydettikten sonra karttan yeni dönemi başlatabilirsin.';
  }

  @override
  String get depositRenewStartHint =>
      'Banka vadeli hesabı vade gününde yeniler. Başka bir günde yenilediysen tarihi değiştir; aradaki günler faizsiz sayılır.';

  @override
  String pensionVestingNextIn(String now, String duration, String next) {
    return '$now · $duration sonra $next';
  }

  @override
  String pensionVestingSoon(String now, String next) {
    return '$now · bir ay içinde $next';
  }

  @override
  String pensionYears(int n) {
    return '$n yıl';
  }

  @override
  String pensionMonths(int n) {
    return '$n ay';
  }

  @override
  String pensionYearsMonths(int years, int months) {
    return '$years yıl $months ay';
  }

  @override
  String dividendAboveGross(String gross) {
    return 'Net tutar brütten ($gross) büyük olamaz. Alanı kontrol et.';
  }

  @override
  String get pensionAddContribution => 'Bu ayın katkısını ekle';

  @override
  String get pensionContributionTitle => 'Katkı ekle';

  @override
  String get pensionContributionAmount => 'Katkı tutarı';

  @override
  String pensionContributionGov(String amount) {
    return 'Devlet katkısı: $amount';
  }

  @override
  String get pensionContributionGovCapped =>
      'Bu yılın devlet katkısı sınırı doldu.';

  @override
  String get pensionContributionSaved => 'Katkı eklendi';

  @override
  String get pensionContributionDue => 'Bu ayın katkısı henüz eklenmedi.';

  @override
  String get pensionNoGovFund =>
      'Devlet katkısı fonu seçilmedi; devlet katkısı eklenmez.';

  @override
  String get pensionPrincipal => 'Ana para (ödediğin katkı)';

  @override
  String get pensionPrincipalHint =>
      'Bugüne kadar cebinden yatırdığın toplam; ekstrende \"katkı payı\" diye geçer.';

  @override
  String get pensionGain => 'Getiri (kâr)';

  @override
  String get pensionGainHint => 'Ekstrendeki getiri. Zarardaysan eksiyle yaz.';

  @override
  String get pensionHistoryHint =>
      'Grafik, bugünkü fon paylarını fonlarının gerçek fiyat geçmişiyle değerler; geçmişte dağılımın farklıydıysa eski dönemler birebir tutmaz.';

  @override
  String get pensionGovPrincipal => 'Devlet katkısı ana parası';

  @override
  String get pensionGovGain => 'Devlet katkısı getirisi';

  @override
  String get pensionErrorPrincipal => 'Ana parayı yaz.';

  @override
  String get pensionSwitchFunds => 'Fon değiştir';

  @override
  String get pensionSwitchTitle => 'Fon dağılımını değiştir';

  @override
  String get pensionSwitchHint =>
      'Birikimin bugünkü fiyatlarla yeni dağılıma taşınır. Ana para ve kâr değişmez; grafik bugünden sonra yeni fonlarla yürür.';

  @override
  String get pensionSwitchContributions =>
      'Yeni katkılar da bu dağılımla gitsin';

  @override
  String pensionSwitchCount(int n) {
    return 'Bu yıl $n/12 fon değişikliği';
  }

  @override
  String get pensionSwitchSaved => 'Fon dağılımı değişti';

  @override
  String get pensionSwitchSame => 'Dağılım zaten böyle.';

  @override
  String get pensionSwitchNote => 'Fon değişikliği';

  @override
  String get contractManagedNotice =>
      'Bu varlık sözleşmeden yönetilir. Değiştirmek için varlık sayfasındaki sözleşme kartını kullan.';

  @override
  String raceMoneyReturn(String pct) {
    return 'Paranın getirisi $pct';
  }

  @override
  String get raceMoneyReturnHint =>
      'Para ekleme zamanı dahil · Performans ile aynı';

  @override
  String get kiyasBaslik => 'Başka yere koysaydın';

  @override
  String get kiyasAciklama => 'Aynı paraları aynı günlerde buraya yatırsaydın.';

  @override
  String get kiyasSenin => 'Senin portföyün';

  @override
  String get kiyasBasaBas => 'Başa baş';

  @override
  String get kiyasTemettuNotu =>
      'Bu dönemdeki nakit temettüler iki tarafta da cebine giren para sayıldı.';

  @override
  String get kiyasVeriYok => 'Kıyas için fiyat verisi şu an alınamadı.';

  @override
  String get pensionDayHint => 'Örn. 15';

  @override
  String get pensionDayNote =>
      'Aylık katkının her ay hesabından çekildiği gün. 29-31 her ayda olmadığı için en fazla 28; ay sonunda çekiliyorsa 28 yaz.';

  @override
  String get pensionDayError => '1 ile 28 arasında bir gün yaz.';

  @override
  String get pensionAuto => 'Katkıyı otomatik ekle';

  @override
  String get pensionAutoNote =>
      'Katkı günü gelince aylık katkını o günün fon fiyatıyla ekleriz, sonra tutarı sana sorarız. Kapalıysa yalnızca hatırlatırız.';

  @override
  String get pensionAutoNeedsPlan =>
      'Otomatik ekleme için aylık katkıyı ve katkı gününü yaz.';

  @override
  String get pensionAutoLotNote => 'Otomatik katkı';

  @override
  String pensionAutoAdded(String date, String amount) {
    return '$date katkın otomatik eklendi: $amount. Tutarı güncellemek ister misin?';
  }

  @override
  String get pensionAutoConfirm => 'Tutar doğru';

  @override
  String get pensionAutoUpdate => 'Tutarı güncelle';

  @override
  String get pensionAutoUpdateTitle => 'Otomatik katkıyı güncelle';

  @override
  String get pensionAutoUpdatePlan => 'Sonraki aylar da bu tutarla eklensin';

  @override
  String get pensionAutoUpdated => 'Katkı güncellendi';

  @override
  String pensionAutoSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count aylık BES katkın otomatik eklendi. Tutarı BES kartından güncelleyebilirsin.',
      one:
          'BES katkın otomatik eklendi. Tutarı BES kartından güncelleyebilirsin.',
    );
    return '$_temp0';
  }

  @override
  String get pensionAddExtraContribution => 'Ek katkı ekle';

  @override
  String cpiSentenceMonth(String month, String change, String cpi) {
    return '$month ayında birikimin $change, aylık enflasyon $cpi oldu.';
  }

  @override
  String cpiSentenceRange(String start, String end, String change, String cpi) {
    return '$start - $end arasında birikimin $change, enflasyon $cpi oldu.';
  }

  @override
  String cpiSentenceYear(String start, String end, String change, String cpi) {
    return 'Son bir yılda ($start - $end) birikimin $change, enflasyon $cpi oldu.';
  }

  @override
  String cpiSentenceSinceFirstBuy(
      String date, String end, String change, String cpi) {
    return 'İlk alımından ($date) $end sonuna birikimin $change, enflasyon $cpi oldu.';
  }

  @override
  String savingsRose(String pct) {
    return '$pct arttı';
  }

  @override
  String savingsFell(String pct) {
    return '$pct azaldı';
  }

  @override
  String get savingsFlat => 'değişmedi';

  @override
  String get purchasingPowerUp => 'alım gücün arttı.';

  @override
  String get purchasingPowerDown => 'alım gücün geriledi.';

  @override
  String get purchasingPowerKept => 'alım gücün korundu.';

  @override
  String cpiNextNote(String month, String date) {
    return '$month TÜFE\'si $date tarihinde açıklanınca karşılaştırma $month ayını da kapsar.';
  }

  @override
  String cpiNextNoteLate(String month) {
    return '$month TÜFE\'si yüklenince karşılaştırma $month ayını da kapsar.';
  }

  @override
  String cpiShortenedNote(String month) {
    return 'Bu kadar geriye giden TÜFE verisi yok; karşılaştırma $month ayından başlıyor.';
  }

  @override
  String get cpiHowComputed => 'Nasıl hesaplandı';

  @override
  String get compoundRealReturn => 'Bileşik reel getiri';

  @override
  String get cpiSourceLabel => 'Kaynak';

  @override
  String get cpiSourceValue => 'TÜİK TÜFE';

  @override
  String vsInflationIn(String window) {
    return 'Enflasyona göre ($window)';
  }

  @override
  String get investedRow => 'Yatırdığın';

  @override
  String get marketAddedRow => 'Fiyat etkisi';

  @override
  String get dividendPocketRow => 'Cebine aldığın temettü';

  @override
  String flowBuyBalance(String flow, String change) {
    return 'Alım +$flow · toplam $change';
  }

  @override
  String flowSellBalance(String flow, String change) {
    return 'Satış −$flow · toplam $change';
  }

  @override
  String ofLastNMonths(String n) {
    return 'Son $n ayın';
  }

  @override
  String ofLastNWeeks(String n) {
    return 'Son $n haftanın';
  }

  @override
  String ofLastNYears(String n) {
    return 'Son $n yılın';
  }

  @override
  String inMonthPhrase(String month) {
    return '$month ayında';
  }

  @override
  String inWeekPhrase(String date) {
    return '$date haftasında';
  }

  @override
  String inYearPhrase(String year) {
    return '$year yılında';
  }

  @override
  String singleContribution(String period, String bucket, String amount) {
    return '$period yalnızca birinde para yatırdın: $bucket $amount.';
  }

  @override
  String singleWithdrawal(String bucket, String amount) {
    return '$bucket $amount çektin.';
  }

  @override
  String onlySalesInWindow(String bucket, String amount) {
    return 'Bu pencerede yeni para girmedi; satış var: $bucket $amount.';
  }

  @override
  String onlySalesInWindowTotal(String amount) {
    return 'Bu pencerede yeni para girmedi; toplam $amount satış var.';
  }

  @override
  String get marketPound => 'Sterlin';

  @override
  String get depositInterestAtMaturity => 'Vade sonunda net faiz';

  @override
  String get depositInterestAdded => 'Eklenen net faiz';

  @override
  String get depositPaidAtMaturityNote =>
      'Faiz vade sonunda eklenir; o güne kadar değer anaparada kalır. Vade içinde oranı güncellersen kazanç son girdiğin orana göre hesaplanır.';

  @override
  String get depositRateMidTermHint =>
      'Vade ve başlangıç aynı kalır. Vade sonundaki kazanç bu yeni orana göre hesaplanır.';

  @override
  String depositRateSavedMidTerm(String rate) {
    return 'Oran %$rate oldu. Vade sonundaki kazanç bu orana göre hesaplanacak.';
  }

  @override
  String depositStripRate(String rate) {
    return '%$rate brüt faiz';
  }

  @override
  String get cihazOtpBaslik => 'Bu cihazı doğrula';

  @override
  String get cihazOtpAciklama =>
      'Hesabın listede olmayan bir cihazda açılıyor. Güvenliğin için e-postana gönderdiğimiz kodu gir.';

  @override
  String get cihazOtpIpucu =>
      'Bu sen değilsen vazgeç ve şifreni değiştir. Doğrulanan cihaz, diğer cihazlardaki oturumu kapatır.';

  @override
  String get cihazOtpVazgec => 'Vazgeç ve çıkış yap';

  @override
  String get cihazKapisiHata =>
      'Bu cihaz doğrulanamadı. Bağlantını kontrol edip tekrar dene.';

  @override
  String get baskaCihazdaAcildi =>
      'Hesabın başka bir cihazda açıldı. Bu cihazda oturum kapatıldı.';

  @override
  String get kayitliCihazlar => 'Giriş yaptığın cihazlar';

  @override
  String get kayitliCihazlarAlt => 'Hesabın aynı anda tek cihazda açık kalır';

  @override
  String get kayitliCihazlarAciklama =>
      'Hesabın aynı anda yalnızca bir cihazda açık olabilir. Listede olmayan bir cihazdan giriş yapılınca e-postana doğrulama kodu gönderilir. Tanımadığın bir cihazı kaldır ve şifreni değiştir.';

  @override
  String get buCihaz => 'Bu cihaz';

  @override
  String cihazSonKullanim(String tarih) {
    return 'Son kullanım: $tarih';
  }

  @override
  String get cihazKaldir => 'Kaldır';

  @override
  String get cihazKaldirBaslik => 'Cihaz kaldırılsın mı?';

  @override
  String cihazKaldirMesaj(String ad) {
    return '$ad bir sonraki girişte e-posta koduyla yeniden doğrulanmak zorunda kalır.';
  }

  @override
  String get cihazKaldirildi => 'Cihaz kaldırıldı';

  @override
  String get cihazListesiBos => 'Kayıtlı cihaz yok.';

  @override
  String get otpSpamIpucu => 'Kod gelmediyse Gereksiz / Spam klasörüne de bak.';

  @override
  String get welcomeSkip => 'Atla';

  @override
  String get welcomeNext => 'Devam';

  @override
  String get welcomeCreateAccount => 'Hesap oluştur';

  @override
  String get welcomeTryDemo => 'Örnek portföye göz at';

  @override
  String get welcomeHaveAccount => 'Hesabım var, giriş yap';

  @override
  String welcomePageOf(int sayfa, int toplam) {
    return 'Tanıtım, sayfa $sayfa / $toplam';
  }

  @override
  String get welcomeP1Title => 'Tüm birikimin tek ekranda';

  @override
  String get welcomeP1Body =>
      'Ne aldığını bir kez yaz, fiyatları sandık güncellesin. Toplamını, kârını ve dağılımını her an gör.';

  @override
  String get welcomeP2Title => 'Gerçekten kazanıyor musun?';

  @override
  String get welcomeP2Body =>
      'Getirini enflasyonla, dolarla ve altınla kıyasla. Yeni alımlar değil, paranın kendisinin ne getirdiğini gör.';

  @override
  String get welcomeP3Title => 'Uygulamayı açmadan takip et';

  @override
  String get welcomeP3Body =>
      'Ana ekran widget\'ı ve sabah özeti portföyünü sana getirir. iPhone\'da kilit ekranında canlı takip edersin.';

  @override
  String get welcomeP4Title => 'Alarm kur, birlikte takip et';

  @override
  String get welcomeP4Body =>
      'Hedef fiyata gelince haber verelim. Eşinle ya da ailenle ortak portföyü birlikte izle.';

  @override
  String get welcomeTagStock => 'Hisse';

  @override
  String get welcomeTagFund => 'Fon';

  @override
  String get welcomeTagGold => 'Altın';

  @override
  String get welcomeTagFx => 'Döviz';

  @override
  String get welcomeTagCrypto => 'Kripto';

  @override
  String get welcomeTagPension => 'BES';

  @override
  String get welcomeTagInflation => 'Enflasyon';

  @override
  String get welcomeTagUsd => 'Dolar';

  @override
  String get welcomeTagWidget => 'Widget';

  @override
  String get welcomeTagLock => 'Kilit ekranı';

  @override
  String get welcomeTagBrief => 'Sabah özeti';

  @override
  String get welcomeTagAlarm => 'Fiyat alarmı';

  @override
  String get welcomeTagPartner => 'Ortak portföy';

  @override
  String get levelBeginnerDescSade =>
      'Sade görünüm: yalnızca temel rakamlar. Teknik sinyaller, grafik araçları ve ileri metrikler gizlenir.';

  @override
  String get levelSurveyIntro =>
      'Üç kısa soru; ekranları sana göre ayarlayalım.';

  @override
  String levelSurveyProgress(int no, int toplam) {
    return 'Soru $no / $toplam';
  }

  @override
  String get levelSurveyQ1 => 'Ne kadar süredir yatırım yapıyorsun?';

  @override
  String get levelSurveyQ1A0 => 'Yeni başlıyorum';

  @override
  String get levelSurveyQ1A1 => '1-3 yıldır';

  @override
  String get levelSurveyQ1A2 => '3 yıldan fazla';

  @override
  String get levelSurveyQ2 => 'Birikimin daha çok nerede?';

  @override
  String get levelSurveyQ2A0 => 'Altın, döviz, mevduat';

  @override
  String get levelSurveyQ2A1 => 'Fon ve hisse';

  @override
  String get levelSurveyQ2A2 => 'Aktif hisse ve kripto alım satımı';

  @override
  String get levelSurveyQ3 => 'Bu terimlerden hangileri sana tanıdık?';

  @override
  String get levelSurveyQ3A0 => 'Pek tanıdık değil';

  @override
  String get levelSurveyQ3A1 => 'Enflasyona göre getiri, dağılım';

  @override
  String get levelSurveyQ3A2 => 'Oynaklık, XIRR, RSI';

  @override
  String levelSurveyResult(String seviye) {
    return 'Sana $seviye görünümü uygun.';
  }

  @override
  String get levelSurveyResultNote =>
      'İstediğin an Ayarlar › Görünüm\'den değiştirebilirsin.';

  @override
  String get levelSurveyRetake => 'Anketi yeniden yap';

  @override
  String get levelSurveyOpen => '3 soruyla seviyemi bul';

  @override
  String get levelSurveyBack => 'Geri';

  @override
  String get todaysReturn => 'Bugünkü getirin';

  @override
  String returnSince(String date) {
    return '$date itibarıyla getirin';
  }

  @override
  String get balanceChangeInclBuys => 'Toplam değişim (alımlar dahil)';

  @override
  String get firstAssetPickTitle => 'Ne biriktiriyorsun?';

  @override
  String get firstAssetPickHint =>
      'Seç, miktarını yaz; fiyat kendiliğinden gelir.';

  @override
  String get firstAssetGoldGram => 'Gram altın';

  @override
  String get firstAssetUsd => 'Dolar';

  @override
  String get firstAssetEur => 'Euro';

  @override
  String get firstAssetFund => 'Bir fon';

  @override
  String get firstAssetStock => 'Bir hisse';

  @override
  String get firstAssetOtherType => 'Başka bir tür ekle';

  @override
  String get addDetails => 'Ayrıntı ekle (komisyon, not)';

  @override
  String get addByTyping => 'Yazarak ekle';

  @override
  String get importFromStatement => 'Ekstreden aktar';

  @override
  String get orWithEmail => 'veya e-postayla';

  @override
  String get todayTopMoverLabel => 'En çok oynayan';

  @override
  String get todayVsInflationYou => 'Getirin';

  @override
  String get todayVsInflationCpi => 'TÜFE';

  @override
  String get vitrinWelcome => 'Hoş geldin';

  @override
  String get vitrinTitle => 'Neye sahipsin?';

  @override
  String get vitrinHint =>
      'Dokun, miktarını yaz. Fiyat canlı gelir, sandığın kendini günceller.';

  @override
  String get vitrinLive => 'Fiyatlar canlı';

  @override
  String get vitrinQuarterGold => 'Çeyrek altın';

  @override
  String get vitrinFundHint => 'TEFAS\'taki tüm fonlar';

  @override
  String get vitrinStockHint => 'Borsa İstanbul';

  @override
  String get vitrinOtherTypes => 'Kripto, emtia, mevduat, BES ve diğerleri';

  @override
  String get vitrinOtherTypesShort => 'Kripto, BES ve diğer türler';

  @override
  String get vitrinStatementHint =>
      'Aracı kurum PDF, Excel ya da CSV; hepsi tek seferde';

  @override
  String get vitrinStatementHintShort => 'PDF, Excel ya da CSV; tek seferde';

  @override
  String get vitrinTapToAdd => 'Eklemek için dokun';

  @override
  String get vitrinPriceUnknown => 'Fiyat henüz yok';

  @override
  String get rankingTitle => 'Sıralama';

  @override
  String get rankingTabPartners => 'Ortaklarım';

  @override
  String get rankingTabEveryone => 'Zirvedekiler';

  @override
  String get todaysPortfolioBadge => 'Bugünkü portföyle';

  @override
  String get todaysPortfolioBadgeHint =>
      'Bu görünümü Ayarlar › Görünüm\'den kapatabilirsin.';

  @override
  String get todaysPortfolioSettingTitle => 'Bugünkü portföyle göster';

  @override
  String get todaysPortfolioSettingSubtitle =>
      'Performans, bugünkü varlıklarını dönem boyunca elinde tutmuşsun gibi çizilir. Kapalıyken gerçek geçmişin görünür.';

  @override
  String get settingsGroupGeneral => 'GENEL';

  @override
  String get settingsGroupPortfolioView => 'PORTFÖY GÖRÜNÜMÜ';

  @override
  String get settingsGroupSecurityAccount => 'GÜVENLİK VE HESAP';

  @override
  String get settingsGroupData => 'VERİ';

  @override
  String get settingsGroupAbout => 'UYGULAMA HAKKINDA';

  @override
  String get settingsAdvancedUpper => 'GELİŞMİŞ';

  @override
  String get settingsAdvancedSemantics => 'Gelişmiş ayarlar';

  @override
  String get settingsThemeLabel => 'Tema';

  @override
  String get settingsBaseCurrencyLabel => 'Baz para birimi';

  @override
  String get tekOnayBaslik => 'Yasal Koşullar';

  @override
  String tekOnayAciklama(String ulke) {
    return 'Uygulama yatırım tavsiyesi değildir; gösterilen fiyatlar ve teknik analiz bilgi amaçlıdır. Verilerin Supabase ($ulke) ve Firebase (ABD/Küresel) üzerinde saklanır; ayrıntısı Gizlilik Politikası ve KVKK Aydınlatma Metni\'nde.';
  }

  @override
  String get tekOnayUlkeBilinmiyor => 'yurt dışı';

  @override
  String tekOnayCumle(String kosullar, String gizlilik, String kvkk) {
    return '$kosullar\'nı kabul ediyorum ve 18 yaşından büyüğüm. $gizlilik ve $kvkk ile bilgilendirildim.';
  }

  @override
  String get tekOnayKosullarBaglanti => 'Kullanım Koşulları';

  @override
  String get tekOnayKvkkBaglanti => 'KVKK Aydınlatma Metni';

  @override
  String get tekOnayGerekli =>
      'Devam etmek için kutuyu işaretleyip Kullanım Koşulları\'nı kabul etmelisin.';

  @override
  String get arenaMeasuring => 'Fark ölçülüyor…';

  @override
  String arenaBehind(String ad, String fark) {
    return '$ad $fark puan önde · yetişebilirsin';
  }

  @override
  String get arenaNoDataYet => 'Henüz veri yok';

  @override
  String get arenaWaiting => 'Getiriler ölçülünce düello başlar';

  @override
  String get arenaStripDaily => 'Gün gün önde olan';

  @override
  String get arenaStripMonthly => 'Ay ay önde olan';

  @override
  String arenaSwaps(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n kez yer değişti',
      zero: 'Yer hiç değişmedi',
    );
    return '$_temp0';
  }

  @override
  String get yasalKapiBaslikGuncel => 'Güncellenen belgeler';

  @override
  String get yasalKapiBaslikIlk => 'Yasal belgeler';

  @override
  String get yasalKapiAciklamaGuncel =>
      'Yasal belgelerimizi güncelledik. Devam etmek için aşağıdaki adımları tamamla.';

  @override
  String get yasalKapiAciklamaIlk =>
      'Uygulamayı kullanmaya başlamadan önce aşağıdaki adımları tamamla.';

  @override
  String get yasalKapiNelerDegisti => 'Neler değişti';

  @override
  String get yasalKapiDegisiklikNotu =>
      'Sürüm 1.6: Ekstre içe aktarmada uygulama sütunlardan emin olamazsa \"Yapay zekâyla eşle\" seçeneği çıkar. Basarsan tablonun yalnızca anonim iskeleti (ad, numara, tutar ve tarihler gizli) yapay zekâya (Anthropic) gider; dosya telefonundan çıkmaz ve iskelet saklanmaz. Sürüm 1.5: Varlık notları eklendi. Portföyündeki varlıklar için haftalık notlar ve aylık rapor yapay zekâyla (Anthropic) yazılır; yapay zekâya kişisel verilerin gönderilmez, yalnızca varlığın piyasa ölçümleri gider. Notlar otomatik denetlenir ama hata içerebilir ve yatırım tavsiyesi değildir. Notlara verdiğin geri bildirim (oy, \"yanlış sayı\" işareti, açıklama) ve Premium hakkın hesabınla saklanır, hesabını silince silinir. Açık Rıza Metni değişmedi.';

  @override
  String get yasalBelgeKosullar => 'Kullanım Koşulları';

  @override
  String get yasalBelgeGizlilik => 'Gizlilik Politikası';

  @override
  String get yasalBelgeKvkk => 'KVKK Aydınlatma Metni';

  @override
  String get yasalBelgeKvkkKisa => 'KVKK Metni';

  @override
  String get yasalBelgelerTurkce => 'Belgeler Türkçedir.';

  @override
  String get yasalKapiOnayla => 'Okudum, kabul ediyorum';

  @override
  String get yasalKapiOnaylaKisa => 'Kabul ediyorum';

  @override
  String get yasalKapiKayitHatasi =>
      'Onayın kaydedilemedi. Bağlantını kontrol edip tekrar dene.';

  @override
  String get yasalKapiCikis => 'Çıkış yap';

  @override
  String get yasalBelgeAcikRiza => 'Açık Rıza Metni';

  @override
  String get yasalBelgeAcikRizaAciklama => 'Yurt dışına veri aktarımı';

  @override
  String get zorunluOkumaIpucu => 'Onaylamak için metni sona kadar oku';

  @override
  String get zorunluOkumaIpucuKisa => 'Sona kadar oku';

  @override
  String get zorunluOkumaIlerleme => 'Okuma ilerlemesi';

  @override
  String get zorunluOkumaOnayla => 'Okudum ve onaylıyorum';

  @override
  String get zorunluOkumaOnaylaKisa => 'Onaylıyorum';

  @override
  String get zorunluOkumaRizaVer => 'Okudum ve açık rıza veriyorum';

  @override
  String get zorunluOkumaRizaVerKisa => 'Açık rıza veriyorum';

  @override
  String zorunluOkumaEksik(String belgeler) {
    return 'Devam etmek için şunları sonuna kadar okuyup onaylamalısın: $belgeler';
  }

  @override
  String get yasalBelgeYatirimUyarisi => 'Yatırım Uyarısı';

  @override
  String get flowTitleUpper => 'PARA AKIŞI';

  @override
  String get flowLastWeekIn => 'Son hafta net giriş';

  @override
  String get flowLastWeekOut => 'Son hafta net çıkış';

  @override
  String get flowLastWeekFlat => 'Son hafta net akış';

  @override
  String flowRange(String from, String to) {
    return '$from - $to';
  }

  @override
  String get flowChartCaption => 'Haftalık net akış · son 8 hafta';

  @override
  String flowChartSemantics(String amount) {
    return 'Son 8 haftanın haftalık net para akışı. Son hafta $amount.';
  }

  @override
  String flowWeekOf(String date) {
    return '$date haftası';
  }

  @override
  String get flowFundSize => 'Fon büyüklüğü';

  @override
  String get flowInvestors => 'Yatırımcı sayısı';

  @override
  String flowInvestorsDelta(String count, String delta) {
    return '$count ($delta)';
  }

  @override
  String get flowEventsTitle => 'Büyük hareketler · son 30 gün';

  @override
  String flowEventIn(String date) {
    return 'Büyük giriş · $date';
  }

  @override
  String flowEventOut(String date) {
    return 'Büyük çıkış · $date';
  }

  @override
  String flowEventEvidence(String amount, String pct, String times) {
    return '$amount · fon büyüklüğüne oranı $pct · olağan günlük hareketin $times katı';
  }

  @override
  String flowEventInvestors(String delta) {
    return 'Aynı gün yatırımcı sayısı $delta';
  }

  @override
  String get flowNoEvents =>
      'Son 30 günde olağandışı büyüklükte bir giriş ya da çıkış yok.';

  @override
  String get flowExplain =>
      'Net akış, fona giren ve fondan çıkan paranın farkıdır; fiyat değişimi dahil değildir.';

  @override
  String flowFootnote(String date) {
    return 'Kaynak: TEFAS · veri tarihi $date. Kimin alıp sattığı bu veriden bilinemez. Geçmişteki para akışı gelecekteki getiriyi göstermez; yatırım tavsiyesi değildir.';
  }

  @override
  String flowStreakIn(String count) {
    return '$count haftadır üst üste net giriş';
  }

  @override
  String flowStreakOut(String count) {
    return '$count haftadır üst üste net çıkış';
  }

  @override
  String get flowPeriod1m => 'Son 1 ay';

  @override
  String get flowPeriod3m => 'Son 3 ay';

  @override
  String flowPeriodValue(String amount, String pct) {
    return '$amount · $pct';
  }

  @override
  String get flowPeriodNote =>
      'Yüzdeler, akışın dönem başındaki fon büyüklüğüne oranıdır.';

  @override
  String flowDecompose(String total, String price, String flow) {
    return 'Son 1 ayda fon büyüklüğü $total değişti: fiyat etkisi $price, para akışı $flow.';
  }

  @override
  String flowEventEvidenceMulti(String amount, String pct, String days) {
    return '$amount · fon büyüklüğüne oranı $pct · $days işlem günü üst üste';
  }

  @override
  String get weekTitle => 'Haftanın özeti';

  @override
  String get weekIntro =>
      'Tuttuğun varlıklarda son haftanın öne çıkanları. Bir satıra dokununca ayrıntısı açılır.';

  @override
  String get weekFundsUpper => 'FONLARINDA PARA AKIŞI';

  @override
  String weekRowRange(String label, String range) {
    return '$label · $range';
  }

  @override
  String get weekRowIn => 'Net giriş';

  @override
  String get weekRowOut => 'Net çıkış';

  @override
  String get weekRowFlat => 'Net akış';

  @override
  String get weekRowBigIn => 'Bu hafta büyük giriş var';

  @override
  String get weekRowBigOut => 'Bu hafta büyük çıkış var';

  @override
  String get weekEmptyNoData =>
      'Bu hafta gösterecek bir şey yok. Portföyündeki fonların para akışı ve hisse ya da kriptolarındaki olağandışı hacim günleri, verisi geldiğinde burada görünür.';

  @override
  String get weekFootnote =>
      'Kaynak: TEFAS, Yahoo Finance, Binance. Net akış fona giren ve çıkan paranın farkıdır; kimin alıp sattığı bu veriden bilinemez. Portföyünün haftalık getirisi Performans sekmesindeki Özet\'te. Yatırım tavsiyesi değildir.';

  @override
  String get weekLink => 'Tüm fonlarımın haftası';

  @override
  String get volTitleUpper => 'HACİM RADARI';

  @override
  String volLastDay(String date) {
    return 'Para hacmi · $date';
  }

  @override
  String volVsAverage(String times) {
    return 'Önceki 20 günün ortalamasının $times katı';
  }

  @override
  String volPriceSameDay(String pct) {
    return 'Aynı gün fiyat $pct';
  }

  @override
  String get volChartCaption => 'Günlük para hacmi · son 20 işlem günü';

  @override
  String volChartSemantics(String amount) {
    return 'Son 20 işlem gününün günlük para hacmi. Son gün $amount.';
  }

  @override
  String get volExplain =>
      'Para hacmi, o gün el değiştiren hisselerin toplam tutarıdır. Her işlemin bir alıcısı ve bir satıcısı vardır; yüksek hacim tek başına para girişi ya da çıkışı demek değildir.';

  @override
  String get volEventsTitle => 'Olağandışı hacim günleri · son 30 gün';

  @override
  String volEventTitle(String date) {
    return 'Olağandışı hacim · $date';
  }

  @override
  String volEventEvidence(String amount, String times, String pct) {
    return '$amount · ortalamanın $times katı · fiyat $pct';
  }

  @override
  String get volNoEvents => 'Son 30 günde olağandışı hacim günü yok.';

  @override
  String volFootnote(String date) {
    return 'Kaynak: Yahoo Finance gün sonu verisi · veri tarihi $date. Kimin alıp sattığı bu veriden bilinemez. Yatırım tavsiyesi değildir.';
  }

  @override
  String get cryTitleUpper => 'ALICI BASKISI';

  @override
  String cryShareLabel(String date) {
    return 'Alıcı payı · $date';
  }

  @override
  String cryShareAvg(String pct) {
    return 'Son 7 günün ortalaması $pct';
  }

  @override
  String get cryExplain =>
      'Alıcı payı, o günkü işlem hacminin ne kadarının piyasa emriyle alım yapanlardan geldiğini gösterir. %50\'nin üstü alıcıların, altı satıcıların daha istekli olduğu anlamına gelir; para girişi ölçüsü değildir.';

  @override
  String cryVolumeLabel(String amount) {
    return 'İşlem hacmi $amount';
  }

  @override
  String get cryChartCaption => 'Günlük işlem hacmi (USDT) · son 20 gün';

  @override
  String cryChartSemantics(String amount) {
    return 'Son 20 günün günlük işlem hacmi. Son gün $amount.';
  }

  @override
  String cryEventEvidence(
      String amount, String times, String pct, String share) {
    return '$amount · ortalamanın $times katı · fiyat $pct · alıcı payı $share';
  }

  @override
  String cryFootnote(String date) {
    return 'Kaynak: Binance, USDT paritesi · veri tarihi $date. Yalnız Binance\'teki işlemleri kapsar; kimin alıp sattığı bu veriden bilinemez. Yatırım tavsiyesi değildir.';
  }

  @override
  String get weekVolumeUpper => 'OLAĞANDIŞI HACİM';

  @override
  String weekVolumeRow(String date) {
    return 'Olağandışı hacim · $date';
  }

  @override
  String get tekOnayGizlilikBaglanti => 'Gizlilik Politikası';

  @override
  String get yasalBelgeAcildi => 'Açıldı';

  @override
  String yasalAdimKayitBaslik(int sayi) {
    return 'Kayıt için $sayi adım';
  }

  @override
  String yasalAdimKapiBaslik(int sayi) {
    return '$sayi adım';
  }

  @override
  String get yasalAdimUyariAciklama =>
      'Uygulamanın yatırım tavsiyesi olmadığını anlatan kısa metin. Sonuna kadar okuyup en altta onayla.';

  @override
  String get yasalAdimRizaAciklama =>
      'Verilerinin yurt dışına aktarılmasına açık rıza. Sonuna kadar okuyup rızanı en altta ver.';

  @override
  String get yasalAdimKutuBaslik => 'Kullanım Koşulları\'nı kabul et';

  @override
  String yasalAdimGuncellendi(String belgeler) {
    return '$belgeler güncellendi';
  }

  @override
  String yasalAdimListeVe(String onceki, String son) {
    return '$onceki ve $son';
  }

  @override
  String get yasalAdimKosulGuncelAciklama =>
      'Değişiklikleri belgeden okuyabilirsin; okuman zorunlu değil. Devam etmek için kutuyu işaretle.';

  @override
  String get yasalAdimBilgiGuncelAciklama =>
      'Bilgilendirme amaçlıdır; okuman zorunlu değil. Kutuyu işaretleyerek bilgilendirildiğini belirt.';

  @override
  String get yasalAdimOkuOnayla => 'Oku ve onayla';

  @override
  String get yasalAdimOkunduOnaylandi => 'Okundu ve onaylandı';

  @override
  String yasalAdimSemantik(int sira, int toplam, String ad, String durum) {
    return 'Adım $sira/$toplam, $ad, $durum';
  }

  @override
  String get yasalAdimDurumTamam => 'tamamlandı';

  @override
  String get yasalAdimDurumBekliyor => 'bekliyor';

  @override
  String get yasalAdimDurumSonra => 'sırası gelecek';

  @override
  String yasalAdimDigerBelgeler(int sayi) {
    return 'Diğer belgeler (bilgi amaçlı) · $sayi';
  }

  @override
  String yasalAdimSayac(int tamam, int toplam) {
    return '$tamam/$toplam adım tamamlandı';
  }

  @override
  String get yasalKapiBaslikGuncelTek => 'Güncellenen belge';

  @override
  String get streakTitle => 'Birikim serin';

  @override
  String streakMonths(String n) {
    return '$n ay art arda';
  }

  @override
  String get streakRestarted => 'Seri yeniden başladı';

  @override
  String get streakLongest => 'En uzun seri';

  @override
  String streakMonthsValue(String n) {
    return '$n ay';
  }

  @override
  String get streakPause => 'Mola hakkı';

  @override
  String get streakPauseAvailable => '1 ay, kullanılabilir';

  @override
  String streakPauseUsed(String month) {
    return 'Kullanıldı · $month ayında açılır';
  }

  @override
  String get streakOpenMonth => 'Bu ay henüz ekleme yok; ay sonuna kadar açık.';

  @override
  String get streakExplain =>
      'Portföyüne para eklediğin ayları sayar. Son 12 ayda bir boş ay seriyi bozmaz.';

  @override
  String get streakBesIncluded => 'BES otomatik katkıları dahil.';

  @override
  String get streakLegendSaving => 'birikim';

  @override
  String get streakLegendPause => 'mola';

  @override
  String get streakLegendGap => 'ara';

  @override
  String get streakLegendOpen => 'bu ay';

  @override
  String streakStripSemantics(String total, String saved) {
    return 'Son $total ay: $saved birikim ayı';
  }

  @override
  String get savingReminderTitle => 'Maaş günü hatırlatması';

  @override
  String get savingReminderOff => 'Kapalı';

  @override
  String savingReminderOn(String day) {
    return 'Ayın $day. günü, 10:30 · o ay ekleme yoksa';
  }

  @override
  String get savingReminderSheetBody =>
      'Seçtiğin gün, o ay portföyüne hiç ekleme yapmadıysan tek bir hatırlatma gelir. Ekleme yaptıysan gelmez. Seçtiğin gün o ayda yoksa (ör. Şubat\'ta 30) ayın son günü gelir.';

  @override
  String savingReminderDay(String day) {
    return 'Ayın $day. günü';
  }

  @override
  String get rdrKademeSakin => 'sakin';

  @override
  String get rdrKademeHareketli => 'hareketli';

  @override
  String get rdrKademeCok => 'çok hareketli';

  @override
  String get rdrHaftaSakin => 'Sakin hafta';

  @override
  String get rdrHaftaHareketli => 'Hareketli hafta';

  @override
  String get rdrHaftaCok => 'Çok hareketli hafta';

  @override
  String get rdrGunSakin => 'Sakin gün';

  @override
  String get rdrGunHareketli => 'Hareketli gün';

  @override
  String get rdrGunCok => 'Çok hareketli gün';

  @override
  String rdrOlcekSemantics(String kademe) {
    return 'Kendi olağanına göre: $kademe';
  }

  @override
  String get rdrAyrinti => 'Ayrıntı';

  @override
  String rdrKaynakSatiri(String kaynak, String tarih) {
    return '$kaynak · $tarih · tavsiye değildir';
  }

  @override
  String rdrYasal(String kaynak) {
    return 'Veriler $kaynak kaynaklıdır ve kimin alıp sattığını göstermez. Geçmişteki hareket gelecekteki getiriyi göstermez; yatırım tavsiyesi değildir.';
  }

  @override
  String get rdrNasilOkunur => 'Nasıl okunur';

  @override
  String get rdrKoc1 =>
      'Üstteki cümle bu varlığın son durumunu tek satırda anlatır. Altındaki sayı o cümlenin kanıtıdır.';

  @override
  String get rdrKoc2 =>
      'Ölçek, sayının bu varlığın kendi olağanına göre ne kadar büyük olduğunu gösterir: sakin, hareketli, çok hareketli.';

  @override
  String get rdrKoc3 =>
      'Altı noktalı kelimelere dokunursan ne anlama geldiğini görürsün.';

  @override
  String rdrKocAdim(String adim) {
    return '$adim / 3';
  }

  @override
  String get rdrIleri => 'İleri';

  @override
  String get rdrAnladim => 'Anladım';

  @override
  String get rdrTerimNetAkis => 'Net akış';

  @override
  String get rdrTerimNetAkisTanim =>
      'Fona giren paradan çıkan para düşülünce kalan tutar. Fon fiyatının artması ya da düşmesi buna girmez; yalnız yatırımcıların koyduğu ve çektiği para sayılır.';

  @override
  String get rdrTerimBuyukluk => 'Fon büyüklüğü';

  @override
  String get rdrTerimBuyuklukTanim =>
      'Fondaki toplam paranın bugünkü değeri. Hem yeni para girince hem de fonun içindekiler değer kazanınca büyür.';

  @override
  String get rdrTerimAyristirma => 'Fiyat ve yeni para';

  @override
  String get rdrTerimAyristirmaTanim =>
      'Fon büyüklüğündeki değişim iki kaynaktan gelir: fondaki varlıkların değerinin değişmesi (fiyat) ve yatırımcıların koyup çektiği para (yeni para). İkisinin toplamı büyüklük değişimidir.';

  @override
  String get rdrTerimYatirimci => 'Yatırımcı sayısı';

  @override
  String get rdrTerimYatirimciTanim =>
      'Fonda payı olan kişi sayısı. Aynı tutar az kişiden büyük paralarla da, çok kişiden küçük paralarla da gelebilir; bu sayı farkı gösterir.';

  @override
  String get rdrTerimSira => 'Kategoride akış sırası';

  @override
  String get rdrTerimSiraTanim =>
      'Aynı TEFAS kategorisindeki fonların, aynı hafta en çok net para girişi olandan en çok net çıkışı olana sırası. Yalnız o haftanın her gününde verisi olan fonlar sıralanır.';

  @override
  String get rdrTerimBuyukHareket => 'Büyük hareket';

  @override
  String get rdrTerimBuyukHareketTanim =>
      'Bir günde giren ya da çıkan paranın hem fon büyüklüğünün en az %3\'ü hem de fonun olağan günlük hareketinin en az 4 katı olması. İkisi birden olmadıkça işaretlenmez; ₺250 mn altındaki fonlarda ve para piyasası fonlarında hiç işaretlenmez.';

  @override
  String get rdrTerimOlcek => 'Ölçek';

  @override
  String get rdrTerimOlcekTanim =>
      'Sayının bu varlığın kendi geçmişine göre büyüklüğü. Fonda son hafta önceki haftaların ortalamasıyla, hissede son günün hacmi önceki 20 günün ortalamasıyla kıyaslanır. Kriptoda alıcı payının %50\'den uzaklığına bakılır: 2 puan hareketli, 5 puan çok hareketli. O gün büyük hareket ya da olağandışı hacim işaretlendiyse ölçek en üsttedir.';

  @override
  String get rdrTerimHacim => 'Para hacmi';

  @override
  String get rdrTerimHacimTanim =>
      'O gün el değiştiren hisselerin toplam tutarı. Her işlemin bir alıcısı ve bir satıcısı vardır; yüksek hacim tek başına para girişi demek değildir.';

  @override
  String get rdrTerimKat => 'Ortalamanın katı';

  @override
  String get rdrTerimKatTanim =>
      'Son günün hacminin önceki 20 işlem gününün ortalamasına oranı. 1 kat olağan bir gün demektir.';

  @override
  String get rdrTerimOlagandisi => 'Olağandışı hacim';

  @override
  String get rdrTerimOlagandisiTanim =>
      'Hacmin önceki 20 günün ortalamasının en az 2 katı olduğu ve bu sıçramanın o varlığın olağan dalgalanmasının çok dışında kaldığı gün.';

  @override
  String get rdrTerimAliciPayi => 'Alıcı payı';

  @override
  String get rdrTerimAliciPayiTanim =>
      'İşlem hacminin ne kadarının hemen almak isteyenlerden (piyasa emriyle alanlardan) geldiği. %50\'nin üstü alıcıların, altı satıcıların daha istekli olduğunu gösterir. Para girişi ölçüsü değildir. Birden çok günde hacim ağırlıklıdır: işlemi çok olan gün daha çok sayılır.';

  @override
  String get rdrTerimNetAlim => 'Net alım';

  @override
  String get rdrTerimNetAlimTanim =>
      'Piyasa emriyle alanların hacminden satanların hacmi düşülünce kalan tutar (USDT). Yalnız Binance\'teki işlemleri kapsar.';

  @override
  String rdrTerimOrnek(String deger) {
    return 'Bu varlıkta: $deger';
  }

  @override
  String get rdrFonGirisSakin => 'Bu fona son hafta olağan ölçüde para girdi.';

  @override
  String get rdrFonGirisHareketli =>
      'Bu fona son hafta olağandan fazla para girdi.';

  @override
  String get rdrFonGirisCok =>
      'Bu fona son hafta olağanın çok üstünde para girdi.';

  @override
  String get rdrFonCikisSakin =>
      'Bu fondan son hafta olağan ölçüde para çıktı.';

  @override
  String get rdrFonCikisHareketli =>
      'Bu fondan son hafta olağandan fazla para çıktı.';

  @override
  String get rdrFonCikisCok =>
      'Bu fondan son hafta olağanın çok üstünde para çıktı.';

  @override
  String get rdrFonGiris => 'Bu fona son hafta para girdi.';

  @override
  String get rdrFonCikis => 'Bu fondan son hafta para çıktı.';

  @override
  String get rdrFonDenge =>
      'Bu fonda son hafta giren ve çıkan para dengedeydi.';

  @override
  String get rdrFonKarisik => 'Bu fonda son hafta büyük para hareketi oldu.';

  @override
  String rdrFonNetAralik(String aralik) {
    return 'net akış · $aralik';
  }

  @override
  String get rdrSon8Hafta => 'son 8 hafta';

  @override
  String rdrBuyukHareketSayisi(String sayi) {
    return '$sayi büyük hareket';
  }

  @override
  String get rdrBuyukHareketYok => 'büyük hareket yok';

  @override
  String rdrFonDetayBaslik(String kod) {
    return '$kod · Para akışı';
  }

  @override
  String get rdrHaftayaDokun =>
      'Bir haftaya dokun, o haftanın rakamı burada görünür.';

  @override
  String rdrSecilenHafta(String aralik) {
    return '$aralik haftası';
  }

  @override
  String get rdrVeriYok => 'veri yok';

  @override
  String rdrAyristirmaCumle(String yuzde) {
    return 'Son 1 ayda fon büyüklüğü $yuzde değişti.';
  }

  @override
  String rdrFiyat(String yuzde) {
    return 'fiyat $yuzde';
  }

  @override
  String rdrYeniPara(String yuzde) {
    return 'yeni para $yuzde';
  }

  @override
  String rdrOlaganinKati(String kat) {
    return 'olağan haftanın $kat katı';
  }

  @override
  String get rdrDonemUpper => 'DÖNEM';

  @override
  String get rdrBaglamUpper => 'BAĞLAM';

  @override
  String get rdrSiraUpper => 'KATEGORİDE AKIŞ SIRASI';

  @override
  String rdrSiraAlt(String kategori) {
    return '$kategori · aynı haftanın net akışına göre sıra';
  }

  @override
  String get rdrSiraBuFon => 'bu fon';

  @override
  String rdrSiraToplam(String sayi) {
    return '$sayi fon içinde';
  }

  @override
  String get rdrHareketlerUpper => 'BÜYÜK HAREKETLER · SON 30 GÜN';

  @override
  String rdrHisseSakin(String tarih) {
    return '$tarih günü bu hissede olağan miktarda işlem yapıldı.';
  }

  @override
  String rdrHisseHareketli(String tarih) {
    return '$tarih günü bu hissede olağandan fazla işlem yapıldı.';
  }

  @override
  String rdrHisseCok(String tarih) {
    return '$tarih günü bu hissede olağanın çok üstünde işlem yapıldı.';
  }

  @override
  String rdrHisseYalin(String tarih, String tutar) {
    return '$tarih günü bu hissede $tutar tutarında işlem yapıldı.';
  }

  @override
  String rdrHacimAlt(String yuzde) {
    return 'para hacmi · fiyat $yuzde';
  }

  @override
  String get rdrHacimAltFiyatsiz => 'para hacmi';

  @override
  String get rdrOrtalamaCizgisi => 'kesikli çizgi: önceki 20 günün ortalaması';

  @override
  String rdrHacimDetayBaslik(String kod) {
    return '$kod · Hacim radarı';
  }

  @override
  String get rdrGuneDokun =>
      'Bir güne dokun, o günün hacmi ve fiyatı burada görünür.';

  @override
  String rdrSecilenGun(String tarih, String tutar, String yuzde) {
    return '$tarih: $tutar · fiyat $yuzde';
  }

  @override
  String rdrSecilenGunFiyatsiz(String tarih, String tutar) {
    return '$tarih: $tutar';
  }

  @override
  String get rdrOlagandisiUpper => 'OLAĞANDIŞI HACİM GÜNLERİ · SON 30 GÜN';

  @override
  String rdrKriptoAlici(String tarih) {
    return '$tarih günü alanlar satanlardan daha istekliydi.';
  }

  @override
  String rdrKriptoAliciCok(String tarih) {
    return '$tarih günü alanlar satanlardan belirgin biçimde daha istekliydi.';
  }

  @override
  String rdrKriptoSatici(String tarih) {
    return '$tarih günü satanlar alanlardan daha istekliydi.';
  }

  @override
  String rdrKriptoSaticiCok(String tarih) {
    return '$tarih günü satanlar alanlardan belirgin biçimde daha istekliydi.';
  }

  @override
  String rdrKriptoDenge(String tarih) {
    return '$tarih günü alanlar ile satanlar dengedeydi.';
  }

  @override
  String rdrAlici(String yuzde) {
    return 'Alıcı $yuzde';
  }

  @override
  String rdrSatici(String yuzde) {
    return 'Satıcı $yuzde';
  }

  @override
  String rdrYediGunOrt(String yuzde) {
    return '7 günde alıcı payı: $yuzde';
  }

  @override
  String get rdrSaatlikUpper => 'SON 24 SAAT · SAAT SAAT NET ALIM';

  @override
  String rdrEnIstekliSaat(String aralik, String tutar) {
    return '$aralik alıcıların en istekli olduğu saat · $tutar net alım';
  }

  @override
  String get rdrIstekliSaatYok =>
      'Son 24 saatte alıcıların ağır bastığı bir saat olmadı.';

  @override
  String rdrSonMum(String saat) {
    return 'son mum $saat';
  }

  @override
  String rdrKriptoDetayBaslik(String kod) {
    return '$kod · Alıcı baskısı';
  }

  @override
  String get rdrIslemHacmiUpper => 'İŞLEM HACMİ · SON 20 GÜN';

  @override
  String rdrHaftaBaslikVar(String sayi) {
    return 'Son haftada $sayi varlığında olağandışı hareket var.';
  }

  @override
  String get rdrHaftaBaslikYok =>
      'Son haftada varlıklarında olağandışı bir hareket yok.';

  @override
  String get rdrRozetBuyukGiris => 'Büyük giriş';

  @override
  String get rdrRozetBuyukCikis => 'Büyük çıkış';

  @override
  String get rdrRozetHacim => 'Olağandışı hacim';

  @override
  String get rdrRozetAlici => 'Alıcı istekli';

  @override
  String get rdrRozetSatici => 'Satıcı istekli';

  @override
  String get rdrRozetHareketli => 'Hareketli';

  @override
  String get rdrRozetSakin => 'Sakin';

  @override
  String rdrSatirFon(String tutar, String yuzde) {
    return 'Net $tutar · büyüklüğün $yuzde';
  }

  @override
  String rdrSatirFonOransiz(String tutar) {
    return 'Net $tutar';
  }

  @override
  String rdrSatirHacim(String tarih, String kat, String yuzde) {
    return '$tarih · hacim $kat kat · fiyat $yuzde';
  }

  @override
  String rdrSatirKripto(String ort, String yuzde) {
    return '7 günde alıcı payı $ort · son gün $yuzde';
  }

  @override
  String rdrYatirimciHafta(String sayi, String fark) {
    return '$sayi · son hafta $fark';
  }

  @override
  String rdrKartHaftaOlayi(String olay) {
    return 'Son 7 günde olağandışı gün: $olay';
  }

  @override
  String rdrDunAralik(String aralik) {
    return 'Dün $aralik';
  }

  @override
  String get rdrSaateDokun =>
      'Bir saate dokun, o saatin net alımı ve alıcı payı burada görünür.';

  @override
  String get anzYararli => 'İşime yaradı';

  @override
  String get anzYararsiz => 'İşime yaramadı';

  @override
  String rdrSatirKriptoOrtsuz(String yuzde) {
    return 'Son gün alıcı payı $yuzde';
  }

  @override
  String rdrSatirNot(String metin) {
    return 'Not: $metin';
  }

  @override
  String get rdrHaftaKaynak =>
      'Fon akışı TEFAS · hacim Yahoo Finance · kripto Binance · tavsiye değildir';

  @override
  String rdrAylikRaporSatir(String ay) {
    return '$ay raporu';
  }

  @override
  String get rdrOku => 'Oku';

  @override
  String rdrSeritSayi(String sayi) {
    return '$sayi varlığında son haftada olağandışı hareket var';
  }

  @override
  String get rdrAyarHareketSatiri => 'Pazartesi özetinde hareket satırı';

  @override
  String get rdrAyarHareketSatiriAlt =>
      'Haftalık bildirimde fonlarındaki büyük giriş-çıkışı ve olağandışı hacmi de yaz.';

  @override
  String get rdrAyarSakinGoster => 'Sakin varlıkları özette göster';

  @override
  String get rdrAyarSakinGosterAlt =>
      'Haftanın özetinde hareketsiz geçen varlıkları da listele.';

  @override
  String get prmUcretsiz => 'Ücretsiz';

  @override
  String get prmPremium => 'Premium';

  @override
  String get prmSatirVarlik => 'Varlık';

  @override
  String get prmSatirAkis => 'Para akışı';

  @override
  String get prmSatirHacim => 'Hacim radarı';

  @override
  String get prmSatirNot => 'Haftalık not';

  @override
  String get prmSatirAylik => 'Aylık rapor';

  @override
  String get prmSinirsiz => 'sınırsız';

  @override
  String prmYillikTasarruf(String oran) {
    return '%$oran tasarruf';
  }

  @override
  String get prmVarErisim => 'Var';

  @override
  String get prmYokErisim => 'Yok';

  @override
  String get prmAkisUcretsiz => 'son hafta';

  @override
  String get prmAkisPremium => '8 hafta + olaylar';

  @override
  String get prmHacimUcretsiz => 'son gün';

  @override
  String get prmHacimPremium => '20 gün';

  @override
  String get prmNotUcretsiz => 'ilk cümle';

  @override
  String get prmNotPremium => 'tamamı';

  @override
  String prmKilitAkis(String sayi) {
    return '8 haftalık seyir ve $sayi büyük hareket Premium\'da';
  }

  @override
  String get prmKilitAyrinti => 'Ayrıntılar Premium\'da';

  @override
  String get prmKilitNot => 'Notun tamamı Premium\'da';

  @override
  String get prmKilitEkstreAi => 'Yapay zekâyla eşleme Premium\'da';

  @override
  String get prmSatirEkstreAi => 'Ekstreyi yapay zekâyla okutma';

  @override
  String get prmHediyeBaslik => 'İlk kullanıcılarımızdansın';

  @override
  String prmHediyeGovde(String gun, String tarih) {
    return '$gun gün Premium senin; kart bilgisi gerekmez. $tarih tarihinde biter, bitince verilerinden hiçbiri silinmez.';
  }

  @override
  String get prmTesekkurler => 'Teşekkürler';

  @override
  String get prmAbonelikAylik => 'Premium · aylık';

  @override
  String get prmAbonelikYillik => 'Premium · yıllık';

  @override
  String get prmAbonelikHediye => 'Premium · erken kullanıcı hediyesi';

  @override
  String prmYenileme(String tarih, String magaza) {
    return 'Yenileme $tarih · $magaza';
  }

  @override
  String prmBitis(String tarih) {
    return '$tarih tarihinde biter';
  }

  @override
  String get prmYonet => 'Yönet';

  @override
  String get prmGeriYukle => 'Satın alımları geri yükle';

  @override
  String get anzNotUpper => 'HAFTALIK NOT · YAPAY ZEKÂ';

  @override
  String anzMeta(String sayi, String aralik) {
    return '$sayi madde · $aralik';
  }

  @override
  String get anzNotuOku => 'Notu oku';

  @override
  String anzDetayBaslik(String kod) {
    return '$kod · haftalık not';
  }

  @override
  String anzAylikDetayBaslik(String kod) {
    return '$kod · aylık not';
  }

  @override
  String anzAltSatir(String kaynak, String tarih) {
    return 'Yapay zekâ ile oluşturuldu · girdi $kaynak, $tarih · yatırım tavsiyesi değildir';
  }

  @override
  String get anzIseYaradi => 'İşine yaradı mı?';

  @override
  String get anzYanlisSayi => 'Yanlış bir sayı gördüm';

  @override
  String get anzYanlisIpucu => 'Hangi sayı yanlış? (isteğe bağlı)';

  @override
  String get anzGonder => 'Gönder';

  @override
  String get anzTesekkur => 'Teşekkürler, not incelenecek.';

  @override
  String get anzAylikUpper => 'AYLIK RAPOR';

  @override
  String anzAylikBaslik(String ay) {
    return '$ay raporu';
  }

  @override
  String anzAylikOzetVar(String toplam, String sayi) {
    return 'Notu çıkan $toplam varlığından $sayi tanesinde ay boyunca belirgin hareket oldu.';
  }

  @override
  String anzAylikEksik(String kodlar) {
    return '$kodlar için bu ay not çıkmadı; sayıları kendi sayfalarında.';
  }

  @override
  String get anzAylikOzetYok =>
      'Bu ay varlıklarında belirgin bir hareket olmadı.';

  @override
  String get anzAylikBos => 'Bu ayın raporu henüz hazır değil.';

  @override
  String get anzOkunamadi => 'Not şu an açılamadı.';
}
