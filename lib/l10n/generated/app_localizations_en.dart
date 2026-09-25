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
      'Biometric lock, download your data, delete account';

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
  String get levelBeginnerDesc =>
      'Simple view: technical signals, percentile, health and XIRR cards are hidden.';

  @override
  String get levelIntermediateDesc =>
      'Today\'s view: technical signals, percentile, health card and money-weighted return (XIRR).';

  @override
  String get levelAdvancedDesc =>
      'Intermediate + risk-adjusted return, timing effect and recovery (Summary › 1Y).';

  @override
  String get noAssetsYet => 'No assets added yet';

  @override
  String get noAssetsOfType => 'No assets of this type';

  @override
  String get noAssetsYetHint =>
      'Start building your sandık by adding your first asset.';

  @override
  String get noAssetsOfTypeHint =>
      'Change the filter or add an asset of this type.';

  @override
  String get addFirstAsset => 'Add Your First Asset';

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
      'Prices could not be updated — showing older data.';

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
  String get termsMustAccept => 'You must accept the legal terms.';

  @override
  String get consentMustAccept =>
      'You must give explicit consent to the cross-border data transfer.';

  @override
  String get refreshPrices => 'Refresh prices';

  @override
  String get assetAllocation => 'ASSET ALLOCATION';

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
    return '$count active price alerts';
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
    return '$buys buys · $sells removals';
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
  String get tickerHintCrypto => 'e.g. BTC, ETH — pick from the list';

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
      'Company name (optional — fetched from the symbol)';

  @override
  String goldSemantics(String kind) {
    return '$kind gold';
  }

  @override
  String get commissionNote =>
      'Trading commission is added to your cost — profit/loss shows the real figure.';

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
  String quantitySemantics(String value) {
    return 'Quantity $value';
  }

  @override
  String get quickEntryTitle => 'Quick Entry';

  @override
  String get quickEntryHelp =>
      'One asset per line. Price is optional — leave it blank and the current price is fetched.\ne.g.  100 dollars  /  10 grams gold 4500 lira  /  GARAN 500 units';

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
  String get fundsLoadFailed => 'Could not load funds';

  @override
  String get searchEllipsis => 'Search...';

  @override
  String get clearSearch => 'Clear search';

  @override
  String get pickStockPrompt => 'Please pick a stock';

  @override
  String get pickStock => 'Pick a stock';

  @override
  String get pickStockTap => 'Tap to pick a stock...';

  @override
  String get pickFundPrompt => 'Please pick a fund';

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
  String get totalQuantityUpper => 'TOTAL QUANTITY';

  @override
  String get otherTab => 'Other';

  @override
  String periodChangeUpper(String period) {
    return '$period CHANGE';
  }

  @override
  String buyPerUnit(String unit) {
    return 'BUY / $unit';
  }

  @override
  String todayPerUnit(String unit) {
    return 'TODAY / $unit';
  }

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
      'This CANNOT be undone.\n\nAll your portfolio records, performance history and partner links will be permanently deleted within 30 days.\n\nDo you want to continue?';

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
      'BIST is closed on weekends; the banner shows the last close labelled \"Market closed\".';

  @override
  String get showAmounts => 'Show amounts';

  @override
  String get showAmountsSubtitle =>
      'When off, only the daily percentage and chart are shown. The lock screen is visible without unlocking your phone, so this is off by default.';

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
    return 'Too many attempts — you can try again in $wait.';
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
  String get premiumPitch =>
      'Unlimited assets, premium indicators, 2 signal analyses a day';

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
    return 'You are now partners with $name!';
  }

  @override
  String get requestRejected => 'The partner request was rejected.';

  @override
  String get requestCancelled => 'The partner request was cancelled.';

  @override
  String get partnershipAccepted => 'Partnership accepted!';

  @override
  String get sendingEllipsis => 'Sending...';

  @override
  String waitFor(String wait) {
    return 'Wait — $wait';
  }

  @override
  String get requestPartnership => 'Request Partnership';

  @override
  String get generatingEllipsis => 'Generating...';

  @override
  String get generateCode => 'Generate Code';

  @override
  String get switchToDark => 'Switch to dark theme';

  @override
  String get switchToLight => 'Switch to light theme';

  @override
  String get tabChart => 'Chart';

  @override
  String get tabSummary => 'Summary';

  @override
  String get modeReal => 'Actual';

  @override
  String get modeSim => 'Simulation';

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
  String noHistoryTypeBody(String type) {
    return 'Price history is not tracked for $type. Its value counts in the portfolio total, but no time chart can be drawn.';
  }

  @override
  String get simModeTitle => 'Simulation Mode';

  @override
  String get realModeTitle => 'Actual Mode';

  @override
  String get simModeBody =>
      'How the chart would look if you had held today\'s net portfolio for the whole period — it ignores past buy/sell decisions and shows only the price change of your current position.';

  @override
  String get realModeBody =>
      'Each day\'s value is computed from the net quantity you held that day. Tap a point to see that day\'s portfolio value and any buy / sell amounts — so you can see exactly why the chart rose or fell.';

  @override
  String get portfolioPerformance => 'Portfolio Performance';

  @override
  String get chartDataFailed => 'Could not load chart data';

  @override
  String get chartDataFailedBody =>
      'Price history could not be fetched. Check your connection and try again.';

  @override
  String intradayMissingBody(String names) {
    return 'Intraday prices could not be fetched for $names. These assets are drawn FLAT at their last known price — a flat line does not mean the market was quiet.';
  }

  @override
  String get retryLower => 'Try again';

  @override
  String get raceUpper => 'RACE';

  @override
  String get changeByTypeUpper => 'CHANGE BY TYPE';

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
  String get tradeVolumeUpper => 'TRADE VOLUME';

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
  String periodMarketReturn(String period) {
    return '$period market return';
  }

  @override
  String get whereItCameFrom => 'Where it came from';

  @override
  String get periodStart => 'Period start';

  @override
  String get yourContribution => 'Your contribution';

  @override
  String get marketWord => 'Market';

  @override
  String get cashDividend => 'Cash dividends within it';

  @override
  String get commissionPaid => 'Commission paid';

  @override
  String get contributionNotReturn =>
      'The blue bar is your own money — it is not a return. The percentage comes only from the market bar.';

  @override
  String get periodCourse => 'Course over the period';

  @override
  String greenDaysOfTotal(int total, int up) {
    return '$up of $total trading days closed up.';
  }

  @override
  String get againstInflation => 'Against inflation';

  @override
  String realReturnPeriod(String period) {
    return 'Real return · $period';
  }

  @override
  String get nominalReturn => 'Your return';

  @override
  String cpiWindowRange(String start, String end) {
    return 'Measured: $start – $end';
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
      'This is how much your portfolio value swung on average over the year. High is neither good nor bad — it just means bigger ups and downs.';

  @override
  String get concentration => 'Concentration';

  @override
  String get moneyReturnAnnual => 'Return on your money (annual)';

  @override
  String get xirrBody =>
      'The annual compound return of the money you invested, taking the DATES of your investments into account.';

  @override
  String get periodMarketReturnLabel => 'Period market return';

  @override
  String get xirrVsMarketBody =>
      'The two numbers do not contradict: the top one also accounts for when you bought, the bottom one measures only the market\'s move.';

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
    return 'In the daily view the $name line shows your real value — the same as the daily chart on the Performance screen.';
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
      'Portfolios are computed series — they are not quoted on any market. Their returns are drawn as a percentage from the start of the period, just like an asset.';

  @override
  String get portfolioActivityTitle => 'Portfolio Activity';

  @override
  String get clearFilters => 'Clear filters';

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
  String get selectedPeriodReturn => 'Return for the selected period';

  @override
  String get depositsDontChangeRank => 'Deposits don\'t change the ranking';

  @override
  String get everyoneMeasuredSame => 'Everyone is measured the same way';

  @override
  String get rankVsPortfolioNote =>
      'This number can DIFFER from the profit/loss percentage on the Portfolio screen — that one shows total profit/loss since your first purchase, this one only what happened in the period you picked.';

  @override
  String get rankSwapNote =>
      'If you sold an asset entirely and bought another during the period, the result shows the \"as if you had held the new asset from the start\" scenario. Portfolios without price history are excluded from the ranking.';

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
      'No one\'s asset list is shared — only return percentages are ranked.';

  @override
  String get yourReturnUpper => 'YOUR RETURN';

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
      'Your rank opens once there are enough participants — anonymous, KVKK compliant';

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
      'Your portfolio\'s value at the end of the period is compared with its value at the start:\n\n(period end − period start) ÷ period start\n\nThe 7D / 30D / 1Y choice above changes the result directly.';

  @override
  String get depositsDontChangeRankBody =>
      'The only thing measured is how much your assets gained in the market. Buys and sells during the period do NOT affect the ratio.\n\nThe calculation assumes you held today\'s assets from the start of the period. Growing your portfolio therefore does not raise your return — you see the same percentage whether you hold 1 lot or 10,000.';

  @override
  String get everyoneMeasuredSameBody =>
      'You and your partners are computed with the same formula, at the same moment, from the same prices.\n\nYou don\'t need to wait for your partner to open the app — the calculation happens on this device.';

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
      'The subscription is billed to your App Store account. It renews automatically; to cancel, manage it under Settings → Apple ID → Subscriptions. The yearly plan starts with a 7-day free trial; unless you cancel, you are charged at the end of the trial.';

  @override
  String get premiumUnlocked => 'Premium unlocked';

  @override
  String get premiumUnlockedBody =>
      'Unlimited assets, 2 signal analyses a day, premium indicators and more are now unlocked.';

  @override
  String get greatWord => 'Great';

  @override
  String get sandikPremiumUpper => 'SANDIK PREMIUM';

  @override
  String get paywallHeadline => 'Track your portfolio\nin more depth';

  @override
  String get paywallSubhead =>
      'Unlimited assets, advanced indicators and 2 signal analyses a day.';

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
  String recapPoints(String n) {
    return '$n points';
  }

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
    return 'A short story of the year — $character';
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
  String realReturnSemanticsAhead(String pts) {
    return 'Over the last year your portfolio beat inflation by $pts points';
  }

  @override
  String get lastYearInflation => 'Over the last year, inflation-wise you are ';

  @override
  String pointsAhead(String pts) {
    return '$pts points ahead';
  }

  @override
  String realReturnSemanticsBehind(String pts) {
    return 'Over the last year your portfolio trailed inflation by $pts points';
  }

  @override
  String pointsBehind(String pts) {
    return '$pts points behind';
  }

  @override
  String get realReturnPointsUnit => 'points';

  @override
  String get realReturnAheadOfInflation => 'ahead of inflation';

  @override
  String get realReturnBehindInflation => 'behind inflation';

  @override
  String get realReturnLastYear => 'last year';

  @override
  String get realReturnYours => 'Yours';

  @override
  String get realReturnCpi => 'CPI';

  @override
  String get weeklyFlatSemantics =>
      'Your portfolio\'s market return did not change this week';

  @override
  String get thisWeekFromMarket => 'From the market this week: ';

  @override
  String get noChangeLower => 'no change';

  @override
  String pctDown(String pct) {
    return '$pct% down';
  }

  @override
  String weeklyDownSemantics(String pct) {
    return 'Your portfolio\'s market return is $pct percent down this week';
  }

  @override
  String weeklyUpSemantics(String pct) {
    return 'Your portfolio\'s market return is $pct percent up this week';
  }

  @override
  String pctUp(String pct) {
    return '$pct% up';
  }

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
  String get txSell => 'Sale';

  @override
  String get txDividend => 'Dividend';

  @override
  String get txBuy => 'Purchase';

  @override
  String get gainWord => 'gain';

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
    return 'Widen the gap — second is $gap% behind';
  }

  @override
  String get atTheTop => 'You\'re at the top — keep the lead';

  @override
  String toPassPerson(String name, String diff) {
    return '+$diff% to pass $name';
  }

  @override
  String get higherInOtherPeriods =>
      'You rank higher in other periods — tap to see';

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
      'This is not a sale — the asset leaves your portfolio and drops out of totals and the history chart. Transaction records stay under \"Portfolio Activity\". If you sold it, use \"Sell\" instead so your realised profit/loss is counted.';

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
      'You are selling the whole position — it leaves the list but stays as a sale record. Your transaction history and realised profit/loss are kept. To remove the record entirely, use \"Delete\" from the asset detail.';

  @override
  String get saleValue => 'Sale value';

  @override
  String get noPriceAlert => 'No price alert';

  @override
  String nActiveAlerts(int n) {
    return '$n active price alerts';
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
    return '$lehte/$total indicators · $pct% confidence';
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
      'This asset\'s price history could not be fetched — indicators cannot be calculated.';

  @override
  String get noIndicatorsSelected =>
      'No indicators are selected for this asset type. Enable them from Profile → Signal Settings.';

  @override
  String get technicalAnalysisUpper => 'TECHNICAL ANALYSIS';

  @override
  String nOfMIndicators(int on, int all) {
    return '· $on/$all indicators';
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
  String get csvImportTitle => 'Import from CSV';

  @override
  String get csvImportBody =>
      'Copy and paste your broker statement or Excel table. Include a header row; column order doesn\'t matter.';

  @override
  String get pasteHere => 'Paste here';

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
  String get pasteFromStatement => 'Paste from statement / CSV';

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
      'The change is a unit price difference — you don\'t own this asset.';

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
  String betterThanPctInvestors(int pct) {
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
      'When the market is closed, the last close is shown.';

  @override
  String get hiddenWeekend =>
      'Not visible right now: weekend display is off. Use the switch above to turn it on.';

  @override
  String hiddenOutsideWindow(String start, String end) {
    return 'Not visible right now: you\'re outside the $start–$end window. The banner appears at $start. To see it now, turn on \"Show all day\".';
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
      'Your portfolio delivered a real return above inflation — your purchasing power grew.';

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
      'Your portfolio fell short of inflation — your purchasing power shrank.';

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
  String get searchAssetOrSymbol => 'Search asset name or symbol';

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
  String get todaysBalanceChange => 'Today\'s balance change';

  @override
  String sinceDateToToday(String date) {
    return '$date → today';
  }

  @override
  String balanceChangeSince(String date) {
    return 'Balance change since $date';
  }

  @override
  String periodChangeSim(String period) {
    return '$period change · simulation';
  }

  @override
  String periodBalanceChange(String period) {
    return '$period balance change';
  }

  @override
  String get marketOnlyRow => 'Market effect only';

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
      'Return is computed by comparing the start and end of the selected period. Rankings and allocations are anonymous — identity, quantity and TRY figures are never shared.';

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
  String get toneRest => 'You can do better — follow the 30D view';

  @override
  String get raceFooterPartners =>
      'The ranking is the selected period\'s return (%). Everyone is measured with the same formula; no one\'s asset list is visible.';

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
    return 'Measured: $start – $end (CPI is published monthly, so the window ends at the last released month)';
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
    return 'sandık — version $surum';
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
  String get shareCardXirr => 'Annualized (XIRR)';

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
  String shareCardBetterThanPct(int pct) {
    return '$pct% of investors';
  }

  @override
  String shareCardRange(String start, String end) {
    return '$start – $end';
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
  String get todayMarketOnly => 'market effect only';

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
  String get todayLoading => 'Intraday data loading';

  @override
  String get todayRealLabel => 'Versus inflation';

  @override
  String get todayRealHint => 'Yearly return minus CPI';

  @override
  String todayPoints(String pts) {
    return '$pts pts';
  }

  @override
  String get todayWeekLabel => 'Last week';

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
  String get todayGreenLabel => 'Holdings in the green';

  @override
  String get todayGreenHint => 'Above their buy price';

  @override
  String todayGreenValue(int green, int total) {
    return '$green / $total';
  }

  @override
  String get todayOpenAction => 'Open';

  @override
  String todayEventCpiShort(String date) {
    return 'CPI release · $date';
  }

  @override
  String todayEventHolidayShort(String date) {
    return 'Market holiday · $date';
  }

  @override
  String get todayEventMonthEndShort => 'Month end · monthly summary';

  @override
  String todayDaysShort(int n) {
    return '$n days';
  }

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
  String get todayWordToday => 'today';

  @override
  String get todayWordTomorrow => 'tomorrow';

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
  String get emptyPasteHint =>
      'Copy your broker statement and paste it; every line becomes an asset.';

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
  String get sectionThisPeriod => 'THIS PERIOD';

  @override
  String get sectionAssets => 'ASSETS';

  @override
  String get sectionDepth => 'DEPTH';

  @override
  String get sectionDepthHint => 'XIRR, health, advanced metrics, character';

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
}
