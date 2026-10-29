// Fiyat alarmı "Her geçişte haber ver" — saf karar (0171, 2026-10-29).
//
// `check-price-alerts` tekrarlı (`tekrar=true`) alarmda her turda bu
// fonksiyonu sorar; tek atış (`tekrar=false`) alarm buraya hiç girmez, o
// dal 0046'daki gibi kalır (`isTriggered` + `alarmiSondur`).
//
// ── Kural ───────────────────────────────────────────────────────────────────
//   · nöbette (`triggered_at` null) ve fiyat hedefe ulaştı (sınır dahil,
//     `isTriggered` ile aynı) → 'cal'. Alarm söndürülmez.
//   · çalmış (`triggered_at` dolu) ve fiyat hedefin ÖBÜR tarafına
//     [TEKRAR_TAMPONU] kadar geçti → 'nobete_don' (`triggered_at` null).
//     'above' alarmda fiyat ≤ hedef×(1−%0,5); 'below'da ≥ hedef×(1+%0,5).
//     Tampon, seviyenin etrafındaki oynamada beş dakikada bir bildirim
//     gelmesini önler: 42,00'de kurulan dolar alarmı 41,79'a inmeden
//     yeniden kurulmaz.
//   · günlük tavan: bir TR gününde [GUNLUK_TAVAN] çalıştan sonra o gün
//     ne çalar ne nöbete döner ('tavan'). Sessiz damga atılmaz: kişinin
//     görmediği bir "çalış" uydurmak olurdu. Ertesi gün fiyat geri dönünce
//     nöbete girer; tavan doluyken kişi elle yeniden kurduysa ertesi gün
//     fiyat hâlâ hedefin ötesindeyse çalar (nadir; o gün haber vermemek
//     tavanın sözü).
//   · fiyat geçersizse (0, NaN, negatif) → 'bekle'; uydurma yok.
//
// Günlük sayaç satırda (`gunluk_tetik_sayisi`, `gunluk_tetik_gunu`); gece
// sıfırlayan iş yok — gün okurken karşılaştırılır ([bugunkuSayi]).

/// Nöbete dönüş tamponu: hedefin %0,5 öbür tarafı.
export const TEKRAR_TAMPONU = 0.005;

/// Bir alarmın bir TR gününde en çok çalış sayısı.
export const GUNLUK_TAVAN = 3;

export type TekrarDurumu = {
  target_price: number;
  direction: string;
  triggered_at?: string | null;
  gunluk_tetik_sayisi?: number | null;
  gunluk_tetik_gunu?: string | null;
};

export type TekrarKarari =
  | { tur: 'cal'; sayi: number; gun: string }
  | { tur: 'nobete_don' }
  | { tur: 'tavan' }
  | { tur: 'bekle' };

/// Bir anın Europe/Istanbul takvim günü, `YYYY-MM-DD` (Postgres `date`).
export function trGunuTekrar(d: Date): string {
  return new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).format(d);
}

/// Satırdaki sayaç bugüne mi ait; değilse bugün 0 kez çaldı.
export function bugunkuSayi(a: TekrarDurumu, bugun: string): number {
  if (a.gunluk_tetik_gunu !== bugun) return 0;
  const n = Number(a.gunluk_tetik_sayisi ?? 0);
  return Number.isFinite(n) && n > 0 ? n : 0;
}

/// Fiyat hedefe ulaştı mı (sınır dahil) — `isTriggered` ile aynı kural.
/// `check-price-alerts`'i içe aktarmamak için burada (o modül `Deno.serve`
/// koşar).
function hedefte(price: number, target: number, direction: string): boolean {
  return direction === 'above' ? price >= target : price <= target;
}

/// Fiyat hedefin öbür tarafına tamponla geçti mi.
export function tampondanGecti(
  price: number,
  target: number,
  direction: string,
): boolean {
  return direction === 'above'
    ? price <= target * (1 - TEKRAR_TAMPONU)
    : price >= target * (1 + TEKRAR_TAMPONU);
}

/// Tekrarlı alarmın bu turdaki kararı.
export function tekrarKarari(
  a: TekrarDurumu,
  price: number,
  simdi: Date = new Date(),
): TekrarKarari {
  const target = Number(a.target_price);
  if (!Number.isFinite(price) || price <= 0) return { tur: 'bekle' };
  if (!Number.isFinite(target) || target <= 0) return { tur: 'bekle' };
  const bugun = trGunuTekrar(simdi);
  const sayi = bugunkuSayi(a, bugun);
  const tavanDolu = sayi >= GUNLUK_TAVAN;

  if (a.triggered_at == null) {
    if (!hedefte(price, target, a.direction)) return { tur: 'bekle' };
    if (tavanDolu) return { tur: 'tavan' };
    return { tur: 'cal', sayi: sayi + 1, gun: bugun };
  }
  if (!tampondanGecti(price, target, a.direction)) return { tur: 'bekle' };
  if (tavanDolu) return { tur: 'tavan' };
  return { tur: 'nobete_don' };
}
