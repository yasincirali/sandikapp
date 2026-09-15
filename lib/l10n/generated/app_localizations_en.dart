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
      'English is in beta: some screens are still Turkish.';

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
  String get tradeVolumeUpper => 'TRADE VOLUME';

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
  String get nominalReturn => 'Nominal return';

  @override
  String get periodCpi => 'Period CPI';

  @override
  String get pointDifference => 'Point difference';

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
  String portfolioLineNote(String name) {
    return 'The $name line is the scenario where you held today\'s assets from the start of the period — it is not your realised return.';
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
}
