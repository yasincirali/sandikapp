import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Ücretsiz alarm tavanı dolu (yasin 2026-11-12: "alarm ekleme kısmında
/// sonsuz alarma gidebilecek bir bug var").
///
/// İki kaynaktan gelir, ekranda tek uyarıya (`alarmSiniriUyarisi`, Premium
/// yolu dahil) bağlanır:
///  - istemci: yazmadan hemen önceki yeniden sayım tavanı dolu buldu;
///  - sunucu: 0181 tetikleyicisi yazmayı `alarm_siniri` mesajıyla reddetti.
///
/// Neden ayrı bir tür: alarm kurma sayfası hatayı kendi alanının altında
/// yazar (snackbar modalın altında kalırdı). Tavan ise bir "hata" değil,
/// Premium kapısıdır; sayfa bunu tanıyıp kapanır ve çağıran ortak uyarıyı
/// gösterir. Ham sunucu metni hiçbir yolda kullanıcıya gitmez.
class AlarmSiniriDolu implements Exception {
  const AlarmSiniriDolu();

  @override
  String toString() => 'AlarmSiniriDolu';
}

/// Sunucu tetikleyicisinin (0181) hata mesajındaki sabit işaret.
const alarmSiniriSunucuKodu = 'alarm_siniri';

/// [e] tavan kararı mı (istemci ya da sunucu). Sunucu hatası mesajla
/// tanınır (`CihazOturumuService.kuralHatasi` deseni); SQLSTATE 54000
/// başka sınırlarla (ör. `cihaz_siniri`) ortak olduğu için tek başına
/// yetmez.
bool alarmSiniriHatasiMi(Object e) =>
    e is AlarmSiniriDolu ||
    (e is PostgrestException && e.message.contains(alarmSiniriSunucuKodu));
