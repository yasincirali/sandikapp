// Akış Gözlem Edge Function — FON PARA AKIŞI VE BÜYÜK GİRİŞ/ÇIKIŞ TESPİTİ
//
// pg_cron ile günde dört kez koşar (0103_fon_akisi.sql). TEFAS'ın büyüklük
// ucundan her fonun günlük pay adedini ve toplam değerini okur, net para
// akışını hesaplayıp `fon_akis_gunluk`'a yazar; kurala uyan günleri
// `balina_olay`'a işler. Kural ve hesap `_shared/balina.ts`'te (saf, testli).
//
// ── Neden sunucuda ──────────────────────────────────────────────────────────
// Uç, tek istekte TÜM fonları döndürüyor (~375 KB). 8 haftalık grafik için
// cihazın 40 günü ayrı ayrı çekmesi ~15 MB eder; ayrıca kart, olay listesi ve
// ileride bildirim AYNI satırı okumalı (tutarsız sayı gösteremeyiz). Bu
// yüzden veri bir kez burada çekilir, herkes tablodan okur.
//
// ── Maliyet tasarımı ────────────────────────────────────────────────────────
//   · Kullanıcı ya da fon başına değil GÜN başına istek: gün × 2 (yatırım +
//     emeklilik). Sıradan bir turda 2–3 gün = 4–6 istek.
//   · Kesinleşmiş gün bir daha sorulmaz (`fon_akis_tur.kesin`). Yalnız son
//     iki gün her tur yeniden çekilir: TEFAS fiyatları fon fon yayınlıyor.
//   · İlk kurulumda 130 günlük pencere tur başına 14 günle, birkaç turda dolar.
//   · Yatırımcı sayısı ayrı uçta ve fon başına; yalnız portföylerde tutulan
//     fonlar için ve o günün sayısı henüz yoksa sorulur.
//
// ── Sıra neden eskiden yeniye ───────────────────────────────────────────────
// Bir günün akışı önceki günün payına bakar. Bir gün çekilemezse tur ORADA
// durur; sonraki günü yazmak, iki günün akışını tek güne yığardı.
//
// ── Secret ──────────────────────────────────────────────────────────────────
// `TEFAS_NAV_CRON_SECRET` PAYLAŞILIR (emsal: yurt-ici-kotasyon ↔ fiyat
// alarmı, 0101): ikisi de TEFAS'tan salt-okur veri çeken işler.
//
// Yanıt `{ ok, gun, satir, olay, yatirimci }`. Gövde `{ "dry_run": true }` →
// ilk günü TEFAS'tan okur, yazmaz. Hata mesajı, token, ham TEFAS yanıtı
// DÖNMEZ (CLAUDE.md "Sunucu").

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { fonKodlari, trGun } from '../_shared/tefas_nav.ts';
import {
  AkisIstatistigi,
  AkisSatiri,
  balinaOlayi,
  BuyuklukSatiri,
  buyuklukSatirlari,
  cekilecekGunler,
  gunEkle,
  gunKesinMi,
  gunSatirlari,
  OLAY_PENCERE_GUN,
  PENCERE_GUN,
  tefasGunParam,
  yatirimciSayisi,
} from '../_shared/balina.ts';

const corsHeaders = {
  // Tarayıcı çağrısı yok — cron/pg_net sunucudan sunucuya; Allow-Origin yok.
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, x-cron-secret',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

const USER_AGENT =
  'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 ' +
  '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const TEFAS = 'https://www.tefas.gov.tr/api/funds';
const FON_TIPLERI = ['YAT', 'EMK'] as const;

/// Saklama süresi (gün). Kart 8 hafta gösterir; bir yıllık pay ileride
/// "geçen yıla göre" kıyasına ve teşhise yeter.
const SAKLAMA_GUN = 400;

/// Ardışık TEFAS istekleri arası bekleme. Uç art arda isteklerde bağlantıyı
/// kesiyor (ölçüldü 2026-10-04); gün başına iki istek için bedeli küçük.
const ISTEK_ARASI_MS = 400;

/// Bu süreden sonra yeni güne başlanmaz; kalan sonraki tura kalır
/// (edge function sınırı 150 sn, tetikleyici zaman aşımı 140 sn).
const TUR_SURE_USTU_MS = 95_000;

/// Tur başına yatırımcı sayısı sorulacak en fazla fon (bkz. TUR_KOD_USTU).
const YATIRIMCI_KOD_USTU = 150;

/// PostgREST sayfa boyu (barındırılan projede üst sınır 1000).
const SAYFA = 1000;

const bekle = (ms: number) => new Promise((r) => setTimeout(r, ms));

async function tefasPost(yol: string, govde: unknown): Promise<unknown[] | null> {
  try {
    const res = await fetch(`${TEFAS}/${yol}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Accept: 'application/json, text/plain, */*',
        'User-Agent': USER_AGENT,
      },
      body: JSON.stringify(govde),
      signal: AbortSignal.timeout(25_000),
    });
    if (!res.ok) return null;
    const data = await res.json();
    // Uç hatayı 200 + `errorMessage` ile bildiriyor; boş listeyle karışmasın.
    if (data?.errorMessage) return null;
    return Array.isArray(data?.resultList) ? data.resultList : [];
  } catch (_) {
    return null;
  }
}

/// Bir günün tüm fonları. `null` = çekilemedi (tur durur), `[]` = o gün
/// fiyat yok (tatil ya da henüz yayınlanmadı).
function gunBuyuklukleri(fonTipi: string, gun: string): Promise<BuyuklukSatiri[] | null> {
  const t = tefasGunParam(gun);
  return tefasPost('fonBuyuklukBazliBilgiGetir', {
    dil: 'TR',
    fonTipi,
    kurucuKodu: null,
    sfonTurKod: null,
    fonTurAciklama: null,
    islem: 1,
    fonTurKod: null,
    fonGrubu: null,
    // Aynı gün iki uçta: `son*` alanları o günün değeri olur.
    basTarih: t,
    bitTarih: t,
    calismaTipi: 2,
  }).then((liste) => (liste === null ? null : buyuklukSatirlari(liste)));
}

/// Bir sorgunun tüm sayfalarını toplar.
async function tumSayfalar<T>(
  sayfa: (bas: number, son: number) => PromiseLike<{ data: T[] | null; error: unknown }>,
): Promise<T[]> {
  const out: T[] = [];
  for (let bas = 0; ; bas += SAYFA) {
    const { data, error } = await sayfa(bas, bas + SAYFA - 1);
    if (error) throw error;
    out.push(...(data ?? []));
    if ((data ?? []).length < SAYFA) return out;
  }
}

async function parcaliUpsert(
  client: SupabaseClient,
  tablo: string,
  satirlar: unknown[],
  onConflict: string,
) {
  for (let i = 0; i < satirlar.length; i += 500) {
    const { error } = await client
      .from(tablo)
      .upsert(satirlar.slice(i, i + 500), { onConflict });
    if (error) throw error;
  }
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('TEFAS_NAV_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503 (bkz. cron_auth.ts). Sonra header kontrolü.
    const eksik = cronSecretZorunlu(cronSecret, 'TEFAS_NAV_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Env denetimi kapıdan SONRA: yetkisiz çağıran eksik yapılandırmayı
    // öğrenemesin (observe-tefas-nav ile aynı sıra).
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch (_) { /* gövde opsiyonel */ }

    const client = createClient(supabaseUrl, serviceRoleKey);
    const basladi = Date.now();
    const bugun = trGun(new Date());
    const pencereBasi = gunEkle(bugun, -PENCERE_GUN);

    // 1) Hangi günler çekilecek.
    const { data: turRows, error: turErr } = await client
      .from('fon_akis_tur')
      .select('tarih')
      .eq('kesin', true)
      .gte('tarih', pencereBasi);
    if (turErr) throw turErr;
    const kesin = new Set((turRows ?? []).map((r) => String(r.tarih)));
    const gunler = cekilecekGunler(bugun, kesin);

    if (dryRun) {
      const ilk = gunler.length > 0 ? await gunBuyuklukleri('YAT', gunler[0]) : [];
      return jsonResponse({
        ok: ilk !== null,
        dry_run: true,
        gun: gunler.length,
        satir: ilk?.length ?? 0,
      });
    }

    // 2) İlk günden ÖNCEKİ son verili günün payları — akışın çıpası.
    const oncekiPay = new Map<string, number>();
    if (gunler.length > 0) {
      const { data: oncekiGun, error: ogErr } = await client
        .from('fon_akis_tur')
        .select('tarih')
        .lt('tarih', gunler[0])
        .gt('fon_sayisi', 0)
        .order('tarih', { ascending: false })
        .limit(1)
        .maybeSingle();
      if (ogErr) throw ogErr;
      if (oncekiGun?.tarih) {
        const rows = await tumSayfalar<{ fon_kodu: string; pay_adedi: number }>((bas, son) =>
          client
            .from('fon_akis_gunluk')
            .select('fon_kodu, pay_adedi')
            .eq('tarih', String(oncekiGun.tarih))
            .order('fon_kodu')
            .range(bas, son)
        );
        for (const r of rows) oncekiPay.set(String(r.fon_kodu), Number(r.pay_adedi));
      }
    }

    // 3) Günleri eskiden yeniye çek, yaz, olayları işle.
    let islenenGun = 0;
    let yazilanGun = 0;
    let yazilanSatir = 0;
    let yazilanOlay = 0;
    let sonVeriliGun: string | null = null;

    for (const gun of gunler) {
      if (Date.now() - basladi > TUR_SURE_USTU_MS) break;

      const satirlar: AkisSatiri[] = [];
      let basarisiz = false;
      for (const tip of FON_TIPLERI) {
        await bekle(ISTEK_ARASI_MS);
        const liste = await gunBuyuklukleri(tip, gun);
        if (liste === null) {
          basarisiz = true;
          break;
        }
        satirlar.push(...gunSatirlari(gun, tip, liste, oncekiPay));
      }
      // Çekilemeyen günde DUR: sonraki günü yazmak iki günün akışını tek
      // güne yığardı. Bu gün deftere yazılmaz, sonraki tur yeniden dener.
      if (basarisiz) break;

      const kesinMi = gunKesinMi(gun, bugun);
      if (satirlar.length === 0) {
        // Fiyat yok. Yeterince eskiyse tatildir (bir daha sorma); yeniyse
        // henüz yayınlanmamış olabilir — deftere yazma, sonraki tur sorar.
        if (kesinMi) {
          const { error } = await client
            .from('fon_akis_tur')
            .upsert({ tarih: gun, fon_sayisi: 0, kesin: true, cekildi: new Date().toISOString() });
          if (error) throw error;
        }
        islenenGun++;
        continue;
      }

      await parcaliUpsert(client, 'fon_akis_gunluk', satirlar, 'fon_kodu,tarih');

      // Olaylar: yalnız kartın gösterdiği pencere için. Günün olayları
      // silinip yeniden yazılır — yeniden çekilen günde artık kurala uymayan
      // bir satır listede asılı kalmasın.
      if (gun >= gunEkle(bugun, -OLAY_PENCERE_GUN)) {
        const istRows = await tumSayfalar<{ fon_kodu: string; gozlem: number; sapma: number | null; en_buyuk: number | null }>(
          (bas, son) => client.rpc('akis_sapma', { p_gun: gun }).order('fon_kodu').range(bas, son),
        );
        const ist = new Map<string, AkisIstatistigi>();
        for (const r of istRows) {
          ist.set(String(r.fon_kodu), {
            gozlem: Number(r.gozlem),
            sapma: r.sapma === null ? null : Number(r.sapma),
            enBuyuk: r.en_buyuk === null ? null : Number(r.en_buyuk),
          });
        }
        const olaylar = [];
        for (const s of satirlar) {
          const o = balinaOlayi(s.net_akis, s.portfoy_degeri, ist.get(s.fon_kodu), s.fon_turu);
          if (o !== null) olaylar.push({ ticker: `TEFAS:${s.fon_kodu}`, tarih: gun, ...o });
        }
        const { error: silErr } = await client
          .from('balina_olay')
          .delete()
          .eq('tarih', gun)
          .in('tur', ['fon_giris', 'fon_cikis']);
        if (silErr) throw silErr;
        if (olaylar.length > 0) {
          await parcaliUpsert(client, 'balina_olay', olaylar, 'ticker,tarih');
        }
        yazilanOlay += olaylar.length;
      }

      // Defter EN SON: yazma yarıda kalırsa gün "çekilmemiş" kalır.
      const { error: defterErr } = await client.from('fon_akis_tur').upsert({
        tarih: gun,
        fon_sayisi: satirlar.length,
        kesin: kesinMi,
        cekildi: new Date().toISOString(),
      });
      if (defterErr) throw defterErr;

      islenenGun++;
      yazilanGun++;
      yazilanSatir += satirlar.length;
      sonVeriliGun = gun;
    }

    // 4) Yatırımcı sayısı — yalnız portföylerde tutulan fonlar, yalnız en
    //    yeni gün. Geçmiş güne yazılmaz (uç tarih vermiyor).
    let yazilanYatirimci = 0;
    const { data: enYeni, error: eyErr } = await client
      .from('fon_akis_tur')
      .select('tarih')
      .gt('fon_sayisi', 0)
      .order('tarih', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (eyErr) throw eyErr;
    const yatirimciGunu = sonVeriliGun ?? (enYeni?.tarih ? String(enYeni.tarih) : null);

    if (yatirimciGunu !== null && yatirimciGunu === String(enYeni?.tarih ?? '')) {
      const { data: assetRows, error: assetErr } = await client
        .from('assets')
        .select('ticker')
        .in('type', ['fon', 'bes'])
        .like('ticker', 'TEFAS:%')
        .is('deleted_at', null);
      if (assetErr) throw assetErr;
      const kodlar = fonKodlari((assetRows ?? []).map((r) => String(r.ticker ?? '')));

      if (kodlar.length > 0) {
        const { data: gunRows, error: grErr } = await client
          .from('fon_akis_gunluk')
          .select('fon_kodu, portfoy_degeri, yatirimci')
          .eq('tarih', yatirimciGunu)
          .in('fon_kodu', kodlar);
        if (grErr) throw grErr;
        const sorulacak = (gunRows ?? [])
          .filter((r) => r.yatirimci === null)
          .slice(0, YATIRIMCI_KOD_USTU);

        const CONCURRENCY = 4;
        for (let i = 0; i < sorulacak.length; i += CONCURRENCY) {
          if (Date.now() - basladi > TUR_SURE_USTU_MS + 20_000) break;
          const batch = sorulacak.slice(i, i + CONCURRENCY);
          const sonuclar = await Promise.all(batch.map(async (r) => ({
            kod: String(r.fon_kodu),
            kisi: yatirimciSayisi(
              await tefasPost('fonBilgiGetir', { fonKodu: r.fon_kodu, dil: 'TR', periyod: 1 }),
              Number(r.portfoy_degeri),
            ),
          })));
          for (const { kod, kisi } of sonuclar) {
            if (kisi === null) continue;
            const { error } = await client
              .from('fon_akis_gunluk')
              .update({ yatirimci: kisi })
              .eq('fon_kodu', kod)
              .eq('tarih', yatirimciGunu);
            if (error) throw error;
            yazilanYatirimci++;
          }
          await bekle(ISTEK_ARASI_MS);
        }
      }
    }

    // 5) Saklama.
    const sinir = gunEkle(bugun, -SAKLAMA_GUN);
    for (const tablo of ['fon_akis_gunluk', 'balina_olay', 'fon_akis_tur']) {
      const { error } = await client.from(tablo).delete().lt('tarih', sinir);
      if (error) throw error;
    }

    return jsonResponse({
      ok: true,
      gun: yazilanGun,
      satir: yazilanSatir,
      olay: yazilanOlay,
      yatirimci: yazilanYatirimci,
      // Bu turda sırada bekleyen gün kaldı mı (ilk kurulumda true döner).
      kalan: Math.max(0, gunler.length - islenenGun),
    });
  } catch (err) {
    // Hata ayrıntısı yalnızca sunucu günlüğünde; yanıt sabit.
    console.error('akis-gozlem', err);
    return jsonResponse({ ok: false }, 500);
  }
});
