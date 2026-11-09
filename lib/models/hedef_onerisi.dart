/// "Hedefin yok · Hedef belirle" önerisinin görünürlük kuralı — saf.
///
/// ## Neden (Ar-Ge 5 Kas 19:00 #2, müşteri YAP)
/// Hedef koymak istemeyen biriktirici bu satırı her açılışta görüyordu
/// (1 Kas'ta tek satıra inmişti, ama kalıcı bir dürtüydü). Monzo ve Revolut
/// önerileri kapatılabilir; bir kez kapatılan öneri dönmez. İki yol:
///   · ✕ ile kapatılan öneri bir daha gösterilmez ([kapatildi]);
///   · üç ayrı günde gösterilip dokunulmayan öneri 30 gün söner
///     ([gosterildi]); süre dolunca yeniden üç gün şansı olur.
/// Öneri sönünce hedef Profil'den belirlenebilir (`HedefProfilSatiri`):
/// hedef sayfasının başka girişi yoktu, yol kapanmamalı.
///
/// Durum tek metin tercihte (`PrefKeys.hedefOnerisi`) saklanır:
/// `"sonGun:sayi:erteleGun:kapali"`; gün `yyyymmdd`. Bozuk/eski değer
/// varsayılana (görünür) düşer.
class HedefOnerisiDurumu {
  const HedefOnerisiDurumu({
    this.sonGun = 0,
    this.sayi = 0,
    this.erteleGun = 0,
    this.kapali = false,
  });

  /// Gösterimin son sayıldığı gün (aynı gün ikinci kez sayılmaz).
  final int sonGun;

  /// Dokunulmadan geçen gösterim günü.
  final int sayi;

  /// Bu günden ÖNCE gizli (`0`: erteleme yok).
  final int erteleGun;

  /// ✕ ile kapatıldı: bir daha gösterilmez.
  final bool kapali;

  /// Kaç dokunulmamış gösterimden sonra söner.
  static const sonmeEsigi = 3;

  /// Sönme süresi.
  static const sonmeSuresi = Duration(days: 30);

  static int gunKodu(DateTime t) => t.year * 10000 + t.month * 100 + t.day;

  static HedefOnerisiDurumu coz(String? kod) {
    final p = (kod ?? '').split(':');
    if (p.length != 4) return const HedefOnerisiDurumu();
    final s = p.take(3).map(int.tryParse).toList();
    if (s.any((v) => v == null)) return const HedefOnerisiDurumu();
    return HedefOnerisiDurumu(
        sonGun: s[0]!, sayi: s[1]!, erteleGun: s[2]!, kapali: p[3] == '1');
  }

  String get kod => '$sonGun:$sayi:$erteleGun:${kapali ? 1 : 0}';

  /// Kartta öneri çizilsin mi?
  bool gorunur(DateTime now) => !kapali && gunKodu(now) >= erteleGun;

  /// Öneri bugün çizildi. Görünmüyorsa ya da bugün zaten sayıldıysa aynı
  /// durum döner (yazma gerekmez: `identical`).
  HedefOnerisiDurumu gosterildi(DateTime now) {
    final bugun = gunKodu(now);
    if (!gorunur(now) || sonGun == bugun) return this;
    final n = sayi + 1;
    if (n >= sonmeEsigi) {
      return HedefOnerisiDurumu(
          sonGun: bugun, erteleGun: gunKodu(now.add(sonmeSuresi)));
    }
    return HedefOnerisiDurumu(sonGun: bugun, sayi: n);
  }

  /// Öneriye dokunuldu (hedef sayfası açıldı): sayaç sıfırlanır.
  HedefOnerisiDurumu dokunuldu() => HedefOnerisiDurumu(sonGun: sonGun);

  /// ✕: kalıcı kapatma.
  HedefOnerisiDurumu kapatildi() =>
      HedefOnerisiDurumu(sonGun: sonGun, kapali: true);
}
