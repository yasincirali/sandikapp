// Hareket ilkelleri. Kural: her giriş 2–3 özelliği birlikte oynatır,
// her interpolate clamp'lidir, linear easing yoktur.
import React from "react";
import { interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../theme";

/** İş gören giriş: opacity + translateY + scale birlikte. */
export const Entrance: React.FC<{
  delay?: number;
  children: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ delay = 0, children, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({
    frame: frame - delay,
    fps,
    config: theme.spring.smooth,
  });

  return (
    <div
      style={{
        opacity: p,
        transform: `translateY(${interpolate(p, [0, 1], [36, 0])}px) scale(${interpolate(
          p,
          [0, 1],
          [0.95, 1],
        )})`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/**
 * Kelime kelime açılan başlık.
 *
 * `gap` PİKSEL — em olsaydı ebeveynin font-size'ına (genelde 16px) göre
 * çözülür, 60px'lik başlıkta sıfıra yakın boşluk verirdi. Skill'in
 * özellikle uyardığı tuzak.
 */
export const WordReveal: React.FC<{
  text: string;
  delay?: number;
  per?: number;
  highlight?: string; // hero renkle vurgulanacak TEK kelime
  style?: React.CSSProperties;
}> = ({ text, delay = 0, per = 3, highlight, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        gap: 14,
        justifyContent: "center",
        ...style,
      }}
    >
      {text.split(" ").map((word, i) => {
        const p = spring({
          frame: frame - delay - i * per,
          fps,
          config: theme.spring.snappy,
        });
        // Noktalama kırpılarak karşılaştırılır: "kazandın," ile "kazandın"
        // eşleşmeyince vurgu sessizce kayboluyordu.
        const bare = word.replace(/[.,;:!?]/g, "");
        const isHero = highlight !== undefined && bare === highlight;

        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: p,
              transform: `translateY(${interpolate(p, [0, 1], [28, 0])}px)`,
              color: isHero ? theme.colors.primary : theme.colors.text90,
              // Parlama YALNIZCA vurgulu kelimede — kare başına tek hero öğe.
              textShadow: isHero ? `0 0 40px ${theme.colors.glow}` : "none",
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

/**
 * Sahne sarmalayıcı: giriş + çıkış.
 * Çıkış girişten HIZLI (10 kare / ~20 kare) — skill kuralı 4.
 */
export const SceneWrap: React.FC<{
  children: React.ReactNode;
  durationInFrames: number;
  style?: React.CSSProperties;
}> = ({ children, durationInFrames, style }) => {
  const frame = useCurrentFrame();

  const exitO = interpolate(
    frame,
    [durationInFrames - 10, durationInFrames - 1],
    [1, 0],
    { easing: theme.ease.in, extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  const exitY = interpolate(
    frame,
    [durationInFrames - 10, durationInFrames - 1],
    [0, -30],
    { easing: theme.ease.in, extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <div
      style={{
        width: "100%",
        height: "100%",
        opacity: exitO,
        transform: `translateY(${exitY}px)`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/** 2 sn'den uzun duran öğeler nefes alır — skill kuralı 7. */
export const useBreathe = () => {
  const frame = useCurrentFrame();
  return {
    scale: 1 + Math.sin(frame / 22) * 0.012,
    floatY: Math.sin(frame / 30) * 3,
  };
};
