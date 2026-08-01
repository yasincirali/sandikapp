import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';

class PartnershipRequestsScreen extends ConsumerStatefulWidget {
  final String? highlightInviteId;

  const PartnershipRequestsScreen({
    super.key,
    this.highlightInviteId,
  });

  @override
  ConsumerState<PartnershipRequestsScreen> createState() =>
      _PartnershipRequestsScreenState();
}

class _PartnershipRequestsScreenState
    extends ConsumerState<PartnershipRequestsScreen> {
  List<Map<String, dynamic>> _pendingInvites = [];
  bool _loading = true;
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
    final user = ref.read(authProvider).valueOrNull;
    if (user == null) {
      if (!mounted) return;
      setState(() => _loading = false);
      return;
    }

    final invites =
        await SupabaseService.instance.getPendingInvitesForMe(user.id);

    invites.sort((a, b) {
      final aHighlighted = a['id'] == widget.highlightInviteId;
      final bHighlighted = b['id'] == widget.highlightInviteId;
      if (aHighlighted == bHighlighted) return 0;
      return aHighlighted ? -1 : 1;
    });

    if (!mounted) return;
    setState(() {
      _pendingInvites = invites;
      _loading = false;
    });
  }

  Future<void> _accept(String inviteId) async {
    try {
      await ref.read(partnersProvider.notifier).acceptInvite(inviteId);
      AnalyticsService.instance.logPartnerInviteAccepted();
      ref.read(allPartnerAssetsProvider.notifier).reload();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ortaklık kabul edildi.'),
          backgroundColor: Sandik.gain,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _reject(String inviteId) async {
    try {
      await ref.read(partnersProvider.notifier).rejectInvite(inviteId);
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ortaklık isteği reddedildi.'),
          backgroundColor: Sandik.loss,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Sandik.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Ortaklık Onayı',
          style: context.t.headlineLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: Sandik.amber,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Ortaklık kodunuzu giren müşterileri buradan görup onaylayabilirsiniz.',
              style: context.t.titleMedium?.copyWith(
                color: Sandik.text36,
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(
                  child: CircularProgressIndicator(color: Sandik.amber),
                ),
              )
            else if (_pendingInvites.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Sandik.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.lg),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: Sandik.text36.withValues(alpha: 0.5),
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bekleyen ortaklık isteği yok.',
                      style: context.t.titleMedium?.copyWith(
                        color: Sandik.text36,
                      ),
                    ),
                  ],
                ),
              )
            else
              ..._pendingInvites.map(
                (invite) => _ApprovalInviteCard(
                  invite: invite,
                  highlighted: invite['id'] == widget.highlightInviteId,
                  onAccept: () => _accept(invite['id'] as String),
                  onReject: () => _reject(invite['id'] as String),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ApprovalInviteCard extends StatelessWidget {
  final Map<String, dynamic> invite;
  final bool highlighted;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  const _ApprovalInviteCard({
    required this.invite,
    required this.highlighted,
    required this.onAccept,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final rawRequesterName =
        ((invite['requester_name'] as String?) ?? '').trim();
    final requesterName =
        rawRequesterName.isEmpty ? 'Kullanıcı' : rawRequesterName;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color:
            highlighted ? Sandik.amber.withValues(alpha: 0.1) : Sandik.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: highlighted
              ? Sandik.amber.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.05),
          width: highlighted ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlighted) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Sandik.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Yeni gelen istek',
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Sandik.amber,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Sandik.amber.withValues(alpha: 0.12),
                child: Text(
                  requesterName.isNotEmpty
                      ? requesterName[0].toUpperCase()
                      : '?',
                  style: const TextStyle(
                    color: Sandik.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      requesterName,
                      style: context.t.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ortaklık kodunuzu girdi ve onay bekliyor.',
                      style: context.t.bodyMedium?.copyWith(
                        color: Sandik.text36,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onReject,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Sandik.loss,
                    side: const BorderSide(color: Sandik.loss, width: 1.2),
                  ),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: Sandik.gain,
                    foregroundColor: Sandik.dark,
                  ),
                  child: const Text('Onayla'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
