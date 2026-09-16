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
 * bayrak elle çevrilir.
 *
 * 2026-09-16: kayıt geldi (public/shots/kayit.mov, 1126×2436, 60fps, 94 sn).
 * İlk yüklenen 384×832'lik sürüm ölçek olarak yetersizdi (886×1920 hedefin
 * altında, 2,3× büyütme gerekiyordu); aynı çekim tam çözünürlükte yeniden
 * yüklendi.
 */
export const HAS_CAPTURE = true;

/**
 * Kaydın hangi saniyesinden başlanacağı.
 *
 * Artık sahne başına ayrı `startFrom` verildiği için (bkz. Preview.tsx
 * SCENES) bu yalnızca placeholder modunun tabanıdır.
 */
export const CAPTURE_START_SECONDS = 3;

/**
 * Ekran kaydı — <OffthreadVideo>, asla <Video>.
 *
 * ## `startFrom` birimi: KOMPOZİSYON karesi, kaydın karesi değil
 *
 * Kayıt 60 fps, kompozisyon 30 fps. Remotion `startFrom`'u kompozisyonun
 * fps'iyle saniyeye çevirir, yani sahne tablosunda saniye × 30 yazılır.
 * Kaydın kendi 60 fps'iyle çarpmak videoyu iki kat ileri sardırırdı —
 * her sahne yanlış ekranı gösterirdi.
 *
 * `playbackRate` ile hız: bazı sahneler kayıtta ağır ilerliyor (kullanıcı
 * senaryo gereği her dokunuştan sonra 1–2 sn bekledi). Kurguda o bekleme
 * ölü zaman; hafif hızlandırma akışı toparlıyor.
 */
const RealCapture: React.FC<{ startFrom: number; speed?: number }> = ({
  startFrom,
  speed = 1,
}) => (
  <OffthreadVideo
    src={staticFile("shots/kayit.mov")}
    startFrom={startFrom}
    playbackRate={speed}
    style={{ width: "100%", height: "100%", objectFit: "cover" }}
    // Ham kayıtta mikrofon kapalıydı ama yine de sessize alınır: kurgunun
    // kendi ses yatağı var.
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
  speed?: number;
}> = ({ shot, startFrom, zoomTo, speed }) => (
  <AbsoluteFill>
    {HAS_CAPTURE ? (
      <RealCapture startFrom={startFrom} speed={speed} />
    ) : (
      <PlaceholderShot src={shot} zoomTo={zoomTo} />
    )}
  </AbsoluteFill>
);
