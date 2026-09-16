import React from "react";
import { Composition } from "remotion";
import { Preview } from "./Preview";
import { SPEC } from "./theme";

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
    </>
  );
};
