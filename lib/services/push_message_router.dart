import 'notification_service.dart';

/// FCM veri mesajından çıkarılan eylem.
///
/// [RemotePushService] ön planda gelen her mesajı buradan geçirir. Sınıf
/// saf: Firebase'e, Supabase'e, bildirim eklentisine dokunmaz — bu yüzden
/// yönlendirme kuralları (varsayılan ad, başlık yedeği, eksik alanların
/// yutulması) istemci olmadan test edilir (Faz 3.17).
sealed class PushEylemi {
  const PushEylemi();
}

/// Ortaklık daveti: yerel bildirim gösterilir.
class OrtaklikDavetiEylemi extends PushEylemi {
  const OrtaklikDavetiEylemi({required this.inviteId, required this.requesterName});
  final String inviteId;
  final String requesterName;
}

/// Sunucunun ürettiği hazır sinyal bildirimi: Android ön planda kendisi
/// göstermez, uygulama gösterir.
class SinyalBildirimiEylemi extends PushEylemi {
  const SinyalBildirimiEylemi({
    required this.title,
    required this.body,
    required this.assetId,
  });
  final String title;
  final String body;
  final String assetId;
}

/// Diğer her görünür push (fiyat alarmı, yüzde alarmı, takip listesi,
/// brifing, özet, temettü, takvim, TÜFE): Android ön planda göstermez,
/// uygulama aynı kanalda yerel bildirim olarak basar (2026-10-29).
///
/// Neden (yasin, 2026-10-29: "tüm bildirimler push içinde okunabilir
/// olmalı"): yalnız sinyal ve davet yeniden basılıyordu; uygulama açıkken
/// gelen alarm Android'de HİÇ görünmüyordu (kullanıcı ancak çanı açınca
/// fark ediyordu). [data] dokunuşta push'a dokunulmuş gibi aynı varış
/// yerine gitsin diye taşınır (`handleRemoteMessageData`).
class GenelBildirimEylemi extends PushEylemi {
  const GenelBildirimEylemi({
    required this.title,
    required this.body,
    required this.channelId,
    required this.data,
  });
  final String title;
  final String body;
  final String channelId;
  final Map<String, String> data;
}

/// Tür → Android kanalı; sunucunun `channel_id`'si gelmezse yedek. Eşleme
/// sunucudaki gönderenlerle aynı (alarm/takip `alert_channel`, brifing/
/// temettü/takvim `brief_channel`, özet/TÜFE `summary_channel`).
String genelBildirimKanali(String? type) => switch (type) {
      NotificationService.priceAlertType ||
      'yuzde_alarm' ||
      'gosterge_alarm' ||
      'cizim_alarm' ||
      NotificationService.watchlistMoveType =>
        'alert_channel',
      NotificationService.weeklySummaryType ||
      NotificationService.monthlySummaryType ||
      NotificationService.inflationDayType =>
        'summary_channel',
      _ => 'brief_channel',
    };

/// Cron'dan "analiz zamanı" tetiği.
class AnalizIstegiEylemi extends PushEylemi {
  const AnalizIstegiEylemi(this.slot);
  final String slot;
}

/// Tanınmayan ya da eksik mesaj — hiçbir şey yapılmaz.
class YokEylemi extends PushEylemi {
  const YokEylemi();
}

/// Ön plan mesajını eyleme çevirir.
///
/// [data] FCM `message.data`; [notificationTitle]/[notificationBody] varsa
/// `message.notification` alanları (sunucu bazen yalnızca `notification`
/// bloğunda başlık gönderir, bazen `data` içinde — ikisi de kabul).
///
/// [androidChannelId]: `message.notification.android.channelId` — genel
/// dalda yerel bildirim aynı kanala basılır ki kullanıcının kanal ayarı
/// (kapalı/sessiz) ön planda da geçerli olsun.
PushEylemi pushMesajiniYonlendir(
  Map<String, dynamic> data, {
  String? notificationTitle,
  String? notificationBody,
  String? androidChannelId,
}) {
  final type = data['type']?.toString();

  if (type == NotificationService.partnerInviteType) {
    final inviteId = data['invite_id']?.toString();
    // Kimliksiz davet açılamaz; bildirim göstermek boş bir dokunuş üretir.
    if (inviteId == null || inviteId.isEmpty) return const YokEylemi();
    final ad = data['requester_name']?.toString().trim();
    return OrtaklikDavetiEylemi(
      inviteId: inviteId,
      requesterName: (ad == null || ad.isEmpty) ? 'Bir kullanici' : ad,
    );
  }

  if (type == NotificationService.signalAlertType) {
    return SinyalBildirimiEylemi(
      title: notificationTitle ?? data['title']?.toString() ?? 'Yeni sinyal',
      body: notificationBody ?? data['body']?.toString() ?? '',
      assetId: data['asset_id']?.toString() ?? '',
    );
  }

  if (type == NotificationService.signalAnalyzeRequestType) {
    return AnalizIstegiEylemi(data['slot']?.toString() ?? 'manual');
  }

  // Görünür bildirim taşıyan her diğer tür. Başlıksız (yalnız veri) mesaj
  // sessiz tetiktir; ona bildirim basılmaz.
  final baslik = notificationTitle?.trim() ?? '';
  if (type != null && type.isNotEmpty && baslik.isNotEmpty) {
    final kanal = androidChannelId?.trim() ?? '';
    return GenelBildirimEylemi(
      title: baslik,
      body: notificationBody ?? '',
      channelId: kanal.isNotEmpty ? kanal : genelBildirimKanali(type),
      data: {
        for (final e in data.entries)
          if (e.value != null) e.key: e.value.toString(),
      },
    );
  }

  return const YokEylemi();
}

/// Cihaz kimliği üretimi — 16 rastgele bayt, 32 hex karakter.
///
/// [rastgeleBayt] enjekte edilir: üretimde `Random.secure()`, testte sabit.
String cihazKimligiUret(int Function() rastgeleBayt) =>
    List.generate(16, (_) => rastgeleBayt())
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();

/// Token değişince eski satır silinmeli mi?
///
/// Yalnızca gerçekten FARKLI ve dolu bir eski token varsa; aksi halde
/// gereksiz DELETE (ilk kayıt, aynı token yeniden gelmesi).
bool eskiTokenSilinmeli(String? eski, String yeni) =>
    eski != null && eski.isNotEmpty && eski != yeni;
