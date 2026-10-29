/// Hafta sonu kapalı piyasalar (Ar-Ge 21 Eki 08:45 #3; yasin "şerh
/// düştüklerim dışında yap", 2026-10-21).
///
/// ## Neden
/// `analyze-signals` hafta sonu da her saat koşuyor ve BIST hissesi, fon,
/// BES ve eurobond için mum çekip aynı kapanışı yeniden hesaplıyordu: yeni
/// bar yok, sinyal değişmez, kaynak (Yahoo/TEFAS) hız sınırı ve işlem süresi
/// boşa gider. Cumartesi ve pazar bu türler atlanır.
///
/// Koşmaya DEVAM edenler: kripto (7/24), altın (yurt içi altın hafta sonu da
/// yazılıyor, `hafta_sonu_yurt_ici_seri`), döviz ve emtia (müşteri raporu
/// 21 Eki 09:15: hareket az ama sıfır değil). Resmî tatiller de atlanır
/// (`borsaKapaliGunMu`, Ar-Ge 29 Eki #1): liste `bist_tatil.ts`'te, yalnız
/// ilan edilmiş günler; listede olmayan gün açık sayılır.
///
/// Gün Türkiye saatiyle (UTC+3, yaz saati yok) hesaplanır: gece yarısına
/// yakın bir UTC anı TR'de ertesi gün olabilir.
import { BIST_TATIL } from './bist_tatil.ts';

const HAFTA_SONU_KAPALI = new Set(['hisse', 'fon', 'bes', 'eurobond']);

export function haftaSonuKapaliMi(tur: string, simdi: Date): boolean {
  if (!HAFTA_SONU_KAPALI.has(tur)) return false;
  const tr = new Date(simdi.getTime() + 3 * 3600 * 1000);
  const g = tr.getUTCDay();
  return g === 0 || g === 6;
}

/// TR takvim günü `AA-GG` ve yıl. Yaz saati yok, UTC+3 sabit.
function trGunParcalari(simdi: Date): { yil: string; ayGun: string; g: number; dk: number } {
  const tr = new Date(simdi.getTime() + 3 * 3600 * 1000);
  const iso = tr.toISOString();
  return {
    yil: iso.slice(0, 4),
    ayGun: iso.slice(5, 10),
    g: tr.getUTCDay(),
    dk: tr.getUTCHours() * 60 + tr.getUTCMinutes(),
  };
}

function listede(liste: readonly string[] | undefined, ayGun: string): boolean {
  return (liste ?? []).includes(ayGun);
}

/// BIST tam gün tatil mi? Hafta sonu burada sayılmaz.
export function bistTatilMi(simdi: Date): boolean {
  const { yil, ayGun } = trGunParcalari(simdi);
  const dini = BIST_TATIL.diniTamGun as Record<string, readonly string[]>;
  return listede(BIST_TATIL.sabitTamGun, ayGun) || listede(dini[yil], ayGun);
}

/// Öğleden sonra kapalı yarım gün mü (arife, 28 Ekim)? 12:30'da kapanır.
export function bistYarimGunMu(simdi: Date): boolean {
  const { yil, ayGun } = trGunParcalari(simdi);
  const dini = BIST_TATIL.diniYarimGun as Record<string, readonly string[]>;
  return listede(BIST_TATIL.sabitYarimGun, ayGun) || listede(dini[yil], ayGun);
}

export const YARIM_GUN_KAPANIS_DK = 12 * 60 + 30;

/// Borsa türü bugün hiç işlem görmüyor mu: hafta sonu ya da resmî tatil.
/// Kripto, altın, döviz ve emtia hiçbir zaman kapalı sayılmaz.
export function borsaKapaliGunMu(tur: string, simdi: Date): boolean {
  if (!HAFTA_SONU_KAPALI.has(tur)) return false;
  return haftaSonuKapaliMi(tur, simdi) || bistTatilMi(simdi);
}

/// BIST seansı şu an açık mı? (TR 10:00–18:10; yarım günde 12:30.)
/// İstemcideki `DailySummary.isMarketOpen` ile AYNI kural: uygulama
/// önplandayken istemci, kapalıyken sunucu karar verir.
export function bistSeansAcikMi(simdi: Date): boolean {
  const { g, dk } = trGunParcalari(simdi);
  if (g === 0 || g === 6) return false;
  if (bistTatilMi(simdi)) return false;
  const kapanis = bistYarimGunMu(simdi) ? YARIM_GUN_KAPANIS_DK : 18 * 60 + 10;
  return dk >= 10 * 60 && dk < kapanis;
}
