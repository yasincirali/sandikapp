/// Gösterge ve çizgi alarmları (0170) — "fiyat EMA50'yi keserse / çizdiğim
/// trend çizgisine değerse haber ver".
///
/// ## Neden (yasin, 2026-10-29)
/// *"Gösterge ya da çizgiye değdiğinde push gelmesi yapılabilir mi?"* — üç
/// seçeneğin üçü de onaylandı: yatay çizgiden normal fiyat alarmı
/// ([PriceAlert], ücretsiz), gösterge alarmı ve trend çizgisi/ışın alarmı
/// (ikisi Premium). Bu dosya Premium olan iki türün modeli.
///
/// ## Neden [PriceAlert]'ten ayrı (0169 ile aynı gerekçe)
/// Seviye her an değişir (EMA, eğik çizgi); `price_alerts` sabit hedef
/// ister ve eski build `direction`'ı `below` değilse `above` okur. Ayrı
/// tabloyu eski istemci hiç görmez.
///
/// ## Tek atış
/// Değerlendirme sunucuda (`_shared/seviye_alarmi.ts`): fiyat seviyenin
/// öbür tarafına GEÇİNCE (yön uyuyorsa) çalar ve fiyat alarmı gibi kapanır
/// (`triggeredAt`). Kurulduğu ilk turda yalnız taraf yazılır — o anda zaten
/// öbür taraftaysa "kesti" demek uydurma olurdu.
library;

/// Seviyenin hangi yönde kesilmesi beklenir. Sunucu CHECK'i aynı üç kodu ister.
enum SeviyeYon {
  /// Fiyat seviyeyi aşağıdan yukarı keserse.
  yukari('yukari'),

  /// Yukarıdan aşağı keserse.
  asagi('asagi'),

  /// Hangi yöne olursa.
  herIkisi('her_ikisi');

  const SeviyeYon(this.kod);
  final String kod;

  /// Bilinmeyen kod `herIkisi`ne düşer (yalnız bozuk/ileri sürüm satırına
  /// karşı; 0169 `YuzdeYon.koddan` ile aynı gerekçe).
  static SeviyeYon koddan(String? kod) =>
      values.where((y) => y.kod == kod).firstOrNull ?? SeviyeYon.herIkisi;

  /// Güncel fiyat seviyenin altındaysa beklenen geçiş yukarıdır, üstündeyse
  /// aşağı; eşitse iki yön de (fiyat alarmının "yön seçtirilmez, türetilir"
  /// kuralı — `PriceAlert.suggestDirection`).
  static SeviyeYon fiyattan({required double guncel, required double seviye}) {
    if (!(guncel > 0) || !seviye.isFinite) return SeviyeYon.herIkisi;
    if (guncel < seviye) return SeviyeYon.yukari;
    if (guncel > seviye) return SeviyeYon.asagi;
    return SeviyeYon.herIkisi;
  }
}

/// Alarm kurulabilen göstergeler. Kod sunucuyla aynı
/// (`_shared/gosterge_alarmi.ts › GostergeKodu`). Bollinger standart (20, 2σ).
enum GostergeKodu {
  ema20('ema20'),
  ema50('ema50'),
  ema200('ema200'),
  sma20('sma20'),
  bbUst('bb_ust'),
  bbAlt('bb_alt');

  const GostergeKodu(this.kod);
  final String kod;

  static GostergeKodu? koddan(String? kod) =>
      values.where((g) => g.kod == kod).firstOrNull;

  /// Çipte ve listede okunan kısa ad. Bollinger'in tam adı l10n'da
  /// (bant adı dile göre değişir); EMA/MA kısaltması evrenseldir.
  String get kisaAd => switch (this) {
        GostergeKodu.ema20 => 'EMA20',
        GostergeKodu.ema50 => 'EMA50',
        GostergeKodu.ema200 => 'EMA200',
        GostergeKodu.sma20 => 'MA20',
        GostergeKodu.bbUst => 'BB↑',
        GostergeKodu.bbAlt => 'BB↓',
      };
}

/// PostgREST `numeric`'i metin olarak da döndürebilir.
double? _sayi(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

DateTime? _zaman(Object? v) =>
    v == null ? null : DateTime.tryParse(v.toString());

class GostergeAlarmi {
  final String id;
  final String userId;

  /// Fiyat alarmıyla aynı alfabe (`THYAO.IS`, `AAPL`, `KRIPTO:BTC`).
  final String symbol;
  final String label;
  final GostergeKodu gosterge;
  final SeviyeYon yon;
  final bool enabled;
  final DateTime? triggeredAt;

  /// Çaldığı andaki fiyat ve seviye — bildirimdeki sayıların kendisi.
  final double? tetikFiyat;
  final double? tetikSeviye;
  final DateTime createdAt;

  const GostergeAlarmi({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.gosterge,
    required this.yon,
    required this.createdAt,
    this.enabled = true,
    this.triggeredAt,
    this.tetikFiyat,
    this.tetikSeviye,
  });

  /// Nöbette mi (alarm tavanına sayılır). Çalan alarm kapanır.
  bool get isActive => enabled && triggeredAt == null;

  /// Bilinmeyen gösterge kodlu satır `null` döner ve listeden düşer: ileri
  /// sürümün yeni göstergesini eski build yanlış adla göstermesin.
  static GostergeAlarmi? fromMap(Map<String, dynamic> m) {
    final g = GostergeKodu.koddan(m['gosterge']?.toString());
    if (g == null) return null;
    return GostergeAlarmi(
      id: m['id'].toString(),
      userId: m['user_id']?.toString() ?? '',
      symbol: m['symbol']?.toString() ?? '',
      label: m['label']?.toString() ?? '',
      gosterge: g,
      yon: SeviyeYon.koddan(m['yon']?.toString()),
      enabled: m['enabled'] != false,
      triggeredAt: _zaman(m['triggered_at']),
      tetikFiyat: _sayi(m['tetik_fiyat']),
      tetikSeviye: _sayi(m['tetik_seviye']),
      createdAt: _zaman(m['created_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'gosterge': gosterge.kod,
        'yon': yon.kod,
      };
}

class CizimAlarmi {
  final String id;
  final String userId;
  final String symbol;
  final String label;

  /// Cihazdaki çizimin kimliği (`GrafikCizimi.id`).
  final String cizimId;

  /// Alarm kurulduğundaki çizim biçimi (`cizimImzasi`); çizim taşınınca
  /// istemci farkı bununla görür ve alarmı yeni doğruya taşır.
  final String? cizimImzasi;

  /// Doğru (t epoch ms, p alarm biriminde); sunucu duvar saatiyle okur.
  final int t1;
  final double p1;
  final int t2;
  final double p2;

  /// Işın mı (t2'den sonra da uzar), parça mı.
  final bool uzanir;
  final SeviyeYon yon;
  final bool enabled;
  final DateTime? triggeredAt;
  final double? tetikFiyat;
  final double? tetikSeviye;
  final DateTime createdAt;

  const CizimAlarmi({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.cizimId,
    required this.t1,
    required this.p1,
    required this.t2,
    required this.p2,
    required this.uzanir,
    required this.yon,
    required this.createdAt,
    this.cizimImzasi,
    this.enabled = true,
    this.triggeredAt,
    this.tetikFiyat,
    this.tetikSeviye,
  });

  bool get isActive => enabled && triggeredAt == null;

  static CizimAlarmi? fromMap(Map<String, dynamic> m) {
    final t1 = _sayi(m['t1']), t2 = _sayi(m['t2']);
    final p1 = _sayi(m['p1']), p2 = _sayi(m['p2']);
    if (t1 == null || t2 == null || p1 == null || p2 == null) return null;
    return CizimAlarmi(
      id: m['id'].toString(),
      userId: m['user_id']?.toString() ?? '',
      symbol: m['symbol']?.toString() ?? '',
      label: m['label']?.toString() ?? '',
      cizimId: m['cizim_id']?.toString() ?? '',
      cizimImzasi: m['cizim_imzasi']?.toString(),
      t1: t1.round(),
      p1: p1,
      t2: t2.round(),
      p2: p2,
      uzanir: m['uzanir'] == true,
      yon: SeviyeYon.koddan(m['yon']?.toString()),
      enabled: m['enabled'] != false,
      triggeredAt: _zaman(m['triggered_at']),
      tetikFiyat: _sayi(m['tetik_fiyat']),
      tetikSeviye: _sayi(m['tetik_seviye']),
      createdAt: _zaman(m['created_at']) ?? DateTime.now(),
    );
  }

  /// Doğrunun [simdiMs] anındaki seviyesi — Alarmlarım satırı "çizgi şu
  /// an ₺…" yazsın diye (uçtan uca test 2026-10-29: satır seviyesiz
  /// "altına inince" diyordu). Sunucunun `cizgiDegeri`yle aynı kural
  /// (`_shared/cizim_alarmi.ts`): parça bittiyse ya da değer sıfırın
  /// altındaysa `null` (uydurma sayı yok). Başlamamış doğruda başlangıç
  /// seviyesi: nöbet oradan başlayacak.
  double? seviye(int simdiMs) {
    if (t2 <= t1) return null;
    if (!uzanir && simdiMs > t2) return null;
    final t = simdiMs < t1 ? t1 : simdiMs;
    final v = p1 + (p2 - p1) * (t - t1) / (t2 - t1);
    return v.isFinite && v > 0 ? v : null;
  }

  /// Doğru alanları — ekleme ve "çizgi taşındı" güncellemesi ortak.
  Map<String, dynamic> dogruMap() => {
        'cizim_imzasi': cizimImzasi,
        't1': t1,
        'p1': p1,
        't2': t2,
        'p2': p2,
        'uzanir': uzanir,
        'yon': yon.kod,
      };

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'cizim_id': cizimId,
        ...dogruMap(),
      };
}
