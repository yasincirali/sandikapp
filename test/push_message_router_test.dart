import 'package:flutter_test/flutter_test.dart';
import 'package:portfoy_takip/services/notification_service.dart';
import 'package:portfoy_takip/services/push_message_router.dart';

/// `RemotePushService`'in ön plan mesaj yönlendirmesi — Firebase olmadan
/// (Faz 3.17). Kurallar `pushMesajiniYonlendir`'e çıkarıldı; servis yalnızca
/// eylemi yürütür.
void main() {
  group('ortaklık daveti', () {
    test('kimlik ve ad taşır', () {
      final e = pushMesajiniYonlendir({
        'type': NotificationService.partnerInviteType,
        'invite_id': 'inv1',
        'requester_name': '  Ayşe ',
      });
      expect(e, isA<OrtaklikDavetiEylemi>());
      final d = e as OrtaklikDavetiEylemi;
      expect(d.inviteId, 'inv1');
      expect(d.requesterName, 'Ayşe');
    });

    test('ad boşsa varsayılan ad — bildirim adsız kalmaz', () {
      final e = pushMesajiniYonlendir({
        'type': NotificationService.partnerInviteType,
        'invite_id': 'inv1',
        'requester_name': '   ',
      }) as OrtaklikDavetiEylemi;
      expect(e.requesterName, 'Bir kullanici');
    });

    test('kimliksiz davet yok sayılır — boş dokunuş üretmez', () {
      expect(
          pushMesajiniYonlendir({'type': NotificationService.partnerInviteType}),
          isA<YokEylemi>());
      expect(
          pushMesajiniYonlendir(
              {'type': NotificationService.partnerInviteType, 'invite_id': ''}),
          isA<YokEylemi>());
    });
  });

  group('sinyal bildirimi', () {
    test('notification bloğu öncelikli, data yedek', () {
      final e = pushMesajiniYonlendir(
        {'type': NotificationService.signalAlertType, 'title': 'data', 'asset_id': 'a1'},
        notificationTitle: 'Başlık',
        notificationBody: 'Gövde',
      ) as SinyalBildirimiEylemi;
      expect(e.title, 'Başlık');
      expect(e.body, 'Gövde');
      expect(e.assetId, 'a1');
    });

    test('hiç başlık yoksa "Yeni sinyal"', () {
      final e = pushMesajiniYonlendir({'type': NotificationService.signalAlertType})
          as SinyalBildirimiEylemi;
      expect(e.title, 'Yeni sinyal');
      expect(e.body, '');
      expect(e.assetId, '');
    });
  });

  test('analiz isteği slot taşır, yoksa manual', () {
    expect(
        (pushMesajiniYonlendir({
          'type': NotificationService.signalAnalyzeRequestType,
          'slot': 'morning'
        }) as AnalizIstegiEylemi)
            .slot,
        'morning');
    expect(
        (pushMesajiniYonlendir({'type': NotificationService.signalAnalyzeRequestType})
                as AnalizIstegiEylemi)
            .slot,
        'manual');
  });

  test('tanınmayan tür ve boş mesaj yok sayılır', () {
    expect(pushMesajiniYonlendir({'type': 'x'}), isA<YokEylemi>());
    expect(pushMesajiniYonlendir({}), isA<YokEylemi>());
  });

  test('cihaz kimliği 32 hex karakter, tek baytlar sıfırla doldurulur', () {
    var i = 0;
    final id = cihazKimligiUret(() => [0, 15, 255, 16][(i++) % 4]);
    expect(id.length, 32);
    expect(id, startsWith('000fff10'));
    expect(RegExp(r'^[0-9a-f]{32}$').hasMatch(id), isTrue);
  });

  test('eski token yalnızca dolu ve farklıysa silinir', () {
    expect(eskiTokenSilinmeli(null, 't2'), isFalse);
    expect(eskiTokenSilinmeli('', 't2'), isFalse);
    expect(eskiTokenSilinmeli('t2', 't2'), isFalse,
        reason: 'aynı token yeniden gelince gereksiz DELETE atılmamalı');
    expect(eskiTokenSilinmeli('t1', 't2'), isTrue);
  });
}
