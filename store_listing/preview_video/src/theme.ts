// theme.ts — tek gerçek kaynak. Bileşenlerde ham renk/easing YAZILMAZ.
//
// Renkler lib/theme/sandik.dart `SandikPalette.dark`'tan birebir alındı.
// Remotion skill'i kendi paletini önerir (mor/camgöbeği) — ALINMADI:
// tanıtım videosunda uygulamanın kimliği kazanır, skill'in değil.
// (CLAUDE.md çakışma kuralı + SKILLS_README uyarısı.)
import { Easing } from "remotion";

export const theme = {
  colors: {
    // sandık koyu palet — Seviye 0/1/2
    bg: "#0A1E15",
    surface1: "#112E28",
    surface2: "#1A3D2E",

    // HERO renk: amber. Karede EN FAZLA bir öğe bu renkte parlar.
    primary: "#F5A623", // amberFill — CTA, aktif durum, logo ikonu
    gold: "#F5C842", // display sayılar, wordmark

    // Kâr/zarar — denetimde AA'ya çekilmiş tonlar, değiştirme
    gain: "#3DB77F",
    loss: "#FF6B52",

    text: "#FFFFFF",
    text90: "rgba(255,255,255,0.88)",
    text58: "rgba(255,255,255,0.55)",

    onAmber: "#112E28", // amber zemin üstüne koyu marka yeşili (7.66:1)
    glow: "rgba(245, 166, 35, 0.40)",
  },

  fonts: {
    // Uygulama DM Sans kullanıyor; sistem yığını yedek.
    display: "'DM Sans', -apple-system, 'Segoe UI', Roboto, sans-serif",
    body: "'DM Sans', -apple-system, 'Segoe UI', Roboto, sans-serif",
  },

  // Linear YASAK.
  ease: {
    out: Easing.bezier(0.16, 1, 0.3, 1), // easeOutExpo — girişler
    inOut: Easing.bezier(0.83, 0, 0.17, 1), // hareketler, Ken Burns
    in: Easing.bezier(0.7, 0, 0.84, 0), // yalnızca çıkışlar
  },

  spring: {
    snappy: { damping: 14, stiffness: 160, mass: 0.6 },
    smooth: { damping: 20, stiffness: 90, mass: 1 },
    bouncy: { damping: 11, stiffness: 170, mass: 0.7 },
  },
} as const;

// App Store önizleme zorunlu formatı (App Preview Specifications).
// Tüm güncel iPhone boyutları TEK çözünürlük kabul eder: 886×1920.
export const SPEC = {
  width: 886,
  height: 1920,
  fps: 30, // maks 30, progressive
  // Süre 15–30 sn aralığında OLMAK ZORUNDA. 24 sn güvenli orta nokta.
  durationInFrames: 24 * 30,
} as const;

// 9:16 güvenli alan: kritik metin dikeyde ortadaki ~%75'te kalmalı
// (mağaza arayüzü üstü/altı kapatır).
export const SAFE = {
  top: Math.round(SPEC.height * 0.12),
  bottom: Math.round(SPEC.height * 0.13),
  side: 64,
} as const;
