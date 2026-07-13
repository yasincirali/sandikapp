import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../providers/preferences_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'paywall_screen.dart';
import '../widgets/sandik_error_view.dart';
import '../theme/sandik.dart';
import '../services/analytics_service.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import '../utils/friendly_error.dart';
import 'settings_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

/// Ortaklık akışına özel markaya uygun mesaj gösterimi.
/// Sunucudan gelen kod-bazlı Türkçe mesajları tanır ve bağlama göre
/// bilgi/hata rozeti seçer (raw exception göstermez).
Future<void> _showPartnerMsg(
  BuildContext context,
  String rawMessage, {
  required bool isError,
}) async {
  if (!context.mounted) return;
  final msg = rawMessage.replaceFirst(RegExp(r'^Exception:\s*'), '');

  if (!isError) {
    await showAppSuccess(context, title: 'Tamamlandı', message: msg);
    return;
  }

  // Belirli senaryolar için bilgi rozeti (hata değil bilgilendirme):
  if (msg.contains('zaten ortağın')) {
    await showAppInfo(context, title: 'Zaten Ortaksınız', message: msg);
    return;
  }
  if (msg.contains('Kendi ürettiğin')) {
    await showAppInfo(context, title: 'Kendi Kodun', message: msg);
    return;
  }
  if (msg.contains('süresi dolmuş')) {
    await showAppInfo(context, title: 'Süresi Doldu', message: msg);
    return;
  }
  await showSandikDialog(
    context: context,
    kind: SandikDialogKind.error,
    title: 'Bir sorun oluştu',
    message: msg,
  );
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _codeCtrl = TextEditingController();
  String? _generatedCode;
  bool _generating = false;
  bool _submitting = false;
  bool _busy = false;

  String? _pendingInviteId;
  String? _pendingPartnerName;
  Timer? _pollTimer;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _showMsg(String msg, {bool isError = false}) =>
      _showPartnerMsg(context, msg, isError: isError);

  Future<void> _generateCode() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() {
      _generating = true;
      _busy = true;
    });
    try {
      final code = await AuthService.instance.generatePartnerCode(user.id);
      setState(() => _generatedCode = code);
      await Clipboard.setData(ClipboardData(text: code));
      await _showMsg('Kod üretildi ve panoya kopyalandı');
    } catch (e) {
      await _showMsg(e.toString(), isError: true);
    } finally {
      if (mounted)
        setState(() {
          _generating = false;
          _busy = false;
        });
    }
  }

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _submitting = true;
      _busy = true;
    });
    try {
      final result = await ref.read(partnersProvider.notifier).submitCode(code);
      _codeCtrl.clear();
      setState(() {
        _pendingInviteId = result.inviteId;
        _pendingPartnerName = result.partnerName;
      });
      _startPolling(result.inviteId);
    } catch (e) {
      await _showMsg(e.toString(), isError: true);
    } finally {
      if (mounted)
        setState(() {
          _submitting = false;
          _busy = false;
        });
    }
  }

  void _startPolling(String inviteId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final status = await SupabaseService.instance.getInviteStatus(inviteId);
      if (status == 'accepted') {
        _pollTimer?.cancel();
        await ref.read(partnersProvider.notifier).refresh();
        ref.read(allPartnerAssetsProvider.notifier).reload();
        if (mounted) {
          final name = _pendingPartnerName;
          setState(() {
            _pendingInviteId = null;
            _pendingPartnerName = null;
          });
          await _showMsg('$name ile ortaklık kuruldu!');
        }
      } else if (status == 'rejected') {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _pendingInviteId = null;
            _pendingPartnerName = null;
          });
          await _showMsg('Ortaklık isteği reddedildi.', isError: true);
        }
      }
    });
  }

  Future<void> _cancelPending() async {
    final inviteId = _pendingInviteId;
    if (inviteId == null) return;

    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Ortaklık İsteğini İptal Et'),
        content: const Text(
            'Gönderdiğiniz ortaklık isteğini iptal etmek istediğinize emin misiniz?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Evet, iptal et'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    _pollTimer?.cancel();
    setState(() => _busy = true);
    try {
      await ref.read(partnersProvider.notifier).rejectInvite(inviteId);
      if (mounted) {
        setState(() {
          _pendingInviteId = null;
          _pendingPartnerName = null;
        });
        await _showMsg('Ortaklık isteği iptal edildi.');
      }
    } catch (e) {
      if (mounted) {
        _startPolling(inviteId);
        await _showMsg(e.toString(), isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _logout() => confirmAndLogout(context, ref);

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final partnersAsync = ref.watch(partnersProvider);

    return PopScope(
      canPop: !_busy,
      child: Stack(
      children: [
        CupertinoPageScaffold(
          backgroundColor: Sandik.background,
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Profil',
                          style: GoogleFonts.dmSans(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.white,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        onPressed: _busy
                            ? null
                            : () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => const SettingsScreen(),
                                  ),
                                ),
                        child: _ActionIcon(
                          icon: Icons.settings_outlined,
                          color: Sandik.text90,
                          disabled: _busy,
                          semanticLabel: 'Ayarlar',
                        ),
                      ),
                      const SizedBox(width: 8),
                      SandikLogoutButton(
                        onPressed: _logout,
                        disabled: _busy,
                      ),
                    ],
                  ),
                ),
                // Body
                Expanded(
                  child: AbsorbPointer(
                    absorbing: _busy,
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 4),
                      children: [
                        _buildUserHeader(user),
                        const SizedBox(height: 20),
                        const _ProfilePremiumBanner(),
                        const SizedBox(height: 24),
                        _PendingRequestsSection(userId: user?.id ?? ''),
                        const SizedBox(height: 8),
                        const _SectionTitle('ORTAKLIK İŞLEMLERİ'),
                        const SizedBox(height: 16),
                        _buildInviteSection(),
                        const SizedBox(height: 32),
                        const _SectionTitle('ORTAKLARIM'),
                        const SizedBox(height: 16),
                        partnersAsync.when(
                          loading: () => const Center(
                            child:
                                CircularProgressIndicator(color: Sandik.amber),
                          ),
                          error: (e, _) => SandikErrorView(error: e),
                          data: (partners) => partners.isEmpty
                              ? _buildEmptyPartners()
                              : Column(
                                  children: partners
                                      .map((p) => _buildPartnerTile(p))
                                      .toList(),
                                ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_busy) ...[
          const ModalBarrier(
              dismissible: false, color: Color(0xCC000000)),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 24, vertical: 20),
              decoration: BoxDecoration(
                color: Sandik.surface1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5, color: Sandik.amber),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    _submitting
                        ? 'Ortaklık isteği gönderiliyor...'
                        : _generating
                            ? 'Kod üretiliyor...'
                            : 'İşleniyor...',
                    style: GoogleFonts.dmSans(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
          ),
        ],
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
                  style: GoogleFonts.dmSans(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(user.email,
                    style:
                        GoogleFonts.dmSans(fontSize: 14, color: Sandik.text36)),
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
        // Kod üretme
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Sandik.surface1, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Davet Kodu Üret',
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'Kodu ortağınıza gönderin. Ortak kodu girince size onay isteği gelir.',
                style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36),
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
                          style: GoogleFonts.dmSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: Sandik.amber,
                            letterSpacing: 4,
                          ),
                        ),
                      ),
                      CupertinoButton(
                        minimumSize: Size.zero,
                        padding: EdgeInsets.zero,
                        onPressed: () async {
                          final shortCode = _generatedCode!.split(':')[0];
                          final msg =
                              'Merhaba! Sandık portföy uygulamasında seninle ortak olmak istiyorum.\n\n'
                              'Ortak kodun: $shortCode\n\n'
                              'Uygulamayı aç → Profil → "Ortak Kodu Gir" bölümünden bu kodu gir.';
                          await Share.share(msg, subject: 'Sandık Ortak Daveti');
                          AnalyticsService.instance.logPartnerInviteSent();
                        },
                        child: const Icon(Icons.share_rounded,
                            color: Sandik.amber),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              CupertinoButton(
                onPressed: _generating ? null : _generateCode,
                padding: EdgeInsets.zero,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: _generating
                        ? Sandik.amber.withValues(alpha: 0.05)
                        : Sandik.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _generating ? 'Üretiliyor...' : 'Kod Üret',
                    style: GoogleFonts.dmSans(
                        color: Sandik.amber, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Kod girme
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: Sandik.surface1, borderRadius: BorderRadius.circular(16)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Ortak Kodunu Gir',
                  style: GoogleFonts.dmSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
              const SizedBox(height: 8),
              Text(
                'Ortağınızın size gönderdiği kodu girin (örn: ABCDE-12345). Onay vermesi beklenir.',
                style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36),
              ),
              const SizedBox(height: 16),
              if (_pendingInviteId != null) ...[
                _buildWaitingCard(),
              ] else ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.text,
                  textCapitalization: TextCapitalization.characters,
                  style: const TextStyle(color: Colors.white),
                  decoration: Sandik.inputDecoration('XXXXX-XXXXX'),
                ),
                const SizedBox(height: 16),
                CupertinoButton(
                  onPressed: _submitting ? null : _submitCode,
                  padding: EdgeInsets.zero,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: _submitting
                          ? Sandik.gain.withValues(alpha: 0.05)
                          : Sandik.gain.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      _submitting ? 'Gönderiliyor...' : 'Ortaklık İste',
                      style: GoogleFonts.dmSans(
                          color: Sandik.gain, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWaitingCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Sandik.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: Sandik.amber.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Sandik.amber),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '$_pendingPartnerName onayı bekleniyor...',
                  style: GoogleFonts.dmSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            onPressed: _cancelPending,
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            child: Text('İptal',
                style: GoogleFonts.dmSans(fontSize: 13, color: Sandik.text36)),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyPartners() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
          color: Sandik.surface1, borderRadius: BorderRadius.circular(16)),
      child: Column(
        children: [
          const Icon(Icons.people_outline_rounded,
              size: 48, color: Sandik.text36),
          const SizedBox(height: 16),
          Text(
            'Henüz ortağınız yok',
            style: GoogleFonts.dmSans(fontSize: 14, color: Sandik.text36),
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
          color: Sandik.surface1, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: p.isActive
                ? Sandik.gain.withValues(alpha: 0.1)
                : Sandik.text36.withValues(alpha: 0.1),
            child: Text(
              p.user.displayName.isNotEmpty
                  ? p.user.displayName[0].toUpperCase()
                  : '?',
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
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text(
                  p.isActive ? 'Görünür' : 'Gizlendi',
                  style: GoogleFonts.dmSans(
                      fontSize: 12,
                      color: p.isActive ? Sandik.gain : Sandik.text36),
                ),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await ref
                        .read(partnersProvider.notifier)
                        .toggleHidden(p.user.id, p.isActive);
                    if (mounted) setState(() => _busy = false);
                  },
            child: _ActionIcon(
              icon: p.isActive
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: p.isActive ? Sandik.text58 : Sandik.gain,
              disabled: _busy,
              semanticLabel: p.isActive ? 'Ortağı gizle' : 'Ortağı göster',
            ),
          ),
          const SizedBox(width: 8),
          CupertinoButton(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            onPressed: _busy
                ? null
                : () => _confirmRemove(p.user.id, p.user.displayName),
            child: _ActionIcon(
              icon: Icons.delete_outline_rounded,
              color: Sandik.loss,
              disabled: _busy,
              semanticLabel: 'Ortağı sil',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(String partnerId, String name) async {
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Ortaklığı Kaldır'),
        content:
            Text('$name ile ortaklığı kaldırmak istediğinizden emin misiniz?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      setState(() => _busy = true);
      await ref.read(partnersProvider.notifier).removePartner(partnerId);
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ── Bekleyen onay istekleri (kod sahibine gösterilir) ─────────────────────────

class _PendingRequestsSection extends ConsumerStatefulWidget {
  final String userId;
  const _PendingRequestsSection({required this.userId});

  @override
  ConsumerState<_PendingRequestsSection> createState() =>
      _PendingRequestsSectionState();
}

class _PendingRequestsSectionState
    extends ConsumerState<_PendingRequestsSection> {
  List<Map<String, dynamic>> _pendingInvites = [];
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.userId.isEmpty) return;
    final invites =
        await SupabaseService.instance.getPendingInvitesForMe(widget.userId);
    if (mounted) setState(() => _pendingInvites = invites);
  }

  Future<void> _showMsg(String msg, {bool isError = false}) =>
      _showPartnerMsg(context, msg, isError: isError);

  Future<void> _accept(Map<String, dynamic> invite) async {
    try {
      await ref
          .read(partnersProvider.notifier)
          .acceptInvite(invite['id'] as String);
      ref.read(allPartnerAssetsProvider.notifier).reload();
      await _load();
      await _showMsg('Ortaklık kabul edildi!');
    } catch (e) {
      await _showMsg(e.toString(), isError: true);
    }
  }

  Future<void> _reject(Map<String, dynamic> invite) async {
    try {
      await ref
          .read(partnersProvider.notifier)
          .rejectInvite(invite['id'] as String);
      await _load();
    } catch (e) {
      await _showMsg(e.toString(), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_pendingInvites.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('BEKLEYEN ORTAKLIK İSTEKLERİ'),
        const SizedBox(height: 12),
        ..._pendingInvites.map((invite) => _PendingInviteTile(
              invite: invite,
              onAccept: () => _accept(invite),
              onReject: () => _reject(invite),
            )),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _PendingInviteTile extends StatefulWidget {
  final Map<String, dynamic> invite;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  const _PendingInviteTile(
      {required this.invite, required this.onAccept, required this.onReject});

  @override
  State<_PendingInviteTile> createState() => _PendingInviteTileState();
}

class _PendingInviteTileState extends State<_PendingInviteTile> {
  String _requesterName = '...';

  @override
  void initState() {
    super.initState();
    final requesterName =
        ((widget.invite['requester_name'] as String?) ?? '').trim();
    if (requesterName.isNotEmpty) {
      _requesterName = requesterName;
      return;
    }
    _loadRequesterName();
  }

  Future<void> _loadRequesterName() async {
    final toUserId = widget.invite['to_user_id'] as String?;
    if (toUserId == null) return;
    dynamic profile;
    try {
      profile = await SupabaseService.instance.getProfile(toUserId);
    } catch (_) {
      profile = null;
    }
    if (mounted)
      setState(() => _requesterName = profile?.displayName ?? 'Kullanıcı');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Sandik.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Sandik.amber.withValues(alpha: 0.3), width: 1.5),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: Sandik.amber.withValues(alpha: 0.15),
            child: Text(
              _requesterName.isNotEmpty ? _requesterName[0].toUpperCase() : '?',
              style: const TextStyle(
                  color: Sandik.amber, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_requesterName,
                    style: GoogleFonts.dmSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white)),
                Text('Ortaklık istiyor',
                    style:
                        GoogleFonts.dmSans(fontSize: 12, color: Sandik.text36)),
              ],
            ),
          ),
          CupertinoButton(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            onPressed: widget.onReject,
            child:
                const Icon(Icons.close_rounded, color: Sandik.loss, size: 22),
          ),
          CupertinoButton(
            minimumSize: Size.zero,
            padding: EdgeInsets.zero,
            onPressed: widget.onAccept,
            child:
                const Icon(Icons.check_rounded, color: Sandik.gain, size: 22),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Sandik.text36,
        ),
      );
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool disabled;
  final String semanticLabel;

  const _ActionIcon({
    required this.icon,
    required this.color,
    required this.disabled,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = disabled ? color.withValues(alpha: 0.35) : color;
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: iconColor.withValues(alpha: 0.18)),
        ),
        child: Center(child: Icon(icon, color: iconColor, size: 20)),
      ),
    );
  }
}

// ── Premium banner ────────────────────────────────────────────────────────

class _ProfilePremiumBanner extends ConsumerWidget {
  const _ProfilePremiumBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Paywall master switch kapalıysa banner hiç gösterilmez.
    if (!ref.watch(paywallVisibleProvider)) return const SizedBox.shrink();
    final premium = ref.watch(effectivePremiumProvider);
    if (premium) return const _PremiumActiveBadge();
    return GestureDetector(
      onTap: () {
        AnalyticsService.instance
            .logPremiumGateShown(feature: 'profile_banner');
        PaywallScreen.show(context, source: 'profile_banner');
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Sandik.amber.withValues(alpha: 0.20),
              Sandik.gold.withValues(alpha: 0.08),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Sandik.amber.withValues(alpha: 0.40)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Sandik.amber.withValues(alpha: 0.20),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.workspace_premium_rounded,
                  color: Sandik.amber, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Sandık Premium',
                      style: GoogleFonts.dmSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    'Sınırsız varlık, AI portföy raporu, premium göstergeler',
                    style: GoogleFonts.dmSans(
                        fontSize: 11,
                        color: Sandik.text58,
                        height: 1.35),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Sandik.amber),
          ],
        ),
      ),
    );
  }
}

class _PremiumActiveBadge extends StatelessWidget {
  const _PremiumActiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: Sandik.gain.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Sandik.gain.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: Sandik.gain.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Sandik.gain, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Premium aktif',
                    style: GoogleFonts.dmSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: Colors.white)),
                const SizedBox(height: 2),
                Text('Tüm gelişmiş özellikler açık',
                    style: GoogleFonts.dmSans(
                        fontSize: 11, color: Sandik.text58)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
