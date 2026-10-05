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
import {
  ayAraligi,
  FonGunu,
  fonPaketi,
  ONCEKI_HAFTA,
  haftaAraligi,
  HacimSatiri,
  hacimPaketi,
  istekGovdesi,
  KategoriSirasi,
  NotTuru,
  OlaySatiri,
  ozelKimlik,
  Paket,
  tavanaGoreModel,
} from '../_shared/analiz.ts';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const MODEL: Record<NotTuru, string> = {
  haftalik: 'claude-sonnet-5-5',
  aylik: 'claude-opus-5-5',
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

type Secilen = { ticker: string; varlik: 'fon' | 'hisse' | 'kripto'; tutan: number };

/// Açık pozisyonlardan varlık listesi; en çok kişinin tuttuğu önce.
export async function tutulanVarliklar(client: SupabaseClient, ust: number): Promise<Secilen[]> {
  const satirlar = await hepsi<PozisyonLot & { type: string }>((bas, son) =>
    client.from('assets')
      .select('id, user_id, type, ticker, name, sub_category, currency, quantity, kind, added_date, ref_asset_id')
      .in('type', ['fon', 'bes', 'hisse', 'kripto'])
      .is('deleted_at', null)
      .order('id')
      .range(bas, son)
  );
  const tutanlar = new Map<string, { varlik: Secilen['varlik']; kisiler: Set<string> }>();
  for (const lot of acikPozisyonLotlari(satirlar)) {
    const ham = String(lot.ticker ?? '').trim().toUpperCase();
    let ticker: string;
    let varlik: Secilen['varlik'];
    if (lot.type === 'hisse') {
      if (!ham.endsWith('.IS')) continue;
      ticker = ham; varlik = 'hisse';
    } else if (lot.type === 'kripto') {
      if (!ham.startsWith('KRIPTO:') || ham === 'KRIPTO:USDT') continue;
      ticker = ham; varlik = 'kripto';
    } else {
      const kod = varlikKodu(ham);
      if (!/^[A-Z0-9]{2,6}$/.test(kod)) continue;
      ticker = `TEFAS:${kod}`; varlik = 'fon';
    }
    const t = tutanlar.get(ticker) ?? { varlik, kisiler: new Set<string>() };
    t.kisiler.add(String(lot.user_id));
    tutanlar.set(ticker, t);
  }
  return [...tutanlar.entries()]
    .map(([ticker, t]) => ({ ticker, varlik: t.varlik, tutan: t.kisiler.size }))
    .sort((a, b) => b.tutan - a.tutan || a.ticker.localeCompare(b.ticker))
    .slice(0, ust);
}

export async function paketleriKur(
  client: SupabaseClient,
  secilen: Secilen[],
  tur: NotTuru,
  aralik: { baslangic: string; bitis: string },
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
    } else {
      const p = hacimPaketi(s.ticker, s.varlik, tur, aralik, hacimGunleri.get(s.ticker) ?? [],
        olaylar.get(s.ticker) ?? []);
      if (p) paketler.push(p);
    }
  }
  return paketler;
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

    if (!dryRun) {
      const { data: onceki, error } = await client.from('analiz_batch')
        .select('id').eq('tur', tur).eq('donem', donem).neq('durum', 'hata').limit(1);
      if (error) throw error;
      if ((onceki ?? []).length > 0) return jsonResponse({ ok: true, atlandi: 'donem_gonderildi' });
    }

    const ust = Number(Deno.env.get('ANALIZ_VARLIK_USTU') ?? '300') || 300;
    const secilen = await tutulanVarliklar(client, ust);
    const paketler = await paketleriKur(client, secilen, tur, aralik);
    if (paketler.length === 0) return jsonResponse({ ok: true, varlik: secilen.length, istek: 0 });

    // Ay içi harcama (UTC ay başı; tavan kabaca, kuruş hassasiyeti gerekmez).
    const ayBasi = new Date();
    ayBasi.setUTCDate(1);
    ayBasi.setUTCHours(0, 0, 0, 0);
    const harcamalar = await hepsi<{ maliyet_usd: number | null }>((bas, son) =>
      client.from('varlik_analizi').select('maliyet_usd')
        .gte('olusturuldu', ayBasi.toISOString()).range(bas, son)
    );
    const harcama = harcamalar.reduce((t, r) => t + Number(r.maliyet_usd ?? 0), 0);
    const tavan = Number(Deno.env.get('ANALIZ_AYLIK_TAVAN_USD') ?? '50');
    const model = tavanaGoreModel(MODEL[tur], harcama, tavan);

    const istekler = paketler.map((p) => ({ custom_id: ozelKimlik(p.ticker), params: istekGovdesi(p, model) }));
    if (dryRun) {
      return jsonResponse({
        ok: true, dry_run: true, tur, donem, aralik, model, varlik: secilen.length,
        istek: istekler.length, ornek: istekler[0],
        // Yalnız piyasa ölçümleri; kişisel veri yok.
        paketler: paketler.map((p) => ({
          ticker: p.ticker, rozet: p.rozet, olaylar: p.olaylar,
          olcumler: Object.fromEntries(p.olcumler.map((o) => [o.anahtar, o.gosterim])),
        })),
      });
    }

    const anthropic = new Anthropic({ apiKey });
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
    return jsonResponse({ ok: true, tur, donem, model, istek: istekler.length });
  } catch (err) {
    console.error('analiz-hazirla', err);
    return jsonResponse({ ok: false }, 500);
  }
});
