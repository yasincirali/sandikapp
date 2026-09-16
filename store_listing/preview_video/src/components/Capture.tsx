// Ekran kaydı katmanı.
//
// Apple 2.3.4: önizleme YALNIZCA uygulamanın ekran kaydından oluşabilir.
// Bu yüzden asıl içerik burasıdır; metin overlay'leri sadece açıklar.
//
// Kayıt gelmeden de projenin render edilebilmesi için `PLACEHOLDER` modu
// var — böylece kurgu/zamanlama kayıt beklemeden doğrulanabiliyor.
// Kayıt public/shots/kayit.mov'a düştüğünde HAS_CAPTURE true olur.
import React from "react";
import {
  AbsoluteFill,
  Img,
  OffthreadVideo,
  interpolate,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { theme } from "../theme";

/**
 * Kayıt dosyası mevcut mu?
 *
 * Remotion bileşeni içinde fs okuyamayız (tarayıcıda çalışır), bu yüzden
 * bayrak elle çevrilir. Kaydı koyduktan sonra burayı true yap.
 */
export const HAS_CAPTURE = false;

/** Kaydın hangi saniyesinden başlanacağı (baştaki Denetim Merkezi'ni atla). */
export const CAPTURE_START_SECONDS = 3;

/**
 * Ekran kaydı — <OffthreadVideo>, asla <Video>.
 *
 * `startFrom` ham kaydın başındaki ölü zamanı kırpar.
 */
const RealCapture: React.FC<{ startFrom: number }> = ({ startFrom }) => (
  <OffthreadVideo
    src={staticFile("shots/kayit.mov")}
    startFrom={startFrom}
    style={{ width: "100%", height: "100%", objectFit: "cover" }}
    // Ekran kaydı biraz sönük gelir; hafif düzeltme.
    // (Grade katmanı ayrıca üstten bağlıyor.)
    volume={0}
  />
);

/**
 * Kayıt yokken: gerçek ekran GÖRÜNTÜSÜ + Ken Burns.
 *
 * Bu yalnızca kurguyu doğrulamak içindir; teslim edilecek videoda
 * gerçek kayıt kullanılır (2.3.4 "video screen captures").
 */
const PlaceholderShot: React.FC<{ src: string; zoomTo?: number }> = ({
  src,
  zoomTo = 1.08,
}) => {
  const frame = useCurrentFrame();
  const { durationInFrames } = useVideoConfig();

  // Her still Ken Burns alır — skill kuralı 6.
  const scale = interpolate(frame, [0, durationInFrames], [1, zoomTo], {
    easing: theme.ease.inOut,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const pan = interpolate(frame, [0, durationInFrames], [0, -18], {
    easing: theme.ease.inOut,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <Img
      src={staticFile(src)}
      style={{
        width: "100%",
        height: "100%",
        objectFit: "cover",
        transform: `scale(${scale}) translateY(${pan}px)`,
      }}
    />
  );
};

/**
 * Sahnenin görsel tabanı.
 *
 * `shot` — placeholder modunda gösterilecek ekran görüntüsü.
 * `startFrom` — gerçek kayıtta bu sahnenin başladığı kare.
 */
export const Capture: React.FC<{
  shot: string;
  startFrom: number;
  zoomTo?: number;
}> = ({ shot, startFrom, zoomTo }) => (
  <AbsoluteFill>
    {HAS_CAPTURE ? (
      <RealCapture startFrom={startFrom} />
    ) : (
      <PlaceholderShot src={shot} zoomTo={zoomTo} />
    )}
  </AbsoluteFill>
);
