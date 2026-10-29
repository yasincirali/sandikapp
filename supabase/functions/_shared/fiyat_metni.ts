// Bildirim metninde fiyat — sayı biçimi ve para simgesi tek yerde.
//
// Neden ayrı modül (2026-10-29, bildirim denetimi): fiyat alarmı
// (`formatTRY`) her fiyatı 2 haneye yuvarlıyordu — SHIB ₺0,0004 bildirimde
// "0,00" okunuyordu; kartı ve çan satırı ABD hissesi alarmında bile "₺"
// basıyordu (sayı dolar). Yüzde alarmının `tlMetni`'si küçük fiyatı doğru
// yazıyordu ama simge bilgisi yoktu. Takip listesi push'u fiyat hiç
// göstermiyordu. Üç yüzey aynı kurala bağlansın diye kural burada.
//
// Simge kuralı istemcideki `kotasyonSembolu` (lib/models/asset_type.dart)
// eşidir: CANLI kotasyonun kendi birimi. Push'taki sayı canlı kotasyondur
// (`fetchLiveQuotes`), uygulamadaki takip satırı gibi TL'ye çevrilmiş seri
// ucu değil — bu yüzden ABD hissesi "$" ile yazılır; "₺" ile dolar sayısı
// yazmak uydurma sayı olurdu (fiyat kaynağı sözleşmesi madde 3).
//
// Simge BİLİNMİYORSA (yabancı borsa, para birimi kaydı olmayan eurobond)
// `null` döner ve sayı simgesiz yazılır: yanlış simge, simgesiz sayıdan
// kötüdür. Endeks puandır, simge almaz (istemci `bistEndeksiMi` /
// `kureselEndeksMi`).

import { isFxSymbol, isGoldSymbol, isTefasSymbol } from './live_prices.ts';
import { GRAM_ONEKI } from './emtia_gram.ts';
import { kriptoMu } from './kripto.ts';

const SIMGELER: Record<string, string> = {
  USD: '$', EUR: '€', GBP: '£', JPY: '¥', CHF: '₣', CAD: 'C$', AUD: 'A$',
  CNY: '¥', RUB: '₽', TRY: '₺', INR: '₹', KRW: '₩', BRL: 'R$',
};

/// Endeks mi (puan, fiyat değil) — istemcideki iki kuralın birleşimi.
export function endeksMi(sembol: string): boolean {
  const t = sembol.trim().toUpperCase();
  if (t.startsWith('^')) return true;
  if (!t.startsWith('XU')) return false;
  return t.endsWith('.IS') || (t.length === 5 && !/[.:=\-]/.test(t));
}

/// Kotasyonun para simgesi; bilinmiyorsa `null`.
///
/// [currency]: varlığın kayıtlı kotasyon para birimi (`watchlist.currency`).
/// Yalnız sembolün kendisinin karar veremediği yerde (düz Yahoo sembolü,
/// eurobond) kullanılır: kayıt varsayılanı 'TRY' olduğundan sembolün açık
/// söylediğini (`.IS` = TL, `=F` = dolar) kayıt ezmesin.
export function kotasyonSimgesi(sembol: string, currency?: string | null): string | null {
  const t = sembol.trim().toUpperCase();
  if (t.length === 0 || endeksMi(t)) return null;
  // Paritede fiyat KARŞI para birimindedir: USDTRY=X → ₺, EURUSD=X → $.
  if (t.endsWith('=X')) {
    const cift = t.slice(0, -2);
    return cift.length === 6 ? SIMGELER[cift.slice(3)] ?? null : null;
  }
  if (
    isGoldSymbol(t) || t.startsWith('ALTIN_') || isFxSymbol(t) ||
    isTefasSymbol(t) || kriptoMu(t) || t.endsWith('.IS')
  ) return '₺';
  // Yahoo vadelisi ve gram türevi dolar kotedir (COMEX/NYMEX).
  if (t.endsWith('=F') || t.startsWith(GRAM_ONEKI)) return '$';
  const kayit = (currency ?? '').trim().toUpperCase();
  if (kayit) return SIMGELER[kayit] ?? null;
  // Kayıt yok (fiyat alarmı yalnız sembol taşır): son eksiz, harf/tire
  // Yahoo sembolü ABD borsasıdır (AAPL, BRK-B). Başka son ek (SAP.DE) ve
  // eurobond belirsiz → simgesiz.
  return /^[A-Z][A-Z\-]{0,5}$/.test(t) ? '$' : null;
}

/// Fiyat sayısı, Türkçe biçim (Intl'in tr-TR verisine güvenilmez).
///
/// 1 ve üstü: binlik nokta, 2 ondalık. 1 altı (SHIB, düşük fiyatlı fon):
/// en az 2, en çok 6 ondalık, sondaki sıfırlar atılır — 2 haneye
/// yuvarlamak ₺0,0004'ü "0,00" yapıyordu.
export function fiyatSayisi(v: number): string {
  const isaret = v < 0 ? '-' : '';
  const a = Math.abs(v);
  if (a < 1) {
    let k = a.toFixed(6).replace(/0+$/, '');
    const [, kesir = ''] = k.split('.');
    if (kesir.length < 2) k = a.toFixed(2);
    return `${isaret}${k.replace('.', ',')}`;
  }
  const [tam, kesir] = a.toFixed(2).split('.');
  const binlik = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${isaret}${binlik},${kesir}`;
}

/// Simgeli fiyat: "₺312,40", "$255,10"; simge yoksa yalnız sayı.
export function fiyatMetni(v: number, simge: string | null): string {
  return `${simge ?? ''}${fiyatSayisi(v)}`;
}
