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
import { createAccessToken, sendFcmNotification, ServiceAccount, shortLabel } from './fcm.ts';
import {
  collapseTokens,
  ekHesap,
  ekHesapSatirlari,
  TokenRow,
  tokenSatirlariniOku,
} from './push_tokens.ts';
import { degisimKarti, kartGorseli, KartAyari, KartVerisi } from './bildirim_karti.ts';
import { istanbulGunu, kriptoMu } from './kripto.ts';
import { EUROBOND_ONEKI } from './eurobond.ts';
import { GRAM_ONEKI } from './emtia_gram.ts';
import { fiyatMetni, kotasyonSimgesi } from './fiyat_metni.ts';
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

/// Yüzdenin hangi döneme ait olduğu (2026-10-29, bildirim denetimi).
///
/// Push 18:25'te (TR) gider; o anda her kaynağın "değişim"i başka bir şeyi
/// ölçer ve eski metin hepsine "Bugünkü kapanış" diyordu (yasin: "artışın
/// günlük mü haftalık mı olduğu net olmalı"):
///   · `kapanis` — BIST (18:10'da kapanmış), eurobond: önceki kapanışa göre
///     günlük değişim.
///   · `gun_ici` — ABD hissesi (16:30'da açılmış), vadeli, küresel endeks,
///     altın/döviz (truncgil `Change`, piyasa açık): önceki kapanışa göre,
///     gün henüz bitmedi.
///   · `kripto` — `kripto_fiyat.gun_acilis_try`: bugün 00:00 (İstanbul)
///     açılışına göre (`live_prices.ts › kriptoSatiriKotasyon`).
///   · `fon` — TEFAS'ın bugün açıkladığı NAV, bir önceki NAV'a göre.
export type HareketDonemi = 'kapanis' | 'gun_ici' | 'kripto' | 'fon';

export type Hareket = {
  ad: string;
  pct: number;
  fon?: boolean;
  emtia?: boolean;
  /// Dönem verilmezse eski bayraklardan türer (fon → fon, emtia → gün içi,
  /// aksi kapanış) — eski çağıranlar ve testler bozulmasın.
  donem?: HareketDonemi;
  /// Canlı kotasyon (sembolün kendi biriminde) ve simgesi; bilinmiyorsa
  /// metinde fiyat yazılmaz (uydurma sayı yok).
  fiyat?: number | null;
  simge?: string | null;
};

/// Sembolden dönem — gerekçe `HareketDonemi` belgesinde.
export function hareketDonemi(sembol: string): HareketDonemi {
  const t = sembol.trim().toUpperCase();
  if (t.startsWith('TEFAS:')) return 'fon';
  if (kriptoMu(t)) return 'kripto';
  if (t.endsWith('.IS') || t.startsWith(EUROBOND_ONEKI)) return 'kapanis';
  return 'gun_ici';
}

function donemi(h: Hareket): HareketDonemi {
  return h.donem ?? (h.fon ? 'fon' : h.emtia ? 'gun_ici' : 'kapanis');
}

/// Başlıktaki dönem sözcüğü: gün kapanmışsa "bugün", sürüyorsa "gün içi".
const BASLIK_DONEMI: Record<HareketDonemi, string> = {
  kapanis: 'bugün',
  fon: 'bugün',
  gun_ici: 'gün içi',
  kripto: 'gün içi',
};

/// Gövdenin ilk cümlesi: yüzde neye göre.
const TABAN_CUMLESI: Record<HareketDonemi, string> = {
  kapanis: 'Günlük değişim, önceki kapanışa göre.',
  gun_ici: 'Gün içi değişim, önceki kapanışa göre.',
  kripto: "Bugün 00:00'dan (İstanbul) bu yana.",
  fon: 'Bugün açıklanan fon fiyatı, bir önceki fiyata göre.',
};

/// Çoklu bildirimde tek dönemli listenin başlığı.
const LISTE_BASLIGI: Record<HareketDonemi, string> = {
  kapanis: 'Günlük değişim (önceki kapanışa göre)',
  gun_ici: 'Gün içi değişim (önceki kapanışa göre)',
  kripto: "Bugün 00:00'dan (İstanbul) bu yana",
  fon: 'Bugün açıklanan fon fiyatı (bir önceki fiyata göre)',
};

/// Karışık listede satır sonundaki kısa dönem etiketi.
const KISA_DONEM: Record<HareketDonemi, string> = {
  kapanis: 'günlük',
  gun_ici: 'gün içi',
  kripto: "00:00'dan beri",
  fon: 'fon fiyatı',
};

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

/// Bugün yüzde alarmı (0169) çalmış (kullanıcı, sembol) çiftlerini
/// adaylardan çıkarır. Aynı varlığın aynı günkü hareketi kullanıcıya iki
/// kez gelmesin: yüzde alarmını kendisi kurmuş ve almış, akşamki takip
/// listesi özeti onu tekrar söylemez (müşteri raporu 27 Eki 09:15 #2).
/// Anahtar `user_id|sembol`; sembol kuralı iki tarafta da istemcinin
/// `alarmSembolu`'dur (ALTIN_* ya da ticker).
export function calanlariCikar<T extends { sembol: string }>(
  uid: string,
  satirlar: T[],
  calanlar: ReadonlySet<string>,
): T[] {
  if (calanlar.size === 0) return satirlar;
  return satirlar.filter((s) => !calanlar.has(`${uid}|${s.sembol}`));
}

/// Mesajdaki gösterimle aynı yuvarlama (tek ondalık, mutlak değer).
export function gorunenYuzde(pct: number): number {
  return Math.round(Math.abs(pct) * 10) / 10;
}

/// "+%5,3" / "−%5,5" — tek ondalık, Türkçe virgül, işaret her zaman.
function yuzdeParcasi(pct: number): string {
  return `${pct >= 0 ? '+' : '−'}%${Math.abs(pct).toFixed(1).replace('.', ',')}`;
}

function fiyatParcasi(h: Hareket): string | null {
  return typeof h.fiyat === 'number' && Number.isFinite(h.fiyat) && h.fiyat > 0
    ? fiyatMetni(h.fiyat, h.simge ?? null)
    : null;
}

/// Mesaj — tavsiye yok, emoji yok (RETENTION_STRATEJISI §8–9). Ondalık
/// ayırıcı Türkçe virgül; yön oku başlıkta.
///
/// 2026-10-29 (bildirim denetimi, yasin: "değerler tutarlı, artışın günlük
/// mü haftalık mı olduğu net olmalı"): başlık dönemi ("bugün"/"gün içi") ve
/// FİYATI söyler — eski "Tutar yok" kuralı kullanıcının cüzdan tutarı
/// içindi; birim fiyat kişisel değil, alarm ve yüzde alarmı da yazıyor ve
/// "%5 ama kaçtan kaça?" sorusu cevapsız kalıyordu. Gövde yüzdenin neye
/// göre olduğunu söyler; eski "Bugünkü kapanış" ABD hissesi, kripto ve
/// döviz için yanlıştı (18:25'te o piyasalar açık).
export function hareketMesaji(hareketler: Hareket[]): { title: string; body: string } {
  const ilk = hareketler[0];
  if (hareketler.length === 1) {
    const d = donemi(ilk);
    const fiyat = fiyatParcasi(ilk);
    return {
      title: `${ilk.pct >= 0 ? '▲' : '▼'} ${ilk.ad} ${BASLIK_DONEMI[d]} ` +
        `${yuzdeParcasi(ilk.pct)}${fiyat ? ` · ${fiyat}` : ''}`,
      body: `Takip listendeki varlık. ${TABAN_CUMLESI[d]} Yatırım tavsiyesi değildir.`,
    };
  }
  const donemler = new Set(hareketler.map(donemi));
  const tekDonem = donemler.size === 1 ? donemi(ilk) : null;
  const satir = (h: Hareket) => {
    const fiyat = fiyatParcasi(h);
    const ek = tekDonem ? '' : ` (${KISA_DONEM[donemi(h)]})`;
    return `${h.ad} ${yuzdeParcasi(h.pct)}${fiyat ? ` ${fiyat}` : ''}${ek}`;
  };
  const liste = hareketler.map(satir).join(' · ');
  return {
    title: `Takip listende bugün ${hareketler.length} sert hareket`,
    body: `${tekDonem ? `${LISTE_BASLIGI[tekDonem]}: ` : ''}${liste}. ` +
      'Yatırım tavsiyesi değildir.',
  };
}

/// Kart yalnız TEK hareketli bildirimde: birden çok hareketi tek halka
/// anlatamaz, metin zaten hepsini sayıyor. Alt satır dönemi söyler
/// (2026-10-29: "son kapanış" ABD hissesinde/dövizde yanlıştı).
export function hareketKarti(hareketler: Hareket[]): KartVerisi | null {
  if (hareketler.length !== 1) return null;
  const h = hareketler[0];
  const alt: Record<HareketDonemi, string> = {
    kapanis: 'Takip listesi · günlük',
    gun_ici: 'Takip listesi · gün içi',
    kripto: "Takip listesi · 00:00'dan beri",
    fon: 'Takip listesi · fon fiyatı',
  };
  return degisimKarti(h.ad, h.pct, alt[donemi(h)]);
}

/// Bildirimdeki kısa ad (2026-10-29): `watchlist.name` uzun şirket adıydı
/// ("Türk Hava Yolları A.O.") ve kilit ekranında yüzdeyi ekrandan itiyordu.
/// Sinyal bildirimiyle aynı kural (`fcm.ts › shortLabel`): hisse/fon/kripto
/// kodu. Kodun kullanıcıya bir şey söylemediği yerde (altın alt kategorisi,
/// kur, vadeli, gram türevi, eurobond ISIN'i, `^` endeks) kayıtlı ad.
export function takipEtiketi(sembol: string, ad: string): string {
  const t = sembol.trim().toUpperCase();
  const adVar = (ad ?? '').trim();
  if (
    t.startsWith('ALTIN_') || t.endsWith('=X') || t.endsWith('=F') ||
    t.startsWith(GRAM_ONEKI) || t.startsWith(EUROBOND_ONEKI) || t.startsWith('^')
  ) return adVar || sembol;
  return shortLabel(adVar || sembol, sembol);
}

type WatchRow = {
  user_id: string;
  ticker: string;
  name: string;
  type: string;
  sub_category: string | null;
  currency?: string | null;
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
    .select('user_id, ticker, name, type, sub_category, currency');
  if (error) throw new Error(`watchlist okunamadi: ${error.message}`);
  const liste = (rows ?? []) as WatchRow[];
  if (liste.length === 0) return { ok: true, reason: 'Takip listesi bos.', sent: 0 };

  // Sembol ↔ satırlar. Fon/BES ticker'ı `TEFAS:XXX`; canlı kotasyon onu
  // TEFAS'a yönlendirir (`live_prices.ts`).
  const kullaniciSatirlari = new Map<
    string,
    Array<{ sembol: string; ad: string; currency: string | null }>
  >();
  const semboller = new Set<string>();
  for (const r of liste) {
    const s = takipSembolu(r.ticker ?? '', r.sub_category);
    if (!s) continue;
    semboller.add(s);
    const l = kullaniciSatirlari.get(r.user_id) ?? [];
    // Fon adı uzun ("… Para Piyasası Katılım Fonu") ve kilit ekranında
    // kesilir; fonda kullanıcının tanıdığı ad koddur (TTE, AFT). 2026-10-29:
    // hisse ve kripto da koda indi (`takipEtiketi`).
    l.push({ sembol: s, ad: takipEtiketi(s, r.name), currency: r.currency ?? null });
    kullaniciSatirlari.set(r.user_id, l);
  }
  if (semboller.size === 0) return { ok: true, reason: 'Fiyatlanabilir sembol yok.', sent: 0 };

  const kotasyon = await fetchLiveQuotes(semboller, admin);

  // Bugün çalmış yüzde alarmları (0169). Okuma düşerse (tablo henüz
  // dağıtılmamış) tekilleştirme yapılmaz, özet bugünkü gibi gider.
  const calanlar = new Set<string>();
  const { data: yuzdeSatirlari, error: yuzdeHatasi } = await admin
    .from('yuzde_alarmlari')
    .select('user_id, symbol')
    .eq('son_tetik_gunu', istanbulGunu(new Date()));
  if (yuzdeHatasi) {
    console.error('watchlist_moves: yuzde_alarmlari okunamadi', yuzdeHatasi.code);
  }
  for (const r of (yuzdeSatirlari ?? []) as Array<{ user_id: string; symbol: string }>) {
    calanlar.add(`${r.user_id}|${r.symbol}`);
  }

  // Kullanıcı → seçilen hareketler.
  const secimler = new Map<string, Hareket[]>();
  for (const [uid, satirlar] of kullaniciSatirlari) {
    const adaylar: Hareket[] = [];
    for (const s of calanlariCikar(uid, satirlar, calanlar)) {
      const q = kotasyon.get(s.sembol);
      if (!q || q.changePct === null) continue;
      adaylar.push({
        ad: s.ad,
        pct: q.changePct,
        fon: s.sembol.startsWith('TEFAS:'),
        emtia: emtiaSembolu(s.sembol),
        donem: hareketDonemi(s.sembol),
        fiyat: q.price,
        simge: kotasyonSimgesi(s.sembol, s.currency),
      });
    }
    const secili = hareketleriSec(adaylar, esik);
    if (secili.length > 0) secimler.set(uid, secili);
  }
  if (secimler.size === 0) {
    return { ok: true, reason: 'Esigi asan hareket yok.', checked: semboller.size, sent: 0 };
  }

  const userIds = [...secimler.keys()];
  // Tekilleştirme günü İstanbul günü (2026-10-29): UTC tarih 21:00–24:00
  // TR arasında bir sonraki günü gösterirdi; yüzde alarmı ve kripto da
  // `istanbulGunu` kullanıyor.
  const bugun = istanbulGunu(new Date());
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
  const tokensByUser = new Map<string, TokenRow[]>();
  for (const t of tokens) {
    const l = tokensByUser.get(t.user_id) ?? [];
    l.push(t);
    tokensByUser.set(t.user_id, l);
  }

  let sent = 0;
  let recorded = 0;
  let skippedQuietHours = 0;
  let skippedAlready = 0;
  const failures: string[] = [];
  const cankaydi = new Set<string>();
  const accessToken = args.dryRun || !args.fcm
    ? ''
    : await createAccessToken(JSON.parse(args.fcm.serviceAccountJson) as ServiceAccount);

  // Kullanıcı başına döngü (2026-10-29): çan kaydı eskiden token
  // döngüsünün İÇİNDEYDİ — token'ı olmayan (bildirim izni kapalı) ya da
  // sessiz saatteki kullanıcının çanına hiçbir şey düşmüyordu. Çan push'un
  // yedeğidir (`app_notifications.ts`); sessiz saat yalnız push'u susturur.
  for (const [uid, hareketler] of secimler) {
    if (zaten.has(uid)) { skippedAlready += 1; continue; }
    const mesaj = hareketMesaji(hareketler);
    const userTokens = tokensByUser.get(uid) ?? [];
    const sessizde = sessiz.has(uid);
    if (args.dryRun || !args.fcm) {
      if (sessizde) skippedQuietHours += 1;
      else sent += userTokens.length;
      continue;
    }

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
    else recorded += 1;

    let pushGitti = false;
    if (sessizde) {
      skippedQuietHours += 1;
    } else {
      for (const t of userTokens) {
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
          pushGitti = true;
        } else {
          // Ham FCM gövdesi yalnızca günlüğe; yanıta kısa kod (2026-09-23 denetimi L2).
          console.error('[watchlist-moves] FCM gonderimi basarisiz:', r.rawText.slice(0, 500));
          failures.push(`fcm: ${r.hataKodu}`);
          if (r.shouldDeleteToken) {
            await admin.from('user_push_tokens').delete().eq('token', t.token);
          }
        }
      }
    }

    // Günlük damga: push gittiyse YA DA çana yazıldıysa. Aynı gün ikinci
    // tur (elle tetik, yeniden deneme) çana ikinci satır yazmasın.
    if (pushGitti || !kayitHatasi) {
      await admin
        .from('watchlist_move_log')
        .upsert({ user_id: uid, sent_on: bugun }, { onConflict: 'user_id,sent_on' });
    }
  }

  return {
    ok: true,
    checked: semboller.size,
    users_with_moves: secimler.size,
    sent,
    recorded,
    skipped_already: skippedAlready,
    skipped_quiet_hours: skippedQuietHours,
    dry_run: args.dryRun,
    failures: failures.slice(0, 5),
  };
}
