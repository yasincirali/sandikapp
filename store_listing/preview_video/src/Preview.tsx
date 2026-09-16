// App Store önizleme kurgusu.
//
// Yapı, store_listing/SCREENSHOT_PLAN.md'deki mesaj hiyerarşisini izler:
// en güçlü iddia önce. Sıra "uygulamayı gezdirme" değil, "ikna" sırasıdır.
//
// Süre 24 sn = 720 kare (zorunlu 15–30 sn aralığının ortası).
import React from "react";
import { AbsoluteFill, Audio, Sequence, staticFile } from "remotion";
import { SPEC, theme } from "./theme";
import { BgMesh, Grade, Grain, Vignette } from "./components/Layers";
import { Capture, CAPTURE_START_SECONDS } from "./components/Capture";
import { Caption } from "./components/Caption";
import { SceneWrap } from "./components/Motion";
import { Outro } from "./scenes/Outro";
import { PrivacyMask } from "./components/PrivacyMask";

const F = SPEC.fps;

/**
 * Sahne tablosu.
 *
 * `from`/`dur` — kurgudaki yeri (kare).
 * `startFrom`  — GERÇEK kayıtta bu anın başladığı kare. Kayıt geldiğinde
 *                bu değerler kaydın gerçek zamanlamasına göre güncellenir;
 *                şimdilik çekim senaryosundaki tahmini sıraya göre.
 * `shot`       — kayıt yokken gösterilecek gerçek ekran görüntüsü.
 */
const SCENES = [
  {
    key: "ana",
    from: 0,
    dur: 5 * F,
    shot: "shots/01_ana.png",
    startFrom: Math.round(CAPTURE_START_SECONDS * F),
    text: "Tüm yatırımların tek ekranda",
    highlight: "tek",
    zoomTo: 1.07,
    // Ortak seçicideki gerçek isim bu yükseklikte (kare 40'ta ölçüldü)
    maskTop: 0.503,
  },
  {
    key: "portfoy",
    from: 5 * F,
    dur: 4 * F,
    shot: "shots/02_portfoy.png",
    startFrom: Math.round((CAPTURE_START_SECONDS + 8) * F),
    text: "Hisse, fon, altın, döviz birlikte",
    highlight: "birlikte",
    zoomTo: 1.06,
  },
  {
    key: "varlik",
    from: 9 * F,
    dur: 5 * F,
    shot: "shots/04_varlik.png",
    startFrom: Math.round((CAPTURE_START_SECONDS + 13) * F),
    // FARKLILAŞTIRICI mesaj — rakiplerin yapmadığı şey.
    text: "Komisyon ve temettü dahil gerçek kâr",
    highlight: "gerçek",
    zoomTo: 1.08,
  },
  {
    key: "performans",
    from: 14 * F,
    dur: 5 * F,
    shot: "shots/03_performans.png",
    startFrom: Math.round((CAPTURE_START_SECONDS + 19) * F),
    text: "Zaman içinde ne kazandın, gör",
    highlight: "kazandın",
    zoomTo: 1.07,
    // Performans ekranında seçici daha yukarıda (kare 470'te ölçüldü)
    maskTop: 0.147,
  },
  {
    key: "dagilim",
    from: 19 * F,
    dur: 2.5 * F,
    shot: "shots/05_dagilim.jpeg",
    startFrom: Math.round((CAPTURE_START_SECONDS + 25) * F),
    text: "Ağırlığın nerede, tek bakışta",
    highlight: "nerede",
    zoomTo: 1.06,
  },
] as const;

const OUTRO_FROM = 21.5 * F;

export const Preview: React.FC = () => {
  return (
    <AbsoluteFill style={{ backgroundColor: theme.colors.bg }}>
      {/*
        Ses. Tamamı scripts/gen-sfx.mjs ile sentezlendi — hazır müzik
        kullanılmadığı için telif/lisans zinciri yok (2.3.9).
        Önizlemeler sessiz de oynatılabildiğinden video sessizken de
        tam anlaşılır olmalı; ses yalnızca destekler.
      */}
      <Audio src={staticFile("sfx/pad.wav")} volume={0.5} />

      {/* Sahne geçişlerinde whoosh — görüntüden 3 kare ÖNCE başlar */}
      {SCENES.slice(1).map((s) => (
        <Sequence key={`w-${s.key}`} from={Math.max(0, s.from - 3)} durationInFrames={20}>
          <Audio src={staticFile("sfx/whoosh.wav")} volume={0.32} />
        </Sequence>
      ))}

      {/* Metin girişinde yumuşak pop */}
      {SCENES.map((s) => (
        <Sequence key={`p-${s.key}`} from={s.from + 6} durationInFrames={10}>
          <Audio src={staticFile("sfx/pop.wav")} volume={0.22} />
        </Sequence>
      ))}

      {/* Kapanış vuruşu */}
      <Sequence from={Math.round(OUTRO_FROM) - 3} durationInFrames={30}>
        <Audio src={staticFile("sfx/thump.wav")} volume={0.42} />
      </Sequence>

      {/* Katman 1 — arka plan */}
      <BgMesh />

      {/* Katman 2+3 — ekran kaydı + açıklayıcı metin */}
      {SCENES.map((s) => (
        <Sequence key={s.key} from={s.from} durationInFrames={s.dur}>
          <SceneWrap durationInFrames={s.dur}>
            <AbsoluteFill>
              <Capture shot={s.shot} startFrom={s.startFrom} zoomTo={s.zoomTo} />
              {"maskTop" in s ? (
                <PrivacyMask topRatio={(s as { maskTop: number }).maskTop} />
              ) : null}
              {/* Metin, ekran oturduktan ~8 kare sonra gelsin */}
              <Caption text={s.text} highlight={s.highlight} delay={8} />
            </AbsoluteFill>
          </SceneWrap>
        </Sequence>
      ))}

      {/* Kapanış */}
      <Sequence from={OUTRO_FROM} durationInFrames={SPEC.durationInFrames - OUTRO_FROM}>
        <Outro durationInFrames={SPEC.durationInFrames - OUTRO_FROM} />
      </Sequence>

      {/* Katman 4 — grade (içeriğin üstünde) */}
      <Grade />

      {/* Katman 5 — grain + vignette (en üstte) */}
      <Grain />
      <Vignette />
    </AbsoluteFill>
  );
};
