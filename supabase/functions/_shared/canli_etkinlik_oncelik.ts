// Live Activity push önceliği — saf kural (bkz. migration 0143).
//
// Görünen içerik son YÜKSEK öncelikli push'takiyle aynıysa öncelik 5
// (Apple: cihazın güç durumuna göre teslim, bütçeden düşmez), değiştiyse
// 10 (hemen). İçerik ve push sayısı değişmez; yalnızca başlık.

/// İmzaya GİRMEYEN alanlar: her push'ta zaten değişen zaman damgaları.
/// Bunlar yüzünden imza her dakika değişseydi kural hiçbir şeyi
/// seyreltmezdi; rakam aynıyken saatin geç gelmesi yanlış bilgi değildir
/// (rakam o saatte de aynıydı).
const ZAMAN_ALANLARI = new Set(['updatedAtText', 'dateText', 'sessionEndsAtUnix']);

/// Görünür içeriğin kararlı imzası — anahtar sırasından bağımsız.
export function pushImzasi(contentState: Record<string, unknown>): string {
  const anahtarlar = Object.keys(contentState)
    .filter((k) => !ZAMAN_ALANLARI.has(k))
    .sort();
  return JSON.stringify(anahtarlar.map((k) => [k, contentState[k]]));
}

/// `'10'` ya da `'5'`. Önceki imza yoksa (sütun yok / ilk push) 10:
/// bugünkü davranış.
export function pushOnceligi(imza: string, onceki: unknown): '10' | '5' {
  return typeof onceki === 'string' && onceki.length > 0 && onceki === imza
    ? '5'
    : '10';
}
