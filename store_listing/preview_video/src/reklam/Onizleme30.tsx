// App Store önizleme videosu — 886×1920, 30 sn (2026-09-21 kaydı).
//
// ## Neden bu mesaj: "gerçeği söyler"
//
// Kayıttaki portföy enflasyonun GERİSİNDE (−0,5 / −9,2 puan, kırmızı).
// Önceki kurgular (`Preview`, `Tanitim`) yeşil demo portföye dayanıyordu;
// bu kayıtla o iddia kurulamaz. Kullanıcı kararı (2026-09-21): kırmızıyı
// gizleme, mesajı ona çevir — "nominal kârın var ama enflasyona göre
// gerisindesin" cümlesini söyleyebilen uygulama, söylemeyenden dürüsttür.
// Bu aynı zamanda `fiyat_kaynagi.dart`'ın "uydurma sayı yasak" kuralının
// pazarlama tarafıdır: ekranda ne varsa videoda o var, tek bir rakam
// rötuşlanmadı.
//
// ## Apple 2.3.4
// Önizleme YALNIZCA uygulamanın ekran kaydından oluşur. Metin katmanı
// kaydın ÜSTÜNDE durur ve ekranı örtmez; kayıt her karede görünür.
//
// ## Kesim noktaları (ham kayıt saniyesi → sahne)
//   04–10  ana ekran, toplam + Bugün kartı
//   30–36  görünüm kaydırma (Ben → Test → Birlikte)
//   56–62  Performans günlük grafik + crosshair
//   68–74  "Nereden geldi" dökümü (katkın / piyasa ayrımı)
//   84–90  KCHOL detayı: alış → bugün, +%53
//   104–110 portföy listesi + kaydırmalı aksiyonlar
// Kesimler 114 BPM ızgarasına oturur (`beat()`); ses yatağı ortak.
import React from "react";
import {
  AbsoluteFill,
  Audio,
  OffthreadVideo,
  Sequence,
  interpolate,
  spring,
  staticFile,
  useCurrentFrame,
  useVideoConfig,
} from "remotion";
import { BgMesh, Grade, Grain, Vignette } from "../components/Layers";
import { MUSIC, beat, theme } from "./theme";
import { Wordmark } from "./ui";

export const ONIZLEME30 = {
  width: 886,
  height: 1920,
  fps: 30,
  durationInFrames: 900, // 30 sn
} as const;

/** Ham kayıt: 60 fps, 1126×2436. `startFrom` KOMPOZİSYON karesidir. */
const KAYIT = "shots/kayit2.MP4";

const font = theme.fonts.display;

/**
 * Kayıt katmanı.
 *
 * `startFrom` saniye × kompozisyon fps'i (30) — kaydın kendi 60 fps'iyle
 * çarpmak videoyu iki kat ileri sardırır (Capture.tsx'teki aynı tuzak).
 * Hafif ölçek + çok yavaş kayma: duran ekran kaydı bile nefes alır
 * (skill kuralı 7), ama parmak hareketini bozacak kadar değil.
 */
const Kayit: React.FC<{ sn: number; hiz?: number; zoom?: number; panY?: number }> = ({
  sn,
  hiz = 1,
  zoom = 1,
  panY = 0,
}) => {
  const frame = useCurrentFrame();
  const { fps, durationInFrames } = useVideoConfig();
  // Ken Burns: 1 → +%3. Ekran kaydında daha fazlası metni bulanıklaştırır.
  const s = interpolate(frame, [0, durationInFrames], [zoom, zoom + 0.03], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const y = interpolate(frame, [0, durationInFrames], [0, panY], {
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <OffthreadVideo
        src={staticFile(KAYIT)}
        startFrom={Math.round(sn * fps)}
        playbackRate={hiz}
        volume={0}
        style={{
          width: "100%",
          height: "100%",
          objectFit: "cover",
          transform: `scale(${s}) translateY(${y}px)`,
        }}
      />
    </AbsoluteFill>
  );
};

/**
 * Alt bant + başlık. Kaydın üstünde durur, ekranın ORTA %60'ını örtmez:
 * mağaza oynatıcısı üst/alt kenarları kendi arayüzüyle kaplar, kritik
 * içerik ortada kalmalı.
 *
 * Giriş üç özelliği birlikte oynatır (opacity + translateY + scale),
 * çıkış girişten hızlıdır.
 */
const Altyazi: React.FC<{
  ust?: string;
  ana: string;
  vurgu?: string;
  vurguRenk?: string;
  dur: number;
  konum?: "alt" | "ust";
}> = ({ ust, ana, vurgu, vurguRenk, dur, konum = "alt" }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame, fps, config: theme.spring.smooth });
  const cikis = interpolate(frame, [dur - 8, dur - 1], [1, 0], {
    easing: theme.ease.in,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  const kayma = interpolate(p, [0, 1], [26, 0]);
  const olcek = interpolate(p, [0, 1], [0.97, 1]);

  return (
    <div
      style={{
        position: "absolute",
        left: 0,
        right: 0,
        // Alt sekme çubuğu kayıtta ~150 px yer kaplar; altyazı onun ÜSTÜNDE
        // durmalı. Doğrulama karelerinde metin "Ana / Portföy / Performans"
        // etiketlerinin üzerine biniyordu (2026-09-21).
        ...(konum === "alt" ? { bottom: 300 } : { top: 196 }),
        padding: "26px 44px 30px",
        opacity: p * cikis,
        transform: `translateY(${kayma}px) scale(${olcek})`,
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: 10,
        textAlign: "center",
        // Kendi bandı: kayıt açık renkli bir karta denk geldiğinde bile
        // metin okunur kalır. Gradyan kenarları yumuşatır, kutu hissi vermez.
        background:
          konum === "alt"
            ? "linear-gradient(180deg, rgba(4,26,18,0) 0%, rgba(4,26,18,0.92) 26%, rgba(4,26,18,0.94) 74%, rgba(4,26,18,0) 100%)"
            : "none",
      }}
    >
      {ust ? (
        <div
          style={{
            fontFamily: font,
            fontSize: 25,
            fontWeight: 700,
            letterSpacing: 2.4,
            textTransform: "uppercase",
            color: theme.colors.primary,
            textShadow: "0 2px 18px rgba(0,0,0,0.85)",
          }}
        >
          {ust}
        </div>
      ) : null}
      <div
        style={{
          fontFamily: font,
          fontSize: 56,
          lineHeight: 1.12,
          fontWeight: 800,
          color: theme.colors.text90,
          // Kayıt koyu ama her yerde değil; gölge okunurluğu garanti eder.
          textShadow: "0 3px 26px rgba(0,0,0,0.92), 0 1px 4px rgba(0,0,0,0.8)",
        }}
      >
        {ana}
        {vurgu ? (
          <>
            {" "}
            <span
              style={{
                color: vurguRenk ?? theme.colors.primary,
                textShadow: `0 0 34px ${vurguRenk ?? theme.colors.glow}66, 0 3px 26px rgba(0,0,0,0.9)`,
              }}
            >
              {vurgu}
            </span>
          </>
        ) : null}
      </div>
    </div>
  );
};

/** Kaydın üstünü/altını hafif karartır: altyazı her kayıtta okunur kalır. */
const Okunurluk: React.FC = () => (
  <AbsoluteFill
    style={{
      pointerEvents: "none",
      background:
        "linear-gradient(180deg, rgba(0,0,0,0.42) 0%, transparent 22%, transparent 58%, rgba(0,0,0,0.62) 88%)",
    }}
  />
);

/** Sahne: kayıt + okunurluk + altyazı. Kesim vuruşta. */
const Sahne: React.FC<{
  from: number;
  to: number;
  sn: number;
  hiz?: number;
  zoom?: number;
  panY?: number;
  ust?: string;
  ana: string;
  vurgu?: string;
  vurguRenk?: string;
  konum?: "alt" | "ust";
}> = ({ from, to, sn, hiz, zoom, panY, ust, ana, vurgu, vurguRenk, konum }) => {
  const dur = to - from;
  return (
    <Sequence from={from} durationInFrames={dur}>
      <Kayit sn={sn} hiz={hiz} zoom={zoom} panY={panY} />
      <Okunurluk />
      <Altyazi
        ust={ust}
        ana={ana}
        vurgu={vurgu}
        vurguRenk={vurguRenk}
        dur={dur}
        konum={konum}
      />
    </Sequence>
  );
};

/** SFX — görselden 3 kare önce (erken = senkron, geç = bozuk). */
const Sfx: React.FC<{ at: number; file: string; volume?: number; len?: number }> = ({
  at,
  file,
  volume = 0.4,
  len = 36,
}) => (
  <Sequence from={Math.max(0, at - 3)} durationInFrames={len}>
    <Audio src={staticFile(`sfx/${file}`)} volume={volume} />
  </Sequence>
);

/** Kapanış: wordmark + tek cümle. Kayıt yok, marka var. */
const Kapanis: React.FC<{ dur: number }> = ({ dur }) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame, fps, config: theme.spring.smooth });
  const p2 = spring({ frame: frame - 10, fps, config: theme.spring.smooth });
  const nefes = Math.sin(frame / 26) * 0.006;
  const cikis = interpolate(frame, [dur - 10, dur - 1], [1, 0], {
    easing: theme.ease.in,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill
      style={{
        alignItems: "center",
        justifyContent: "center",
        gap: 34,
        opacity: cikis,
      }}
    >
      <div
        style={{
          opacity: p,
          transform: `translateY(${interpolate(p, [0, 1], [30, 0])}px) scale(${
            interpolate(p, [0, 1], [0.9, 1]) + nefes
          })`,
        }}
      >
        <Wordmark size={92} />
      </div>
      <div
        style={{
          opacity: p2,
          transform: `translateY(${interpolate(p2, [0, 1], [22, 0])}px)`,
          fontFamily: font,
          fontSize: 46,
          fontWeight: 700,
          color: theme.colors.text90,
          textAlign: "center",
          padding: "0 70px",
          lineHeight: 1.3,
        }}
      >
        Paran ne kadar,{" "}
        <span style={{ color: theme.colors.gain, fontWeight: 800 }}>gerçekte</span> ne
        kadar.
      </div>
    </AbsoluteFill>
  );
};

export const Onizleme30: React.FC = () => {
  const { fps, durationInFrames } = useVideoConfig();
  const frame = useCurrentFrame();
  const b = (n: number) => beat(fps, n);

  // Müzik: 0,5 sn fade-in, son 1,5 sn fade-out.
  const vol = interpolate(
    frame,
    [0, 0.5 * fps, durationInFrames - 1.5 * fps, durationInFrames - 1],
    [0, MUSIC.volume, MUSIC.volume, 0],
    { extrapolateLeft: "clamp", extrapolateRight: "clamp" },
  );

  // Vuruş ızgarası (114 BPM ≈ 15,79 kare): sahne sınırları vuruş katları.
  const S = [0, b(9), b(18), b(27), b(36), b(45), b(51), durationInFrames];

  return (
    <AbsoluteFill style={{ background: theme.colors.bg, fontFamily: font }}>
      <Audio src={staticFile(MUSIC.file)} volume={vol} />
      <BgMesh />

      {/* 1 — Kanca: toplam varlık + günün hareketi (kayıt 04 sn) */}
      <Sahne
        from={S[0]}
        to={S[1]}
        sn={4}
        zoom={1.02}
        panY={-14}
        ust="Bugün ne oldu"
        ana="Tüm paran"
        vurgu="tek ekranda"
      />

      {/* 2 — Dürüstlük: enflasyon satırı. Kırmızı rakam kadrajın içinde. */}
      <Sahne
        from={S[1]}
        to={S[2]}
        sn={10}
        zoom={1.05}
        panY={-26}
        ust="Reel getiri"
        ana="Kârın var ama"
        vurgu="enflasyonu geçti mi?"
        vurguRenk={theme.colors.loss}
      />

      {/* 3 — Gün içi grafik: crosshair ile okuma (kayıt 56 sn) */}
      <Sahne
        from={S[2]}
        to={S[3]}
        sn={56}
        hiz={1.15}
        zoom={1.03}
        ust="Günlük"
        ana="Gün içinde"
        vurgu="ne oldu"
        vurguRenk={theme.colors.gain}
      />

      {/* 4 — Nereden geldi: katkın / piyasa ayrımı (kayıt 68 sn) */}
      <Sahne
        from={S[3]}
        to={S[4]}
        sn={69}
        zoom={1.04}
        panY={-20}
        ust="Nereden geldi"
        ana="Kendi paran mı,"
        vurgu="piyasa mı?"
        vurguRenk={theme.colors.gain}
      />

      {/* 5 — Varlık detayı: alış → bugün, teknik görünüm (kayıt 84 sn) */}
      <Sahne
        from={S[4]}
        to={S[5]}
        sn={84}
        hiz={1.1}
        zoom={1.03}
        ust="Her varlık"
        ana="Aldığın günden"
        vurgu="bugüne"
        vurguRenk={theme.colors.gain}
      />

      {/* 6 — Ortak portföy: iki defter, tek toplam (kayıt 30 sn) */}
      <Sahne
        from={S[5]}
        to={S[6]}
        sn={31}
        hiz={1.2}
        zoom={1.02}
        ust="Birlikte"
        ana="İkinizin portföyü"
        vurgu="tek toplamda"
      />

      {/* 7 — Kapanış */}
      <Sequence from={S[6]} durationInFrames={durationInFrames - S[6]}>
        <Kapanis dur={durationInFrames - S[6]} />
      </Sequence>

      {/* ---- SES ---- Kesimlerde kısa vurgu; kapanışta tok bir kapanış. */}
      <Sfx at={S[1]} file="whoosh.wav" volume={0.3} />
      <Sfx at={S[2]} file="pop.wav" volume={0.22} />
      <Sfx at={S[3]} file="whoosh.wav" volume={0.26} />
      <Sfx at={S[4]} file="pop.wav" volume={0.22} />
      <Sfx at={S[5]} file="whoosh.wav" volume={0.3} />
      <Sfx at={S[6]} file="thump.wav" volume={0.42} len={60} />

      <Grade />
      <Grain />
      <Vignette />
    </AbsoluteFill>
  );
};
