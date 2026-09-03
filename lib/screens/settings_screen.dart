import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kDebugMode, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/data_export_service.dart';
import '../services/disclaimer_service.dart';
import '../services/home_widget_service.dart';
import '../services/live_activity_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import '../utils/theme_resolution.dart';
import 'legal_doc_screen.dart';
import 'push_diagnostics_screen.dart';
import 'signal_settings_screen.dart';
import '../widgets/custom_loading_indicator.dart';

/// Profil → Ayarlar ekranı.
///
/// İçerik:
/// - Yasal belgeler (Gizlilik Politikası, Kullanım Koşulları, KVKK)
/// - Disclaimer'ı tekrar görüntüleme
/// - Hesabımı sil (yasal zorunluluk: Play 2024 + App Store 5.1.1(v))
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;
  bool _exporting = false;

  static const _supportEmail = 'sandikapp.destek@gmail.com';

  Future<void> _confirmDeleteAccount() async {
    // 1. Kademe — uyarı
    final firstConfirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        backgroundColor: context.c.surface2,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: context.c.loss),
            const SizedBox(width: 8),
            Text('Hesabını silmek üzeresin',
                style: TextStyle(color: context.c.text90)),
          ],
        ),
        content: Text(
          'Bu işlem GERİ ALINAMAZ.\n\n'
          'Tüm portföy kayıtların, performans geçmişin ve ortaklık '
          'bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\n'
          'Devam etmek istiyor musun?',
          style: TextStyle(color: context.c.text90),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Vazgeç',
                style: TextStyle(color: context.c.text58)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Devam Et',
                style: TextStyle(color: context.c.loss)),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !mounted) return;

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
              child: Text('Vazgeç',
                  style: TextStyle(color: context.c.text58)),
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

    setState(() => _deleting = true);
    try {
      // Provider üzerinden çağır — auth state'i null'a çekip AuthGate'in
      // otomatik olarak LoginScreen'e dönmesini sağlar. Doğrudan
      // AuthService.deleteAccount çağrılırsa state güncellenmez ve
      // kullanıcı silinmiş olsa da ekranda kalır.
      await ref
          .read(authProvider.notifier)
          .deleteAccount(password: passwordCtrl.text);
      if (!mounted) return;
      // Açık olabilecek modal'ları kapatıp root'a dön.
      Navigator.of(context).popUntil((r) => r.isFirst);
      if (!mounted) return;
      await showAppSuccess(
        context,
        title: 'Hesabın silindi',
        message: 'Görüşmek üzere.',
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Verilerin JSON dosyası olarak hazırlandı ve paylaşıldı.'),
          duration: Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppError(context, e);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showDisclaimerText() {
    showDialog(
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
            child: Text('Kapat',
                style: TextStyle(color: context.c.amberText)),
          ),
        ],
      ),
    );
  }

  void _showLegalDoc(String title, List<LegalBlock> blocks, IconData icon) {
    Navigator.push(
      context,
      adaptiveRoute(
        builder: (_) => LegalDocScreen(title: title, blocks: blocks, icon: icon),
      ),
    );
  }

  Future<void> _sendMail({
    required String subject,
    String body = '',
  }) async {
    final userEmail = ref.read(authProvider).valueOrNull?.email ?? '';
    final signature = userEmail.isNotEmpty
        ? '\n\n---\nKullanıcı: $userEmail'
        : '';
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Mail uygulaması açılamadı. Lütfen $_supportEmail adresine yazın.'),
        ),
      );
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
                          selectedColor: context.c.amberFill.withValues(alpha: 0.25),
                          backgroundColor: context.c.surface1,
                          labelStyle: TextStyle(
                            color: type == t ? context.c.amberText : context.c.text58,
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
    return Scaffold(
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: context.c.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded,
              color: context.c.text90, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ayarlar',
          style: context.t.headlineMedium?.copyWith(
            color: context.c.text90,
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _deleting,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            const _SectionTitle('GÖRÜNÜM'),
            const SizedBox(height: 12),
            const _ThemeModePicker(),
            const SizedBox(height: 24),

            // -- BİLDİRİMLER ---------------------------------------
            //
            // Sinyalle ilgili İKİ ayar vardı ve iki ayrı bölümdeydi:
            // bildirim anahtarı "BİLDİRİMLER"de, gösterge seçimi
            // "SİNYALLER"de. Kullanıcı sinyalleri ayarlamak istediğinde
            // ekranda iki farklı yere bakmak zorundaydı. Aynı özelliğin
            // parçaları bir arada durur.
            const _SectionTitle('BİLDİRİMLER'),
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
                adaptiveRoute(
                    builder: (_) => const SignalSettingsScreen()),
              ),
            ),
            _SwitchTile(
              icon: Icons.people_outline_rounded,
              title: 'Ortaklık daveti bildirimleri',
              subtitle: 'Yeni ortaklık isteği geldiğinde bildirim al',
              value: ref.watch(partnerNotificationsProvider),
              onChanged: (v) => ref
                  .read(partnerNotificationsProvider.notifier)
                  .set(v),
            ),
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
              const _SectionTitle('CANLI ETKİNLİKLER'),
              const SizedBox(height: 12),
              const _LiveActivitySection(),
              const SizedBox(height: 28),
            ],

            // -- ORTAKLIK ------------------------------------------
            //
            // Tek satırlık "SOSYAL" bölümüydü; adı artık içeriğiyle
            // eşleşiyor.
            const _SectionTitle('ORTAKLIK'),
            const SizedBox(height: 12),
            _SwitchTile(
              icon: Icons.emoji_events_outlined,
              title: 'Yarış\'a katıl',
              subtitle:
                  'Ortaklarınla getiri sıralaması. Sadece kaydolan ortaklar '
                  'birbirinin yüzdesini görebilir; hangi varlıklara sahip '
                  'olduğunu asla göstermez.',
              value: ref.watch(leaderboardOptInProvider),
              onChanged: (v) =>
                  ref.read(leaderboardOptInProvider.notifier).set(v),
            ),
            const SizedBox(height: 28),
            const _SectionTitle('YASAL'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Gizlilik Politikası',
              subtitle: 'Verilerin nasıl işleniyor',
              onTap: () => _showLegalDoc('Gizlilik Politikası', LegalDocs.privacy, Icons.privacy_tip_outlined),
            ),
            _SettingsTile(
              icon: Icons.gavel_outlined,
              title: 'Kullanım Koşulları',
              subtitle: 'Hizmet sözleşmesi',
              onTap: () => _showLegalDoc('Kullanım Koşulları', LegalDocs.terms, Icons.gavel_outlined),
            ),
            _SettingsTile(
              icon: Icons.shield_outlined,
              title: 'KVKK Aydınlatma Metni',
              subtitle: 'Kişisel veri işleme aydınlatması',
              onTap: () => _showLegalDoc('KVKK Aydınlatma Metni', LegalDocs.kvkk, Icons.shield_outlined),
            ),
            _SettingsTile(
              icon: Icons.gavel_rounded,
              title: 'Yatırım Tavsiyesi Reddi',
              subtitle: 'Onayladığın yasal uyarı metnini görüntüle',
              onTap: _showDisclaimerText,
            ),
            const SizedBox(height: 28),
            const _SectionTitle('DESTEK'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.mail_outline_rounded,
              title: 'Bize Ulaş',
              subtitle: _supportEmail,
              onTap: () => _sendMail(subject: 'Sandık uygulama iletişim'),
            ),
            _SettingsTile(
              icon: Icons.rate_review_outlined,
              title: 'Şikayet & Tavsiye',
              subtitle: 'Görüşünü bize ilet',
              onTap: _openFeedbackSheet,
            ),
            const SizedBox(height: 28),
            const _SectionTitle('HESAP'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.download_outlined,
              title: 'Verilerimi İndir',
              subtitle: 'Tüm verilerini JSON dosyası olarak al (KVKK Madde 11)',
              trailing: _exporting
                  ? const CustomLoadingIndicator(size: 18)
                  : null,
              onTap: _exporting ? null : _exportData,
            ),
            _SettingsTile(
              icon: Icons.delete_forever_outlined,
              title: 'Hesabımı Sil',
              subtitle: 'Tüm verilerin kalıcı olarak silinir',
              destructive: true,
              trailing: _deleting
                  ? const CustomLoadingIndicator(size: 18)
                  : null,
              onTap: _deleting ? null : _confirmDeleteAccount,
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
            ...[
              const SizedBox(height: 28),
              const _SectionTitle('GELİŞTİRİCİ'),
              const SizedBox(height: 12),
              _SettingsTile(
                icon: Icons.notifications_active_outlined,
                title: 'Push Teşhisi',
                subtitle:
                    'cron → edge function → FCM zincirinin neresi kopuk; '
                    'cihaz APNs/FCM token durumu',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const PushDiagnosticsScreen(),
                  ),
                ),
              ),
              if (kDebugMode) ...[
                const SizedBox(height: 8),
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
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Text(
        text,
        style: context.t.titleSmall?.copyWith(
          fontWeight: FontWeight.w600,
          // Bölüm başlığı yapısal bilgidir — text36 (3.79:1) yalnızca
          // yardımcı metin eşiğini geçer, light modda okunmuyordu.
          color: context.c.text58,
          letterSpacing: 1.2,
        ),
      ),
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
/// `MaterialApp.themeMode`'u besler. Varsayılan koyudur: sandık dark-first
/// bir markadır, sistem takibi kullanıcının açık tercihidir.
class _ThemeModePicker extends ConsumerWidget {
  const _ThemeModePicker();

  static const _options = <(ThemeMode, IconData, String)>[
    (ThemeMode.system, Icons.brightness_auto_rounded, 'Sistem'),
    (ThemeMode.light, Icons.light_mode_rounded, 'Açık'),
    (ThemeMode.dark, Icons.dark_mode_rounded, 'Koyu'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);

    return Container(
      padding: const EdgeInsets.all(SandikSpace.xs),
      decoration: context.surfaceCard(),
      child: Row(
        children: [
          for (final (mode, icon, label) in _options)
            Expanded(
              child: SandikTappable(
                semanticLabel: '$label tema',
                onTap: () {
                  ref.read(themeModeProvider.notifier).set(mode);
                  // Uygulama DIŞI yüzeyler de hemen dönsün.
                  //
                  // Bunlar servis singleton'ları üzerinden beslenir ve
                  // provider okuyamazlar; tercih dışarıdan itilir (kilit
                  // ekranı saat/tutar ayarlarındaki desenin aynısı). Burada
                  // itilmezse widget bir sonraki portföy tazelemesine kadar
                  // eski temada kalırdı — kullanıcı ayarı değiştirip ana
                  // ekrana çıktığında değişmemiş görürdü.
                  final isLight = resolveThemeIsLightNow(mode);
                  LiveActivityService.instance.themeIsLight = isLight;
                  unawaited(HomeWidgetService.instance.applyTheme(isLight));
                },
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
                Icon(Icons.chevron_right,
                    color: context.c.text36, size: 20),
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
    final current = ref.read(
        isStart ? liveActivityStartProvider : liveActivityEndProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: current ~/ 60, minute: current % 60),
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
          subtitle:
              'Kapalıyken yalnızca günlük yüzde ve grafik görünür. '
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
                Icon(Icons.info_outline_rounded,
                    color: p.amberText, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _whyHidden(start, end, weekend),
                    style: TextStyle(
                        color: p.text58, fontSize: 11, height: 1.35),
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
    final isWeekend = now.weekday == DateTime.saturday ||
        now.weekday == DateTime.sunday;

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
            Text(label,
                style: TextStyle(color: p.text58, fontSize: 11)),
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
