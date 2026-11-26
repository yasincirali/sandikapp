/// Saatli fiyat bildirimi (0188, yasin 2026-11-26): kullanıcının seçtiği
/// saatlerde bir varlığın o anki fiyatı push olarak gelir. Sunucu eşi
/// `saatli_bildirimler`; gönderen `saatli-bildirim` fonksiyonu.
///
/// Saat TR gününün DAKİKASI (0 = 00:00, 1425 = 23:45), 15'in katı. Gün bit
/// maskesi: bit 0 pazartesi … bit 6 pazar (ISO), 127 = her gün — sunucu
/// `_shared/saatli_bildirim.ts` aynı sırayı kullanır. Arayüz bugün gün
/// seçtirmez (tasarım: varsayılan her gün); alan okunur ve korunur.
class SaatliBildirim {
  /// Varlık başına en çok saat; sunucu tetikleyicisi de aynı sınırı uygular.
  static const enFazlaSaat = 5;

  /// Kullanıcı başına en çok aktif varlık (sunucuyla aynı).
  static const enFazlaVarlik = 5;

  /// Saat adımı, dakika.
  static const adimDk = 15;

  static const herGun = 127;

  final String id;
  final String userId;
  final String symbol;
  final String label;
  final List<int> saatler;
  final int gunler;
  final bool aktif;
  final DateTime createdAt;

  const SaatliBildirim({
    required this.id,
    required this.userId,
    required this.symbol,
    required this.label,
    required this.saatler,
    this.gunler = herGun,
    this.aktif = true,
    required this.createdAt,
  });

  factory SaatliBildirim.fromMap(Map<String, dynamic> m) => SaatliBildirim(
        id: m['id'] as String,
        userId: m['user_id'] as String,
        symbol: m['symbol'] as String,
        label: (m['label'] as String?) ?? m['symbol'] as String,
        saatler: [
          for (final s in (m['saatler'] as List?) ?? const []) (s as num).toInt()
        ]..sort(),
        gunler: (m['gunler'] as num?)?.toInt() ?? herGun,
        aktif: (m['aktif'] as bool?) ?? true,
        createdAt: DateTime.tryParse(m['created_at']?.toString() ?? '') ??
            DateTime.now(),
      );

  Map<String, dynamic> toInsertMap() => {
        'user_id': userId,
        'symbol': symbol,
        'label': label,
        'saatler': saatler,
        'gunler': gunler,
        'aktif': aktif,
      };

  SaatliBildirim copyWith({List<int>? saatler}) => SaatliBildirim(
        id: id,
        userId: userId,
        symbol: symbol,
        label: label,
        saatler: saatler ?? this.saatler,
        gunler: gunler,
        aktif: aktif,
        createdAt: createdAt,
      );

  /// Sunucu tetikleyicisinin şekil kuralı: 1–5 saat, tekil, 15'in katı,
  /// 0..1425. İstemci kaydetmeden önce sorar ki kullanıcı ret görmesin.
  static bool saatlerGecerli(List<int> saatler) =>
      saatler.isNotEmpty &&
      saatler.length <= enFazlaSaat &&
      saatler.toSet().length == saatler.length &&
      saatler.every((s) => s >= 0 && s <= 1425 && s % adimDk == 0);

  /// "09:00".
  static String saatMetni(int dakika) =>
      '${(dakika ~/ 60).toString().padLeft(2, '0')}:'
      '${(dakika % 60).toString().padLeft(2, '0')}';

  /// Seçilebilir bütün saatler (00:00 … 23:45).
  static List<int> get tumSaatler =>
      [for (var d = 0; d < 24 * 60; d += adimDk) d];

  /// Saat kullanıcının sessiz penceresine düşüyor mu. Pencere saat
  /// cinsinden (0-23, sarmalı olabilir; sunucu `sessizSaatteMi` ile aynı
  /// kural). Saatli bildirim sessiz saatte de gönderilir (kullanıcının
  /// açıkça seçtiği saat); bu yalnız seçerken uyarı içindir.
  static bool sessizPencerede(int dakika, int? bas, int? son) {
    if (bas == null || son == null || bas == son) return false;
    final saat = dakika ~/ 60;
    return bas < son ? saat >= bas && saat < son : saat >= bas || saat < son;
  }
}
