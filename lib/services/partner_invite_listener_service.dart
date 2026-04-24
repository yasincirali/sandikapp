import 'package:supabase_flutter/supabase_flutter.dart';

import 'notification_service.dart';
import 'supabase_service.dart';

class PartnerInviteListenerService {
  static final PartnerInviteListenerService instance =
      PartnerInviteListenerService._();
  PartnerInviteListenerService._();

  final Set<String> _notifiedInviteIds = <String>{};
  RealtimeChannel? _channel;
  String? _activeUserId;

  SupabaseClient get _client => Supabase.instance.client;

  Future<void> start(String userId) async {
    if (_activeUserId == userId && _channel != null) return;

    await stop();
    _activeUserId = userId;

    final channel = _client.channel('partner-invites-$userId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'partner_invites',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'from_user_id',
          value: userId,
        ),
        callback: (payload) async {
          final row = payload.newRecord;
          final inviteId = row['id'] as String?;
          final status = row['status'] as String?;
          final toUserId = row['to_user_id'] as String?;

          if (inviteId == null ||
              toUserId == null ||
              status != 'pending' ||
              !_notifiedInviteIds.add(inviteId)) {
            return;
          }

          var requesterName = ((row['requester_name'] as String?) ?? '').trim();
          if (requesterName.isEmpty) {
            try {
              final profile =
                  await SupabaseService.instance.getProfile(toUserId);
              requesterName = profile?.displayName.trim() ?? '';
            } catch (_) {
              requesterName = '';
            }
          }
          if (requesterName.isEmpty) {
            requesterName = 'Bir kullanici';
          }

          await NotificationService.instance.showPartnerInviteNotification(
            inviteId: inviteId,
            requesterName: requesterName,
          );
        },
      )
      ..subscribe();

    _channel = channel;
  }

  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _activeUserId = null;
    _notifiedInviteIds.clear();
    if (channel != null) {
      await _client.removeChannel(channel);
    }
  }
}
