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
PushEylemi pushMesajiniYonlendir(
  Map<String, dynamic> data, {
  String? notificationTitle,
  String? notificationBody,
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
