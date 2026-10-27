import '../services/temettu_gecmisi.dart' show trGunu;

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
