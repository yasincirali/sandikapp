// Reklamlara özgü hareket parçaları. Genel ilkeller ../components/Motion'da.
import React from "react";
import {
  AbsoluteFill,
  Audio,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { BgMesh, Grade, Grain, Vignette } from "../components/Layers";
import { MUSIC, theme, tr } from "./theme";

const font = theme.fonts.display;

/** Beş katmanlı yığın + müzik. Her reklam kompozisyonu bununla sarılır. */
export const AdShell: React.FC<{ children: React.ReactNode; music?: boolean }> = ({
  children,
  music = true,
}) => {
  const { durationInFrames, fps } = useVideoConfig();
  const frame = useCurrentFrame();
  // Müzik: 0,6 sn fade-in, son 1,2 sn fade-out. Kısa reklamda sert kesim
  // "video bozuldu" hissi verir.
  const vol = interpolate(
    frame,
    [0, 0.6 * fps, durationInFrames - 1.2 * fps, durationInFrames - 1],
    [0, MUSIC.volume, MUSIC.volume, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );
  return (
    <AbsoluteFill style={{ background: theme.colors.bg, fontFamily: font }}>
      {music ? <Audio src={staticFile(MUSIC.file)} volume={vol} /> : null}
      <BgMesh />
      {children}
      <Grade />
      <Grain />
      <Vignette />
    </AbsoluteFill>
  );
};

/** SFX: görselden 3 kare ÖNCE başlar (erken = senkron, geç = bozuk). */
export const Sfx: React.FC<{ at: number; file: string; volume?: number; len?: number }> = ({
  at,
  file,
  volume = 0.5,
  len = 40,
}) => (
  <Sequence from={Math.max(0, at - 3)} durationInFrames={len}>
    <Audio src={staticFile(`sfx/${file}`)} volume={volume} />
  </Sequence>
);

/**
 * Sahne sarmalayıcı: opacity + hafif yükselme ile giriş (spring), girişten
 * hızlı çıkış (10 kare). Kesimler vuruşta olduğundan geçiş kısadır.
 */
export const Scene: React.FC<{
  from: number;
  to: number;
  children: React.ReactNode;
  exitUp?: boolean;
}> = ({ from, to, children, exitUp = true }) => {
  const dur = to - from;
  return (
    <Sequence from={from} durationInFrames={dur}>
      <SceneBody dur={dur} exitUp={exitUp}>
        {children}
      </SceneBody>
    </Sequence>
  );
};

const SceneBody: React.FC<{ dur: number; exitUp: boolean; children: React.ReactNode }> = ({
  dur,
  exitUp,
  children,
}) => {
  const frame = useCurrentFrame();
  const exitO = interpolate(frame, [dur - 10, dur - 1], [1, 0], {
    easing: theme.ease.in,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const exitY = interpolate(frame, [dur - 10, dur - 1], [0, exitUp ? -40 : 0], {
    easing: theme.ease.in,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ opacity: exitO, transform: `translateY(${exitY}px)` }}>
      {children}
    </AbsoluteFill>
  );
};

/**
 * Kelime kelime başlık. Bir kelime `hero` rengiyle vurgulanır, bir kelime
 * `melt` ile erir (aşağı akar, bulanır) — "eridi" için.
 */
export const Headline: React.FC<{
  text: string;
  delay?: number;
  per?: number;
  size: number;
  hero?: string;
  heroColor?: string;
  melt?: string;
  meltAt?: number;
  weight?: number;
  color?: string;
  align?: "center" | "left";
  style?: React.CSSProperties;
}> = ({
  text,
  delay = 0,
  per = 3,
  size,
  hero,
  heroColor = theme.colors.primary,
  melt,
  meltAt = 999,
  weight = 800,
  color = theme.colors.text,
  align = "center",
  style,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <div
      style={{
        display: "flex",
        flexWrap: "wrap",
        justifyContent: align === "center" ? "center" : "flex-start",
        columnGap: size * 0.26,
        rowGap: size * 0.06,
        fontFamily: font,
        fontSize: size,
        fontWeight: weight,
        letterSpacing: "-0.035em",
        lineHeight: 1.06,
        textAlign: align,
        ...style,
      }}
    >
      {text.split(" ").map((word, i) => {
        const p = spring({ frame: frame - delay - i * per, fps, config: theme.spring.snappy });
        const bare = word.replace(/[.,;:!?]/g, "");
        const isHero = hero !== undefined && bare === hero;
        const isMelt = melt !== undefined && bare === melt;
        // Erime: meltAt'tan sonra 26 karede aşağı süzülür, bulanır, incelir.
        const m = isMelt
          ? interpolate(frame, [meltAt, meltAt + 26], [0, 1], {
              easing: theme.ease.in,
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            })
          : 0;
        return (
          <span
            key={i}
            style={{
              display: "inline-block",
              opacity: p * (1 - m * 0.55),
              transform: `translateY(${interpolate(p, [0, 1], [size * 0.4, 0]) + m * size * 0.35}px) scaleY(${1 + m * 0.45}) scaleX(${1 - m * 0.12})`,
              transformOrigin: "50% 0%",
              filter: m > 0 ? `blur(${m * 6}px)` : "none",
              color: isHero ? heroColor : isMelt ? theme.colors.loss : color,
              textShadow: isHero ? `0 0 ${size * 0.5}px ${heroColor}66` : "none",
            }}
          >
            {word}
          </span>
        );
      })}
    </div>
  );
};

/** Sayaç: spring ile hedefe, tabular-nums ile titremesiz. */
export const Counter: React.FC<{
  to: number;
  delay: number;
  prefix?: string;
  suffix?: string;
  decimals?: number;
  size: number;
  color: string;
  glow?: boolean;
  style?: React.CSSProperties;
}> = ({ to, delay, prefix = "", suffix = "", decimals = 2, size, color, glow, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - delay, fps, config: { damping: 28, stiffness: 60, mass: 1 } });
  const v = interpolate(p, [0, 1], [0, to]);
  const inP = spring({ frame: frame - delay, fps, config: theme.spring.smooth });
  return (
    <div
      style={{
        fontFamily: font,
        fontSize: size,
        fontWeight: 800,
        letterSpacing: "-0.04em",
        lineHeight: 1,
        color,
        fontVariantNumeric: "tabular-nums",
        opacity: inP,
        transform: `translateY(${interpolate(inP, [0, 1], [30, 0])}px) scale(${interpolate(inP, [0, 1], [0.94, 1])})`,
        textShadow: glow ? `0 0 ${size * 0.4}px ${color}55` : "none",
        whiteSpace: "nowrap",
        ...style,
      }}
    >
      {prefix}
      {tr(v, decimals)}
      {suffix}
    </div>
  );
};

/** Giriş: opacity + y + scale birlikte. Uzun duranlar nefes alır. */
export const Rise: React.FC<{
  delay?: number;
  children: React.ReactNode;
  breathe?: boolean;
  from?: number;
  style?: React.CSSProperties;
}> = ({ delay = 0, children, breathe = false, from = 40, style }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - delay, fps, config: theme.spring.smooth });
  const b = breathe ? 1 + Math.sin(frame / 22) * 0.012 : 1;
  const fy = breathe ? Math.sin(frame / 30) * 3 : 0;
  return (
    <div
      style={{
        opacity: p,
        transform: `translateY(${interpolate(p, [0, 1], [from, 0]) + fy}px) scale(${interpolate(p, [0, 1], [0.94, 1]) * b})`,
        ...style,
      }}
    >
      {children}
    </div>
  );
};

/** Alt satır — açıklayıcı tek cümle, sakin ağırlık. */
export const Sub: React.FC<{ text: string; delay?: number; size: number; style?: React.CSSProperties }> = ({
  text,
  delay = 0,
  size,
  style,
}) => (
  <Rise delay={delay} from={24} style={style}>
    <div
      style={{
        fontFamily: font,
        fontSize: size,
        fontWeight: 500,
        color: theme.colors.text58,
        letterSpacing: "-0.01em",
        lineHeight: 1.25,
        textAlign: "center",
      }}
    >
      {text}
    </div>
  </Rise>
);

/** Çizilen yatay çizgi (toplam satırının üstü). */
export const Rule: React.FC<{ delay: number; width: number; color?: string }> = ({
  delay,
  width,
  color = theme.colors.divider,
}) => {
  const frame = useCurrentFrame();
  const w = interpolate(frame, [delay, delay + 14], [0, width], {
    easing: theme.ease.out,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return <div style={{ width: w, height: 2, background: color, borderRadius: 1 }} />;
};
