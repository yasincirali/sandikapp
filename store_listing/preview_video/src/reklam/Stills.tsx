// Statik reklam görselleri (<Still>). Spring yok — kare 0'da her şey yerinde.
//
// Beş görsel, üç mesaj:
//   enflasyon → "eridi mi?" + rozet + telefon      (kare, hikâye, banner)
//   altin     → hangi varlık kazandırdı (getiri çubukları, biri kırmızı)
//   ortak     → Ben / Ayşe / Birlikte
import React from "react";
import { AbsoluteFill } from "remotion";
import { BgMesh, Grade, Grain, Vignette } from "../components/Layers";
import { DEMO, theme, tr } from "./theme";
import { PhoneHome, Rozet, StoreLine, Tri, Wordmark } from "./ui";

const font = theme.fonts.display;

const Shell: React.FC<{ children: React.ReactNode }> = ({ children }) => (
  <AbsoluteFill style={{ background: theme.colors.bg, fontFamily: font }}>
    <BgMesh />
    {children}
    <Grade />
    <Grain />
    <Vignette />
  </AbsoluteFill>
);

/** Statik başlık: bir kelime hero, bir kelime "erimiş" (loss + hafif bulanık). */
const H: React.FC<{
  text: string;
  size: number;
  hero?: string;
  heroColor?: string;
  melt?: string;
  align?: "left" | "center";
  color?: string;
  weight?: number;
  style?: React.CSSProperties;
}> = ({ text, size, hero, heroColor = theme.colors.primary, melt, align = "left", color = theme.colors.text, weight = 800, style }) => (
  <div
    style={{
      display: "flex",
      flexWrap: "wrap",
      justifyContent: align === "center" ? "center" : "flex-start",
      columnGap: size * 0.26,
      rowGap: size * 0.05,
      fontSize: size,
      fontWeight: weight,
      letterSpacing: "-0.035em",
      lineHeight: 1.06,
      textAlign: align,
      color,
      ...style,
    }}
  >
    {text.split(" ").map((w, i) => {
      const bare = w.replace(/[.,;:!?]/g, "");
      const isHero = hero === bare;
      const isMelt = melt === bare;
      return (
        <span
          key={i}
          style={{
            display: "inline-block",
            color: isHero ? heroColor : isMelt ? theme.colors.loss : undefined,
            textShadow: isHero ? `0 0 ${size * 0.5}px ${heroColor}66` : "none",
            transform: isMelt ? "scaleY(1.12) translateY(3%)" : "none",
            transformOrigin: "50% 0%",
            filter: isMelt ? "blur(0.6px)" : "none",
          }}
        >
          {w}
        </span>
      );
    })}
  </div>
);

const SubT: React.FC<{ text: string; size: number; style?: React.CSSProperties; align?: "left" | "center" }> = ({
  text,
  size,
  style,
  align = "left",
}) => (
  <div
    style={{
      fontSize: size,
      fontWeight: 500,
      color: theme.colors.text58,
      lineHeight: 1.25,
      letterSpacing: "-0.01em",
      textAlign: align,
      ...style,
    }}
  >
    {text}
  </div>
);

/* ------------------------------------------------------------------ */
/* 1080×1080 — üç varyant                                              */
/* ------------------------------------------------------------------ */
export const StillSquare: React.FC<{ variant: "enflasyon" | "altin" | "ortak" }> = ({ variant }) => {
  if (variant === "enflasyon") return <SquareEnflasyon />;
  if (variant === "altin") return <SquareAltin />;
  return <SquareOrtak />;
};

const SquareEnflasyon: React.FC = () => (
  <Shell>
    <AbsoluteFill style={{ padding: 72 }}>
      <Wordmark size={56} />
      <H
        text="Paran arttı mı, yoksa sadece eridi mi?"
        size={92}
        melt="eridi"
        // 560'ta "eridi" telefonun kenarına değiyordu; 500 kelimeyi alt satıra alır.
        style={{ marginTop: 64, width: 500 }}
      />
      <SubT
        text="Portföyünü TÜFE ile yan yana koyar; gerçek farkı söyler."
        size={34}
        style={{ marginTop: 32, width: 520 }}
      />
      <div style={{ position: "absolute", left: 72, bottom: 72 }}>
        <StoreLine size={0.72} />
      </div>
    </AbsoluteFill>
    {/* Telefon sağdan, altı taşar */}
    {/* 640/470/−4° sağ kenardan taşıyordu (yüzde etiketleri kesik). Dönüş
        sol üst köşeden olduğundan alt kısım sağa kayar; pay bırakıldı. */}
    <div style={{ position: "absolute", left: 585, top: 210, transform: "rotate(-3deg)", transformOrigin: "0 0" }}>
      <PhoneHome w={440} />
    </div>
  </Shell>
);

/** Getiri çubukları — DEMO_PORTFOY'daki altı varlık, biri zararda. */
const GETIRI = [
  { ad: "DLY", tur: "Fon", pct: 45.0, renk: theme.colors.fon },
  { ad: "KCHOL", tur: "Hisse", pct: 39.3, renk: theme.colors.primary },
  { ad: "Çeyrek Altın", tur: "Altın", pct: 37.9, renk: theme.colors.gold },
  { ad: "ABD Doları", tur: "Döviz", pct: 26.4, renk: theme.colors.doviz },
  { ad: "SAHOL", tur: "Hisse", pct: -8.0, renk: theme.colors.primary },
] as const;

const GetiriListesi: React.FC<{ w: number; size?: number }> = ({ w, size = 1 }) => (
  <div
    style={{
      width: w,
      padding: 34 * size,
      borderRadius: 30 * size,
      background: theme.colors.surface1,
      border: `1px solid ${theme.colors.divider}`,
      boxShadow: "0 50px 100px -30px rgba(0,0,0,0.7)",
      display: "flex",
      flexDirection: "column",
      gap: 22 * size,
    }}
  >
    <div
      style={{
        fontSize: 20 * size,
        fontWeight: 700,
        letterSpacing: "0.12em",
        color: theme.colors.text58,
        textTransform: "uppercase",
      }}
    >
      Getiri · son 12 ay
    </div>
    {GETIRI.map((g) => {
      const neg = g.pct < 0;
      const c = neg ? theme.colors.loss : theme.colors.gain;
      return (
        <div key={g.ad} style={{ display: "flex", alignItems: "center", gap: 16 * size }}>
          <div style={{ width: 12 * size, height: 12 * size, borderRadius: 6 * size, background: g.renk }} />
          <div style={{ width: 210 * size }}>
            <div style={{ fontSize: 30 * size, fontWeight: 700, color: theme.colors.text }}>{g.ad}</div>
            <div style={{ fontSize: 20 * size, fontWeight: 500, color: theme.colors.text58 }}>{g.tur}</div>
          </div>
          <div style={{ flex: 1, height: 12 * size, borderRadius: 6 * size, background: theme.colors.surface2, overflow: "hidden" }}>
            <div style={{ width: `${(Math.abs(g.pct) / 50) * 100}%`, height: "100%", background: c, borderRadius: 6 * size }} />
          </div>
          <div
            style={{
              width: 130 * size,
              display: "flex",
              justifyContent: "flex-end",
              alignItems: "center",
              gap: 8 * size,
              fontSize: 30 * size,
              fontWeight: 800,
              color: c,
              fontVariantNumeric: "tabular-nums",
            }}
          >
            <Tri size={11 * size} color={c} down={neg} />%{tr(Math.abs(g.pct), 1)}
          </div>
        </div>
      );
    })}
  </div>
);

const SquareAltin: React.FC = () => (
  <Shell>
    <AbsoluteFill style={{ padding: 72 }}>
      <Wordmark size={56} />
      <H
        text="Altın mı, dolar mı, hisse mi kazandırdı?"
        size={78}
        hero="kazandırdı"
        heroColor={theme.colors.gold}
        style={{ marginTop: 48, width: 940 }}
      />
      <div style={{ marginTop: 44 }}>
        <GetiriListesi w={936} size={1} />
      </div>
      <div style={{ position: "absolute", left: 72, bottom: 72, display: "flex", alignItems: "center", gap: 28 }}>
        <StoreLine size={0.72} />
        <SubT text="Hepsi tek ekranda, gerçek kârıyla." size={30} />
      </div>
    </AbsoluteFill>
  </Shell>
);

const KisiKart: React.FC<{ ad: string; tutar: string; hero?: boolean; w: number }> = ({ ad, tutar, hero, w }) => (
  <div
    style={{
      width: w,
      padding: "30px 34px",
      borderRadius: 30,
      background: hero ? theme.colors.amberTint : theme.colors.surface1,
      border: `1.5px solid ${hero ? `${theme.colors.primary}66` : theme.colors.divider}`,
      boxShadow: hero ? `0 0 70px ${theme.colors.glow}` : "0 40px 80px -30px rgba(0,0,0,0.6)",
    }}
  >
    <div style={{ display: "flex", alignItems: "center", gap: 14 }}>
      <div
        style={{
          width: 44,
          height: 44,
          borderRadius: 22,
          background: hero ? theme.colors.primary : theme.colors.surface2,
          color: hero ? theme.colors.onAmber : theme.colors.gold,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
          fontSize: 22,
          fontWeight: 800,
        }}
      >
        {ad[0]}
      </div>
      <span style={{ fontSize: 30, fontWeight: 600, color: theme.colors.text90 }}>{ad}</span>
    </div>
    <div
      style={{
        marginTop: 18,
        fontSize: hero ? 60 : 50,
        fontWeight: 800,
        letterSpacing: "-0.03em",
        color: theme.colors.gold,
        fontVariantNumeric: "tabular-nums",
      }}
    >
      {tutar}
    </div>
  </div>
);

const SquareOrtak: React.FC = () => (
  <Shell>
    <AbsoluteFill style={{ padding: 72 }}>
      <Wordmark size={56} />
      <H text="Eşinle aynı sandık." size={96} hero="aynı" style={{ marginTop: 56 }} />
      <SubT
        text="Aynı portföyü birlikte takip edin. Herkesin katkısı ve getirisi ayrı ayrı hesaplanır."
        size={34}
        style={{ marginTop: 26, width: 900 }}
      />
      <div style={{ display: "flex", gap: 22, marginTop: 54 }}>
        <KisiKart ad="Ben" tutar={DEMO.ortak.ben} w={300} />
        <KisiKart ad="Ayşe" tutar={DEMO.ortak.ayse} w={300} />
        <KisiKart ad="Birlikte" tutar={DEMO.ortak.birlikte} w={300} hero />
      </div>
      <div style={{ position: "absolute", left: 72, bottom: 72 }}>
        <StoreLine size={0.72} glow={false} />
      </div>
    </AbsoluteFill>
  </Shell>
);

/* ------------------------------------------------------------------ */
/* 1080×1920 — hikâye                                                  */
/* ------------------------------------------------------------------ */
export const StillStory: React.FC = () => (
  <Shell>
    <AbsoluteFill style={{ alignItems: "center", paddingTop: 250, paddingLeft: 72, paddingRight: 72 }}>
      <Wordmark size={64} />
      <H
        text="Paran arttı mı, yoksa sadece eridi mi?"
        size={104}
        melt="eridi"
        align="center"
        style={{ marginTop: 60 }}
      />
      <div style={{ marginTop: 50 }}>
        <Rozet size={1.15} />
      </div>
      {/* CTA telefonun ÜSTÜNDE: altta (bottom 250) telefonun ortasına biniyordu. */}
      <div style={{ marginTop: 44 }}>
        <StoreLine size={1} />
      </div>
    </AbsoluteFill>
    <div style={{ position: "absolute", left: "50%", top: 1080, transform: "translateX(-50%)" }}>
      <PhoneHome w={600} />
    </div>
  </Shell>
);

/* ------------------------------------------------------------------ */
/* 1600×900 — X / LinkedIn banner                                      */
/* ------------------------------------------------------------------ */
export const StillBanner: React.FC = () => (
  <Shell>
    <AbsoluteFill style={{ padding: 90, justifyContent: "center" }}>
      <Wordmark size={64} />
      <H
        text="Enflasyonu geçtin mi?"
        size={112}
        hero="Enflasyonu"
        style={{ marginTop: 44, width: 860 }}
      />
      <SubT
        text="Hisse, fon, altın, döviz — tek sandıkta. Getirini TÜFE ile yan yana koyar, gerçek farkı söyler."
        size={34}
        style={{ marginTop: 26, width: 760 }}
      />
      <div style={{ marginTop: 40 }}>
        <StoreLine size={0.8} />
      </div>
    </AbsoluteFill>
    <div style={{ position: "absolute", left: 1040, top: 110, transform: "rotate(-6deg)", transformOrigin: "0 0" }}>
      <PhoneHome w={470} />
    </div>
  </Shell>
);
