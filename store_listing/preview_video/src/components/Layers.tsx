// Beş katmanlı yığın: arka plan → içerik → grade → grain + vignette.
// Düz tek renk arka plan yok — skill kuralı 5.
import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { theme } from "../theme";

/** Katman 1 — yumuşak hareketli mesh. Asla düz zemin. */
export const BgMesh: React.FC = () => {
  const frame = useCurrentFrame();
  // Sin/cos ile çok yavaş sürüklenme: sahne canlı kalır, dikkat çalmaz.
  const d1 = Math.sin(frame / 55) * 40;
  const d2 = Math.cos(frame / 70) * 32;

  return (
    <AbsoluteFill style={{ background: theme.colors.bg }}>
      <div
        style={{
          position: "absolute",
          width: 1100,
          height: 1100,
          borderRadius: "50%",
          top: -420,
          left: -280 + d1,
          filter: "blur(60px)",
          background: `radial-gradient(circle, ${theme.colors.primary}22, transparent 62%)`,
        }}
      />
      <div
        style={{
          position: "absolute",
          width: 820,
          height: 820,
          borderRadius: "50%",
          bottom: -360,
          right: -220 - d2,
          filter: "blur(80px)",
          background: `radial-gradient(circle, ${theme.colors.gain}18, transparent 65%)`,
        }}
      />
    </AbsoluteFill>
  );
};

/** Katman 4 — grade. Ekran kaydı + grafikleri tek görünüme bağlar. */
export const Grade: React.FC = () => (
  <AbsoluteFill style={{ pointerEvents: "none" }}>
    <AbsoluteFill
      style={{
        backgroundColor: theme.colors.primary,
        mixBlendMode: "soft-light",
        opacity: 0.1, // koyu tema: düşük tut, ekran kaydı zaten koyu
      }}
    />
    <AbsoluteFill
      style={{
        background:
          "linear-gradient(180deg, rgba(0,0,0,0.16), transparent 26%, transparent 74%, rgba(0,0,0,0.26))",
      }}
    />
  </AbsoluteFill>
);

/** Katman 5a — prosedürel grain, asset dosyası yok. */
export const Grain: React.FC = () => {
  const frame = useCurrentFrame();
  const noise = `url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='220' height='220'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='2'/%3E%3C/filter%3E%3Crect width='220' height='220' filter='url(%23n)' opacity='0.5'/%3E%3C/svg%3E")`;
  return (
    <AbsoluteFill
      style={{
        pointerEvents: "none",
        backgroundImage: noise,
        backgroundSize: "220px",
        // Kare kare kaydır: film titremesi
        backgroundPosition: `${(frame * 7) % 220}px ${(frame * 13) % 220}px`,
        opacity: 0.035,
        mixBlendMode: "overlay", // koyu tema
      }}
    />
  );
};

/** Katman 5b — vignette, en üstte. */
export const Vignette: React.FC = () => (
  <AbsoluteFill
    style={{
      pointerEvents: "none",
      background:
        "radial-gradient(ellipse at center, transparent 55%, rgba(0,0,0,0.30) 100%)",
    }}
  />
);
