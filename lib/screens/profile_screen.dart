import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../services/auth_service.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _codeCtrl = TextEditingController();
  String? _generatedCode;
  bool _generating = false;
  bool _redeeming = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _generateCode() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() => _generating = true);
    try {
      final code = await AuthService.instance.generatePartnerCode(user.id);
      setState(() => _generatedCode = code);
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Kod üretildi ve panoya kopyalandı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  Future<void> _redeemCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _redeeming = true);
    try {
      // Check current partner count to detect new vs resync
      final partnersBefore =
          ref.read(partnersProvider).valueOrNull?.length ?? 0;
      final name = await ref.read(partnersProvider.notifier).redeemCode(code);
      _codeCtrl.clear();

      // Always invalidate partner assets so UI reflects updated DB
      ref.invalidate(allPartnerAssetsProvider);

      final partnersAfter =
          ref.read(partnersProvider).valueOrNull?.length ?? 0;
      final isNewPartnership = partnersAfter > partnersBefore;

      final user = ref.read(authProvider).valueOrNull;
      if (mounted && user != null && isNewPartnership) {
        final returnCode =
            await AuthService.instance.generatePartnerCode(user.id);
        if (mounted) _showReturnCodeSheet(name, returnCode);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$name\'in varlıkları güncellendi.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  void _showReturnCodeSheet(String partnerName, String returnCode) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Sandik.text36,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Sandik.gain.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: Sandik.gain, size: 32),
            ),
            const SizedBox(height: 16),
            Text(
              '$partnerName ile Ortaklık Kuruldu!',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              '$partnerName artık portföyünüzü görebilir. Siz de onların portföyünü görmek için bu kodu paylaşın:',
              style: GoogleFonts.inter(fontSize: 13, color: Sandik.text58),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      returnCode.split(':')[0],
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Sandik.amber,
                        letterSpacing: 4,
                      ),
                    ),
                  ),
                  IconButton(
                    icon:
                        const Icon(Icons.share_rounded, color: Sandik.amber),
                    onPressed: () => Share.share(returnCode),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: Sandik.amber.withValues(alpha: 0.1),
                foregroundColor: Sandik.amber,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Tamam'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sandik.surface2,
        title: const Text('Çıkış Yap', style: TextStyle(color: Colors.white)),
        content: const Text('Hesabınızdan çıkmak istediğinizden emin misiniz?',
            style: TextStyle(color: Sandik.text58)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Vazgeç', style: TextStyle(color: Sandik.text36))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Sandik.loss),
            child: const Text('Çıkış Yap'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(authProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final partnersAsync = ref.watch(partnersProvider);

    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Profil',
          style: GoogleFonts.plusJakartaSans(
              fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        actions: [
          IconButton(
            onPressed: _logout,
            icon: const Icon(Icons.logout_rounded, color: Sandik.loss),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildUserHeader(user),
          const SizedBox(height: 32),
          const _SectionTitle('ORTAKLIK İŞLEMLERİ'),
          const SizedBox(height: 16),
          _buildInviteSection(),
          const SizedBox(height: 32),
          const _SectionTitle('ORTAKLARIM'),
          const SizedBox(height: 16),
          partnersAsync.when(
            loading: () => const Center(
                child: CircularProgressIndicator(color: Sandik.amber)),
            error: (e, _) => Text(e.toString()),
            data: (partners) => partners.isEmpty
                ? _buildEmptyPartners()
                : Column(
                    children:
                        partners.map((p) => _buildPartnerTile(p)).toList(),
                  ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildUserHeader(dynamic user) {
    if (user == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Sandik.amber.withValues(alpha: 0.1),
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase()
                  : '?',
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Sandik.amber),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: GoogleFonts.plusJakartaSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  user.email,
                  style: GoogleFonts.inter(fontSize: 14, color: Sandik.text36),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInviteSection() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Davet Kodu Üret',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Kodu ortağınıza göndererek portföylerinizi birleştirebilirsiniz.',
                style: GoogleFonts.inter(fontSize: 13, color: Sandik.text36),
              ),
              const SizedBox(height: 20),
              if (_generatedCode != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _generatedCode!.split(':')[0],
                          style: GoogleFonts.jetBrainsMono(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Sandik.amber,
                              letterSpacing: 4),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.share_rounded,
                            color: Sandik.amber),
                        onPressed: () => Share.share(_generatedCode!),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton(
                onPressed: _generating ? null : _generateCode,
                style: FilledButton.styleFrom(
                  backgroundColor: Sandik.amber.withValues(alpha: 0.1),
                  foregroundColor: Sandik.amber,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_generating ? 'Üretiliyor...' : 'Kod Üret'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Sandik.surface1,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Ortak Kodunu Gir',
                style: GoogleFonts.inter(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _codeCtrl,
                style: const TextStyle(color: Colors.white),
                decoration:
                    Sandik.inputDecoration('Davet kodunu buraya yapıştırın'),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _redeeming ? null : _redeemCode,
                style: FilledButton.styleFrom(
                  backgroundColor: Sandik.gain.withValues(alpha: 0.1),
                  foregroundColor: Sandik.gain,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(_redeeming ? 'Bağlanıyor...' : 'Ortaklık Kur'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyPartners() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.people_outline_rounded,
              size: 48, color: Sandik.text36.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          Text(
            'Henüz ortağınız yok',
            style: GoogleFonts.inter(fontSize: 14, color: Sandik.text36),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPartnerTile(dynamic p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Sandik.surface1,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: p.isActive
                ? Sandik.gain.withValues(alpha: 0.1)
                : Sandik.text36.withValues(alpha: 0.1),
            child: Text(
              p.user.displayName[0].toUpperCase(),
              style: TextStyle(
                  color: p.isActive ? Sandik.gain : Sandik.text36,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.user.displayName,
                    style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(p.isActive ? 'Aktif Ortak' : 'Donduruldu',
                    style:
                        GoogleFonts.inter(fontSize: 12, color: Sandik.text36)),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
                p.isActive
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: Sandik.text36),
            onPressed: () => ref
                .read(partnersProvider.notifier)
                .toggleActive(p.user.id, !p.isActive),
          ),
          IconButton(
            tooltip: 'Veriyi Güncelle',
            icon: const Icon(Icons.sync_rounded, color: Sandik.amber),
            onPressed: () => _showSyncSheet(p.user.displayName),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Sandik.loss),
            onPressed: () => _confirmRemove(p.user.id, p.user.displayName),
          ),
        ],
      ),
    );
  }

  void _showSyncSheet(String partnerName) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Sandik.surface1,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: Sandik.text36,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 24),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Sandik.amber.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.sync_rounded,
                  color: Sandik.amber, size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              '$partnerName\'in Verilerini Güncelle',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              '$partnerName\'den yeni bir davet kodu üretmesini ve size göndermesini isteyin. '
              'Kodu "Ortak Kodunu Gir" alanına girdikten sonra tüm son varlıkları görünür hale gelecek.',
              style: GoogleFonts.inter(fontSize: 13, color: Sandik.text58),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              style: FilledButton.styleFrom(
                backgroundColor: Sandik.amber.withValues(alpha: 0.1),
                foregroundColor: Sandik.amber,
                minimumSize: const Size(double.infinity, 48),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Anladım'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmRemove(String partnerId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Sandik.surface2,
        title: const Text('Ortaklığı Kaldır',
            style: TextStyle(color: Colors.white)),
        content: Text(
            '$name ile ortaklığı kaldırmak istediğinizden emin misiniz?',
            style: const TextStyle(color: Sandik.text58)),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child:
                  const Text('Vazgeç', style: TextStyle(color: Sandik.text36))),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Sandik.loss),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(partnersProvider.notifier).removePartner(partnerId);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Sandik.text36,
        ),
      );
}
