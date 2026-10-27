// Yüzde alarmı — "Gram altın bugün %2 düşerse haber ver" (0169, Ar-Ge
// 2026-10-27 08:45 §1, yasin onayı).
//
// `check-price-alerts` her turda (yarım saatlik eski iş + 5 dakikalık hızlı
// iş, 0168) fiyat alarmlarından ÖNCE bu turu koşar. Fiyat alarmının kodu ve
// davranışı değişmez; bu dal ayrı tablodan (`yuzde_alarmlari`) okur, ayrı
// damga atar.
//
// ── Kaynak: sunucunun ZATEN tuttuğu günlük yüzde ───────────────────────────
// `widget-fiyat` ile aynı tablolar ve aynı hesap (`widget_fiyat.ts`):
//   · altın ayarları + TL döviz → `yurt_ici_kotasyon.degisim_pct`
//     (truncgil `Change`; uygulamanın gösterdiği günlük yüzde)
//   · kripto → `kripto_fiyat` (gün açılışına göre, İstanbul günü)
// Fon kapsam DIŞI: günde tek NAV, "bugün %2 düşerse" gün içi bir soru.
// Yeni sembol merdiveni kurulmaz (fiyat_kaynagi sözleşmesi madde 1);
// kapsam `widgetSembolTuru`'ndan türer. İstemci eşi
// `FiyatKaynagi.yuzdeAlarmiKapsamindaMi`.
//
// ── Uydurma sayı yok (madde 3) ──────────────────────────────────────────────
// Yüzde bilinmiyorsa, satır bayatsa ya da bugünün (TR) satırı değilse alarm
// DEĞERLENDİRİLMEZ. Widget'ın bayatlık eşiği (2 saat) burada fazla geniş:
// alarm "şimdi" der; yurt içi 15 dakika (5 dk'da bir yazılır), kripto
// fiyat alarmıyla aynı 10 dakika (`KRIPTO_BAYATLIK_MS`).
//
// Hafta sonu altın/döviz DEĞERLENDİRİLMEZ: piyasa kapalıyken truncgil'in
// `Change` alanı cuma gününün değişimini taşıyabilir; cumartesi sabahı
// "bugün %2 düştü" demek dünün hareketini bugüne yazmak olurdu. Kripto
// 7/24 (yüzde günün kendi açılışına göre).

import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';

import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { kriptoKodu, istanbulGunu, TR_OFFSET_MS } from './kripto.ts';
import { isGoldSymbol, KRIPTO_BAYATLIK_MS } from './live_prices.ts';
import { kriptoWidgetFiyati, widgetSembolTuru, yurtIciWidgetFiyati } from './widget_fiyat.ts';
import {
  kartGorseli,
  KartAyari,
  KartVerisi,
  kartVerisiniHazirla,
  yuzdeYazisi,
} from './bildirim_karti.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  TokenRow,
  tokenSatirlariniOku,
} from './push_tokens.ts';
import { sessizKullanicilar } from './quiet_hours.ts';
import { appNotificationRow, recordAppNotification } from './app_notifications.ts';

/// Fiyat alarmıyla aynı kanal: kullanıcı "alarmlar" kanalını açık tutup
/// brifingi kapatabilir; yüzde alarmı da kendi kurduğu alarmdır.
export const YUZDE_KANAL = 'alert_channel';

export const YUZDE_YURT_ICI_BAYATLIK_MS = 15 * 60_000;
export const YUZDE_KRIPTO_BAYATLIK_MS = KRIPTO_BAYATLIK_MS;

export type YuzdeYon = 'dusus' | 'yukselis' | 'ikisi';
export type YuzdeKaynak = 'yurt_ici' | 'kripto';

export type YuzdeAlarmSatiri = {
  id: string;
  user_id: string;
  symbol: string;
  label: string;
  esik_pct: number | string;
  yon: string;
  son_tetik_gunu: string | null;
};

/// Sembol yüzde alarmı alabilir mi; alırsa hangi tablodan. Fon ve
/// beyaz liste dışı her şey `null`.
export function yuzdeAlarmKaynagi(sembol: string): YuzdeKaynak | null {
  const t = widgetSembolTuru(sembol);
  return t === 'yurt_ici' || t === 'kripto' ? t : null;
}

/// 0168 hızlı tur türü (`turler` filtresi) — `check-price-alerts › alarmTuru`
/// ile aynı ayrım, yalnız kapsamdaki semboller için.
export function yuzdeAlarmTuru(sembol: string): 'altin' | 'doviz' | 'kripto' | null {
  const k = yuzdeAlarmKaynagi(sembol);
  if (k === 'kripto') return 'kripto';
  if (k === 'yurt_ici') return isGoldSymbol(sembol) ? 'altin' : 'doviz';
  return null;
}

/// Bu kaynağın "bugün"ü şu an anlamlı mı (yukarıdaki hafta sonu kararı).
export function bugunDegerlendirilir(kaynak: YuzdeKaynak, simdi: Date): boolean {
  if (kaynak === 'kripto') return true;
  const g = new Date(simdi.getTime() + TR_OFFSET_MS).getUTCDay();
  return g !== 0 && g !== 6;
}

/// Yön metni geçerli mi — DB CHECK'i aynı üçlüyü ister; bozuk satır yine de
/// değerlendirilmez (yanlış yönde çalmaktansa susmak).
export function yonGecerli(yon: string): yon is YuzdeYon {
  return yon === 'dusus' || yon === 'yukselis' || yon === 'ikisi';
}

/// Alarm çalar mı. Sınır DAHİL (fiyat alarmıyla aynı gerekçe: kullanıcı
/// "%2 düşerse" der, "%2'den fazla" demez).
export function yuzdeTetiklendiMi(degisim: number, esik: number, yon: string): boolean {
  if (!Number.isFinite(degisim) || !Number.isFinite(esik) || esik <= 0) return false;
  if (!yonGecerli(yon)) return false;
  if (yon === 'dusus') return degisim <= -esik;
  if (yon === 'yukselis') return degisim >= esik;
  return Math.abs(degisim) >= esik;
}

/// Bugün zaten çaldı mı (günde en çok bir kez).
export function bugunCaldi(son: string | null | undefined, bugun: string): boolean {
  return typeof son === 'string' && son.slice(0, 10) === bugun;
}

export type YuzdeKotasyon = { fiyat: number; degisim: number; zaman: number };

/// Satırı alarm kotasyonuna çevirir: widget yardımcılarıyla AYNI hesap,
/// üstüne alarm bayatlığı ve "bugünün satırı" şartı. Yüzde yoksa `null`.
export function yuzdeKotasyonu(
  kaynak: YuzdeKaynak,
  satir: Record<string, unknown>,
  simdiMs: number,
): YuzdeKotasyon | null {
  const f = kaynak === 'yurt_ici'
    ? yurtIciWidgetFiyati(
      satir as { ts: unknown; fiyat: unknown; degisim_pct: unknown },
      simdiMs,
    )
    : kriptoWidgetFiyati(
      satir as { fiyat_try: unknown; gun_acilis_try: unknown; guncellendi: unknown },
      simdiMs,
    );
  if (!f || f.degisim === undefined || !Number.isFinite(f.degisim)) return null;
  const sinir = kaynak === 'yurt_ici' ? YUZDE_YURT_ICI_BAYATLIK_MS : YUZDE_KRIPTO_BAYATLIK_MS;
  if (simdiMs - f.zaman > sinir) return null;
  if (istanbulGunu(new Date(f.zaman)) !== istanbulGunu(new Date(simdiMs))) return null;
  return { fiyat: f.fiyat, degisim: f.degisim, zaman: f.zaman };
}

/// `yurt_ici_kotasyon` satırlarından sembol başına EN YENİ olanı.
export function sonSatirlar<T extends { sembol: unknown; ts: unknown }>(
  satirlar: T[],
): Map<string, T> {
  const out = new Map<string, T>();
  for (const s of satirlar) {
    const k = String(s.sembol);
    const onceki = out.get(k);
    if (!onceki || Date.parse(String(s.ts)) > Date.parse(String(onceki.ts))) out.set(k, s);
  }
  return out;
}

/// Eşik metni: 2 → "2", 2.5 → "2,5".
export function esikMetni(esik: number): string {
  const yuvarlak = Math.round(esik * 100) / 100;
  return Number.isInteger(yuvarlak)
    ? String(yuvarlak)
    : String(yuvarlak).replace('.', ',');
}

/// Türkçe TL biçimi — `check-price-alerts › formatTRY` ile aynı kural
/// (Intl'in tr-TR verisine güvenilmez). 1 ₺ altı (SHIB) 2 haneye
/// yuvarlanınca 0 olurdu; orada 6 haneye kadar, sondaki sıfırlar atılır.
export function tlMetni(v: number): string {
  if (Math.abs(v) < 1) {
    return v.toFixed(6).replace(/0+$/, '').replace(/\.$/, '').replace('.', ',');
  }
  const [tam, kesir] = Math.abs(v).toFixed(2).split('.');
  const binlik = tam.replace(/\B(?=(\d{3})+(?!\d))/g, '.');
  return `${v < 0 ? '-' : ''}${binlik},${kesir}`;
}

/// Bildirim metni: "▼ Gram altın bugün %2,1 düştü · ₺4.212,37".
/// Yön oku + fiil birlikte: yön yalnız renkle (ya da yalnız okla) verilmez.
export function yuzdeAlarmMesaji(
  label: string,
  degisim: number,
  fiyat: number,
  esik: number,
): { title: string; body: string } {
  const yukari = degisim > 0;
  return {
    title: `${yukari ? '▲' : '▼'} ${label} bugün %${yuzdeYazisi(degisim)} ` +
      `${yukari ? 'yükseldi' : 'düştü'} · ₺${tlMetni(fiyat)}`,
    body: `Kurduğun günlük %${esikMetni(esik)} alarmı çalıştı; yarın kendiliğinden ` +
      'yeniden kurulur. Yatırım tavsiyesi değildir.',
  };
}

/// Kart (yalnız `bildirim_surumu >= 2`): büyük satır yüzde, halka yüzde.
export function yuzdeAlarmKarti(
  label: string,
  degisim: number,
  fiyat: number,
  esik: number,
): KartVerisi | null {
  if (!Number.isFinite(degisim) || !Number.isFinite(fiyat)) return null;
  return kartVerisiniHazirla({
    e: label,
    b: `%${yuzdeYazisi(degisim)}`,
    y: degisim > 0 ? 'u' : degisim < 0 ? 'd' : 'n',
    p: degisim,
    a: `₺${tlMetni(fiyat)} · günlük %${esikMetni(esik)} alarmı`,
  });
}

/// Bugünün damgasını atar; YALNIZ bu çağrı attıysa `'damgalandi'`.
/// Koşullu UPDATE: iki tur çakışırsa ikincisi satır alamaz, push göndermez
/// (0168 `alarmiSondur` gerekçesi).
export async function yuzdeDamgala(
  // deno-lint-ignore no-explicit-any
  admin: { from: (t: string) => any },
  id: string,
  bugun: string,
  kotasyon: { fiyat: number; degisim: number },
  simdi: Date = new Date(),
): Promise<'damgalandi' | 'zaten' | 'hata'> {
  const { data, error } = await admin
    .from('yuzde_alarmlari')
    .update({
      son_tetik_gunu: bugun,
      son_tetik_at: simdi.toISOString(),
      son_tetik_pct: Math.round(kotasyon.degisim * 1000) / 1000,
      son_tetik_fiyat: kotasyon.fiyat,
    })
    .eq('id', id)
    .or(`son_tetik_gunu.is.null,son_tetik_gunu.lt.${bugun}`)
    .select('id');
  if (error) {
    console.error('[yuzde-alarmi] damga yazilamadi:', error.message);
    return 'hata';
  }
  return Array.isArray(data) && data.length > 0 ? 'damgalandi' : 'zaten';
}

/// Bir turun tamamı. Hata fırlatabilir; çağıran yakalar ki fiyat alarmı
/// turu bundan etkilenmesin.
export async function yuzdeAlarmTuruKos(
  admin: SupabaseClient,
  args: {
    dryRun: boolean;
    /// 0168 `turler` filtresi; `null` = her tür.
    filtre: ReadonlySet<string> | null;
    fcm: { projectId: string; serviceAccountJson: string } | null;
    kart?: KartAyari | null;
    simdi?: Date;
  },
): Promise<Record<string, unknown>> {
  const simdi = args.simdi ?? new Date();
  const simdiMs = simdi.getTime();
  const bugun = istanbulGunu(simdi);

  // ── 1) Bugün henüz çalmamış etkin alarmlar ────────────────────────────────
  const { data: satirlar, error } = await admin
    .from('yuzde_alarmlari')
    .select('id, user_id, symbol, label, esik_pct, yon, son_tetik_gunu')
    .eq('enabled', true)
    .or(`son_tetik_gunu.is.null,son_tetik_gunu.lt.${bugun}`);
  if (error) throw new Error(`Yuzde alarmlari alinamadi: ${error.message}`);

  const alarmlar = ((satirlar ?? []) as YuzdeAlarmSatiri[]).filter((a) => {
    const kaynak = yuzdeAlarmKaynagi(a.symbol);
    if (kaynak === null || !yonGecerli(a.yon)) return false;
    if (bugunCaldi(a.son_tetik_gunu, bugun)) return false;
    const tur = yuzdeAlarmTuru(a.symbol);
    if (args.filtre !== null && (tur === null || !args.filtre.has(tur))) return false;
    return bugunDegerlendirilir(kaynak, simdi);
  });
  if (alarmlar.length === 0) return { checked: 0, sent: 0 };

  // ── 2) Kotasyonlar: sembol başına son satır, tek sorgu/tablo ──────────────
  const kotasyonlar = new Map<string, YuzdeKotasyon>();
  const yurtIci = [...new Set(alarmlar.map((a) => a.symbol)
    .filter((s) => yuzdeAlarmKaynagi(s) === 'yurt_ici'))];
  const kripto = [...new Set(alarmlar.map((a) => a.symbol)
    .filter((s) => yuzdeAlarmKaynagi(s) === 'kripto'))];

  if (yurtIci.length > 0) {
    const { data, error: e } = await admin
      .from('yurt_ici_kotasyon')
      .select('sembol, ts, fiyat, degisim_pct')
      .in('sembol', yurtIci)
      .gte('ts', new Date(simdiMs - YUZDE_YURT_ICI_BAYATLIK_MS).toISOString());
    if (e) {
      console.error('[yuzde-alarmi] yurt_ici okunamadi:', e.code);
    } else {
      for (const [s, satir] of sonSatirlar((data ?? []) as Array<{ sembol: unknown; ts: unknown }>)) {
        const k = yuzdeKotasyonu('yurt_ici', satir as Record<string, unknown>, simdiMs);
        if (k) kotasyonlar.set(s, k);
      }
    }
  }
  if (kripto.length > 0) {
    const kodlar = new Map<string, string>();
    for (const s of kripto) {
      const kod = kriptoKodu(s);
      if (kod) kodlar.set(kod, s);
    }
    const { data, error: e } = await admin
      .from('kripto_fiyat')
      .select('kod, fiyat_try, gun_acilis_try, guncellendi')
      .in('kod', [...kodlar.keys()]);
    if (e) {
      console.error('[yuzde-alarmi] kripto okunamadi:', e.code);
    } else {
      for (const satir of (data ?? []) as Array<Record<string, unknown>>) {
        const s = kodlar.get(String(satir.kod));
        const k = s ? yuzdeKotasyonu('kripto', satir, simdiMs) : null;
        if (s && k) kotasyonlar.set(s, k);
      }
    }
  }

  const tetiklenen = alarmlar.filter((a) => {
    const k = kotasyonlar.get(a.symbol);
    return k !== undefined && yuzdeTetiklendiMi(k.degisim, Number(a.esik_pct), a.yon);
  });
  if (tetiklenen.length === 0) {
    return { checked: alarmlar.length, priced: kotasyonlar.size, sent: 0 };
  }

  // ── 3) Token'lar ──────────────────────────────────────────────────────────
  const userIds = [...new Set(tetiklenen.map((a) => a.user_id))];
  const { data: tokenRows } = await tokenSatirlariniOku((s) =>
    admin.from('user_push_tokens').select(s).in('user_id', userIds)
  );
  // 0137: cihazın pasif hesaplarının satırları da (başlıkta hesap adı).
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

  // Sessiz saatler (0057): atlanır ama DAMGALANMAZ — pencere bitince koşul
  // sürüyorsa aynı gün içinde bir sonraki turda gider.
  const sessiz = await sessizKullanicilar(admin, userIds);
  const accessToken = args.dryRun || args.fcm === null
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  let sent = 0;
  let skippedQuietHours = 0;
  const failures: string[] = [];

  for (const alarm of tetiklenen) {
    if (sessiz.has(alarm.user_id)) { skippedQuietHours += 1; continue; }
    const k = kotasyonlar.get(alarm.symbol)!;
    const esik = Number(alarm.esik_pct);
    const mesaj = yuzdeAlarmMesaji(alarm.label, k.degisim, k.fiyat, esik);
    if (args.dryRun || args.fcm === null) { sent += 1; continue; }

    // Damga ÖNCE, push SONRA (fiyat alarmıyla aynı sıra): push başarısız
    // olursa bugün bir daha denenmez ama kullanıcı 5 dakikada bir aynı
    // bildirimi de yemez — geri alınamaz olan o.
    const damga = await yuzdeDamgala(admin, alarm.id, bugun, k, simdi);
    if (damga === 'hata') { failures.push('damga: yazilamadi'); continue; }
    if (damga === 'zaten') continue;

    // Çan kaydı push'tan bağımsız (0066 gerekçesi).
    const kayit = await recordAppNotification(admin, appNotificationRow({
      userId: alarm.user_id,
      type: 'yuzde_alarm',
      title: mesaj.title,
      body: mesaj.body,
      data: { symbol: alarm.symbol, yuzde_alarm_id: alarm.id },
    }));
    if (kayit) failures.push(kayit);

    const kartVerisi = yuzdeAlarmKarti(alarm.label, k.degisim, k.fiyat, esik);
    for (const t of tokensByUser.get(alarm.user_id) ?? []) {
      const r = await sendFcmNotification({
        accessToken,
        projectId: args.fcm.projectId,
        token: t.token,
        hesap: ekHesap(t),
        title: mesaj.title,
        body: mesaj.body,
        channelId: YUZDE_KANAL,
        // Fiyat alarmıyla aynı acil uyarı (#252): APNs 10, Android yüksek.
        priority: 'high',
        // `type: 'price_alert'` BİLEREK: eski ve yeni build bu türe
        // dokununca sembolün varlık ekranını açar (`openPriceAlertAsset`).
        // Yeni tür adı eski build'de hiçbir yere gitmezdi.
        data: { type: 'price_alert', symbol: alarm.symbol, yuzde_alarm_id: alarm.id },
        gorselUrl: await kartGorseli(args.kart, t, kartVerisi),
      });
      if (r.ok) {
        sent += 1;
      } else {
        console.error('[yuzde-alarmi] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
        failures.push(`fcm: ${r.hataKodu}`);
        if (r.shouldDeleteToken) {
          await admin.from('user_push_tokens').delete().eq('token', t.token);
        }
      }
    }
  }

  return {
    checked: alarmlar.length,
    priced: kotasyonlar.size,
    triggered: tetiklenen.length,
    sent,
    skipped_quiet_hours: skippedQuietHours,
    failures: failures.slice(0, 5),
  };
}
