/// Kullanıcının kurduğu fiyat alarmı.
///
/// [symbol] fiyat kaynağının anladığı koddur (`THYAO.IS`, `ALTIN_GRAM`,
/// `USDTRY=X`); [label] kullanıcıya gösterilen addır. İkisi ayrı tutulur
/// çünkü bildirimde kod okunmaz — "ALTIN_GRAM 5.400'ü geçti" kimseye bir
/// şey ifade etmez.
class PriceAlert {
  final String id;
  final String userId;
  final String symbol;
  final String label;
  final double targetPrice;

  /// `above` → fiyat hedefe ulaşınca · `below` → hedefin altına inince.
  final String direction;

  final bool enabled;

  /// Tetiklendiği an. Tek atış alarmda doluysa alarm susmuştur; kullanıcı
  /// yeniden kurabilir. Tekrarlı alarmda ([tekrar]) "çaldı, fiyatın geri
  /// dönmesini bekliyor" demektir; sunucu dönüşte temizler.
  final DateTime? triggeredAt;
  final DateTime createdAt;

  /// "Her geçişte haber ver" (0171). `false` → tek atış (0046, varsayılan;
  /// kolon yoksa da `false`). `true` → çalınca sönmez; fiyat hedefin öbür
  /// tarafına %0,5 geçince sunucu yeniden nöbete alır, günde en çok 3 kez.
  final bool tekrar;

  /// Son çalış anı (0171). Nöbete dönüşte [triggeredAt] silinir, bu kalır:
  /// listedeki "son çaldı" satırı bunu okur.
  final DateTime? sonTetikAt;

  const PriceAlert({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.targetPrice,
    required this.direction,
    required this.enabled,
    required this.createdAt,
    this.triggeredAt,
    this.tekrar = false,
    this.sonTetikAt,
  });

  bool get isAbove => direction == 'above';

  /// Hâlâ beklemede mi? (kapatılmamış ve tetiklenmemiş)
  ///
  /// 0171: açık tekrarlı alarm çalmış olsa da BEKLEYENDİR — kendiliğinden
  /// nöbete döner, kişi bir şey yapmaz. Sayımlar (tavan, çan, rozet) onu
  /// etkin sayar; Alarmlarım onu "Çalanlar"a düşürmez.
  bool get isActive => enabled && (tekrar || triggeredAt == null);

  /// Çalıp susmuş tek atış alarm: "yeniden kur" isteyen tek durum.
  /// Tekrarlı alarm hiç bu duruma düşmez.
  bool get sondu => !tekrar && triggeredAt != null;

  /// Gösterilecek son çalış: [sonTetikAt], yoksa (0171 öncesi satır)
  /// [triggeredAt]. Hiç çalmadıysa `null`.
  DateTime? get sonCalis => sonTetikAt ?? triggeredAt;

  factory PriceAlert.fromMap(Map<String, dynamic> m) => PriceAlert(
        id: m['id'].toString(),
        userId: m['user_id'].toString(),
        symbol: m['symbol']?.toString() ?? '',
        label: m['label']?.toString() ?? '',
        targetPrice: (m['target_price'] as num?)?.toDouble() ?? 0,
        direction: m['direction']?.toString() == 'below' ? 'below' : 'above',
        enabled: m['enabled'] == true,
        triggeredAt: m['triggered_at'] == null
            ? null
            : DateTime.tryParse(m['triggered_at'].toString()),
        createdAt:
            DateTime.tryParse(m['created_at']?.toString() ?? '') ??
                DateTime.now(),
        // Kolon yoksa (0171 öncesi şema) tek atış.
        tekrar: m['tekrar'] == true,
        sonTetikAt: m['son_tetik_at'] == null
            ? null
            : DateTime.tryParse(m['son_tetik_at'].toString()),
      );

  /// [tekrar] yalnız açıkken yazılır: tek atış alarmın insert'i 0171'den
  /// önceki şemada da (kolon yokken) birebir eskisi gibi geçer.
  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'target_price': targetPrice,
        'direction': direction,
        if (tekrar) 'tekrar': true,
      };

  /// Aynı alarm, değişen alanlarla (provider'ın yerel yamaları).
  /// [triggeredAt]'i silmek için [damgasiz].
  PriceAlert copyWith({
    String? label,
    double? targetPrice,
    String? direction,
    bool? enabled,
    bool? tekrar,
    bool damgasiz = false,
  }) =>
      PriceAlert(
        id: id,
        userId: userId,
        symbol: symbol,
        label: label ?? this.label,
        targetPrice: targetPrice ?? this.targetPrice,
        direction: direction ?? this.direction,
        enabled: enabled ?? this.enabled,
        triggeredAt: damgasiz ? null : triggeredAt,
        createdAt: createdAt,
        tekrar: tekrar ?? this.tekrar,
        sonTetikAt: sonTetikAt,
      );

  /// Verilen fiyat için mantıklı bir yön önerir.
  ///
  /// Kullanıcı hedefi yazdıktan sonra yönü ayrıca seçmek zorunda kalmasın:
  /// güncel fiyatın ÜSTÜNDE bir hedef "yükselince", ALTINDA bir hedef
  /// "düşünce" demektir. Yanlış yön seçimi alarmın hiç çalışmaması demek
  /// olurdu ve kullanıcı sebebini anlamazdı.
  static String suggestDirection({
    required double currentPrice,
    required double targetPrice,
  }) =>
      targetPrice >= currentPrice ? 'above' : 'below';
}

/// Bir sembolün ETKİN alarmlarının satır özeti: gösterilecek tek hedef +
/// kalan etkin alarm sayısı (takip listesi çanı, 2026-10-26).
class EtkinAlarmOzeti {
  /// Güncel fiyata en yakın etkin alarm.
  final PriceAlert enYakin;

  /// [enYakin] dışında kalan etkin alarm sayısı ("+N").
  final int digerSayisi;

  const EtkinAlarmOzeti(this.enYakin, this.digerSayisi);
}

/// [alarmlar] içinden yalnız ETKİN olanları ([PriceAlert.isActive]) alır,
/// güncel fiyata en yakın hedefi seçer. Etkin alarm yoksa `null`.
///
/// **Neden en yakın:** satırda tek hedefe yer var; kullanıcının "ne zaman
/// haber gelecek" sorusunun cevabı fiyata en yakın eşiktir, en yeni ya da en
/// eski alarm değil. Tetiklenmiş/kapalı alarm haber vermeyeceği için sayılmaz
/// — çan "bekleyen bir alarm var" demektir.
///
/// [guncelFiyat] bilinmiyorsa (null/0) mesafe hesaplanamaz; sayı uydurulmaz,
/// listenin sırası (provider: en yeni önce) korunur ve ilk etkin alarm
/// gösterilir. Eşit mesafede de listedeki ilk kazanır (deterministik).
EtkinAlarmOzeti? etkinAlarmOzeti(Iterable<PriceAlert> alarmlar,
    {double? guncelFiyat}) {
  final etkin = [for (final a in alarmlar) if (a.isActive) a];
  if (etkin.isEmpty) return null;
  var enYakin = etkin.first;
  final f = guncelFiyat;
  if (f != null && f > 0) {
    var enKisa = (enYakin.targetPrice - f).abs();
    for (final a in etkin.skip(1)) {
      final m = (a.targetPrice - f).abs();
      if (m < enKisa) {
        enKisa = m;
        enYakin = a;
      }
    }
  }
  return EtkinAlarmOzeti(enYakin, etkin.length - 1);
}
