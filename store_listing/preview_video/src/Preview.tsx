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
 * `from`/`dur` — kurgudaki yeri (kare, 30 fps).
 * `startFrom`  — kaydın hangi SANİYESİNDEN alınacağı × F. Değerler
 *                public/shots/kayit.mov taranarak ölçüldü (aşağıda).
 * `shot`       — kayıt yokken gösterilecek yedek ekran görüntüsü.
 * `speed`      — kayıt oynatma hızı; ölü beklemeyi toparlar.
 *
 * ## Kaydın haritası (ölçüldü, 2026-09-16)
 *
 *   0–7 sn    Ana ekran: toplam varlık + ENFLASYON ROZETİ
 *   8–12 sn   Ana ekranda scroll, dağılım barları, hareketler
 *  13–19 sn   Portföy: donut + varlık listesi
 *  20–28 sn   Performans/Özet: sağlık kartları, "Dengeli"
 *  29–33 sn   Performans/Grafik: 1Y çizgi + CROSSHAIR gezdirme
 *  34–37 sn   Performans/Özet: "NEREDEN GELDİ" çubukları
 *  38–45 sn   Reel getiri kartı: nominal %63 · TÜFE %31,51 · +31,5 puan
 *  56–60 sn   Varlık detayı (KCHOL): maliyet kırılımı
 *  64–72 sn   Donut'ta DİLİM SEÇİMİ: Fon → Altın → Döviz
 *  80–88 sn   Birlikte sekmesi: ortak toplam
 *  92–94 sn   Ana ekrana dönüş
 *
 * ## Sıralama gerekçesi
 *
 * CEKIM_SENARYOSU.md §1: en güçlü iddia önce. sandık'ın rakiplerde
 * olmayan şeyi TÜFE'ye göre reel getiri — video onunla açılıp onunla
 * kapanıyor. "Nereden geldi" çubukları ikinci sırada çünkü iddianın
 * KANITI orası: katkı ile piyasa hareketini ayırıyor.
 *
 * Kayıtta güçlü ama videoya ALINMAYANLAR ve nedenleri:
 *   - Portföy sağlığı / "Dengeli"  → iyi kart ama 24 sn'ye sığmıyor;
 *     mesaj enflasyon ekseninden sapıyor
 *   - Birlikte sekmesi             → "Test" yazan gerçek hesap adı var
 *   - Varlık detayı (KCHOL)        → "Koç Holding" gerçek veri (2.3.9)
 */
const SCENES = [
  {
    key: "rozet",
    from: 0,
    // 3,4 sn: kayıtta scroll 3,5 sn'de başlıyor. Daha uzun tutulursa sahne
    // kaydırmayı yakalıyor ve açılış karesi kayıyor.
    dur: 3.4 * F,
    shot: "shots/01_ana.png",
    // 0,9 sn: TOPLAM VARLIK kartı + rozet aynı karede duruyor.
    //
    // 1,5 sn denendi ve kadraj kaydı: kullanıcı ~3,5 sn'de scroll etmeye
    // başlıyor, toplam kartı yukarı çıkıp kesiliyor. Sahne 4,5 sn sürdüğü
    // için başlangıç geç alınırsa videonun EN KRİTİK karesi (toplam + rozet
    // birlikte) hiç görünmüyor. 0,9 sn'de kayıt çubuğu da oturmuş oluyor.
    startFrom: Math.round(0.9 * F),
    text: "Enflasyonu geçtin mi?",
    highlight: "Enflasyonu",
    zoomTo: 1.05,
    speed: 1,
    // Ana ekranda ortak seçici "Birlikte / Ben / Test" — "Test" gerçek
    // hesap adı. Kurgusal adla örtülür (2.3.9).
    //
    // 0,647: 886×1920 render'ında segmentin ÜST kenarı (merkez y≈1287,
    // yükseklik ≈86). İki kez still render'da ölçülerek düzeltildi —
    // 0,695 boşluğa, 0,517 ortak kartına düşüyordu.
    maskTop: 0.647,
  },
  {
    key: "kanit",
    from: 3.4 * F,
    // 3,2 sn: kayıt bu sahnede scroll ediyor. Uzun tutulursa kadraj aşağı
    // inip "Portföyünün %35'i Koç Holding içinde" satırını yakalıyor
    // (gerçek veri, 2.3.9). Kart okunacak kadar duruyor, sonra kesiliyor.
    dur: 3.2 * F,
    shot: "shots/03_performans.png",
    // 38,9 sn: reel getiri kartı ekranın ORTASINDA — %23,95 reel, nominal
    // %63,00, TÜFE %31,51, +31,5 puan aynı karede.
    //
    // 38,6 denendi ve kadraj aşağı kayıp "Portföyünün %35'i Koç Holding
    // içinde" satırını aldı — gerçek veri (2.3.9). Maskelemek yerine
    // kadraj kaydırıldı: metin satırının ortasına yama koymak göze
    // batıyordu, kartın kendisi zaten daha yukarıda duruyor.
    startFrom: Math.round(38.2 * F),
    text: "Nominal değil, reel getiri",
    highlight: "reel",
    zoomTo: 1.04,
    speed: 1,
  },
  {
    key: "nereden",
    from: 6.6 * F,
    dur: 4.6 * F,
    shot: "shots/03_performans.png",
    // 34 sn: "Nereden geldi" — Dönem başı / Katkın / Piyasa / Şimdi.
    // Kurgunun en işlevsel karesi: katkı ile piyasayı AYIRIYOR.
    startFrom: Math.round(34.2 * F),
    text: "Katkın mı, piyasa mı?",
    highlight: "piyasa",
    zoomTo: 1.05,
    speed: 1,
  },
  {
    key: "grafik",
    from: 11.2 * F,
    dur: 4.3 * F,
    shot: "shots/03_performans.png",
    // 29,5 sn: 1Y grafiği + crosshair gezdirme. Etkileşimi gösteren tek yer.
    startFrom: Math.round(29.5 * F),
    text: "Zaman içinde ne kazandın",
    highlight: "kazandın",
    zoomTo: 1.03,
    speed: 1,
    // Grafik sahnesinde seçici ekranın ÜSTÜNDE (merkez y≈312, yükseklik
    // ≈86) — ana ekrandakinden çok daha yukarıda.
    maskTop: 0.14,
  },
  {
    key: "dagilim",
    from: 15.5 * F,
    dur: 4.2 * F,
    shot: "shots/05_dagilim.jpeg",
    // 64,5 sn: donut'ta dilim seçimi — Fon → Altın geçişi canlı.
    startFrom: Math.round(64.5 * F),
    text: "Ağırlığın nerede",
    highlight: "nerede",
    zoomTo: 1.04,
    speed: 1.15,
  },
] as const;

const OUTRO_FROM = 19.7 * F;

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
              <Capture
                shot={s.shot}
                startFrom={s.startFrom}
                zoomTo={s.zoomTo}
                speed={"speed" in s ? (s as { speed: number }).speed : 1}
              />
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
