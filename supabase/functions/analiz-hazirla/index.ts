// Analiz Hazırla Edge Function — HAFTALIK VARLIK NOTU / AYLIK RAPOR (Balina F2, 0117)
//
// pg_cron Pazar 20:00 TR (haftalık) ve ayın 1'i 06:00 TR (aylık) çağırır.
// Portföylerde tutulan varlıkları seçer, her biri için ölçüm paketini kurar
// (`_shared/analiz.ts`) ve hepsini TEK bir Anthropic Message Batch olarak
// gönderir. Sonucu `analiz-topla` saatte bir toplar.
//
// ── Neden Batch ─────────────────────────────────────────────────────────────
// Not kimsenin beklemediği bir iş (Pazartesi sabahına hazır olsun yeter);
// Batch yarı fiyat. Sistem talimatı istekler arasında önbelleğe alınır.
//
// ── Neden varlık başına ─────────────────────────────────────────────────────
// Maliyet kullanıcı sayısıyla değil varlık çeşidiyle büyür; modele kişisel
// veri (miktar, maliyet, kimin tuttuğu) GİTMEZ — yalnız piyasa ölçümleri.
//
// ── Kapılar ─────────────────────────────────────────────────────────────────
//   · `ANTHROPIC_API_KEY` function secret'ı tanımsızsa hiçbir şey gönderilmez
//     (503). Anahtarı koymak özelliği sunucuda açmaktır; uygulamada görünmesi
//     ayrıca `balina_radari_acik` bayrağına bağlı.
//   · Aynı dönem iki kez gönderilmez (`analiz_batch` defteri).
//   · Aylık harcama tavanı `ANALIZ_AYLIK_TAVAN_USD` (varsayılan 50): aşılınca
//     model Haiku'ya iner (N-04).
//   · Varlık üst sınırı `ANALIZ_VARLIK_USTU` (varsayılan 300), en çok
//     tutulandan başlayarak.
//
//   · Aylık nota haber (0177): `ANALIZ_HABER_ACIK` function secret'ı tam "1"
//     ise her varlık için AYRI bir haber batch'i gider (sunucu taraflı
//     `web_search`, varlık başına en çok 2 arama; `_shared/analiz_haber.ts`).
//     Kapalıyken (varsayılan) bu dosya #317 ile aynı işi yapar: tek not
//     batch'i, aynı istekler. Haber, tavan tahminiyle birlikte aşılacaksa
//     ya da model tavan yüzünden indiyse gönderilmez.
//
// Gövde: `{ tur: 'haftalik' | 'aylik', dry_run?: true, bugun?: 'YYYY-MM-DD' }`.
// `dry_run` paketleri kurar, örnek bir istek döner, GÖNDERMEZ (anahtar
// gerekmez). Yanıtta anahtar, ham Anthropic yanıtı, hata mesajı DÖNMEZ.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { acikPozisyonLotlari, PozisyonLot } from '../_shared/positions.ts';
import { varlikKodu } from '../_shared/haftalik_akis.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import { gunEkle } from '../_shared/balina.ts';
import { fetchDatedSeries, fetchEurobondDated, Seri } from '../_shared/dated_history.ts';
import { EUROBOND_ONEKI } from '../_shared/eurobond.ts';
import { ONS_GRAM } from '../_shared/emtia_gram.ts';
import {
  ayAraligi,
  FonGunu,
  fiyatPaketi,
  fonPaketi,
  ONCEKI_HAFTA,
  haftaAraligi,
  HacimSatiri,
  hacimPaketi,
  istekGovdesi,
  KategoriSirasi,
  NotTuru,
  Olcum,
  OlaySatiri,
  ozelKimlik,
  Paket,
  tavanaGoreModel,
  VarlikTuru,
} from '../_shared/analiz.ts';
import { haberAcikMi, haberGirdisi, haberIstegi, haberTavaniUygun } from '../_shared/analiz_haber.ts';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const MODEL: Record<NotTuru, string> = {
  haftalik: 'claude-sonnet-5-5',
  // Sonnet 5.5 (yasin kararı 2026-10-12): aylık da Sonnet; ilk tasarımda Opus'tu.
  aylik: 'claude-sonnet-5-5',
};

/// PostgREST bir yanıtta en çok 1000 satır döner; sayfala.
async function hepsi<T>(
  sorgu: (bas: number, son: number) => PromiseLike<{ data: unknown; error: unknown }>,
): Promise<T[]> {
  const out: T[] = [];
  for (let bas = 0; ; bas += 1000) {
    const yanit = await sorgu(bas, bas + 999);
    if (yanit.error) throw yanit.error;
    const data = yanit.data as T[] | null;
    out.push(...(data ?? []));
    if (!data || data.length < 1000) return out;
  }
}

/// `.in()` URL'e yazılır; uzun listeyi parçala.
function parcala<T>(xs: T[], n = 100): T[][] {
  const out: T[][] = [];
  for (let i = 0; i < xs.length; i += n) out.push(xs.slice(i, i + n));
  return out;
}

/// Seçilen varlık. [seri]/[para] yalnız fiyat paketli türlerde: serinin
/// sembolü (`dated_history.ts`) ve kote olduğu para.
export type Secilen = {
  ticker: string;
  varlik: VarlikTuru;
  tutan: number;
  seri?: string;
  para?: string;
};

/// Aylık nota 2026-11-07'de eklenen türler (yasin: "tüm varlıklar").
/// Haftalık not bilerek eski kapsamda: istek "aylık rapor"du ve haftalık
/// maliyet her hafta tekrarlanır. Dışarıda kalanlar ve neden:
///   · mevduat — değeri sözleşme faizinden; piyasa hareketi yok, yorumu
///     faiz oranının kendisi olurdu.
///   · diğer ve elle fiyatlı lot — seri yok (veri yoksa not yok).
///   · KRIPTO:USDT — dolara sabit; "değişim" kurdan ibaret (döviz notu var).
export const AYLIK_EK_TURLER = ['altin', 'doviz', 'emtia', 'eurobond'] as const;

/// Lot → not anahtarı ve ölçü. İstemci eşi `notAnahtari`
/// (`lib/providers/analiz_provider.dart`); biçim iki yanda aynı olmalı.
///   'THYAO.IS' · 'TEFAS:TTE' · 'KRIPTO:BTC'           (akış/hacim; eski)
///   'HISSE:AAPL' · 'ALTIN:GRAM' · 'USDTRY=X' · 'SI=F' · 'GRAM:SI=F' ·
///   'EUROBOND:XS…'                                     (fiyat; 2026-11-07)
/// Yurt dışı hissede önek: 'F', 'GE' gibi kısa semboller `varlik_analizi`
/// `length(ticker) >= 3` kısıtına takılırdı; önek türü de ayırır.
export function lotSecimi(
  lot: { type: string; ticker?: string | null; currency?: string | null; is_manual_price?: boolean | null },
  tur: NotTuru,
): Omit<Secilen, 'tutan'> | null {
  const ham = String(lot.ticker ?? '').trim().toUpperCase();
  const aylik = tur === 'aylik';
  if (lot.type === 'hisse') {
    if (ham.endsWith('.IS')) return { ticker: ham, varlik: 'hisse' };
    if (!aylik || lot.is_manual_price === true) return null;
    if (!/^[A-Z0-9.\-^=]{1,20}$/.test(ham)) return null;
    const para = String(lot.currency ?? '').trim().toUpperCase() || 'USD';
    return { ticker: `HISSE:${ham}`, varlik: 'yabanci_hisse', seri: ham, para };
  }
  if (lot.type === 'kripto') {
    if (!ham.startsWith('KRIPTO:') || ham === 'KRIPTO:USDT') return null;
    return { ticker: ham, varlik: 'kripto' };
  }
  if (lot.type === 'fon' || lot.type === 'bes') {
    const kod = varlikKodu(ham);
    if (!/^[A-Z0-9]{2,6}$/.test(kod)) return null;
    return { ticker: `TEFAS:${kod}`, varlik: 'fon' };
  }
  if (!aylik || lot.is_manual_price === true) return null;
  if (lot.type === 'altin') {
    // Bütün altın türleri (gram, çeyrek, cumhuriyet…) aynı gram serisinin
    // ağırlık katıdır: yüzde değişim aynı, tek not yeter (maliyet).
    return { ticker: ALTIN_ANAHTARI, varlik: 'altin', seri: ALTIN_ANAHTARI, para: 'TRY' };
  }
  if (lot.type === 'doviz') {
    if (!/^[A-Z]{3}TRY=X$/.test(ham)) return null;
    return { ticker: ham, varlik: 'doviz', seri: ham, para: 'TRY' };
  }
  if (lot.type === 'emtia') {
    if (!/^(GRAM:)?[A-Z0-9]{1,6}=F$/.test(ham)) return null;
    return { ticker: ham, varlik: 'emtia', seri: ham, para: 'USD' };
  }
  if (lot.type === 'eurobond') {
    if (!ham.startsWith(EUROBOND_ONEKI) || ham.length > 40) return null;
    const para = String(lot.currency ?? '').trim().toUpperCase() || 'USD';
    return { ticker: ham, varlik: 'eurobond', seri: ham, para };
  }
  return null;
}

export const ALTIN_ANAHTARI = 'ALTIN:GRAM';

/// Açık pozisyonlardan varlık listesi; en çok kişinin tuttuğu önce.
export async function tutulanVarliklar(
  client: SupabaseClient,
  ust: number,
  tur: NotTuru = 'haftalik',
): Promise<Secilen[]> {
  const turler = tur === 'aylik'
    ? ['fon', 'bes', 'hisse', 'kripto', ...AYLIK_EK_TURLER]
    : ['fon', 'bes', 'hisse', 'kripto'];
  const satirlar = await hepsi<PozisyonLot & { type: string; is_manual_price?: boolean | null }>((bas, son) =>
    client.from('assets')
      .select('id, user_id, type, ticker, name, sub_category, currency, quantity, kind, added_date, ref_asset_id, is_manual_price')
      .in('type', turler)
      .is('deleted_at', null)
      .order('id')
      .range(bas, son)
  );
  const tutanlar = new Map<string, { secim: Omit<Secilen, 'tutan'>; kisiler: Set<string> }>();
  for (const lot of acikPozisyonLotlari(satirlar)) {
    const secim = lotSecimi(lot, tur);
    if (!secim) continue;
    const t = tutanlar.get(secim.ticker) ?? { secim, kisiler: new Set<string>() };
    t.kisiler.add(String(lot.user_id));
    tutanlar.set(secim.ticker, t);
  }
  return [...tutanlar.values()]
    .map((t) => ({ ...t.secim, tutan: t.kisiler.size }))
    .sort((a, b) => b.tutan - a.tutan || a.ticker.localeCompare(b.ticker))
    .slice(0, ust);
}

export async function paketleriKur(
  client: SupabaseClient,
  secilen: Secilen[],
  tur: NotTuru,
  aralik: { baslangic: string; bitis: string },
  seriYukle: SeriYukleyici = (semboller) => serileriYukle(client, semboller),
): Promise<Paket[]> {
  // Dönem öncesi pay: fonda önceki gün (oran paydası, yatırımcı farkı);
  // haftalıkta ayrıca `akis_kati` için önceki 7 hafta. Hacimde 20 işlem
  // günü ortalaması (~30 takvim günü, tatil payıyla 45).
  const fonBasi = gunEkle(aralik.baslangic, tur === 'haftalik' ? -7 * ONCEKI_HAFTA - 3 : -10);
  const hacimBasi = gunEkle(aralik.baslangic, -45);
  const fonlar = secilen.filter((s) => s.varlik === 'fon');
  const hisseler = secilen.filter((s) => s.varlik === 'hisse');
  const kriptolar = secilen.filter((s) => s.varlik === 'kripto');

  const fonGunleri = new Map<string, FonGunu[]>();
  for (const p of parcala(fonlar.map((f) => f.ticker.slice('TEFAS:'.length)))) {
    const rows = await hepsi<FonGunu & { fon_kodu: string }>((bas, son) =>
      client.from('fon_akis_gunluk')
        .select('fon_kodu, tarih, net_akis, portfoy_degeri, yatirimci, fon_turu')
        .in('fon_kodu', p).gte('tarih', fonBasi).lte('tarih', aralik.bitis)
        .order('fon_kodu').order('tarih').range(bas, son)
    );
    for (const r of rows) {
      const t = `TEFAS:${r.fon_kodu}`;
      const g: FonGunu = {
        tarih: r.tarih,
        net_akis: r.net_akis === null ? null : Number(r.net_akis),
        portfoy_degeri: Number(r.portfoy_degeri),
        yatirimci: r.yatirimci === null ? null : Number(r.yatirimci),
        fon_turu: r.fon_turu,
      };
      const l = fonGunleri.get(t);
      if (l) l.push(g); else fonGunleri.set(t, [g]);
    }
  }

  const hacimGunleri = new Map<string, HacimSatiri[]>();
  for (const [tablo, liste, kolon] of [
    ['hisse_hacim_gunluk', hisseler, 'ticker, tarih, kapanis, para_hacmi'],
    ['kripto_hacim_gunluk', kriptolar, 'ticker, tarih, kapanis, para_hacmi, alici_payi'],
  ] as const) {
    for (const p of parcala(liste.map((x) => x.ticker))) {
      const rows = await hepsi<Record<string, unknown>>((bas, son) =>
        client.from(tablo).select(kolon)
          .in('ticker', p).gte('tarih', hacimBasi).lte('tarih', aralik.bitis)
          .order('ticker').order('tarih').range(bas, son)
      );
      for (const r of rows) {
        const t = String(r.ticker);
        const g: HacimSatiri = {
          tarih: String(r.tarih),
          kapanis: Number(r.kapanis),
          para_hacmi: Number(r.para_hacmi),
          alici_payi: r.alici_payi == null ? null : Number(r.alici_payi),
        };
        const l = hacimGunleri.get(t);
        if (l) l.push(g); else hacimGunleri.set(t, [g]);
      }
    }
  }

  const olaylar = new Map<string, OlaySatiri[]>();
  for (const p of parcala(secilen.map((s) => s.ticker))) {
    const rows = await hepsi<Record<string, unknown>>((bas, son) =>
      client.from('balina_olay')
        .select('ticker, tarih, tur, tutar, buyukluk_orani, ortalama_kati, fiyat_degisim, alici_payi')
        .in('ticker', p).gte('tarih', aralik.baslangic).lte('tarih', aralik.bitis)
        .order('ticker').order('tarih').range(bas, son)
    );
    for (const r of rows) {
      const sayi = (v: unknown) => (v == null ? null : Number(v));
      const o: OlaySatiri = {
        tarih: String(r.tarih), tur: String(r.tur), tutar: Number(r.tutar),
        buyukluk_orani: sayi(r.buyukluk_orani), ortalama_kati: sayi(r.ortalama_kati),
        fiyat_degisim: sayi(r.fiyat_degisim), alici_payi: sayi(r.alici_payi),
      };
      const t = String(r.ticker);
      const l = olaylar.get(t);
      if (l) l.push(o); else olaylar.set(t, [o]);
    }
  }

  const paketler: Paket[] = [];
  // Akış/hacim paketi çıkmayan (aylıkta) ve zaten fiyat ölçülü varlıklar.
  const fiyatla: Secilen[] = [];
  for (const s of secilen) {
    if (s.varlik === 'fon') {
      // Kategori sırası yalnız haftalıkta: RPC en çok 14 günlük aralık alır
      // (kart ile aynı sorgu; aylıkta "ay boyu sıra" ayrı bir ölçüm olurdu).
      let sira: KategoriSirasi = null;
      if (tur === 'haftalik' && fonGunleri.has(s.ticker)) {
        const { data, error } = await client.rpc('fon_kategori_akis_sirasi', {
          p_fon_kodu: s.ticker.slice('TEFAS:'.length),
          p_baslangic: aralik.baslangic,
          p_bitis: aralik.bitis,
        });
        if (error) console.error('analiz-hazirla: kategori sirasi', s.ticker, error.code);
        const kendi = (data as Array<{ sira: number; kendi: boolean; fon_sayisi: number }> | null)
          ?.find((r) => r.kendi);
        if (kendi) sira = { sira: Number(kendi.sira), fonSayisi: Number(kendi.fon_sayisi) };
      }
      const p = fonPaketi(s.ticker, tur, aralik, fonGunleri.get(s.ticker) ?? [],
        olaylar.get(s.ticker) ?? [], sira);
      if (p) paketler.push(p);
      else if (tur === 'aylik') fiyatla.push(s);
    } else if (s.varlik === 'hisse' || s.varlik === 'kripto') {
      const p = hacimPaketi(s.ticker, s.varlik, tur, aralik, hacimGunleri.get(s.ticker) ?? [],
        olaylar.get(s.ticker) ?? []);
      if (p) paketler.push(p);
      else if (tur === 'aylik') fiyatla.push(s);
    } else {
      fiyatla.push(s);
    }
  }
  if (fiyatla.length > 0) paketler.push(...await fiyatPaketleri(fiyatla, tur, aralik, seriYukle));
  return paketler;
}

/// Sembol kümesi → tarihli seri. Ağ işi; test sahte yükleyici verir.
export type SeriYukleyici = (semboller: Set<string>) => Promise<Map<string, Seri>>;

/// `loadDatedHistories` ile aynı (sembol başına tek istek, 8'li paralel,
/// boş seri haritaya girmez); tek fark eurobond TEMİZ fiyattan
/// (`fetchEurobondDated` [temiz] notu: kupon günü sahte düşüş olmasın).
async function serileriYukle(client: SupabaseClient, semboller: Set<string>): Promise<Map<string, Seri>> {
  const out = new Map<string, Seri>();
  const liste = [...semboller];
  for (let i = 0; i < liste.length; i += 8) {
    const sonuc = await Promise.all(liste.slice(i, i + 8).map(async (sembol) => {
      try {
        const seri = sembol.startsWith(EUROBOND_ONEKI)
          ? await fetchEurobondDated(client, sembol, fetch, true)
          : await fetchDatedSeries(client, sembol);
        return [sembol, seri] as const;
      } catch (_) {
        return [sembol, [] as Seri] as const;
      }
    }));
    for (const [sembol, seri] of sonuc) if (seri.length > 0) out.set(sembol, seri);
  }
  return out;
}

const GC_F = 'GC=F';
const USDTRY = 'USDTRY=X';

/// Gram altın TL serisi: GC=F (USD/ons) × aynı günün USDTRY'si ÷ 31,1035.
/// Kuru olmayan gün seriye girmez (uydurma nokta yok). Yalnız yüzde
/// ölçüldüğü için 22/24 ayar ve ağırlık çarpanı sonucu değiştirmez.
export function altinGramSerisi(ons: Seri, kur: Seri): Seri {
  const gun = (ms: number) => new Date(ms).toISOString().slice(0, 10);
  const kurGunu = new Map(kur.map(([t, v]) => [gun(t), v] as const));
  const out: Seri = [];
  for (const [t, v] of ons) {
    const k = kurGunu.get(gun(t));
    if (k !== undefined && k > 0) out.push([t, (v * k) / ONS_GRAM]);
  }
  return out;
}

function fiyatKaynagi(s: Secilen): Olcum['kaynak'] {
  if (s.varlik === 'fon') return 'TEFAS';
  if (s.varlik === 'kripto') return 'Binance';
  if (s.varlik === 'eurobond') return 'Börse Frankfurt';
  return 'Yahoo Finance';
}

/// Fiyat paketli varlıkların serilerini TEK seferde (sembol başına bir
/// istek, 8'li paralel) çeker ve paketleri kurar. Seri boşsa paket yok.
export async function fiyatPaketleri(
  secilen: Secilen[],
  tur: NotTuru,
  aralik: { baslangic: string; bitis: string },
  seriYukle: SeriYukleyici,
): Promise<Paket[]> {
  const semboller = new Set<string>();
  for (const s of secilen) {
    if (s.varlik === 'altin') { semboller.add(GC_F); semboller.add(USDTRY); continue; }
    // Fon/hisse/kripto yedeği: not anahtarı zaten seri sembolüdür.
    semboller.add(s.seri ?? s.ticker);
    if (s.para && s.para !== 'TRY') semboller.add(`${s.para}TRY=X`);
  }
  const seriler = await seriYukle(semboller);
  const out: Paket[] = [];
  for (const s of secilen) {
    const seri = s.varlik === 'altin'
      ? altinGramSerisi(seriler.get(GC_F) ?? [], seriler.get(USDTRY) ?? [])
      : seriler.get(s.seri ?? s.ticker) ?? [];
    if (seri.length === 0) continue;
    const para = s.para ?? 'TRY';
    const p = fiyatPaketi({
      ticker: s.ticker, kod: notKodu(s.ticker), varlik: s.varlik, tur, aralik, seri, para,
      kur: para === 'TRY' ? null : seriler.get(`${para}TRY=X`) ?? null,
      kaynak: fiyatKaynagi(s),
    });
    if (p) out.push(p);
  }
  return out;
}

/// Modele ve `girdi.kod`'a giden kısa ad. Yalnız sembol: kullanıcının
/// yazdığı varlık adı modele GİTMEZ (kişisel veri kuralı).
export function notKodu(ticker: string): string {
  if (ticker === ALTIN_ANAHTARI) return 'Gram altın';
  const t = ticker.replace(/^(TEFAS|KRIPTO|HISSE|EUROBOND):/, '').replace(/\.IS$/, '');
  const d = /^([A-Z]{3})TRY=X$/.exec(t);
  return d ? `${d[1]}/TRY` : t;
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return jsonResponse({ ok: false }, 405);

  try {
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');
    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }

    let tur: NotTuru = 'haftalik';
    let dryRun = false;
    let bugun = trGun(new Date());
    try {
      const body = await request.json();
      if (body?.tur === 'aylik') tur = 'aylik';
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.bugun === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.bugun)) bugun = body.bugun;
    } catch (_) { /* gövde opsiyonel */ }

    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!apiKey && !dryRun) {
      console.error('analiz-hazirla: ANTHROPIC_API_KEY tanimli degil, gonderilmedi.');
      return jsonResponse({ ok: false, neden: 'anahtar_yok' }, 503);
    }

    const aralik = tur === 'haftalik' ? haftaAraligi(bugun) : ayAraligi(bugun);
    // Haftalık: anlatılan haftanın Pazartesi'si; aylık: ayın 1'i.
    const donem = aralik.baslangic;
    const client: SupabaseClient = createClient(supabaseUrl, serviceRoleKey);

    // Haber yalnız aylık notta ve yalnız secret tam "1" iken (fail-closed).
    const haberAcik = tur === 'aylik' && haberAcikMi(Deno.env.get('ANALIZ_HABER_ACIK'));

    // Aynı dönem iki kez gönderilmez; not ve haber defteri ayrı (`amac`).
    // Not gitmiş, haber gitmemişse (bayrak ay içinde açıldı, haber batch'i
    // düştü) yalnız haber gider.
    const defterdeVar = async (amac: 'not' | 'haber') => {
      const { data, error } = await client.from('analiz_batch')
        .select('id').eq('tur', tur).eq('donem', donem).eq('amac', amac).neq('durum', 'hata').limit(1);
      if (error) throw error;
      return (data ?? []).length > 0;
    };
    const notGerekli = dryRun || !(await defterdeVar('not'));
    const haberGerekli = haberAcik && (dryRun || !(await defterdeVar('haber')));
    if (!notGerekli && !haberGerekli) return jsonResponse({ ok: true, atlandi: 'donem_gonderildi' });

    const ust = Number(Deno.env.get('ANALIZ_VARLIK_USTU') ?? '300') || 300;
    const secilen = await tutulanVarliklar(client, ust, tur);
    const paketler = await paketleriKur(client, secilen, tur, aralik);
    if (paketler.length === 0) return jsonResponse({ ok: true, varlik: secilen.length, istek: 0 });

    // Ay içi harcama (UTC ay başı; tavan kabaca, kuruş hassasiyeti gerekmez).
    // Not maliyeti satırlarda; haber maliyeti (arama dahil) haber batch'inin
    // defter satırında (0177). Haber sütunu okunamazsa (migration henüz
    // yoksa) not yolu durmaz: haber maliyeti 0 sayılır, hata loglanır.
    const ayBasi = new Date();
    ayBasi.setUTCDate(1);
    ayBasi.setUTCHours(0, 0, 0, 0);
    const harcamalar = await hepsi<{ maliyet_usd: number | null }>((bas, son) =>
      client.from('varlik_analizi').select('maliyet_usd')
        .gte('olusturuldu', ayBasi.toISOString()).range(bas, son)
    );
    let harcama = harcamalar.reduce((t, r) => t + Number(r.maliyet_usd ?? 0), 0);
    try {
      const haberler = await hepsi<{ maliyet_usd: number | null }>((bas, son) =>
        client.from('analiz_batch').select('maliyet_usd').eq('amac', 'haber')
          .gte('olusturuldu', ayBasi.toISOString()).range(bas, son)
      );
      harcama += haberler.reduce((t, r) => t + Number(r.maliyet_usd ?? 0), 0);
    } catch (e) {
      console.error('analiz-hazirla: haber harcamasi okunamadi', (e as { code?: string })?.code);
    }
    const tavan = Number(Deno.env.get('ANALIZ_AYLIK_TAVAN_USD') ?? '50');
    const model = tavanaGoreModel(MODEL[tur], harcama, tavan);
    // Model tavan yüzünden indiyse haber yok: arama ücreti modelden bağımsız
    // ve tavan zaten aşılmış.
    const haberGidecek = haberGerekli && model === MODEL[tur] &&
      haberTavaniUygun(harcama, tavan, paketler.length);
    if (haberGerekli && !haberGidecek) console.error('analiz-hazirla: haber tavan nedeniyle gonderilmedi');

    const istekler = paketler.map((p) => ({ custom_id: ozelKimlik(p.ticker), params: istekGovdesi(p, model) }));
    const haberIstekleri = haberGidecek
      ? paketler.map((p) => ({ custom_id: ozelKimlik(p.ticker), params: haberIstegi(p, aralik, model) }))
      : [];
    if (dryRun) {
      return jsonResponse({
        ok: true, dry_run: true, tur, donem, aralik, model, varlik: secilen.length,
        istek: istekler.length, ornek: istekler[0],
        // Bayrak kapalıyken alan hiç yok (yanıt #317 ile aynı).
        ...(haberAcik ? { haber: { istek: haberIstekleri.length, ornek: haberIstekleri[0] ?? null } } : {}),
        // Yalnız piyasa ölçümleri; kişisel veri yok.
        paketler: paketler.map((p) => ({
          ticker: p.ticker, rozet: p.rozet, olaylar: p.olaylar,
          olcumler: Object.fromEntries(p.olcumler.map((o) => [o.anahtar, o.gosterim])),
        })),
      });
    }

    const anthropic = new Anthropic({ apiKey });
    let notIstek = 0;
    if (notGerekli) {
      // `output_config` SDK sürümünün tiplerinde olmayabilir; gövde API'ye aynen gider.
      // deno-lint-ignore no-explicit-any
      const batch = await anthropic.messages.batches.create({ requests: istekler as any });

      const girdiler = Object.fromEntries(paketler.map((p) => [ozelKimlik(p.ticker), p]));
      const { error: yazErr } = await client.from('analiz_batch').insert({
        id: batch.id, tur, donem, istek_sayisi: istekler.length, girdiler, model,
      });
      if (yazErr) {
        // Batch gitti ama defter yazılamadı: sonuç toplanamaz, boşa para.
        // İptal et; bir sonraki tetik yeniden dener.
        console.error('analiz-hazirla: analiz_batch yazilamadi', yazErr.code);
        await anthropic.messages.batches.cancel(batch.id).catch(() => {});
        return jsonResponse({ ok: false }, 500);
      }
      notIstek = istekler.length;
    }

    // Haber batch'i notun ardından ve ondan bağımsız: düşerse not etkilenmez,
    // bir sonraki tetik yalnız haberi yeniden dener.
    let haberIstek = 0;
    if (haberIstekleri.length > 0) {
      try {
        // deno-lint-ignore no-explicit-any
        const hb = await anthropic.messages.batches.create({ requests: haberIstekleri as any });
        const girdiler = Object.fromEntries(paketler.map((p) => [ozelKimlik(p.ticker), haberGirdisi(p, aralik)]));
        const { error: yazErr } = await client.from('analiz_batch').insert({
          id: hb.id, tur, donem, istek_sayisi: haberIstekleri.length, girdiler, model, amac: 'haber',
        });
        if (yazErr) {
          console.error('analiz-hazirla: haber defteri yazilamadi', yazErr.code);
          await anthropic.messages.batches.cancel(hb.id).catch(() => {});
        } else {
          haberIstek = haberIstekleri.length;
        }
      } catch (e) {
        console.error('analiz-hazirla: haber batch gonderilemedi', (e as { status?: number })?.status);
      }
    }
    return jsonResponse({
      ok: true, tur, donem, model, istek: notIstek,
      ...(haberAcik ? { haber_istek: haberIstek } : {}),
    });
  } catch (err) {
    console.error('analiz-hazirla', err);
    return jsonResponse({ ok: false }, 500);
  }
});
