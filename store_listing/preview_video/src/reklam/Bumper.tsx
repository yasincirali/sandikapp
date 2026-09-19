// Reklam 3 — YouTube bumper / pre-roll, 1920×1080, 6 sn.
//
// 5 sn logo sting yapısı (design-rules): mark in → wordmark → tagline →
// nefes → çıkış. Tek soru, tek CTA.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { AdShell, Headline, Rise, Scene, Sfx } from "./shared";
import { theme } from "./theme";
import { AppIcon, StoreLine } from "./ui";

export const BUMPER = { width: 1920, height: 1080, fps: 30, durationInFrames: 180 } as const;

export const Bumper: React.FC = () => {
  return (
    <AdShell>
      <Sfx at={2} file="thump.wav" volume={0.45} />
      <Sfx at={16} file="whoosh.wav" volume={0.3} />
      <Sfx at={50} file="pop.wav" volume={0.25} />
      <Sfx at={104} file="impactSoft_medium_000.ogg" volume={0.45} />
      <Scene from={0} to={BUMPER.durationInFrames} exitUp={false}>
        <Sting />
      </Scene>
    </AdShell>
  );
};

const Sting: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // İkon: bouncy giriş + −14°'den düzelme. Videonun en büyük hareketi.
  const mark = spring({ frame, fps, config: theme.spring.bouncy });
  const rot = interpolate(mark, [0, 1], [-14, 0]);
  // Wordmark ikonun arkasından sağa kayarak çıkar.
  const wm = spring({ frame: frame - 14, fps, config: theme.spring.smooth });
  const breathe = 1 + Math.sin(frame / 22) * 0.012;

  return (
    <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
      <div style={{ display: "flex", alignItems: "center", gap: 44, transform: `scale(${breathe})` }}>
        <div
          style={{
            opacity: mark,
            transform: `scale(${interpolate(mark, [0, 1], [0.5, 1])}) rotate(${rot}deg)`,
          }}
        >
          <AppIcon size={200} />
        </div>
        <div style={{ overflow: "hidden", paddingRight: 20 }}>
          <div
            style={{
              opacity: wm,
              transform: `translateX(${interpolate(wm, [0, 1], [-160, 0])}px)`,
              fontFamily: theme.fonts.display,
              fontSize: 220,
              fontWeight: 800,
              letterSpacing: "-0.04em",
              lineHeight: 1,
              color: theme.colors.gold,
            }}
          >
            sandık
          </div>
        </div>
      </div>

      <Headline
        text="Enflasyonu geçtin mi?"
        size={96}
        hero="Enflasyonu"
        delay={48}
        per={3}
        style={{ marginTop: 64 }}
      />

      <Rise delay={102} from={26} style={{ marginTop: 56 }}>
        <StoreLine size={0.95} />
      </Rise>
    </AbsoluteFill>
  );
};
