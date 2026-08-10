import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/portfolio_provider.dart';
import '../services/analytics_service.dart';
import '../services/supabase_service.dart';
import '../theme/sandik.dart';
import '../widgets/custom_loading_indicator.dart';

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
        SnackBar(
          // Renkli zeminde tema `contentTextStyle`'ı (text90) kullanılamaz —
          // light modda 3.02:1 verir. Dolgu üstünün mürekkebi `onStatus`.
          content: Text('Ortaklık kabul edildi.',
              style: TextStyle(color: context.c.onStatus)),
          backgroundColor: context.c.gain,
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
        SnackBar(
          content: Text('Ortaklık isteği reddedildi.',
              style: TextStyle(color: context.c.onStatus)),
          backgroundColor: context.c.loss,
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
      backgroundColor: context.c.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Ortaklık Onayı',
          style: context.t.headlineLarge?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: context.c.text90,
          ),
        ),
      ),
      body: RefreshIndicator(
        color: context.c.amberText,
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Ortaklık kodunuzu giren müşterileri buradan görup onaylayabilirsiniz.',
              style: context.t.titleMedium?.copyWith(
                color: context.c.text36,
              ),
            ),
            const SizedBox(height: 20),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 40),
                child: CustomLoadingView(),
              )
            else if (_pendingInvites.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: context.c.surface1,
                  borderRadius: BorderRadius.circular(SandikRadius.lg),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.notifications_none_rounded,
                      color: context.c.text36.withValues(alpha: 0.5),
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Bekleyen ortaklık isteği yok.',
                      style: context.t.titleMedium?.copyWith(
                        color: context.c.text36,
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
            highlighted ? context.c.amberFill.withValues(alpha: 0.1) : context.c.surface1,
        borderRadius: BorderRadius.circular(SandikRadius.md),
        border: Border.all(
          color: highlighted
              ? context.c.amberFill.withValues(alpha: 0.45)
              : context.c.overlay,
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
                color: context.c.amberFill.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'Yeni gelen istek',
                style: context.t.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.c.amberText,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: context.c.amberFill.withValues(alpha: 0.12),
                child: Text(
                  requesterName.isNotEmpty
                      ? requesterName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    color: context.c.amberText,
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
                        color: context.c.text90,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Ortaklık kodunuzu girdi ve onay bekliyor.',
                      style: context.t.bodyMedium?.copyWith(
                        color: context.c.text36,
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
                    foregroundColor: context.c.loss,
                    side: BorderSide(color: context.c.loss, width: 1.2),
                  ),
                  child: const Text('Reddet'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: onAccept,
                  style: FilledButton.styleFrom(
                    backgroundColor: context.c.gain,
                    // `onAmber` amber içindir ve iki temada da koyudur;
                    // light'ta koyu yeşil dolgu üstünde 3.02:1 veriyordu.
                    foregroundColor: context.c.onStatus,
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
