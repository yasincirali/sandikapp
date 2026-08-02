import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_provider.dart';
import '../providers/preferences_provider.dart';
import '../services/data_export_service.dart';
import '../services/disclaimer_service.dart';
import '../theme/sandik.dart';
import '../utils/friendly_error.dart';
import 'legal_doc_screen.dart';
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
        backgroundColor: Sandik.surface2,
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Sandik.loss),
            SizedBox(width: 8),
            Text('Hesabını silmek üzeresin',
                style: TextStyle(color: Colors.white)),
          ],
        ),
        content: const Text(
          'Bu işlem GERİ ALINAMAZ.\n\n'
          'Tüm portföy kayıtların, performans geçmişin ve ortaklık '
          'bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\n'
          'Devam etmek istiyor musun?',
          style: TextStyle(color: Sandik.text90),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç',
                style: TextStyle(color: Sandik.text58)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Devam Et',
                style: TextStyle(color: Sandik.loss)),
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
          backgroundColor: Sandik.surface2,
          title: const Text('Şifrenle onayla',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Güvenliğin için şifrenle onay vermen gerekiyor.',
                style: TextStyle(color: Sandik.text58, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: passwordCtrl,
                obscureText: obscure,
                autofocus: true,
                style: const TextStyle(color: Colors.white),
                decoration: Sandik.inputDecoration(
                  'Şifre',
                  prefixIcon: const Icon(Icons.lock_outline,
                      color: Sandik.text36, size: 20),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Sandik.text36,
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
              child: const Text('Vazgeç',
                  style: TextStyle(color: Sandik.text58)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              child: const Text('HESABI SİL',
                  style: TextStyle(
                      color: Sandik.loss, fontWeight: FontWeight.bold)),
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
        backgroundColor: Sandik.surface2,
        title: const Row(
          children: [
            Icon(Icons.gavel_rounded, color: Sandik.amber, size: 20),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Yatırım Tavsiyesi Reddi',
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            Text(
              'v$disclaimerVersion',
              style: TextStyle(color: Sandik.text36, fontSize: 11),
            ),
          ],
        ),
        content: const SingleChildScrollView(
          child: Text(
            disclaimerText,
            style: TextStyle(
              color: Sandik.text90,
              fontSize: 13,
              height: 1.55,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat',
                style: TextStyle(color: Sandik.amber)),
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
      backgroundColor: Sandik.surface2,
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
                    color: Colors.white,
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
                          selectedColor: Sandik.amber.withValues(alpha: 0.25),
                          backgroundColor: Sandik.surface1,
                          labelStyle: TextStyle(
                            color: type == t ? Sandik.amber : Sandik.text58,
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
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    hintText: 'Mesajınızı yazın…',
                    hintStyle: const TextStyle(color: Sandik.text36),
                    filled: true,
                    fillColor: Sandik.surface1,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(SandikRadius.md),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Sandik.amber,
                    foregroundColor: Colors.black,
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
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Sandik.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Ayarlar',
          style: context.t.headlineMedium?.copyWith(
            color: Colors.white,
          ),
        ),
      ),
      body: AbsorbPointer(
        absorbing: _deleting,
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          children: [
            // UH1 fix: Açık tema implementasyonu yok — "deneysel" diye
            // göstermek kullanıcı güvenini sarsıyor. Tema seçici tamamen
            // kaldırıldı; uygulama dark-first kalıyor. Gerçek light tema
            // Faz 3'te eklendiğinde geri gelecek.
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
            const _SectionTitle('SOSYAL'),
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
            const _SectionTitle('SİNYALLER'),
            const SizedBox(height: 12),
            _SettingsTile(
              icon: Icons.tune_rounded,
              title: 'Sinyal Ayarları',
              subtitle: 'Her varlık türü için gösterge seçimi + Premium',
              onTap: () => Navigator.push(
                context,
                adaptiveRoute(
                    builder: (_) => const SignalSettingsScreen()),
              ),
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
            // Debug-only: Crashlytics test
            if (kDebugMode) ...[
              const SizedBox(height: 28),
              const _SectionTitle('GELİŞTİRİCİ'),
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
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'sandık — sürüm 1.0.0',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Sandik.text36,
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
          color: Sandik.text36,
          letterSpacing: 1.2,
        ),
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
    final color = destructive ? Sandik.loss : Colors.white;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
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
                    style: const TextStyle(
                      color: Sandik.text58,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right,
                    color: Sandik.text36, size: 20),
          ],
        ),
      ),
    );
  }
}

/// Açma/kapama anahtarlı ayar satırı.
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
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(SandikRadius.md),
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Sandik.text58,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: Sandik.amber,
          ),
        ],
      ),
    );
  }
}

// UH1 fix: _ThemeModeTile + _ThemeChip kaldırıldı.
// Light theme implementasyonu yapılmadan UI'da göstermek kullanıcı
// güvenini sarsıyordu. Faz 3'te gerçek light theme tasarlanınca geri gelecek.
