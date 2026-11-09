// Gram emtia sembolü (`GRAM:SI=F`) — istemcideki `emtia_katalogu.dart` eşi.
//
// yasin (18 Eki 2026): ons kote metaller (gümüş, platin, paladyum) gram
// olarak da eklenebilmeli. Gram lot ayrı semboldür ki ons lotuyla aynı
// pozisyonda toplanmasın (altının gram/ons ayrımıyla aynı gerekçe). Kendi
// kotasyonu yoktur: ons tabanı çekilir, fiyat 31,1035'e bölünür; yüzde
// değişim aynıdır. Bölme yalnız Yahoo okuyan yerlerde, tabanı çekerken
// yapılır (live_prices, price_history, dated_history).

export const GRAM_ONEKI = 'GRAM:';
/** Bir troy ons kaç gram — `price_history.ts` ve istemciyle aynı değer. */
export const ONS_GRAM = 31.1035;

/// `GRAM:SI=F` → `SI=F`; gram sembolü değilse null.
export function gramTabani(symbol: string): string | null {
  const s = symbol.trim().toUpperCase();
  if (!s.startsWith(GRAM_ONEKI)) return null;
  const t = s.slice(GRAM_ONEKI.length);
  return t.length > 0 ? t : null;
}
