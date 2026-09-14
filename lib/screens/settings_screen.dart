import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/base_currency_provider.dart';
import '../models/yatirimci_seviyesi.dart';
import '../providers/price_alert_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../l10n/l10n.dart';
import '../providers/quiet_hours_provider.dart';
import '../services/data_export_service.dart';
import '../services/auth_service.dart';
import '../services/social_auth_service.dart';
import '../services/biometric_lock_service.dart';
import '../services/disclaimer_service.dart';
import '../services/supabase_service.dart';
import '../services/live_activity_service.dart';
import '../theme/sandik.dart';
import '../widgets/sandik_app_bar.dart';
import '../utils/sandik_snack.dart';
import '../utils/friendly_error.dart';
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
  bool _exporting = false;

  static const _supportEmail = 'sandikapp.destek@gmail.com';

  Future<void> _confirmDeleteAccount() async {
    if (_deleting) return;
    // 1. Kademe — uyarı
    final firstConfirm = await showSandikConfirm(
      context: context,
      title: 'Hesabını silmek üzeresin',
      message: 'Bu işlem GERİ ALINAMAZ.\n\n'
          'Tüm portföy kayıtların, performans geçmişin ve ortaklık '
          'bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\n'
          'Devam etmek istiyor musun?',
      confirmLabel: 'Devam et',
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
        title: 'Kimliğini doğrula',
        message: 'Hesabın Apple/Google ile açılmış. Silmeden önce aynı '
            'hesapla bir kez daha giriş yapman istenecek.',
        confirmLabel: 'Devam et',
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
    final secondConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          backgroundColor: context.c.surface2,
          title: Text('Şifrenle onayla',
              style: TextStyle(color: context.c.text90)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Güvenliğin için şifrenle onay vermen gerekiyor.',
                style: TextStyle(color: context.c.text58, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                autofocus: true,
                style: TextStyle(color: context.c.text90),
                decoration: context.inputDecoration(
                  'Şifre',
                  prefixIcon: Icon(Icons.lock_outline,
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
              child: Text('HESABI SİL',
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
        title: 'Hesabın silindi',
        message: 'Görüşmek üzere.',
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

  Future<void> _exportData() async {
    if (_exporting) return;
    setState(() => _exporting = true);
    try {
      await DataExportService.instance.exportAndShare();
      if (!mounted) return;
      sandikSnack(
          context, 'Verilerin JSON dosyası olarak hazırlandı ve paylaşıldı.',
          kind: SandikSnackKind.success, duration: const Duration(seconds: 4));
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showDisclaimerText() {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.c.surface2,
        title: Row(
          children: [
            Icon(Icons.gavel_rounded, color: context.c.amberText, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yatırım Tavsiyesi Reddi',
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
            child: Text('Kapat', style: TextStyle(color: context.c.amberText)),
          ),
        ],
      ),
    );
  }

  void _showLegalDoc(String title, List<LegalBlock> blocks, IconData icon) {
    Navigator.push(
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
          'Mail uygulaması açılamadı. Lütfen $_supportEmail adresine yaz.',
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
    final result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.c.surface2,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (ctx, setLocal) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Şikayet & Tavsiye',
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
                  maxLines: 6,
                  minLines: 4,
                  style: TextStyle(color: context.c.text90),
                  decoration: InputDecoration(
                    hintText: 'Mesajınızı yazın…',
                    hintStyle: TextStyle(color: context.c.text36),
                    filled: true,
                    fillColor: context.c.surface1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      borderSide: BorderSide.none,
                    ),
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
                  child: const Text('Gönder',
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
                          'Hesabın siliniyor…',
                          style: context.t.titleMedium
                              ?.copyWith(color: context.c.text90),
                        ),
                        SizedBox(height: SandikSpace.xs),
                        Text(
                          'Bu işlem birkaç saniye sürebilir. Uygulamayı kapatma.',
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

  void _bolumAc(SettingsBolum b) => Navigator.of(context).push(
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
              ? 'Sinyaller, fiyat alarmları, sessiz saatler, Canlı Etkinlik'
              : 'Sinyaller, fiyat alarmları, sessiz saatler',
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
              const SandikSectionHeader(title: 'TANILAMA'),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Push Teşhisi',
                subtitle: 'Bildirim zincirinin neresi kopuk; '
                    'cihaz APNs/FCM token durumu',
                onTap: () => Navigator.of(context).push(
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
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'sandık — sürüm 1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: context.c.text36,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(height: 40),
      ];

  List<Widget> _gorunum() => [
            const SizedBox(height: 4),
            const _ThemeModePicker(),
            const SizedBox(height: 12),
            const _BaseCurrencyPicker(),
            const SizedBox(height: 12),
            const _InvestorLevelPicker(),
            const SizedBox(height: 12),
            const _LanguagePicker(),
            const SizedBox(height: 24),

      ];

  List<Widget> _bildirimler() => [
            const SandikSectionHeader(title: 'BİLDİRİMLER'),
            const SizedBox(height: 12),
            _SwitchTile(
              icon: Icons.notifications_active_outlined,
              title: 'Teknik sinyal bildirimleri',
              subtitle: 'AL/SAT göstergesi tetiklendiğinde bildirim al',
              value: ref.watch(signalNotificationsProvider),
              onChanged: (v) async {
                await ref.read(signalNotificationsProvider.notifier).set(v);
                // Sunucuya da yaz: sinyal push'unu sunucu gönderiyor, bu
                // anahtar orada bilinmezse kapatmak işe yaramaz.
                await syncSignalsEnabledPreference(ref);
              },
            ),
            _SettingsTile(
              icon: Icons.tune_rounded,
              title: 'Sinyal ayarları',
              subtitle: 'Her varlık türü için gösterge seçimi + Premium',
              onTap: () => Navigator.push(
                context,
                adaptiveRoute<void>(builder: (_) => const SignalSettingsScreen()),
              ),
            ),
            // Alarm KURMA yeri varlık ekranıdır (zil ikonu); burada yalnızca
            // liste. Alt satır aktif sayısını söyler ki hub'dan bakan kişi
            // ekrana girmeden durumu görsün.
            _SettingsTile(
              icon: Icons.add_alert_outlined,
              title: 'Fiyat alarmları',
              subtitle: () {
                final aktif = ref
                        .watch(priceAlertsProvider)
                        .valueOrNull
                        ?.where((a) => a.isActive)
                        .length ??
                    0;
                return aktif == 0
                    ? 'Varlık ekranındaki zil ile kurulur'
                    : '$aktif aktif alarm';
              }(),
              onTap: () => Navigator.push(
                context,
                adaptiveRoute<void>(builder: (_) => const PriceAlertsScreen()),
              ),
            ),
            const _QuietHoursTile(),
            const SizedBox(height: 8),
            _SwitchTile(
              icon: Icons.people_outline_rounded,
              title: 'Ortaklık daveti bildirimleri',
              subtitle: 'Yeni ortaklık isteği geldiğinde bildirim al',
              value: ref.watch(partnerNotificationsProvider),
              onChanged: (v) =>
                  ref.read(partnerNotificationsProvider.notifier).set(v),
            ),
            // Ortağı OLMAYAN kullanıcıya gösterilmez: kapatacak bir şeyi
            // yokken sunulan anahtar, ayar listesini uzatmaktan başka işe
            // yaramaz ve "bu ne?" sorusu doğurur.
            if (ref.watch(activePartnersProvider).isNotEmpty)
              const _PartnerActivitySwitch(),
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
              const SandikSectionHeader(title: 'CANLI ETKİNLİKLER'),
              const SizedBox(height: 12),
              const _LiveActivitySection(),
              const SizedBox(height: 28),
            ],

      ];

  List<Widget> _hesap() => [
            const SizedBox(height: 4),
            _SwitchTile(
              icon: Icons.fingerprint_rounded,
              title: 'Biyometrik kilit',
              subtitle:
                  'Uygulamayı açarken Face ID / parmak izi / cihaz PIN\'i iste',
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
                        'Bu cihazda biyometrik doğrulama ya da PIN tanımlı değil.',
                        kind: SandikSnackKind.warning);
                    return;
                  }
                  final ok = await svc.authenticate(
                      reason: 'Biyometrik kilidi açmak için kimliğini doğrula');
                  if (!ok) return;
                }
                await ref.read(biometricLockProvider.notifier).set(v);
              },
            ),
            _SettingsTile(
              icon: Icons.download_outlined,
              title: 'Verilerimi İndir',
              subtitle: 'Tüm verilerini JSON dosyası olarak al (KVKK Madde 11)',
              trailing:
                  _exporting ? const CustomLoadingIndicator(size: 18) : null,
              onTap: _exporting ? null : _exportData,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_outlined,
              title: 'Hesabımı Sil',
              subtitle: 'Tüm verilerin kalıcı olarak silinir',
              destructive: true,
              trailing:
                  _deleting ? const CustomLoadingIndicator(size: 18) : null,
              onTap: _deleting ? null : _confirmDeleteAccount,
            ),
      ];

  List<Widget> _yardim() => [
            const SandikSectionHeader(title: 'DESTEK'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Bize Ulaş',
              subtitle: _supportEmail,
              onTap: () => _sendMail(subject: 'Sandık uygulama iletişim'),
            ),
            _SettingsTile(
              icon: Icons.explore_outlined,
              title: 'Tanıtım turunu yeniden izle',
              subtitle: 'Ekranların ne işe yaradığını hatırla',
              // Tur gerçek sekmelerin üstünde çalışır; Ayarlar kapanır,
              // köke dönülür ve katman orada açılır.
              onTap: () => OnboardingScreen.yenidenBaslat(context),
            ),
            _SettingsTile(
              icon: Icons.rate_review_outlined,
              title: 'Şikayet & Tavsiye',
              subtitle: 'Görüşünü bize ilet',
              onTap: _openFeedbackSheet,
            ),
            const SizedBox(height: 28),
            const SandikSectionHeader(title: 'YASAL'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Gizlilik Politikası',
              subtitle: 'Verilerin nasıl işleniyor',
              onTap: () => _showLegalDoc('Gizlilik Politikası',
                  LegalDocs.privacy, Icons.privacy_tip_outlined),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Kullanım Koşulları',
              subtitle: 'Hizmet sözleşmesi',
              onTap: () => _showLegalDoc(
                  'Kullanım Koşulları', LegalDocs.terms, Icons.gavel_outlined),
            ),
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: 'KVKK Aydınlatma Metni',
              subtitle: 'Kişisel veri işleme aydınlatması',
              onTap: () => _showLegalDoc('KVKK Aydınlatma Metni',
                  LegalDocs.kvkk, Icons.shield_outlined),
            ),
            _SettingsTile(
              icon: Icons.gavel_rounded,
              title: 'Yatırım Tavsiyesi Reddi',
              subtitle: 'Onayladığın yasal uyarı metnini görüntüle',
              onTap: _showDisclaimerText,
            ),
            const SizedBox(height: 28),
      ];
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
/// `MaterialApp.themeMode`'u besler. Varsayılan koyudur: sandık dark-first
/// bir markadır, sistem takibi kullanıcının açık tercihidir.
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
                semanticLabel: '$label tema',
                // Uygulama DIŞI yüzeylere (kilit ekranı + widget) itiş
                // BURADA YAPILMAZ.
                //
                // Tercihi yazmak yeterli: itişi `main.dart`'taki tek
                // `themeModeProvider` dinleyicisi üstlenir (bkz.
                // `_applySurfaceTheme`). Eskiden her ekran kendi itişini
                // yapıyordu ve Profil başlığındaki hızlı geçiş bunu
                // atlıyordu — aynı tercih iki yoldan değiştirildiğinde
                // yüzeyler ayrışıyordu.
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
                    semanticLabel: 'Baz para birimi ${birim.label}',
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
                            birim.kod == 'ALTIN' ? 'Altın' : birim.kod,
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
                ? 'Kur henüz çekilmedi; tutarlar şimdilik ₺ görünür.'
                : 'Tutarlar bugünkü kurla ${baz.etkinBirim.label.toLowerCase()} '
                    'cinsinden gösterilir; hesaplar ₺ üzerinden yapılır.',
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
                    semanticLabel: '${s.etiket(context)} seviye',
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
            '${current.aciklama(context)} ${context.l10n.investorLevelNote}',
            style: context.t.bodySmall?.copyWith(color: context.c.text36),
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool destructive;
  final Widget? trailing;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final color = destructive ? context.c.loss : context.c.text90;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
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
                  Text(
                    title,
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: context.c.text58,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                Icon(Icons.chevron_right, color: context.c.text36, size: 20),
          ],
        ),
      ),
    );
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
      helpText: isStart ? 'Başlangıç saati' : 'Bitiş saati',
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
          title: 'Gün boyu göster',
          subtitle: 'Kapalıyken yalnızca seçtiğin saat aralığında görünür.',
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
              'Gösterim aralığı',
              style: TextStyle(
                  color: p.text90, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _TimeBox(
                  label: 'Başlangıç',
                  value: _fmt(start),
                  onTap: () => _pick(context, ref, isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _TimeBox(
                  label: 'Bitiş',
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
          title: 'Hafta sonu da göster',
          subtitle: 'Hafta sonu BIST kapalıdır; banner son kapanışı '
              '"Piyasa kapalı" etiketiyle gösterir.',
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
          title: 'Tutarları göster',
          subtitle: 'Kapalıyken yalnızca günlük yüzde ve grafik görünür. '
              'Kilit ekranı telefonunuz açılmadan görülebildiği için '
              'varsayılan olarak kapalıdır.',
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

            final snapshot = ref.read(portfolioProvider).valueOrNull;
            if (snapshot != null) {
              unawaited(svc.sync(
                snapshot,
                hideBalance: ref.read(balanceHiddenProvider),
              ));
            }
          },
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
                    _whyHidden(start, end, weekend),
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
                ? 'iOS, Live Activity oturumunu en fazla 8 saat açık '
                    'tutar. Uygulamayı açtıkça süre yenilenir; hiç '
                    'açmazsanız kilit ekranından düşebilir.'
                : 'Piyasa kapalıyken son kapanış gösterilir.',
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
  static String _whyHidden(int start, int end, bool weekend) {
    final now = DateTime.now();
    final isWeekend =
        now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    if (!weekend && isWeekend) {
      return 'Şu an görünmüyor: hafta sonu gösterimi kapalı. '
          'Açmak için yukarıdaki anahtarı kullanın.';
    }
    return 'Şu an görünmüyor: saat ${_fmt(start)}–${_fmt(end)} aralığının '
        'dışındasınız. Banner ${_fmt(start)}\'da görünecek. Hemen görmek '
        'için "Gün boyu göster"i açın.';
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
      title: 'Ortak hareketi bildirimleri',
      subtitle: 'Ortağın portföyüne ekleme yaptığında günlük özette an',
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
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: context.c.hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: context.c.overlay,
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
                  style: TextStyle(
                    color: context.c.text90,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: context.c.text58,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: context.c.amberText,
          ),
        ],
      ),
    );
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
      helpText: isStart ? 'Sessizlik başlangıcı' : 'Sessizlik bitişi',
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
          title: 'Sessiz saatler',
          subtitle: q.enabled
              ? 'Brifing, özet, takvim ve alarm push\'ları '
                  '${_fmt(q.start!)}–${_fmt(q.end!)} arası gönderilmez'
              : 'Gece belirli saatlerde hiçbir proaktif bildirim gelmesin',
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
                    label: 'Başlangıç',
                    value: _fmt(q.start!),
                    onTap: () => _pick(context, ref, isStart: true),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _TimeBox(
                    label: 'Bitiş',
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
