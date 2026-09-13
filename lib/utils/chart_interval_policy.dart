import '../services/history_service.dart';

/// Dönem (GÜNLÜK/1H/1A/6A/1Y) → hangi bar aralıkları seçilebilir?
///
/// ## Neden ayrı bir politika katmanı
/// Dönem seçici ile bar seçici birbirinden BAĞIMSIZ olsaydı anlamsız
/// kombinasyonlar doğardı: "1Y dönemi + 1 dakikalık bar" 365 gün × ~486
/// bar/gün ister — Yahoo bunu vermez (dakikalık veride 8 GÜN duvarı var),
/// verseydi de yüz binlerce nokta çizilemezdi. Tersi de bozuk: "GÜNLÜK dönem
/// + 1 haftalık bar" tek nokta üretir, grafik diye bir şey kalmaz.
///
/// Sektörde (TradingView, Yahoo Finance, Investing.com, Bloomberg) bu problem
/// TEK BİÇİMDE çözülmüş: **dönem seçilir, bar listesi ona göre yeniden
/// kurulur.** Geçersiz kombinasyon UI'da hiç var olmaz. Bu dosya o eşlemenin
/// TEK KAYNAĞIDIR — hem seçici hem controller buradan okur.
///
/// ## İki kısıt türü — karıştırma
/// 1. **Sağlayıcı duvarı (fiziksel).** Ölçüldü (2026-09-13, THYAO.IS):
///    `1m` yalnızca 8 gün, `5m`/`15m` yalnızca 1 ay geriye veri veriyor;
///    aşılınca `Unprocessable Entity`. Bu satırlar TERCİH DEĞİL.
/// 2. **Okunabilirlik (tasarım).** `pickForSpan`'in benimsediği ~30-300
///    nokta hedefi. Örn. GÜNLÜK'te saatlik bar çalışır ama BIST seansı
///    ~8 saat olduğu için 8 nokta üretir: çizgi değil, merdiven.
///
/// ## Sinyallerle ilişkisi: YOK
/// Bu politika ÇİZİM içindir. Sinyal üretimi günlük bara sabittir; gerekçesi
/// [ResolutionTier] dokümantasyonunda. Bar seçmek bildirim davranışını
/// DEĞİŞTİRMEZ — görsel bir tercihi push davranışına bağlamak, geri
/// alınamayan bir dış etkiyi (bildirim + DB yazımı) salt görüntüye
/// bağlamak olurdu.
class ChartIntervalPolicy {
  const ChartIntervalPolicy._();

  /// Gün içi ("GÜNLÜK" sekmesi) dönemin gün sayısı.
  ///
  /// `_periods[0]` `days: 0` taşır (takvim günü, kayan pencere değil).
  /// Politikanın tek giriş anahtarı gün sayısı olduğundan bu değer
  /// adlandırıldı; çıplak `0` çağıran tarafta okunmaz kalırdı.
  static const int gunIciGun = 0;

  /// [periodDays] döneminde seçilebilecek bar aralıkları (ince → kaba).
  ///
  /// Asla boş dönmez: her dönemin en az bir geçerli barı vardır, aksi
  /// halde o dönemde grafik hiç çizilemezdi.
  static List<ResolutionTier> gecerliBarlar(int periodDays) {
    // GÜNLÜK (takvim günü). 1sa YOK: BIST seansı ~8 saat → 8 nokta.
    if (periodDays <= gunIciGun) {
      return const [
        ResolutionTier.oneMin,
        ResolutionTier.fiveMin,
        ResolutionTier.fifteenMin,
      ];
    }
    // 1H (7 gün). 1dk YOK: 8 günlük duvara dayanıyor ve ~3400 nokta üretir.
    if (periodDays <= 7) {
      return const [
        ResolutionTier.fiveMin,
        ResolutionTier.fifteenMin,
        ResolutionTier.hourly,
      ];
    }
    // 1A (30 gün). 5dk YOK: Yahoo `1mo` sınırında ve 2342 nokta üretir.
    if (periodDays <= 30) {
      return const [
        ResolutionTier.fifteenMin,
        ResolutionTier.hourly,
        ResolutionTier.daily,
      ];
    }
    // 3A+ : intraday veri YOK (`15m`/`5m`, `3mo` range'inde reddediliyor).
    // Geriye kalan tek soru günlük mü haftalık mı.
    return const [ResolutionTier.daily, ResolutionTier.weekly];
  }

  /// [periodDays] döneminin varsayılan barı — kullanıcı seçim yapmamışsa.
  ///
  /// ~30-300 nokta hedefine göre: GÜNLÜK'te 5dk (~98 nokta/seans), 1H'de
  /// 15dk (~220), 1A'da 1sa (~208), 6A'da 1G (~125), 1Y'de 1H (~52).
  ///
  /// Merdiven [gecerliBarlar] ile TUTARLI olmak zorunda: döndürülen değer
  /// her zaman o dönemin geçerli listesinde bulunmalı. Test bunu doğrular.
  static ResolutionTier varsayilanBar(int periodDays) {
    if (periodDays <= gunIciGun) return ResolutionTier.fiveMin;
    if (periodDays <= 7) return ResolutionTier.fifteenMin;
    if (periodDays <= 30) return ResolutionTier.hourly;
    if (periodDays <= 180) return ResolutionTier.daily;
    return ResolutionTier.weekly;
  }

  /// Kullanıcının mevcut seçimini yeni döneme uyarlar.
  ///
  /// **Kural: seçim geçerliyse KORUNUR, değilse en yakın geçerliye düşer.**
  ///
  /// Her dönem değişiminde varsayılana sıfırlamak, dönemler arası gezinen
  /// kullanıcının tercihini sürekli ezerdi: 1H'de 15dk seçen biri 1A'ya
  /// geçip geri döndüğünde seçimini kaybederdi. Yahoo Finance ve TradingView
  /// ikisi de seçimi korur. Aynı disiplin bu projede 6A yüzdelik diliminde
  /// de uygulandı ("başka döneme gidip dönünce rakam korunuyor").
  ///
  /// "En yakın" bar SÜRESİ üzerinden ölçülür, enum SIRASI üzerinden değil —
  /// enum'a ileride bir üye eklenirse sıra tabanlı mesafe sessizce bozulurdu.
  /// Eşitlikte KABA olan kazanır: veri yokluğundan boş grafik göstermektense
  /// bir kademe kaba çizmek yeğdir.
  static ResolutionTier uyarla(ResolutionTier secili, int periodDays) {
    final gecerli = gecerliBarlar(periodDays);
    if (gecerli.contains(secili)) return secili;

    final hedef = secili.barSuresi.inSeconds;
    var enIyi = gecerli.first;
    var enIyiFark = (enIyi.barSuresi.inSeconds - hedef).abs();
    for (final t in gecerli.skip(1)) {
      final fark = (t.barSuresi.inSeconds - hedef).abs();
      // `<=` → eşitlikte SONRAKİ (daha kaba) kazanır.
      if (fark <= enIyiFark) {
        enIyi = t;
        enIyiFark = fark;
      }
    }
    return enIyi;
  }

  /// Bar otomatik düşürüldüğünde kullanıcıya gösterilecek açıklama.
  ///
  /// Sessiz düşüş kafa karıştırır: 1A'da 15dk bakan kullanıcı 6A'ya geçince
  /// grafik birden seyrekleşir ve sebebi görünmez. Seçim korunduysa (`eski
  /// == yeni`) `null` döner ve hiçbir şey gösterilmez.
  static String? degisimAciklamasi(ResolutionTier eski, ResolutionTier yeni) {
    if (eski == yeni) return null;
    return '${eski.etiket} bu dönemde kullanılamıyor — '
        '${yeni.etiket} bara geçildi.';
  }
}
