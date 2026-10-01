/// TÜİK TÜFE açıklama takvimi — TEK yer.
///
/// TÜİK bir ayın enflasyonunu ertesi ayın 3'ünde saat 10:00'da açıklar
/// (Eylül TÜFE'si → 3 Ekim 10:00). Kural iki yüzeyde okunuyor: Bugün
/// kartının "TÜİK enflasyonu · 3 Ekim" damgası (`BugunService`) ve Özet'in
/// reel getiri kartındaki "Ağu sonundan bugüne" köprü satırı
/// (`TufeKoprusu`). 2026-10-01'e kadar kural `BugunService` içinde satır
/// içiydi; ikinci okuyucu gelince buraya taşındı ki iki yüzey farklı gün
/// söylemesin.
///
/// Resmî tatil kaydırması bilinçli olarak YOK: TÜİK takvimi 3'ü hafta sonuna
/// denk gelse de çoğunlukla 3'ünde yayımlar ve kaydırdığı yıllarda bunu
/// önceden ilan eder. Uydurma bir kaydırma kuralı yazmak, kuralı hiç
/// yazmamaktan kötü olurdu.
class TuikTakvimi {
  TuikTakvimi._();

  /// Açıklamanın ayın kaçında yapıldığı.
  static const aciklamaGunu = 3;

  /// Açıklama saati (yerel).
  static const aciklamaSaati = 10;

  /// [ay]'ın TÜFE verisinin açıklandığı an: ertesi ayın 3'ü, 10:00.
  ///
  /// [ay]'ın yalnızca yıl/ay alanları okunur; gün önemsizdir.
  static DateTime aciklamaTarihi(DateTime ay) =>
      DateTime(ay.year, ay.month + 1, aciklamaGunu, aciklamaSaati);

  /// [now]'dan sonraki (ya da [now]'a eşit) ilk açıklama anı.
  ///
  /// Bu ayın 3'ü 10:00 geçmediyse o, geçtiyse gelecek ayın 3'ü.
  static DateTime sonrakiAciklama(DateTime now) {
    final buAy = DateTime(now.year, now.month, aciklamaGunu, aciklamaSaati);
    return now.isAfter(buAy)
        ? DateTime(now.year, now.month + 1, aciklamaGunu, aciklamaSaati)
        : buAy;
  }
}
