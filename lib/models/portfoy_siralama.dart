/// Portföy listesi sıralama seçimi (Portföy sekmesi, sağ üstteki düğme).
///
/// Neden ayrı dosya ve `kod` (Ar-Ge 2026-10-25 12:45 #3, kabul 13:15 #2):
/// seçim artık kalıcı (`portfoySiralamaProvider`, kişiye özel). Diske enum
/// SIRASI (`index`) değil bu kararlı kod yazılır — sıra değişir ya da araya
/// seçenek girerse kullanıcının tercihi başka bir sıralamaya kaymaz.
/// Tanınmayan / boş kod bugünkü varsayılana ([varsayilan], "Değere göre ·
/// yüksekten düşüğe") düşer; kimse bir şey kaybetmez.
enum PortfoySiralama {
  valueDesc('deger_azalan'),
  valueAsc('deger_artan'),
  gainDesc('kar_azalan'),
  gainAsc('kar_artan'),
  gainPctDesc('kar_yuzde_azalan'),
  gainPctAsc('kar_yuzde_artan');

  const PortfoySiralama(this.kod);

  /// Diske yazılan kararlı ad. Değiştirilmez; yeni seçenek yeni kod alır.
  final String kod;

  static const varsayilan = PortfoySiralama.valueDesc;

  static PortfoySiralama kodla(String? kod) {
    for (final s in values) {
      if (s.kod == kod) return s;
    }
    return varsayilan;
  }
}
