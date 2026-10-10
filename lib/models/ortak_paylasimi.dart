/// Sahibin bir ortağa hangi portföylerini gösterdiği
/// (`public.ortak_paylasimlari`, 0135).
///
/// ## Neden sunucuda (yasin, 2026-10-10)
/// "Ortağıma hangi portföyün görüneceğini seçebilmeliyim." Seçim yalnız
/// istemcide süzülseydi ortağın cihazı yine bütün lotları indirirdi; sınır
/// RLS'te (`assets_partner_read` → `ortak_portfoyu_gorur`). Bu sınıf o
/// kuralın istemci eşidir ([gorur]) — yalnız ÖNİZLEME ve etiket için; ortak
/// tarafında süzme sunucunun işidir.
///
/// Satır yoksa ortak her şeyi görür ([OrtakPaylasimi.hepsi]) — 0135 öncesi
/// davranış; eski sürüm hiç satır yazmaz.
class OrtakPaylasimi {
  const OrtakPaylasimi({
    required this.sahipId,
    required this.ortakId,
    this.tumu = true,
    this.ana = true,
    this.portfoyIdler = const {},
  });

  /// Satırı olmayan (sınırsız) paylaşım.
  const OrtakPaylasimi.hepsi({required this.sahipId, required this.ortakId})
      : tumu = true,
        ana = true,
        portfoyIdler = const {};

  final String sahipId;
  final String ortakId;

  /// Her şey, sonradan açılan portföyler dahil.
  final bool tumu;

  /// Seçili modda Ana portföy (portfoy_id NULL lotlar) görünür mü.
  final bool ana;

  /// Seçili modda görünen adlandırılmış portföyler.
  final Set<String> portfoyIdler;

  /// Ortak bir şeyleri görmüyor mu ("yalnız paylaştıkları" notu).
  bool get kisitli => !tumu;

  /// [portfoyId] (`null` = Ana) ortağa görünür mü. Sunucudaki
  /// `ortak_portfoyu_gorur` ile AYNI kural.
  bool gorur(String? portfoyId) {
    if (tumu) return true;
    return portfoyId == null ? ana : portfoyIdler.contains(portfoyId);
  }

  /// [bilinen] portföyler arasında ortağa görünenlerin sayısı (Ana dahil).
  int gorunenSayisi(Iterable<String> bilinen) =>
      (gorur(null) ? 1 : 0) + bilinen.where(gorur).length;

  OrtakPaylasimi kopya({bool? tumu, bool? ana, Set<String>? portfoyIdler}) =>
      OrtakPaylasimi(
        sahipId: sahipId,
        ortakId: ortakId,
        tumu: tumu ?? this.tumu,
        ana: ana ?? this.ana,
        portfoyIdler: portfoyIdler ?? this.portfoyIdler,
      );

  Map<String, dynamic> toSupabase() => {
        'sahip_id': sahipId,
        'ortak_id': ortakId,
        'tumu': tumu,
        'ana': ana,
        // Kararlı sıra: aynı seçim aynı satırı yazsın (diff/log okunur).
        'portfoy_idler': portfoyIdler.toList()..sort(),
      };

  factory OrtakPaylasimi.fromSupabase(Map<String, dynamic> m) =>
      OrtakPaylasimi(
        sahipId: m['sahip_id'] as String,
        ortakId: m['ortak_id'] as String,
        tumu: m['tumu'] != false,
        ana: m['ana'] != false,
        portfoyIdler: {
          for (final p in (m['portfoy_idler'] as List?) ?? const []) '$p',
        },
      );
}
