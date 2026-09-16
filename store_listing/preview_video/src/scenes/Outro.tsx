// Kapanış.
//
// Bilerek YAZILMAYANLAR:
// - Fiyat / "ücretsiz" (2.3.7 — önizlemede fiyat bilgisi geçmez)
// - "App Store'dan indir" CTA'sı ve mağaza rozeti (2.3.4 yalnızca ekran
//   kaydı + açıklayıcı overlay'e izin veriyor; indirme çağrısı ekranda
//   olup biteni açıklamıyor. Zaten kullanıcı ürün sayfasında, indirme
//   butonu videonun hemen üstünde.)
// - Android / Google Play adı, ikonu (2.3.10)
//
// Kalan: marka adı + ne olduğunu anlatan tek satır.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { theme } from "../theme";
import { useBreathe } from "../components/Motion";

export const Outro: React.FC<{ durationInFrames: number }> = ({
  durationInFrames,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const { scale: breathe, floatY } = useBreathe();

  // Wordmark: bouncy — logonun kendisi, videonun en büyük hareketi.
  const mark = spring({ frame, fps, config: theme.spring.bouncy });

  // Alt satır gecikmeli gelir (stagger).
  const sub = spring({ frame: frame - 10, fps, config: theme.spring.smooth });

  // Çıkış — son 8 karede sakin kapanış.
  const exit = interpolate(
    frame,
    [durationInFrames - 8, durationInFrames - 1],
    [1, 0],
    { easing: theme.ease.in, extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill
      style={{
        justifyContent: "center",
        alignItems: "center",
        // Kapanış zemini: kayıt bitti, marka öne çıkıyor.
        background: `radial-gradient(ellipse at center, ${theme.colors.surface1} 0%, ${theme.colors.bg} 70%)`,
        opacity: exit,
      }}
    >
      {/* Marka adı — karedeki TEK parlayan öğe */}
      <div
        style={{
          opacity: mark,
          transform: `scale(${interpolate(mark, [0, 1], [0.86, 1]) * breathe}) translateY(${
            interpolate(mark, [0, 1], [30, 0]) + floatY
          }px)`,
          fontFamily: theme.fonts.display,
          fontSize: 132,
          fontWeight: 800,
          letterSpacing: "-0.04em",
          color: theme.colors.gold,
          textShadow: `0 0 70px ${theme.colors.glow}`,
        }}
      >
        sandık
      </div>

      <div
        style={{
          opacity: sub,
          transform: `translateY(${interpolate(sub, [0, 1], [24, 0])}px)`,
          marginTop: 26,
          fontFamily: theme.fonts.body,
          fontSize: 40,
          fontWeight: 500,
          color: theme.colors.text58,
          letterSpacing: "-0.01em",
          textAlign: "center",
        }}
      >
        Portföyün, tek sandıkta
      </div>
    </AbsoluteFill>
  );
};
