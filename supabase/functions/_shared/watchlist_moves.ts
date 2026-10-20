// Takip listesinde günlük büyük hareket — kapanış sonrası tek push.
//
// Neden var (2026-09-20, günlük giriş turu): sahip OLMADIĞI hisseyi
// izleyen kullanıcı "alayım mı" kararı için her gün döner; ama alarm kurmak
// üç dokunuş derinde ve çoğu kurmuyor. Bu modül alarm kurmadan, izlenen
// varlık gün içinde eşiğin üstünde oynadıysa kapanışta haber verir.
//
// Kurallar:
//   · Kullanıcı başına GÜNDE TEK push, en çok üç varlık (mutlak harekete
//     göre sıralı). Her sembole ayrı push yağdırmak alarm kanalını değersiz
//     kılardı.
//   · Yalnızca kullanıcının KENDİ seçtiği liste (watchlist) — proaktif değil,
//     istek üzerine bildirim; kanal fiyat alarmıyla aynı (`alert_channel`).
//   · TEFAS fonu (fon/BES) 2026-10-17'den beri dahil: değişim aynı canlı
//     kotasyon yolundan, TEFAS'ın son iki NAV'ından gelir (bugün tarihli
//     NAV yoksa fon o gün sayılmaz). Eşik fonda %2: fon hisseye göre az
//     oynar, %5 fonda neredeyse hiç aşılmazdı.
//   · Emtia (Yahoo vadelisi, `=F`) 2026-10-18: eşik %3 ve metin "gün içi".
//     Vadeli neredeyse 24 saat işler; push anında "kapanış" yoktur, değişim
//     önceki uzlaşma fiyatına göre gün içi harekettir. %5 petrol/gümüşte
//     ayda birkaç kez aşılırdı, kullanıcı hiç haber almazdı (yasin onayı
//     "Gönder", 18 Eki).
//   · Sessiz saatler ve `watchlist_move_log` (0068) günlük tekilleştirme.
//
// Sembol kuralı istemcideki `alarmSembolu` ile AYNI: altın alt kategorisi
// (ALTIN_*) sembolün kendisi, aksi hâlde ticker. Farklı olsaydı kullanıcı
// ekranda 6.200 görürken sunucu başka bir seriye bakardı.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { collapseTokens, ekHesap, ekHesapSatirlari, tokenSatirlariniOku } from './push_tokens.ts';
import { degisimKarti, kartGorseli, KartAyari, KartVerisi } from './bildirim_karti.ts';
import { fetchLiveQuotes } from './live_prices.ts';
import { sessizKullanicilar } from './quiet_hours.ts';
import { appNotificationRow, recordAppNotification } from './app_notifications.ts';

/** Bildirime değer günlük hareket (mutlak, yüzde). */
export const HAREKET_ESIGI_PCT = 5;
/** Fon (TEFAS) için eşik — gerekçe dosya başında. */
export const FON_HAREKET_ESIGI_PCT = 2;
/** Emtia vadelisi için eşik — gerekçe dosya başında. */
export const EMTIA_HAREKET_ESIGI_PCT = 3;
/** Tek push'ta en çok kaç varlık anılır. */
export const EN_COK_VARLIK = 3;
export const CHANNEL_ID = 'alert_channel';

export type Hareket = { ad: string; pct: number; fon?: boolean; emtia?: boolean };

/// Yahoo vadeli sembolü (`CL=F`, `SI=F`); istemcideki `emtiaKatalogu` ile
/// aynı biçim. Tür alanına bakılmaz: "Diğer" yolundan eklenen vadeli de
/// aynı piyasa saatini taşır.
export function emtiaSembolu(sembol: string): boolean {
  return sembol.trim().toUpperCase().endsWith('=F');
}

/// İstemcideki `alarmSembolu` (lib/widgets/alarm_kur_sheet.dart) eşi.
export function takipSembolu(ticker: string, subCategory: string | null | undefined): string | null {
  const sub = (subCategory ?? '').trim();
  if (sub.startsWith('ALTIN_')) return sub;
  const t = ticker.trim();
  return t.length === 0 ? null : t;
}

/// Eşiği aşanları mutlak harekete göre sırala, ilk N. Fon ve emtia
/// satırı kendi eşiğiyle süzülür.
export function hareketleriSec(
  adaylar: Hareket[],
  esikPct = HAREKET_ESIGI_PCT,
  enCok = EN_COK_VARLIK,
  fonEsikPct = FON_HAREKET_ESIGI_PCT,
  emtiaEsikPct = EMTIA_HAREKET_ESIGI_PCT,
): Hareket[] {
  return adaylar
    // Eşik, mesajda GÖRÜNEN tek ondalıklı değerle karşılaştırılır: 9,8/10
    // kayan noktada −1,99999… çıkar, mesaj "%2,0" der ama eşiği geçmezdi
    // (müşteri testi 2026-10-17, BES −%2,0 bildirilmiyordu).
    .filter((h) =>
      Number.isFinite(h.pct) &&
      gorunenYuzde(h.pct) >=
        (h.fon ? fonEsikPct : h.emtia ? emtiaEsikPct : esikPct)
    )
    .sort((a, b) => Math.abs(b.pct) - Math.abs(a.pct))
    .slice(0, enCok);
}

/// Mesajdaki gösterimle aynı yuvarlama (tek ondalık, mutlak değer).
export function gorunenYuzde(pct: number): number {
  return Math.round(Math.abs(pct) * 10) / 10;
}

/// Mesaj — tutar yok, tavsiye yok, emoji yok (RETENTION_STRATEJISI §8–9).
/// Ondalık ayırıcı Türkçe virgül; yön oku başlıkta.
export function hareketMesaji(hareketler: Hareket[]): { title: string; body: string } {
  const parca = (h: Hareket) => {
    const m = Math.abs(h.pct).toFixed(1).replace('.', ',');
    return `${h.ad} ${h.pct >= 0 ? '+' : '−'}%${m}`;
  };
  const ilk = hareketler[0];
  const title = hareketler.length === 1
    ? `${ilk.pct >= 0 ? '▲' : '▼'} Takip listende: ${parca(ilk)}`
    : `Takip listende ${hareketler.length} büyük hareket`;
  // Fonun kapanışı yok, günde bir yayımlanan fiyatı var (TEFAS NAV).
  const body = hareketler.length === 1
    ? `${ilk.fon ? 'Bugünkü fon fiyatı' : ilk.emtia ? 'Gün içi hareket' : 'Bugünkü kapanış'}. Yatırım tavsiyesi değildir.`
    : `${hareketler.map(parca).join(' · ')}. Yatırım tavsiyesi değildir.`;
  return { title, body };
}

/// Kart yalnız TEK hareketli bildirimde: birden çok hareketi tek halka
/// anlatamaz, metin zaten hepsini sayıyor.
export function hareketKarti(hareketler: Hareket[]): KartVerisi | null {
  if (hareketler.length !== 1) return null;
  const h = hareketler[0];
  const alt = h.fon
    ? 'Takip listesi · fon fiyatı'
    : h.emtia
    ? 'Takip listesi · gün içi'
    : 'Takip listesi · son kapanış';
  return degisimKarti(h.ad, h.pct, alt);
}

type WatchRow = {
  user_id: string;
  ticker: string;
  name: string;
  type: string;
  sub_category: string | null;
};

export async function takipListesiHareketleri(
  admin: SupabaseClient,
  args: {
    fcm: { projectId: string; serviceAccountJson: string } | null;
    dryRun: boolean;
    esikPct?: number;
    /// Bildirim kartı (0092): verilirse `bildirim_surumu >= 2` cihazlara
    /// tek hareketli bildirimde kart görseli eklenir.
    kart?: KartAyari | null;
  },
): Promise<Record<string, unknown>> {
  const esik = args.esikPct ?? HAREKET_ESIGI_PCT;

  const { data: rows, error } = await admin
    .from('watchlist')
    .select('user_id, ticker, name, type, sub_category');
  if (error) throw new Error(`watchlist okunamadi: ${error.message}`);
  const liste = (rows ?? []) as WatchRow[];
  if (liste.length === 0) return { ok: true, reason: 'Takip listesi bos.', sent: 0 };

  // Sembol ↔ satırlar. Fon/BES ticker'ı `TEFAS:XXX`; canlı kotasyon onu
  // TEFAS'a yönlendirir (`live_prices.ts`).
  const kullaniciSatirlari = new Map<string, Array<{ sembol: string; ad: string }>>();
  const semboller = new Set<string>();
  for (const r of liste) {
    const s = takipSembolu(r.ticker ?? '', r.sub_category);
    if (!s) continue;
    semboller.add(s);
    const l = kullaniciSatirlari.get(r.user_id) ?? [];
    // Fon adı uzun ("… Para Piyasası Katılım Fonu") ve kilit ekranında
    // kesilir; fonda kullanıcının tanıdığı ad koddur (TTE, AFT).
    const ad = s.startsWith('TEFAS:') ? s.slice('TEFAS:'.length) : (r.name || s);
    l.push({ sembol: s, ad });
    kullaniciSatirlari.set(r.user_id, l);
  }
  if (semboller.size === 0) return { ok: true, reason: 'Fiyatlanabilir sembol yok.', sent: 0 };

  const kotasyon = await fetchLiveQuotes(semboller, admin);

  // Kullanıcı → seçilen hareketler.
  const secimler = new Map<string, Hareket[]>();
  for (const [uid, satirlar] of kullaniciSatirlari) {
    const adaylar: Hareket[] = [];
    for (const s of satirlar) {
      const q = kotasyon.get(s.sembol);
      if (!q || q.changePct === null) continue;
      adaylar.push({
        ad: s.ad,
        pct: q.changePct,
        fon: s.sembol.startsWith('TEFAS:'),
        emtia: emtiaSembolu(s.sembol),
      });
    }
    const secili = hareketleriSec(adaylar, esik);
    if (secili.length > 0) secimler.set(uid, secili);
  }
  if (secimler.size === 0) {
    return { ok: true, reason: 'Esigi asan hareket yok.', checked: semboller.size, sent: 0 };
  }

  const userIds = [...secimler.keys()];
  const bugun = new Date().toISOString().slice(0, 10);
  const { data: gonderilmis } = await admin
    .from('watchlist_move_log')
    .select('user_id')
    .eq('sent_on', bugun)
    .in('user_id', userIds);
  const zaten = new Set((gonderilmis ?? []).map((r: { user_id: string }) => r.user_id));
  const sessiz = await sessizKullanicilar(admin, userIds);

  const { data: tokenRows } = await tokenSatirlariniOku((s) =>
    admin.from('user_push_tokens').select(s).in('user_id', userIds)
  );
  // 0137: cihazın pasif hesaplarının satırları da (başlıkta hesap adı).
  const tokens = collapseTokens([
    ...(tokenRows ?? []),
    ...await ekHesapSatirlari(admin, userIds),
  ]);

  let sent = 0;
  let skippedQuietHours = 0;
  let skippedAlready = 0;
  const failures: string[] = [];
  const cankaydi = new Set<string>();
  const accessToken = args.dryRun || !args.fcm
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  for (const t of tokens) {
    const uid = t.user_id;
    const hareketler = secimler.get(uid);
    if (!hareketler) continue;
    if (zaten.has(uid)) { skippedAlready += 1; continue; }
    if (sessiz.has(uid)) { skippedQuietHours += 1; continue; }
    const mesaj = hareketMesaji(hareketler);
    if (args.dryRun || !args.fcm) { sent += 1; continue; }

    const kayitHatasi = await recordAppNotification(
      admin,
      appNotificationRow({
        userId: uid,
        type: 'watchlist_move',
        title: mesaj.title,
        body: mesaj.body,
        data: { sent_on: bugun },
      }),
      cankaydi,
    );
    if (kayitHatasi) failures.push(kayitHatasi);

    const r = await sendFcmNotification({
      accessToken,
      projectId: args.fcm.projectId,
      token: t.token,
      hesap: ekHesap(t),
      title: mesaj.title,
      body: mesaj.body,
      channelId: CHANNEL_ID,
      data: { type: 'watchlist_move', sent_on: bugun },
      gorselUrl: await kartGorseli(args.kart, t, hareketKarti(hareketler)),
    });
    if (r.ok) {
      sent += 1;
      await admin
        .from('watchlist_move_log')
        .upsert({ user_id: uid, sent_on: bugun }, { onConflict: 'user_id,sent_on' });
    } else {
      // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
      console.error('[watchlist-moves] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
      failures.push(`fcm: ${r.hataKodu}`);
      if (r.shouldDeleteToken) {
        await admin.from('user_push_tokens').delete().eq('token', t.token);
      }
    }
  }

  return {
    ok: true,
    checked: semboller.size,
    users_with_moves: secimler.size,
    sent,
    skipped_already: skippedAlready,
    skipped_quiet_hours: skippedQuietHours,
    dry_run: args.dryRun,
    failures: failures.slice(0, 5),
  };
}
