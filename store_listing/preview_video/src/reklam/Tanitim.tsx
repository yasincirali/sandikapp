// Tanıtım videosu — 1920×1080, ~27 sn (2026-09-21, "son haliyle").
//
// Amaç: ilgi çekici ve işlevleri BASİTÇE anlatan video. Üslup, kullanıcının
// 2026-09-18'de beğendiği launch/mağaza üslubu: her sahnede özellik başlığı
// + tek düz cümle, jargon yok (TÜFE→enflasyon, XU100→BIST 100). Anlatım
// yok; müzik + seyrek SFX. Kesimler 114 BPM vuruş ızgarasında.
//
// Sahneler (vuruş): 0 kanca · 4 ana ekran · 12 Bugün kartı · 19 gerçek kazanç
// · 26 enflasyon · 32 ortak kaydırma · 38 bildirimler · 44–52 CTA.
// Arayüz `ui_home.tsx` ile güncel hâlde çizilir (piyasa şeridi, görünüm çipi
// + noktalar, Bugün kartı, kaydırmalı geçiş).
import React from "react";
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from "remotion";
import { AdShell, Counter, Headline, Rise, Rule, Scene, Sfx, Sub } from "./shared";
import { DEMO, TANITIM, beat, theme, tr, trInt } from "./theme";
import { StoreLine, Wordmark } from "./ui";
import { BildirimKarti, BugunKartiMock, PhoneHome2 } from "./ui_home";

export const TANITIM_SPEC = { width: 1920, height: 1080, fps: 30, durationInFrames: 821 } as const;

/** 16:9 kenar boşluğu. */
const M = 120;

/** Sol metin sütunu + sağ telefon: tanıtımın ana yerleşimi. */
const Split: React.FC<{ left: React.ReactNode; right: React.ReactNode; leftW?: number }> = ({
  left,
  right,
  leftW = 860,
}) => (
  <AbsoluteFill>
    <div
      style={{
        position: "absolute",
        left: M,
        top: 0,
        bottom: 0,
        width: leftW,
        display: "flex",
        flexDirection: "column",
        justifyContent: "center",
        gap: 28,
      }}
    >
      {left}
    </div>
    {right}
  </AbsoluteFill>
);

/** Telefon: alttan yükselir, sahne boyunca hafif yaklaşır, nefes alır. */
const Telefon: React.FC<{ children: (p: { s: number }) => React.ReactNode; w?: number; x?: number; y?: number }> = ({
  children,
  w = 460,
  x = 1200,
  y = 46,
}) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame, fps, config: theme.spring.smooth });
  const breathe = Math.sin(frame / 34) * 3;
  return (
    <div
      style={{
        position: "absolute",
        left: x,
        top: y,
        opacity: enter,
        transform: `translateY(${interpolate(enter, [0, 1], [180, 0]) + breathe}px) scale(${interpolate(enter, [0, 1], [0.96, 1])})`,
        transformOrigin: "50% 30%",
      }}
    >
      {children({ s: w / 430 })}
    </div>
  );
};

const Baslik: React.FC<{ text: string; hero?: string; delay?: number; size?: number }> = ({ text, hero, delay = 4, size = 88 }) => (
  <Headline text={text} hero={hero} heroColor={theme.colors.gold} size={size} delay={delay} per={2} align="left" style={{ maxWidth: 860 }} />
);

const Aciklama: React.FC<{ text: string; delay?: number }> = ({ text, delay = 22 }) => (
  <Sub text={text} size={40} delay={delay} style={{ textAlign: "left", maxWidth: 800 }} />
);

/** Toplam sayacı: 0 → 766.876, tabular. */
const useToplam = (delay: number) => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const p = spring({ frame: frame - delay, fps, config: { damping: 28, stiffness: 50, mass: 1 } });
  return `₺${trInt(interpolate(p, [0, 1], [0, 766876]))}`;
};

export const Tanitim: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);
  const END = TANITIM_SPEC.durationInFrames;

  return (
    <AdShell>
      {/* ---- SES ---- */}
      <Sfx at={3} file="pop.wav" volume={0.25} />
      <Sfx at={b(4)} file="whoosh.wav" volume={0.35} />
      <Sfx at={b(4) + 8} file="impactSoft_medium_000.ogg" volume={0.4} />
      <Sfx at={b(12)} file="whoosh.wav" volume={0.3} />
      {[0, 1, 2, 3].map((i) => (
        <Sfx key={`b${i}`} at={b(12) + 22 + i * 6} file="pop.wav" volume={0.16} />
      ))}
      <Sfx at={b(19)} file="whoosh.wav" volume={0.3} />
      <Sfx at={b(19) + 62} file="impactSoft_medium_000.ogg" volume={0.4} />
      <Sfx at={b(26)} file="whoosh.wav" volume={0.3} />
      <Sfx at={b(30)} file="impactSoft_medium_000.ogg" volume={0.45} />
      <Sfx at={b(32)} file="whoosh.wav" volume={0.3} />
      <Sfx at={b(32) + 30} file="drop_001.ogg" volume={0.4} />
      <Sfx at={b(38)} file="whoosh.wav" volume={0.3} />
      {[0, 1, 2].map((i) => (
        <Sfx key={`n${i}`} at={b(38) + 14 + i * 9} file="pop.wav" volume={0.22} />
      ))}
      <Sfx at={b(44)} file="impactBell_heavy_000.ogg" volume={0.5} len={70} />

      {/* ---- 1. KANCA ---- */}
      <Scene from={0} to={b(4)}>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center", padding: `0 ${M}px` }}>
          <Headline text="Altın mı, dolar mı, hisse mi" size={104} delay={2} per={2} />
          <Headline text="daha çok kazandırdı?" size={104} delay={12} per={2} hero="kazandırdı?" heroColor={theme.colors.gold} style={{ marginTop: 12 }} />
        </AbsoluteFill>
      </Scene>

      {/* ---- 2. ANA EKRAN ---- */}
      <Scene from={b(4)} to={b(12)}>
        <AnaEkran />
      </Scene>

      {/* ---- 3. BUGÜN KARTI ---- */}
      <Scene from={b(12)} to={b(19)}>
        <Bugun />
      </Scene>

      {/* ---- 4. GERÇEK KAZANÇ ---- */}
      <Scene from={b(19)} to={b(26)}>
        <GercekKazanc />
      </Scene>

      {/* ---- 5. ENFLASYON ---- */}
      <Scene from={b(26)} to={b(32)}>
        <Enflasyon />
      </Scene>

      {/* ---- 6. ORTAK ---- */}
      <Scene from={b(32)} to={b(38)}>
        <Ortak />
      </Scene>

      {/* ---- 7. BİLDİRİMLER ---- */}
      <Scene from={b(38)} to={b(44)}>
        <Bildirimler />
      </Scene>

      {/* ---- 8. CTA ---- */}
      <Scene from={b(44)} to={END} exitUp={false}>
        <AbsoluteFill style={{ justifyContent: "center", alignItems: "center" }}>
          <Rise delay={0} breathe>
            <Wordmark size={150} />
          </Rise>
          <Headline
            text="Sandığını aç, ne kazandığını gör."
            size={64}
            weight={700}
            color={theme.colors.text90}
            delay={12}
            per={2}
            style={{ marginTop: 52 }}
          />
          <Rise delay={30} from={30} style={{ marginTop: 60 }}>
            <StoreLine size={1.05} />
          </Rise>
        </AbsoluteFill>
      </Scene>
    </AdShell>
  );
};

/** 2 — güncel ana ekran: şerit akar, toplam sayar, Bugün satırları sırayla. */
const AnaEkran: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const toplam = useToplam(16);
  const bugunP = spring({ frame: frame - 34, fps, config: { damping: 26, stiffness: 40, mass: 1 } });
  return (
    <Split
      left={
        <>
          <Baslik text="Hepsi tek ekranda." hero="tek" />
          <Aciklama text="Hisse, fon, altın ve döviz. Fiyatlar kendiliğinden güncellenir; sen sadece bakarsın." />
        </>
      }
      right={
        <Telefon>
          {() => <PhoneHome2 w={460} serit={frame * 1.2} toplam={toplam} bugunP={bugunP} />}
        </Telefon>
      }
    />
  );
};

/** 3 — Bugün kartı büyük: satırlar sırayla gelir. */
const Bugun: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const enter = spring({ frame: frame - 4, fps, config: theme.spring.smooth });
  const p = spring({ frame: frame - 14, fps, config: { damping: 26, stiffness: 36, mass: 1 } });
  const breathe = Math.sin(frame / 34) * 3;
  return (
    <Split
      leftW={780}
      left={
        <>
          <Baslik text="Bugün ne oldu?" hero="Bugün" />
          <Aciklama text="Günün hareketi, enflasyona göre durumun, hedefine kalan. Her gün değişen tek kart." />
        </>
      }
      right={
        <div
          style={{
            position: "absolute",
            left: 1060,
            top: 130,
            opacity: enter,
            transform: `translateY(${interpolate(enter, [0, 1], [120, 0]) + breathe}px) scale(${interpolate(enter, [0, 1], [0.96, 1])})`,
          }}
        >
          <BugunKartiMock s={1.85} p={p} />
        </div>
      }
    />
  );
};

/** 4 — KCHOL örneği: fiyat farkı + temettü − komisyon = gerçek kazanç. */
const GercekKazanc: React.FC = () => {
  const { fps } = useVideoConfig();
  // Satır genişliği 740: 640'ta "Gerçek kazanç" etiketi ve 84 px'lik değer
  // ikişer satıra kırılıyordu (kare 400). Etiket ve değer nowrap.
  const W = 740;
  const Row: React.FC<{ label: string; value: string; delay: number; color: string; big?: boolean }> = ({ label, value, delay, color, big }) => (
    <Rise delay={delay} from={22}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline", width: W, fontFamily: theme.fonts.display }}>
        <span style={{ fontSize: big ? 40 : 34, fontWeight: 600, color: big ? theme.colors.text : theme.colors.text58, whiteSpace: "nowrap" }}>{label}</span>
        <span style={{ fontSize: big ? 76 : 54, fontWeight: 800, color, fontVariantNumeric: "tabular-nums", letterSpacing: "-0.03em", whiteSpace: "nowrap", textShadow: big ? `0 0 40px ${color}55` : "none" }}>
          {value}
        </span>
      </div>
    </Rise>
  );
  return (
    <Split
      leftW={780}
      left={
        <>
          <Baslik text="Gerçek kazancın." hero="Gerçek" />
          <Aciklama text="Komisyon maliyete girer, temettü kazanca yazılır. Gördüğün rakam, cebindeki rakam." />
        </>
      }
      right={
        <div style={{ position: "absolute", left: 1040, top: 0, bottom: 0, display: "flex", flexDirection: "column", justifyContent: "center", gap: 24 }}>
          <Rise delay={6} from={16}>
            <div style={{ fontFamily: theme.fonts.display, fontSize: 28, fontWeight: 700, color: theme.colors.text58, letterSpacing: "0.08em", textTransform: "uppercase" }}>
              KCHOL · {DEMO.kchol.alis}
            </div>
          </Rise>
          <Row label="Fiyat farkı" value={DEMO.kchol.fiyatFarki} delay={14} color={theme.colors.text90} />
          <Row label="Temettü" value={DEMO.kchol.temettu} delay={26} color={theme.colors.gain} />
          <Row label="Komisyon" value={DEMO.kchol.komisyon} delay={38} color={theme.colors.loss} />
          <Rule delay={52} width={W} color={theme.colors.text58} />
          <Row label="Gerçek kazanç" value={DEMO.kchol.gercek} delay={Math.round(beat(fps, 3.6))} color={theme.colors.gold} big />
        </div>
      }
    />
  );
};

/** 5 — getiri − enflasyon = fark; tek parlama son satırda. */
const Enflasyon: React.FC = () => {
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);
  // Sayaçlar sağa yaslı, sabit genişlikte kutuda: 120 px'lik sayaç 1040'tan
  // başlayınca "+%34,35" ve "puan" sağ kenardan taşıyordu (kare 500).
  const W = 760;
  const Row: React.FC<{ label: string; delay: number; children: React.ReactNode }> = ({ label, delay, children }) => (
    <div style={{ display: "flex", alignItems: "baseline", justifyContent: "space-between", width: W }}>
      <Rise delay={delay} from={16}>
        <div style={{ fontSize: 34, fontWeight: 600, color: theme.colors.text58, fontFamily: theme.fonts.display, whiteSpace: "nowrap" }}>{label}</div>
      </Rise>
      {children}
    </div>
  );
  return (
    <Split
      leftW={820}
      left={
        <>
          <Baslik text="Enflasyonu geçtin mi?" hero="Enflasyonu" size={80} />
          <Aciklama text="Getirin ile enflasyon yan yana. Fark tek satırda: öndesin ya da geridesin." />
        </>
      }
      right={
        <div style={{ position: "absolute", left: 1040, top: 0, bottom: 0, display: "flex", flexDirection: "column", justifyContent: "center", gap: 26 }}>
          <Row label="Portföy getirisi" delay={4}>
            <Counter to={DEMO.pct} delay={8} prefix="+%" size={96} color={theme.colors.gold} />
          </Row>
          <Row label="Enflasyon" delay={b(1.5)}>
            <Counter to={DEMO.tufe} delay={b(1.5) + 4} prefix="−%" size={96} color={theme.colors.loss} />
          </Row>
          <Rule delay={b(3)} width={W} color={theme.colors.text58} />
          <Row label="Gerçek fark" delay={b(3.5)}>
            <Counter to={DEMO.fark} delay={b(4)} prefix="+" suffix=" puan" size={88} color={theme.colors.gain} glow />
          </Row>
        </div>
      }
    />
  );
};

/** 6 — kartı sola kaydır: Ayşe'nin kartı yandan gelir, noktalar akar, Bugün kartı onun gününü anlatır. */
const Ortak: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  const b = (n: number) => beat(fps, n);
  // Sürükleme 1,5. vuruşta başlar, kart genişliği + boşluk kadar gider (398).
  const slide = spring({ frame: frame - b(1.5), fps, config: { damping: 22, stiffness: 70, mass: 1 } });
  const dx = -398 * slide;
  const gecti = slide > 0.985;
  const bugunP = spring({ frame: frame - b(3.2), fps, config: { damping: 26, stiffness: 44, mass: 1 } });
  return (
    <Split
      left={
        <>
          <Baslik text="Birlikte takip et." hero="Birlikte" />
          <Aciklama text="Eşinle ya da ortağınla aynı portföy. Kartı kaydır, onun gününü gör." />
        </>
      }
      right={
        <Telefon>
          {() => (
            <PhoneHome2
              w={460}
              serit={frame * 1.2 + 900}
              dx={dx}
              bugunP={gecti ? bugunP : 1}
              bugunEtiket={gecti ? "Ayşe'nin bugünü" : undefined}
              bugunKisisel={!gecti}
              bugunGun={gecti ? TANITIM.ayse : undefined}
            />
          )}
        </Telefon>
      }
    />
  );
};

/** 7 — üç bildirim üst üste düşer. */
const Bildirimler: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();
  return (
    <Split
      leftW={780}
      left={
        <>
          <Baslik text="Haber gelir." hero="Haber" />
          <Aciklama text="Fiyat alarmı, günlük brifing, enflasyon günü. Uygulamayı açmadan cebine düşer." />
        </>
      }
      right={
        <div style={{ position: "absolute", left: 1080, top: 0, bottom: 0, display: "flex", flexDirection: "column", justifyContent: "center", gap: 22 }}>
          {TANITIM.bildirimler.map((n, i) => {
            const p = spring({ frame: frame - 14 - i * 9, fps, config: theme.spring.snappy });
            const fy = Math.sin((frame + i * 40) / 30) * 2;
            return (
              <div
                key={n.baslik}
                style={{
                  opacity: p,
                  transform: `translateY(${interpolate(p, [0, 1], [-60, 0]) + fy}px) scale(${interpolate(p, [0, 1], [0.92, 1])})`,
                }}
              >
                <BildirimKarti baslik={n.baslik} govde={n.govde} saat={n.saat} size={1.1} />
              </div>
            );
          })}
        </div>
      }
    />
  );
};

export const _tr = tr;
