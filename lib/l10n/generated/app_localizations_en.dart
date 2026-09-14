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
      'Only changes the card set in Performance › Summary; calculations stay the same.';

  @override
  String get levelBeginner => 'Beginner';

  @override
  String get levelIntermediate => 'Intermediate';

  @override
  String get levelAdvanced => 'Advanced';

  @override
  String get levelBeginnerDesc =>
      'Simple summary: return, inflation and contribution. No health, XIRR or percentile.';

  @override
  String get levelIntermediateDesc =>
      'Today\'s view: health card, money-weighted return (XIRR), percentile.';

  @override
  String get levelAdvancedDesc =>
      'Intermediate + risk-adjusted return, timing effect and recovery.';

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
}
