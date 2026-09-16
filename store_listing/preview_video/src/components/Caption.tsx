// Açıklayıcı metin overlay'i.
//
// Apple 2.3.4 metin overlay'ine izin verir: "You can add narration and video
// or textual overlays to help explain anything that isn't clear from the
// video alone." Yani metin AÇIKLAR — reklam sloganı değil, ekranda olup
// biteni anlatır.
//
// Fiyat yazılmaz (2.3.7), başka platform adı geçmez (2.3.10).
import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame, useVideoConfig } from "remotion";
import { SAFE, theme } from "../theme";
import { WordReveal } from "./Motion";

/**
 * Metnin okunurluğu için altına koyu bir taban gerekir: ekran kaydı
 * üstünde çıplak metin yer yer kayboluyor.
 */
export const Caption: React.FC<{
  text: string;
  highlight?: string;
  delay?: number;
  position?: "top" | "bottom";
}> = ({ text, highlight, delay = 0, position = "bottom" }) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  // Taban panel girişi — metinden 2 kare önce gelir ki metin boşluğa düşmesin.
  const panel = interpolate(frame, [delay - 2, delay + 12], [0, 1], {
    easing: theme.ease.out,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  // Çıkış: girişten hızlı.
  const exit = interpolate(
    frame,
    [durationInFrames - 9, durationInFrames - 1],
    [1, 0],
    { easing: theme.ease.in, extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  return (
    <AbsoluteFill
      style={{
        justifyContent: position === "bottom" ? "flex-end" : "flex-start",
        alignItems: "center",
        paddingTop: position === "top" ? SAFE.top : 0,
        // Alt sekme çubuğunun ÜSTÜNDE dur. SAFE.bottom tek başına yetmiyordu:
        // metin paneli uygulamanın tab bar'ıyla çakışıyordu (kare 40/470).
        paddingBottom: position === "bottom" ? SAFE.bottom + 190 : 0,
        paddingLeft: SAFE.side,
        paddingRight: SAFE.side,
        pointerEvents: "none",
      }}
    >
      <div
        style={{
          opacity: panel * exit,
          transform: `translateY(${interpolate(panel, [0, 1], [18, 0])}px)`,
          // Ekran kaydı koyu olduğu için 0.82 opaklık panelin görünmesine
          // yetmiyordu — metin çıplak duruyordu. Neredeyse opak + gölge.
          background: "rgba(7, 22, 15, 0.96)",
          backdropFilter: "blur(24px)",
          border: `1px solid ${theme.colors.primary}40`,
          borderRadius: 28,
          padding: "30px 36px",
          maxWidth: "100%",
          boxShadow: "0 30px 70px -18px rgba(0,0,0,0.85)",
        }}
      >
        <WordReveal
          text={text}
          highlight={highlight}
          delay={delay}
          per={3}
          style={{
            fontFamily: theme.fonts.display,
            fontSize: 52,
            fontWeight: 700,
            lineHeight: 1.12,
            letterSpacing: "-0.03em",
            textAlign: "center",
          }}
        />
      </div>
    </AbsoluteFill>
  );
};
