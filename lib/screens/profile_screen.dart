import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/sandik.dart';
import '../services/auth_service.dart';
import '../services/supabase_service.dart';
import 'login_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _codeCtrl = TextEditingController();
  String? _generatedCode;
  bool _generating = false;
  bool _submitting = false;
  bool _busy = false; // genel işlem kilidi — tüm butonları disable eder

  // Kod girildikten sonra onay bekleme durumu
  String? _pendingInviteId;
  String? _pendingPartnerName;
  Timer? _pollTimer;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _pollTimer?.cancel();
    super.dispose();
  }

  // ── Kod üret ──────────────────────────────────────────────────────────────

  Future<void> _generateCode() async {
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) return;
    setState(() { _generating = true; _busy = true; });
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
      if (mounted) setState(() { _generating = false; _busy = false; });
    }
  }

  // ── Kodu gönder (onay bekleme başlar) ──────────────────────────────────────

  Future<void> _submitCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() { _submitting = true; _busy = true; });
    try {
      final result = await ref.read(partnersProvider.notifier).submitCode(code);
      _codeCtrl.clear();
      setState(() {
        _pendingInviteId = result.inviteId;
        _pendingPartnerName = result.partnerName;
      });
      _startPolling(result.inviteId);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    } finally {
      if (mounted) setState(() { _submitting = false; _busy = false; });
    }
  }

  // ── Polling: onay verildi mi? ──────────────────────────────────────────────

  void _startPolling(String inviteId) {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) async {
      if (!mounted) return;
      final status = await SupabaseService.instance.getInviteStatus(inviteId);
      if (status == 'accepted') {
        _pollTimer?.cancel();
        // Partnership kuruldu — listeleri yenile
        await ref.read(partnersProvider.notifier).refresh();
        ref.read(allPartnerAssetsProvider.notifier).reload();
        if (mounted) {
          setState(() {
            _pendingInviteId = null;
            _pendingPartnerName = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$_pendingPartnerName ile ortaklık kuruldu!'),
              backgroundColor: Sandik.gain,
            ),
          );
        }
      } else if (status == 'rejected') {
        _pollTimer?.cancel();
        if (mounted) {
          setState(() {
            _pendingInviteId = null;
            _pendingPartnerName = null;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ortaklık isteği reddedildi.'),
              backgroundColor: Sandik.loss,
            ),
          );
        }
      }
    });
  }

  void _cancelPending() {
    _pollTimer?.cancel();
    setState(() {
      _pendingInviteId = null;
      _pendingPartnerName = null;
    });
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool loggingOut = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            backgroundColor: Sandik.surface2,
            title: const Text('Çıkış Yap', style: TextStyle(color: Colors.white)),
            content: const Text('Hesabınızdan çıkmak istediğinizden emin misiniz?',
                style: TextStyle(color: Sandik.text58)),
            actions: [
              TextButton(
                onPressed: loggingOut ? null : () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç', style: TextStyle(color: Sandik.text36)),
              ),
              FilledButton(
                onPressed: loggingOut
                    ? null
                    : () async {
                        setDialogState(() => loggingOut = true);
                        await ref.read(authProvider.notifier).logout();
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      },
                style: FilledButton.styleFrom(backgroundColor: Sandik.loss),
                child: loggingOut
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Çıkış Yap'),
              ),
            ],
          ),
        );
      },
    );
    if (confirm == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authProvider).valueOrNull;
    final partnersAsync = ref.watch(partnersProvider);

    return Stack(
      children: [
        Scaffold(
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
                onPressed: _busy ? null : _logout,
                icon: const Icon(Icons.logout_rounded, color: Sandik.loss),
              ),
            ],
          ),
          body: AbsorbPointer(
            absorbing: _busy,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              children: [
                _buildUserHeader(user),
                const SizedBox(height: 24),

                // ── Bekleyen onay istekleri (kod sahibine gösterilir) ────────────
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
          ),
        ),
        if (_busy)
          const ModalBarrier(dismissible: false, color: Colors.transparent),
      ],
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
        // Kod üretme
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
                'Kodu ortağınıza gönderin. Ortak kodu girince size onay isteği gelir.',
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
        // Kod girme
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
              const SizedBox(height: 8),
              Text(
                'Ortağınızın size gönderdiği kodu girin (örn: ABCDE-12345). Onay vermesi beklenir.',
                style: GoogleFonts.inter(fontSize: 13, color: Sandik.text36),
              ),
              const SizedBox(height: 16),
              // Onay bekleniyor göstergesi
              if (_pendingInviteId != null) ...[
                _buildWaitingCard(),
              ] else ...[
                TextField(
                  controller: _codeCtrl,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: Sandik.inputDecoration('XXXXX-XXXXX'),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _submitting ? null : _submitCode,
                  style: FilledButton.styleFrom(
                    backgroundColor: Sandik.gain.withValues(alpha: 0.1),
                    foregroundColor: Sandik.gain,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child:
                      Text(_submitting ? 'Gönderiliyor...' : 'Ortaklık İste'),
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
                  style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: _cancelPending,
            style: TextButton.styleFrom(
              foregroundColor: Sandik.text36,
              padding: EdgeInsets.zero,
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('İptal',
                style: GoogleFonts.inter(fontSize: 13, color: Sandik.text36)),
          ),
        ],
      ),
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
                Text(p.isActive ? 'Görünür' : 'Gizlendi',
                    style: GoogleFonts.inter(
                        fontSize: 12,
                        color: p.isActive ? Sandik.gain : Sandik.text36)),
              ],
            ),
          ),
          IconButton(
            tooltip: p.isActive ? 'Gizle' : 'Göster',
            icon: Icon(
                p.isActive
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: _busy
                    ? Sandik.text36.withValues(alpha: 0.3)
                    : (p.isActive ? Sandik.text58 : Sandik.text36)),
            onPressed: _busy
                ? null
                : () async {
                    setState(() => _busy = true);
                    await ref
                        .read(partnersProvider.notifier)
                        .toggleHidden(p.user.id, p.isActive); // isActive=true → gizle
                    if (mounted) setState(() => _busy = false);
                  },
          ),
          IconButton(
            icon: Icon(Icons.close_rounded,
                color: _busy ? Sandik.loss.withValues(alpha: 0.3) : Sandik.loss),
            onPressed: _busy
                ? null
                : () => _confirmRemove(p.user.id, p.user.displayName),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(String partnerId, String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        bool removing = false;
        return StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            backgroundColor: Sandik.surface2,
            title: const Text('Ortaklığı Kaldır',
                style: TextStyle(color: Colors.white)),
            content: Text(
                '$name ile ortaklığı kaldırmak istediğinizden emin misiniz?',
                style: const TextStyle(color: Sandik.text58)),
            actions: [
              TextButton(
                onPressed: removing ? null : () => Navigator.pop(ctx, false),
                child: const Text('Vazgeç',
                    style: TextStyle(color: Sandik.text36)),
              ),
              FilledButton(
                onPressed: removing
                    ? null
                    : () async {
                        setDialog(() => removing = true);
                        await ref
                            .read(partnersProvider.notifier)
                            .removePartner(partnerId);
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      },
                style: FilledButton.styleFrom(backgroundColor: Sandik.loss),
                child: removing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Kaldır'),
              ),
            ],
          ),
        );
      },
    );
    if (confirm == true && mounted) {
      setState(() {});
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
    // 5 saniyede bir yenile
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

  Future<void> _accept(Map<String, dynamic> invite) async {
    try {
      await ref
          .read(partnersProvider.notifier)
          .acceptInvite(invite['id'] as String);
      ref.read(allPartnerAssetsProvider.notifier).reload();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Ortaklık kabul edildi!'),
              backgroundColor: Sandik.gain),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
    }
  }

  Future<void> _reject(Map<String, dynamic> invite) async {
    try {
      await ref
          .read(partnersProvider.notifier)
          .rejectInvite(invite['id'] as String);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
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
    if (mounted) {
      setState(() => _requesterName = profile?.displayName ?? 'Kullanıcı');
    }
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
                Text(
                  _requesterName,
                  style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.white),
                ),
                Text(
                  'Ortaklık istiyor',
                  style: GoogleFonts.inter(fontSize: 12, color: Sandik.text36),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Sandik.loss, size: 22),
            onPressed: widget.onReject,
            tooltip: 'Reddet',
          ),
          IconButton(
            icon: const Icon(Icons.check_rounded, color: Sandik.gain, size: 22),
            onPressed: widget.onAccept,
            tooltip: 'Onayla',
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
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Sandik.text36,
        ),
      );
}
