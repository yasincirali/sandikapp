import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/destek.dart';
import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/price_alert_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/fon_akisi_provider.dart' show balinaRadariAcikProvider;
import '../providers/preferences_provider.dart';
import '../l10n/l10n.dart';
import '../providers/quiet_hours_provider.dart';
import '../widgets/sandik_acilir.dart';
import '../widgets/seviye_anketi.dart';
import '../widgets/yenilikler_sheet.dart';
import '../services/surum_notu_service.dart';
import '../services/review_prompt_service.dart';
import '../services/crash_reporter.dart';
import '../services/data_export_service.dart';
import '../services/share_card_service.dart';
import '../services/auth_service.dart';
import '../services/social_auth_service.dart';
import '../services/biometric_lock_service.dart';
import '../services/disclaimer_service.dart';
import '../services/remote_config_service.dart';
import '../services/supabase_service.dart';
import '../services/home_widget_service.dart';
import '../services/live_activity_service.dart';
import '../theme/sandik.dart';
import '../theme/yazi_boyutu.dart';

import '../widgets/sandik_app_bar.dart';
import '../utils/sandik_snack.dart';
import '../utils/friendly_error.dart';
import 'kayitli_cihazlar_screen.dart';
import 'kullanici_adi_screen.dart';
import 'legal_doc_screen.dart';
import 'onboarding_screen.dart';
import 'push_diagnostics_screen.dart';
import 'price_alerts_screen.dart';
import 'signal_settings_screen.dart';
import '../widgets/custom_loading_indicator.dart';

/// Ayarlar'ın alt ekranları. Hub → bölüm, en fazla bir seviye derin.
enum SettingsBolum {
  gorunum,
  bildirimler,
  hesap,
  yardim;

  /// Bölüm başlığı — dile göre (3.20). Enum bağlamsız olduğu için başlık
  /// alan olarak değil, `context` (ya da testte doğrudan sözlük) ile üretilir.
  String baslik(BuildContext context) => baslikOf(context.l10n);

  String baslikOf(AppLocalizations l) => switch (this) {
        SettingsBolum.gorunum => l.settingsAppearance,
        SettingsBolum.bildirimler => l.settingsNotifications,
        SettingsBolum.hesap => l.settingsAccount,
        SettingsBolum.yardim => l.settingsHelp,
      };
}

/// Profil → Ayarlar ekranı.
///
/// 2026-09-14: tek uzun liste (9 bölüm, ~25 satır) sığ bir HUB'a bölündü —
/// dört satır, her biri bir alt ekran ([SettingsBolum]). Aynı `State`
/// sınıfı hem hub'ı hem bölümü çizer: silme/dışa aktarma/yasal metin
/// akışları bu sınıfta yaşıyor, bölüm başına kopyalanmasın diye.
///
/// Özelliğe ait ayarlar ait olduğu yerde durur: Yarış anahtarı Lider
/// tablosu ekranına taşındı, fiyat alarmı varlık ekranından kurulur;
/// Bildirimler bölümünde yalnızca liste kalır.
class SettingsScreen extends ConsumerStatefulWidget {
  /// `null` → hub; dolu → o bölümün satırları.
  final SettingsBolum? bolum;
  const SettingsScreen({super.key, this.bolum});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;

  /// Hub'ın "Gelişmiş" grubu açık mı. Kapalı başlar: içindekiler teknik ve
  /// nadir; ilk bakışta yer kaplamasın.
  bool _gelismisAcik = false;

  // Ayarlar sadeleştirmesi (sadeleştirme listesi madde 10, 2026-10-04):
  // bölümler net başlıklı gruplara ayrılır, teknik satırlar hub'da katlanır
  // "Gelişmiş"e iner. HİÇBİR satır kalkmadı ve tercih anahtarları değişmedi
  // — yalnız sıra ve başlık. Bayrak `performans_ayar_sade` (ve `_sadeAyar`)
  // 2026-10-05'te kalktı; eski başlıksız düzenler silindi.

  /// Kurulu sürüm — paketten okunur, elle yazılmaz (bkz. sayfa dibindeki
  /// sürüm satırı). Yüklenene kadar null.
  String? _surum;

  static const _supportEmail = kDestekEposta;

  @override
  void initState() {
    super.initState();
    SurumNotuService.instance.calisanSurum().then((v) {
      if (mounted) setState(() => _surum = v);
    }).catchError((_) => null);
  }

  Future<void> _confirmDeleteAccount() async {
    if (_deleting) return;
    // 1. Kademe — uyarı
    final firstConfirm = await showSandikConfirm(
      context: context,
      title: context.l10n.deleteAccountTitle,
      message: context.l10n.deleteAccountBody,
      confirmLabel: context.l10n.continueAction,
      destructive: true,
      barrierDismissible: false,
    );
    if (!firstConfirm || !mounted) return;

    // Yalnızca Apple/Google ile açılmış hesabın şifresi yok: ikinci kademe
    // sağlayıcının kendi ekranıdır (AuthService.deleteAccount taze kimlik
    // alır, sunucu doğrular). Şifre diyaloğu burada anlamsız olurdu.
    if (!AuthService.instance.hasPasswordIdentity) {
      final social = await showSandikConfirm(
        context: context,
        title: context.l10n.verifyIdentityTitle,
        message: context.l10n.verifyIdentityBody,
        confirmLabel: context.l10n.continueAction,
        destructive: true,
        barrierDismissible: false,
      );
      if (!social || !mounted) return;
      await _runDelete(password: null);
      return;
    }

    // 2. Kademe — şifre doğrulama
    final passwordCtrl = TextEditingController();
    bool obscure = true;
    final secondConfirm = await showSandikGecisli<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: context.c.surface2,
          title: Text(context.l10n.confirmWithPassword,
              style: TextStyle(color: context.c.text90)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.l10n.confirmWithPasswordBody,
                style: TextStyle(color: context.c.text58, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                autofocus: true,
                style: TextStyle(color: context.c.text90),
                decoration: context.inputDecoration(
                  context.l10n.passwordLabel,
                  prefixIcon: Icon(Icons.lock_outline_rounded,
                      color: context.c.text36, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: context.c.text36,
                      size: 20,
                    ),
                    onPressed: () => setLocal(() => obscure = !obscure),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: Text('Vazgeç', style: TextStyle(color: context.c.text58)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: Text(context.l10n.deleteAccountUpper,
                  style: TextStyle(
                      color: context.c.loss, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (secondConfirm != true || !mounted || passwordCtrl.text.isEmpty) return;
    await _runDelete(password: passwordCtrl.text);
  }

  Future<void> _runDelete({required String? password}) async {
    setState(() => _deleting = true);
    try {
      // Provider üzerinden çağır — auth state'i null'a çekip AuthGate'in
      // otomatik olarak LoginScreen'e dönmesini sağlar. Doğrudan
      // AuthService.deleteAccount çağrılırsa state güncellenmez ve
      // kullanıcı silinmiş olsa da ekranda kalır.
      await ref.read(authProvider.notifier).deleteAccount(password: password);
      if (!mounted) return;
      // Açık olabilecek modal'ları kapatıp root'a dön.
      Navigator.of(context).popUntil((r) => r.isFirst);
      if (!mounted) return;
      await showAppSuccess(
        context,
        title: context.l10n.accountDeletedTitle,
        message: context.l10n.accountDeletedBody,
      );
    } on SocialSignInCancelled {
      // Sağlayıcı ekranında vazgeçti — hata değil.
      if (mounted) setState(() => _deleting = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      showAppError(context, e);
    }
  }

  /// Dokunulan karonun dikdörtgeni — iPad popover'ı buradan açılır.
  final _disaAktarKaroKey = GlobalKey();

  /// Kilit ve gösterge karonun kendisinde (`_SettingsTile.onTapAsync`, tek
  /// yükleniyor davranışı 2026-10-08); eski `_exporting` bayrağı kalktı.
  Future<void> _exportData() async {
    // Dikdörtgen karo "yükleniyor" hâline geçmeden ÖNCE ölçülür: o anda
    // trailing değişiyor, ölçüm kararlı hâlden yapılsın. (`onTapAsync`
    // göstergeyi bir sonraki karede çizer; bu satır senkron koşar.)
    final origin = ShareCardService.originOf(_disaAktarKaroKey.currentContext);
    try {
      await DataExportService.instance.exportAndShare(paylasimKaynagi: origin);
      // Başarı toast'ı YOK (kullanıcı kararı, 2026-09-16): `exportAndShare`
      // sistem paylaşım sayfasını açıyor, kullanıcı dosyayı zaten orada
      // görüyor. Toast paylaşım sayfasının ARKASINDA kalıyordu.
    } catch (e, st) {
      // Sessiz kalmasın: "verilerimi indir" sahada hata verdiğinde elimizde
      // tek iz yoktu (CLAUDE.md "servis catch'leri sessiz kalmasın").
      CrashReporter.report(e, st, reason: 'SettingsScreen.exportData');
      if (!mounted) return;
      showAppError(context, e);
    }
  }

  void _showDisclaimerText() {
    showSandikGecisli<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.c.surface2,
        title: Row(
          children: [
            Icon(Icons.gavel_rounded, color: context.c.amberText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.l10n.investmentDisclaimer,
                style: TextStyle(color: context.c.text90, fontSize: 16),
              ),
            ),
            Text(
              'v$disclaimerVersion',
              style: TextStyle(color: context.c.text36, fontSize: 11),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Text(
            disclaimerText,
            style: TextStyle(
              color: context.c.text90,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.close, style: TextStyle(color: context.c.amberText)),
          ),
        ],
      ),
    );
  }

  void _showLegalDoc(String title, List<LegalBlock> blocks, IconData icon) {
    pushGuarded(
      context,
      adaptiveRoute<void>(
        builder: (_) =>
            LegalDocScreen(title: title, blocks: blocks, icon: icon),
      ),
    );
  }

  Future<void> _sendMail({
    required String subject,
    String body = '',
  }) async {
    final userEmail = ref.read(authProvider).valueOrNull?.email ?? '';
    final signature =
        userEmail.isNotEmpty ? '\n\n---\nKullanıcı: $userEmail' : '';
    final uri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      query: _encodeMailtoQuery({
        'subject': subject,
        'body': '$body$signature',
      }),
    );
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      sandikSnack(context,
          context.l10n.mailAppFailed(_supportEmail),
          kind: SandikSnackKind.warning, duration: const Duration(seconds: 5));
    }
  }

  String _encodeMailtoQuery(Map<String, String> params) {
    return params.entries
        .map((e) =>
            '${Uri.encodeComponent(e.key)}=${Uri.encodeComponent(e.value)}')
        .join('&');
  }

  Future<void> _openFeedbackSheet() async {
    String type = 'Şikayet';
    final controller = TextEditingController();
    final result = await showSandikSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: SandikSpace.screenH(ctx),
            right: SandikSpace.screenH(ctx),
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.l10n.feedbackTitle,
                  style: context.t.headlineSmall?.copyWith(
                    color: context.c.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final t in const ['Şikayet', 'Tavsiye', 'Diğer'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(t),
                          selected: type == t,
                          onSelected: (_) => setLocal(() => type = t),
                          selectedColor:
                              context.c.amberFill.withValues(alpha: 0.25),
                          backgroundColor: context.c.surface1,
                          labelStyle: TextStyle(
                            color: type == t
                                ? context.c.amberText
                                : context.c.text58,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  // Gönder düğmesinin etkinliği `controller.text`'e bakar;
                  // yeniden çizim olmadan klavye yerleştikten sonra yazılan
                  // metin düğmeyi açmıyordu (csv_import_screen aynı hata).
                  onChanged: (_) => setLocal(() {}),
                  maxLines: 6,
                  minLines: 4,
                  style: TextStyle(color: context.c.text90),
                  decoration: InputDecoration(
                    hintText: context.l10n.feedbackHint,
                    hintStyle: TextStyle(color: context.c.text36),
                    // Dolgu/çerçeve temadan (`inputDecorationTheme` = `inputFill` kuralı).
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: context.c.amberFill,
                    foregroundColor: context.c.onAmber,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: controller.text.trim().isEmpty
                      ? null
                      : () => Navigator.pop(
                            ctx,
                            {'type': type, 'body': controller.text.trim()},
                          ),
                  child: Text(context.l10n.send,
                      style: TextStyle(fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result != null) {
      await _sendMail(
        subject: '[${result['type']}] Sandık uygulama geri bildirim',
        body: result['body'] ?? '',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bolum = widget.bolum;
    // Silme uçarken ekran TAMAMEN kilitli olmalı — yalnızca gövde değil.
    //
    // Önceki hâlde `AbsorbPointer` sadece `body`'yi sarıyordu: app bar'ın geri
    // oku ve sistem geri hareketi açık kalıyordu. Kullanıcı istek uçarken
    // ekrandan çıkabiliyor, sonra `Navigator.popUntil` başka bir ekranı
    // kapatıyordu. Hesap silme geri alınamaz ve 30 sn sürebilir; bu pencerede
    // tek doğru davranış "bekle" demek.
    //
    // `canPop: false` yalnızca _deleting iken: normal zamanda geri tuşu
    // çalışmaya devam etsin (ayarlar hub'ı iç içe açılıyor).
    return PopScope(
      canPop: !_deleting,
      child: Scaffold(
        backgroundColor: context.c.background,
        appBar: SandikAppBar(
          title: bolum?.baslik(context) ?? context.l10n.settings,
          // Geri oku silme sırasında gizlenir: görünüp tıklanmaması
          // kullanıcıya "bu iş bitene kadar bekle"yi sessizce anlatır.
          showBack: !_deleting,
        ),
        body: Stack(
          children: [
            AbsorbPointer(
              absorbing: _deleting,
              child: ListView(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                children: switch (bolum) {
                  null => _hub(),
                  SettingsBolum.gorunum => _gorunum(),
                  SettingsBolum.bildirimler => _bildirimler(),
                  SettingsBolum.hesap => _hesap(),
                  SettingsBolum.yardim => _yardim(),
                },
              ),
            ),
            // Örtü, kilidin GÖRÜNÜR karşılığı. AbsorbPointer tek başına
            // dokunuşu yutar ama ekran çalışır görünmeye devam eder;
            // kullanıcı uygulamanın donduğunu sanıp kapatmaya çalışır.
            if (_deleting)
              Positioned.fill(
                child: ColoredBox(
                  color: context.c.background.withValues(alpha: 0.82),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CustomLoadingIndicator(size: 32),
                        SizedBox(height: SandikSpace.md),
                        Text(
                          context.l10n.deletingAccount,
                          style: context.t.titleMedium
                              ?.copyWith(color: context.c.text90),
                        ),
                        SizedBox(height: SandikSpace.xs),
                        Text(
                          context.l10n.deletingAccountBody,
                          textAlign: TextAlign.center,
                          style: context.t.bodySmall
                              ?.copyWith(color: context.c.text58),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _bolumAc(SettingsBolum b) => pushGuarded(
        context,
        adaptiveRoute<void>(builder: (_) => SettingsScreen(bolum: b)),
      );

  /// Hub: dört bölüm + (admin) tanılama + (debug) geliştirici + sürüm.
  List<Widget> _hub() => [
        const SizedBox(height: 4),
        _SettingsTile(
          icon: Icons.palette_outlined,
          title: SettingsBolum.gorunum.baslik(context),
          subtitle: context.l10n.settingsAppearanceSubtitle,
          onTap: () => _bolumAc(SettingsBolum.gorunum),
        ),
        _SettingsTile(
          icon: Icons.notifications_outlined,
          title: SettingsBolum.bildirimler.baslik(context),
          subtitle: defaultTargetPlatform == TargetPlatform.iOS
              ? context.l10n.notifSubtitleIos
              : context.l10n.notifSubtitleAndroid,
          onTap: () => _bolumAc(SettingsBolum.bildirimler),
        ),
        _SettingsTile(
          icon: Icons.shield_outlined,
          title: SettingsBolum.hesap.baslik(context),
          subtitle: context.l10n.settingsAccountSubtitle,
          onTap: () => _bolumAc(SettingsBolum.hesap),
        ),
        _SettingsTile(
          icon: Icons.help_outline_rounded,
          title: SettingsBolum.yardim.baslik(context),
          subtitle: context.l10n.settingsHelpSubtitle,
          onTap: () => _bolumAc(SettingsBolum.yardim),
        ),
            ...() {
              final teknik = _teknikBolumler();
              if (teknik.isEmpty) return teknik;
              // Teknik satırlar katlanır "Gelişmiş" grubunda:
              // tanılama ve geliştirici araçları gündelik ayar değildir,
              // hub'ın dört bölümüyle aynı ağırlıkta durmaları listeyi
              // olduğundan kalabalık gösteriyordu (madde 10).
              return <Widget>[
                const SizedBox(height: 28),
                _GelismisGrup(
                  acik: _gelismisAcik,
                  onDegis: () =>
                      setState(() => _gelismisAcik = !_gelismisAcik),
                  children: teknik,
                ),
              ];
            }(),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              // Sürüm SABİT yazılmıyordu artık: fastlane CI'da bump ettiği
              // için elle yazılan değer bayatlıyordu (gerçek 1.1.4 iken
              // burada "1.0.0" görünüyordu). `PackageInfo` kurulu olanı
              // söyler.
              child: Text(
                context.l10n.appVersionLabel(_surum ?? '…'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.c.text36,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 40),
      ];

  /// Teknik bölümler — admin tanılama ve debug geliştirici. Eski düzende
  /// hub'da doğrudan, sade düzende "Gelişmiş" grubunun içinde çizilir.
  List<Widget> _teknikBolumler() => [
            // Push teşhisi debug kapısının DIŞINDA, admin'e açık.
            //
            // Bu ekranın tek işi zincirin neresinin koptuğunu göstermek ve
            // zincir çoğunlukla TESTFLIGHT'ta kopuyor: APNs ortamı, gerçek
            // cihaz izni, provisioning profile gibi şeyler debug build'de
            // hiç sınanmaz. Debug'a kilitli bir teşhis aracı tam da ihtiyaç
            // duyulan yerde kullanılamıyordu.
            //
            // Ekran KENDİNİ koruyor: teşhis RPC'leri admin-only ve admin
            // olmayan hesaba "Bu hesap admin değil" diyor. Burada ikinci
            // bir kapı kurmak (e-posta karşılaştırması gibi) yetki kuralını
            // iki yere kopyalardı; ikisi ayrıştığında yanlış olan bu taraf
            // olurdu. Salt okunur, token'ların kendisini göstermez.
            // 2026-09: tile artık YALNIZCA admin hesaba görünür. Ekranın
            // kendini koruması yeterliydi ama admin olmayan kullanıcı
            // "GELİŞTİRİCİ" başlığı altında cron/edge/APNs jargonlu, "Bu
            // hesap admin değil" diyen 943 satırlık bir ekrana çıkıyordu.
            if (ref.watch(isPushAdminProvider).valueOrNull == true) ...[
              const SizedBox(height: 28),
              SandikSectionHeader(title: context.l10n.diagnosticsUpper),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: context.l10n.pushDiagnostics,
                subtitle: context.l10n.pushDiagnosticsSubtitle,
                onTap: () => pushGuarded(
                  context,
                  adaptiveRoute<void>(
                    builder: (_) => const PushDiagnosticsScreen(),
                  ),
                ),
              ),
            ],
            // Debug build'de admin olmasa da görünür — Crashlytics testi
            // geliştiricinin kendi cihazında yapılır.
            if (kDebugMode) ...[
              const SizedBox(height: 28),
              const SandikSectionHeader(title: 'GELİŞTİRİCİ (DEBUG)'),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.bug_report_outlined,
                title: 'Test Crash (debug-only)',
                subtitle:
                    'Crashlytics raporlamasını test etmek için uygulamayı çökertir',
                destructive: true,
                onTap: () {
                  // Bilinçli olarak çökertiyoruz — Crashlytics dashboard'da görünmeli
                  throw Exception('Test crash — kullanıcı tetikledi');
                },
              ),
            ],
      ];

  /// Görünüm — iki grup (sadeleştirme madde 10, 2026-10-04).
  ///
  ///   · GENEL: uygulamanın kendisi (tema, yazı boyutu, dil)
  ///   · PORTFÖY GÖRÜNÜMÜ: rakamların nasıl gösterildiği (baz birim,
  ///     yatırımcı seviyesi, "Bugünkü portföyle")
  ///
  /// Eski düzende beş seçici başlıksız alt alta duruyordu; tema ve baz
  /// birim satırlarının ne seçtiği ancak simgelerden anlaşılıyordu.
  /// "Bugünkü portföyle" Performans'ın kapsam panelinden buraya taşındı
  /// (madde 5): dönemden döneme değişen bir kontrol değil, bir bakış
  /// tercihi. Sade Başlangıç'ta (grafik araçları gizli) satır yok — orada
  /// etkisiz olurdu (bkz. `_simulate`).
  List<Widget> _gorunum() {
    final l = context.l10n;
    return [
      const SizedBox(height: 4),
      SandikSectionHeader(title: l.settingsGroupGeneral),
      _SubSectionTitle(l.settingsThemeLabel),
      const SizedBox(height: 8),
      const _ThemeModePicker(),
      const SizedBox(height: 12),
      const _YaziBoyutuPicker(),
      const SizedBox(height: 12),
      const _LanguagePicker(),
      const SizedBox(height: 28),
      SandikSectionHeader(title: l.settingsGroupPortfolioView),
      _SubSectionTitle(l.settingsBaseCurrencyLabel),
      const SizedBox(height: 8),
      const _BaseCurrencyPicker(),
      const SizedBox(height: 12),
      const _InvestorLevelPicker(),
      if (ref.watch(seviyeGorunurlukProvider).grafikAraclari) ...[
        const SizedBox(height: 12),
        const _BugunkuPortfoyAnahtari(),
      ],
      const SizedBox(height: 24),
    ];
  }

  List<Widget> _bildirimler() => [
            SandikSectionHeader(title: context.l10n.notificationsUpper),
            const SizedBox(height: 12),
            // Teknik sinyaller TEK satır (2026-09-21): anahtar bildirimi
            // açar/kapar, satırın kendisi ayarlara götürür. Eskiden iki
            // ayrı satırdı (bildirim anahtarı + ayar bağlantısı) ve aynı
            // konu iki yerde görünüyordu.
            _SettingsTile(
              icon: Icons.tune_rounded,
              title: context.l10n.signalSettings,
              subtitle: context.l10n.signalNotificationsSubtitle,
              onTap: () => pushGuarded(
                context,
                adaptiveRoute<void>(builder: (_) => const SignalSettingsScreen()),
              ),
              trailing: Semantics(
                label: context.l10n.signalNotifications,
                child: Switch.adaptive(
                  value: ref.watch(signalNotificationsProvider),
                  // `amberText` — öteki dört anahtarla aynı (2026-10-08).
                  activeTrackColor: context.c.amberText,
                  onChanged: (v) async {
                    await ref.read(signalNotificationsProvider.notifier).set(v);
                    // Sunucuya da yaz: sinyal push'unu sunucu gönderiyor, bu
                    // anahtar orada bilinmezse kapatmak işe yaramaz.
                    await syncSignalsEnabledPreference(ref);
                  },
                ),
              ),
            ),
            // Alarm KURMA yeri varlık ekranıdır (zil ikonu); burada yalnızca
            // liste. Alt satır aktif sayısını söyler ki hub'dan bakan kişi
            // ekrana girmeden durumu görsün.
            _SettingsTile(
              icon: Icons.add_alert_outlined,
              title: context.l10n.priceAlerts,
              subtitle: () {
                final aktif = ref
                        .watch(priceAlertsProvider)
                        .valueOrNull
                        ?.where((a) => a.isActive)
                        .length ??
                    0;
                return aktif == 0
                    ? context.l10n.alertSetFromAssetScreen
                    : '$aktif aktif alarm';
              }(),
              onTap: () => pushGuarded(
                context,
                adaptiveRoute<void>(builder: (_) => const PriceAlertsScreen()),
              ),
            ),
            const _QuietHoursTile(),
            const SizedBox(height: 8),
            // Ortak bildirim anahtarları BURADA kalır, ortak yönetiminin
            // (Profil) yanına taşınmaz (sadeleştirme değerlendirmesi
            // 2026-10-04): kullanıcı "bildirimleri kapat"ı tek listede arar;
            // sessiz saatler ve brifing saati de bu listede. Profil'e ikinci
            // bir kopya ya da bağlantı eklemek,
            // kaldırdığımız "aynı ayar iki yerde" sorununu geri getirirdi.
            _SwitchTile(
              icon: Icons.people_outline_rounded,
              title: context.l10n.partnerInviteNotifications,
              subtitle: context.l10n.partnerInviteNotificationsSubtitle,
              value: ref.watch(partnerNotificationsProvider),
              onChanged: (v) =>
                  ref.read(partnerNotificationsProvider.notifier).set(v),
            ),
            // Ortağı OLMAYAN kullanıcıya gösterilmez: kapatacak bir şeyi
            // yokken sunulan anahtar, ayar listesini uzatmaktan başka işe
            // yaramaz ve "bu ne?" sorusu doğurur.
            if (ref.watch(activePartnersProvider).isNotEmpty)
              const _PartnerActivitySwitch(),
            const _BriefSlotTile(),
            if (ref.watch(balinaRadariAcikProvider)) const _RadarAyarlari(),
            // Maaş günü birikim hatırlatması (0119) — birikim serisiyle aynı
            // bayrak: seri görünmüyorken "serin ay ay sayılıyor" diyen bir
            // hatırlatma anlamsız olurdu.
            if (RemoteConfigService.instance.birikimSerisi)
              const _BirikimHatirlatmaTile(),
            const SizedBox(height: 28),

            // -- CANLI ETKİNLİKLER ---------------------------------
            //
            // Bölüm başlığı iOS'taki özellik adıyla EŞLEŞİR ("Canlı
            // Etkinlikler"): kullanıcı gördüğü adla arar.
            //
            // Tutar anahtarı da BURADA durur, "GİZLİLİK" altında değil.
            // Gizlilik onun SONUCU, konusu değil: anahtar Canlı
            // Etkinlik'in ne göstereceğini belirler ve o özellik
            // kapalıyken hiçbir şey ifade etmez. Android'in ayar
            // kılavuzu da bunu söylüyor -- bir ayar, ait olduğu
            // ÖZELLİĞİN altında durur.
            //
            // iOS-only: Android'de ActivityKit yok, kanal kayıtlı değil
            // ve `sync` ilk satırda döner (bkz. LiveActivityService).
            // Çalışmayan bir ayarı göstermek kullanıcıyı yanıltır.
            if (defaultTargetPlatform == TargetPlatform.iOS) ...[
              SandikSectionHeader(title: context.l10n.liveActivitiesUpper),
              const SizedBox(height: 12),
              const _LiveActivitySection(),
              const SizedBox(height: 28),
            ],

      ];

  List<Widget> _hesap() {
    final hesapSatirlari = <Widget>[
            // Kullanıcı adı (0079): ortağın gördüğü ad. İlk girişte zorunlu
            // seçilir, buradan değiştirilir — aynı ekran, geri oklu.
            _SettingsTile(
              icon: Icons.alternate_email_rounded,
              title: context.l10n.kullaniciAdiEtiket,
              subtitle: ref.watch(authProvider).valueOrNull?.username ??
                  context.l10n.kullaniciAdiSecilmedi,
              onTap: () => pushGuarded(
                context,
                adaptiveRoute<void>(builder: (_) => const KullaniciAdiScreen()),
              ),
            ),
            _SwitchTile(
              icon: Icons.fingerprint_rounded,
              title: context.l10n.biometricLock,
              subtitle:
                  context.l10n.biometricLockSubtitle,
              value: ref.watch(biometricLockProvider),
              onChanged: (v) async {
                if (v) {
                  // Açarken bir kez doğrula: cihazda kilit yoksa ya da
                  // kullanıcı vazgeçerse anahtar açık kalmasın — sonra
                  // kilitten çıkamayacağı bir ekrana düşerdi.
                  final svc = BiometricLockService.instance;
                  if (!await svc.available) {
                    if (!mounted) return;
                    sandikSnack(context,
                        context.l10n.noBiometricOnDevice,
                        kind: SandikSnackKind.warning);
                    return;
                  }
                  if (!mounted) return;
                  // Sözlük await'ten ÖNCE okunur.
                  final istem = context.l10n.biometricPrompt;
                  final sonuc = await svc.authenticate(reason: istem);
                  if (!sonuc.basariliMi) {
                    // Cihazda kilit yoksa yukarıdaki `available` kapısı
                    // geçirmişti ama doğrulama yine de yapılamadı: anahtarı
                    // açmak kullanıcıyı çıkışsız kilit ekranına düşürürdü.
                    if (sonuc == BiyometrikSonuc.kullanilamaz && mounted) {
                      sandikSnack(context, context.l10n.noBiometricOnDevice,
                          kind: SandikSnackKind.warning);
                    }
                    return;
                  }
                }
                await ref.read(biometricLockProvider.notifier).set(v);
              },
            ),
            // Tek aktif cihaz (0098): kod ile doğrulanmış cihazlar; buradan
            // kaldırılan cihaz bir sonraki girişte yeniden kod ister.
            _SettingsTile(
              icon: Icons.devices_rounded,
              title: context.l10n.kayitliCihazlar,
              subtitle: context.l10n.kayitliCihazlarAlt,
              onTap: () => pushGuarded(
                context,
                adaptiveRoute<void>(
                    builder: (_) => const KayitliCihazlarScreen()),
              ),
            ),
    ];
    final veriSatirlari = <Widget>[
            _SettingsTile(
              key: _disaAktarKaroKey,
              icon: Icons.download_outlined,
              title: context.l10n.downloadMyData,
              subtitle: context.l10n.downloadMyDataSubtitle,
              onTap: null,
              onTapAsync: _exportData,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_outlined,
              title: context.l10n.deleteMyAccount,
              subtitle: context.l10n.deleteMyAccountSubtitle,
              destructive: true,
              trailing:
                  _deleting ? const CustomLoadingIndicator(size: 18) : null,
              onTap: _deleting ? null : _confirmDeleteAccount,
            ),
    ];
    // Kim olduğun ve nasıl korunduğun bir grup, verinin
    // kendisi (dışa aktarma, silme) ayrı grup. Silme en altta kalır.
    return [
      SandikSectionHeader(title: context.l10n.settingsGroupSecurityAccount),
      const SizedBox(height: 12),
      ...hesapSatirlari,
      const SizedBox(height: 28),
      SandikSectionHeader(title: context.l10n.settingsGroupData),
      const SizedBox(height: 12),
      ...veriSatirlari,
    ];
  }

  List<Widget> _yardim() {
    final iletisim = _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: context.l10n.contactUs,
              subtitle: _supportEmail,
              onTap: () => _sendMail(subject: 'Sandık uygulama iletişim'),
            );
    final puan = _SettingsTile(
              icon: Icons.star_outline_rounded,
              title: context.l10n.rateAppTitle,
              subtitle: context.l10n.rateAppSubtitle,
              // Kapı yok: kullanıcı bilerek geliyor. Otomatik istemi
              // "Sonra" diye geçiştirdiyse puanı buradan verir.
              onTap: () => ReviewPromptService.instance.magazayiAc(),
            );
    final yenilikler = _SettingsTile(
              icon: Icons.auto_awesome_outlined,
              title: context.l10n.whatsNewTitle,
              subtitle: context.l10n.whatsNewSubtitle,
              // Elle açılışta TÜM liste gösterilir (otomatik açılışın
              // `onemli` filtresi uygulanmaz): kullanıcı buraya bilerek
              // geliyor, yama sürümlerini de görebilmeli.
              onTap: () async {
                final notlar = await SurumNotuService.instance
                    .gosterilecekler(otomatikAcilis: false);
                // State'in kendi `mounted`'ı — `context.mounted` burada
                // analyzer'ın istediği güvence değil.
                if (!mounted) return;
                if (notlar.isEmpty) {
                  sandikSnack(context, context.l10n.whatsNewEmpty);
                  return;
                }
                await YeniliklerSheet.goster(context, notlar);
              },
            );
    final tur = _SettingsTile(
              icon: Icons.explore_outlined,
              title: context.l10n.replayTour,
              subtitle: context.l10n.replayTourSubtitle,
              // Tur gerçek sekmelerin üstünde çalışır; Ayarlar kapanır,
              // köke dönülür ve katman orada açılır.
              onTap: () => OnboardingScreen.yenidenBaslat(context),
            );
    final geriBildirim = _SettingsTile(
              icon: Icons.rate_review_outlined,
              title: context.l10n.feedbackTitle,
              subtitle: context.l10n.feedbackSubtitle,
              onTap: _openFeedbackSheet,
            );
    final yasal = <Widget>[
            SandikSectionHeader(title: context.l10n.legalUpper),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: context.l10n.privacyPolicy,
              subtitle: context.l10n.privacyPolicySubtitle,
              onTap: () => _showLegalDoc(context.l10n.privacyPolicy,
                  LegalDocs.privacy, Icons.privacy_tip_outlined),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: context.l10n.termsOfUse,
              subtitle: context.l10n.termsOfUseSubtitle,
              onTap: () => _showLegalDoc(
                  context.l10n.termsOfUse, LegalDocs.terms, Icons.gavel_outlined),
            ),
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: context.l10n.kvkkNotice,
              subtitle: context.l10n.kvkkNoticeSubtitle,
              onTap: () => _showLegalDoc(context.l10n.kvkkNotice,
                  LegalDocs.kvkk, Icons.shield_outlined),
            ),
            // 1.2 (2026-10-04): kayıtta onaylanan dört belgenin dördü de
            // burada; hepsi `legal/tr/*.md`'den (web ile aynı metin).
            _SettingsTile(
              icon: Icons.public_rounded,
              title: context.l10n.yasalBelgeAcikRiza,
              subtitle: context.l10n.yasalBelgeAcikRizaAciklama,
              onTap: () => _showLegalDoc(context.l10n.yasalBelgeAcikRiza,
                  LegalDocs.acikRiza, Icons.public_rounded),
            ),
            _SettingsTile(
              icon: Icons.gavel_rounded,
              title: context.l10n.investmentDisclaimer,
              subtitle: context.l10n.disclaimerSubtitle,
              onTap: _showDisclaimerText,
            ),
            const SizedBox(height: 28),
    ];
    // "Bize yaz" türü satırlar (iletişim, geri bildirim, puan)
    // DESTEK'te yan yana; uygulamanın kendini anlattığı satırlar
    // (yenilikler, tanıtım turu) UYGULAMA HAKKINDA'da; yasal belgeler aynı.
    return [
      SandikSectionHeader(title: context.l10n.supportUpper),
      const SizedBox(height: 12),
      iletisim,
      geriBildirim,
      puan,
      const SizedBox(height: 28),
      SandikSectionHeader(title: context.l10n.settingsGroupAbout),
      const SizedBox(height: 12),
      yenilikler,
      tur,
      const SizedBox(height: 28),
      ...yasal,
    ];
  }
}

/// Hub'ın katlanır "Gelişmiş" grubu (sadeleştirme madde 10, 2026-10-04).
///
/// Başlık `SandikSectionHeader` + açılır ok; gövde ortak `SandikAcilir`
/// (Performans kapsam paneli ve Özet'in "Daha fazlası" ile aynı hareket).
/// Kapalıyken içerik ağaçta değil — teknik satırlar gerçekten "geride".
class _GelismisGrup extends StatelessWidget {
  const _GelismisGrup({
    required this.acik,
    required this.onDegis,
    required this.children,
  });

  final bool acik;
  final VoidCallback onDegis;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: acik,
          label: context.l10n.settingsAdvancedSemantics,
          child: ExcludeSemantics(
            child: CupertinoButton(
              minimumSize: SandikTouch.minSize,
              padding: EdgeInsets.zero,
              onPressed: onDegis,
              child: SandikSectionHeader(
                title: context.l10n.settingsAdvancedUpper,
                trailing: SandikAcilirOk(
                  acik: acik,
                  child: Icon(Icons.expand_more_rounded,
                      size: 18, color: context.c.text58),
                ),
              ),
            ),
          ),
        ),
        SandikAcilir(
          acik: acik,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// "Bugünkü portföyle" — Performans'ın simülasyon görünümü (sade düzen).
///
/// TEK KAYNAK `bugunkuPortfoyleProvider`: burası yazar, Performans okur
/// (`_simulate`). Performans'ta anahtar yok, yalnız etkinken rozet.
class _BugunkuPortfoyAnahtari extends ConsumerWidget {
  const _BugunkuPortfoyAnahtari();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _SwitchTile(
      icon: Icons.history_toggle_off_rounded,
      title: context.l10n.todaysPortfolioSettingTitle,
      subtitle: context.l10n.todaysPortfolioSettingSubtitle,
      value: ref.watch(bugunkuPortfoyleProvider),
      onChanged: (v) => ref.read(bugunkuPortfoyleProvider.notifier).set(v),
    );
  }
}

/// Bölüm İÇİ alt başlık — ör. "Canlı Etkinlikler > Gizlilik".
///
/// [_SectionTitle]'dan görsel olarak AYRIŞIR: küçük punto, harf aralığı
/// yok, cümle düzeni (ALL CAPS değil). Aksi halde iki kademe aynı ağırlıkta
/// okunur ve hiyerarşi kaybolur — kullanıcı alt başlığı yeni bir bölüm
/// sanar.
///
/// Bir bölümde ikinci bir kırılım gerektiğinde kullanılır: Android'in ayar
/// kılavuzu, yakından ilişkili ayarların grup başlığı almasını önerir.
class _SubSectionTitle extends StatelessWidget {
  final String text;
  const _SubSectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Üstte belirgin boşluk: alt başlık kendinden ÖNCEKİ satırdan
      // ayrılmalı, sonrakiyle birlikte okunmalı.
      padding: const EdgeInsets.fromLTRB(8, 18, 8, 6),
      child: Text(
        text,
        style: context.t.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: context.c.text58,
        ),
      ),
    );
  }
}

/// Tema modu seçici — Sistem / Açık / Koyu.
///
/// Seçim [themeModeProvider] üzerinden `SharedPreferences`'a yazılır ve
/// `MaterialApp.themeMode`'u besler. Varsayılan `ThemeMode.system`:
/// cihazı açık moda almış kullanıcı uygulamayı da açık görmeli
/// (`ThemeModeNotifier.build` gerekçesi).
///
/// ⚠️ **"Sistem" uygulama DIŞI yüzeylerde farklı davranır** (2026-09-15):
/// kilit ekranı ve widget cihazı izlemez, KOYU kalır. Sebep `SurfaceTheme
/// .decide`'da: "Sistem" cihazın otomatik görünümüyle gün içinde
/// kendiliğinden dönüyor ve banner kullanıcı hiçbir şey yapmadan renk
/// değiştiriyordu. Yüzeyler yalnızca açık/koyu SEÇİMİNİ izler.
///
/// Bu ayrım kasıtlıdır ve arayüzde ayrıca anlatılmıyor: "Sistem" seçen
/// kullanıcının beklentisi uygulamanın cihazı izlemesi, o korunuyor.
class _ThemeModePicker extends ConsumerWidget {
  const _ThemeModePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    final l = context.l10n;
    final options = <(ThemeMode, IconData, String)>[
      (ThemeMode.system, Icons.brightness_auto_rounded, l.themeSystem),
      (ThemeMode.light, Icons.light_mode_rounded, l.themeLight),
      (ThemeMode.dark, Icons.dark_mode_rounded, l.themeDark),
    ];

    return Container(
      padding: const EdgeInsets.all(SandikSpace.xs),
      decoration: context.surfaceCard(),
      child: Row(
        children: [
          for (final (mode, icon, label) in options)
            Expanded(
              child: SandikTappable(
                semanticLabel: context.l10n.themeSemantics(label),
                selected: current == mode,
                // Uygulama DIŞI yüzeylere (kilit ekranı + widget) itiş
                // BURADA YAPILMAZ.
                //
                // Tercihi yazmak yeterli: itişi `main.dart`'taki tek
                // `themeModeProvider` dinleyicisi üstlenir (bkz.
                // `_applySurfaceTheme`). Eskiden her ekran kendi itişini
                // yapıyordu ve Profil başlığındaki hızlı geçiş bunu
                // atlıyordu — aynı tercih iki yoldan değiştirildiğinde
                // yüzeyler ayrışıyordu. O geçiş 2026-10-04'te kaldırıldı;
                // tema artık YALNIZ bu seçiciden değişir.
                onTap: () => ref.read(themeModeProvider.notifier).set(mode),
                child: AnimatedContainer(
                  duration: SandikMotion.stateOf(context),
                  curve: SandikMotion.enter,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: current == mode
                        ? context.c.amberFill.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius: SandikRadius.smAll,
                  ),
                  child: Column(
                    children: [
                      Icon(
                        icon,
                        size: 20,
                        color: current == mode
                            ? context.c.amberText
                            : context.c.text36,
                      ),
                      const SizedBox(height: SandikSpace.xs),
                      Text(
                        label,
                        style: context.t.labelLarge?.copyWith(
                          letterSpacing: 0,
                          fontWeight: current == mode
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: current == mode
                              ? context.c.amberText
                              : context.c.text58,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Baz birimin arayüz dilindeki adı.
///
/// `BaseCurrency.label` Türkçe sabit ("Dolar") ve enum `money_format`'ta,
/// `BuildContext`'siz yaşıyor; İngilizce modda ekran okuyucu "Base currency
/// Dolar", not satırı "shown in dolar" diyordu (2026-09-29 emülatör testi
/// #27). Gösterim buradan geçer; enum etiketi dilden bağımsız kimlik kalır.
@visibleForTesting
String bazBirimAdi(AppLocalizations l, BaseCurrency b) => switch (b) {
      BaseCurrency.try_ => l.baseCurrencyNameLira,
      BaseCurrency.usd => l.baseCurrencyNameDollar,
      BaseCurrency.eur => l.baseCurrencyNameEuro,
      BaseCurrency.gold => l.baseCurrencyNameGold,
    };

/// Baz para birimi (Faz 3.2). Tema seçiciyle aynı dil: dört eşit segment.
///
/// Tercih yalnızca GÖSTERİMİ değiştirir — hesaplar TRY'de kalır, tutarlar
/// bugünkü kurla çevrilir (bkz. `money_format.dart`). Alt satır bunu açıkça
/// söyler ki "dolar bazlı getirim bu mu" yanılgısı olmasın.
class _BaseCurrencyPicker extends ConsumerWidget {
  const _BaseCurrencyPicker();

  static const _options = <(BaseCurrency, IconData)>[
    (BaseCurrency.try_, Icons.currency_lira_rounded),
    (BaseCurrency.usd, Icons.attach_money_rounded),
    (BaseCurrency.eur, Icons.euro_rounded),
    (BaseCurrency.gold, Icons.workspace_premium_rounded),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(baseCurrencyProvider);
    final baz = ref.watch(bazParaProvider);
    // Seçili birimin kuru henüz yoksa ekranlar ₺'de kalır; kullanıcı bunu
    // burada görsün, "seçtim ama değişmedi" sanmasın.
    final kurYok = current != BaseCurrency.try_ && baz.lira;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(SandikSpace.xs),
          decoration: context.surfaceCard(),
          child: Row(
            children: [
              for (final (birim, icon) in _options)
                Expanded(
                  child: SandikTappable(
                    semanticLabel: context.l10n
                        .baseCurrencySemantics(bazBirimAdi(context.l10n, birim)),
                    selected: current == birim,
                    onTap: () => setBaseCurrency(ref, birim),
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: current == birim
                            ? context.c.amberFill.withValues(alpha: 0.16)
                            : null,
                        borderRadius: SandikRadius.smAll,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: current == birim
                                ? context.c.amberText
                                : context.c.text36,
                          ),
                          const SizedBox(height: SandikSpace.xs),
                          Text(
                            birim == BaseCurrency.gold
                                ? context.l10n.assetTypeGold
                                : birim.kod,
                            style: context.t.labelLarge?.copyWith(
                              letterSpacing: 0,
                              fontWeight: current == birim
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current == birim
                                  ? context.c.amberText
                                  : context.c.text58,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: SandikSpace.xs),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
          child: Text(
            kurYok
                ? context.l10n.rateNotFetched
                : context.l10n.baseCurrencyNote(
                    bazBirimAdi(context.l10n, baz.etkinBirim).toLowerCase()),
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ),
      ],
    );
  }
}

/// Yatırımcı seviyesi — Özet sekmesinin metrik kümesi. Tema/baz para
/// seçicilerle aynı dil: üç eşit segment + seçilenin bir satırlık açıklaması.
///
/// Profilde deneyim alanı yok ve zorunlu onboarding istenmiyor; bu yüzden
/// OPSİYONEL bir cihaz tercihi (kişiye özel). Varsayılan Orta = bugünkü
/// görünüm, yani hiç dokunmayan kullanıcı için hiçbir şey değişmez.
class _InvestorLevelPicker extends ConsumerWidget {
  const _InvestorLevelPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(yatirimciSeviyesiProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubSectionTitle(context.l10n.investorLevel),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(SandikSpace.xs),
          decoration: context.surfaceCard(),
          child: Row(
            children: [
              for (final s in YatirimciSeviyesi.values)
                Expanded(
                  child: SandikTappable(
                    semanticLabel: context.l10n.levelSemantics(s.etiket(context)),
                    selected: current == s,
                    onTap: () => ref
                        .read(investorLevelIndexProvider.notifier)
                        .set(s.index),
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: current == s
                            ? context.c.amberFill.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: SandikRadius.smAll,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            s.ikon,
                            size: 20,
                            color: current == s
                                ? context.c.amberText
                                : context.c.text36,
                          ),
                          const SizedBox(height: SandikSpace.xs),
                          Text(
                            s.etiket(context),
                            style: context.t.labelLarge?.copyWith(
                              letterSpacing: 0,
                              fontWeight: current == s
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current == s
                                  ? context.c.amberText
                                  : context.c.text58,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            '${current.aciklama(context)} '
            '${context.l10n.investorLevelNote}',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ),
        // Anket (2026-10-04; bayrak `seviye_anketi` 2026-10-05'te kalktı):
        // hangi seviyede olduğundan emin olmayan kullanıcı etiket seçmek
        // yerine üç soruyu cevaplar.
        CupertinoButton(
          padding: const EdgeInsets.symmetric(horizontal: SandikSpace.xs),
          minimumSize: SandikTouch.minSize,
          alignment: Alignment.centerLeft,
          onPressed: () => seviyeAnketiniAc(context),
          child: Text(
            context.l10n.levelSurveyOpen,
            style: context.t.bodyMedium?.copyWith(color: context.c.amberText),
          ),
        ),
      ],
    );
  }
}

/// Arayüz dili (3.20). Tema seçiciyle aynı dil: üç segment.
///
/// Varsayılan Türkçe (sistem DEĞİL): İngilizce beta, bazı ekranlar Türkçe
/// kalıyor; İngilizce cihazlı kullanıcı seçmeden karışık arayüz görmesin.
/// "Sistem" seçilirse cihaz dili izlenir (`LocaleNotifier`).
class _LanguagePicker extends ConsumerWidget {
  const _LanguagePicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = LocaleNotifier.encode(ref.watch(localeProvider));
    final l = context.l10n;
    final options = <(String, IconData, String)>[
      ('tr', Icons.translate_rounded, l.languageTurkish),
      ('en', Icons.language_rounded, l.languageEnglish),
      ('system', Icons.phone_android_rounded, l.languageSystem),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubSectionTitle(l.language),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(SandikSpace.xs),
          decoration: context.surfaceCard(),
          child: Row(
            children: [
              for (final (kod, icon, label) in options)
                Expanded(
                  child: SandikTappable(
                    semanticLabel: '$label ${l.language}',
                    selected: current == kod,
                    onTap: () => ref
                        .read(localeProvider.notifier)
                        .set(LocaleNotifier.parse(kod)),
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: current == kod
                            ? context.c.amberFill.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: SandikRadius.smAll,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            icon,
                            size: 20,
                            color: current == kod
                                ? context.c.amberText
                                : context.c.text36,
                          ),
                          const SizedBox(height: SandikSpace.xs),
                          Text(
                            label,
                            style: context.t.labelLarge?.copyWith(
                              letterSpacing: 0,
                              fontWeight: current == kod
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current == kod
                                  ? context.c.amberText
                                  : context.c.text58,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l.languageNote,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// İstek atan karo (ör. verilerimi indir). Verildiğinde [onTap] yok
  /// sayılır: iş sürerken karo kilitli, sağdaki ok yerine küçük gösterge
  /// döner, ikinci dokunuş yutulur — [SandikAsyncButton] / [SandikAsyncTap]
  /// ile aynı sözleşme (tek yükleniyor davranışı, 2026-10-08). Karonun
  /// kendi bileşeni olmasının nedeni görünüş: [SandikAsyncTap] göstergeyi
  /// içeriğin ÜSTÜNE koyar, burada ise satır metni yerinde kalmalı ve
  /// gösterge yalnız sağ yuvada (eskiden elle yazılan `_exporting` hâli)
  /// görünmeli. Hata yutulmaz; çağıran kendi yakalar.
  final Future<void> Function()? onTapAsync;
  final bool destructive;
  final Widget? trailing;

  const _SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.onTapAsync,
    this.destructive = false,
    this.trailing,
  });

  @override
  State<_SettingsTile> createState() => _SettingsTileState();
}

class _SettingsTileState extends State<_SettingsTile> {
  bool _busy = false;

  Future<void> _calistir() async {
    if (_busy) return;
    // Haptic kilidin ARDINDAN — [SandikAsyncButton] ile aynı gerekçe.
    SandikHaptic.medium.perform();
    setState(() => _busy = true);
    try {
      await widget.onTapAsync!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    final title = widget.title;
    final subtitle = widget.subtitle;
    final destructive = widget.destructive;
    final VoidCallback? onTap = widget.onTapAsync == null
        ? widget.onTap
        : (_busy ? null : _calistir);
    final trailing = _busy
        ? const CustomLoadingIndicator(size: CustomLoadingIndicator.small)
        : widget.trailing;
    final color = destructive ? context.c.loss : context.c.text90;
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: SandikCard(
      padding: EdgeInsets.zero,
      child: CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        onPressed: onTap,
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(SandikRadius.md),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // `context.t` — ham `TextStyle` `CupertinoButton`'ın
                  // içinde Cupertino yazı ailesini miras alıyordu; satır
                  // DM Sans yerine dar sistem fontuyla çiziliyor, yanındaki
                  // `_SwitchTile`'dan ayrışıyordu (2026-10-08). Tema stili
                  // yazı boyutu ayarıyla da büyür.
                  Text(
                    title,
                    style: context.t.bodyLarge
                        ?.copyWith(color: color, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: context.t.titleSmall?.copyWith(
                        color: context.c.text58, fontWeight: FontWeight.w400),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right_rounded, color: context.c.text36, size: 20),
          ],
        ),
      ),
    ));
  }
}

/// Açma/kapama anahtarlı ayar satırı.
/// Live Activity gösterim penceresi — başlangıç/bitiş saati + hafta sonu.
///
/// Varsayılan BIST seansıdır (10:00–18:10) ama kullanıcı değiştirebilir:
/// yurt dışı piyasa izleyen ya da gece hareket takip eden biri için sabit
/// bir borsa saati anlamsızdır.
///
/// ⚠️ Apple oturumu **8 saat** sonra zorla kapatır. Daha geniş pencere
/// seçilirse oturum uygulama her açıldığında yenilenir; kullanıcı gün boyu
/// hiç açmazsa banner düşer. Bu Apple'ın kuralı, aşılamaz — bu yüzden
/// arayüzde açıkça yazılır.
class _LiveActivitySection extends ConsumerWidget {
  const _LiveActivitySection();

  /// BIST varsayılanı — "Gün boyu" kapatılınca buraya dönülür.
  ///
  /// Servisteki sabitlerden okunur, elle 10*60 yazılmaz: varsayılan
  /// değişirse iki yerde birden değişmesi gereken bir kopya kalmasın.
  static const _defaultStart = LiveActivityService.defaultStartMinute;
  static const _defaultEnd = LiveActivityService.defaultEndMinute;

  static String _fmt(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// "Gün boyu göster" anahtarı.
  ///
  /// Başlangıç == bitiş kuralı zaten 7/24 anlamına geliyordu ama bu
  /// KEŞFEDİLEBİLİR DEĞİLDİ: kullanıcının iki saat kutusunu aynı değere
  /// getirmesi gerektiğini kendi başına bulması beklenemez. (Gerçek bir
  /// kullanıcı bu yüzden özelliği hiç açamadı.) Anahtar aynı kuralı tek
  /// dokunuşa indirir.
  Future<void> _setAllDay(WidgetRef ref, bool allDay) async {
    final start = allDay ? 0 : _defaultStart;
    final end = allDay ? 0 : _defaultEnd;

    await ref.read(liveActivityStartProvider.notifier).set(start);
    await ref.read(liveActivityEndProvider.notifier).set(end);

    // Servise hemen aktar — bir sonraki portföy güncellemesini beklemeden
    // pencere geçerli olmalı.
    final svc = LiveActivityService.instance;
    svc.startMinute = start;
    svc.endMinute = end;
  }

  Future<void> _pick(
    BuildContext context,
    WidgetRef ref, {
    required bool isStart,
  }) async {
    final current =
        ref.read(isStart ? liveActivityStartProvider : liveActivityEndProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
      helpText: isStart ? context.l10n.startHour : context.l10n.endHour,
      builder: (ctx, child) => MediaQuery(
        // 24 saat biçimi: TR kullanıcısı AM/PM beklemez.
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;

    final mins = picked.hour * 60 + picked.minute;
    final notifier = ref.read(
        (isStart ? liveActivityStartProvider : liveActivityEndProvider)
            .notifier);
    await notifier.set(mins);

    // Servise hemen aktar: kullanıcı saati değiştirince bir sonraki
    // portföy güncellemesini beklemeden pencere geçerli olmalı.
    final svc = LiveActivityService.instance;
    svc.startMinute = ref.read(liveActivityStartProvider);
    svc.endMinute = ref.read(liveActivityEndProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final start = ref.watch(liveActivityStartProvider);
    final end = ref.watch(liveActivityEndProvider);
    final weekend = ref.watch(liveActivityWeekendProvider);
    final p = context.c;

    // Başlangıç == bitiş → kullanıcı sınır koymamış (7/24).
    final isAllDay = start == end;
    // Gece yarısını saran pencere (22:00–06:00) süreyi ters hesaplatır.
    final spanMinutes =
        isAllDay ? 1440 : (end > start ? end - start : 1440 - start + end);
    final exceedsAppleLimit = spanMinutes > 8 * 60;

    // Şu an banner görünür olmalı mı? Servisin kendi kuralını kullanır —
    // burada ikinci bir kopya kurmak, ayarın "görünecek" dediği ile
    // servisin yaptığının sessizce ayrışması demekti.
    final svc = LiveActivityService.instance;
    final visibleNow = svc.isWithinWindow(DateTime.now());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SwitchTile(
          icon: Icons.schedule_rounded,
          title: context.l10n.showAllDay,
          subtitle: context.l10n.showAllDaySubtitle,
          value: isAllDay,
          onChanged: (v) => _setAllDay(ref, v),
        ),

        // Saat kutuları yalnızca "gün boyu" KAPALIYKEN anlamlı. Açıkken
        // göstermek "bu saatler hâlâ geçerli mi?" sorusu doğurur.
        if (!isAllDay) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 8),
            child: Text(
              context.l10n.displayWindow,
              style: TextStyle(
                  color: p.text90, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _TimeBox(
                  label: context.l10n.startTime,
                  value: _fmt(start),
                  onTap: () => _pick(context, ref, isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeBox(
                  label: context.l10n.endTime,
                  value: _fmt(end),
                  onTap: () => _pick(context, ref, isStart: false),
                ),
              ),
            ],
          ),
        ],

        const SizedBox(height: 4),
        _SwitchTile(
          icon: Icons.weekend_outlined,
          title: context.l10n.showOnWeekend,
          subtitle: context.l10n.showOnWeekendSubtitle,
          value: weekend,
          onChanged: (v) async {
            await ref.read(liveActivityWeekendProvider.notifier).set(v);
            LiveActivityService.instance.includeWeekend = v;
          },
        ),

        // ---- Gizlilik alt başlığı ----
        //
        // Bölüm içinde İKİNCİ bir kırılım: "ne zaman görünsün"
        // ayarlarından sonra "ne göstersin" ayarı gelir. Android'in ayar
        // kılavuzu bunu öneriyor — yakından ilişkili ayarlar bir grupta
        // toplanır ve grup başlığı alır.
        //
        // Anahtarın kendisi bir Canlı Etkinlik ayarıdır (bu yüzden bu
        // bölümde), ama sonucu gizliliktir (bu yüzden alt başlık).
        const _SubSectionTitle('Gizlilik'),
        _SwitchTile(
          icon: Icons.visibility_off_outlined,
          title: context.l10n.showAmounts,
          subtitle: context.l10n.showAmountsSubtitle,
          value: ref.watch(lockScreenAmountsProvider),
          onChanged: (v) async {
            await ref.read(lockScreenAmountsProvider.notifier).set(v);

            // Servise aktar VE hemen senkronla.
            //
            // Alanı set etmek tek başına YETMİYORDU: `sync` yalnızca
            // portföy state'i yayınlandığında çağrılıyor, yani tercih
            // bir sonraki fiyat tick'ine kadar kilit ekranına
            // yansımıyordu. Piyasa kapalıyken tick hiç gelmiyor ve
            // anahtar hiç işe yaramıyormuş gibi görünüyordu.
            final svc = LiveActivityService.instance;
            svc.showAmountsOnLockScreen = v;
            // Kilit ekranı widget'ı aynı tercihi okur (karar 4.4) — aynı
            // gerekçeyle hemen yazılır.
            HomeWidgetService.instance.lockScreenAmounts = v;

            final snapshot = ref.read(portfolioProvider).valueOrNull;
            if (snapshot != null) {
              CrashReporter.arkaPlan(svc.sync(
                snapshot,
                hideBalance: ref.read(balanceHiddenProvider),
              ), reason: 'settings_screen.svc.sync');
              CrashReporter.arkaPlan(
                  HomeWidgetService.instance.updateWithChart(
                    snapshot,
                    hideBalance: ref.read(balanceHiddenProvider),
                  ),
                  reason: 'settings_screen.HomeWidgetService.updateWithChart');
            }
          },
        ),
        // Kilit ekranı widget'ı nasıl eklenir (karar 4.6) — tutar ayarının
        // hemen altında: kullanıcı "bu ayar neyi yönetir"i okurken yüzeyi
        // nereden ekleyeceğini de görür.
        Padding(
          padding: const EdgeInsets.fromLTRB(
              SandikSpace.md, SandikSpace.xs, SandikSpace.md, SandikSpace.sm),
          child: Text(
            context.l10n.lockWidgetHowTo,
            style: context.t.bodySmall?.copyWith(color: context.c.text58),
          ),
        ),

        // ---- Durum satırı ----
        //
        // Pencere dışındayken kilit ekranında HİÇBİR ŞEY olmuyor ve
        // kullanıcıya bunun sebebini söyleyen tek bir işaret yoktu:
        // banner yok, hata yok, açıklama yok. Kullanıcı özelliği bozuk
        // sanıyordu. Bu satır "şu an neden görünmüyor" sorusunu yanıtlar.
        if (!visibleNow)
          Container(
            margin: const EdgeInsets.only(top: 10),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: p.amberFill.withValues(alpha: 0.10),
              borderRadius: SandikRadius.mdAll,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded, color: p.amberText, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _whyHidden(context.l10n, start, end, weekend),
                    style:
                        TextStyle(color: p.text58, fontSize: 11, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

        Padding(
          padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
          child: Text(
            exceedsAppleLimit
                ? context.l10n.liveActivityIosNote
                : context.l10n.marketClosedNote,
            style: TextStyle(color: p.text36, fontSize: 11, height: 1.35),
          ),
        ),
      ],
    );
  }

  /// Banner şu an neden görünmüyor? Kullanıcının okuyabileceği tek cümle.
  ///
  /// Hafta sonu kontrolü ÖNCE gelir: cumartesi 14:00'te hem "hafta sonu
  /// kapalı" hem "saat aralığı dışında" doğru olabilir ama kullanıcının
  /// düzeltmesi gereken ayar hafta sonu anahtarıdır.
  static String _whyHidden(
      AppLocalizations l, int start, int end, bool weekend) {
    final now = DateTime.now();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    if (!weekend && isWeekend) {
      return l.hiddenWeekend;
    }
    return l.hiddenOutsideWindow(_fmt(start), _fmt(end));
  }
}

/// Saat seçici kutusu — dokununca `showTimePicker` açar.
class _TimeBox extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;

  const _TimeBox({
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.c;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(SandikRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: context.surfaceCard(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: p.text58, fontSize: 11)),
            const SizedBox(height: 2),
            Text(
              value,
              // Tabular: iki kutu yan yana ve rakam genişliği değişirse
              // hizalama kayar.
              style: TextStyle(
                color: p.text90,
                fontSize: 20,
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Brifing saati — sabah 09:45 ya da kapanış 18:30 (0068).
///
/// Tercih SUNUCUDA (`profiles.brief_slot`): iki cron'dan hangisinin bu
/// kullanıcıya göndereceğini edge function okuyor. Türk yatırımcısının
/// alışkanlığı akşam kapanışa bakmak; sabah brifingi dünü anlatır. Seçim
/// iki uçlu, üçüncü seçenek yok (ikisi birden = çift push, bütçe dışı).
class _BriefSlotTile extends ConsumerStatefulWidget {
  const _BriefSlotTile();

  @override
  ConsumerState<_BriefSlotTile> createState() => _BriefSlotTileState();
}

class _BriefSlotTileState extends ConsumerState<_BriefSlotTile> {
  String? _slot;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _oku());
  }

  Future<void> _oku() async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final v = await SupabaseService.instance.getBriefSlot(me.id);
    if (mounted) setState(() => _slot = v);
  }

  Future<void> _yaz(String v) async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final onceki = _slot;
    setState(() => _slot = v);
    try {
      await SupabaseService.instance.setBriefSlot(me.id, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _slot = onceki);
      sandikSnack(context, 'Ayar kaydedilemedi, tekrar dene.',
          kind: SandikSnackKind.error);
    }
  }

  /// İki seçenekli sayfa. Satır içi seçici (SegmentedButton) 360pt'te
  /// taşıyordu; para birimi seçici gibi sayfa açmak hem sığar hem tutarlı.
  Future<void> _sec() async {
    final l10n = context.l10n;
    final mevcut = _slot ?? 'morning';
    final secim = await showSandikSheet<String>(
      context: context,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  SandikSpace.lg, SandikSpace.lg, SandikSpace.lg, SandikSpace.sm),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  l10n.briefSlotTitle,
                  style: ctx.t.titleMedium?.copyWith(
                    color: ctx.c.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            for (final (deger, etiket) in [
              ('morning', l10n.briefSlotMorning),
              ('evening', l10n.briefSlotEvening),
            ])
              ListTile(
                leading: Icon(
                  deger == mevcut
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  color: deger == mevcut ? ctx.c.amberText : ctx.c.text58,
                ),
                title: Text(etiket,
                    style: ctx.t.bodyLarge?.copyWith(color: ctx.c.text90)),
                onTap: () => Navigator.pop(ctx, deger),
              ),
            const SizedBox(height: SandikSpace.sm),
          ],
        ),
      ),
    );
    if (secim != null && secim != mevcut) await _yaz(secim);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final slot = _slot ?? 'morning';
    return _SettingsTile(
      icon: Icons.schedule_rounded,
      title: l10n.briefSlotTitle,
      subtitle: slot == 'evening' ? l10n.briefSlotEvening : l10n.briefSlotMorning,
      onTap: _sec,
    );
  }
}

/// Maaş günü birikim hatırlatması (0119, birikim serisi Faz 2).
///
/// Tercih SUNUCUDA (`profiles.birikim_hatirlatma_gunu`) çünkü push'u
/// `calendar-nudge` gönderiyor. Varsayılan KAPALI (opt-in): yasin kararı
/// 2026-10-05; bildirim bütçesi (RETENTION_STRATEJISI §7) kullanıcının
/// istemediği bir hatırlatmayı kaldırmaz. O ay ekleme yapan kullanıcıya
/// hiç gitmez — sayfadaki açıklama bunu söyler.
class _BirikimHatirlatmaTile extends ConsumerStatefulWidget {
  const _BirikimHatirlatmaTile();

  @override
  ConsumerState<_BirikimHatirlatmaTile> createState() =>
      _BirikimHatirlatmaTileState();
}

class _BirikimHatirlatmaTileState
    extends ConsumerState<_BirikimHatirlatmaTile> {
  int? _gun;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _oku());
  }

  Future<void> _oku() async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final v = await SupabaseService.instance.getBirikimHatirlatmaGunu(me.id);
    if (mounted) setState(() => _gun = v);
  }

  Future<void> _yaz(int? v) async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final onceki = _gun;
    setState(() => _gun = v);
    try {
      await SupabaseService.instance.setBirikimHatirlatmaGunu(me.id, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _gun = onceki);
      sandikSnack(context, 'Ayar kaydedilemedi, tekrar dene.',
          kind: SandikSnackKind.error);
    }
  }

  /// Kapalı + 31 gün. Liste kaydırılır; sayfa ekranın yarısını geçmez.
  /// "Kapalı" ayrı bir değer (0) taşır çünkü sayfanın `null` dönüşü
  /// "vazgeçti" demek.
  Future<void> _sec() async {
    final l10n = context.l10n;
    final mevcut = _gun ?? 0;
    final secim = await showSandikSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(SandikRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(ctx).height * 0.7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(SandikSpace.lg,
                    SandikSpace.lg, SandikSpace.lg, SandikSpace.xs),
                child: Text(
                  l10n.savingReminderTitle,
                  style: ctx.t.titleMedium?.copyWith(
                    color: ctx.c.text90,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(SandikSpace.lg, 0,
                    SandikSpace.lg, SandikSpace.sm),
                child: Text(
                  l10n.savingReminderSheetBody,
                  style: ctx.t.bodySmall?.copyWith(color: ctx.c.text58),
                ),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (var g = 0; g <= 31; g++)
                      ListTile(
                        leading: Icon(
                          g == mevcut
                              ? Icons.radio_button_checked_rounded
                              : Icons.radio_button_off_rounded,
                          color:
                              g == mevcut ? ctx.c.amberText : ctx.c.text58,
                        ),
                        title: Text(
                          g == 0
                              ? l10n.savingReminderOff
                              : l10n.savingReminderDay('$g'),
                          style: ctx.t.bodyLarge
                              ?.copyWith(color: ctx.c.text90),
                        ),
                        onTap: () => Navigator.pop(ctx, g),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: SandikSpace.sm),
            ],
          ),
        ),
      ),
    );
    if (secim != null && secim != mevcut) await _yaz(secim == 0 ? null : secim);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final gun = _gun;
    return _SettingsTile(
      icon: Icons.savings_outlined,
      title: l10n.savingReminderTitle,
      subtitle:
          gun == null ? l10n.savingReminderOff : l10n.savingReminderOn('$gun'),
      onTap: _sec,
    );
  }
}

/// Ortak hareketinin günlük brifingde anılması.
///
/// Tercih SUNUCUDA (`profiles.partner_activity_push`) çünkü brifingi üreten
/// edge function okuyor; cihaz tercihleri oradan görünmez. Bu yüzden diğer
/// anahtarlar gibi bir `_BoolPrefNotifier` değil — ağ okuması gerektiriyor.
///
/// **Mahremiyet notu:** bu bildirim yeni bir bilgi açmaz; ortağın lot'ları
/// zaten karşı tarafta görünüyor. Anahtar, bilgiyi değil BİLDİRİMİ kapatır.
class _PartnerActivitySwitch extends ConsumerStatefulWidget {
  const _PartnerActivitySwitch();

  @override
  ConsumerState<_PartnerActivitySwitch> createState() =>
      _PartnerActivitySwitchState();
}

class _PartnerActivitySwitchState
    extends ConsumerState<_PartnerActivitySwitch> {
  /// null = henüz okunmadı. Okuma bitene kadar anahtar AÇIK görünür çünkü
  /// sunucu varsayılanı da açık; "kapalı → açık" sıçraması yanıltırdı.
  bool? _deger;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _oku());
  }

  Future<void> _oku() async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final v = await SupabaseService.instance.getPartnerActivityPush(me.id);
    if (mounted) setState(() => _deger = v);
  }

  Future<void> _yaz(bool v) async {
    final me = ref.read(authProvider).valueOrNull;
    if (me == null) return;
    final onceki = _deger;
    // İyimser güncelleme: anahtar hemen hareket etsin, hata olursa geri alsın.
    setState(() => _deger = v);
    try {
      await SupabaseService.instance.setPartnerActivityPush(me.id, v);
    } catch (_) {
      if (!mounted) return;
      setState(() => _deger = onceki);
      sandikSnack(context, 'Ayar kaydedilemedi, tekrar dene.',
          kind: SandikSnackKind.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SwitchTile(
      icon: Icons.favorite_border_rounded,
      title: context.l10n.partnerActivityNotifications,
      subtitle: context.l10n.partnerActivityNotificationsSubtitle,
      value: _deger ?? true,
      onChanged: _yaz,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(padding: const EdgeInsets.only(bottom: 8), child: SandikCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            // `_SettingsTile` ile aynı ikon kutusu: `overlay` açık temada
            // görünmüyordu (beyaz kutu), komşu satırlar gri.
            decoration: BoxDecoration(
              color: context.c.text90.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
            child: Icon(icon, color: context.c.text90, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.t.bodyLarge?.copyWith(
                      color: context.c.text90, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: context.t.titleSmall?.copyWith(
                      color: context.c.text58, fontWeight: FontWeight.w400),
                ),
              ],
            ),
          ),
          // `Switch.adaptive` — uygulamanın öteki anahtarları gibi (Android'de
          // Material, iOS'ta Cupertino). Eskiden burada her platformda
          // Cupertino vardı; aynı listede iki anahtar dili görünüyordu.
          Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeTrackColor: context.c.amberText,
          ),
        ],
      ),
    ));
  }
}

// UH1 fix: _ThemeModeTile + _ThemeChip kaldırıldı.
// Light theme implementasyonu yapılmadan UI'da göstermek kullanıcı
// güvenini sarsıyordu. Faz 3'te gerçek light theme tasarlanınca geri gelecek.

/// Sessiz saatler — tek global pencere, tüm proaktif push'lar (brifing,
/// haftalık özet, takvim, fiyat alarmı). Sinyaller kendi tür bazlı
/// penceresini kullanır (Sinyal ayarları).
class _QuietHoursTile extends ConsumerWidget {
  const _QuietHoursTile();

  static const _defaultStart = 22;
  static const _defaultEnd = 8;

  String _fmt(int h) => '${h.toString().padLeft(2, '0')}:00';

  Future<void> _pick(BuildContext context, WidgetRef ref,
      {required bool isStart}) async {
    final cur = ref.read(quietHoursProvider).valueOrNull ?? const QuietHours();
    final start = cur.start ?? _defaultStart;
    final end = cur.end ?? _defaultEnd;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: isStart ? start : end, minute: 0),
      helpText: isStart ? context.l10n.quietStart : context.l10n.quietEnd,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    // Sunucu saat çözünürlüğünde çalışır (cron saat başı); dakika atılır.
    final h = picked.hour;
    await ref.read(quietHoursProvider.notifier).set(
          start: isStart ? h : start,
          end: isStart ? end : h,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final q = ref.watch(quietHoursProvider).valueOrNull ?? const QuietHours();
    return Column(
      children: [
        _SwitchTile(
          icon: Icons.bedtime_outlined,
          title: context.l10n.quietHours,
          subtitle: q.enabled
              ? context.l10n.quietHoursOn(_fmt(q.start!), _fmt(q.end!))
              : context.l10n.quietHoursOff,
          value: q.enabled,
          onChanged: (v) => ref.read(quietHoursProvider.notifier).set(
                start: v ? _defaultStart : null,
                end: v ? _defaultEnd : null,
              ),
        ),
        if (q.enabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: _TimeBox(
                    label: context.l10n.startTime,
                    value: _fmt(q.start!),
                    onTap: () => _pick(context, ref, isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeBox(
                    label: context.l10n.endTime,
                    value: _fmt(q.end!),
                    onTap: () => _pick(context, ref, isStart: false),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Yazı boyutu (2026-10-03). Tema/dil seçicileriyle aynı dil: dört segment.
///
/// Seçim anında tüm uygulamaya uygulanır (`YaziBoyutuKapsami`); ayrı bir
/// önizleme yok — kullanıcı bu ekranın kendisinin büyüdüğünü görür.
/// Simge boyu kademeyle büyür: etiket okunmadan da sıra anlaşılsın.
/// Sınırların gerekçesi `theme/yazi_boyutu.dart`'ta.
class _YaziBoyutuPicker extends ConsumerWidget {
  const _YaziBoyutuPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(yaziBoyutuProvider);
    final l = context.l10n;
    final options = <(YaziBoyutu, double, String)>[
      (YaziBoyutu.kucuk, 16, l.textSizeSmall),
      (YaziBoyutu.normal, 19, l.textSizeNormal),
      (YaziBoyutu.buyuk, 22, l.textSizeLarge),
      (YaziBoyutu.cokBuyuk, 25, l.textSizeXLarge),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SubSectionTitle(l.textSize),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(SandikSpace.xs),
          decoration: context.surfaceCard(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (boyut, ikonBoyu, label) in options)
                Expanded(
                  child: SandikTappable(
                    semanticLabel: l.textSizeSemantics(label),
                    selected: current == boyut,
                    onTap: () => ref
                        .read(yaziBoyutuIndexProvider.notifier)
                        .set(boyut.index),
                    child: AnimatedContainer(
                      duration: SandikMotion.stateOf(context),
                      curve: SandikMotion.enter,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: current == boyut
                            ? context.c.amberFill.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: SandikRadius.smAll,
                      ),
                      child: Column(
                        children: [
                          // Simgeler alt çizgiye hizalı dursun: en büyüğün
                          // kutusu, küçükler altına oturur.
                          SizedBox(
                            height: 25,
                            child: Align(
                              alignment: Alignment.bottomCenter,
                              child: Icon(
                                Icons.text_fields_rounded,
                                size: ikonBoyu,
                                color: current == boyut
                                    ? context.c.amberText
                                    : context.c.text36,
                              ),
                            ),
                          ),
                          const SizedBox(height: SandikSpace.xs),
                          Text(
                            label,
                            textAlign: TextAlign.center,
                            style: context.t.labelLarge?.copyWith(
                              letterSpacing: 0,
                              fontWeight: current == boyut
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: current == boyut
                                  ? context.c.amberText
                                  : context.c.text58,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            l.textSizeNote,
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
          ),
        ),
      ],
    );
  }
}

/// Balina radarı ayarları (S19-A, 2026-10-05) — Bildirimler bölümünde iki
/// anahtar. Yalnız bayrak açıkken görünür; kapalıyken anlatacak özellik yok.
///
/// "Pazartesi özetinde hareket satırı" SUNUCUDA (0118
/// `profiles.haftalik_hareket_satiri`): cümleyi kuran weekly-summary. Açılışta
/// okunur; okunamazsa anahtar gösterilmez (yanlış bir "açık" göstermektense).
/// "Sakin varlıkları göster" yereldir, yalnız Haftanın özeti ekranını
/// etkiler.
class _RadarAyarlari extends ConsumerStatefulWidget {
  const _RadarAyarlari();

  @override
  ConsumerState<_RadarAyarlari> createState() => _RadarAyarlariState();
}

class _RadarAyarlariState extends ConsumerState<_RadarAyarlari> {
  bool? _hareketSatiri;

  @override
  void initState() {
    super.initState();
    _oku();
  }

  Future<void> _oku() async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    try {
      final v = await SupabaseService.instance.haftalikHareketSatiri(uid);
      if (mounted) setState(() => _hareketSatiri = v ?? true);
    } catch (e, st) {
      CrashReporter.report(e, st, reason: '_RadarAyarlari._oku');
    }
  }

  Future<void> _yaz(bool v) async {
    final uid = ref.read(authProvider).valueOrNull?.id;
    if (uid == null) return;
    final onceki = _hareketSatiri;
    setState(() => _hareketSatiri = v);
    try {
      await SupabaseService.instance.setHaftalikHareketSatiri(uid, v);
    } catch (e) {
      if (!mounted) return;
      setState(() => _hareketSatiri = onceki);
      showAppError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      children: [
        if (_hareketSatiri != null)
          _SwitchTile(
            icon: Icons.radar_rounded,
            title: l10n.rdrAyarHareketSatiri,
            subtitle: l10n.rdrAyarHareketSatiriAlt,
            value: _hareketSatiri!,
            onChanged: _yaz,
          ),
        _SwitchTile(
          icon: Icons.format_list_bulleted_rounded,
          title: l10n.rdrAyarSakinGoster,
          subtitle: l10n.rdrAyarSakinGosterAlt,
          value: ref.watch(haftaSakinGosterProvider),
          onChanged: (v) => ref.read(haftaSakinGosterProvider.notifier).set(v),
        ),
      ],
    );
  }
}
