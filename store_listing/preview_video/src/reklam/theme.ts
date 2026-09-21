// Reklam kompozisyonlarının ortak sabitleri.
//
// Renkler ana theme.ts'ten (sandık paleti) — skill'in mor/camgöbeği paleti
// ALINMADI, ui-ux-pro-max'ın önerdiği "rose + blue" paleti de ALINMADI:
// reklamda uygulamanın kimliği kazanır (CLAUDE.md çakışma kuralı).
// Tür renkleri uygulamanın donut grafiğinden okundu (fon mavi, döviz nane).
import { theme as base } from "../theme";

export const theme = {
  ...base,
  colors: {
    ...base.colors,
    // Varlık türü renkleri — donut/dağılım çubuklarıyla aynı okuma.
    fon: "#4FA3E0",
    doviz: "#6FD3A5",
    // Rozet zemini: gain'in %14 opak hâli.
    gainTint: "rgba(61, 183, 127, 0.14)",
    lossTint: "rgba(255, 107, 82, 0.14)",
    amberTint: "rgba(245, 166, 35, 0.14)",
    // Telefon çerçevesi ve iç yüzeyler
    frame: "#0B241B",
    divider: "rgba(255,255,255,0.08)",
  },
} as const;

/**
 * Müzik: "Happy Beats / Business Moves vol-11", Sascha Ende (ende.app),
 * CC BY 4.0, ticari kullanım serbest (SES_LISANS.md). Vuruş 114 BPM —
 * brag hattındaki beat-grid'den (4,75 · 8,96 · 13,70 · 17,39 · 21,07 sn)
 * türetildi: aralıklar 0,526 sn'nin katları.
 */
export const MUSIC = {
  bpm: 114,
  file: "music/business-moves-vol11.mp3",
  volume: 0.3,
} as const;

/** Vuruş başına kare. 30 fps'te ≈ 15,79. */
export const fpb = (fps: number) => (fps * 60) / MUSIC.bpm;
/** n. vuruşun karesi — kesimler bunun katlarına oturur. */
export const beat = (fps: number, n: number) => Math.round(n * fpb(fps));

/**
 * Demo portföy — store_listing/DEMO_PORTFOY.md ile birebir.
 * Uydurma sayı yok: 16.09.2026 canlı fiyatlarından okunan kompozisyon.
 */
export const DEMO = {
  toplam: "₺766.876",
  kz: "+₺196.091",
  pct: 34.35,
  tufe: 31.51,
  fark: 2.85, // 34,35 − 31,51 — rozet yeşil
  aralik: "Eyl 2025 – Eyl 2026",
  dagilim: [
    { ad: "Fon", pct: 35.0, renk: "fon" },
    { ad: "Altın", pct: 28.2, renk: "gold" },
    { ad: "Hisse", pct: 22.8, renk: "primary" },
    { ad: "Döviz", pct: 14.0, renk: "doviz" },
  ],
  // Ortak portföy: Ben + Ayşe = Birlikte (ekran görüntüsündeki toplamla aynı)
  ortak: { ben: "₺766.876", ayse: "₺805.153", birlikte: "₺1.572.029" },
  // Gerçek kâr örneği: KCHOL 620 × 148,00 → 206,10.
  // Nominal +36.022; komisyon −184 (maliyete), temettü +2.480 (kazanca).
  kchol: {
    alis: "620 × ₺148,00",
    fiyatFarki: "+₺36.022",
    komisyon: "−₺184",
    temettu: "+₺2.480",
    gercek: "+₺38.318",
  },
} as const;

/** Türkçe ondalık: 34.35 → "34,35" */
export const tr = (n: number, d = 2) => n.toFixed(d).replace(".", ",");

/** Tam sayı binlik: 766876 → "766.876" (toLocaleString'e güvenmeden). */
export const trInt = (n: number) =>
  Math.round(n)
    .toString()
    .replace(/\B(?=(\d{3})+(?!\d))/g, ".");

/**
 * Tanıtım videosu (2026-09-21) — güncel ana ekranın çizimi için ek sayılar.
 *
 * DEMO_PORTFOY.md'de olmayan üç şey burada ve TEMSİLİDİR (gün içi hareket,
 * piyasa bandı, hedef). Portföy toplamı/getiri/dağılım DEMO'dan; hedef
 * ₺1.000.000 → oran DEMO.toplam'dan hesaplanır (766.876 / 1.000.000).
 * Bugün kartındaki "artıdaki varlık" DEMO'dan: 6 varlığın 5'i artıda (SAHOL eksi).
 */
export const TANITIM = {
  gun: { tutar: "+₺4.317", pct: 0.57 },
  haftalik: 1.3,
  hedefTRY: 1_000_000,
  hedefOran: 77, // 766.876 / 1.000.000 → %76,7
  hedefKalan: "₺233.124",
  yesil: "5 / 6",
  piyasa: [
    { ad: "Dolar", deger: "48,79", pct: 0.08 },
    { ad: "Euro", deger: "56,11", pct: -0.08 },
    { ad: "Altın", deger: "6.204", pct: 0.41 },
    { ad: "BIST 100", deger: "11.482", pct: 1.12 },
  ],
  // Ortak görünümü: Ayşe'nin günü — DEMO.ortak.ayse toplamı.
  ayse: { tutar: "+₺1.906", pct: 0.24 },
  bildirimler: [
    { baslik: "KCHOL hedef fiyata geldi", govde: "₺206,10 · alarmın tetiklendi", saat: "14:32" },
    { baslik: "Günlük brifing", govde: "Bugün +₺4.317 · %0,57 artıda", saat: "18:30" },
    { baslik: "Enflasyon açıklandı", govde: "TÜFE %31,51 · sen 2,85 puan öndesin", saat: "10:00" },
  ],
} as const;

/** 9:16 güvenli alan — platform arayüzü üstü/altı kapatır. */
export const SAFE_9x16 = { top: 230, bottom: 260, side: 72 } as const;
