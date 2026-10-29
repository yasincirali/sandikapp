// Seviye alarmları — gösterge (EMA/MA/Bollinger) ve çizgi (trend/ışın)
// alarmlarının ortak turu (0170, yasin 2026-10-29: "Gösterge ya da çizgiye
// değdiğinde push gelmesi yapılabilir mi?").
//
// `check-price-alerts` her turda (yarım saatlik iş + 5 dakikalık hızlı iş,
// 0168) yüzde alarmından sonra, fiyat alarmından ÖNCE bu turu try içinde
// koşar. Fiyat alarmının sorgusu, tetikleme kuralı ve sırası değişmez.
//
// ── Kural: taraf değişimi ───────────────────────────────────────────────────
// Her turda fiyatın seviyeye göre tarafı ('ust' / 'alt') hesaplanır ve
// satırdaki `son_taraf` ile karşılaştırılır:
//   · `son_taraf` null (ilk tur) → yalnız yazılır, ÇALMAZ. Kurulduğu anda
//     zaten öbür taraftaysa "kesti" demek uydurma olurdu.
//   · taraf değişti ve yön uyuyor → ÇALAR (tek atış: enabled=false).
//   · taraf değişti, yön uymuyor ('yukari' alarmda fiyat aşağı geçti) →
//     yeni taraf yazılır; sonraki yukarı geçiş çalar.
//   · fiyat seviyeye tam eşit → taraf değişmez (eşitlik geçiş değildir).
// Damga ve taraf yazımı KOŞULLU UPDATE'tir: okunan `son_taraf` hâlâ
// yerindeyse yazar. Çakışan iki tur ikisi de push göndermez; istemci
// arada çizgiyi taşıdıysa (tetikleyici `son_taraf`ı sıfırlar) eski doğruya
// göre verilmiş karar yazılmaz.
//
// ── Sessiz saatler (0057) ───────────────────────────────────────────────────
// Çalacak alarm sessiz saatteyse ATLANIR ve hiçbir şey yazılmaz: pencere
// bitince fiyat hâlâ yeni taraftaysa bir sonraki tur çalar (fiyat alarmıyla
// aynı davranış). Sessiz saatte geri döndüyse haber de yoktur.
//
// ── Uydurma sayı yok ────────────────────────────────────────────────────────
// Canlı fiyatı alınamayan, serisi yetmeyen (EMA200 < 200 kapanış) ya da
// bayat seriye sahip alarm DEĞERLENDİRİLMEZ ve satırına dokunulmaz.

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { fetchLivePrices } from './live_prices.ts';
import { fiyatMetni, kotasyonSimgesi } from './fiyat_metni.ts';
import { kartGorseli, KartAyari, KartVerisi, kartVerisiniHazirla } from './bildirim_karti.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  TokenRow,
  tokenSatirlariniOku,
} from './push_tokens.ts';
import { sessizKullanicilar } from './quiet_hours.ts';
import { appNotificationRow, recordAppNotification } from './app_notifications.ts';
import {
  BB_CARPAN,
  BB_PERIYOT,
  canliIleKapanislar,
  gostergeAdi,
  gostergeAlarmKapsamindaMi,
  gostergeGecerli,
  gostergeSeviyesi,
  gunlukSeriler,
} from './gosterge_alarmi.ts';
import { cizgiDegeri } from './cizim_alarmi.ts';

export const SEVIYE_KANAL = 'alert_channel';

export type Taraf = 'ust' | 'alt';
export type SeviyeYon = 'yukari' | 'asagi' | 'her_ikisi';

export function yonGecerli(y: string): y is SeviyeYon {
  return y === 'yukari' || y === 'asagi' || y === 'her_ikisi';
}

/// Fiyatın seviyeye göre tarafı; eşitse null (taraf değişmez).
export function tarafi(fiyat: number, seviye: number): Taraf | null {
  if (!Number.isFinite(fiyat) || !Number.isFinite(seviye)) return null;
  if (fiyat > seviye) return 'ust';
  if (fiyat < seviye) return 'alt';
  return null;
}

export type SeviyeKarari =
  | { tur: 'yok' }
  | { tur: 'yaz'; taraf: Taraf }
  | { tur: 'cal'; taraf: Taraf };

/// Bu turda ne yapılacak. Saf; dosya başındaki kuralın kendisi.
export function seviyeKarari(
  onceki: string | null | undefined,
  fiyat: number,
  seviye: number,
  yon: string,
): SeviyeKarari {
  if (!yonGecerli(yon)) return { tur: 'yok' };
  const simdi = tarafi(fiyat, seviye);
  if (simdi === null) {
    return { tur: 'yok' };
  }
  const eski = onceki === 'ust' || onceki === 'alt' ? onceki : null;
  if (eski === null) return { tur: 'yaz', taraf: simdi };
  if (eski === simdi) return { tur: 'yok' };
  const uyar = yon === 'her_ikisi' ||
    (yon === 'yukari' && simdi === 'ust') ||
    (yon === 'asagi' && simdi === 'alt');
  return uyar ? { tur: 'cal', taraf: simdi } : { tur: 'yaz', taraf: simdi };
}

// ── Metinler ────────────────────────────────────────────────────────────────

/// Göstergenin tamlayan hâli — Türkçe ek okunuşa göre (EMA iki yüz → 'ün').
const GOSTERGE_TAMLAYAN: Record<string, string> = {
  ema20: "EMA20'nin",
  ema50: "EMA50'nin",
  ema200: "EMA200'ün",
  sma20: "MA20'nin",
  bb_ust: 'Bollinger üst bandının',
  bb_alt: 'Bollinger alt bandının',
};

/// Gövdedeki tanım: hangi hesapla karşılaştırıldığını söyler.
export function gostergeTanimi(kod: string): string {
  if (kod === 'bb_ust' || kod === 'bb_alt') {
    return `${gostergeAdi(kod)} (${BB_PERIYOT}, ${BB_CARPAN}σ; günlük kapanışlarla)`;
  }
  return `${gostergeAdi(kod)} (günlük kapanışlarla)`;
}

/// "▲ THYAO EMA50'nin üstüne çıktı · ₺312,40". Yön ok + fiil birlikte
/// (yalnız renk/okla anlatılmaz); gövde seviyenin sayısını ve alarmın
/// kapandığını söyler.
export function gostergeMesaji(
  label: string,
  kod: string,
  taraf: Taraf,
  fiyat: number,
  seviye: number,
  simge: string | null,
): { title: string; body: string } {
  const ust = taraf === 'ust';
  const tamlayan = GOSTERGE_TAMLAYAN[kod] ?? gostergeAdi(kod);
  return {
    title: `${ust ? '▲' : '▼'} ${label} ${tamlayan} ${ust ? 'üstüne çıktı' : 'altına indi'}` +
      ` · ${fiyatMetni(fiyat, simge)}`,
    body: `${gostergeTanimi(kod)} ${fiyatMetni(seviye, simge)}. ` +
      'Tek seferlik alarmdı, kapatıldı. Yatırım tavsiyesi değildir.',
  };
}

export function cizimMesaji(
  label: string,
  taraf: Taraf,
  fiyat: number,
  seviye: number,
  simge: string | null,
): { title: string; body: string } {
  const ust = taraf === 'ust';
  return {
    title: `${ust ? '▲' : '▼'} ${label} çizdiğin çizginin ` +
      `${ust ? 'üstüne çıktı' : 'altına indi'} · ${fiyatMetni(fiyat, simge)}`,
    body: `Çizginin şu anki değeri ${fiyatMetni(seviye, simge)}. ` +
      'Tek seferlik alarmdı, kapatıldı. Yatırım tavsiyesi değildir.',
  };
}

export function seviyeKarti(
  label: string,
  taraf: Taraf,
  fiyat: number,
  altSatir: string,
  simge: string | null,
): KartVerisi | null {
  if (!Number.isFinite(fiyat)) return null;
  return kartVerisiniHazirla({
    e: label,
    b: fiyatMetni(fiyat, simge),
    y: taraf === 'ust' ? 'u' : 'd',
    a: altSatir,
  });
}

// ── Satırlar ────────────────────────────────────────────────────────────────

type OrtakSatir = {
  id: string;
  user_id: string;
  symbol: string;
  label: string;
  yon: string;
  son_taraf: string | null;
};

export type GostergeSatiri = OrtakSatir & { gosterge: string };

export type CizimSatiri = OrtakSatir & {
  t1: number | string;
  p1: number | string;
  t2: number | string;
  p2: number | string;
  uzanir: boolean;
};

type Tablo = 'gosterge_alarmlari' | 'cizim_alarmlari';

// deno-lint-ignore no-explicit-any
type Yazici = { from: (t: string) => any };

/// Koşullu UPDATE: satır hâlâ etkin ve `son_taraf` okunduğu gibiyse yazar.
/// YALNIZ bu çağrı yazdıysa `'yazildi'`.
export async function seviyeYaz(
  admin: Yazici,
  tablo: Tablo,
  id: string,
  oncekiTaraf: string | null,
  alanlar: Record<string, unknown>,
): Promise<'yazildi' | 'zaten' | 'hata'> {
  let q = admin.from(tablo).update(alanlar).eq('id', id).is('triggered_at', null);
  q = oncekiTaraf === null ? q.is('son_taraf', null) : q.eq('son_taraf', oncekiTaraf);
  const { data, error } = await q.select('id');
  if (error) {
    console.error(`[seviye-alarmi] ${tablo} yazilamadi:`, error.message);
    return 'hata';
  }
  return Array.isArray(data) && data.length > 0 ? 'yazildi' : 'zaten';
}

type Cal = {
  tablo: Tablo;
  satir: OrtakSatir;
  taraf: Taraf;
  fiyat: number;
  seviye: number;
  mesaj: { title: string; body: string };
  kart: KartVerisi | null;
  bildirimTuru: 'gosterge_alarm' | 'cizim_alarm';
  veri: Record<string, string>;
};

/// Bir turun tamamı. Hata fırlatabilir; çağıran yakalar ki fiyat alarmı
/// turu bundan etkilenmesin.
export async function seviyeAlarmTuruKos(
  admin: SupabaseClient,
  args: {
    dryRun: boolean;
    /// 0168 hızlı tur süzgeci: sembol bu turda değerlendirilir mi.
    turaGirer: (sembol: string) => boolean;
    fcm: { projectId: string; serviceAccountJson: string } | null;
    kart?: KartAyari | null;
    simdi?: Date;
    /// Test kapısı.
    fiyatlar?: (s: Set<string>) => Promise<Map<string, number>>;
    seriler?: (s: string[]) => Promise<Map<string, Array<[number, number]>>>;
  },
): Promise<Record<string, unknown>> {
  const simdi = args.simdi ?? new Date();
  const simdiMs = simdi.getTime();

  // ── 1) Etkin alarmlar ─────────────────────────────────────────────────────
  const [g, c] = await Promise.all([
    admin.from('gosterge_alarmlari')
      .select('id, user_id, symbol, label, gosterge, yon, son_taraf')
      .eq('enabled', true)
      .is('triggered_at', null),
    admin.from('cizim_alarmlari')
      .select('id, user_id, symbol, label, t1, p1, t2, p2, uzanir, yon, son_taraf')
      .eq('enabled', true)
      .is('triggered_at', null),
  ]);
  if (g.error) throw new Error(`Gosterge alarmlari alinamadi: ${g.error.message}`);
  if (c.error) throw new Error(`Cizim alarmlari alinamadi: ${c.error.message}`);

  const gostergeler = ((g.data ?? []) as GostergeSatiri[]).filter((a) =>
    gostergeGecerli(a.gosterge) && yonGecerli(a.yon) &&
    gostergeAlarmKapsamindaMi(a.symbol) && args.turaGirer(a.symbol)
  );
  const cizimler = ((c.data ?? []) as CizimSatiri[]).filter((a) =>
    yonGecerli(a.yon) && args.turaGirer(a.symbol)
  );
  if (gostergeler.length === 0 && cizimler.length === 0) {
    return { checked: 0, sent: 0 };
  }

  // ── 2) Canlı fiyat + günlük seriler (sembol başına tek çekim) ─────────────
  const semboller = new Set([...gostergeler, ...cizimler].map((a) => a.symbol));
  const fiyatlar = await (args.fiyatlar ?? ((s) => fetchLivePrices(s, admin)))(semboller);
  const seriSembolleri = [...new Set(gostergeler.map((a) => a.symbol))]
    .filter((s) => fiyatlar.has(s));
  const seriler = await (args.seriler ??
    ((s) => gunlukSeriler(admin, s, simdiMs)))(seriSembolleri);

  // Sembol başına kapanış dizisi ve gösterge başına seviye bir kez.
  const kapanisOnbellek = new Map<string, number[] | null>();
  const seviyeOnbellek = new Map<string, number | null>();
  const gostergeSeviye = (sembol: string, kod: string): number | null => {
    const anahtar = `${sembol}|${kod}`;
    if (seviyeOnbellek.has(anahtar)) return seviyeOnbellek.get(anahtar)!;
    if (!kapanisOnbellek.has(sembol)) {
      kapanisOnbellek.set(
        sembol,
        canliIleKapanislar(seriler.get(sembol) ?? [], fiyatlar.get(sembol), simdiMs),
      );
    }
    const k = kapanisOnbellek.get(sembol);
    const v = k ? gostergeSeviyesi(kod, k) : null;
    seviyeOnbellek.set(anahtar, v);
    return v;
  };

  // ── 3) Kararlar ───────────────────────────────────────────────────────────
  const calacak: Cal[] = [];
  const yazilacak: Array<{ tablo: Tablo; satir: OrtakSatir; taraf: Taraf; seviye: number }> = [];
  let degerlendirilen = 0;

  for (const a of gostergeler) {
    const fiyat = fiyatlar.get(a.symbol);
    const seviye = gostergeSeviye(a.symbol, a.gosterge);
    if (fiyat === undefined || seviye === null) continue;
    degerlendirilen += 1;
    const k = seviyeKarari(a.son_taraf, fiyat, seviye, a.yon);
    if (k.tur === 'yaz') yazilacak.push({ tablo: 'gosterge_alarmlari', satir: a, taraf: k.taraf, seviye });
    if (k.tur === 'cal') {
      const simge = kotasyonSimgesi(a.symbol);
      calacak.push({
        tablo: 'gosterge_alarmlari',
        satir: a,
        taraf: k.taraf,
        fiyat,
        seviye,
        mesaj: gostergeMesaji(a.label, a.gosterge, k.taraf, fiyat, seviye, simge),
        kart: seviyeKarti(a.label, k.taraf, fiyat,
          `${gostergeAdi(a.gosterge)} ${fiyatMetni(seviye, simge)}`, simge),
        bildirimTuru: 'gosterge_alarm',
        veri: { symbol: a.symbol, gosterge_alarm_id: a.id },
      });
    }
  }

  for (const a of cizimler) {
    const fiyat = fiyatlar.get(a.symbol);
    const seviye = cizgiDegeri({
      t1: Number(a.t1),
      p1: Number(a.p1),
      t2: Number(a.t2),
      p2: Number(a.p2),
      uzanir: a.uzanir === true,
    }, simdiMs);
    if (fiyat === undefined || seviye === null) continue;
    degerlendirilen += 1;
    const k = seviyeKarari(a.son_taraf, fiyat, seviye, a.yon);
    if (k.tur === 'yaz') yazilacak.push({ tablo: 'cizim_alarmlari', satir: a, taraf: k.taraf, seviye });
    if (k.tur === 'cal') {
      const simge = kotasyonSimgesi(a.symbol);
      calacak.push({
        tablo: 'cizim_alarmlari',
        satir: a,
        taraf: k.taraf,
        fiyat,
        seviye,
        mesaj: cizimMesaji(a.label, k.taraf, fiyat, seviye, simge),
        kart: seviyeKarti(a.label, k.taraf, fiyat,
          `Çizgi ${fiyatMetni(seviye, simge)}`, simge),
        bildirimTuru: 'cizim_alarm',
        veri: { symbol: a.symbol, cizim_alarm_id: a.id },
      });
    }
  }

  // Taraf yazımları (çalmayan değişimler). Kuru koşuda yazılmaz.
  let tarafYazildi = 0;
  if (!args.dryRun) {
    for (const y of yazilacak) {
      const r = await seviyeYaz(admin, y.tablo, y.satir.id, y.satir.son_taraf ?? null, {
        son_taraf: y.taraf,
        son_seviye: y.seviye,
        son_degerlendirme: simdi.toISOString(),
      });
      if (r === 'yazildi') tarafYazildi += 1;
    }
  }

  if (calacak.length === 0) {
    return {
      checked: degerlendirilen,
      priced: fiyatlar.size,
      sides_written: tarafYazildi,
      sent: 0,
    };
  }

  // ── 4) Token'lar ──────────────────────────────────────────────────────────
  const userIds = [...new Set(calacak.map((x) => x.satir.user_id))];
  const { data: tokenRows } = await tokenSatirlariniOku((s) =>
    admin.from('user_push_tokens').select(s).in('user_id', userIds)
  );
  const tokens = collapseTokens([
    ...(tokenRows ?? []),
    ...await ekHesapSatirlari(admin, userIds),
  ]);
  const tokensByUser = new Map<string, TokenRow[]>();
  for (const t of tokens) {
    const l = tokensByUser.get(t.user_id) ?? [];
    l.push(t);
    tokensByUser.set(t.user_id, l);
  }

  const sessiz = await sessizKullanicilar(admin, userIds, simdi);
  const accessToken = args.dryRun || args.fcm === null
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  let sent = 0;
  let skippedQuietHours = 0;
  const failures: string[] = [];

  for (const x of calacak) {
    if (sessiz.has(x.satir.user_id)) { skippedQuietHours += 1; continue; }
    if (args.dryRun || args.fcm === null) { sent += 1; continue; }

    // Damga ÖNCE, push SONRA (fiyat alarmıyla aynı sıra ve gerekçe).
    const damga = await seviyeYaz(admin, x.tablo, x.satir.id, x.satir.son_taraf ?? null, {
      enabled: false,
      triggered_at: simdi.toISOString(),
      son_taraf: x.taraf,
      son_seviye: x.seviye,
      son_degerlendirme: simdi.toISOString(),
      tetik_fiyat: x.fiyat,
      tetik_seviye: x.seviye,
    });
    if (damga === 'hata') { failures.push('damga: yazilamadi'); continue; }
    if (damga === 'zaten') continue;

    // Çan kaydı push'tan bağımsız (0066 gerekçesi).
    const kayit = await recordAppNotification(admin, appNotificationRow({
      userId: x.satir.user_id,
      type: x.bildirimTuru,
      title: x.mesaj.title,
      body: x.mesaj.body,
      data: x.veri,
    }));
    if (kayit) failures.push(kayit);

    for (const t of tokensByUser.get(x.satir.user_id) ?? []) {
      const r = await sendFcmNotification({
        accessToken,
        projectId: args.fcm.projectId,
        token: t.token,
        hesap: ekHesap(t),
        title: x.mesaj.title,
        body: x.mesaj.body,
        channelId: SEVIYE_KANAL,
        // Fiyat alarmıyla aynı acil uyarı (#252).
        priority: 'high',
        // `type: 'price_alert'` BİLEREK (0169 ile aynı): eski ve yeni build
        // dokununca sembolün varlık ekranını açar.
        data: { type: 'price_alert', ...x.veri },
        gorselUrl: await kartGorseli(args.kart, t, x.kart),
      });
      if (r.ok) {
        sent += 1;
      } else {
        console.error('[seviye-alarmi] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
        failures.push(`fcm: ${r.hataKodu}`);
        if (r.shouldDeleteToken) {
          await admin.from('user_push_tokens').delete().eq('token', t.token);
        }
      }
    }
  }

  return {
    checked: degerlendirilen,
    priced: fiyatlar.size,
    sides_written: tarafYazildi,
    triggered: calacak.length,
    sent,
    skipped_quiet_hours: skippedQuietHours,
    failures: failures.slice(0, 5),
  };
}
