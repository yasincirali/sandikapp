import 'price_alert.dart';

/// Fiyat alarmı hedefinin grafiğin GÖRÜNEN fiyat aralığına göre yeri.
enum AlarmCizgiKonumu {
  /// Hedef görünen aralıkta: kesikli yatay çizgi çizilir.
  icinde,

  /// Hedef aralığın üstünde: çizgi YOK, etiket "grafiğin üstünde" der.
  ustunde,

  /// Hedef aralığın altında: çizgi YOK, etiket "grafiğin altında" der.
  altinda,
}

/// Ana grafikte gösterilecek bir fiyat alarmı ve yeri.
class GrafikAlarmCizgisi {
  final PriceAlert alarm;
  final AlarmCizgiKonumu konum;

  const GrafikAlarmCizgisi(this.alarm, this.konum);

  /// Çizgi çizilir mi (yalnız aralık içindeyse).
  bool get cizilir => konum == AlarmCizgiKonumu.icinde;
}

/// Ana grafikte en çok kaç alarm gösterilir. Üçten fazlası çizgi yığını
/// olur ve fiyat çizgisini okutmaz (Ar-Ge 29 Eki 20:45 #2).
const grafikAlarmAzami = 3;

/// Varlık sayfası ana grafiğinde gösterilecek fiyat alarmları
/// (Ar-Ge 29 Eki 20:45 #2, yasin onayı).
///
/// Neden saf fonksiyon: aynı karar hem çizim alanında (çizgi) hem kartın üst
/// boşluğunda (etiket) okunur; ikisi ayrı yerde hesaplasa "çizgi yok ama
/// etiket grafikte diyor" ayrışması doğardı. `build()` içinde değil burada.
///
/// Kurallar:
/// - Yalnız ETKİN fiyat alarmı ([PriceAlert.isActive]). Tetiklenmiş/kapalı
///   alarm haber vermez; çizgisi "bekleyen eşik var" diye yanıltır.
///   Yüzde, gösterge ve çizgi alarmları buraya hiç gelmez: seviyeleri sabit
///   bir fiyat değildir.
/// - En çok [azami] alarm, güncel fiyata EN YAKIN olanlar önce (kişinin
///   "ne zaman haber gelecek" sorusu; takip çanı [etkinAlarmOzeti] ile aynı
///   ölçüt). [guncelFiyat] bilinmiyorsa liste sırası korunur — mesafe
///   uydurulmaz.
/// - Y ekseni GENİŞLETİLMEZ (Y ekseni fiyata göre; alarm bandı değiştirirse
///   grafik her alarmda başka ölçekte çizilirdi). Aralık dışındaki hedef
///   [AlarmCizgiKonumu.ustunde]/[AlarmCizgiKonumu.altinda] döner.
/// - [minY]/[maxY] HAM fiyat biriminde olmalı. LOG ve karşılaştırma kipinde
///   Y dönüştürülmüştür; çağıran bu fonksiyonu o kiplerde çağırmaz.
/// - Hedefi 0 ya da sonlu olmayan alarm ve geçersiz aralık (sonsuz,
///   `minY >= maxY`) gösterilmez: bilinmeyen yer uydurulmaz.
List<GrafikAlarmCizgisi> grafikAlarmCizgileri(
  Iterable<PriceAlert> alarmlar, {
  required double minY,
  required double maxY,
  double? guncelFiyat,
  int azami = grafikAlarmAzami,
}) {
  if (!minY.isFinite || !maxY.isFinite || minY >= maxY || azami <= 0) {
    return const [];
  }
  final etkin = [
    for (final a in alarmlar)
      if (a.isActive && a.targetPrice.isFinite && a.targetPrice > 0) a
  ];
  final f = guncelFiyat;
  if (f != null && f.isFinite && f > 0) {
    // Kararlı sıralama: eşit mesafede liste sırası (en yeni önce) kalır.
    final sirali = [for (var i = 0; i < etkin.length; i++) (i, etkin[i])]
      ..sort((a, b) {
        final m = (a.$2.targetPrice - f)
            .abs()
            .compareTo((b.$2.targetPrice - f).abs());
        return m != 0 ? m : a.$1.compareTo(b.$1);
      });
    etkin
      ..clear()
      ..addAll(sirali.map((e) => e.$2));
  }
  return [
    for (final a in etkin.take(azami))
      GrafikAlarmCizgisi(
        a,
        a.targetPrice > maxY
            ? AlarmCizgiKonumu.ustunde
            : a.targetPrice < minY
                ? AlarmCizgiKonumu.altinda
                : AlarmCizgiKonumu.icinde,
      ),
  ];
}

/// Ortalama maliyetin grafiğin GÖRÜNEN fiyat aralığına göre yeri
/// (Ar-Ge 1 Kas 08:45 #1, yasin "yap").
///
/// Alarm çizgisiyle AYNI kurallar ([grafikAlarmCizgileri]): Y ekseni
/// maliyete göre genişletilmez (genişletse grafik her pozisyonda başka
/// ölçekte çizilirdi); aralık dışındaysa çizgi yok, etiket "grafiğin
/// üstünde/altında" der. Maliyet ya da aralık geçersizse `null`: bilinmeyen
/// yer uydurulmaz. [minY]/[maxY] HAM fiyat biriminde; LOG ve Karşılaştır'da
/// çağrılmaz.
AlarmCizgiKonumu? maliyetCizgiKonumu(double? maliyet,
    {required double minY, required double maxY}) {
  if (maliyet == null || !maliyet.isFinite || maliyet <= 0) return null;
  if (!minY.isFinite || !maxY.isFinite || minY >= maxY) return null;
  if (maliyet > maxY) return AlarmCizgiKonumu.ustunde;
  if (maliyet < minY) return AlarmCizgiKonumu.altinda;
  return AlarmCizgiKonumu.icinde;
}
