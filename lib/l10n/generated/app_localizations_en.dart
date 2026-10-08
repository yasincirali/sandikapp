// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'sandık';

  @override
  String get loginTagline => 'Grow your treasure together.';

  @override
  String get email => 'Email';

  @override
  String get emailInvalid => 'Enter a valid email';

  @override
  String get password => 'Password';

  @override
  String get passwordShow => 'Show password';

  @override
  String get passwordHide => 'Hide password';

  @override
  String get passwordMin6 => 'At least 6 characters';

  @override
  String get passwordRequired => 'Password required';

  @override
  String get rememberMe => 'Remember me';

  @override
  String get forgotPassword => 'Forgot password';

  @override
  String get signIn => 'Sign In';

  @override
  String get noAccountRegister => 'Don\'t have an account? Sign up';

  @override
  String get register => 'Sign Up';

  @override
  String get registerWelcome => 'Welcome to your sandık.';

  @override
  String get registerSubtitle => 'Create your account in a few steps.';

  @override
  String get fullName => 'Full Name';

  @override
  String get fullNameRequired => 'Enter your full name';

  @override
  String get passwordRepeat => 'Repeat Password';

  @override
  String get passwordsMismatch => 'Passwords do not match';

  @override
  String get sifreKuralUzunluk => 'At least 8 characters';

  @override
  String get sifreKuralHarf => 'At least one letter';

  @override
  String get sifreKuralRakam => 'At least one number';

  @override
  String get haveAccountSignIn => 'Already have an account? Sign in';

  @override
  String get exitAppTitle => 'Exit the app';

  @override
  String get exitAppMessage => 'Are you sure you want to exit?';

  @override
  String get exit => 'Exit';

  @override
  String get tabHome => 'Home';

  @override
  String get tabPortfolio => 'Portfolio';

  @override
  String get tabPerformance => 'Performance';

  @override
  String get tabProfile => 'Profile';

  @override
  String get addAsset => 'Add asset';

  @override
  String get lockTitle => 'sandık is locked';

  @override
  String get lockFailed => 'Verification failed. Try again.';

  @override
  String get lockPrompt => 'Verify your identity to see your portfolio.';

  @override
  String get lockVerifying => 'Verifying…';

  @override
  String get lockNoDeviceCredential =>
      'Your device has no screen lock (Face ID, fingerprint or passcode) set up, so it cannot verify you.';

  @override
  String get lockDisableAndContinue => 'Turn off the lock and continue';

  @override
  String get lockSwitchAccount => 'Sign in with a different account';

  @override
  String get lockSwitchAccountTitle => 'Sign out';

  @override
  String get lockSwitchAccountBody =>
      'You will be signed out of this account and returned to the login screen. Your data is not deleted; it will be there when you sign back in.';

  @override
  String get unlock => 'Unlock';

  @override
  String get disclaimerTitle => 'Legal Notice';

  @override
  String get disclaimerIntro =>
      'To continue using the app, please read and accept the legal notice below.';

  @override
  String get disclaimerAcceptRow =>
      'I have read and accept the legal notice above.';

  @override
  String get disclaimerMustAccept =>
      'You must accept the legal notice to continue.';

  @override
  String get accept => 'I Accept';

  @override
  String get forgotTitle => 'Forgot Password';

  @override
  String get forgotIntro =>
      'Enter the email address we should send the code to.';

  @override
  String get sendCode => 'Send Code';

  @override
  String codeSentTo(String email) {
    return 'We sent a code to $email. Enter the code and your new password.';
  }

  @override
  String get code => 'Code';

  @override
  String get codeInvalid => 'Code missing or invalid';

  @override
  String get newPassword => 'New Password';

  @override
  String get newPasswordRepeat => 'Repeat New Password';

  @override
  String get updatePassword => 'Update Password';

  @override
  String get tryAnotherEmail => 'Try with a different email';

  @override
  String get passwordUpdatedTitle => 'Password updated';

  @override
  String get passwordUpdatedMessage =>
      'You can sign in with your new password. You will be taken to the home screen now.';

  @override
  String get otpTitle => 'Verify your email';

  @override
  String get otpExpired => 'The code has expired. Request a new one.';

  @override
  String get otpEnterFull => 'Please enter the full 6-digit code.';

  @override
  String get otpSentTitle => 'Code sent';

  @override
  String get otpSentMessage => 'A new 6-digit code was sent to your email.';

  @override
  String get otpExpiredShort => 'Code expired';

  @override
  String otpExpiresIn(String time) {
    return 'Code becomes invalid in $time';
  }

  @override
  String get sending => 'Sending…';

  @override
  String get requestNewCode => 'Request New Code';

  @override
  String get verify => 'Verify';

  @override
  String get otpNotReceived => 'Didn\'t get the code? ';

  @override
  String get resend => 'Resend';

  @override
  String resendIn(int seconds) {
    return 'Resend (${seconds}s)';
  }

  @override
  String get otpWrongEmail => 'Entered the wrong email? Go back and try again.';

  @override
  String get settings => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsAccount => 'Account & Security';

  @override
  String get settingsHelp => 'Help & Legal';

  @override
  String get settingsAppearanceSubtitle =>
      'Theme, base currency, language, investor level';

  @override
  String get settingsAccountSubtitle =>
      'Biometric lock, registered devices, download your data, delete account';

  @override
  String get settingsHelpSubtitle => 'Contact us, tour, privacy and terms';

  @override
  String get themeSystem => 'System';

  @override
  String get themeLight => 'Light';

  @override
  String get themeDark => 'Dark';

  @override
  String get language => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get languageTurkish => 'Türkçe';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageNote =>
      'English is in beta: legal texts, the intro tour and gold/fund sub-category names stay Turkish.';

  @override
  String get textSize => 'Text size';

  @override
  String get textSizeSmall => 'Small';

  @override
  String get textSizeNormal => 'Default';

  @override
  String get textSizeLarge => 'Large';

  @override
  String get textSizeXLarge => 'Extra large';

  @override
  String get textSizeNote =>
      'Applied on top of your phone\'s text size setting. Enlarging has a limit so screens stay intact.';

  @override
  String textSizeSemantics(String name) {
    return '$name text size';
  }

  @override
  String get investorLevel => 'Investor level';

  @override
  String get investorLevelNote =>
      'Only changes WHICH metrics are shown; your calculations and data stay the same.';

  @override
  String get levelBeginner => 'Beginner';

  @override
  String get levelIntermediate => 'Intermediate';

  @override
  String get levelAdvanced => 'Advanced';

  @override
  String get levelIntermediateDesc =>
      'Today\'s view: technical signals, percentile, health card and annual return since your first buy.';

  @override
  String get levelAdvancedDesc =>
      'Intermediate + return per unit of risk, effect of your buy timing and recovery from drops (Summary › 1Y).';

  @override
  String get noAssetsYet => 'No assets added yet';

  @override
  String get addAssetTitle => 'Add Asset';

  @override
  String get editAsset => 'Edit';

  @override
  String get add => 'Add';

  @override
  String get update => 'Update';

  @override
  String get save => 'Save';

  @override
  String get assetType => 'Asset Type';

  @override
  String get assetName => 'Asset name';

  @override
  String get nameRequired => 'Name required';

  @override
  String get quantity => 'Quantity';

  @override
  String get quantityInvalid => 'Valid quantity';

  @override
  String get purchasePrice => 'Purchase Price';

  @override
  String get optional => '· optional';

  @override
  String get auto => 'Automatic';

  @override
  String get invalid => 'Invalid';

  @override
  String get commission => 'Commission / Fees';

  @override
  String get cannotBeNegative => 'Cannot be negative';

  @override
  String get allTypes => 'All';

  @override
  String scopeCategory(String label) {
    return 'Category: $label';
  }

  @override
  String get retry => 'Retry';

  @override
  String get cancel => 'Cancel';

  @override
  String quickAllChip(String qty) {
    return 'All ($qty)';
  }

  @override
  String get quickHolding => 'Holding';

  @override
  String quickAvgShort(String price) {
    return 'avg. $price';
  }

  @override
  String get quickUnitPrice => 'Unit price';

  @override
  String get quickTotalCost => 'Total cost';

  @override
  String get delete => 'Delete';

  @override
  String get sell => 'Sell';

  @override
  String get dividend => 'Dividend';

  @override
  String get profile => 'Profile';

  @override
  String get portfolio => 'Portfolio';

  @override
  String get myAssets => 'My Assets';

  @override
  String get watchlist => 'Watchlist';

  @override
  String get priceUpdateFailed =>
      'Prices could not be updated. Showing older data.';

  @override
  String get otpSentPrefix => 'We sent the 6-digit code to\n';

  @override
  String get otpSentSuffix => '';

  @override
  String get registerNameMissing => 'Enter your full name.';

  @override
  String get registerEmailInvalid => 'Enter a valid email.';

  @override
  String get registerPasswordsMismatch => 'Passwords do not match.';

  @override
  String get refreshPrices => 'Refresh prices';

  @override
  String get portfolioActivity => 'PORTFOLIO ACTIVITY';

  @override
  String get seeAllTransactions => 'See all transactions';

  @override
  String seeAllCount(int count) {
    return 'See All ($count)';
  }

  @override
  String get signalDeleteFailed =>
      'Could not delete the notification. Check your connection.';

  @override
  String get permanentDelete => 'Delete permanently';

  @override
  String signalDeleteChoice(int past, int active) {
    return 'There are $past past and $active active notifications. What should be deleted?';
  }

  @override
  String get cancelShort => 'Cancel';

  @override
  String get onlyHistory => 'History only';

  @override
  String get clearAllSignals => 'Clear all signals';

  @override
  String get clearAllLower => 'Clear all';

  @override
  String clearAllSignalsBody(int count) {
    return '$count notifications will move to history. To delete them for good, use the \"Delete History\" button there.';
  }

  @override
  String get clearVerb => 'Clear';

  @override
  String get clearAllUpper => 'Clear All';

  @override
  String get noActiveSignals => 'No active signals right now';

  @override
  String get historyUpper => 'HISTORY';

  @override
  String deleteHistoryCount(int count) {
    return 'Permanently delete $count notifications from history';
  }

  @override
  String get deleteHistoryTitle => 'Delete history';

  @override
  String deleteHistoryBody(int count) {
    return '$count notifications will be deleted PERMANENTLY. This cannot be undone.';
  }

  @override
  String get permanentDeleteUpper => 'Delete Permanently';

  @override
  String get deleteHistoryButton => 'Delete History';

  @override
  String get signalNeutral => 'NEUTRAL';

  @override
  String signalDeletedAt(String date) {
    return '$date · deleted';
  }

  @override
  String signalConfidence(int count, String pct) {
    return '$count indicators · $pct confidence';
  }

  @override
  String get showBalance => 'Show balance';

  @override
  String get hideBalance => 'Hide balance';

  @override
  String get sortCriterion => 'SORT BY';

  @override
  String tabSemanticsCount(String label, int count) {
    return '$label, $count assets';
  }

  @override
  String get noChange => 'No change';

  @override
  String get buyAction => 'Buy';

  @override
  String get sellAction => 'Sell';

  @override
  String get deleteAction => 'Delete';

  @override
  String activeAlertsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count active price alerts',
      one: '1 active price alert',
    );
    return '$_temp0';
  }

  @override
  String get lastMonth => 'Last month';

  @override
  String get firstPurchase => 'First Purchase';

  @override
  String get avgCost => 'Avg. Cost';

  @override
  String get totalCost => 'Total Cost';

  @override
  String get currentValue => 'Current Value';

  @override
  String get dividendReceived => 'Dividends Received';

  @override
  String lotSummary(int buys, int sells) {
    String _temp0 = intl.Intl.pluralLogic(
      buys,
      locale: localeName,
      other: '$buys buys',
      one: '1 buy',
    );
    String _temp1 = intl.Intl.pluralLogic(
      sells,
      locale: localeName,
      other: '$buys buys · $sells removals',
      zero: '$_temp0',
    );
    return '$_temp1';
  }

  @override
  String get sortMarketValue => 'Market Value';

  @override
  String get sortHighToLow => 'High to Low';

  @override
  String get sortLowToHigh => 'Low to High';

  @override
  String get sortGainTry => 'Gain (TRY)';

  @override
  String get sortGainPct => 'Gain (%)';

  @override
  String get sortHighestFirst => 'Highest First';

  @override
  String get sortLowestFirst => 'Lowest First';

  @override
  String get assetFullName => 'Full Name';

  @override
  String get fundReportTitleUpper => 'FUND REPORT CARD';

  @override
  String fundReportCategory(String category, String count) {
    return '$category · $count funds';
  }

  @override
  String get fundReportPeriod1m => '1 month';

  @override
  String get fundReportPeriodYtd => 'Year to date';

  @override
  String get fundReportPeriod1y => '1 year';

  @override
  String fundReportRank(String count, String rank) {
    return '#$rank of $count';
  }

  @override
  String fundReportReturnVsMedian(String ret, String median) {
    return 'Return $ret · category median $median';
  }

  @override
  String fundReportAboveMedian(String pts) {
    return '$pts pts above the median';
  }

  @override
  String fundReportBelowMedian(String pts) {
    return '$pts pts below the median';
  }

  @override
  String get fundReportAtMedian => 'At the median';

  @override
  String get fundReportFootnote =>
      'Source: TEFAS. Returns are as published by TEFAS; its calculation dates don\'t exactly match the chart\'s period, so they may differ slightly from the period return above. Compared with funds in the same category; past returns do not indicate future returns.';

  @override
  String fundReportPanelLine(String count, String rank, String period) {
    return '#$rank of $count in its category ($period)';
  }

  @override
  String get assetTypeStock => 'Stocks';

  @override
  String get assetTypeFund => 'Funds';

  @override
  String get assetTypeFx => 'Currency';

  @override
  String get assetTypeGold => 'Gold';

  @override
  String get assetTypeCrypto => 'Crypto';

  @override
  String get assetTypeCommodity => 'Commodities';

  @override
  String get assetTypeOther => 'Other';

  @override
  String get tickerHintStock =>
      'e.g. THYAO.IS, GARAN.IS  (add .IS for Borsa İstanbul)';

  @override
  String get tickerHintFund =>
      'Leave empty if there is no Yahoo Finance code and enter the price manually';

  @override
  String get tickerHintFx => 'e.g. USDTRY=X, EURTRY=X, GBPTRY=X';

  @override
  String get tickerHintGold =>
      'e.g. XAUTRY=X (gram gold in TRY) or GC=F (ounce, USD)';

  @override
  String get tickerHintCrypto => 'Pick from the list, e.g. BTC, ETH';

  @override
  String get tickerHintCommodity =>
      'e.g. CL=F (oil), NG=F (natural gas), GC=F (gold ounce)';

  @override
  String get tickerHintOther => 'A Yahoo Finance symbol, or leave it empty';

  @override
  String assetTypeSemantics(String type) {
    return '$type type';
  }

  @override
  String get total => 'total';

  @override
  String get bulkAdd => 'Bulk add';

  @override
  String get quickEntryVoice => 'Voice / Quick entry';

  @override
  String get orNotInList => 'or not in the list';

  @override
  String get symbolHint => 'Type a symbol (e.g. AAPL, THYAO.IS)';

  @override
  String get companyNameHint =>
      'Company name (optional, fetched from the symbol)';

  @override
  String goldSemantics(String kind) {
    return '$kind gold';
  }

  @override
  String get commissionNote =>
      'Trading commission is added to your cost, so profit/loss shows the real figure.';

  @override
  String totalCostTlEquivalent(String amount, String currency, String rate) {
    return '≈ $amount · 1 $currency = $rate';
  }

  @override
  String get costPreviewHint =>
      'Enter a quantity and the total cost appears here.';

  @override
  String get totalCostUpper => 'TOTAL COST';

  @override
  String get transactionDate => 'Transaction date';

  @override
  String get addNote => 'Add a note';

  @override
  String get notesHint => 'Your notes...';

  @override
  String get txHasNote => 'Has a note';

  @override
  String txOpenNote(String name) {
    return '$name transaction, add a note';
  }

  @override
  String txOpenNoteWithNote(String name) {
    return '$name transaction, has a note, open note';
  }

  @override
  String get noteSaved => 'Note saved';

  @override
  String get noteRemoved => 'Note removed';

  @override
  String get noteSaveFailed => 'Couldn\'t save the note';

  @override
  String get noteRemove => 'Remove note';

  @override
  String get noteNone => 'No note on this transaction.';

  @override
  String get noteAddHint =>
      'Why did you buy it, what\'s your target? Write a short note.';

  @override
  String get alertTargetAtCurrent =>
      'Target equals the current price, so the alert would fire right away. Enter a price above or below it.';

  @override
  String get notifTypeDividend => 'Dividend';

  @override
  String get dividendHistoryUpper => 'DIVIDENDS · LAST 12 MONTHS';

  @override
  String dividendRecordedTotal(String amount) {
    return 'Recorded: $amount';
  }

  @override
  String dividendEventLine(String lot, String perShare) {
    return '$lot shares × $perShare';
  }

  @override
  String dividendGrossAmount(String amount) {
    return '$amount gross';
  }

  @override
  String get dividendRecorded => 'Recorded';

  @override
  String get dividendRecordAction => 'Record';

  @override
  String get dividendSourceNote =>
      'Paid dividends per Yahoo Finance, using your shares on the ex-date. Amounts are gross; \"Save\" prefills the net after 15% withholding tax, which you can edit.';

  @override
  String dividendSuggestionLine(String ticker, String date) {
    return '$ticker · ex-date $date';
  }

  @override
  String dividendSuggestionGross(String lot, String perShare, String gross) {
    return '$lot shares × $perShare = $gross gross';
  }

  @override
  String dividendWithholdingAssumed(String rate, String cut, String net) {
    return '$rate withholding tax (−$cut) deducted: net $net. Edit if different.';
  }

  @override
  String dividendEnterNet(String gross) {
    return 'Gross $gross. Enter what you received after withholding tax.';
  }

  @override
  String get noteReadOnlyPartner =>
      'This record belongs to your partner; only they can edit its note.';

  @override
  String get noteReadOnlyDeleted =>
      'A deleted record\'s note can\'t be edited.';

  @override
  String get notesSection => 'Notes';

  @override
  String moreNotesCount(int count) {
    return '+$count more notes · in All Transactions';
  }

  @override
  String get searchAssetSymbolOrNote => 'Search asset, symbol or note';

  @override
  String quantitySemantics(String value) {
    return 'Quantity $value';
  }

  @override
  String get quickEntryTitle => 'Quick Entry';

  @override
  String get quickEntryHelp =>
      'One asset per line. Price is optional: leave it blank and the current price is fetched.\ne.g.  100 dollars  /  10 grams gold 4500 lira  /  GARAN 500 units';

  @override
  String get quickEntryPlaceholder =>
      '100 dollars\n10 grams gold 4500 lira\nGARAN 500 units 105 lira';

  @override
  String saveNAssets(int count) {
    return 'Save $count assets';
  }

  @override
  String get fillTheForm => 'Fill the form';

  @override
  String get bistStocks => 'BIST Stocks';

  @override
  String get tefasFunds => 'TEFAS Funds';

  @override
  String get fundsLoading => 'Loading funds...';

  @override
  String get pleaseWait => 'Please wait';

  @override
  String breakdownUpAmount(String amount) {
    return 'up $amount';
  }

  @override
  String breakdownDownAmount(String amount) {
    return 'down $amount';
  }

  @override
  String get nominalReturnInWindow => 'Your return in this window';

  @override
  String get cpiWindowNote =>
      'CPI is published monthly, so this card ends at the latest published month: different windows from the figure above.';

  @override
  String rangeChip(String start, String end) {
    return '$start - $end';
  }

  @override
  String get rangeToday => 'today';

  @override
  String get rangeSinceFirstBuy => 'First buy to today';

  @override
  String sinceCpiWindowEnd(String month) {
    return 'Since end of $month';
  }

  @override
  String sinceCpiWindowBody(String month, String date) {
    return 'The figure above includes this stretch; this card updates when $month CPI is published ($date).';
  }

  @override
  String sinceCpiWindowBodyLate(String month) {
    return 'The figure above includes this stretch; this card updates once $month CPI is loaded.';
  }

  @override
  String get demoBannerTitle => 'Sample portfolio';

  @override
  String get demoBannerSubtitle => 'Sample holdings, live prices';

  @override
  String get demoCreateAccount => 'Create account';

  @override
  String get demoExit => 'Exit sample';

  @override
  String get demoAccountCardTitle => 'Build your own portfolio';

  @override
  String get demoAccountCardBody =>
      'Everything you see here works with your own holdings too. Create an account to add assets and save notes and alerts.';

  @override
  String get demoAccountCardSignIn => 'I already have an account';

  @override
  String get demoSaveSheetTitle => 'Create an account to save';

  @override
  String get demoSaveSheetBody =>
      'This is a sample portfolio; changes you make here are not saved. Create an account to build your own portfolio.';

  @override
  String get demoSaveSheetContinue => 'Keep exploring';

  @override
  String get fundsLoadFailed => 'Could not load funds';

  @override
  String get searchEllipsis => 'Search...';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get pickStockPrompt => 'Pick a stock from the list or type its symbol';

  @override
  String get pickStock => 'Pick a stock';

  @override
  String get pickStockTap => 'Tap to pick a stock...';

  @override
  String get pickFundPrompt => 'Pick a fund';

  @override
  String get pickFund => 'Pick a fund';

  @override
  String get pickFundTap => 'Tap to pick a fund...';

  @override
  String get noResults => 'No results';

  @override
  String get priceNotAvailable => 'No price information';

  @override
  String get assetFallbackName => 'Asset';

  @override
  String get commodityHint => 'e.g. Oil (Brent)';

  @override
  String get identityStock => 'Stock';

  @override
  String get identityFund => 'Fund';

  @override
  String get identityGoldKind => 'Gold Type';

  @override
  String get pickGoldTap => 'Tap to pick a gold type...';

  @override
  String get goldSearchHint => 'Search: quarter, 22 carat, reşat…';

  @override
  String get goldTypes => 'Gold Types';

  @override
  String get goldQuickPick => 'Quick pick';

  @override
  String get goldGroupGram => 'Gram';

  @override
  String get goldGroupZiynet => 'Jewellery coins';

  @override
  String get goldGroupSikke => 'Historic coins';

  @override
  String get goldGroupOns => 'Ounce';

  @override
  String get goldUnitGram => 'g';

  @override
  String get goldUnitOunce => 'oz';

  @override
  String goldSelectedSemantics(String kind) {
    return 'Selected gold type: $kind. Double tap to change.';
  }

  @override
  String get identityCurrency => 'Currency';

  @override
  String get identityCommodity => 'Commodity';

  @override
  String noResultsFor(String q) {
    return 'No match for \"$q\"';
  }

  @override
  String get periodDaily => 'DAILY';

  @override
  String get period1W => '1W';

  @override
  String get period1M => '1M';

  @override
  String get period3M => '3M';

  @override
  String get period6M => '6M';

  @override
  String get period1Y => '1Y';

  @override
  String assetPerformanceSemantics(String name) {
    return 'Performance: $name';
  }

  @override
  String get setPriceAlert => 'Set a price alert';

  @override
  String get priceHistoryFailed =>
      'This asset\'s price history could not be fetched. Check your connection and try again.';

  @override
  String get otherTab => 'Other';

  @override
  String get noResultsShort => 'No results.';

  @override
  String get compare => 'Compare';

  @override
  String get clearShort => 'Clear';

  @override
  String get searchTickerOrName => 'Search ticker or name…';

  @override
  String get myPortfolioTab => 'My Portfolio';

  @override
  String get deleteAccountTitle => 'You are about to delete your account';

  @override
  String get deleteAccountBody =>
      'This CANNOT be undone.\n\nAll your portfolio records, performance history and partner links will be permanently deleted immediately.\n\nDo you want to continue?';

  @override
  String get continueAction => 'Continue';

  @override
  String get verifyIdentityTitle => 'Verify your identity';

  @override
  String get verifyIdentityBody =>
      'Your account was created with Apple/Google. You will be asked to sign in once more with the same account before deletion.';

  @override
  String get confirmWithPassword => 'Confirm with your password';

  @override
  String get confirmWithPasswordBody =>
      'For your security you need to confirm with your password.';

  @override
  String get deleteAccountUpper => 'DELETE ACCOUNT';

  @override
  String get accountDeletedTitle => 'Your account was deleted';

  @override
  String get accountDeletedBody => 'See you around.';

  @override
  String get investmentDisclaimer => 'Investment Advice Disclaimer';

  @override
  String get close => 'Close';

  @override
  String get feedbackTitle => 'Feedback & Suggestions';

  @override
  String get feedbackHint => 'Write your message…';

  @override
  String get send => 'Send';

  @override
  String get deletingAccount => 'Deleting your account…';

  @override
  String get deletingAccountBody =>
      'This can take a few seconds. Don\'t close the app.';

  @override
  String get diagnosticsUpper => 'DIAGNOSTICS';

  @override
  String get pushDiagnostics => 'Push Diagnostics';

  @override
  String get pushDiagnosticsSubtitle =>
      'Where the notification chain is broken; device APNs/FCM token state';

  @override
  String get notificationsUpper => 'NOTIFICATIONS';

  @override
  String get signalNotifications => 'Technical signal notifications';

  @override
  String get signalNotificationsSubtitle =>
      'Get notified when a BUY/SELL indicator triggers';

  @override
  String get signalSettings => 'Signal settings';

  @override
  String get signalSettingsSubtitle =>
      'Indicator selection per asset type + Premium';

  @override
  String get priceAlerts => 'Price alerts';

  @override
  String get partnerInviteNotifications => 'Partner invite notifications';

  @override
  String get partnerInviteNotificationsSubtitle =>
      'Get notified when a new partner request arrives';

  @override
  String get liveActivitiesUpper => 'LIVE ACTIVITIES';

  @override
  String get biometricLock => 'Biometric lock';

  @override
  String get downloadMyData => 'Download My Data';

  @override
  String get downloadMyDataSubtitle =>
      'Get all your data as a JSON file (KVKK Article 11)';

  @override
  String get deleteMyAccount => 'Delete My Account';

  @override
  String get deleteMyAccountSubtitle => 'All your data is permanently deleted';

  @override
  String get supportUpper => 'SUPPORT';

  @override
  String get contactUs => 'Contact Us';

  @override
  String get replayTour => 'Replay the tour';

  @override
  String get replayTourSubtitle => 'Remind yourself what each screen does';

  @override
  String get feedbackSubtitle => 'Send us your thoughts';

  @override
  String get legalUpper => 'LEGAL';

  @override
  String get privacyPolicy => 'Privacy Policy';

  @override
  String get privacyPolicySubtitle => 'How your data is processed';

  @override
  String get termsOfUse => 'Terms of Use';

  @override
  String get termsOfUseSubtitle => 'Service agreement';

  @override
  String get kvkkNotice => 'KVKK Disclosure Notice';

  @override
  String get kvkkNoticeSubtitle => 'Personal data processing notice';

  @override
  String get disclaimerSubtitle => 'View the legal notice you accepted';

  @override
  String themeSemantics(String name) {
    return '$name theme';
  }

  @override
  String baseCurrencySemantics(String name) {
    return 'Base currency $name';
  }

  @override
  String levelSemantics(String name) {
    return '$name level';
  }

  @override
  String get showAllDay => 'Show all day';

  @override
  String get showAllDaySubtitle =>
      'When off, it only appears in the hours you choose.';

  @override
  String get displayWindow => 'Display window';

  @override
  String get startTime => 'Start';

  @override
  String get endTime => 'End';

  @override
  String get showOnWeekend => 'Show on weekends too';

  @override
  String get showOnWeekendSubtitle =>
      'BIST is closed on weekends. If your portfolio is only stocks and funds, the banner shows the last close labelled \"Market closed\"; with gold, FX or crypto it stays live.';

  @override
  String get showAmounts => 'Show amounts';

  @override
  String get showAmountsSubtitle =>
      'Applies to the Live Activity and the lock screen widget. When off, only the daily percentage and chart are shown. The lock screen is visible without unlocking your phone, so this is off by default.';

  @override
  String get lockWidgetHowTo =>
      'You can add it to the lock screen too: touch and hold the lock screen → Customize → Lock Screen → tap the widget area → sandık.';

  @override
  String get partnerActivityNotifications => 'Partner activity notifications';

  @override
  String get partnerActivityNotificationsSubtitle =>
      'Mention it in the daily brief when your partner adds to their portfolio';

  @override
  String get quietHours => 'Quiet hours';

  @override
  String get biometricLockSubtitle =>
      'Ask for Face ID / fingerprint / device PIN when opening the app';

  @override
  String get doneTitle => 'Done';

  @override
  String get alreadyPartners => 'Already Partners';

  @override
  String get ownCode => 'Your Own Code';

  @override
  String get expiredTitle => 'Expired';

  @override
  String get waitABit => 'Hold On';

  @override
  String get somethingWentWrong => 'Something went wrong';

  @override
  String get cancelInviteTitle => 'Cancel partner request';

  @override
  String get cancelInviteBody =>
      'Are you sure you want to cancel the partner request you sent?';

  @override
  String get yesCancel => 'Yes, cancel it';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get partnerActionsUpper => 'PARTNER ACTIONS';

  @override
  String get myPartnersUpper => 'MY PARTNERS';

  @override
  String get generateInviteCode => 'Generate Invite Code';

  @override
  String get generateInviteCodeBody =>
      'Send the code to your partner. Once they enter it, you get an approval request.';

  @override
  String get enterPartnerCode => 'Enter Partner Code';

  @override
  String get enterPartnerCodeBody =>
      'Enter the code your partner sent you (e.g. KRHNJ-8P2SW). They then need to approve.';

  @override
  String tooManyAttempts(String wait) {
    return 'Too many attempts. You can try again in $wait.';
  }

  @override
  String awaitingApproval(String name) {
    return 'Waiting for $name to approve...';
  }

  @override
  String get cancelWord => 'Cancel';

  @override
  String get noPartnersYet => 'You have no partners yet';

  @override
  String get removePartnerSemantics => 'Remove partner';

  @override
  String get removePartnerTitle => 'Remove partnership';

  @override
  String removePartnerBody(String name) {
    return 'Are you sure you want to remove your partnership with $name?';
  }

  @override
  String get removeWord => 'Remove';

  @override
  String get pendingRequestsUpper => 'PENDING PARTNER REQUESTS';

  @override
  String get wantsToPartner => 'Wants to partner up';

  @override
  String get rejectRequest => 'Reject partner request';

  @override
  String get acceptRequest => 'Accept partner request';

  @override
  String get sandikPremium => 'sandık Premium';

  @override
  String get premiumPitch => 'Unlimited assets and premium indicators';

  @override
  String get premiumActive => 'Premium active';

  @override
  String get premiumActiveBody => 'All advanced features unlocked';

  @override
  String get codeCopied => 'Code generated and copied to clipboard';

  @override
  String tooManyFailedAttempts(String wait) {
    return 'Too many failed attempts.\nYou can try again in $wait.';
  }

  @override
  String partnershipCreated(String name) {
    return 'You are now partners with $name.';
  }

  @override
  String get requestRejected => 'The partner request was rejected.';

  @override
  String get requestCancelled => 'The partner request was cancelled.';

  @override
  String get partnershipAccepted => 'Partnership accepted.';

  @override
  String get sendingEllipsis => 'Sending...';

  @override
  String waitFor(String wait) {
    return 'Wait: $wait';
  }

  @override
  String get requestPartnership => 'Request Partnership';

  @override
  String get generatingEllipsis => 'Generating...';

  @override
  String get generateCode => 'Generate Code';

  @override
  String get tabChart => 'Chart';

  @override
  String get tabSummary => 'Summary';

  @override
  String modeInfoSemantics(String mode) {
    return 'About $mode mode';
  }

  @override
  String get noChartData => 'No chart data';

  @override
  String get noAssetsYetTitle => 'You have no assets yet';

  @override
  String noAssetsOfTypeTitle(String type) {
    return 'No $type in your portfolio';
  }

  @override
  String get noAssetsChartBody =>
      'As you add assets, your portfolio performance turns into a chart here.';

  @override
  String get noAssetsOfTypeChartBody =>
      'Add an asset of this type and its performance appears here. You can pick another type.';

  @override
  String get noHistoryAllBody =>
      'Price history is not tracked for your assets; their value counts in the total but no time chart can be drawn.';

  @override
  String get youngPortfolioTitle => 'No history for this period yet';

  @override
  String get youngPortfolioBody =>
      'Your portfolio is newer than the selected period. The chart fills in as trading days pass. See today\'s move in the DAILY view.';

  @override
  String get forceUpdateTitle => 'Update required';

  @override
  String get forceUpdateBody =>
      'This version of Sandık is no longer supported. Update the app to continue; your data is safe.';

  @override
  String get forceUpdateButton => 'Update';

  @override
  String get serverMovedTitle => 'Sandık has moved';

  @override
  String get serverMovedBodyAndroid =>
      'We moved to a faster server. Close and reopen the app to continue. You\'ll be asked to sign in once; your password and data are unchanged.';

  @override
  String get serverMovedBodyIos =>
      'We moved to a faster server. Close the app (swipe it up) and reopen it to continue. You\'ll be asked to sign in once; your password and data are unchanged.';

  @override
  String get serverMovedCloseButton => 'Close the app';

  @override
  String noHistoryTypeBody(String type) {
    return 'Price history is not tracked for $type. Its value counts in the portfolio total, but no time chart can be drawn.';
  }

  @override
  String get simModeTitle => 'Simulation Mode';

  @override
  String get simModeBody =>
      'How would the chart look if you had held today\'s net portfolio for the whole period? It ignores past buy/sell decisions and shows only the price change of your current position.';

  @override
  String get portfolioPerformance => 'Portfolio Performance';

  @override
  String get chartDataFailed => 'Could not load chart data';

  @override
  String get chartDataFailedBody =>
      'Price history could not be fetched. Check your connection and try again.';

  @override
  String intradayMissingBody(String names) {
    return 'Intraday prices could not be fetched for $names. These assets are drawn FLAT at their last known price. A flat line does not mean the market was quiet.';
  }

  @override
  String get retryLower => 'Try again';

  @override
  String get raceUpper => 'RACE';

  @override
  String get changeByTypeUpper => 'BY TYPE · PRICE EFFECT';

  @override
  String get noData => 'No data';

  @override
  String get tooltipReturn => '\nReturn ';

  @override
  String get tooltipBuy => '\nBuy  +';

  @override
  String get tooltipSell => '\nSell −';

  @override
  String get tooltipNet => '\nNet ';

  @override
  String get tooltipInvested => '\nTotal invested ';

  @override
  String chartTxBuy(String when, String price) {
    return 'Buy $when · $price';
  }

  @override
  String chartTxSell(String when, String price) {
    return 'Sell $when · $price';
  }

  @override
  String get tradeVolumeUpper => 'BUYS · SELLS';

  @override
  String crosshairNetBuy(String amount) {
    return 'Net buy +$amount';
  }

  @override
  String crosshairNetSell(String amount) {
    return 'Net sell −$amount';
  }

  @override
  String get crosshairNetFlat => 'No net change';

  @override
  String crosshairTxCount(int count) {
    return '$count trades';
  }

  @override
  String crosshairBuySellDetail(String buy, String sell) {
    return 'Buy $buy · Sell $sell';
  }

  @override
  String get performanceTitle => 'Performance';

  @override
  String get intervalWeekly => 'Weekly';

  @override
  String get intervalMonthly => 'Monthly';

  @override
  String get intervalYearly => 'Yearly';

  @override
  String lastNWeeksNet(int n) {
    return 'last $n weeks · net';
  }

  @override
  String lastNMonthsNet(int n) {
    return 'last $n months · net';
  }

  @override
  String lastNYearsNet(int n) {
    return 'last $n years · net';
  }

  @override
  String get avgContributingWeek => 'Average per contributing week';

  @override
  String get avgContributingMonth => 'Average per contributing month';

  @override
  String get avgContributingYear => 'Average per contributing year';

  @override
  String get vsLastWeek => 'Compared to last week';

  @override
  String get vsLastMonth => 'Compared to last month';

  @override
  String get vsLastYear => 'Compared to last year';

  @override
  String get ongoingWeek => ', ongoing week';

  @override
  String get ongoingMonth => ', ongoing month';

  @override
  String get ongoingYear => ', ongoing year';

  @override
  String get trendUpWeek => 'This week is above your earlier contributions.';

  @override
  String get trendUpMonth => 'This month is above your earlier contributions.';

  @override
  String get trendUpYear => 'This year is above your earlier contributions.';

  @override
  String get trendDownWeek => 'This week is below your earlier contributions.';

  @override
  String get trendDownMonth =>
      'This month is below your earlier contributions.';

  @override
  String get trendDownYear => 'This year is below your earlier contributions.';

  @override
  String get trendFlatWeek => 'Your contributions are steady week to week.';

  @override
  String get trendFlatMonth => 'Your contributions are steady month to month.';

  @override
  String get trendFlatYear => 'Your contributions are steady year to year.';

  @override
  String get biggestMoverToday => 'Today\'s biggest mover';

  @override
  String get weekExtremes => 'This week\'s extremes';

  @override
  String get lastMonthPeriod => 'the last month';

  @override
  String get last6MonthsPeriod => 'the last 6 months';

  @override
  String get sixMonthExtremes => 'Six-month extremes';

  @override
  String get lastYearPeriod => 'the last year';

  @override
  String get yearCurve => 'Year curve';

  @override
  String get last3MonthsPeriod => 'the last 3 months';

  @override
  String get threeMonthExtremes => 'Three-month extremes';

  @override
  String get last5YearsPeriod => 'the last 5 years';

  @override
  String get fiveYearExtremes => 'Five-year extremes';

  @override
  String get fiveYearCurve => 'Five-year curve';

  @override
  String moneyReturnPeriod(String period) {
    return 'Return on your money · $period';
  }

  @override
  String get whereItCameFrom => 'Where it came from';

  @override
  String get periodStart => 'Period start';

  @override
  String get yourContribution => 'Net contribution';

  @override
  String get marketWord => 'Market';

  @override
  String get cashDividend => 'Of which cash dividends';

  @override
  String get commissionPaid => 'Commission paid';

  @override
  String get contributionNotReturn =>
      'The percentage comes only from the price effect. Cash dividends are part of the return; they went to your pocket, so the bridge shows them on their own line as an outflow.';

  @override
  String annualRatePct(String pct) {
    return '$pct a year';
  }

  @override
  String periodTotalPct(String pct) {
    return 'Period total $pct';
  }

  @override
  String get periodCourse => 'Course over the period';

  @override
  String greenDaysOfTotal(int total, int up) {
    return '$up of $total trading days closed up.';
  }

  @override
  String get againstInflation => 'Against inflation';

  @override
  String get nominalReturn => 'Your return';

  @override
  String cpiWindowRange(String start, String end) {
    return 'Measured: $start - $end';
  }

  @override
  String cpiWindowMonth(String month) {
    return 'Measured month: $month';
  }

  @override
  String get periodCpi => 'Inflation (CPI)';

  @override
  String get pointDifference => 'Difference';

  @override
  String get realReturn => 'Real return';

  @override
  String get cpiNotLoaded => 'Inflation data has not loaded yet.';

  @override
  String get cpiNotLoadedBody =>
      'When the inflation index arrives, your portfolio\'s real return appears here. No estimated figure is shown.';

  @override
  String get allocationChange => 'Allocation change';

  @override
  String get sixMonthComparison => 'Six-month comparison';

  @override
  String get portfolioCharacter => 'Your portfolio\'s character';

  @override
  String get mostPatientAsset => 'Your most patient asset';

  @override
  String nDays(int n) {
    return '$n days';
  }

  @override
  String get shareSummary => 'Share your summary';

  @override
  String get savingDiscipline => 'Your saving discipline';

  @override
  String get noNewMoney =>
      'No new money entered your portfolio in this window.';

  @override
  String get highestWord => 'Highest';

  @override
  String get contributingPeriods => 'Periods with contributions';

  @override
  String portfolioHealthPeriod(String period) {
    return 'Portfolio health · $period';
  }

  @override
  String get maxDrawdown => 'Largest drawdown';

  @override
  String get volatility => 'Volatility';

  @override
  String get volatilityBody =>
      'This is how much your portfolio value swung on average over the year. High is neither good nor bad; it just means bigger ups and downs.';

  @override
  String get concentration => 'Concentration';

  @override
  String get moneyReturnAnnual => 'Since you started (annual)';

  @override
  String get xirrBody =>
      'The annual compound return of the money you invested, taking the DATES of your investments into account.';

  @override
  String get periodMarketReturnLabel => 'Selected period\'s return';

  @override
  String get xirrVsMarketBody =>
      'The two numbers do not contradict: the top one runs from your first buy to today and also accounts for when you bought; the bottom one measures only the market\'s move in the selected period.';

  @override
  String get advancedMetricsYear => 'Advanced metrics · last year';

  @override
  String notEnoughHistory(String period) {
    return 'Not enough history for $period';
  }

  @override
  String get notEnoughHistoryBody =>
      'The summary appears on its own once this period fills up.';

  @override
  String nAssetsPeriod(int count, String period) {
    return '$count ASSETS · $period';
  }

  @override
  String get chartLoadFailed => 'The chart could not be loaded.';

  @override
  String get notEnoughPriceHistory => 'Not enough price history for a chart.';

  @override
  String portfolioLineInfoDaily(String name) {
    return 'In the daily view the $name line shows your real value, the same as the daily chart on the Performance screen.';
  }

  @override
  String portfolioLineInfoSim(String name) {
    return 'For weekly and longer periods the $name line is a simulation: what would have happened had you held today\'s assets since the start of the period. Your buy and sell dates are ignored; it is not your realised return. This keeps it comparable with your watched assets over the same window.';
  }

  @override
  String openDetailSemantics(String name) {
    return 'Open $name details';
  }

  @override
  String addToPortfolioSemantics(String name) {
    return 'Add $name to my portfolio';
  }

  @override
  String get noWatchlistYet => 'You are not watching anything yet';

  @override
  String get noWatchlistBody =>
      'Watch it before you buy. Track the price without touching your portfolio.';

  @override
  String get addToWatchlist => 'Add to watchlist';

  @override
  String get whyWatchlistUpper => 'WHY A WATCHLIST?';

  @override
  String get whyWatchlistBody =>
      'You can follow an asset\'s price without buying it. The watchlist is not part of your portfolio; it does not affect your total value or profit/loss.';

  @override
  String get notInPortfolioNote =>
      'These assets are not part of your portfolio.';

  @override
  String get addAssetsToCompare => 'Add assets to compare';

  @override
  String get addAssetsToCompareBody =>
      'You can also add assets you don\'t own.';

  @override
  String get inMyPortfolio => 'In my portfolio';

  @override
  String get noDataShort => 'no data';

  @override
  String get addToMyPortfolio => 'Add to my portfolio';

  @override
  String get comparisonDisclaimer =>
      'Past performance is not an indicator of future returns. Chart values show percentage change from the start of the period; commission, tax and dividends are not included.';

  @override
  String get searchAssetsHint => 'Search stocks, funds, gold or indices';

  @override
  String get noResultsFound => 'No results found';

  @override
  String get portfolioSeriesNote =>
      'Portfolios are computed series, not quoted on any market. Their returns are drawn as a percentage from the start of the period, just like an asset.';

  @override
  String get portfolioActivityTitle => 'Portfolio Activity';

  @override
  String get clearFilters => 'Clear filters';

  @override
  String watchlistRowUp(String pct) {
    return 'up $pct';
  }

  @override
  String watchlistRowDown(String pct) {
    return 'down $pct';
  }

  @override
  String get watchlistRowFollowing => 'on your watchlist';

  @override
  String notificationsNewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count new notifications',
      one: '1 new notification',
    );
    return '$_temp0';
  }

  @override
  String get signOutAction => 'Sign out';

  @override
  String get baseCurrencyNameLira => 'Lira';

  @override
  String get baseCurrencyNameDollar => 'Dollar';

  @override
  String get baseCurrencyNameEuro => 'Euro';

  @override
  String get baseCurrencyNameGold => 'Gram gold';

  @override
  String get datePickerHelp => 'Select date';

  @override
  String get datePickerConfirm => 'Select';

  @override
  String get sortAssetsSemantics => 'Sort assets';

  @override
  String get showDetailsSemantics => 'Show details';

  @override
  String get hideDetailsSemantics => 'Hide details';

  @override
  String pricePreviewClose(String date) {
    return '$date close. This price will be saved';
  }

  @override
  String pricePreviewLastTradingClose(String date) {
    return 'Last trading day\'s close ($date). This price will be saved';
  }

  @override
  String priceAssignedClose(String date, String price) {
    return '$date close assigned: $price';
  }

  @override
  String priceAssignedLastTradingClose(String date, String price) {
    return 'Last trading day\'s ($date) close assigned: $price';
  }

  @override
  String todayRealAhead(String pts) {
    return '$pts pts ahead';
  }

  @override
  String todayRealBehind(String pts) {
    return '$pts pts behind';
  }

  @override
  String get todayRealEven => 'even';

  @override
  String recapPointsAhead(String n) {
    return 'You beat inflation by $n points';
  }

  @override
  String recapPointsBehind(String n) {
    return 'You trailed inflation by $n points';
  }

  @override
  String get loadingEllipsis => 'Loading…';

  @override
  String get widenDateRangeHint =>
      'Try widening the date range or clearing the search.';

  @override
  String get priceAlertsTitle => 'Price Alerts';

  @override
  String get createAlert => 'Create an alert';

  @override
  String get noAlertsYet => 'You have no alerts yet';

  @override
  String get noAlertsBody =>
      'Tap the bell on an asset\'s screen or create one here; we\'ll let you know even when the app is closed.';

  @override
  String get recreateAlert => 'Set again';

  @override
  String get raceTitle => 'Race';

  @override
  String get raceOptions => 'Race options';

  @override
  String get leaveRace => 'Leave the race';

  @override
  String get leaveRaceBody =>
      'You leave the ranking; your partners can no longer see your percentage. You can rejoin any time.';

  @override
  String get leaveWord => 'Leave';

  @override
  String get howReturnCalculated => 'How is the return calculated?';

  @override
  String get selectedPeriodReturn => 'Return on your picks';

  @override
  String get depositsDontChangeRank =>
      'Adding money doesn\'t change the ranking';

  @override
  String get everyoneMeasuredSame => 'Everyone is measured the same way';

  @override
  String get rankVsPortfolioNote =>
      'The \"Return on your money\" under your row is the number on the Performance screen: it also accounts for when and how much money you added. The ranking measures only your picks, so the two can differ.';

  @override
  String get rankSwapNote =>
      'Newcomers are measured only for as long as they have held their portfolio. Portfolios without price history are excluded from the ranking.';

  @override
  String get notInRace => 'You haven\'t joined the Race';

  @override
  String get notInRaceBody =>
      'Turn on participation to appear in the return ranking with your partners. Only partners who opt in can see each other\'s percentage. Your assets and total TRY value are never shared.';

  @override
  String get joinRace => 'Join the Race';

  @override
  String get addPartnerToRace => 'Add a partner and race together';

  @override
  String get raceNoListShared =>
      'No one\'s asset list is shared; only return percentages are ranked.';

  @override
  String get yourReturnUpper => 'RETURN ON YOUR PICKS';

  @override
  String get dataNotReady => 'Data is not ready.';

  @override
  String get leaderUpper => 'LEADER';

  @override
  String get loadingUpper => 'LOADING';

  @override
  String get globalRanking => 'Global Ranking';

  @override
  String get checkingAnonPool => 'Checking the anonymous pool…';

  @override
  String get comingSoonUpper => 'SOON';

  @override
  String get globalRankingSoon =>
      'Your rank opens once there are enough participants. Anonymous, KVKK compliant';

  @override
  String topPercentile(String period, int pct) {
    return 'You\'re in the top $pct% of the $period ranking';
  }

  @override
  String get topPortfolios => 'Top Portfolios';

  @override
  String topGainersAllocation(String period) {
    return '$period top gainers\' allocation';
  }

  @override
  String get anonymousUpper => 'ANONYMOUS';

  @override
  String get topPortfoliosSoon =>
      'Top portfolios appear here once there are enough participants. The anonymous pool is forming…';

  @override
  String nthPortfolio(int n) {
    return 'Portfolio #$n';
  }

  @override
  String get selectedPeriodReturnBody =>
      'The period is split into days. Each day, the assets you held that day are valued at market prices, and the daily returns are chained together.\n\nIf you sold one asset and bought another, each counts only on the days you held it. The 7D / 30D / 1Y choice above changes the result directly.';

  @override
  String get depositsDontChangeRankBody =>
      'What is measured is your picks: which assets you held, on which days. When and how much money you added does NOT affect the ratio; the same picks give the same percentage whether you hold 1 lot or 10,000.\n\nThe purchase price you entered is not used; everything is valued at market prices.';

  @override
  String get everyoneMeasuredSameBody =>
      'You and your partners are computed with the same formula and the same prices; the calculation happens on this device. Between partners the date you entered counts: history imported via CSV or statement counts right away.\n\nAt least 30 days of history is needed to be ranked. In anonymous rankings (Top portfolios, global), a buy or sell entered with a date more than 3 days in the past counts as made on the day it was entered.';

  @override
  String get planYearly => 'Yearly';

  @override
  String get planYearlySubtitle => '7 days free, then renews automatically';

  @override
  String get planMonthly => 'Monthly';

  @override
  String get planMonthlySubtitle => 'Cancel any time';

  @override
  String get subscriptionTerms =>
      'Payment is charged to your App Store account. The subscription renews automatically for the same period and price unless cancelled at least 24 hours before the period ends. Manage or cancel it under Settings › Apple ID › Subscriptions.';

  @override
  String get premiumUnlocked => 'Premium unlocked';

  @override
  String get premiumUnlockedBody =>
      'Unlimited assets, premium indicators and every Premium detail are now unlocked.';

  @override
  String get greatWord => 'Great';

  @override
  String get sandikPremiumUpper => 'SANDIK PREMIUM';

  @override
  String get paywallHeadline => 'Track your portfolio\nin more depth';

  @override
  String get paywallSubhead =>
      'Unlimited assets and advanced indicators. Portfolio tracking stays free.';

  @override
  String get restorePurchase => 'Restore purchase';

  @override
  String get recapTitle => 'Your sandık Recap';

  @override
  String recapInYear(int year) {
    return 'in $year';
  }

  @override
  String get recapSubtitle => 'A short story of the year.';

  @override
  String recapDays(int n) {
    return '$n days';
  }

  @override
  String myRecapYear(int year) {
    return 'My $year Recap';
  }

  @override
  String recapReady(int year) {
    return 'Your $year Recap is ready';
  }

  @override
  String recapCardSubtitle(String character) {
    return 'A short story of the year: $character';
  }

  @override
  String medianAhead(String pts) {
    return '$pts points ahead of the median';
  }

  @override
  String get returnRanking => 'Return ranking';

  @override
  String returnRankingWith(String detail) {
    return 'Return ranking · $detail';
  }

  @override
  String percentileSemantics(int pct, String detail) {
    return 'Over the last 30 days you are above $pct percent of participants. $detail';
  }

  @override
  String get last30DaysLike => 'Over the last 30 days you\'re ahead of ';

  @override
  String nPeople(int n) {
    return '$n people';
  }

  @override
  String medianBehind(String pts) {
    return '$pts points behind the median';
  }

  @override
  String get lastYearInflation => 'Over the last year, inflation-wise you are ';

  @override
  String pointsAhead(String pts) {
    return '$pts points ahead';
  }

  @override
  String pointsBehind(String pts) {
    return '$pts points behind';
  }

  @override
  String get noChangeLower => 'no change';

  @override
  String get totalNetHidden => 'Total net worth hidden';

  @override
  String totalNetWorth(String amount) {
    return 'Total net worth $amount';
  }

  @override
  String get realisedFromSales => 'Realised from sales: ';

  @override
  String get includedDividend => 'Of which dividends: ';

  @override
  String deletedNRecords(int n) {
    return 'Deleted · $n records';
  }

  @override
  String get txDeleted => 'Deleted';

  @override
  String get txVoided => 'removed';

  @override
  String get seeAllShort => 'See all';

  @override
  String nTransactions(int n) {
    return '$n transactions';
  }

  @override
  String get txSell => 'Sale';

  @override
  String get txDividend => 'Dividend';

  @override
  String get txBuy => 'Purchase';

  @override
  String get gainWord => 'gain';

  @override
  String get costBasisGain => 'Gain vs. cost';

  @override
  String get costBasisLoss => 'Loss vs. cost';

  @override
  String get lossWord => 'loss';

  @override
  String get realisedFromSalesSemantics => 'realised from sales ';

  @override
  String get raceNoPartnerBody =>
      'You have no partners yet. You can already see your own period return and global percentile.';

  @override
  String get viewWord => 'View';

  @override
  String get newUpper => 'NEW';

  @override
  String get racePitch =>
      'A return ranking with your partners. Who is earning more?';

  @override
  String get joinWord => 'Join';

  @override
  String get raceCalculating => 'Calculating the race…';

  @override
  String rankFirst(String period) {
    return 'You\'re 1st in the $period ranking';
  }

  @override
  String rankNth(String period, String rank) {
    return 'You\'re $rank in the $period ranking';
  }

  @override
  String widenTheGap(String gap) {
    return 'Widen the gap, second is $gap% behind';
  }

  @override
  String get atTheTop => 'You\'re at the top. Keep the lead';

  @override
  String toPassPerson(String name, String diff) {
    return '+$diff% to pass $name';
  }

  @override
  String get higherInOtherPeriods =>
      'You rank higher in other periods. Tap to see';

  @override
  String get deleteAssetTitle => 'Delete Asset';

  @override
  String deleteAssetMulti(String name, int n) {
    return 'Permanently delete $n transaction records (buy/sell/dividend) for \"$name\"?';
  }

  @override
  String deleteAssetSingle(String name) {
    return 'Permanently delete \"$name\"?';
  }

  @override
  String get deleteAnyway => 'Delete anyway';

  @override
  String get deleteAssetWarning =>
      'This is not a sale. The asset leaves your portfolio and drops out of totals and the history chart. Transaction records stay under \"Portfolio Activity\". If you sold it, use \"Sell\" instead so your realised profit/loss is counted.';

  @override
  String alarmAlsoDeleteTitle(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Delete the $n alerts too?',
      one: 'Delete the alert too?',
    );
    return '$_temp0';
  }

  @override
  String alarmAlsoDeleteBody(int n, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other:
          '$name was deleted. The $n alerts you set for this symbol are still active. They can keep watching the price even though you no longer hold it.',
      one:
          '$name was deleted. The alert you set for this symbol is still active. It can keep watching the price even though you no longer hold it.',
    );
    return '$_temp0';
  }

  @override
  String alarmAlsoDeleteConfirm(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: 'Delete alerts',
      one: 'Delete alert',
    );
    return '$_temp0';
  }

  @override
  String get alarmKeep => 'Keep alert';

  @override
  String get alarmDeleteFailed => 'Could not delete alerts';

  @override
  String get assetDeleted => 'Asset deleted';

  @override
  String get undoFailed => 'Could not undo';

  @override
  String get enterValidAmount => 'Enter a valid amount';

  @override
  String get dividendSaved => 'Dividend saved';

  @override
  String get dividendPayDate => 'Dividend payment date';

  @override
  String get addDividend => 'Add Dividend';

  @override
  String netAmountReceived(String name) {
    return '$name · net amount received';
  }

  @override
  String paymentDate(String date) {
    return 'Payment date: $date';
  }

  @override
  String get dividendNote =>
      'A dividend does not change your quantity; it is added to your total return.';

  @override
  String get enterValidQuantity => 'Enter a valid quantity';

  @override
  String get enterValidUnitPrice => 'Enter a valid unit price';

  @override
  String cannotExceedQuantity(String qty) {
    return 'You can\'t exceed the current quantity ($qty)';
  }

  @override
  String get depositAmountLabel => 'Amount';

  @override
  String cannotExceedBalance(String amount) {
    return 'You can\'t exceed the current balance ($amount)';
  }

  @override
  String boughtAmount(String qty, String unit) {
    return 'Bought $qty $unit';
  }

  @override
  String soldAmount(String qty, String unit) {
    return 'Sold $qty $unit';
  }

  @override
  String transactionFailed(String error) {
    return 'Transaction failed. $error';
  }

  @override
  String get sellAllWarning =>
      'You are selling the whole position. It leaves the list but stays as a sale record. Your transaction history and realised profit/loss are kept. To remove the record entirely, use \"Delete\" from the asset detail.';

  @override
  String get saleValue => 'Sale value';

  @override
  String get noPriceAlert => 'No price alert';

  @override
  String nActiveAlerts(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n active price alerts',
      one: '1 active price alert',
    );
    return '$_temp0';
  }

  @override
  String get deleteAlertTitle => 'Delete alert';

  @override
  String deleteAlertAbove(String price) {
    return 'Delete the alert for rising above $price?';
  }

  @override
  String triggeredAlertSemantics(String price) {
    return 'Triggered alert $price, tap to set it again';
  }

  @override
  String alertAboveSemantics(String price) {
    return 'Above $price, tap to delete';
  }

  @override
  String alertTriggered(String price) {
    return '$price · triggered';
  }

  @override
  String deleteAlertBelow(String price) {
    return 'Delete the alert for falling below $price?';
  }

  @override
  String alertBelowSemantics(String price) {
    return 'Below $price, tap to delete';
  }

  @override
  String get addAssetFirst =>
      'Add an asset to your portfolio or watchlist first.';

  @override
  String alertSetAbove(String name, String price) {
    return 'Alert set for $name: rising above $price';
  }

  @override
  String get alertSetFailed => 'Could not set the alert';

  @override
  String get enterValidPrice => 'Enter a valid price';

  @override
  String alertForAsset(String name) {
    return 'Alert for $name';
  }

  @override
  String currentlyPrice(String price) {
    return 'Currently $price';
  }

  @override
  String get currentPriceUnknown => 'Current price unknown';

  @override
  String targetPctSemantics(String sign, int pct) {
    return 'Target percent $sign $pct';
  }

  @override
  String get notifyWhenAbove =>
      'We\'ll let you know when the price rises to this level.';

  @override
  String get notifyWhenBelow =>
      'We\'ll let you know when the price falls to this level.';

  @override
  String get setAlert => 'Set alert';

  @override
  String alertSetBelow(String name, String price) {
    return 'Alert set for $name: falling below $price';
  }

  @override
  String get plusWord => 'plus';

  @override
  String get minusWord => 'minus';

  @override
  String get widgetStepHold =>
      'Press and hold an empty spot on your home screen';

  @override
  String get widgetStepPlus => 'Tap the + in the top-left corner';

  @override
  String get widgetStepPickIos => 'Pick \"sandık\" from the list and add it';

  @override
  String get widgetStepPickAndroid =>
      'Find \"sandık\" and drag it to your home screen';

  @override
  String get widgetInstallTitle => 'See your portfolio on the home screen';

  @override
  String get widgetInstallBody =>
      'See your total and daily change without opening the app.';

  @override
  String get gotIt => 'Got it';

  @override
  String get widgetStepWidgetsTab => 'Tap \"Widgets\"';

  @override
  String get disclaimerText =>
      'This app is for information only. The data, analyses and notifications shown are absolutely not investment advice, a trading recommendation, or financial consultancy. Make your investment decisions in consultation with a licensed financial adviser. Past performance does not guarantee future results.';

  @override
  String get justNow => 'just now';

  @override
  String minutesAgo(int n) {
    return '$n min ago';
  }

  @override
  String hoursAgo(int n) {
    return '$n h ago';
  }

  @override
  String daysAgo(int n) {
    return '$n d ago';
  }

  @override
  String get signalCalculating => 'Calculating signal…';

  @override
  String get trendUp => 'UPTREND';

  @override
  String get trendDown => 'DOWNTREND';

  @override
  String get trendFlat => 'FLAT';

  @override
  String indicatorsConfidence(int lehte, int total, int pct) {
    return '$lehte/$total directional indicators · $pct% confidence';
  }

  @override
  String confidenceOnly(int pct) {
    return '$pct% confidence';
  }

  @override
  String get technicalOutlookUpper => 'TECHNICAL OUTLOOK';

  @override
  String get nowUpper => 'NOW';

  @override
  String get arrowUp => '▲ up';

  @override
  String get arrowDown => '▼ down';

  @override
  String get arrowFlat => '◆ flat';

  @override
  String get indicatorsCalculating => 'Calculating indicators…';

  @override
  String get indicatorsNoHistory =>
      'This asset\'s price history could not be fetched, so indicators cannot be calculated.';

  @override
  String get noIndicatorsSelected =>
      'No indicators are selected for this asset type. Enable them from Profile → Signal Settings.';

  @override
  String get technicalAnalysisUpper => 'TECHNICAL ANALYSIS';

  @override
  String nOfMIndicators(int on, int all) {
    return '· $on/$all indicators on';
  }

  @override
  String get configureIndicators => 'Configure Indicators';

  @override
  String buySellNeutralCounts(int buy, int sell, int neutral) {
    return '$buy BUY · $sell SELL · $neutral NEUTRAL';
  }

  @override
  String get confidenceWord => 'confidence';

  @override
  String csvRowsAddedToCart(int n) {
    return '$n rows added to the cart';
  }

  @override
  String get csvImportTitle => 'Import statement';

  @override
  String get csvImportBody =>
      'Choose your broker or bank statement (PDF, Excel or CSV) or copy and paste the table. Column names and order don\'t matter: symbol, quantity, price, date and buy/sell are detected automatically. Buys and sells come in with their dates.';

  @override
  String get pasteHere => 'Paste here';

  @override
  String get importPickFile => 'Choose file (PDF, Excel, CSV)';

  @override
  String get importReading => 'Reading file…';

  @override
  String get importMappingTitle => 'Columns were matched like this';

  @override
  String get importLowConfidence =>
      'We\'re not fully sure about this file\'s columns; check the mapping and fix it if needed.';

  @override
  String get importFixColumns => 'Fix columns';

  @override
  String get importCopyDiagnostic => 'Copy diagnostic text';

  @override
  String get importDiagnosticHint =>
      'Copies the table layout so we can fix an unreadable statement. Names, numbers and amounts are masked.';

  @override
  String get importDiagnosticCopied => 'Diagnostic text copied.';

  @override
  String get importAiButton => 'Map with AI';

  @override
  String get importAiHint =>
      'Only the table layout is sent: names, numbers and amounts are hidden, the document never leaves your phone.';

  @override
  String get importAiSuggested =>
      'AI suggested the columns; check the mapping and fix it if needed.';

  @override
  String get importAiNoMatch =>
      'AI couldn\'t find a holdings table in this file either.';

  @override
  String get importAiLimit =>
      'You\'ve used today\'s AI mapping allowance; try again tomorrow.';

  @override
  String get importAiFailed =>
      'AI mapping isn\'t available right now. Try again a bit later.';

  @override
  String importTradesApplied(int count) {
    return 'Actual purchase date and price for $count holdings taken from account transactions.';
  }

  @override
  String importDepositRow(String name, String amount, String rate, int days) {
    return '$name · $amount · $rate interest · $days-day term';
  }

  @override
  String importFundNotRecognized(String name) {
    return 'Fund not recognized, skipped: $name';
  }

  @override
  String get importFundListFailed =>
      'Couldn\'t load the TEFAS fund list; funds listed by name were skipped. Check your connection and pick the file again.';

  @override
  String importDepositsFound(int n) {
    return '$n time deposits found (demand accounts are not imported)';
  }

  @override
  String importStatementDate(String date) {
    return 'Statement date $date: fund cost is taken as that day\'s unit price.';
  }

  @override
  String cartDepositSubtitle(String rate, int days) {
    return 'Time deposit · $rate · $days days';
  }

  @override
  String get importColumnNone => 'None';

  @override
  String get importApply => 'Apply';

  @override
  String get importOrPaste => 'or paste the table';

  @override
  String get preview => 'Preview';

  @override
  String csvRowsRead(int n) {
    return '$n rows read';
  }

  @override
  String csvRowsSkipped(int n) {
    return ', $n rows skipped';
  }

  @override
  String get closePriceWillBeFetched => 'close price will be fetched';

  @override
  String get unitPiece => 'units';

  @override
  String assetLimitReachedFor(String name) {
    return '$name: asset limit reached';
  }

  @override
  String get someAssetsNotAdded => 'Some Assets Could Not Be Added';

  @override
  String bulkAddSavingProgress(int saved, int total) {
    return 'Saving $saved / $total';
  }

  @override
  String bulkAddPartialResult(int saved, int failed) {
    return '$saved added, $failed could not be added. The failed ones are still in the cart; trying again adds only those.';
  }

  @override
  String importSellExceedsHolding(String name) {
    return '$name: sell quantity is more than you held on that date; not saved.';
  }

  @override
  String importSellNoPrice(String name) {
    return '$name: sell price not found; enter the price and try again.';
  }

  @override
  String get cartSellTag => 'Sell';

  @override
  String get kapLinkLabel => 'KAP disclosures';

  @override
  String get kapLinkHint => 'Opens the company\'s KAP page in your browser';

  @override
  String get kapLinkFailed =>
      'Couldn\'t open the KAP page. Check your connection.';

  @override
  String get clearCartConfirm =>
      'All assets in the cart will be removed. Are you sure?';

  @override
  String get pasteCsv => 'Paste CSV';

  @override
  String get cartEmpty => 'The cart is empty';

  @override
  String get cartEmptyBody =>
      'Use the + Add Asset button below to queue several assets and save them all at once.';

  @override
  String get pasteFromStatement => 'Import statement (PDF, Excel, CSV)';

  @override
  String saveAllCount(int n) {
    return 'Save All ($n)';
  }

  @override
  String get removeFromWatchlist => 'Remove from watchlist';

  @override
  String removeFromWatchlistConfirm(String name) {
    return 'Remove $name from your watchlist?';
  }

  @override
  String get removeWord2 => 'Remove';

  @override
  String get removeFromWatchlistFailed =>
      'Could not remove it. Check your connection.';

  @override
  String get currentPriceUpper => 'CURRENT PRICE';

  @override
  String periodNoChange(String period) {
    return '$period · no change';
  }

  @override
  String get unitPriceDiffNote =>
      'The change is a unit price difference; you don\'t own this asset.';

  @override
  String get notEnoughHistoryForAsset =>
      'Not enough price history for this asset.';

  @override
  String get notInYourPortfolio => 'This asset is not part of your portfolio.';

  @override
  String get searchingEllipsis => 'Searching…';

  @override
  String get startTypingToSearch => 'Start typing to search.';

  @override
  String noResultForQuery(String q) {
    return 'No results for \"$q\".';
  }

  @override
  String get inYourPortfolioUpper => 'IN YOUR PORTFOLIO';

  @override
  String get searchAllAssetsHint =>
      'Search stocks, funds, indices, commodities, currency or gold';

  @override
  String alreadyInPortfolio(String name) {
    return '$name is already in your portfolio';
  }

  @override
  String addedToWatchlist(String name) {
    return '$name added to your watchlist';
  }

  @override
  String get watchlistInListLabel => 'Watching';

  @override
  String get watchlistFullShort => 'Full';

  @override
  String watchlistCountOfLimit(int n, int limit) {
    return '$n/$limit watched';
  }

  @override
  String get watchlistAddShort => 'Add';

  @override
  String watchlistLimitReached(int n) {
    return 'You can watch up to $n assets. Remove one to add another.';
  }

  @override
  String watchlistLimitFree(int n) {
    return 'On the free plan you can watch up to $n assets.';
  }

  @override
  String get partnershipAcceptedShort => 'Partnership accepted.';

  @override
  String get partnershipRejectedShort => 'Partner request rejected.';

  @override
  String get partnershipApprovalTitle => 'Partnership Approval';

  @override
  String get partnershipApprovalBody =>
      'See and approve the people who entered your partner code here.';

  @override
  String get noPendingRequests => 'No pending partner requests.';

  @override
  String get userWord => 'User';

  @override
  String get enteredYourCode =>
      'Entered your partner code and is waiting for approval.';

  @override
  String get portfolioChange => 'Portfolio change';

  @override
  String aheadOfInflationPts(String pts) {
    return '$pts points ahead of inflation';
  }

  @override
  String betterThanPctInvestors(int pct, String ek) {
    return 'Better than $pct% of investors';
  }

  @override
  String nDaysTracked(int n) {
    return '$n days tracked';
  }

  @override
  String get trackingWithSandik => 'tracked with sandık';

  @override
  String get shareCardNoAmounts =>
      'The card shows no amounts; only percentages and labels.';

  @override
  String get preparingEllipsis => 'Preparing…';

  @override
  String get shareAsImage => 'Share as image';

  @override
  String get shareAsText => 'Share as text';

  @override
  String behindInflationPts(String pts) {
    return '$pts points behind inflation';
  }

  @override
  String get assetNotFound => 'Asset not found';

  @override
  String get myMarketReturn => 'My market return';

  @override
  String get dataExported =>
      'Your data was prepared as a JSON file and shared.';

  @override
  String mailAppFailed(String email) {
    return 'Could not open your mail app. Please write to $email.';
  }

  @override
  String get notifSubtitleIos =>
      'Signals, price alerts, quiet hours, Live Activity';

  @override
  String get notifSubtitleAndroid => 'Signals, price alerts, quiet hours';

  @override
  String get alertSetFromAssetScreen => 'Set from the bell on an asset screen';

  @override
  String get sessionTimedOut =>
      'You were signed out for safety. Turn on the lock in Settings › Privacy and this will not happen again.';

  @override
  String lockOfferTitle(String yontem) {
    String _temp0 = intl.Intl.selectLogic(
      yontem,
      {
        'faceId': 'Protect with Face ID',
        'touchId': 'Protect with Touch ID',
        'biyometrik': 'Protect with biometrics',
        'other': 'Protect with your screen lock',
      },
    );
    return '$_temp0';
  }

  @override
  String get lockOfferBody =>
      'Your portfolio lives in your pocket. With the lock on, the app recognises you without getting in your way.';

  @override
  String get lockOfferBenefitStay => 'You stay signed in';

  @override
  String get lockOfferBenefitStayBody =>
      'With the lock off, leaving the app for 10 minutes signs you out for safety and you have to enter your password again. With the lock on, your session stays put.';

  @override
  String get lockOfferBenefitPush => 'Your alerts keep coming';

  @override
  String get lockOfferBenefitPushBody =>
      'Signing out also silences your price alerts and daily summary. With the lock on, they keep arriving.';

  @override
  String get lockOfferBenefitPrivacy => 'Your portfolio stays hidden';

  @override
  String get lockOfferBenefitPrivacyBody =>
      'If someone else picks up your phone, your balances will not open until you verify it is you.';

  @override
  String lockOfferAccept(String yontem) {
    String _temp0 = intl.Intl.selectLogic(
      yontem,
      {
        'faceId': 'Turn on Face ID',
        'touchId': 'Turn on Touch ID',
        'biyometrik': 'Turn on biometric lock',
        'other': 'Turn on app lock',
      },
    );
    return '$_temp0';
  }

  @override
  String get lockOfferDecline => 'Not now';

  @override
  String get lockOfferLater =>
      'You can turn this on later in Settings › Privacy.';

  @override
  String get noBiometricOnDevice =>
      'No biometrics or PIN is set up on this device.';

  @override
  String get biometricPrompt =>
      'Verify your identity to enable the biometric lock';

  @override
  String get rateNotFetched =>
      'The exchange rate hasn\'t been fetched yet; amounts stay in ₺ for now.';

  @override
  String baseCurrencyNote(String unit) {
    return 'Amounts are shown in $unit at today\'s rate; calculations stay in ₺.';
  }

  @override
  String get startHour => 'Start time';

  @override
  String get endHour => 'End time';

  @override
  String get liveActivityIosNote =>
      'iOS keeps a Live Activity session open for at most 8 hours. Opening the app refreshes it; if you never open it, it may drop off the lock screen.';

  @override
  String get marketClosedNote =>
      'While the exchange is closed, stocks and funds show the last close; gold, FX and crypto stay live.';

  @override
  String get hiddenWeekend =>
      'Not visible right now: weekend display is off. Use the switch above to turn it on.';

  @override
  String hiddenOutsideWindow(String start, String end) {
    return 'Not visible right now: you\'re outside the $start-$end window. The banner appears at $start. To see it now, turn on \"Show all day\".';
  }

  @override
  String get quietStart => 'Quiet start';

  @override
  String get quietEnd => 'Quiet end';

  @override
  String quietHoursOn(String start, String end) {
    return 'Briefing, summary, calendar and alert pushes are not sent between $start and $end';
  }

  @override
  String get quietHoursOff =>
      'Silence all proactive notifications during chosen night hours';

  @override
  String get passwordLabel => 'Password';

  @override
  String aheadOfInflationPeriod(String pts) {
    return 'This period you are $pts points ahead of inflation.';
  }

  @override
  String get realReturnPositive =>
      'Your portfolio delivered a real return above inflation; your purchasing power grew.';

  @override
  String percentileSentence(int pct) {
    return 'You are above $pct% of participants.';
  }

  @override
  String get noDrawdown =>
      'Your portfolio did not fall from its peak in this window.';

  @override
  String concentrationBody(String pct, String label, int n, String tail) {
    return '$pct% of your portfolio sits in $label; you have $n positions in total.$tail';
  }

  @override
  String get riskAdjustedReturn => 'Risk-adjusted return';

  @override
  String get riskAdjustedBody =>
      'Annual return ÷ annual volatility. The Sharpe ratio without a risk-free rate: how many points of return per unit of swing you take on.';

  @override
  String get timingEffectBody =>
      'Return on your money (XIRR) − market return. Positive means your buy dates beat the market; negative means you bought in expensive.';

  @override
  String recoveryDays(int n) {
    return '$n days';
  }

  @override
  String get recoveryBody =>
      'Time from the bottom of your largest drawdown back to the old peak.';

  @override
  String get notYet => 'Not yet';

  @override
  String get notRecoveredBody =>
      'After the largest drawdown, the old peak has not been reached again.';

  @override
  String get timingEffect => 'Timing effect';

  @override
  String get recoveryWord => 'Recovery';

  @override
  String get intradayWord => 'Intraday';

  @override
  String get todayWord => 'Today';

  @override
  String get nowWord => 'Now';

  @override
  String behindInflationPeriod(String pts) {
    return 'This period you are $pts points behind inflation.';
  }

  @override
  String get realReturnNegative =>
      'Your portfolio fell short of inflation; your purchasing power shrank.';

  @override
  String get realReturnEven =>
      'Your portfolio kept pace with inflation; your purchasing power held steady.';

  @override
  String nPeopleParen(int n) {
    return '($n people)';
  }

  @override
  String recoveredInDays(int n) {
    return ' and recovered in $n days';
  }

  @override
  String get notRecoveredYet => ' and has not returned to that level yet';

  @override
  String get singleAssetHeavy =>
      'A single asset\'s move noticeably affects your portfolio.';

  @override
  String drawdownBody(String pct, String tail) {
    return 'Your portfolio fell at most $pct% from its highest level$tail.';
  }

  @override
  String get rangeAllTime => 'All time';

  @override
  String get rangeLast7 => 'Last 7 days';

  @override
  String get rangeLast30 => 'Last 30 days';

  @override
  String get rangeLast90 => 'Last 90 days';

  @override
  String get rangeThisYear => 'This year';

  @override
  String get rangeCustom => 'Custom';

  @override
  String get noRecords => 'No records';

  @override
  String nRecords(int n) {
    return '$n records';
  }

  @override
  String nShown(int n) {
    return ' · $n shown';
  }

  @override
  String get noMatchingRecords => 'No records match the filter';

  @override
  String get noTransactionsYet => 'No transactions yet';

  @override
  String get todaysBalanceChange => 'Today\'s total change';

  @override
  String sinceDateToToday(String date) {
    return '$date → today';
  }

  @override
  String balanceChangeSince(String date) {
    return 'Total change since $date';
  }

  @override
  String periodChangeSim(String period) {
    return '$period change · simulation';
  }

  @override
  String periodBalanceChange(String period) {
    return '$period total change';
  }

  @override
  String get marketOnlyRow => 'Price effect only';

  @override
  String rowExpandedSemantics(String label) {
    return '$label, expanded. Double tap to collapse.';
  }

  @override
  String gainAmount(String amount) {
    return 'gain $amount';
  }

  @override
  String flowBuyLower(String amount) {
    return 'bought $amount in period';
  }

  @override
  String rowCollapsedSemantics(String label) {
    return '$label, collapsed. Double tap to see what\'s inside.';
  }

  @override
  String lossAmount(String amount) {
    return 'loss $amount';
  }

  @override
  String flowSellLower(String amount) {
    return 'sold $amount in period';
  }

  @override
  String flowSellUpper(String amount) {
    return 'Sold $amount in period';
  }

  @override
  String flowBuyUpper(String amount) {
    return 'Bought $amount in period';
  }

  @override
  String get raceFooterGlobal =>
      'The ranking is the return on your picks: the assets you held each day are valued at market prices, and when money was added doesn\'t matter. Rankings and allocations are anonymous; identity, quantity and TRY figures are never shared.';

  @override
  String get calculatingEllipsis => 'Calculating…';

  @override
  String nThousandPeople(String n) {
    return '${n}K PEOPLE';
  }

  @override
  String nPeopleUpper(int n) {
    return '$n PEOPLE';
  }

  @override
  String get toneTop5 => 'You\'re in the top few';

  @override
  String get toneTop10 => 'You\'re in sandık\'s top 10%';

  @override
  String get toneTop25 => 'Well above average';

  @override
  String get toneTop50 => 'Above average';

  @override
  String get toneTop75 => 'Close to average';

  @override
  String get toneRest => 'You can do better. Follow the 30D view';

  @override
  String get raceFooterPartners =>
      'The ranking is the return on your picks in the selected period (%): when money was added doesn\'t matter. No one\'s asset list is visible.';

  @override
  String get recapYourPortfolio => 'Your portfolio';

  @override
  String get recapGrewThisYear => 'This is how you grew this year.';

  @override
  String get recapToughYear => 'It was a tough year.';

  @override
  String get recapVsInflation => 'Against inflation · last 12 months';

  @override
  String get recapKeptPower =>
      'You protected your purchasing power and added to it.';

  @override
  String get recapInflationWon =>
      'Inflation was ahead over the last 12 months.';

  @override
  String recapInflationWindow(String start, String end) {
    return 'Measured: $start - $end (CPI is published monthly, so the window ends at the last released month)';
  }

  @override
  String get recapBestAsset => 'Biggest winner';

  @override
  String recapReturnedPct(String pct) {
    return 'It returned $pct% so far.';
  }

  @override
  String get recapMostPatient => 'Your most patient holding';

  @override
  String recapInPortfolioDays(int n) {
    return 'It has been in your portfolio for $n days.';
  }

  @override
  String recapTypeCount(int n) {
    return 'Across $n asset types.';
  }

  @override
  String get recapForAYear => 'For a whole year.';

  @override
  String recapShareTitle(int year) {
    return 'My sandık Recap $year';
  }

  @override
  String get shareWord => 'Share';

  @override
  String get scopeTogether => 'Together';

  @override
  String get scopeMe => 'Me';

  @override
  String get scopeLabel => 'Scope';

  @override
  String get scopeSearch => 'Search partners';

  @override
  String scopePeopleCount(int n) {
    return '$n people';
  }

  @override
  String get scopeSwipeHint => 'You can also swipe the card left/right';

  @override
  String get scopeNoMatch => 'No matching partner';

  @override
  String get scopeWho => 'Whose portfolio';

  @override
  String get scopePartners => 'Partners';

  @override
  String get chartTypeTooltip => 'Chart type';

  @override
  String get fullscreenChart => 'Open chart full screen';

  @override
  String get whatsNewTitle => 'What\'s New';

  @override
  String get whatsNewSubtitle => 'See what changed in this version';

  @override
  String get whatsNewEmpty => 'No notes for this version.';

  @override
  String appVersionLabel(String surum) {
    return 'sandık · version $surum';
  }

  @override
  String get shareCardBest => 'Best';

  @override
  String get shareCardWorst => 'Weakest';

  @override
  String get shareCardUpDays => 'Up days';

  @override
  String shareCardUpDaysValue(int up, int total) {
    return '$up/$total';
  }

  @override
  String shareCardReal(String pct) {
    return 'real $pct';
  }

  @override
  String get shareCardXirr => 'Annual return';

  @override
  String get shareCardDrawdown => 'Max drawdown';

  @override
  String get shareCardPatient => 'Most patient';

  @override
  String get shareCardAllocation => 'Allocation';

  @override
  String get shareCardTracked => 'Tracked';

  @override
  String get shareCardInvestors => 'Better than';

  @override
  String shareCardBetterThanPct(int pct, String ek) {
    return '$pct% of investors';
  }

  @override
  String shareCardRange(String start, String end) {
    return '$start - $end';
  }

  @override
  String get notifTypePartner => 'PARTNER';

  @override
  String get notifTypeDailyBrief => 'DAILY';

  @override
  String get notifTypeWeekly => 'WEEKLY';

  @override
  String get notifTypeReminder => 'REMINDER';

  @override
  String notifToday(String time) {
    return 'Today $time';
  }

  @override
  String get reviewPromptTitle => 'Enjoying sandık?';

  @override
  String get reviewPromptBody =>
      'A quick rating helps more investors find the app. You can always do it later.';

  @override
  String get reviewPromptYes => 'Yes, rate it';

  @override
  String get reviewPromptLater => 'Later';

  @override
  String get reviewPromptIssue => 'Something\'s off';

  @override
  String get rateAppTitle => 'Rate sandık';

  @override
  String get rateAppSubtitle => 'Leave a rating on the store';

  @override
  String get todayMarketOnly => 'price effect only';

  @override
  String todaySessionOpen(String close) {
    return 'Session open · closes $close';
  }

  @override
  String todayOpensAt(String when) {
    return 'opens $when';
  }

  @override
  String get todayClosedWord => 'Market closed';

  @override
  String get todayLiveWord => 'Live';

  @override
  String get todayLoading => 'Intraday data loading';

  @override
  String get todayRealLabel => 'Versus inflation';

  @override
  String get todayRealHint => 'Yearly return minus CPI';

  @override
  String get todayWeekHint => 'Market effect on your portfolio · summary ready';

  @override
  String get todayGoalLabel => 'Goal';

  @override
  String get todayGoalSetShort => 'Pick an amount, see what\'s left daily';

  @override
  String get todayGoalAction => 'Set';

  @override
  String todayGoalLeftHint(String goal) {
    return 'Left to $goal';
  }

  @override
  String todayGoalValue(int pct, String left) {
    return '$pct% · $left';
  }

  @override
  String get todayGoalDone => 'Reached';

  @override
  String todayGoalDoneHint(String goal) {
    return 'Goal $goal · pick a new one';
  }

  @override
  String get todayOpenAction => 'Open';

  @override
  String get todayTitle => 'Today';

  @override
  String todayScopeOf(String name) {
    return '$name\'s today';
  }

  @override
  String todayUp(String amount, String pct) {
    return '$amount · up $pct%';
  }

  @override
  String todayDown(String amount, String pct) {
    return '$amount · down $pct%';
  }

  @override
  String get todayFlat => 'No change today';

  @override
  String todayAt(String time) {
    return 'today at $time';
  }

  @override
  String todayMarketClosed(String when) {
    return 'Market closed · opens $when';
  }

  @override
  String todayGreenShare(int green, int total) {
    return '$green of $total holdings in the green';
  }

  @override
  String get todayGoalSet => 'Set a goal';

  @override
  String get todayGoalSetHint =>
      'Pick a target for your portfolio and track what\'s left every day.';

  @override
  String todayGoalProgress(int pct, String left) {
    return '$pct% to goal · $left to go';
  }

  @override
  String todayGoalReached(String goal) {
    return 'Goal reached: $goal';
  }

  @override
  String todayInDays(int n) {
    return 'in $n days';
  }

  @override
  String todayEventCpi(String when) {
    return 'TurkStat releases inflation $when';
  }

  @override
  String todayEventHoliday(String when) {
    return 'Exchange closed $when (public holiday)';
  }

  @override
  String todayEventMonthEnd(String when) {
    return 'Month ends $when; your monthly summary will be ready';
  }

  @override
  String todayMonthlySummary(String month) {
    return 'Your $month summary is ready';
  }

  @override
  String get todayMonthlySummaryHint =>
      'Return, inflation gap and your best holding';

  @override
  String todayCloseAt(String close) {
    return 'closes $close';
  }

  @override
  String get todayClosedShort => 'Closed';

  @override
  String get todayMarketOnlyShort => 'price effect';

  @override
  String get todayGoalNewAction => 'Pick a new one';

  @override
  String get todayMoveLabel => 'Today\'s move';

  @override
  String get todayRealYearly => 'yearly';

  @override
  String get todayGoalSetAction => 'Set a goal';

  @override
  String get todayGoalSetSub => 'See what\'s left every day';

  @override
  String todayGoalProgressTitle(int pct) {
    return '$pct% to goal';
  }

  @override
  String todayGoalLeftShort(String left) {
    return '$left to go';
  }

  @override
  String get goalTitle => 'Portfolio goal';

  @override
  String get goalHint => 'Display only; it does not change any calculation.';

  @override
  String get goalInvalid => 'Enter a valid amount';

  @override
  String get goalRemove => 'Remove goal';

  @override
  String get goalSettingsSubtitle =>
      'Pick a target; track progress on the Today card';

  @override
  String partnerInviteMessage(String code, String link) {
    return 'Hi! I\'d like to share my sandık portfolio with you.\n\nYour partner code: $code\n\nInstall the app, then enter this code under Profile → \"Enter Partner Code\":\n$link';
  }

  @override
  String get partnerInviteSubject => 'sandık partner invite';

  @override
  String get notifTypeMonthly => 'MONTHLY';

  @override
  String raceJoinedCount(int count, int min) {
    return '$count racing today · ranking opens at $min';
  }

  @override
  String raceRunningCount(int count) {
    return '$count racing today';
  }

  @override
  String get marketDollar => 'USD';

  @override
  String get marketEuro => 'EUR';

  @override
  String get marketGold => 'Gold (g)';

  @override
  String get marketBist => 'BIST 100';

  @override
  String get notifTypeWatchlist => 'WATCHLIST';

  @override
  String get notifTypeInflation => 'CPI';

  @override
  String alarmSuggest(String name) {
    return '$name added. Set a price alert?';
  }

  @override
  String get alarmSuggestAction => 'Set alert';

  @override
  String get briefSlotTitle => 'Brief time';

  @override
  String get briefSlotSubtitle =>
      'When your daily portfolio move summary arrives';

  @override
  String get briefSlotMorning => 'Morning 09:45';

  @override
  String get briefSlotEvening => 'Evening 18:30 (close)';

  @override
  String todayRealReturnAhead(String pts) {
    return '$pts pts ahead of inflation · yearly';
  }

  @override
  String todayRealReturnBehind(String pts) {
    return '$pts pts behind inflation · yearly';
  }

  @override
  String todayWeeklyUp(String pct) {
    return 'Last week market +$pct · summary ready';
  }

  @override
  String todayWeeklyDown(String pct) {
    return 'Last week market −$pct · summary ready';
  }

  @override
  String get sectionResult => 'What happened?';

  @override
  String get sectionWhy => 'Why?';

  @override
  String get sectionDetail => 'Details';

  @override
  String get sectionDepth => 'More';

  @override
  String get sectionDepthHint => 'Annual return, health, character';

  @override
  String get myAlarms => 'My alerts';

  @override
  String get viewChipLabel => 'View';

  @override
  String get identityCrypto => 'Cryptocurrency';

  @override
  String get pickCryptoTap => 'Tap to pick a crypto';

  @override
  String get pickCryptoPrompt => 'Pick a cryptocurrency';

  @override
  String cryptoSelectedSemantics(String name) {
    return 'Selected crypto: $name. Double tap to change.';
  }

  @override
  String get cryptoPickerTitle => 'Cryptocurrencies';

  @override
  String get cryptoSearchHint => 'Search name or code (BTC, Ethereum…)';

  @override
  String get cryptoLoading => 'Loading crypto list';

  @override
  String get cryptoLoadFailed => 'Couldn\'t load the crypto list';

  @override
  String get cryptoSourceNote =>
      'Prices from Binance, updated every minute. Not investment advice.';

  @override
  String get priceDelayed => 'Delayed';

  @override
  String priceDelayedSemantics(String time) {
    return 'Price delayed, last updated $time';
  }

  @override
  String get period5Y => '5Y';

  @override
  String get vsPeriodReturnUpper => 'PERIOD RETURN';

  @override
  String get vsTodayUpper => 'TODAY';

  @override
  String get vsMaxDrawdownUpper => 'MAX DRAWDOWN';

  @override
  String get vsVolatilityUpper => 'VOLATILITY (ANNUAL)';

  @override
  String get vsPeriodLow => 'Period low';

  @override
  String get vsPeriodHigh => 'Period high';

  @override
  String vsRangePosition(String pct) {
    return 'Price is at $pct% of the period range';
  }

  @override
  String get vsVolatilityShortNote =>
      'Volatility is computed for periods of 1 month or longer.';

  @override
  String get adPositionUpper => 'YOUR POSITION';

  @override
  String adPositionLine(String amount, String pct) {
    return 'Your position: $amount ($pct)';
  }

  @override
  String chartOpenLabel(String time, String value) {
    return 'OPEN · $time · $value';
  }

  @override
  String get posQuantity => 'Quantity';

  @override
  String get posBuyPrice => 'Your buy price (avg.)';

  @override
  String get posTodayPrice => 'Today\'s price';

  @override
  String get posTotalCost => 'Total paid';

  @override
  String get posCurrentValue => 'Value today';

  @override
  String get posTotalPnl => 'Total profit/loss';

  @override
  String posPeriodPnl(String period) {
    return '$period profit/loss';
  }

  @override
  String chartStartLabel(String date, String value) {
    return 'START · $date · $value';
  }

  @override
  String get chartNowLabel => 'NOW';

  @override
  String get vsWatch => 'Watch';

  @override
  String get vsSelect => 'Select this';

  @override
  String get vsGoToPosition => 'Go to my position';

  @override
  String get vsOwnedNote =>
      'This asset is in your portfolio. Buy and sell from the position screen.';

  @override
  String vsRemovedFromWatchlist(String name) {
    return '$name removed from watchlist';
  }

  @override
  String get vsUndo => 'Undo';

  @override
  String vsChartSemantics(String name, String period) {
    return '$name price chart, $period';
  }

  @override
  String vsOpenDetailSemantics(String name) {
    return 'See $name chart and statistics';
  }

  @override
  String vsWatchSemantics(String name) {
    return 'Watch $name';
  }

  @override
  String vsUnwatchSemantics(String name) {
    return 'Stop watching $name';
  }

  @override
  String get vsLoadFailed =>
      'Couldn\'t load price history. Check your connection and pick the period again.';

  @override
  String vsSheetSemantics(String name) {
    return '$name asset page';
  }

  @override
  String get searchRecentUpper => 'RECENTLY VIEWED';

  @override
  String get searchMarketsUpper => 'MARKETS';

  @override
  String searchShowAll(int count) {
    return 'All ($count)';
  }

  @override
  String get searchInPortfolioTag => 'In portfolio';

  @override
  String get searchAssetsSemantics => 'Search assets';

  @override
  String get searchChip => 'Search';

  @override
  String get searchShortHint => 'Stocks, funds, gold, FX, crypto';

  @override
  String get kullaniciAdiBaslik => 'Choose your username';

  @override
  String get kullaniciAdiAciklama =>
      'Your partner sees you by this name, and it\'s the name shown in the app. You can change it later in Settings > Account.';

  @override
  String get kullaniciAdiZorunluNot =>
      'You need a username to continue. As soon as you pick an available one, you can go on.';

  @override
  String get kullaniciAdiUygunDevam =>
      'This name is available. You can continue.';

  @override
  String get kullaniciAdiEtiket => 'Username';

  @override
  String get kullaniciAdiKurallar =>
      '3-20 characters: letters, digits, dot and underscore. Starts with a letter, no spaces.';

  @override
  String get kullaniciAdiHataBicim =>
      'Must be 3-20 characters, start with a letter and contain only letters, digits, . and _.';

  @override
  String get kullaniciAdiHataUygunsuz =>
      'This name isn\'t allowed. Try another one.';

  @override
  String get kullaniciAdiHataAyrilmis =>
      'This name is reserved. Try another one.';

  @override
  String get kullaniciAdiHataAlinmis => 'This name is taken. Try another one.';

  @override
  String get kullaniciAdiHataBilinmiyor =>
      'Couldn\'t save. Try again in a moment.';

  @override
  String get kullaniciAdiUygun => 'This name is available.';

  @override
  String get kullaniciAdiDevam => 'Continue';

  @override
  String get kullaniciAdiKaydet => 'Save';

  @override
  String get kullaniciAdiKaydedildi => 'Your username was updated.';

  @override
  String get kullaniciAdiSecilmedi => 'Not chosen yet';

  @override
  String get kullaniciAdiCikis => 'Sign out';

  @override
  String get registerUsernameMissing => 'Enter a username.';

  @override
  String get deletedFilter => 'Deleted';

  @override
  String get deletedEmptyTitle => 'No deleted records';

  @override
  String get deletedEmptyBody =>
      'When you delete an asset, its buys, sells and deletion date stay here; they don\'t count toward your portfolio.';

  @override
  String get ipoTitle => 'IPOs';

  @override
  String get ipoProfileRowSubtitle => 'Calendar, price and participation';

  @override
  String get ipoGroupTalep => 'Taking orders';

  @override
  String get ipoGroupYaklasan => 'Upcoming';

  @override
  String get ipoGroupIslemBekliyor => 'Awaiting listing';

  @override
  String get ipoGroupIslemGoruyor => 'Trading';

  @override
  String get ipoGroupBilinmiyor => 'Dates unknown';

  @override
  String ipoOfflineNote(String tarih) {
    return 'Offline: showing the list from $tarih.';
  }

  @override
  String get ipoOfflineNoDate => 'Offline: showing the saved list.';

  @override
  String ipoListDate(String tarih) {
    return 'List date: $tarih';
  }

  @override
  String get ipoEmpty => 'No IPOs in the list right now.';

  @override
  String get ipoDisclaimer =>
      'For information only, not investment advice. Confirm dates and price with your broker.';

  @override
  String ipoRowTalep(String aralik) {
    return 'Orders: $aralik';
  }

  @override
  String ipoRowIslem(String tarih) {
    return 'Listing: $tarih';
  }

  @override
  String get ipoFieldTalep => 'Order period';

  @override
  String get ipoFieldFiyat => 'Offer price';

  @override
  String get ipoFieldDagitim => 'Allocation';

  @override
  String get ipoFieldIslem => 'First trading day';

  @override
  String get ipoFieldPazar => 'Market';

  @override
  String get ipoFieldGuncelleme => 'Info date';

  @override
  String get ipoDagitimEsit => 'Equal';

  @override
  String get ipoDagitimOransal => 'Pro rata';

  @override
  String get ipoOpenSource => 'Open source';

  @override
  String get ipoSourceFailed => 'Couldn\'t open the link.';

  @override
  String get ipoParticipate => 'I participated, add to portfolio';

  @override
  String get ipoParticipateHint =>
      'Enter the lots you were allocated; price and date are filled in. Until trading starts the stock shows at the offer price.';

  @override
  String get ipoParticipateHintTraded =>
      'Enter the lots you were allocated; the offer price and first trading day are filled in. The stock shows at its live price.';

  @override
  String get ipoParticipateNoPrice =>
      'The offer price isn\'t in the list: type the purchase price in the form. A stock that isn\'t trading has no quote; if you leave it empty the cost is saved as 0.';

  @override
  String get ipoParticipateLater =>
      'Allocations are announced after the order period ends. If you took part, you can add it to your portfolio here then.';

  @override
  String get ipoParticipationSaved =>
      'Your IPO lots were added to your portfolio.';

  @override
  String txDateLabeled(String tur, String tarih) {
    return '$tur: $tarih';
  }

  @override
  String deletedOnDate(String tarih) {
    return 'Deleted: $tarih';
  }

  @override
  String get pickGoldPrompt => 'Pick a gold type';

  @override
  String get pickCurrencyPrompt => 'Pick a currency';

  @override
  String get raceLive => 'Live';

  @override
  String get raceLiveJustNow => 'Live · updated just now';

  @override
  String raceLiveSecondsAgo(int n) {
    return 'Live · updated ${n}s ago';
  }

  @override
  String raceLiveMinutesAgo(int n) {
    return 'Live · updated ${n}m ago';
  }

  @override
  String get raceYou => 'You';

  @override
  String get raceYouTag => 'YOU';

  @override
  String get raceVs => 'VS';

  @override
  String raceGapToLeader(String fark) {
    return '$fark pts behind the leader';
  }

  @override
  String get duelTied => 'Neck and neck';

  @override
  String duelAhead(String ad, String adIyelik, String fark) {
    return '$fark pts ahead of $ad';
  }

  @override
  String raceRankUp(int n) {
    return 'Up $n';
  }

  @override
  String raceRankDown(int n) {
    return 'Down $n';
  }

  @override
  String get filterButton => 'Filter';

  @override
  String filterButtonActive(int n) {
    return 'Filter, $n active';
  }

  @override
  String get filterReset => 'Reset';

  @override
  String get filterPeriodHeader => 'PERIOD';

  @override
  String get filterTypeHeader => 'TYPE';

  @override
  String filterShowN(int n) {
    return 'Show $n records';
  }

  @override
  String get filterNoMatch => 'No matching records';

  @override
  String filterRemove(String ad) {
    return 'Remove $ad filter';
  }

  @override
  String get assetTypeDeposit => 'Deposit';

  @override
  String get assetTypePension => 'Pension (BES)';

  @override
  String get tickerHintDeposit => 'Calculated from the contract';

  @override
  String get tickerHintPension => 'TEFAS pension fund code';

  @override
  String get depositBank => 'Bank';

  @override
  String get depositBankHint => 'e.g. the name of your bank';

  @override
  String get depositPrincipal => 'Amount deposited';

  @override
  String get depositRate => 'Annual interest (gross, %)';

  @override
  String get depositKindTerm => 'Term deposit';

  @override
  String get depositKindDaily => 'Daily interest';

  @override
  String get depositTerm => 'Term';

  @override
  String depositDays(int n) {
    return '$n days';
  }

  @override
  String get depositCustomDays => 'Custom';

  @override
  String get depositCustomDaysHint => 'Number of days';

  @override
  String get depositStart => 'Start date';

  @override
  String get depositWithholding => 'Withholding tax (%)';

  @override
  String get depositWithholdingHint =>
      'Suggested from the term. Change it if your bank applies a different rate.';

  @override
  String get depositMaturity => 'Maturity';

  @override
  String get depositNetReturn => 'Net return';

  @override
  String get depositAtMaturity => 'At maturity';

  @override
  String get depositDailyNet => 'Daily net';

  @override
  String get depositErrorBank => 'Enter the bank\'s name.';

  @override
  String get depositErrorPrincipal => 'Enter the amount.';

  @override
  String get depositErrorRate => 'Enter the interest rate.';

  @override
  String get depositErrorDays => 'Enter the term in days.';

  @override
  String get depositErrorWithholding =>
      'Withholding tax must be between 0 and 100.';

  @override
  String get depositAccrualNote =>
      'Interest is added to the principal at maturity; until then the value stays at the principal. If you break the term early, the bank may not pay the interest.';

  @override
  String get depositCardTitle => 'Deposit';

  @override
  String depositPeriodN(int n) {
    return 'Period $n';
  }

  @override
  String depositDaysLeft(int n) {
    return '$n days to maturity';
  }

  @override
  String get depositMatured => 'Matured';

  @override
  String get depositMaturedBody =>
      'Interest has been added. Enter the new rate to start the next period; otherwise the value stays as it is.';

  @override
  String get depositThisPeriod => 'This period, net';

  @override
  String get depositTotalReturn => 'Total net return';

  @override
  String get depositRenew => 'Renew';

  @override
  String get depositWithdraw => 'Withdrawn';

  @override
  String get depositRenewTitle => 'New period';

  @override
  String get depositRenewSaved => 'New period started';

  @override
  String get depositRateUpdate => 'Update rate';

  @override
  String get depositRateSaved => 'Rate updated';

  @override
  String get depositWithdrawTitle => 'Did you withdraw the money?';

  @override
  String depositWithdrawBody(String amount) {
    return 'The deposit is recorded as sold at today\'s value ($amount).';
  }

  @override
  String get depositWithdrawConfirm => 'Yes, close it';

  @override
  String get depositWithdrawn => 'Deposit closed';

  @override
  String get pensionCompany => 'Pension company';

  @override
  String get pensionCompanyHint => 'e.g. the name of your provider';

  @override
  String get pensionEntryDate => 'Joined the system';

  @override
  String get pensionEntryDateHint =>
      'The vesting rate of the government contribution depends on this.';

  @override
  String get pensionFunds => 'Fund allocation';

  @override
  String get pensionAddFund => 'Add fund';

  @override
  String pensionShareTotal(String pct) {
    return 'Total $pct';
  }

  @override
  String get pensionShareError => 'Fund shares must add up to 100%.';

  @override
  String get pensionFundError => 'Pick at least one pension fund.';

  @override
  String get pensionGov => 'Government contribution';

  @override
  String get pensionGovFund => 'Government contribution fund';

  @override
  String get pensionGovFundHint =>
      'Leave it empty if you don\'t know; it won\'t be added.';

  @override
  String get pensionMonthly => 'Monthly contribution';

  @override
  String get pensionDay => 'Contribution day';

  @override
  String get pensionErrorCompany => 'Enter the company\'s name.';

  @override
  String get pensionErrorBalance => 'Principal plus return must be above zero.';

  @override
  String get pensionErrorGovFund =>
      'Also pick the fund for the government contribution balance.';

  @override
  String pensionPriceMissing(String code) {
    return 'Couldn\'t get the price for $code. Try again shortly.';
  }

  @override
  String get pensionPickFund => 'Pick a pension fund';

  @override
  String get pensionPickGovFund => 'Pick the government contribution fund';

  @override
  String get pensionSearchFund => 'Fund code or name';

  @override
  String get pensionNoFundFound => 'No matching pension fund';

  @override
  String get pensionCardTitle => 'Pension (BES)';

  @override
  String pensionYear(int n) {
    return 'Year $n';
  }

  @override
  String get pensionTotal => 'Total savings';

  @override
  String get pensionOwn => 'Your contributions';

  @override
  String get pensionGovShort => 'Government';

  @override
  String get pensionReturn => 'Return';

  @override
  String get pensionIfLeave => 'If you left today (before tax)';

  @override
  String get pensionVesting => 'Government contribution vesting';

  @override
  String get currentValueUpper => 'CURRENT VALUE';

  @override
  String get depositCardRate => 'Interest';

  @override
  String depositCardRateValue(String rate, String wht) {
    return '$rate% gross · $wht% withholding';
  }

  @override
  String get depositWithholdingManual =>
      'You entered this rate; changing the term or date won\'t overwrite it.';

  @override
  String get depositAccrualNoteDaily =>
      'Net interest is added at the end of each day; the value does not change during the day.';

  @override
  String depositAlreadyMatured(String date) {
    return 'This term matured on $date. After saving, start the next period from the card.';
  }

  @override
  String get depositRenewStartHint =>
      'Banks renew a term deposit on its maturity date. If you renewed on another day, change the date; the days in between earn no interest.';

  @override
  String pensionVestingNextIn(String now, String duration, String next) {
    return '$now · $next in $duration';
  }

  @override
  String pensionVestingSoon(String now, String next) {
    return '$now · $next within a month';
  }

  @override
  String pensionYears(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n years',
      one: '1 year',
    );
    return '$_temp0';
  }

  @override
  String pensionMonths(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n months',
      one: '1 month',
    );
    return '$_temp0';
  }

  @override
  String pensionYearsMonths(int years, int months) {
    return '$years yr $months mo';
  }

  @override
  String dividendAboveGross(String gross) {
    return 'The net amount can\'t be more than the gross ($gross). Check the field.';
  }

  @override
  String get pensionAddContribution => 'Add this month\'s contribution';

  @override
  String get pensionContributionTitle => 'Add contribution';

  @override
  String get pensionContributionAmount => 'Contribution';

  @override
  String pensionContributionGov(String amount) {
    return 'Government contribution: $amount';
  }

  @override
  String get pensionContributionGovCapped =>
      'This year\'s government contribution limit is reached.';

  @override
  String get pensionContributionSaved => 'Contribution added';

  @override
  String get pensionContributionDue =>
      'This month\'s contribution isn\'t added yet.';

  @override
  String get pensionNoGovFund =>
      'No government contribution fund is set; it won\'t be added.';

  @override
  String get pensionPrincipal => 'Principal (contributions paid)';

  @override
  String get pensionPrincipalHint =>
      'Total you have paid in so far; shown as \"contributions\" on your statement.';

  @override
  String get pensionGain => 'Return (profit)';

  @override
  String get pensionGainHint =>
      'The return on your statement. Use a minus sign for a loss.';

  @override
  String get pensionHistoryHint =>
      'The chart values today\'s fund units with your funds\' real price history; if your allocation was different in the past, older periods won\'t match exactly.';

  @override
  String get pensionGovPrincipal => 'Government contribution principal';

  @override
  String get pensionGovGain => 'Government contribution return';

  @override
  String get pensionErrorPrincipal => 'Enter the principal.';

  @override
  String get pensionSwitchFunds => 'Switch funds';

  @override
  String get pensionSwitchTitle => 'Change fund allocation';

  @override
  String get pensionSwitchHint =>
      'Your savings move to the new allocation at today\'s prices. Principal and profit stay the same; the chart follows the new funds from today.';

  @override
  String get pensionSwitchContributions =>
      'Send new contributions to this allocation too';

  @override
  String pensionSwitchCount(int n) {
    return '$n/12 fund switches this year';
  }

  @override
  String get pensionSwitchSaved => 'Fund allocation changed';

  @override
  String get pensionSwitchSame => 'That is already your allocation.';

  @override
  String get pensionSwitchNote => 'Fund switch';

  @override
  String get contractManagedNotice =>
      'This asset is managed by its contract. Use the contract card on the asset page to change it.';

  @override
  String raceMoneyReturn(String pct) {
    return 'Return on your money $pct';
  }

  @override
  String get raceMoneyReturnHint =>
      'Includes when money was added · same as Performance';

  @override
  String get kiyasBaslik => 'Had you put it elsewhere';

  @override
  String get kiyasAciklama =>
      'Had you invested the same amounts on the same days here.';

  @override
  String get kiyasSenin => 'Your portfolio';

  @override
  String get kiyasBasaBas => 'Even';

  @override
  String get kiyasTemettuNotu =>
      'Cash dividends this period count as money paid out to you on both sides.';

  @override
  String get kiyasVeriYok =>
      'Price data for the comparison is unavailable right now.';

  @override
  String get pensionDayHint => 'e.g. 15';

  @override
  String get pensionDayNote =>
      'The day your monthly contribution is taken from your account. At most 28 because days 29-31 don\'t exist in every month; if it\'s taken at month-end, enter 28.';

  @override
  String get pensionDayError => 'Enter a day between 1 and 28.';

  @override
  String get pensionAuto => 'Add contribution automatically';

  @override
  String get pensionAutoNote =>
      'On the contribution day we add your monthly contribution at that day\'s fund price, then ask you to confirm the amount. If off, we only remind you.';

  @override
  String get pensionAutoNeedsPlan =>
      'Enter the monthly contribution and day to add it automatically.';

  @override
  String get pensionAutoLotNote => 'Automatic contribution';

  @override
  String pensionAutoAdded(String date, String amount) {
    return 'Your $date contribution was added automatically: $amount. Want to update the amount?';
  }

  @override
  String get pensionAutoConfirm => 'Amount is right';

  @override
  String get pensionAutoUpdate => 'Update amount';

  @override
  String get pensionAutoUpdateTitle => 'Update automatic contribution';

  @override
  String get pensionAutoUpdatePlan =>
      'Use this amount for the coming months too';

  @override
  String get pensionAutoUpdated => 'Contribution updated';

  @override
  String pensionAutoSnack(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count monthly pension contributions were added automatically. You can update the amount on the pension card.',
      one:
          'Your pension contribution was added automatically. You can update the amount on the pension card.',
    );
    return '$_temp0';
  }

  @override
  String get pensionAddExtraContribution => 'Add extra contribution';

  @override
  String cpiSentenceMonth(String month, String change, String cpi) {
    return 'In $month your savings $change; monthly inflation was $cpi.';
  }

  @override
  String cpiSentenceRange(String start, String end, String change, String cpi) {
    return 'Between $start and $end your savings $change; inflation was $cpi.';
  }

  @override
  String cpiSentenceYear(String start, String end, String change, String cpi) {
    return 'Over the last year ($start - $end) your savings $change; inflation was $cpi.';
  }

  @override
  String cpiSentenceSinceFirstBuy(
      String date, String end, String change, String cpi) {
    return 'From your first purchase ($date) to the end of $end your savings $change; inflation was $cpi.';
  }

  @override
  String savingsRose(String pct) {
    return 'grew $pct';
  }

  @override
  String savingsFell(String pct) {
    return 'fell $pct';
  }

  @override
  String get savingsFlat => 'did not change';

  @override
  String get purchasingPowerUp => 'your purchasing power grew.';

  @override
  String get purchasingPowerDown => 'your purchasing power shrank.';

  @override
  String get purchasingPowerKept => 'your purchasing power held steady.';

  @override
  String cpiNextNote(String month, String date) {
    return 'Once $month CPI is published on $date, the comparison will cover $month too.';
  }

  @override
  String cpiNextNoteLate(String month) {
    return 'Once $month CPI is loaded, the comparison will cover $month too.';
  }

  @override
  String cpiShortenedNote(String month) {
    return 'CPI data does not go back that far; the comparison starts from $month.';
  }

  @override
  String get cpiHowComputed => 'How it was computed';

  @override
  String get compoundRealReturn => 'Compound real return';

  @override
  String get cpiSourceLabel => 'Source';

  @override
  String get cpiSourceValue => 'TurkStat CPI';

  @override
  String vsInflationIn(String window) {
    return 'Versus inflation ($window)';
  }

  @override
  String get investedRow => 'You put in';

  @override
  String get marketAddedRow => 'Price effect';

  @override
  String get dividendPocketRow => 'Dividends you pocketed';

  @override
  String flowBuyBalance(String flow, String change) {
    return 'Bought $flow · total $change';
  }

  @override
  String flowSellBalance(String flow, String change) {
    return 'Sold $flow · total $change';
  }

  @override
  String ofLastNMonths(String n) {
    return 'Of the last $n months';
  }

  @override
  String ofLastNWeeks(String n) {
    return 'Of the last $n weeks';
  }

  @override
  String ofLastNYears(String n) {
    return 'Of the last $n years';
  }

  @override
  String inMonthPhrase(String month) {
    return 'in $month';
  }

  @override
  String inWeekPhrase(String date) {
    return 'in the week of $date';
  }

  @override
  String inYearPhrase(String year) {
    return 'in $year';
  }

  @override
  String singleContribution(String period, String bucket, String amount) {
    return '$period, you put money in only once: $bucket, $amount.';
  }

  @override
  String singleWithdrawal(String bucket, String amount) {
    return '$bucket you took out $amount.';
  }

  @override
  String onlySalesInWindow(String bucket, String amount) {
    return 'No new money in this window; there were sales: $bucket $amount.';
  }

  @override
  String onlySalesInWindowTotal(String amount) {
    return 'No new money in this window; sales total $amount.';
  }

  @override
  String get marketPound => 'GBP';

  @override
  String get depositInterestAtMaturity => 'Net interest at maturity';

  @override
  String get depositInterestAdded => 'Net interest added';

  @override
  String get depositPaidAtMaturityNote =>
      'Interest is added at maturity; until then the value stays at the principal. If you update the rate during the term, the gain uses the latest rate you entered.';

  @override
  String get depositRateMidTermHint =>
      'The term and start date stay the same. The gain at maturity uses this new rate.';

  @override
  String depositRateSavedMidTerm(String rate) {
    return 'Rate is now $rate%. The gain at maturity will use this rate.';
  }

  @override
  String depositStripRate(String rate) {
    return '$rate% gross interest';
  }

  @override
  String get cihazOtpBaslik => 'Verify this device';

  @override
  String get cihazOtpAciklama =>
      'Your account is being opened on a device that isn\'t on your list. For your security, enter the code we emailed you.';

  @override
  String get cihazOtpIpucu =>
      'Not you? Cancel and change your password. Verifying this device signs out your other devices.';

  @override
  String get cihazOtpVazgec => 'Cancel and sign out';

  @override
  String get cihazKapisiHata =>
      'Couldn\'t verify this device. Check your connection and try again.';

  @override
  String get baskaCihazdaAcildi =>
      'Your account was opened on another device. You have been signed out here.';

  @override
  String get kayitliCihazlar => 'Registered devices';

  @override
  String get kayitliCihazlarAlt =>
      'Your account stays open on one device at a time';

  @override
  String get kayitliCihazlarAciklama =>
      'Your account can be open on only one device at a time. When someone signs in from a device that isn\'t listed, a verification code is sent to your email. Remove any device you don\'t recognize and change your password.';

  @override
  String get buCihaz => 'This device';

  @override
  String cihazSonKullanim(String tarih) {
    return 'Last used: $tarih';
  }

  @override
  String get cihazKaldir => 'Remove';

  @override
  String get cihazKaldirBaslik => 'Remove this device?';

  @override
  String cihazKaldirMesaj(String ad) {
    return '$ad will need to be verified with an email code the next time it signs in.';
  }

  @override
  String get cihazKaldirildi => 'Device removed';

  @override
  String get cihazListesiBos => 'No registered devices.';

  @override
  String get otpSpamIpucu =>
      'Didn\'t get it? Check your Junk / Spam folder too.';

  @override
  String get welcomeSkip => 'Skip';

  @override
  String get welcomeNext => 'Continue';

  @override
  String get welcomeCreateAccount => 'Create account';

  @override
  String get welcomeTryDemo => 'Explore a sample portfolio';

  @override
  String get welcomeHaveAccount => 'I have an account, sign in';

  @override
  String welcomePageOf(int sayfa, int toplam) {
    return 'Introduction, page $sayfa of $toplam';
  }

  @override
  String get welcomeP1Title => 'All your savings on one screen';

  @override
  String get welcomeP1Body =>
      'Enter what you bought once and sandık keeps prices current. See your total, profit and allocation any time.';

  @override
  String get welcomeP2Title => 'Are you really earning?';

  @override
  String get welcomeP2Body =>
      'Compare your return with inflation, the dollar and gold. See what your money itself earned, not your new purchases.';

  @override
  String get welcomeP3Title => 'Follow without opening the app';

  @override
  String get welcomeP3Body =>
      'The home screen widget and morning brief bring your portfolio to you. On iPhone, follow it live on the lock screen.';

  @override
  String get welcomeP4Title => 'Set alerts, track together';

  @override
  String get welcomeP4Body =>
      'We\'ll let you know when a price hits your target. Track a shared portfolio with your partner or family.';

  @override
  String get welcomeTagStock => 'Stocks';

  @override
  String get welcomeTagFund => 'Funds';

  @override
  String get welcomeTagGold => 'Gold';

  @override
  String get welcomeTagFx => 'FX';

  @override
  String get welcomeTagCrypto => 'Crypto';

  @override
  String get welcomeTagPension => 'Pension';

  @override
  String get welcomeTagInflation => 'Inflation';

  @override
  String get welcomeTagUsd => 'Dollar';

  @override
  String get welcomeTagWidget => 'Widget';

  @override
  String get welcomeTagLock => 'Lock screen';

  @override
  String get welcomeTagBrief => 'Morning brief';

  @override
  String get welcomeTagAlarm => 'Price alert';

  @override
  String get welcomeTagPartner => 'Shared portfolio';

  @override
  String get levelBeginnerDescSade =>
      'Simple view: just the core numbers. Technical signals, chart tools and advanced metrics are hidden.';

  @override
  String get levelSurveyIntro =>
      'Three quick questions to tailor the screens to you.';

  @override
  String levelSurveyProgress(int no, int toplam) {
    return 'Question $no of $toplam';
  }

  @override
  String get levelSurveyQ1 => 'How long have you been investing?';

  @override
  String get levelSurveyQ1A0 => 'Just starting';

  @override
  String get levelSurveyQ1A1 => '1-3 years';

  @override
  String get levelSurveyQ1A2 => 'More than 3 years';

  @override
  String get levelSurveyQ2 => 'Where are most of your savings?';

  @override
  String get levelSurveyQ2A0 => 'Gold, FX, deposits';

  @override
  String get levelSurveyQ2A1 => 'Funds and stocks';

  @override
  String get levelSurveyQ2A2 => 'Active stock and crypto trading';

  @override
  String get levelSurveyQ3 => 'Which of these terms are familiar?';

  @override
  String get levelSurveyQ3A0 => 'Not really';

  @override
  String get levelSurveyQ3A1 => 'Inflation-adjusted return, allocation';

  @override
  String get levelSurveyQ3A2 => 'Volatility, XIRR, RSI';

  @override
  String levelSurveyResult(String seviye) {
    return 'The $seviye view suits you.';
  }

  @override
  String get levelSurveyResultNote =>
      'You can change it any time in Settings › Appearance.';

  @override
  String get levelSurveyRetake => 'Retake the survey';

  @override
  String get levelSurveyOpen => 'Find my level with 3 questions';

  @override
  String get levelSurveyBack => 'Back';

  @override
  String get todaysReturn => 'Today\'s return';

  @override
  String returnSince(String date) {
    return 'Return since $date';
  }

  @override
  String get balanceChangeInclBuys => 'Total change (incl. buys)';

  @override
  String get firstAssetPickTitle => 'What are you saving in?';

  @override
  String get firstAssetPickHint =>
      'Pick one, type the amount; the price fills itself.';

  @override
  String get firstAssetGoldGram => 'Gram gold';

  @override
  String get firstAssetUsd => 'Dollar';

  @override
  String get firstAssetEur => 'Euro';

  @override
  String get firstAssetFund => 'A fund';

  @override
  String get firstAssetStock => 'A stock';

  @override
  String get firstAssetOtherType => 'Add another type';

  @override
  String get addDetails => 'Add details (fee, note)';

  @override
  String get addByTyping => 'Add by typing';

  @override
  String get importFromStatement => 'Import statement';

  @override
  String get orWithEmail => 'or with email';

  @override
  String get todayTopMoverLabel => 'Biggest mover';

  @override
  String get todayVsInflationYou => 'Your return';

  @override
  String get todayVsInflationCpi => 'CPI';

  @override
  String get vitrinWelcome => 'Welcome';

  @override
  String get vitrinTitle => 'What do you own?';

  @override
  String get vitrinHint =>
      'Tap and type the amount. Prices are live; your sandık keeps itself up to date.';

  @override
  String get vitrinLive => 'Live prices';

  @override
  String get vitrinQuarterGold => 'Quarter gold';

  @override
  String get vitrinFundHint => 'Every fund on TEFAS';

  @override
  String get vitrinStockHint => 'Borsa Istanbul';

  @override
  String get vitrinOtherTypes =>
      'Crypto, commodities, deposits, pension and more';

  @override
  String get vitrinOtherTypesShort => 'Crypto, pension and more';

  @override
  String get vitrinStatementHint => 'Broker PDF, Excel or CSV, all in one go';

  @override
  String get vitrinStatementHintShort => 'PDF, Excel or CSV in one go';

  @override
  String get vitrinTapToAdd => 'Tap to add';

  @override
  String get vitrinPriceUnknown => 'No price yet';

  @override
  String get rankingTitle => 'Rankings';

  @override
  String get rankingTabPartners => 'My partners';

  @override
  String get rankingTabEveryone => 'Top portfolios';

  @override
  String get todaysPortfolioBadge => 'With today\'s portfolio';

  @override
  String get todaysPortfolioBadgeHint =>
      'You can turn this view off in Settings › Appearance.';

  @override
  String get todaysPortfolioSettingTitle => 'Show with today\'s portfolio';

  @override
  String get todaysPortfolioSettingSubtitle =>
      'Performance is drawn as if you had held today\'s holdings for the whole period. When off, your actual history is shown.';

  @override
  String get settingsGroupGeneral => 'GENERAL';

  @override
  String get settingsGroupPortfolioView => 'PORTFOLIO VIEW';

  @override
  String get settingsGroupSecurityAccount => 'SECURITY & ACCOUNT';

  @override
  String get settingsGroupData => 'DATA';

  @override
  String get settingsGroupAbout => 'ABOUT THE APP';

  @override
  String get settingsAdvancedUpper => 'ADVANCED';

  @override
  String get settingsAdvancedSemantics => 'Advanced settings';

  @override
  String get settingsThemeLabel => 'Theme';

  @override
  String get settingsBaseCurrencyLabel => 'Base currency';

  @override
  String get tekOnayBaslik => 'Legal Terms';

  @override
  String tekOnayAciklama(String ulke) {
    return 'The app is not investment advice; prices and technical analysis are for information only. Your data is stored on Supabase ($ulke) and Firebase (USA/global); details are in the Privacy Policy and the KVKK Privacy Notice.';
  }

  @override
  String get tekOnayUlkeBilinmiyor => 'abroad';

  @override
  String tekOnayCumle(String kosullar, String gizlilik, String kvkk) {
    return 'I accept the $kosullar and I am over 18. I have been informed by the $gizlilik and the $kvkk.';
  }

  @override
  String get tekOnayKosullarBaglanti => 'Terms of Use';

  @override
  String get tekOnayKvkkBaglanti => 'KVKK Privacy Notice';

  @override
  String get tekOnayGerekli =>
      'To continue, tick the box to accept the Terms of Use.';

  @override
  String get arenaMeasuring => 'Measuring the gap…';

  @override
  String arenaBehind(String ad, String fark) {
    return '$ad leads by $fark pts · you can catch up';
  }

  @override
  String get arenaNoDataYet => 'No data yet';

  @override
  String get arenaWaiting => 'The duel starts once both returns are measured';

  @override
  String get arenaStripDaily => 'Leader day by day';

  @override
  String get arenaStripMonthly => 'Leader month by month';

  @override
  String arenaSwaps(int n) {
    String _temp0 = intl.Intl.pluralLogic(
      n,
      locale: localeName,
      other: '$n lead changes',
      one: '1 lead change',
      zero: 'No lead changes',
    );
    return '$_temp0';
  }

  @override
  String get yasalKapiBaslikGuncel => 'Updated documents';

  @override
  String get yasalKapiBaslikIlk => 'Legal documents';

  @override
  String get yasalKapiAciklamaGuncel =>
      'We\'ve updated our legal documents. To continue, complete the steps below.';

  @override
  String get yasalKapiAciklamaIlk =>
      'Before you start using the app, complete the steps below.';

  @override
  String get yasalKapiNelerDegisti => 'What changed';

  @override
  String get yasalKapiDegisiklikNotu =>
      'Version 1.8: Premium subscription terms were added (price, auto-renewal, cancellation, refunds). If you buy Premium, your subscription is verified through RevenueCat (USA); your card details never reach us. RevenueCat was therefore added to the Explicit Consent Notice. Price sources are no longer listed one by one, because no personal data goes to them. From now on, corrections that do not change how personal data is processed will not ask for a new confirmation. Version 1.7: Two new sources were added for eurobond prices: Börse Frankfurt and Ziraat Bankası. Only our server connects to them and it asks only for the bond\'s ISIN; none of your personal data is sent. Version 1.6: In statement import, if the app is unsure about the columns it offers \"Map with AI\". If you tap it, only an anonymous skeleton of the tables (names, numbers, amounts and dates hidden) goes to AI (Anthropic); the file never leaves your phone and the skeleton is not stored. Version 1.5: asset notes were added. Weekly notes and a monthly report for the assets in your portfolio are written with AI (Anthropic); none of your personal data is sent to the AI, only the asset\'s market metrics. Notes are checked automatically but may contain errors and are not investment advice. Your feedback on notes (vote, \"wrong number\" flag, explanation) and your Premium entitlement are stored with your account and deleted when you delete it.';

  @override
  String get yasalBelgeKosullar => 'Terms of Use';

  @override
  String get yasalBelgeGizlilik => 'Privacy Policy';

  @override
  String get yasalBelgeKvkk => 'KVKK Privacy Notice';

  @override
  String get yasalBelgeKvkkKisa => 'KVKK Notice';

  @override
  String get yasalBelgelerTurkce => 'The documents are in Turkish.';

  @override
  String get yasalKapiOnayla => 'I have read and accept';

  @override
  String get yasalKapiOnaylaKisa => 'I accept';

  @override
  String get yasalKapiKayitHatasi =>
      'Your acceptance couldn\'t be saved. Check your connection and try again.';

  @override
  String get yasalKapiCikis => 'Sign out';

  @override
  String get yasalBelgeAcikRiza => 'Explicit Consent Notice';

  @override
  String get yasalBelgeAcikRizaAciklama => 'International data transfer';

  @override
  String get zorunluOkumaIpucu => 'Scroll to the end to accept';

  @override
  String get zorunluOkumaIpucuKisa => 'Read to the end';

  @override
  String get zorunluOkumaIlerleme => 'Reading progress';

  @override
  String get zorunluOkumaOnayla => 'I\'ve read it and I accept';

  @override
  String get zorunluOkumaOnaylaKisa => 'I accept';

  @override
  String get zorunluOkumaRizaVer => 'I\'ve read it and I give explicit consent';

  @override
  String get zorunluOkumaRizaVerKisa => 'I give consent';

  @override
  String zorunluOkumaEksik(String belgeler) {
    return 'To continue, read to the end and accept: $belgeler';
  }

  @override
  String get yasalBelgeYatirimUyarisi => 'Investment Disclaimer';

  @override
  String get flowTitleUpper => 'MONEY FLOW';

  @override
  String get flowLastWeekIn => 'Net inflow, latest week';

  @override
  String get flowLastWeekOut => 'Net outflow, latest week';

  @override
  String get flowLastWeekFlat => 'Net flow, latest week';

  @override
  String flowRange(String from, String to) {
    return '$from - $to';
  }

  @override
  String get flowChartCaption => 'Weekly net flow · last 8 weeks';

  @override
  String flowChartSemantics(String amount) {
    return 'Weekly net money flow for the last 8 weeks. Latest week $amount.';
  }

  @override
  String flowWeekOf(String date) {
    return 'Week of $date';
  }

  @override
  String get flowFundSize => 'Fund size';

  @override
  String get flowInvestors => 'Investors';

  @override
  String flowInvestorsDelta(String count, String delta) {
    return '$count ($delta)';
  }

  @override
  String get flowEventsTitle => 'Large moves · last 30 days';

  @override
  String flowEventIn(String date) {
    return 'Large inflow · $date';
  }

  @override
  String flowEventOut(String date) {
    return 'Large outflow · $date';
  }

  @override
  String flowEventEvidence(String amount, String pct, String times) {
    return '$amount · $pct of fund size · $times× the usual daily move';
  }

  @override
  String flowEventInvestors(String delta) {
    return 'Investors that day $delta';
  }

  @override
  String get flowNoEvents =>
      'No unusually large inflow or outflow in the last 30 days.';

  @override
  String get flowExplain =>
      'Net flow is money entering the fund minus money leaving it; price changes are not included.';

  @override
  String flowFootnote(String date) {
    return 'Source: TEFAS · data as of $date. This data cannot show who bought or sold. Past flows do not indicate future returns; not investment advice.';
  }

  @override
  String flowStreakIn(String count) {
    return 'Net inflow for $count weeks in a row';
  }

  @override
  String flowStreakOut(String count) {
    return 'Net outflow for $count weeks in a row';
  }

  @override
  String get flowPeriod1m => 'Last 1 month';

  @override
  String get flowPeriod3m => 'Last 3 months';

  @override
  String flowPeriodValue(String amount, String pct) {
    return '$amount · $pct';
  }

  @override
  String get flowPeriodNote =>
      'Percentages are the flow relative to fund size at the start of the period.';

  @override
  String flowDecompose(String total, String price, String flow) {
    return 'Fund size changed $total over the last month: price effect $price, money flow $flow.';
  }

  @override
  String flowEventEvidenceMulti(String amount, String pct, String days) {
    return '$amount · $pct of fund size · $days trading days in a row';
  }

  @override
  String get weekTitle => 'This week';

  @override
  String get weekIntro =>
      'Highlights of the latest week in the assets you hold. Tap a row for details.';

  @override
  String get weekFundsUpper => 'MONEY FLOW IN YOUR FUNDS';

  @override
  String weekRowRange(String label, String range) {
    return '$label · $range';
  }

  @override
  String get weekRowIn => 'Net inflow';

  @override
  String get weekRowOut => 'Net outflow';

  @override
  String get weekRowFlat => 'Net flow';

  @override
  String get weekRowBigIn => 'Large inflow this week';

  @override
  String get weekRowBigOut => 'Large outflow this week';

  @override
  String get weekEmptyNoData =>
      'Nothing to show this week. Money flow in your funds and unusual volume days in your stocks or crypto appear here once their data arrives.';

  @override
  String get weekFootnote =>
      'Sources: TEFAS, Yahoo Finance, Binance. Net flow is money entering minus money leaving the fund; this data cannot show who bought or sold. Your portfolio\'s weekly return is under Performance, Summary. Not investment advice.';

  @override
  String get weekLink => 'My funds this week';

  @override
  String get volTitleUpper => 'VOLUME RADAR';

  @override
  String volLastDay(String date) {
    return 'Traded value · $date';
  }

  @override
  String volVsAverage(String times) {
    return '$times× the average of the previous 20 days';
  }

  @override
  String volPriceSameDay(String pct) {
    return 'Price that day $pct';
  }

  @override
  String get volChartCaption => 'Daily traded value · last 20 trading days';

  @override
  String volChartSemantics(String amount) {
    return 'Daily traded value for the last 20 trading days. Latest day $amount.';
  }

  @override
  String get volExplain =>
      'Traded value is the total value of shares that changed hands that day. Every trade has a buyer and a seller; high volume alone does not mean money flowed in or out.';

  @override
  String get volEventsTitle => 'Unusual volume days · last 30 days';

  @override
  String volEventTitle(String date) {
    return 'Unusual volume · $date';
  }

  @override
  String volEventEvidence(String amount, String times, String pct) {
    return '$amount · $times× the average · price $pct';
  }

  @override
  String get volNoEvents => 'No unusual volume days in the last 30 days.';

  @override
  String volFootnote(String date) {
    return 'Source: Yahoo Finance end-of-day data · as of $date. This data cannot show who bought or sold. Not investment advice.';
  }

  @override
  String get cryTitleUpper => 'BUYER PRESSURE';

  @override
  String cryShareLabel(String date) {
    return 'Buyer share · $date';
  }

  @override
  String cryShareAvg(String pct) {
    return 'Average of the last 7 days $pct';
  }

  @override
  String get cryExplain =>
      'Buyer share is the part of the day\'s volume that came from market-order buyers. Above 50% means buyers were more eager, below means sellers were; it is not a measure of money flowing in.';

  @override
  String cryVolumeLabel(String amount) {
    return 'Volume $amount';
  }

  @override
  String get cryChartCaption => 'Daily volume (USDT) · last 20 days';

  @override
  String cryChartSemantics(String amount) {
    return 'Daily volume for the last 20 days. Latest day $amount.';
  }

  @override
  String cryEventEvidence(
      String amount, String times, String pct, String share) {
    return '$amount · $times× the average · price $pct · buyer share $share';
  }

  @override
  String cryFootnote(String date) {
    return 'Source: Binance, USDT pair · as of $date. Covers trades on Binance only; this data cannot show who bought or sold. Not investment advice.';
  }

  @override
  String get weekVolumeUpper => 'UNUSUAL VOLUME';

  @override
  String weekVolumeRow(String date) {
    return 'Unusual volume · $date';
  }

  @override
  String get tekOnayGizlilikBaglanti => 'Privacy Policy';

  @override
  String get yasalBelgeAcildi => 'Opened';

  @override
  String yasalAdimKayitBaslik(int sayi) {
    String _temp0 = intl.Intl.pluralLogic(
      sayi,
      locale: localeName,
      other: '$sayi steps to sign up',
      one: '1 step to sign up',
    );
    return '$_temp0';
  }

  @override
  String yasalAdimKapiBaslik(int sayi) {
    String _temp0 = intl.Intl.pluralLogic(
      sayi,
      locale: localeName,
      other: '$sayi steps',
      one: '1 step',
    );
    return '$_temp0';
  }

  @override
  String get yasalAdimUyariAciklama =>
      'A short text explaining that the app is not investment advice. Read it to the end and accept at the bottom.';

  @override
  String get yasalAdimRizaAciklama =>
      'Explicit consent to transferring your data abroad. Read it to the end and give your consent at the bottom.';

  @override
  String get yasalAdimKutuBaslik => 'Accept the Terms of Use';

  @override
  String yasalAdimGuncellendi(String belgeler) {
    return '$belgeler updated';
  }

  @override
  String yasalAdimListeVe(String onceki, String son) {
    return '$onceki and $son';
  }

  @override
  String get yasalAdimKosulGuncelAciklama =>
      'You can read the changes in the document; reading it is optional. Tick the box to continue.';

  @override
  String get yasalAdimBilgiGuncelAciklama =>
      'This is for your information; reading it is optional. Tick the box to confirm you have been informed.';

  @override
  String get yasalAdimOkuOnayla => 'Read and accept';

  @override
  String get yasalAdimOkunduOnaylandi => 'Read and accepted';

  @override
  String yasalAdimSemantik(int sira, int toplam, String ad, String durum) {
    return 'Step $sira of $toplam, $ad, $durum';
  }

  @override
  String get yasalAdimDurumTamam => 'completed';

  @override
  String get yasalAdimDurumBekliyor => 'waiting';

  @override
  String get yasalAdimDurumSonra => 'comes later';

  @override
  String yasalAdimDigerBelgeler(int sayi) {
    return 'Other documents (for information) · $sayi';
  }

  @override
  String yasalAdimSayac(int tamam, int toplam) {
    return '$tamam/$toplam steps completed';
  }

  @override
  String get yasalKapiBaslikGuncelTek => 'Updated document';

  @override
  String get streakTitle => 'Your saving streak';

  @override
  String streakMonths(String n) {
    return '$n months in a row';
  }

  @override
  String get streakRestarted => 'Streak started again';

  @override
  String get streakLongest => 'Longest streak';

  @override
  String streakMonthsValue(String n) {
    return '$n months';
  }

  @override
  String get streakPause => 'Pause';

  @override
  String get streakPauseAvailable => '1 month, available';

  @override
  String streakPauseUsed(String month) {
    return 'Used · available again in $month';
  }

  @override
  String get streakOpenMonth =>
      'No contribution yet this month; it stays open until month end.';

  @override
  String get streakExplain =>
      'Counts the months you added money to your portfolio. One empty month in any 12 does not break it.';

  @override
  String get streakBesIncluded => 'Automatic pension contributions included.';

  @override
  String get streakLegendSaving => 'saved';

  @override
  String get streakLegendPause => 'pause';

  @override
  String get streakLegendGap => 'gap';

  @override
  String get streakLegendOpen => 'this month';

  @override
  String streakStripSemantics(String total, String saved) {
    return 'Last $total months: $saved saving months';
  }

  @override
  String get savingReminderTitle => 'Payday reminder';

  @override
  String get savingReminderOff => 'Off';

  @override
  String savingReminderOn(String day) {
    return 'Day $day of the month, 10:30 · only if nothing added';
  }

  @override
  String get savingReminderSheetBody =>
      'On the day you pick, you get one reminder if you haven\'t added anything to your portfolio that month. If you have, nothing is sent. If the day doesn\'t exist that month (e.g. the 30th in February), it comes on the last day.';

  @override
  String savingReminderDay(String day) {
    return 'Day $day';
  }

  @override
  String get rdrKademeSakin => 'calm';

  @override
  String get rdrKademeHareketli => 'active';

  @override
  String get rdrKademeCok => 'very active';

  @override
  String get rdrHaftaSakin => 'Calm week';

  @override
  String get rdrHaftaHareketli => 'Active week';

  @override
  String get rdrHaftaCok => 'Very active week';

  @override
  String get rdrGunSakin => 'Calm day';

  @override
  String get rdrGunHareketli => 'Active day';

  @override
  String get rdrGunCok => 'Very active day';

  @override
  String rdrOlcekSemantics(String kademe) {
    return 'Compared with its own normal: $kademe';
  }

  @override
  String get rdrAyrinti => 'Details';

  @override
  String rdrKaynakSatiri(String kaynak, String tarih) {
    return '$kaynak · $tarih · not advice';
  }

  @override
  String rdrYasal(String kaynak) {
    return 'Data comes from $kaynak and does not show who bought or sold. Past movement does not indicate future returns; this is not investment advice.';
  }

  @override
  String get rdrNasilOkunur => 'How to read';

  @override
  String get rdrKoc1 =>
      'The sentence at the top tells you the latest in one line. The number under it is the evidence.';

  @override
  String get rdrKoc2 =>
      'The scale shows how big the number is compared with this asset\'s own normal: calm, active, very active.';

  @override
  String get rdrKoc3 => 'Tap any dotted-underlined word to see what it means.';

  @override
  String rdrKocAdim(String adim) {
    return '$adim / 3';
  }

  @override
  String get rdrIleri => 'Next';

  @override
  String get rdrAnladim => 'Got it';

  @override
  String get rdrTerimNetAkis => 'Net flow';

  @override
  String get rdrTerimNetAkisTanim =>
      'Money that came into the fund minus money that left. Changes in the fund\'s price are not included; only what investors put in and took out.';

  @override
  String get rdrTerimBuyukluk => 'Fund size';

  @override
  String get rdrTerimBuyuklukTanim =>
      'The current value of all money in the fund. It grows both when new money comes in and when its holdings gain value.';

  @override
  String get rdrTerimAyristirma => 'Price and new money';

  @override
  String get rdrTerimAyristirmaTanim =>
      'A change in fund size has two sources: the value of its holdings (price) and the money investors put in or took out (new money). Together they make up the size change.';

  @override
  String get rdrTerimYatirimci => 'Number of investors';

  @override
  String get rdrTerimYatirimciTanim =>
      'How many people hold units of the fund. The same amount can come from a few large investors or many small ones; this number shows which.';

  @override
  String get rdrTerimSira => 'Flow rank in category';

  @override
  String get rdrTerimSiraTanim =>
      'Funds in the same TEFAS category ranked from the largest net inflow to the largest net outflow in the same week. Only funds with data for every day of that week are ranked.';

  @override
  String get rdrTerimBuyukHareket => 'Big move';

  @override
  String get rdrTerimBuyukHareketTanim =>
      'A day when money in or out is at least 3% of fund size and at least 4 times the fund\'s usual daily move. Both must hold; funds under ₺250M and money market funds are never flagged.';

  @override
  String get rdrTerimOlcek => 'Scale';

  @override
  String get rdrTerimOlcekTanim =>
      'How big the number is against this asset\'s own history. For funds the last week is compared with the average of previous weeks; for stocks the last day\'s volume with the previous 20 days. For crypto it is how far the buyer share is from 50%: 2 points is active, 5 points very active. If a big move or unusual volume was flagged, the scale is at the top.';

  @override
  String get rdrTerimHacim => 'Trading value';

  @override
  String get rdrTerimHacimTanim =>
      'The total value of shares that changed hands that day. Every trade has a buyer and a seller; high volume alone does not mean money flowed in.';

  @override
  String get rdrTerimKat => 'Times the average';

  @override
  String get rdrTerimKatTanim =>
      'The last day\'s volume divided by the average of the previous 20 trading days. 1× is an ordinary day.';

  @override
  String get rdrTerimOlagandisi => 'Unusual volume';

  @override
  String get rdrTerimOlagandisiTanim =>
      'A day when volume is at least twice the 20-day average and the jump is far outside the asset\'s usual swings.';

  @override
  String get rdrTerimAliciPayi => 'Buyer share';

  @override
  String get rdrTerimAliciPayiTanim =>
      'How much of the volume came from people who wanted to buy right away (market buy orders). Above 50% buyers were more eager, below 50% sellers. It is not a measure of money inflow. Over several days it is volume weighted: a busier day counts more.';

  @override
  String get rdrTerimNetAlim => 'Net buying';

  @override
  String get rdrTerimNetAlimTanim =>
      'Market-buy volume minus market-sell volume (USDT). Covers Binance trades only.';

  @override
  String rdrTerimOrnek(String deger) {
    return 'For this asset: $deger';
  }

  @override
  String get rdrFonGirisSakin =>
      'The fund had a normal amount of money come in last week.';

  @override
  String get rdrFonGirisHareketli =>
      'More money than usual came into the fund last week.';

  @override
  String get rdrFonGirisCok =>
      'Far more money than usual came into the fund last week.';

  @override
  String get rdrFonCikisSakin =>
      'A normal amount of money left the fund last week.';

  @override
  String get rdrFonCikisHareketli =>
      'More money than usual left the fund last week.';

  @override
  String get rdrFonCikisCok =>
      'Far more money than usual left the fund last week.';

  @override
  String get rdrFonGiris => 'Money came into the fund last week.';

  @override
  String get rdrFonCikis => 'Money left the fund last week.';

  @override
  String get rdrFonDenge =>
      'Money in and out of the fund balanced out last week.';

  @override
  String get rdrFonKarisik => 'The fund had a big money move last week.';

  @override
  String rdrFonNetAralik(String aralik) {
    return 'net flow · $aralik';
  }

  @override
  String get rdrSon8Hafta => 'last 8 weeks';

  @override
  String rdrBuyukHareketSayisi(String sayi) {
    return '$sayi big move(s)';
  }

  @override
  String get rdrBuyukHareketYok => 'no big moves';

  @override
  String rdrFonDetayBaslik(String kod) {
    return '$kod · Money flow';
  }

  @override
  String get rdrHaftayaDokun => 'Tap a week to see its number here.';

  @override
  String rdrSecilenHafta(String aralik) {
    return 'Week of $aralik';
  }

  @override
  String get rdrVeriYok => 'no data';

  @override
  String rdrAyristirmaCumle(String yuzde) {
    return 'Over the last month the fund size changed $yuzde.';
  }

  @override
  String rdrFiyat(String yuzde) {
    return 'price $yuzde';
  }

  @override
  String rdrYeniPara(String yuzde) {
    return 'new money $yuzde';
  }

  @override
  String rdrOlaganinKati(String kat) {
    return '$kat× a usual week';
  }

  @override
  String get rdrDonemUpper => 'PERIOD';

  @override
  String get rdrBaglamUpper => 'CONTEXT';

  @override
  String get rdrSiraUpper => 'FLOW RANK IN CATEGORY';

  @override
  String rdrSiraAlt(String kategori) {
    return '$kategori · ranked by net flow the same week';
  }

  @override
  String get rdrSiraBuFon => 'this fund';

  @override
  String rdrSiraToplam(String sayi) {
    return 'out of $sayi funds';
  }

  @override
  String get rdrHareketlerUpper => 'BIG MOVES · LAST 30 DAYS';

  @override
  String rdrHisseSakin(String tarih) {
    return 'On $tarih this stock traded a normal amount.';
  }

  @override
  String rdrHisseHareketli(String tarih) {
    return 'On $tarih this stock traded more than usual.';
  }

  @override
  String rdrHisseCok(String tarih) {
    return 'On $tarih this stock traded far more than usual.';
  }

  @override
  String rdrHisseYalin(String tarih, String tutar) {
    return 'On $tarih this stock traded $tutar.';
  }

  @override
  String rdrHacimAlt(String yuzde) {
    return 'trading value · price $yuzde';
  }

  @override
  String get rdrHacimAltFiyatsiz => 'trading value';

  @override
  String get rdrOrtalamaCizgisi => 'dashed line: previous 20-day average';

  @override
  String rdrHacimDetayBaslik(String kod) {
    return '$kod · Volume radar';
  }

  @override
  String get rdrGuneDokun => 'Tap a day to see its volume and price here.';

  @override
  String rdrSecilenGun(String tarih, String tutar, String yuzde) {
    return '$tarih: $tutar · price $yuzde';
  }

  @override
  String rdrSecilenGunFiyatsiz(String tarih, String tutar) {
    return '$tarih: $tutar';
  }

  @override
  String get rdrOlagandisiUpper => 'UNUSUAL VOLUME DAYS · LAST 30 DAYS';

  @override
  String rdrKriptoAlici(String tarih) {
    return 'On $tarih buyers were more eager than sellers.';
  }

  @override
  String rdrKriptoAliciCok(String tarih) {
    return 'On $tarih buyers were clearly more eager than sellers.';
  }

  @override
  String rdrKriptoSatici(String tarih) {
    return 'On $tarih sellers were more eager than buyers.';
  }

  @override
  String rdrKriptoSaticiCok(String tarih) {
    return 'On $tarih sellers were clearly more eager than buyers.';
  }

  @override
  String rdrKriptoDenge(String tarih) {
    return 'On $tarih buyers and sellers were balanced.';
  }

  @override
  String rdrAlici(String yuzde) {
    return 'Buyers $yuzde';
  }

  @override
  String rdrSatici(String yuzde) {
    return 'Sellers $yuzde';
  }

  @override
  String rdrYediGunOrt(String yuzde) {
    return 'Buyer share over 7 days: $yuzde';
  }

  @override
  String get rdrSaatlikUpper => 'LAST 24 HOURS · NET BUYING BY HOUR';

  @override
  String rdrEnIstekliSaat(String aralik, String tutar) {
    return '$aralik buyers were most eager · $tutar net buying';
  }

  @override
  String get rdrIstekliSaatYok =>
      'Buyers did not outweigh sellers in any hour of the last 24.';

  @override
  String rdrSonMum(String saat) {
    return 'last candle $saat';
  }

  @override
  String rdrKriptoDetayBaslik(String kod) {
    return '$kod · Buying pressure';
  }

  @override
  String get rdrIslemHacmiUpper => 'TRADING VOLUME · LAST 20 DAYS';

  @override
  String rdrHaftaBaslikVar(String sayi) {
    return '$sayi of your assets had unusual moves in the last week.';
  }

  @override
  String get rdrHaftaBaslikYok =>
      'None of your assets had unusual moves in the last week.';

  @override
  String get rdrRozetBuyukGiris => 'Big inflow';

  @override
  String get rdrRozetBuyukCikis => 'Big outflow';

  @override
  String get rdrRozetHacim => 'Unusual volume';

  @override
  String get rdrRozetAlici => 'Buyers eager';

  @override
  String get rdrRozetSatici => 'Sellers eager';

  @override
  String get rdrRozetHareketli => 'Active';

  @override
  String get rdrRozetSakin => 'Calm';

  @override
  String rdrSatirFon(String tutar, String yuzde) {
    return 'Net $tutar · $yuzde of size';
  }

  @override
  String rdrSatirFonOransiz(String tutar) {
    return 'Net $tutar';
  }

  @override
  String rdrSatirHacim(String tarih, String kat, String yuzde) {
    return '$tarih · volume $kat× · price $yuzde';
  }

  @override
  String rdrSatirKripto(String ort, String yuzde) {
    return 'Buyer share over 7 days $ort · last day $yuzde';
  }

  @override
  String rdrYatirimciHafta(String sayi, String fark) {
    return '$sayi · last week $fark';
  }

  @override
  String rdrKartHaftaOlayi(String olay) {
    return 'Unusual day in the last 7 days: $olay';
  }

  @override
  String rdrDunAralik(String aralik) {
    return 'Yesterday $aralik';
  }

  @override
  String get rdrSaateDokun =>
      'Tap an hour to see its net buying and buyer share here.';

  @override
  String get anzYararli => 'Helpful';

  @override
  String get anzYararsiz => 'Not helpful';

  @override
  String rdrSatirKriptoOrtsuz(String yuzde) {
    return 'Buyer share on the last day $yuzde';
  }

  @override
  String rdrSatirNot(String metin) {
    return 'Note: $metin';
  }

  @override
  String get rdrHaftaKaynak =>
      'Fund flow TEFAS · volume Yahoo Finance · crypto Binance · not advice';

  @override
  String rdrAylikRaporSatir(String ay) {
    return '$ay report';
  }

  @override
  String get rdrOku => 'Read';

  @override
  String rdrSeritSayi(String sayi) {
    return '$sayi of your assets had unusual moves in the last week';
  }

  @override
  String get rdrAyarHareketSatiri => 'Movement line in the Monday summary';

  @override
  String get rdrAyarHareketSatiriAlt =>
      'Include big fund flows and unusual volume in the weekly notification.';

  @override
  String get rdrAyarSakinGoster => 'Show calm assets in the summary';

  @override
  String get rdrAyarSakinGosterAlt => 'Also list assets that had a quiet week.';

  @override
  String get prmUcretsiz => 'Free';

  @override
  String get prmPremium => 'Premium';

  @override
  String get prmSatirVarlik => 'Assets';

  @override
  String get prmSatirAkis => 'Money flow';

  @override
  String get prmSatirHacim => 'Volume radar';

  @override
  String get prmSatirNot => 'Weekly note';

  @override
  String get prmSatirAylik => 'Monthly report';

  @override
  String get prmSinirsiz => 'unlimited';

  @override
  String get prmSatirSinyal => 'Signal alerts';

  @override
  String get prmSinyalUcretsiz => '1 asset';

  @override
  String get prmSinyalPremium => 'all assets';

  @override
  String get prmSatirTakip => 'Watchlist';

  @override
  String prmYillikTasarruf(String oran) {
    return 'Save $oran%';
  }

  @override
  String get prmVarErisim => 'Included';

  @override
  String get prmYokErisim => 'Not included';

  @override
  String get prmAkisUcretsiz => 'last week';

  @override
  String get prmAkisPremium => '8 weeks + events';

  @override
  String get prmHacimUcretsiz => 'last day';

  @override
  String get prmHacimPremium => '20 days';

  @override
  String get prmNotUcretsiz => 'first sentence';

  @override
  String get prmNotPremium => 'full note';

  @override
  String prmKilitAkis(String sayi) {
    return '8-week trend and $sayi big move(s) in Premium';
  }

  @override
  String get prmKilitAyrinti => 'Details in Premium';

  @override
  String get prmKilitNot => 'Full note in Premium';

  @override
  String get prmKilitEkstreAi => 'AI mapping is in Premium';

  @override
  String get prmSatirEkstreAi => 'Read statements with AI';

  @override
  String get prmHediyeBaslik => 'You\'re one of our first users';

  @override
  String prmHediyeGovde(String gun, String tarih) {
    return '$gun days of Premium are yours, no card needed. It ends on $tarih; none of your data is deleted when it does.';
  }

  @override
  String get prmTesekkurler => 'Thanks';

  @override
  String get prmAbonelikAylik => 'Premium · monthly';

  @override
  String get prmAbonelikYillik => 'Premium · yearly';

  @override
  String get prmAbonelikHediye => 'Premium · early-user gift';

  @override
  String prmYenileme(String tarih, String magaza) {
    return 'Renews $tarih · $magaza';
  }

  @override
  String prmBitis(String tarih) {
    return 'Ends on $tarih';
  }

  @override
  String get prmYonet => 'Manage';

  @override
  String get prmGeriYukle => 'Restore purchases';

  @override
  String get anzNotUpper => 'WEEKLY NOTE · AI';

  @override
  String anzMeta(String sayi, String aralik) {
    return '$sayi points · $aralik';
  }

  @override
  String get anzNotuOku => 'Read note';

  @override
  String anzDetayBaslik(String kod) {
    return '$kod · weekly note';
  }

  @override
  String anzAylikDetayBaslik(String kod) {
    return '$kod · monthly note';
  }

  @override
  String anzAltSatir(String kaynak, String tarih) {
    return 'Written with AI · input $kaynak, $tarih · not investment advice';
  }

  @override
  String get anzIseYaradi => 'Was this useful?';

  @override
  String get anzYanlisSayi => 'I saw a wrong number';

  @override
  String get anzYanlisIpucu => 'Which number is wrong? (optional)';

  @override
  String get anzGonder => 'Send';

  @override
  String get anzTesekkur => 'Thanks, we\'ll review the note.';

  @override
  String get anzAylikUpper => 'MONTHLY REPORT';

  @override
  String anzAylikBaslik(String ay) {
    return '$ay report';
  }

  @override
  String anzAylikOzetVar(String toplam, String sayi) {
    return '$sayi of the $toplam assets with a note had a notable month.';
  }

  @override
  String anzAylikEksik(String kodlar) {
    return 'No note this month for $kodlar; their numbers are on their own pages.';
  }

  @override
  String get anzAylikOzetYok => 'None of your assets had a notable month.';

  @override
  String get anzAylikBos => 'This month\'s report is not ready yet.';

  @override
  String get anzOkunamadi => 'The note could not be opened right now.';

  @override
  String get sgnPremiumAktif => 'Premium indicators on';

  @override
  String get sgnPremiumAktifGovde =>
      'ADX, Williams %R and CCI are part of the signal analysis.';

  @override
  String get sgnPremiumKilitBaslik => 'Premium indicators';

  @override
  String get sgnPremiumKilitGovde =>
      'With Premium, ADX, Williams %R and CCI join the signal analysis.';

  @override
  String get sgnPremiumGec => 'Go Premium';

  @override
  String get pwOzSinirsiz => 'Unlimited assets of every type';

  @override
  String get pwOzGosterge => 'ADX, Williams %R and CCI in signal analysis';

  @override
  String get pwOzSiklik =>
      'Signal alerts for all your assets, at the frequency you choose';

  @override
  String get pwOzKarsilastir => 'Up to 5 series in Compare';

  @override
  String get pwOzOrtak => 'Share your portfolio with more than one partner';

  @override
  String get sgnSlotNotu =>
      'On the free plan signal alerts cover one asset, once a day per type; you pick the asset on its screen. Premium covers all your assets at the frequency you choose.';

  @override
  String get sgnVarlikAcik =>
      'Signal alerts are on for this asset. The free plan covers one asset.';

  @override
  String sgnVarlikKilit(String ad) {
    return 'On the free plan signal alerts cover one asset: $ad. Premium covers all your assets.';
  }

  @override
  String get sgnVarlikTasi => 'Move signals here';

  @override
  String sgnSlotKilitli(String secenek) {
    return '$secenek, Premium';
  }

  @override
  String get cmpSinirPremium => 'Up to 5 series with Premium';

  @override
  String get cmpSinirDolu => 'At most 5 assets';

  @override
  String get pwOzRadar =>
      'Full money-flow and volume-radar detail, the whole weekly note';

  @override
  String pwFiyatAylik(String fiyat) {
    return '$fiyat/mo';
  }

  @override
  String pwFiyatYillik(String fiyat) {
    return '$fiyat/yr';
  }

  @override
  String pwDenemeAltyazi(int gun) {
    return '$gun days free, then renews automatically';
  }

  @override
  String get pwYenilenirAltyazi => 'Renews automatically, cancel anytime';

  @override
  String pwDenemeDugme(int gun) {
    return 'Try $gun days free';
  }

  @override
  String get pwAboneOl => 'Subscribe';

  @override
  String get pwKosulAndroid =>
      'Payment is charged to your Google Play account. The subscription renews automatically for the same period and price unless cancelled before the period ends. Manage or cancel it under Google Play › Payments & subscriptions › Subscriptions.';

  @override
  String pwDenemeKosul(int gun) {
    return 'Unless you cancel before the $gun-day free trial ends, you are charged when it ends.';
  }

  @override
  String get pwKullanilamaz =>
      'Purchases are not available right now. Please try again shortly.';

  @override
  String get pwBeklemede =>
      'Your payment is pending. Premium turns on by itself once it is approved.';

  @override
  String get pwHata =>
      'The purchase could not be completed. If you were not charged, you can try again.';

  @override
  String get pwGeriYuklendi => 'Your subscription has been restored.';

  @override
  String get pwGeriYukBulunamadi =>
      'No active subscription was found for this account.';

  @override
  String get pwGeriYukHata =>
      'Restore is not possible right now. Please try again shortly.';

  @override
  String get assetTypeEurobond => 'Eurobond';

  @override
  String get tickerHintEurobond =>
      'Pick from the list or type an ISIN, e.g. US900123DF45';

  @override
  String get stockMarketBist => 'BIST';

  @override
  String get stockMarketUs => 'US';

  @override
  String stockMarketSemantics(String market) {
    return 'Stock market: $market';
  }

  @override
  String get usStocks => 'US Stocks';

  @override
  String get pickUsStock => 'Pick a US stock';

  @override
  String get pickUsStockTap => 'Tap to pick a US stock...';

  @override
  String get usSymbolHint => 'Type a symbol (e.g. AAPL, BRK-B)';

  @override
  String selectedUsStockSemantics(String name) {
    return 'Selected US stock: $name. Double tap to change.';
  }

  @override
  String get usStockCurrencyLocked => 'US stocks are recorded in dollars';

  @override
  String get costsUpper => 'COSTS';

  @override
  String get costsPaid => 'Paid';

  @override
  String get costsEstimatedOnSale => 'Estimated on sale';

  @override
  String get costTagPaid => 'Paid';

  @override
  String get costTagEstimated => 'Estimated';

  @override
  String get costTagInfo => 'Info';

  @override
  String costsShowAll(int count) {
    return 'Show all ($count)';
  }

  @override
  String get costsShowLess => 'Show less';

  @override
  String get identityEurobond => 'Bond';

  @override
  String get pickEurobondTap => 'Tap to pick a bond';

  @override
  String get pickEurobondPrompt => 'Pick a eurobond';

  @override
  String eurobondSelectedSemantics(String name) {
    return 'Selected bond: $name. Double tap to change.';
  }

  @override
  String get eurobondPickerTitle => 'Eurobonds';

  @override
  String get eurobondLoading => 'Loading bonds';

  @override
  String get eurobondLoadFailed => 'Couldn\'t load the bond list';

  @override
  String get eurobondSourceNote =>
      'USD bonds only for now. Prices are clean, as a percentage of nominal. Not investment advice.';

  @override
  String eurobondMaturityShort(String date) {
    return 'Matures $date';
  }

  @override
  String eurobondYieldShort(String pct) {
    return 'Yield $pct';
  }

  @override
  String get eurobondIsinInvalid =>
      'This ISIN is invalid: the check digit doesn\'t match. A digit may be mistyped.';

  @override
  String get eurobondIsinNotListed =>
      'This ISIN isn\'t in the list. For now you can only add the USD bonds listed here.';

  @override
  String get eurobondCleanPrice => 'Clean price (%)';

  @override
  String get eurobondCleanPriceRequired => 'Enter the clean price';

  @override
  String get eurobondCurrencyLocked => 'The bond\'s currency';

  @override
  String eurobondAccruedLine(String accrued, String paid) {
    return 'Accrued interest: $accrued · Paid: $paid';
  }

  @override
  String eurobondAccruedOnly(String accrued) {
    return 'Accrued interest: $accrued';
  }

  @override
  String eurobondTotalBreakdown(String nominal, String dirty) {
    return '$nominal nominal × dirty $dirty';
  }

  @override
  String get bondInfoUpper => 'BOND DETAILS';

  @override
  String get bondCleanPrice => 'Clean price';

  @override
  String get bondAccrued => 'Accrued interest';

  @override
  String get bondDirtyPrice => 'Dirty price';

  @override
  String get bondPerNominalNote => 'Prices per 100 nominal.';

  @override
  String get bondYtm => 'Yield to maturity';

  @override
  String get bondCoupon => 'Coupon';

  @override
  String bondCouponValue(String rate, String count) {
    return '$rate · $count× a year';
  }

  @override
  String get bondNextCoupon => 'Next coupon';

  @override
  String bondNextCouponValue(String date, String amount) {
    return '$date · $amount';
  }

  @override
  String bondWithholding(String rate) {
    return 'Withholding $rate';
  }

  @override
  String get bondMaturity => 'Maturity';

  @override
  String bondMaturityValue(String date, String days) {
    return '$date · $days days left';
  }

  @override
  String get bondIssuer => 'Issuer';

  @override
  String get bondIssuerTreasury => 'Turkish Treasury';

  @override
  String get bondIssuerCorporate => 'Corporate';

  @override
  String get bondBankSellUpper => 'IF YOU SELL TO THE BANK';

  @override
  String get bondBankZiraat => 'Ziraat Bankası';

  @override
  String bondBankUpdated(String bank, String time) {
    return '$bank · $time';
  }

  @override
  String get bondBankBid => 'Bank bid';

  @override
  String get bondBankAsk => 'Bank ask';

  @override
  String get bondBankSpread => 'Spread';

  @override
  String get bondBankProceeds => 'What you\'d get selling today';

  @override
  String get bondBankNote =>
      'Bank prices are dirty prices (accrued interest included).';

  @override
  String typePickerSearchHint(String examples) {
    return 'Search: $examples…';
  }

  @override
  String get typePickerGroupMarkets => 'Stocks and funds';

  @override
  String get typePickerGroupFxPrecious => 'FX and precious';

  @override
  String get typePickerGroupSavings => 'Savings';

  @override
  String get typePickerUsStock => 'US stock';

  @override
  String get typePickerChange => 'Change';

  @override
  String get typePickerChangeSemantics => 'Change asset type';

  @override
  String get typePickerHintBistOpen => 'BIST open';

  @override
  String get typePickerHintBistClosed => 'BIST closed';

  @override
  String get typePickerHint247 => '24/7';

  @override
  String get s7AraSemantics => 'Search';

  @override
  String get s7AramaIpucu => 'Search assets, symbols or actions';

  @override
  String get s7VarliklarimUpper => 'MY ASSETS';

  @override
  String get s7PiyasaUpper => 'MARKET';

  @override
  String get s7EylemlerUpper => 'ACTIONS';

  @override
  String get s7EylemFiyatAlarmlari => 'Price alerts';

  @override
  String get s7EylemSinyalAyarlari => 'Signal settings';

  @override
  String get s7EylemEkstreAktar => 'Import statement (CSV)';

  @override
  String get s7EylemTopluEkle => 'Bulk add';

  @override
  String get s7EylemTumHareketler => 'All transactions';

  @override
  String get s7EylemKarsilastir => 'Compare';

  @override
  String get s7EylemTakipListesi => 'Add to watchlist';

  @override
  String get s7EylemBildirimler => 'Notifications';

  @override
  String get s7EylemAyarlar => 'Settings';

  @override
  String get s4AnalysisUpper => 'ANALYSIS';

  @override
  String get s4HistoryDocsUpper => 'HISTORY & DOCUMENTS';

  @override
  String get s4Details => 'Details';

  @override
  String get s4RowSignals => 'Technical signals';

  @override
  String get s4RowFundReport => 'Fund report card';

  @override
  String get s4RowFlow => 'Money flow';

  @override
  String get s4RowVolume => 'Volume radar';

  @override
  String get s4RowCrypto => 'Buyer pressure';

  @override
  String get s4RowNote => 'Analysis note';

  @override
  String get s3DagilimBaslik => 'Allocation';

  @override
  String get s3HalkayiAc => 'Open allocation as a large ring';

  @override
  String s3DigerTurler(int n) {
    return '+$n more';
  }

  @override
  String get s5OnAyarSoru => 'How often should we notify you?';

  @override
  String get s5OnAyarAz => 'Less';

  @override
  String get s5OnAyarDengeli => 'Balanced';

  @override
  String get s5OnAyarCok => 'More';

  @override
  String get s5OnAyarOzel => 'Custom';

  @override
  String get s5OnAyarAzAciklama =>
      'Only strong signals (85% confidence), once a day, with RSI and MACD.';

  @override
  String get s5OnAyarDengeliAciklama =>
      'Recommended: 70% confidence, twice a day (11:00 and 15:00), all core indicators.';

  @override
  String get s5OnAyarCokAciklama =>
      'From 50% confidence, every 2 hours, all core indicators.';

  @override
  String get s5OnAyarOzelAciklama =>
      'Your categories have their own settings. Picking an option applies it to every category.';

  @override
  String get s5KategoriyeGoreOzellestir => 'Customise by category';

  @override
  String get s2Filtre => 'Filter';

  @override
  String s2FiltreSayili(int n) {
    return 'Filter · $n';
  }

  @override
  String s2FiltreEtkin(int n) {
    return 'Filter, $n active';
  }

  @override
  String get s2FiltreKisi => 'Person';

  @override
  String get s2FiltreKategori => 'Category';

  @override
  String s2BakiyeArttiAlim(String tutar, String alim) {
    return 'Balance up $tutar; $alim of that is new buys.';
  }

  @override
  String s2BakiyeAzaldiAlim(String tutar, String alim) {
    return 'Balance down $tutar; you bought $alim in the period.';
  }

  @override
  String s2BakiyeArttiSatis(String tutar, String satis) {
    return 'Balance up $tutar; you sold $satis in the period.';
  }

  @override
  String s2BakiyeAzaldiSatis(String tutar, String satis) {
    return 'Balance down $tutar; $satis of that is sales.';
  }

  @override
  String get s6Raporlar => 'Reports';

  @override
  String get s6HaftaOzetiAlt =>
      'What happened in your funds and stocks this week';

  @override
  String get s6AylikRapor => 'Monthly report';

  @override
  String get s6YilOzeti => 'Year in review';

  @override
  String get s6Siralama => 'Leaderboard';

  @override
  String get s6SiralamaAlt => 'Top portfolios and the race with your partners';

  @override
  String get pwdSlogan => 'Open up your sandık.';

  @override
  String get pwdOnceki => 'Previous feature';

  @override
  String get pwdSonraki => 'Next feature';

  @override
  String get pwdIpucu =>
      'Swipe left or right to see the other Premium features';

  @override
  String pwdUcretsiz(String deger) {
    return 'Free: $deger';
  }

  @override
  String pwdPremium(String deger) {
    return 'Premium: $deger';
  }

  @override
  String get pwdVarlikEtiket => 'ASSET LIMIT';

  @override
  String pwdVarlikBaslik(int sayi) {
    return '$sayi assets are free. The rest is Premium.';
  }

  @override
  String get pwdVarlikCubuk => 'Free limit';

  @override
  String pwdVarlikUcretsiz(int varlik, int takip) {
    return '$varlik assets, $takip watchlist';
  }

  @override
  String get pwdSinyalEtiket => 'SIGNALS';

  @override
  String get pwdSinyalBaslik =>
      'Get alerts at the hours you pick, plus three more indicators.';

  @override
  String pwdSinyalUcretsiz(int sayi) {
    return '$sayi a day';
  }

  @override
  String pwdSinyalUcretsizTek(int sayi) {
    return '$sayi a day, one asset';
  }

  @override
  String get pwdSinyalPremium => 'any frequency';

  @override
  String get pwdKarsEtiket => 'COMPARE';

  @override
  String pwdKarsRozet(int ucretsiz, int premium) {
    return '$ucretsiz → $premium series';
  }

  @override
  String get pwdKarsBaslik =>
      'See your portfolio next to gold, the dollar and the index.';

  @override
  String pwdSeri(int sayi) {
    return '$sayi series';
  }

  @override
  String get pwdOrtakEtiket => 'PARTNERS';

  @override
  String get pwdOrtakBaslik =>
      'Your spouse, family and partners, more than one.';

  @override
  String pwdOrtakSayi(int sayi) {
    String _temp0 = intl.Intl.pluralLogic(
      sayi,
      locale: localeName,
      other: '$sayi partners',
      one: '1 partner',
    );
    return '$_temp0';
  }

  @override
  String get pwdAkisEtiket => 'FUND FLOW';

  @override
  String get pwdAkisBaslik => 'Is money flowing into your fund? See 8 weeks.';

  @override
  String get pwdHacimEtiket => 'VOLUME RADAR';

  @override
  String get pwdHacimBaslik =>
      'Is today\'s volume unusual? Compare with 20 days.';

  @override
  String get pwdNotEtiket => 'WEEKLY NOTE';

  @override
  String get pwdNotBaslik => 'The rest of your weekly note is Premium.';

  @override
  String get pwdNotIlk =>
      'Money kept flowing into the funds in your portfolio this week.';

  @override
  String get pwdNotDevam =>
      ' Which one stood out and what that tells you becomes readable in the rest of the note…';

  @override
  String get pwdEkstreEtiket => 'STATEMENT';

  @override
  String get pwdEkstreBaslik =>
      'Upload your statement and let AI match the lines.';

  @override
  String get pwdEkstrePremium => 'AI matching';

  @override
  String pwdYillikAlt(String aylik) {
    return 'Billed once a year · $aylik a month';
  }

  @override
  String get pwdYillikAltSade => 'Billed once a year';

  @override
  String pwdYillikDenemeAlt(int gun, String fiyat) {
    return '$gun days free, then $fiyat once a year';
  }

  @override
  String get pwdAylikAlt => 'Renews monthly, stop in any month';

  @override
  String pwdAylikDenemeAlt(int gun, String fiyat) {
    return '$gun days free, then $fiyat a month';
  }

  @override
  String get pwdBugun => 'Today';

  @override
  String get pwdHerSeyAcik => 'Everything unlocked';

  @override
  String pwdGun(int gun) {
    return 'Day $gun';
  }

  @override
  String get pwdIlkOdeme => 'First payment';

  @override
  String get pwdGuvenTakip => 'Portfolio tracking stays free';

  @override
  String get pwdGuvenIptal => 'Cancel anytime, access until the period ends';

  @override
  String get pwdYillikAboneOl => 'Subscribe yearly';

  @override
  String get pwdAylikAboneOl => 'Subscribe monthly';
}
