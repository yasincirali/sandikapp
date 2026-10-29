import '../services/temettu_gecmisi.dart' show trGunu;
import '../utils/tr_format.dart' show fmtNum;
import 'price_alert.dart';

/// Günlük yüzde alarmı — "Gram altın bugün %2 düşerse haber ver" (0169,
/// Ar-Ge 2026-10-27 §1, yasin onayı).
///
/// **Neden [PriceAlert]'ten ayrı model ve ayrı tablo:** eski build'ler
/// `price_alerts.direction`'ı `below` değilse `above` diye okur; aynı
/// tabloya yeni bir yön yazmak eski sürümde alarmı uydurma bir hedefle
/// gösterirdi. Ayrı tabloyu eski istemci hiç görmez.
///
/// **Neden tek atış değil:** fiyat alarmı çalınca söner (hedefin etrafında
/// salınan fiyat dakikada bir bildirim üretirdi). Yüzde alarmında aynı risk
/// GÜNLÜK damgayla çözülür: TR gününde en çok bir kez çalar, ertesi gün
/// kendiliğinden yeniden nöbete girer — kullanıcı her gün yeniden kurmasın
/// diye var olan özellik budur.
class YuzdeAlarmi {
  final String id;
  final String userId;

  /// Fiyat alarmıyla aynı alfabe (`ALTIN_GRAM`, `USDTRY=X`, `KRIPTO:BTC`).
  final String symbol;
  final String label;

  /// Mutlak günlük değişim eşiği (%). Arayüz [esikler]'i sunar.
  final double esikPct;
  final YuzdeYon yon;
  final bool enabled;

  /// Son çaldığı TR günü (`YYYY-MM-DD`); hiç çalmadıysa `null`.
  final String? sonTetikGunu;

  /// Çaldığı andaki günlük yüzde ve fiyat — bildirimdeki sayıların kendisi.
  final double? sonTetikPct;
  final double? sonTetikFiyat;
  final DateTime createdAt;

  const YuzdeAlarmi({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.esikPct,
    required this.yon,
    required this.createdAt,
    this.enabled = true,
    this.sonTetikGunu,
    this.sonTetikPct,
    this.sonTetikFiyat,
  });

  /// Arayüzün sunduğu eşikler (±%1, ±%2, ±%3). Daha geniş liste karar
  /// yükü; dar liste altında/dövizde günlük oynaklığın olağan aralığı.
  static const esikler = <int>[1, 2, 3];

  /// Bekleyen alarm: kapatılmadıkça her gün nöbettedir (alarm tavanına
  /// sayılır). Bugün çalmış olması onu "pasif" yapmaz; yarın yine çalar.
  bool get isActive => enabled;

  /// Bugün (TR) zaten çaldı mı.
  bool bugunCaldi(DateTime simdi) => sonTetikGunu == yuzdeAlarmGunu(simdi);

  factory YuzdeAlarmi.fromMap(Map<String, dynamic> m) => YuzdeAlarmi(
        id: m['id'].toString(),
        userId: m['user_id']?.toString() ?? '',
        symbol: m['symbol']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        esikPct: _sayi(m['esik_pct']) ?? 0,
        yon: YuzdeYon.koddan(m['yon']?.toString()),
        enabled: m['enabled'] != false,
        sonTetikGunu: _gun(m['son_tetik_gunu']),
        sonTetikPct: _sayi(m['son_tetik_pct']),
        sonTetikFiyat: _sayi(m['son_tetik_fiyat']),
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'esik_pct': esikPct,
        'yon': yon.kod,
      };

  YuzdeAlarmi copyWith({bool? enabled}) => YuzdeAlarmi(
        id: id,
        userId: userId,
        symbol: symbol,
        label: label,
        esikPct: esikPct,
        yon: yon,
        createdAt: createdAt,
        enabled: enabled ?? this.enabled,
        sonTetikGunu: sonTetikGunu,
        sonTetikPct: sonTetikPct,
        sonTetikFiyat: sonTetikFiyat,
      );

  static String? _gun(Object? v) {
    final s = v?.toString();
    return s == null || s.length < 10 ? null : s.substring(0, 10);
  }

  /// PostgREST `numeric`'i metin olarak da döndürebilir.
  static double? _sayi(Object? v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
}

/// Yüzde alarmının yönü. Sunucu CHECK'i aynı üç kodu ister.
enum YuzdeYon {
  dusus('dusus'),
  yukselis('yukselis'),
  ikisi('ikisi');

  const YuzdeYon(this.kod);
  final String kod;

  /// Bilinmeyen kod `ikisi`ne düşer: yanlış yönde susmaktansa iki yönde de
  /// haber vermek kullanıcının istediğine daha yakın (satırı sunucu zaten
  /// geçerli yönle yazdı; bu yalnız bozuk/ileri sürüm satırına karşı).
  static YuzdeYon koddan(String? kod) =>
      values.where((y) => y.kod == kod).firstOrNull ?? YuzdeYon.ikisi;
}

/// TR takvim günü (`YYYY-MM-DD`) — sunucunun `istanbulGunu`'yla aynı gün
/// sınırı (UTC+3, [trGunu]); cihaz saat dilimi başka olsa da.
String yuzdeAlarmGunu(DateTime t) {
  final g = trGunu(t);
  String iki(int n) => n.toString().padLeft(2, '0');
  return '${g.year}-${iki(g.month)}-${iki(g.day)}';
}

/// Eşiğin metni: tam sayıysa "2", değilse "1,5" (listedeki adla aynı).
String yuzdeEsikMetni(double esik) {
  if (esik == esik.roundToDouble()) return esik.round().toString();
  return fmtNum(esik, digits: 1);
}

/// Takip satırındaki çanın kısa metni: "±%2", "−%2", "+%2".
/// Yön işaretle yazılır (renk körlüğü); tam cümleyi ekran okuyucu söyler.
String yuzdeKisaMetni(YuzdeAlarmi a) {
  final isaret = switch (a.yon) {
    YuzdeYon.dusus => '\u2212',
    YuzdeYon.yukselis => '+',
    YuzdeYon.ikisi => '±',
  };
  return '$isaret%${yuzdeEsikMetni(a.esikPct)}';
}

/// Takip satırındaki çanın özeti (Ar-Ge 27 Eki 12:45 #1, müşteri raporu
/// 13:15 "YAP", yasin 29 Eki "yap"): çan yalnız fiyat alarmını okuyordu;
/// gram altına yalnız yüzde alarmı kuran kişi satırda çan görmüyor, "kurdum
/// mu?" diye alarm ekranına gidiyordu.
///
/// Fiyat alarmı varsa o önde kalır (somut hedef, bugünkü davranış birebir);
/// yüzde alarmları "+N" sayısına girer. Yalnız yüzde alarmı varsa en dar
/// eşikli olan gösterilir (ilk çalacak olan). [ekSayi]: gösterge ve çizgi
/// alarmları (0170) yalnız "+N" sayısına girer.
class TakipCaniOzeti {
  /// Öndeki fiyat alarmı; yoksa `null` ve [yuzde] doludur.
  final PriceAlert? fiyat;
  final YuzdeAlarmi? yuzde;

  /// Öndeki dışındaki etkin alarm sayısı (iki tür birlikte).
  final int digerSayisi;

  const TakipCaniOzeti._(this.fiyat, this.yuzde, this.digerSayisi);
}

TakipCaniOzeti? takipCaniOzeti(
  Iterable<PriceAlert> fiyatAlarmlari,
  Iterable<YuzdeAlarmi> yuzdeAlarmlari, {
  required String sembol,
  double? guncelFiyat,
  int ekSayi = 0,
}) {
  final yuzdeler = [
    for (final a in yuzdeAlarmlari)
      if (a.isActive && a.symbol == sembol) a,
  ];
  final fiyat = etkinAlarmOzeti(fiyatAlarmlari, guncelFiyat: guncelFiyat);
  if (fiyat != null) {
    return TakipCaniOzeti._(
        fiyat.enYakin, null, fiyat.digerSayisi + yuzdeler.length + ekSayi);
  }
  // Yalnız gösterge/çizgi alarmı varsa çan yok: onların kısa bir "hedefi"
  // yok, satırda anlatılamaz (şerit onları tek özet çipiyle gösterir).
  if (yuzdeler.isEmpty) return null;
  var en = yuzdeler.first;
  for (final a in yuzdeler.skip(1)) {
    if (a.esikPct < en.esikPct) en = a;
  }
  return TakipCaniOzeti._(null, en, yuzdeler.length - 1 + ekSayi);
}
