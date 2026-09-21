import React from "react";
import { Composition, Still } from "remotion";
import { Preview } from "./Preview";
import { SPEC } from "./theme";
// Reklam kompozisyonları (2026-09-19). Fontlar modül import'uyla yüklenir.
import "./reklam/fonts";
import { Reel, REEL } from "./reklam/Reel";
import { Square, SQUARE } from "./reklam/Square";
import { Bumper, BUMPER } from "./reklam/Bumper";
import { StillBanner, StillSquare, StillStory } from "./reklam/Stills";
// Tanıtım videosu (2026-09-21) — güncel ana ekran, 16:9, ~27 sn.
import { Tanitim, TANITIM_SPEC } from "./reklam/Tanitim";
// App Store önizlemesi (2026-09-21 kaydı) — 886×1920, 30 sn, ham kayıt üstü kurgu.
import { Onizleme30, ONIZLEME30 } from "./reklam/Onizleme30";

export const RemotionRoot: React.FC = () => {
  return (
    <>
      {/* iPhone — 886×1920 tüm güncel iPhone boyutlarını karşılar */}
      <Composition
        id="SandikPreview"
        component={Preview}
        durationInFrames={SPEC.durationInFrames}
        fps={SPEC.fps}
        width={SPEC.width}
        height={SPEC.height}
      />
      {/* iPad 13" — istenirse ayrıca render edilir */}
      <Composition
        id="SandikPreviewIpad"
        component={Preview}
        durationInFrames={SPEC.durationInFrames}
        fps={SPEC.fps}
        width={1200}
        height={1600}
      />

      {/* ---- Reklam videoları ---- */}
      <Composition id="AdReel" component={Reel} {...REEL} />
      <Composition id="AdSquare" component={Square} {...SQUARE} />
      <Composition id="AdBumper" component={Bumper} {...BUMPER} />
      <Composition id="Tanitim" component={Tanitim} {...TANITIM_SPEC} />
      <Composition id="Onizleme30" component={Onizleme30} {...ONIZLEME30} />

      {/* ---- Reklam görselleri ---- */}
      <Still
        id="StillSquareEnflasyon"
        component={StillSquare}
        width={1080}
        height={1080}
        defaultProps={{ variant: "enflasyon" as const }}
      />
      <Still
        id="StillSquareAltin"
        component={StillSquare}
        width={1080}
        height={1080}
        defaultProps={{ variant: "altin" as const }}
      />
      <Still
        id="StillSquareOrtak"
        component={StillSquare}
        width={1080}
        height={1080}
        defaultProps={{ variant: "ortak" as const }}
      />
      <Still id="StillStory" component={StillStory} width={1080} height={1920} />
      <Still id="StillBanner" component={StillBanner} width={1600} height={900} />
    </>
  );
};
