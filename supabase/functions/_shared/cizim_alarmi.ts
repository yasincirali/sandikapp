// Çizgi alarmı — yatay grafikte çizilen trend çizgisi ya da ışına fiyat
// değerse haber ver (0170, yasin 2026-10-29).
//
// Sunucu çizimin kendisini bilmez; istemci çizimi "şu andan sonra grafikte
// görünen doğru"ya çevirip iki nokta olarak yazar (`cizimAlarmDogrusu`,
// `lib/services/cizim_alarmi.dart`). Burada yalnız o doğrunun bugünkü
// değeri hesaplanır. Taraf değişimi/damga/push `seviye_alarmi.ts`'te.
//
// ── Neden duvar saatiyle doğrusal ──────────────────────────────────────────
// Grafik geçmişi mum indeksiyle çizer (hafta sonu yer kaplamaz) ama son
// mumdan sonrasını mum süresi adımıyla, yani duvar saatine göre uzatır
// (`GrafikOlcegi.zamanIndeksi`). Alarm hep "şimdi ve sonrası"nı sorduğu için
// istemci doğruyu o bölgedeki eğimiyle yazar; sunucu da duvar saatiyle
// doğrusal okur. Seans dışı saatlerde (gece, hafta sonu) yeni mum gelmez;
// grafik bu boşlukları sonradan sıkıştırır, alarm sıkıştırmaz — bu yüzden
// gün içi aralıkta çizilen dik bir ışın günler sonra grafikteki çizgiden
// ayrışabilir. Bildirim gövdesi seviyenin sayısını yazar (kullanıcı neyin
// karşılaştırıldığını görür).

export type CizimDogrusu = {
  t1: number;
  p1: number;
  t2: number;
  p2: number;
  uzanir: boolean;
};

/// Cihaz ile sunucu saati arasındaki kabul edilen fark.
export const SAAT_PAYI_MS = 10 * 60_000;

/// Doğrunun [simdiMs] anındaki değeri; değerlendirilemezse null.
///
/// - Bozuk satır (t2 ≤ t1, sayı değil) → null.
/// - Parça (uzanir=false) t2'yi geçtiyse → null: çizgi bitti, "değdi"
///   denecek bir yer yok.
/// - t1'den önce → null; yalnız [SAAT_PAYI_MS] kadar geri uzatılır
///   (istemci t1'i "şimdi" yazar; cihaz saati birkaç dakika ileri olabilir).
/// - Değer sıfır ya da negatifse → null (fiyat orada olamaz; uydurma yok).
export function cizgiDegeri(d: CizimDogrusu, simdiMs: number): number | null {
  const { t1, p1, t2, p2 } = d;
  if (![t1, p1, t2, p2, simdiMs].every(Number.isFinite)) return null;
  if (t2 <= t1) return null;
  if (simdiMs < t1 - SAAT_PAYI_MS) return null;
  if (!d.uzanir && simdiMs > t2) return null;
  const v = p1 + (p2 - p1) * (simdiMs - t1) / (t2 - t1);
  return Number.isFinite(v) && v > 0 ? v : null;
}
