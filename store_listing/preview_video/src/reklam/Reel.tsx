// Reklam 1 — Reels / Shorts / TikTok, 1080×1920, 15 sn.
//
// Kanca: mağaza metninin ilk cümlesi ("Paran arttı mı, yoksa sadece eridi
// mi?"). "eridi" kelimesi gerçekten erir — reklamın tek aşırılığı orada
// harcanır, gerisi sakin. Sonra iddianın hesabı (getiri − TÜFE = fark),
// sonra uygulamanın bunu nasıl gösterdiği, sonra kapsam, sonra CTA.
//
// Kesimler 114 BPM vuruş ızgarasında: 0 · 4 · 10 · 16 · 22 · 28,5 vuruş.
// 9:16 güvenli alan: kritik metin dikeyde 230–1660 arası.
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { AdShell, Counter, Headline, Rise, Rule, Scene, Sfx, Sub } from "./shared";
import { DEMO, SAFE_9x16, beat, theme, tr } from "./theme";
import { PhoneHome, StoreLine, TurCip, Wordmark } from "./ui";

export const REEL = { width: 1080, height: 1920, fps: 30, durationInFrames: 450 } as const;

const Center: React.FC<{ children: React.ReactNode; style?: React.CSSProperties }> = ({
  children,
  style,
}) => (
  <AbsoluteFill
    style={{
      justifyContent: "center",
      alignItems: "center",
      paddingTop: SAFE_9x16.top,
      paddingBottom: SAFE_9x16.bottom,
      paddingLeft: SAFE_9x16.side,
      paddingRight: SAFE_9x16.side,
      ...style,
    }}
  >
    {children}
  </AbsoluteFill>
);

export const Reel: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);

  return (
    <AdShell>
      {/* ---- SES ---- */}
      <Sfx at={3} file="pop.wav" volume={0.25} />
      <Sfx at={30} file="drop_001.ogg" volume={0.55} />
      <Sfx at={b(4)} file="whoosh.wav" volume={0.35} />
      <Sfx at={b(6)} file="pop.wav" volume={0.25} />
      <Sfx at={b(8)} file="impactSoft_medium_000.ogg" volume={0.5} />
      <Sfx at={b(10)} file="whoosh.wav" volume={0.35} />
      <Sfx at={b(10) + 26} file="pop.wav" volume={0.22} />
      <Sfx at={b(16)} file="whoosh.wav" volume={0.35} />
      {[0, 1, 2, 3].map((i) => (
        <Sfx key={i} at={b(16) + 18 + i * 5} file="pop.wav" volume={0.18} />
      ))}
      <Sfx at={b(22)} file="impactBell_heavy_000.ogg" volume={0.5} len={60} />

      {/* ---- 1. KANCA (0–4 vuruş) ---- */}
      <Scene from={0} to={b(4)}>
        <Center>
          <Headline text="Paran arttı mı," size={112} delay={2} />
          <Headline
            text="yoksa sadece eridi mi?"
            size={112}
            delay={14}
            melt="eridi"
            // Sahne 63. karede biter; erime 26 kare sürer. 40'ta başlasa
            // çıkışa kadar ancak yarıya gelirdi (kare 55 kontrolü: hâlâ net).
            meltAt={30}
            style={{ marginTop: 10 }}
          />
        </Center>
      </Scene>

      {/* ---- 2. HESAP (4–10 vuruş) ---- */}
      <Scene from={b(4)} to={b(10)}>
        <Hesap />
      </Scene>

      {/* ---- 3. UYGULAMA (10–16 vuruş) ---- */}
      <Scene from={b(10)} to={b(16)}>
        <Telefon />
      </Scene>

      {/* ---- 4. KAPSAM (16–22 vuruş) ---- */}
      <Scene from={b(16)} to={b(22)}>
        <Center style={{ justifyContent: "flex-start", paddingTop: SAFE_9x16.top + 120 }}>
          <Headline text="Hisse, fon, altın, döviz." size={92} delay={2} />
          <div
            style={{
              display: "grid",
              gridTemplateColumns: "1fr 1fr",
              gap: 24,
              marginTop: 70,
              // Flex sütununda grid içeriğe büzülüyordu — çipler başlığın
              // yanında minik kalıyordu (kare 250/300). Tam genişlik.
              width: "100%",
            }}
          >
            {[
              ["Hisse", theme.colors.primary],
              ["Fon", theme.colors.fon],
              ["Altın", theme.colors.gold],
              ["Döviz", theme.colors.doviz],
            ].map(([ad, renk], i) => (
              <Rise key={ad} delay={18 + i * 5} from={30}>
                <TurCip ad={ad} renk={renk} size={1.35} style={{ width: "100%", justifyContent: "flex-start" }} />
              </Rise>
            ))}
          </div>
          <Sub
            text="Komisyon maliyette, temettü kazançta."
            size={46}
            delay={44}
            style={{ marginTop: 74 }}
          />
          <Sub text="Gördüğün rakam, cebindeki rakam." size={46} delay={52} style={{ marginTop: 8 }} />
        </Center>
      </Scene>

      {/* ---- 5. CTA (22–28,5 vuruş) ---- */}
      <Scene from={b(22)} to={REEL.durationInFrames}>
        <Center>
          <Rise delay={0} breathe>
            <Wordmark size={150} />
          </Rise>
          <Headline
            text="Sandığını aç, ne kazandığını gör."
            size={66}
            weight={700}
            color={theme.colors.text90}
            delay={12}
            per={2}
            style={{ marginTop: 56, maxWidth: 820 }}
          />
          <Rise delay={30} from={30} style={{ marginTop: 70 }}>
            <StoreLine size={1.05} />
          </Rise>
        </Center>
      </Scene>
    </AdShell>
  );
};

/** Getiri − TÜFE = fark. Üç satır, tek parlama (son satır). */
const Hesap: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);
  const Row: React.FC<{ label: string; delay: number; children: React.ReactNode }> = ({
    label,
    delay,
    children,
  }) => (
    <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 14 }}>
      <Rise delay={delay} from={20}>
        <div
          style={{
            fontSize: 38,
            fontWeight: 600,
            color: theme.colors.text58,
            letterSpacing: "0.02em",
          }}
        >
          {label}
        </div>
      </Rise>
      {children}
    </div>
  );
  return (
    <Center>
      <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 54 }}>
        <Row label="Portföy getirisi" delay={0}>
          <Counter to={DEMO.pct} delay={4} prefix="+%" size={168} color={theme.colors.gold} />
        </Row>
        <Row label="Enflasyon (TÜFE)" delay={b(2)}>
          <Counter to={DEMO.tufe} delay={b(2) + 4} prefix="−%" size={168} color={theme.colors.loss} />
        </Row>
        <Rule delay={b(3.5)} width={560} color={`${theme.colors.text58}`} />
        <Row label="Gerçek fark" delay={b(4) - 4}>
          <Counter
            to={DEMO.fark}
            delay={b(4)}
            prefix="+"
            suffix=" puan"
            size={150}
            color={theme.colors.gain}
            glow
          />
        </Row>
      </div>
    </Center>
  );
};

/** Telefon alttan yükselir, çubuklar dolar, rozet oturur. */
const Telefon: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: theme.spring.smooth });
  const bars = spring({ frame: frame - 14, fps, config: { damping: 24, stiffness: 50, mass: 1 } });
  const rozet = spring({ frame: frame - 26, fps, config: theme.spring.snappy });
  // Sahne boyunca hafif yaklaşma — durağan mockup ölü görünür.
  const zoom = interpolate(frame, [0, 95], [1, 1.06], {
    easing: theme.ease.inOut,
    extrapolateLeft: "clamp",
    extrapolateRight: "clamp",
  });
  return (
    <AbsoluteFill>
      <AbsoluteFill
        style={{
          alignItems: "center",
          paddingTop: SAFE_9x16.top + 40,
          paddingLeft: SAFE_9x16.side,
          paddingRight: SAFE_9x16.side,
        }}
      >
        <Headline
          text="sandık ikisini yan yana koyar."
          size={76}
          hero="sandık"
          heroColor={theme.colors.gold}
          delay={4}
          per={2}
        />
      </AbsoluteFill>
      <div
        style={{
          position: "absolute",
          left: "50%",
          top: 560,
          transform: `translateX(-50%) translateY(${interpolate(enter, [0, 1], [260, 0])}px) scale(${zoom * interpolate(enter, [0, 1], [0.96, 1])})`,
          transformOrigin: "50% 20%",
          opacity: enter,
        }}
      >
        <PhoneHome w={600} bars={bars} rozetP={rozet} />
      </div>
    </AbsoluteFill>
  );
};

// tr() burada da kullanılıyor olabilir diye dışa açık tutuldu.
export const _tr = tr;
