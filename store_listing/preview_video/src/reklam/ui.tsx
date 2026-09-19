// Yeniden çizilmiş uygulama arayüzü.
//
// Neden ekran kaydı değil: reklam görselinde (a) "Test" ortak adı, kayıt
// rozeti gibi gerçek hesap izleri olmamalı, (b) sayılar DEMO_PORTFOY.md ile
// tutarlı olmalı, (c) sayaç/çubuk gibi öğeler kendi zamanlamamızla
// oynamalı. Launch videosu (brag-output-2026-09-17-launch) aynı yolu seçti
// ve kullanıcı üslubu beğendi. Mağaza ÖNİZLEMESİ için bu yol geçersiz
// (Apple 2.3.4 yalnızca ekran kaydı) — bu bileşenler yalnızca reklamda.
import React from "react";
import { Img, interpolate, staticFile } from "remotion";
import { DEMO, theme, tr } from "./theme";

const font = theme.fonts.display;

/** Uygulama ikonu (assets/images/sandik_icon.png). */
export const AppIcon: React.FC<{ size: number; style?: React.CSSProperties }> = ({
  size,
  style,
}) => (
  <Img
    src={staticFile("brand/sandik_icon.png")}
    style={{
      width: size,
      height: size,
      borderRadius: size * 0.22,
      boxShadow: `0 ${size * 0.08}px ${size * 0.3}px -${size * 0.06}px rgba(0,0,0,0.7)`,
      ...style,
    }}
  />
);

/** İkon + "sandık" yazısı. Amber parlamayı çağıran verir (kare başına tek). */
export const Wordmark: React.FC<{
  size?: number;
  glow?: boolean;
  style?: React.CSSProperties;
}> = ({ size = 120, glow = false, style }) => (
  <div style={{ display: "flex", alignItems: "center", gap: size * 0.22, ...style }}>
    <AppIcon size={size * 0.9} />
    <span
      style={{
        fontFamily: font,
        fontSize: size,
        fontWeight: 800,
        letterSpacing: "-0.04em",
        lineHeight: 1,
        color: theme.colors.gold,
        textShadow: glow ? `0 0 ${size * 0.5}px ${theme.colors.glow}` : "none",
      }}
    >
      sandık
    </span>
  </div>
);

/**
 * Enflasyon rozeti — uygulamanın en ayırt edici satırı, reklamların imzası.
 * `p` 0→1 giriş ilerlemesi (opacity + scale birlikte).
 */
export const Rozet: React.FC<{ p?: number; size?: number; style?: React.CSSProperties }> = ({
  p = 1,
  size = 1,
  style,
}) => (
  <div
    style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 14 * size,
      padding: `${16 * size}px ${26 * size}px`,
      borderRadius: 999,
      background: theme.colors.gainTint,
      border: `${Math.max(1.5, 2 * size)}px solid ${theme.colors.gain}66`,
      opacity: p,
      transform: `scale(${interpolate(p, [0, 1], [0.88, 1])})`,
      fontFamily: font,
      whiteSpace: "nowrap",
      ...style,
    }}
  >
    <Tri size={22 * size} color={theme.colors.gain} />
    <span style={{ color: theme.colors.gain, fontSize: 34 * size, fontWeight: 800 }}>
      {tr(DEMO.fark)} puan
    </span>
    <span style={{ color: theme.colors.text90, fontSize: 30 * size, fontWeight: 500 }}>
      enflasyonun önündesin
    </span>
  </div>
);

/** Yukarı/aşağı üçgen — emoji değil, CSS. */
export const Tri: React.FC<{ size: number; color: string; down?: boolean }> = ({
  size,
  color,
  down,
}) => (
  <div
    style={{
      width: 0,
      height: 0,
      borderLeft: `${size * 0.55}px solid transparent`,
      borderRight: `${size * 0.55}px solid transparent`,
      ...(down
        ? { borderTop: `${size}px solid ${color}` }
        : { borderBottom: `${size}px solid ${color}` }),
    }}
  />
);

/** Küçük başlık etiketi (uygulamadaki "TOPLAM NET VARLIK" kasası). */
const Eyebrow: React.FC<{ children: React.ReactNode; color?: string; size: number }> = ({
  children,
  color = theme.colors.gain,
  size,
}) => (
  <div
    style={{
      fontFamily: font,
      fontSize: 13 * size,
      fontWeight: 700,
      letterSpacing: "0.12em",
      color,
      textTransform: "uppercase",
    }}
  >
    {children}
  </div>
);

/**
 * Ana ekran mockup'ı. `w` genişlik (px), yükseklik oranı iPhone (19.5:9).
 * `bars` 0→1: dağılım çubuklarının doluluk ilerlemesi.
 * `rozetP` 0→1: rozetin giriş ilerlemesi.
 */
export const PhoneHome: React.FC<{
  w: number;
  bars?: number;
  rozetP?: number;
  style?: React.CSSProperties;
}> = ({ w, bars = 1, rozetP = 1, style }) => {
  const s = w / 430; // 430 = tasarım genişliği
  const h = w * (19.5 / 9);
  const pad = 22 * s;

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
        ...style,
      }}
    >
      <div
        style={{
          width: "100%",
          height: "100%",
          borderRadius: 56 * s,
          background: theme.colors.bg,
          overflow: "hidden",
          position: "relative",
        }}
      >
        {/* Durum çubuğu */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            padding: `${20 * s}px ${34 * s}px 0`,
            color: theme.colors.text90,
            fontSize: 17 * s,
            fontWeight: 600,
          }}
        >
          <span>9:41</span>
          <div style={{ display: "flex", gap: 6 * s, alignItems: "center" }}>
            {[0.4, 0.65, 0.85, 1].map((k, i) => (
              <div
                key={i}
                style={{
                  width: 4 * s,
                  height: 12 * s * k,
                  borderRadius: 2 * s,
                  background: theme.colors.text90,
                  alignSelf: "flex-end",
                }}
              />
            ))}
            <div
              style={{
                marginLeft: 8 * s,
                width: 26 * s,
                height: 12 * s,
                borderRadius: 4 * s,
                border: `${1.5 * s}px solid ${theme.colors.text58}`,
                padding: 1.5 * s,
              }}
            >
              <div style={{ width: "70%", height: "100%", background: theme.colors.text90, borderRadius: 2 * s }} />
            </div>
          </div>
        </div>

        {/* Üst çubuk: marka pili + ikonlar */}
        <div
          style={{
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            padding: `${18 * s}px ${pad}px 0`,
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              gap: 8 * s,
              padding: `${8 * s}px ${14 * s}px`,
              borderRadius: 14 * s,
              background: theme.colors.amberTint,
              border: `1px solid ${theme.colors.primary}55`,
            }}
          >
            <AppIcon size={20 * s} style={{ boxShadow: "none" }} />
            <span style={{ color: theme.colors.gold, fontSize: 19 * s, fontWeight: 700 }}>
              sandık
            </span>
          </div>
          <div style={{ display: "flex", gap: 10 * s }}>
            {[0, 1, 2].map((i) => (
              <div
                key={i}
                style={{
                  width: 40 * s,
                  height: 40 * s,
                  borderRadius: 12 * s,
                  background: theme.colors.surface1,
                }}
              />
            ))}
          </div>
        </div>

        {/* Hero kart */}
        <div
          style={{
            margin: `${18 * s}px ${pad} 0`,
            padding: `${22 * s}px ${26 * s}px`,
            borderRadius: 22 * s,
            background: theme.colors.surface1,
            border: `1px solid ${theme.colors.divider}`,
          }}
        >
          <Eyebrow size={s}>Toplam net varlık</Eyebrow>
          <div
            style={{
              marginTop: 8 * s,
              fontSize: 54 * s,
              fontWeight: 800,
              letterSpacing: "-0.03em",
              color: theme.colors.gold,
              lineHeight: 1.05,
              fontVariantNumeric: "tabular-nums",
            }}
          >
            {DEMO.toplam}
          </div>
          <div
            style={{
              marginTop: 10 * s,
              display: "flex",
              alignItems: "center",
              gap: 10 * s,
              color: theme.colors.gain,
              fontSize: 22 * s,
              fontWeight: 700,
            }}
          >
            <Tri size={11 * s} color={theme.colors.gain} />
            <span>{DEMO.kz}</span>
            <span>%{tr(DEMO.pct)}</span>
          </div>
        </div>

        {/* Rozet kartı */}
        <div
          style={{
            margin: `${14 * s}px ${pad} 0`,
            padding: `${18 * s}px ${22 * s}px`,
            borderRadius: 20 * s,
            background: theme.colors.gainTint,
            border: `1px solid ${theme.colors.gain}55`,
            opacity: rozetP,
            transform: `translateY(${interpolate(rozetP, [0, 1], [14, 0])}px)`,
          }}
        >
          {/* Tek satır — uygulamada da tek satırdır; 24/21 px'te 600 px'lik
              mockup'ta ikinci satıra taşıyordu (kare 200). */}
          <div style={{ display: "flex", alignItems: "center", gap: 9 * s, whiteSpace: "nowrap" }}>
            <Tri size={12 * s} color={theme.colors.gain} />
            <span style={{ color: theme.colors.gain, fontSize: 22 * s, fontWeight: 800 }}>
              {tr(DEMO.fark)} puan
            </span>
            <span style={{ color: theme.colors.text90, fontSize: 19 * s, fontWeight: 500 }}>
              enflasyonun önündesin
            </span>
          </div>
          <div
            style={{
              marginTop: 8 * s,
              color: theme.colors.text58,
              fontSize: 15 * s,
              fontWeight: 500,
            }}
          >
            Senin %{tr(DEMO.pct)} · TÜFE %{tr(DEMO.tufe)} · {DEMO.aralik}
          </div>
        </div>

        {/* Dağılım */}
        <div style={{ margin: `${22 * s}px ${pad} 0` }}>
          <Eyebrow size={s} color={theme.colors.text58}>
            Varlık dağılımı
          </Eyebrow>
          {DEMO.dagilim.map((d, i) => {
            const renk = theme.colors[d.renk as keyof typeof theme.colors] as string;
            const fill = interpolate(bars, [i * 0.12, i * 0.12 + 0.6], [0, d.pct], {
              extrapolateLeft: "clamp",
              extrapolateRight: "clamp",
            });
            return (
              <div
                key={d.ad}
                style={{
                  display: "flex",
                  alignItems: "center",
                  gap: 12 * s,
                  marginTop: 14 * s,
                  fontSize: 19 * s,
                  fontWeight: 600,
                  color: theme.colors.text90,
                }}
              >
                <div style={{ width: 10 * s, height: 10 * s, borderRadius: 5 * s, background: renk }} />
                <span style={{ width: 62 * s }}>{d.ad}</span>
                <div
                  style={{
                    flex: 1,
                    height: 8 * s,
                    borderRadius: 4 * s,
                    background: theme.colors.surface2,
                    overflow: "hidden",
                  }}
                >
                  <div
                    style={{
                      width: `${(fill / 50) * 100}%`,
                      height: "100%",
                      borderRadius: 4 * s,
                      background: renk,
                    }}
                  />
                </div>
                <span
                  style={{
                    width: 62 * s,
                    textAlign: "right",
                    fontVariantNumeric: "tabular-nums",
                    color: theme.colors.text58,
                  }}
                >
                  %{tr(fill, 1)}
                </span>
              </div>
            );
          })}
        </div>

        {/* Varlık satırları — dağılımın altı boş kalıyordu (kare 200) */}
        <div style={{ margin: `${32 * s}px ${pad} 0` }}>
          <Eyebrow size={s} color={theme.colors.text58}>
            Varlıklar
          </Eyebrow>
          {[
            ["Çeyrek Altın", "20 adet · Altın", "₺216.554", "%37,9", "gold"],
            ["DLY", "32.000 lot · Fon", "₺199.520", "%45,0", "fon"],
          ].map(([ad, alt, deger, pct, renk]) => (
            <div
              key={ad}
              style={{
                marginTop: 12 * s,
                padding: `${14 * s}px ${16 * s}px`,
                borderRadius: 16 * s,
                background: theme.colors.surface1,
                border: `1px solid ${theme.colors.divider}`,
                display: "flex",
                alignItems: "center",
                gap: 12 * s,
              }}
            >
              <div
                style={{
                  width: 34 * s,
                  height: 34 * s,
                  borderRadius: 10 * s,
                  background: `${theme.colors[renk as keyof typeof theme.colors] as string}33`,
                }}
              />
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 18 * s, fontWeight: 700, color: theme.colors.text }}>{ad}</div>
                <div style={{ fontSize: 13 * s, fontWeight: 500, color: theme.colors.text58 }}>{alt}</div>
              </div>
              <div style={{ textAlign: "right", fontVariantNumeric: "tabular-nums" }}>
                <div style={{ fontSize: 18 * s, fontWeight: 700, color: theme.colors.text }}>{deger}</div>
                <div
                  style={{
                    display: "flex",
                    justifyContent: "flex-end",
                    alignItems: "center",
                    gap: 5 * s,
                    fontSize: 13 * s,
                    fontWeight: 700,
                    color: theme.colors.gain,
                  }}
                >
                  <Tri size={8 * s} color={theme.colors.gain} />
                  {pct}
                </div>
              </div>
            </div>
          ))}
        </div>

        {/* Alt sekme çubuğu */}
        <div
          style={{
            position: "absolute",
            left: 0,
            right: 0,
            bottom: 0,
            height: 96 * s,
            background: theme.colors.surface1,
            borderTop: `1px solid ${theme.colors.divider}`,
            display: "flex",
            justifyContent: "space-around",
            alignItems: "center",
            paddingBottom: 14 * s,
          }}
        >
          {["Ana", "Portföy", "", "Performans", "Profil"].map((t, i) =>
            i === 2 ? (
              <div
                key={i}
                style={{
                  width: 60 * s,
                  height: 60 * s,
                  borderRadius: 30 * s,
                  background: theme.colors.primary,
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  color: theme.colors.onAmber,
                  fontSize: 36 * s,
                  fontWeight: 500,
                  lineHeight: 1,
                  marginTop: -18 * s,
                }}
              >
                +
              </div>
            ) : (
              <div
                key={i}
                style={{
                  display: "flex",
                  flexDirection: "column",
                  alignItems: "center",
                  gap: 6 * s,
                  color: i === 0 ? theme.colors.primary : theme.colors.text58,
                  fontSize: 12 * s,
                  fontWeight: 600,
                }}
              >
                <div
                  style={{
                    width: 22 * s,
                    height: 22 * s,
                    borderRadius: 6 * s,
                    background: i === 0 ? theme.colors.primary : theme.colors.text58,
                    opacity: i === 0 ? 1 : 0.6,
                  }}
                />
                {t}
              </div>
            ),
          )}
        </div>
      </div>
    </div>
  );
};

/** Varlık türü çipi — glif CSS ile, emoji yok. */
export const TurCip: React.FC<{
  ad: string;
  renk: string;
  size?: number;
  style?: React.CSSProperties;
}> = ({ ad, renk, size = 1, style }) => (
  <div
    style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 16 * size,
      padding: `${20 * size}px ${30 * size}px ${20 * size}px ${22 * size}px`,
      borderRadius: 26 * size,
      background: theme.colors.surface1,
      border: `1.5px solid ${theme.colors.divider}`,
      fontFamily: font,
      fontSize: 40 * size,
      fontWeight: 700,
      color: theme.colors.text,
      whiteSpace: "nowrap",
      ...style,
    }}
  >
    <div
      style={{
        width: 44 * size,
        height: 44 * size,
        borderRadius: 14 * size,
        background: `${renk}22`,
        border: `1.5px solid ${renk}66`,
        display: "flex",
        alignItems: "center",
        justifyContent: "center",
      }}
    >
      <div style={{ width: 16 * size, height: 16 * size, borderRadius: 8 * size, background: renk }} />
    </div>
    {ad}
  </div>
);

/** Mağaza satırı — hero (amber) dolgu. Kare başına TEK amber parlama. */
export const StoreLine: React.FC<{ size?: number; glow?: boolean; style?: React.CSSProperties }> = ({
  size = 1,
  glow = true,
  style,
}) => (
  <div
    style={{
      display: "inline-flex",
      alignItems: "center",
      gap: 18 * size,
      padding: `${22 * size}px ${44 * size}px`,
      borderRadius: 999,
      background: theme.colors.primary,
      color: theme.colors.onAmber,
      fontFamily: font,
      fontSize: 38 * size,
      fontWeight: 800,
      letterSpacing: "-0.01em",
      boxShadow: glow ? `0 0 60px ${theme.colors.glow}, 0 0 120px rgba(245,166,35,0.2)` : "none",
      whiteSpace: "nowrap",
      ...style,
    }}
  >
    Şimdi App Store'da · Ücretsiz
  </div>
);
