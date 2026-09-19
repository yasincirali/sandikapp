// Reklam 2 — Instagram/Facebook akış, 1080×1080, 12 sn.
//
// Kanca: "Kârın gerçekten kârın mı?" — sonra bir fiş: fiyat farkı,
// komisyon (maliyete), temettü (kazanca), gerçek kâr. Rakiplerin ilk satırda
// durduğu yerde sandık dört satır yazar. Sayılar DEMO_PORTFOY (KCHOL).
import React from "react";
import { AbsoluteFill, useVideoConfig } from "remotion";
import { AdShell, Headline, Rise, Rule, Scene, Sfx, Sub } from "./shared";
import { DEMO, beat, theme } from "./theme";
import { StoreLine, Wordmark } from "./ui";

export const SQUARE = { width: 1080, height: 1080, fps: 30, durationInFrames: 360 } as const;

const PAD = 84;

export const Square: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);

  return (
    <AdShell>
      <Sfx at={3} file="pop.wav" volume={0.25} />
      <Sfx at={b(4)} file="whoosh.wav" volume={0.35} />
      {[0, 1, 2].map((i) => (
        <Sfx key={i} at={b(4) + 12 + i * 9} file="pop.wav" volume={0.2} />
      ))}
      <Sfx at={b(8)} file="impactSoft_medium_000.ogg" volume={0.5} />
      <Sfx at={b(14)} file="impactBell_heavy_000.ogg" volume={0.5} len={60} />

      {/* 1. Kanca */}
      <Scene from={0} to={b(4)}>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", padding: PAD }}>
          <Headline text="Kârın gerçekten kârın mı?" size={104} hero="gerçekten" delay={2} />
        </AbsoluteFill>
      </Scene>

      {/* 2. Fiş */}
      <Scene from={b(4)} to={b(14)}>
        <Fis />
      </Scene>

      {/* 3. CTA */}
      <Scene from={b(14)} to={SQUARE.durationInFrames}>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", padding: PAD }}>
          <Headline
            text="Gördüğün rakam, cebindeki rakam."
            size={78}
            weight={700}
            color={theme.colors.text90}
            delay={2}
            per={2}
            style={{ maxWidth: 860 }}
          />
          <Rise delay={16} breathe style={{ marginTop: 60 }}>
            <Wordmark size={110} />
          </Rise>
          <Rise delay={30} from={26} style={{ marginTop: 54 }}>
            <StoreLine size={0.9} />
          </Rise>
        </AbsoluteFill>
      </Scene>
    </AdShell>
  );
};

const Satir: React.FC<{
  label: string;
  note?: string;
  value: string;
  color: string;
  delay: number;
  big?: boolean;
  glow?: boolean;
}> = ({ label, note, value, color, delay, big, glow }) => (
  <Rise delay={delay} from={22}>
    <div
      style={{
        display: "flex",
        justifyContent: "space-between",
        alignItems: "baseline",
        width: 900,
        padding: `${big ? 8 : 4}px 0`,
      }}
    >
      <div style={{ display: "flex", alignItems: "baseline", gap: 18 }}>
        <span
          style={{
            fontSize: big ? 54 : 42,
            fontWeight: big ? 800 : 600,
            color: big ? theme.colors.text : theme.colors.text90,
            letterSpacing: "-0.02em",
          }}
        >
          {label}
        </span>
        {note ? (
          <span style={{ fontSize: 28, fontWeight: 500, color: theme.colors.text58 }}>{note}</span>
        ) : null}
      </div>
      <span
        style={{
          fontSize: big ? 72 : 48,
          fontWeight: 800,
          color,
          fontVariantNumeric: "tabular-nums",
          letterSpacing: "-0.03em",
          textShadow: glow ? `0 0 40px ${color}66` : "none",
        }}
      >
        {value}
      </span>
    </div>
  </Rise>
);

const Fis: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);
  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", padding: PAD }}>
      <Rise delay={0} from={16}>
        <div
          style={{
            fontSize: 30,
            fontWeight: 700,
            letterSpacing: "0.12em",
            color: theme.colors.text58,
            textTransform: "uppercase",
            marginBottom: 30,
          }}
        >
          KCHOL · {DEMO.kchol.alis}
        </div>
      </Rise>
      <div style={{ display: "flex", flexDirection: "column", gap: 22, alignItems: "center" }}>
        <Satir label="Fiyat farkı" value={DEMO.kchol.fiyatFarki} color={theme.colors.text} delay={10} />
        <Satir
          label="Komisyon"
          note="maliyete eklendi"
          value={DEMO.kchol.komisyon}
          color={theme.colors.loss}
          delay={19}
        />
        <Satir
          label="Temettü"
          note="kazanca yazıldı"
          value={DEMO.kchol.temettu}
          color={theme.colors.gain}
          delay={28}
        />
        <Rule delay={b(3.2)} width={900} color={theme.colors.text58} />
        <Satir
          label="Gerçek kâr"
          value={DEMO.kchol.gercek}
          color={theme.colors.gain}
          delay={b(4)}
          big
          glow
        />
      </div>
      <Sub
        text="Çoğu uygulama ilk satırda durur."
        size={40}
        delay={b(6)}
        style={{ marginTop: 56 }}
      />
    </AbsoluteFill>
  );
};
