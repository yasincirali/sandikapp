// Güncel ana ekranın çizimi (2026-09-21): piyasa şeridi, toplam kartı +
// görünüm çipi + sayfa noktaları, Bugün kartı. `ui.tsx`'teki PhoneHome
// 2026-09-19 arayüzünü (rozet kartı + dağılım) çizer; tanıtım videosu
// "son hâl" ister, bu dosya o hâli çizer. Neden ekran kaydı değil: ui.tsx
// başındaki gerekçe aynen geçerli (gerçek hesap izi yok, sayılar DEMO ile
// tutarlı, hareket kendi zamanlamamızda) — üstelik emülatör Flutter'ı render
// edemiyor, gerçek cihaz kaydı da bu turda yok.
//
// Ölçek: tasarım genişliği 430 (iPhone pt), `s = w / 430`. Bileşenler
// telefon içinde küçük, Bugün kartı sahnesinde büyük çizilir (aynı kod).
import React from "react";
import { interpolate } from "remotion";
import { DEMO, TANITIM, theme, tr } from "./theme";
import { AppIcon, Tri } from "./ui";

const font = theme.fonts.display;

/** Tasarım genişliği ve kart penceresi (kenar boşluğu 22). */
export const DESIGN_W = 430;
export const PAD = 22;
export const CARD_W = DESIGN_W - PAD * 2; // 386
export const CARD_GAP = 12;

// ── Piyasa şeridi ─────────────────────────────────────────────────────────

/** Dört öğe, döngüsel; `offset` tasarım px cinsinden kayma (zamanla artar). */
export const PiyasaSeridiMock: React.FC<{ s: number; offset: number }> = ({ s, offset }) => {
  const itemW = 196;
  const W = itemW * TANITIM.piyasa.length;
  const x = -((((offset % W) + W) % W) * s);
  const items = [...TANITIM.piyasa, ...TANITIM.piyasa, ...TANITIM.piyasa];
  return (
    <div
      style={{
        height: 30 * s,
        margin: `${10 * s}px ${PAD * s}px 0`,
        borderTop: `1px solid ${theme.colors.divider}`,
        borderBottom: `1px solid ${theme.colors.divider}`,
        overflow: "hidden",
        position: "relative",
        fontFamily: font,
      }}
    >
      <div style={{ position: "absolute", left: x, top: 0, height: "100%", display: "flex" }}>
        {items.map((p, i) => {
          const pct: number = p.pct;
          const renk = pct === 0 ? theme.colors.text58 : pct > 0 ? theme.colors.gain : theme.colors.loss;
          return (
            <div
              key={i}
              style={{
                width: itemW * s,
                display: "flex",
                alignItems: "center",
                gap: 5 * s,
                whiteSpace: "nowrap",
                fontSize: 12.5 * s,
              }}
            >
              <span style={{ color: theme.colors.text58, fontWeight: 600 }}>{p.ad}</span>
              <span style={{ color: theme.colors.text90, fontWeight: 700, fontVariantNumeric: "tabular-nums" }}>
                {p.deger}
              </span>
              <Tri size={7 * s} color={renk} down={p.pct < 0} />
              <span style={{ color: renk, fontWeight: 700 }}>%{tr(Math.abs(p.pct))}</span>
              <span style={{ color: theme.colors.text58, marginLeft: 8 * s }}>·</span>
            </div>
          );
        })}
      </div>
    </div>
  );
};

// ── Toplam kartı + görünüm çipi ───────────────────────────────────────────

const Eyebrow: React.FC<{ s: number; color?: string; children: React.ReactNode }> = ({
  s,
  color = theme.colors.gain,
  children,
}) => (
  <div
    style={{
      fontFamily: font,
      fontSize: 12 * s,
      fontWeight: 700,
      letterSpacing: "0.12em",
      color,
      textTransform: "uppercase",
    }}
  >
    {children}
  </div>
);

/** Görünüm çipi: avatar harfi + ad (Ben / Ayşe / Birlikte). */
export const GorunumCip: React.FC<{ s: number; ad: string; harf?: string; birlikte?: boolean }> = ({
  s,
  ad,
  harf,
  birlikte,
}) => (
  <div
    style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 6 * s,
      padding: `${5 * s}px ${10 * s}px ${5 * s}px ${6 * s}`,
      borderRadius: 999,
      background: theme.colors.surface2,
      border: `1px solid ${theme.colors.divider}`,
      fontFamily: font,
      fontSize: 12 * s,
      fontWeight: 700,
      color: theme.colors.text90,
      whiteSpace: "nowrap",
    }}
  >
    {birlikte ? (
      <div style={{ width: 24 * s, height: 16 * s, position: "relative" }}>
        <div style={{ position: "absolute", left: 0, width: 16 * s, height: 16 * s, borderRadius: "50%", background: theme.colors.primary, border: `1.5px solid ${theme.colors.surface2}` }} />
        <div style={{ position: "absolute", left: 8 * s, width: 16 * s, height: 16 * s, borderRadius: "50%", background: theme.colors.gain, border: `1.5px solid ${theme.colors.surface2}` }} />
      </div>
    ) : (
      <div
        style={{
          width: 16 * s,
          height: 16 * s,
          borderRadius: "50%",
          background: theme.colors.primary,
          color: theme.colors.onAmber,
          fontSize: 10 * s,
          fontWeight: 800,
          display: "flex",
          alignItems: "center",
          justifyContent: "center",
        }}
      >
        {harf}
      </div>
    )}
    {ad}
  </div>
);

/** Toplam kartı. `toplam` metin (sayaç dışarıda), `kz`/`pct` değişim satırı. */
export const HeroKart: React.FC<{
  s: number;
  toplam: string;
  kz: string;
  pct: string;
  cip: React.ReactNode;
  style?: React.CSSProperties;
}> = ({ s, toplam, kz, pct, cip, style }) => (
  <div
    style={{
      width: CARD_W * s,
      padding: `${18 * s}px ${22 * s}px`,
      borderRadius: 22 * s,
      background: theme.colors.surface1,
      border: `1px solid ${theme.colors.divider}`,
      fontFamily: font,
      boxSizing: "border-box",
      ...style,
    }}
  >
    <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
      <Eyebrow s={s}>Toplam net varlık</Eyebrow>
      {cip}
    </div>
    <div
      style={{
        marginTop: 8 * s,
        fontSize: 46 * s,
        fontWeight: 800,
        letterSpacing: "-0.03em",
        color: theme.colors.gold,
        lineHeight: 1.05,
        fontVariantNumeric: "tabular-nums",
        whiteSpace: "nowrap",
      }}
    >
      {toplam}
    </div>
    <div
      style={{
        marginTop: 8 * s,
        display: "flex",
        alignItems: "center",
        gap: 8 * s,
        color: theme.colors.gain,
        fontSize: 18 * s,
        fontWeight: 700,
        whiteSpace: "nowrap",
      }}
    >
      <Tri size={10 * s} color={theme.colors.gain} />
      <span>{kz}</span>
      <span>{pct}</span>
    </div>
  </div>
);

/**
 * Kart penceresi — carousel. `dx` tasarım px (negatif = sola sürükleme).
 * Ben kartı parmağı izler, komşu (Ayşe) yandan gelir; pencere kırpar.
 * Altında sayfa noktaları: seçili hap `ilerleme` ile komşuya akar.
 */
export const KartPenceresi: React.FC<{
  s: number;
  dx: number;
  toplamBen: string;
  toplamAyse?: string;
}> = ({ s, dx, toplamBen, toplamAyse = DEMO.ortak.ayse }) => {
  const tam = CARD_W + CARD_GAP;
  const ilerleme = Math.max(-1, Math.min(1, dx / tam));
  const komsuX = dx < 0 ? dx + tam : dx - tam;
  return (
    <div style={{ margin: `${14 * s}px ${PAD * s}px 0` }}>
      <div style={{ position: "relative", width: CARD_W * s, overflow: "hidden" }}>
        <div style={{ transform: `translateX(${dx * s}px)` }}>
          <HeroKart
            s={s}
            toplam={toplamBen}
            kz={DEMO.kz}
            pct={`%${tr(DEMO.pct)}`}
            cip={<GorunumCip s={s} ad="Ben" harf="B" />}
          />
        </div>
        {dx !== 0 ? (
          <div style={{ position: "absolute", left: komsuX * s, top: 0, width: CARD_W * s }}>
            <HeroKart
              s={s}
              toplam={toplamAyse}
              kz="+₺211.360"
              pct="%35,6"
              cip={<GorunumCip s={s} ad="Ayşe" harf="A" />}
            />
          </div>
        ) : null}
      </div>
      {/* Sayfa noktaları: Ben · Ayşe · Birlikte */}
      <div style={{ display: "flex", justifyContent: "center", gap: 6 * s, marginTop: 10 * s, position: "relative", height: 6 * s }}>
        {[0, 1, 2].map((i) => (
          <div key={i} style={{ width: 6 * s, height: 6 * s, borderRadius: 3 * s, background: theme.colors.text58, opacity: 0.45 }} />
        ))}
        <div
          style={{
            position: "absolute",
            left: `calc(50% - ${9 * s}px + ${-ilerleme * 12 * s}px)`,
            top: 0,
            width: 18 * s,
            height: 6 * s,
            borderRadius: 3 * s,
            background: theme.colors.primary,
          }}
        />
      </div>
    </div>
  );
};

// ── Bugün kartı ───────────────────────────────────────────────────────────

const Sparkline: React.FC<{ w: number; h: number; color: string }> = ({ w, h, color }) => {
  const pts = [0.55, 0.5, 0.58, 0.42, 0.46, 0.3, 0.34, 0.2, 0.16];
  const d = pts
    .map((p, i) => `${i === 0 ? "M" : "L"}${(w * i) / (pts.length - 1)},${p * h}`)
    .join(" ");
  const lx = w;
  const ly = pts[pts.length - 1] * h;
  return (
    <svg width={w} height={h} viewBox={`0 0 ${w} ${h}`} style={{ display: "block", overflow: "visible" }}>
      <path d={d} fill="none" stroke={color} strokeWidth={Math.max(1.5, w / 42)} strokeLinecap="round" strokeLinejoin="round" />
      <circle cx={lx} cy={ly} r={Math.max(2, w / 32)} fill={color} />
    </svg>
  );
};

/** `etiket ····· değer ›` satırı + kısa açıklama; `p` giriş ilerlemesi. */
const DefterSatiri: React.FC<{
  s: number;
  etiket: string;
  deger: string;
  ipucu: string;
  renk: string;
  p: number;
  cubuk?: number;
}> = ({ s, etiket, deger, ipucu, renk, p, cubuk }) => (
  <div
    style={{
      padding: `${7 * s}px 0`,
      opacity: p,
      transform: `translateY(${interpolate(p, [0, 1], [10 * s, 0])}px)`,
    }}
  >
    <div style={{ display: "flex", alignItems: "baseline", gap: 6 * s, fontSize: 13 * s }}>
      <span style={{ color: theme.colors.text90, fontWeight: 500, whiteSpace: "nowrap" }}>{etiket}</span>
      <span
        style={{
          flex: 1,
          borderBottom: `${1.5 * s}px dotted ${theme.colors.text58}`,
          opacity: 0.5,
          transform: `translateY(-${4 * s}px)`,
          minWidth: 24 * s,
        }}
      />
      <span style={{ color: renk, fontWeight: 700, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" }}>{deger}</span>
      <span style={{ color: theme.colors.text58, fontSize: 12 * s }}>›</span>
    </div>
    <div style={{ fontSize: 11.5 * s, color: theme.colors.text58, marginTop: 1 * s, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>
      {ipucu}
    </div>
    {cubuk !== undefined ? (
      <div style={{ height: 4 * s, borderRadius: 2 * s, background: theme.colors.surface2, marginTop: 6 * s, overflow: "hidden" }}>
        <div style={{ width: `${cubuk * p}%`, height: "100%", background: renk }} />
      </div>
    ) : null}
  </div>
);

/**
 * Bugün kartı — uygulamadaki almanak düzeni: tarih sütunu | günün hareketi;
 * defter satırları; ayak notu. `p` 0→1 satırların sırayla girişi.
 * `etiket` kapsam başlığı (ortak görünümü), `kisisel` hedef satırı.
 */
export const BugunKartiMock: React.FC<{
  s: number;
  p?: number;
  etiket?: string;
  kisisel?: boolean;
  gun?: { tutar: string; pct: number };
  style?: React.CSSProperties;
}> = ({ s, p = 1, etiket, kisisel = true, gun = TANITIM.gun, style }) => {
  const c = theme.colors;
  const row = (i: number) =>
    interpolate(p, [0.15 + i * 0.16, 0.45 + i * 0.16], [0, 1], {
      extrapolateLeft: "clamp",
      extrapolateRight: "clamp",
    });
  const head = interpolate(p, [0, 0.3], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const satirlar = [
    { etiket: "Enflasyona göre", deger: `+${tr(DEMO.fark, 1)} puan`, ipucu: "Yıllık getirin ile TÜFE farkı", renk: c.gain },
    { etiket: "Geçen hafta", deger: `+%${tr(TANITIM.haftalik, 1)}`, ipucu: "Piyasanın portföyüne etkisi · özet hazır", renk: c.gain },
    ...(kisisel
      ? [{ etiket: "Hedef", deger: `%${TANITIM.hedefOran} · ${TANITIM.hedefKalan}`, ipucu: "₺1.000.000 hedefe kalan", renk: c.gain, cubuk: TANITIM.hedefOran }]
      : []),
    { etiket: "Artıdaki varlık", deger: TANITIM.yesil, ipucu: "Alış fiyatının üstündekiler", renk: c.text90 },
  ];
  return (
    <div
      style={{
        width: CARD_W * s,
        padding: `${16 * s}px ${16 * s}px ${6 * s}px`,
        borderRadius: 20 * s,
        background: c.surface1,
        border: `1px solid ${c.divider}`,
        fontFamily: font,
        boxSizing: "border-box",
        ...style,
      }}
    >
      {etiket ? (
        // `lang="tr"`: CSS uppercase Türkçe i→İ dönüşümünü ancak dil
        // işaretliyken yapar; yoksa "AYŞE'NIN" çıkıyordu (kare 590).
        <div lang="tr" style={{ fontSize: 10.5 * s, fontWeight: 600, letterSpacing: "0.08em", textTransform: "uppercase", color: c.text58, marginBottom: 8 * s, opacity: head }}>
          {etiket}
        </div>
      ) : null}
      <div style={{ display: "flex", alignItems: "center", opacity: head, transform: `translateY(${(1 - head) * 8 * s}px)` }}>
        <div style={{ width: 60 * s, flex: "none" }}>
          <div style={{ fontSize: 34 * s, fontWeight: 800, letterSpacing: -1 * s, lineHeight: 1, color: c.text90 }}>21</div>
          <div style={{ fontSize: 12 * s, fontWeight: 600, color: c.text58, marginTop: 4 * s }}>Eylül</div>
          <div style={{ fontSize: 12 * s, color: c.text58, opacity: 0.8 }}>Pazartesi</div>
        </div>
        <div style={{ width: 1, height: 48 * s, background: c.divider, margin: `0 ${12 * s}px`, flex: "none" }} />
        <div style={{ flex: 1, minWidth: 0, display: "flex", alignItems: "center", gap: 10 * s }}>
          <div style={{ minWidth: 0, flex: 1 }}>
            <div style={{ fontSize: 20 * s, fontWeight: 700, letterSpacing: "-0.01em", color: c.gain, whiteSpace: "nowrap", fontVariantNumeric: "tabular-nums" }}>
              {gun.tutar}
              <span style={{ fontSize: 12 * s, fontWeight: 600, marginLeft: 6 * s }}>%{tr(gun.pct)} artıda</span>
            </div>
            <div style={{ fontSize: 11.5 * s, color: c.text58, marginTop: 3 * s, whiteSpace: "nowrap" }}>Seans açık · 18:00 kapanış</div>
          </div>
          <Sparkline w={64 * s} h={24 * s} color={c.gain} />
        </div>
      </div>
      <div style={{ height: 1, background: c.divider, margin: `${10 * s}px 0 ${4 * s}px` }} />
      {satirlar.map((r, i) => (
        <DefterSatiri key={r.etiket} s={s} p={row(i)} {...r} />
      ))}
      <div
        style={{
          display: "flex",
          justifyContent: "space-between",
          fontSize: 11.5 * s,
          color: c.text58,
          padding: `${8 * s}px 0 ${6 * s}px`,
          borderTop: `1px solid ${c.divider}`,
          marginTop: 4 * s,
          opacity: row(satirlar.length),
        }}
      >
        <span>
          TÜİK enflasyonu · <span style={{ color: c.text90, fontWeight: 600 }}>3 Ekim</span>
        </span>
        <span>12 gün</span>
      </div>
    </div>
  );
};

// ── Telefon çerçevesi + güncel ana ekran ──────────────────────────────────

/**
 * Güncel ana ekran. `w` genişlik px. Hareket girdileri:
 *   `serit`  piyasa şeridi kayması (tasarım px),
 *   `dx`     kart penceresi sürüklemesi (tasarım px, negatif sola),
 *   `bugunP` Bugün kartı satır girişleri (0→1),
 *   `toplam` toplam metni (sayaç dışarıda hesaplanır).
 */
export const PhoneHome2: React.FC<{
  w: number;
  serit: number;
  dx?: number;
  bugunP?: number;
  toplam?: string;
  bugunEtiket?: string;
  bugunKisisel?: boolean;
  bugunGun?: { tutar: string; pct: number };
  style?: React.CSSProperties;
}> = ({ w, serit, dx = 0, bugunP = 1, toplam = DEMO.toplam, bugunEtiket, bugunKisisel = true, bugunGun, style }) => {
  const s = w / DESIGN_W;
  const h = w * (19.5 / 9);
  return (
    <div
      style={{
        width: w,
        height: h,
        borderRadius: 66 * s,
        background: theme.colors.frame,
        padding: 12 * s,
        boxShadow: "0 60px 120px -30px rgba(0,0,0,0.75), 0 0 0 1px rgba(255,255,255,0.06)",
        fontFamily: font,
        boxSizing: "border-box",
        ...style,
      }}
    >
      <div style={{ width: "100%", height: "100%", borderRadius: 56 * s, background: theme.colors.bg, overflow: "hidden", position: "relative" }}>
        {/* Durum çubuğu */}
        <div style={{ display: "flex", justifyContent: "space-between", padding: `${20 * s}px ${34 * s}px 0`, color: theme.colors.text90, fontSize: 17 * s, fontWeight: 600 }}>
          <span>9:41</span>
          <div style={{ display: "flex", gap: 6 * s, alignItems: "center" }}>
            {[0.4, 0.65, 0.85, 1].map((k, i) => (
              <div key={i} style={{ width: 4 * s, height: 12 * s * k, borderRadius: 2 * s, background: theme.colors.text90, alignSelf: "flex-end" }} />
            ))}
            <div style={{ marginLeft: 8 * s, width: 26 * s, height: 12 * s, borderRadius: 4 * s, border: `${1.5 * s}px solid ${theme.colors.text58}`, padding: 1.5 * s }}>
              <div style={{ width: "70%", height: "100%", background: theme.colors.text90, borderRadius: 2 * s }} />
            </div>
          </div>
        </div>

        {/* Üst çubuk */}
        <div style={{ display: "flex", justifyContent: "space-between", alignItems: "center", padding: `${16 * s}px ${PAD * s}px 0` }}>
          <div style={{ display: "flex", alignItems: "center", gap: 8 * s, padding: `${8 * s}px ${14 * s}px`, borderRadius: 14 * s, background: theme.colors.amberTint, border: `1px solid ${theme.colors.primary}55` }}>
            <AppIcon size={20 * s} style={{ boxShadow: "none" }} />
            <span style={{ color: theme.colors.gold, fontSize: 19 * s, fontWeight: 700 }}>sandık</span>
          </div>
          <div style={{ display: "flex", gap: 10 * s }}>
            {[0, 1, 2].map((i) => (
              <div key={i} style={{ width: 40 * s, height: 40 * s, borderRadius: 12 * s, background: theme.colors.surface1 }} />
            ))}
          </div>
        </div>

        <PiyasaSeridiMock s={s} offset={serit} />
        <KartPenceresi s={s} dx={dx} toplamBen={toplam} />
        <div style={{ margin: `${12 * s}px ${PAD * s}px 0` }}>
          <BugunKartiMock s={s} p={bugunP} etiket={bugunEtiket} kisisel={bugunKisisel} gun={bugunGun} />
        </div>

        {/* Varlık satırları — Bugün kartının altı boş kalıyordu (kare 130);
            liste sekme çubuğunun arkasına doğal biçimde devam eder. */}
        <div style={{ margin: `${18 * s}px ${PAD * s}px 0` }}>
          <Eyebrow s={s} color={theme.colors.text58}>
            Varlıklar
          </Eyebrow>
          {[
            ["Çeyrek Altın", "20 adet · Altın", "₺216.554", "%37,9", theme.colors.gold],
            ["DLY", "32.000 lot · Fon", "₺199.520", "%45,0", theme.colors.fon],
            ["KCHOL", "620 lot · Hisse", "₺127.782", "%39,3", theme.colors.primary],
          ].map(([ad, alt, deger, pct, renk]) => (
            <div
              key={ad}
              style={{
                marginTop: 10 * s,
                padding: `${12 * s}px ${14 * s}px`,
                borderRadius: 16 * s,
                background: theme.colors.surface1,
                border: `1px solid ${theme.colors.divider}`,
                display: "flex",
                alignItems: "center",
                gap: 12 * s,
              }}
            >
              <div style={{ width: 32 * s, height: 32 * s, borderRadius: 10 * s, background: `${renk}33` }} />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 16 * s, fontWeight: 700, color: theme.colors.text }}>{ad}</div>
                <div style={{ fontSize: 12 * s, fontWeight: 500, color: theme.colors.text58 }}>{alt}</div>
              </div>
              <div style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
                <div style={{ fontSize: 16 * s, fontWeight: 700, color: theme.colors.text }}>{deger}</div>
                <div style={{ display: "flex", justifyContent: "flex-end", alignItems: "center", gap: 5 * s, fontSize: 12 * s, fontWeight: 700, color: theme.colors.gain }}>
                  <Tri size={7 * s} color={theme.colors.gain} />
                  {pct}
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Alt sekme çubuğu */}
        <div style={{ position: "absolute", left: 0, right: 0, bottom: 0, height: 96 * s, background: theme.colors.surface1, borderTop: `1px solid ${theme.colors.divider}`, display: "flex", justifyContent: "space-around", alignItems: "center", paddingBottom: 14 * s }}>
          {["Ana", "Portföy", "", "Performans", "Profil"].map((t, i) =>
            i === 2 ? (
              <div key={i} style={{ width: 60 * s, height: 60 * s, borderRadius: 30 * s, background: theme.colors.primary, display: "flex", alignItems: "center", justifyContent: "center", color: theme.colors.onAmber, fontSize: 36 * s, fontWeight: 500, lineHeight: 1, marginTop: -18 * s }}>
                +
              </div>
            ) : (
              <div key={i} style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: 6 * s, color: i === 0 ? theme.colors.primary : theme.colors.text58, fontSize: 12 * s, fontWeight: 600 }}>
                <div style={{ width: 22 * s, height: 22 * s, borderRadius: 6 * s, background: i === 0 ? theme.colors.primary : theme.colors.text58, opacity: i === 0 ? 1 : 0.6 }} />
                {t}
              </div>
            ),
          )}
        </div>
      </div>
    </div>
  );
};

/** Bildirim kartı (kilit ekranı üslubu). */
export const BildirimKarti: React.FC<{ baslik: string; govde: string; saat: string; size?: number; style?: React.CSSProperties }> = ({
  baslik,
  govde,
  saat,
  size = 1,
  style,
}) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: 18 * size,
      padding: `${18 * size}px ${22 * size}px`,
      borderRadius: 22 * size,
      background: "rgba(255,255,255,0.08)",
      border: "1px solid rgba(255,255,255,0.12)",
      backdropFilter: "blur(20px)",
      fontFamily: font,
      width: 620 * size,
      boxSizing: "border-box",
      ...style,
    }}
  >
    <AppIcon size={44 * size} style={{ boxShadow: "none", flex: "none" }} />
    <div style={{ flex: 1, minWidth: 0 }}>
      <div style={{ display: "flex", justifyContent: "space-between", alignItems: "baseline" }}>
        <span style={{ fontSize: 20 * size, fontWeight: 700, color: theme.colors.text, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{baslik}</span>
        <span style={{ fontSize: 14 * size, color: theme.colors.text58, marginLeft: 12 * size, flex: "none" }}>{saat}</span>
      </div>
      <div style={{ fontSize: 17 * size, fontWeight: 500, color: theme.colors.text90, marginTop: 3 * size, whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" }}>{govde}</div>
    </div>
  </div>
);
