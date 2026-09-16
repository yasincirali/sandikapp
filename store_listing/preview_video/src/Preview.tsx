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
import { StatusBarPatch } from "./components/StatusBarPatch";

const F = SPEC.fps;

/**
 * ## İKİ KAYIT
 *
 * `kayit.mov`  (94 sn) — birinci çekim. Ana ekran + Performans/Özet
 *                        yüzeyleri burada: TOPLAM VARLIK, enflasyon rozeti,
 *                        reel getiri kartı, "Nereden geldi" çubukları.
 * `kayit2.MP4` (77 sn) — ikinci çekim. İŞLEVSELLİK burada: varlık ekleme
 *                        formu, alarm kurma, takip listesi ve endeks
 *                        karşılaştırması (Portföyüm vs XU100 vs THYAO).
 *
 * Neden ikisi birden: ilk kurgu tek kayıttan yapıldı ve 20 saniyenin 13'ü
 * tek ekranda (Performans) geçiyordu. İzleyici "bu uygulama ne yapıyor"
 * sorusunun cevabını alamıyordu — ekleme, alarm, takip hiç görünmüyordu.
 * İkinci çekim tam o eksikleri kapatıyor ama ana ekranla başlamıyor, yani
 * enflasyon iddiası onda yok.
 *
 * Bu yüzden iddia birinci kayıttan, işlevsellik ikinciden alınıyor.
 * Apple 2.3.4 buna izin verir: ikisi de AYNI uygulamanın ekran kaydı.
 */
const SRC2 = "shots/kayit2.MP4";

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
    dur: 3.2 * F,
    shot: "shots/01_ana.png",
    // Kayıt 1 · 0,9 sn: TOPLAM VARLIK + enflasyon rozeti aynı karede.
    startFrom: Math.round(0.9 * F),
    text: "Enflasyonu geçtin mi?",
    highlight: "Enflasyonu",
    zoomTo: 1.05,
    speed: 1,
    maskTop: 0.647,
  },
  {
    key: "kanit",
    from: 3.2 * F,
    dur: 3.0 * F,
    shot: "shots/03_performans.png",
    // Kayıt 1 · 38,2 sn: reel %23,95 · nominal %63 · TÜFE %31,51 · +31,5 puan
    startFrom: Math.round(38.2 * F),
    text: "Nominal değil, reel getiri",
    highlight: "reel",
    zoomTo: 1.04,
    speed: 1,
  },
  {
    key: "ekle",
    from: 6.2 * F,
    dur: 3.4 * F,
    shot: "shots/02_portfoy.png",
    // Kayıt 2 · 18,6 sn: fon arayıp ekleme formu — miktar, otomatik fiyat.
    startFrom: Math.round(18.6 * F),
    src: SRC2,
    text: "Ekle, gerisini o halleder",
    highlight: "gerisini",
    zoomTo: 1.03,
    // Form dolduruluyor; hafif hızlandırma tuş tuş beklemeyi toparlıyor.
    speed: 1.25,
  },
  {
    key: "alarm",
    from: 9.6 * F,
    dur: 3.2 * F,
    shot: "shots/04_varlik.png",
    // Kayıt 2 · 34,3 sn: "KCHOL için alarm kuruldu: ₺216,83 üstüne çıkınca"
    // Onay şeridi kareye giriyor — kurulan alarmın SONUCU görünüyor.
    startFrom: Math.round(34.3 * F),
    src: SRC2,
    text: "Hedefe gelince haber ver",
    highlight: "haber",
    zoomTo: 1.04,
    speed: 1,
  },
  {
    key: "takip",
    from: 12.8 * F,
    dur: 3.6 * F,
    shot: "shots/03_performans.png",
    // Kayıt 2 · 67,8 sn: dört çizgi ve DÖRT LEJANT birlikte okunuyor —
    // Portföyüm −%0,9 · ALTIN_GRAM −%2,2 · XU100 −%7,1 · THYAO −%9,3.
    //
    // Crosshair'li an (65,2) denendi ve BIRAKILDI: baloncuk kayıtta ancak
    // ~1 saniye açık kalıyor, 3,6 saniyelik sahnenin çoğunda yok. Üstelik
    // o kadrajda ortak seçici görünüyor ve maske gerekiyordu. 67,8'de
    // seçici kaydırılıp kaybolmuş, ekran duruyor ve karşılaştırma
    // lejanttan zaten okunuyor — maskeye de gerek kalmıyor.
    startFrom: Math.round(67.8 * F),
    src: SRC2,
    text: "Endeksi geçiyor musun?",
    highlight: "Endeksi",
    zoomTo: 1.03,
    speed: 1,
  },
  {
    key: "dagilim",
    from: 16.4 * F,
    dur: 3.4 * F,
    shot: "shots/05_dagilim.jpeg",
    // Kayıt 1 · 64,5 sn: donut dilim seçimi — Fon → Altın geçişi canlı.
    startFrom: Math.round(64.5 * F),
    text: "Ağırlığın nerede",
    highlight: "nerede",
    zoomTo: 1.04,
    speed: 1.15,
  },
] as const;

const OUTRO_FROM = 19.8 * F;

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
                src={"src" in s ? (s as { src: string }).src : undefined}
              />
              {/* Kayıt göstergesi HER sahnede örtülür — iki kaydın ikisinde
                  de var (biri kırmızı rozet, biri kırmızı zeminli saat). */}
              <StatusBarPatch />
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
