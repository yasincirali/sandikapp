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
}
