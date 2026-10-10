// Fon kalem raporu — KAP aylık Portföy Dağılım Raporu'ndan fon kalemleri
// (Fon X-Ray Katman A, 0132).
//
// pg_cron ayın 8-12'si günde dört tur `trigger_fon_kalem_raporu()` ile
// çağırır. Her turda:
//   1. Kullanıcıların BUGÜN tuttuğu fon/BES kodları (kim tuttuğu değil).
//   2. Bu dönem için işlenmemiş (ne `gecti` ne `red`) olanlar.
//   3. KAP liste taraması (gün başına bir kez, `fon_kalem_taramasi`).
//   4. En çok [TUR_USTU] fon: ek → PDF → metin → model → BEŞ KONTROL → yaz.
//
// ── Bayrak (varsayılan KAPALI) ──────────────────────────────────────────────
// `FON_KALEM_ACIK=1` function secret'ı yoksa fonksiyon cron kapısından
// sonra hiçbir şey yapmaz: KAP'a, TEFAS'a, modele gitmez, tabloya yazmaz.
// İstemci tarafı ayrıca `fon_xray_kalem` Remote Config bayrağına bağlı.
//
// ── Neden yalnız tutulan fonlar ─────────────────────────────────────────────
// KAP veri yayınının ticari kanalı lisanslı (araştırma raporu, hukuki risk):
// riski küçülten önlemler — yalnız kullanıcıların tuttuğu fonlar, fon ve ay
// başına TEK indirme, kaynak + tarih etiketi, KAP bildirimine bağlantı.
//
// ── Kişisel veri ────────────────────────────────────────────────────────────
// Modele giden yalnız kamuya açık KAP belgesinin metni. Yasal metne dokunmaz
// (araştırma: "ayrıştırmada bir LLM kullanılsa bile ona giden şey kullanıcı
// verisi değil, kamu belgesi").
//
// ── Geçici hata ≠ red ───────────────────────────────────────────────────────
// Ağ hatası, 429, zaman aşımı → hiçbir şey yazılmaz, sonraki tur yeniden
// dener. Yalnız belgenin kendisi kontrolden düşerse `red` yazılır (aynı ay
// için bir daha para harcanmaz).
//
// Gövde: `{ dry_run?: true, bugun?: 'YYYY-MM-DD' }`. `dry_run` listeyi tarar,
// kuyruğu döndürür, PDF indirmez ve modele gitmez. Yanıtta `error.message`,
// ham model yanıtı, PDF metni DÖNMEZ.

import { createClient, SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { acikPozisyonLotlari, PozisyonLot } from '../_shared/positions.ts';
import { varlikKodu } from '../_shared/haftalik_akis.ts';
import { maliyetUsd } from '../_shared/analiz.ts';
import { hataOzeti } from '../_shared/ekstre_esleme.ts';
import {
  ayristir,
  FON_TIPLERI,
  FonTipi,
  gunVeyaOncesi,
  ISTEK_BASLIKLARI,
  istekGovdesi as tefasGovdesi,
  TEFAS_DAGILIM_URL,
  trGunu,
} from '../_shared/fon_dagilim.ts';
import {
  bildirimAdresi,
  dogrula,
  donemBildirimleri,
  ekPdfNesnesi,
  istekGovdesi,
  KAP_LISTE_USTU,
  KAP_TABAN,
  metinYeterliMi,
  pdfBaytlari,
  PdrSatiri,
  pdrSatirlari,
  oncekiAySonu,
  taramaKesinMi,
  taranacakGunler,
} from '../_shared/fon_kalem.ts';
import { pdfMetni } from '../_shared/pdf_metin.ts';

const MODEL = 'claude-opus-5-5';

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  });
}

const bekle = (ms: number) => new Promise((r) => setTimeout(r, ms));

/// KAP ~20 istek/dk'dan hızlısında bağlantı kesiyor (tefas-fon ölçümü).
const KAP_ARASI_MS = 3_000;
/// PDF üst sınırı: aylık rapor 50-500 KB; çok büyüğü rapor değildir.
const PDF_UST_BAYT = 15 * 1024 * 1024;
const KAP_BASLIKLARI: Record<string, string> = {
  Accept: 'application/json, text/plain, */*',
  'Content-Type': 'application/json',
  Origin: KAP_TABAN,
  Referer: `${KAP_TABAN}/tr/`,
  'User-Agent': ISTEK_BASLIKLARI['User-Agent'],
};

class GeciciHata extends Error {
  constructor(public kod: string) {
    super(kod);
    this.name = 'GeciciHata';
  }
}

async function kapGet(yol: string): Promise<Response> {
  const res = await fetch(`${KAP_TABAN}${yol}`, {
    headers: KAP_BASLIKLARI,
    signal: AbortSignal.timeout(40_000),
  }).catch(() => null);
  if (!res || !res.ok) throw new GeciciHata(`kap_${res?.status ?? 'ag'}`);
  return res;
}

/// Bugün tutulan fon/BES kodları — açık kolon listesi, kişi bilgisi dönmez.
async function tutulanFonlar(client: SupabaseClient): Promise<Set<string>> {
  const satirlar: (PozisyonLot & { type: string })[] = [];
  for (let bas = 0; ; bas += 1000) {
    const { data, error } = await client.from('assets')
      .select('id, user_id, type, ticker, sub_category, currency, quantity, kind, added_date, ref_asset_id')
      .in('type', ['fon', 'bes'])
      .is('deleted_at', null)
      .order('id')
      .range(bas, bas + 999);
    if (error) throw error;
    satirlar.push(...((data ?? []) as (PozisyonLot & { type: string })[]));
    if (!data || data.length < 1000) break;
  }
  const kodlar = new Set<string>();
  for (const lot of acikPozisyonLotlari(satirlar)) {
    const kod = varlikKodu(String(lot.ticker ?? ''));
    if (/^[A-Z0-9]{2,8}$/.test(kod)) kodlar.add(kod);
  }
  return kodlar;
}

/// Bir günün PDR satırları: önbellekte kesinse oradan, değilse KAP'tan.
async function gununPdrleri(
  client: SupabaseClient,
  gun: string,
): Promise<{ pdr: PdrSatiri[]; kapaGidildi: boolean; kesik: boolean }> {
  const { data: onceki, error } = await client.from('fon_kalem_taramasi')
    .select('pdr, kesik, tarandi').eq('gun', gun).maybeSingle();
  if (error) throw error;
  if (onceki && taramaKesinMi(gun, String(onceki.tarandi))) {
    return { pdr: onceki.pdr as PdrSatiri[], kapaGidildi: false, kesik: Boolean(onceki.kesik) };
  }
  const res = await fetch(`${KAP_TABAN}/tr/api/disclosure/funds/byCriteria`, {
    method: 'POST',
    headers: KAP_BASLIKLARI,
    body: JSON.stringify({
      fromDate: gun, toDate: gun, fundTypes: [], mkkMemberOid: null,
      disclosureClass: '', subjectList: [], index: '',
    }),
    signal: AbortSignal.timeout(60_000),
  }).catch(() => null);
  if (!res || !res.ok) throw new GeciciHata(`kap_liste_${res?.status ?? 'ag'}`);
  const liste = await res.json().catch(() => null);
  if (!Array.isArray(liste)) throw new GeciciHata('kap_liste_bicim');
  const pdr = pdrSatirlari(liste);
  const kesik = liste.length >= KAP_LISTE_USTU;
  const { error: yErr } = await client.from('fon_kalem_taramasi').upsert({
    gun, pdr, satir: liste.length, kesik, tarandi: new Date().toISOString(),
  }, { onConflict: 'gun' });
  if (yErr) throw yErr;
  return { pdr, kapaGidildi: true, kesik };
}

/// Ay sonu TEFAS satırı (kontrol 3) ve unvan (kontrol 4). Fon tipi
/// bilinmiyorsa (Katman B satırı yok) YAT → EMK → BYF denenir.
async function ayaSonuTefas(
  kod: string,
  donem: string,
  bilinenTip: FonTipi | null,
): Promise<{ dagilim: Record<string, number>; unvan: string | null; tarih: string } | null> {
  const bas = new Date(`${donem}T12:00:00Z`);
  bas.setUTCDate(bas.getUTCDate() - 7);
  const tipler = bilinenTip ? [bilinenTip] : [...FON_TIPLERI];
  for (const tip of tipler) {
    const res = await fetch(TEFAS_DAGILIM_URL, {
      method: 'POST',
      headers: ISTEK_BASLIKLARI,
      body: JSON.stringify(tefasGovdesi(tip, trGunu(bas).replaceAll('-', ''), donem.replaceAll('-', ''), kod)),
      signal: AbortSignal.timeout(30_000),
    }).catch(() => null);
    if (!res || !res.ok) throw new GeciciHata(`tefas_${res?.status ?? 'ag'}`);
    const a = ayristir(await res.text(), tip);
    if (a.durum === 'hata') throw new GeciciHata('tefas_bicim');
    const satir = gunVeyaOncesi(a.satirlar.filter((s) => s.fon_kodu === kod), donem);
    if (satir) return { dagilim: satir.dagilim, unvan: satir.fon_unvan ?? null, tarih: satir.tarih };
    if (tipler.length > 1) await bekle(11_000);
  }
  return null;
}

type Islem = { kod: string; sonuc: 'gecti' | 'red' | 'gecici'; neden?: string; maliyet?: number | null };

async function fonuIsle(
  client: SupabaseClient,
  anthropic: Anthropic,
  kod: string,
  index: number,
  donem: string,
  bilinenTip: FonTipi | null,
): Promise<Islem> {
  const yaz = async (durum: 'gecti' | 'red', kalemler: unknown[], dogrulama: Record<string, unknown>) => {
    const { error } = await client.from('fon_kalemleri').upsert({
      fon_kodu: kod, donem, durum, kalemler, kaynak_url: bildirimAdresi(index),
      dogrulama, alindi: new Date().toISOString(),
    }, { onConflict: 'fon_kodu,donem' });
    if (error) throw error;
  };

  try {
    const ek = await (await kapGet(`/tr/api/notification/attachment-detail/${index}`)).json().catch(() => null);
    const objId = ekPdfNesnesi(ek);
    if (!objId) {
      await yaz('red', [], { neden: 'pdf_eki_yok', bildirim: index });
      return { kod, sonuc: 'red', neden: 'pdf_eki_yok' };
    }
    await bekle(KAP_ARASI_MS);
    const dosya = new Uint8Array(await (await kapGet(`/tr/api/file/download/${objId}`)).arrayBuffer());
    const pdf = dosya.length <= PDF_UST_BAYT ? pdfBaytlari(dosya) : null;
    if (!pdf) {
      await yaz('red', [], { neden: 'pdf_degil', bildirim: index });
      return { kod, sonuc: 'red', neden: 'pdf_degil' };
    }
    let metin: string;
    try {
      metin = await pdfMetni(pdf);
    } catch (_) {
      metin = '';
    }
    if (!metinYeterliMi(metin)) {
      // Vektör çizilmiş ya da taranmış PDF: OCR yok, model çağrılmaz.
      await yaz('red', [], { neden: 'metin_yok', bildirim: index });
      return { kod, sonuc: 'red', neden: 'metin_yok' };
    }

    const tefas = await ayaSonuTefas(kod, donem, bilinenTip);

    // Opus 5.5: zorunlu araç seçimi (tool_choice any/tool) bu modelde 400
    // döner; yapılandırılmış çıktı (`output_config.format`) kullanılır.
    // Sunucu taraflı yedek (`fallbacks: 'default'`): güvenlik sınıflandırıcısı
    // bir kamu belgesini yanlışlıkla reddederse istek uygun modele yönlenir.
    // deno-lint-ignore no-explicit-any
    const yanit: any = await anthropic.beta.messages.create({
      ...istekGovdesi(metin, kod, MODEL),
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      // deno-lint-ignore no-explicit-any
    } as any);
    const maliyet = maliyetUsd(String(yanit.model ?? MODEL), yanit.usage ?? {}, false);
    if (yanit.stop_reason === 'refusal' || yanit.stop_reason === 'max_tokens') {
      await yaz('red', [], { neden: `model_${yanit.stop_reason}`, bildirim: index, maliyet_usd: maliyet, model: MODEL });
      return { kod, sonuc: 'red', neden: `model_${yanit.stop_reason}`, maliyet };
    }
    // deno-lint-ignore no-explicit-any
    const metinBlogu = (yanit.content ?? []).find((c: any) => c.type === 'text');
    let ham: unknown = null;
    try {
      ham = metinBlogu ? JSON.parse(metinBlogu.text) : null;
    } catch (_) {
      ham = null;
    }

    const s = dogrula({
      ham,
      pdfMetni: metin,
      tefas: tefas?.dagilim ?? null,
      unvan: tefas?.unvan ?? null,
    });
    const ortak = {
      ...s.ozet,
      bildirim: index,
      tefas_tarih: tefas?.tarih ?? null,
      model: MODEL,
      maliyet_usd: maliyet,
    };
    if (!s.gecti) {
      await yaz('red', [], { ...ortak, kontrol: s.kontrol, neden: s.neden });
      return { kod, sonuc: 'red', neden: `${s.kontrol}`, maliyet };
    }
    await yaz('gecti', s.kalemler, { ...ortak, kontroller: ['sema', 'metin', 'toplam', 'tefas', 'bant'] });
    return { kod, sonuc: 'gecti', maliyet };
  } catch (e) {
    // Geçici: yazılmaz, sonraki tur dener. Ham mesaj loga da yazılmaz.
    console.error('[fon-kalem-raporu]', kod, e instanceof GeciciHata ? e.kod : hataOzeti(e));
    return { kod, sonuc: 'gecici', neden: e instanceof GeciciHata ? e.kod : 'sunucu' };
  }
}

Deno.serve(async (request) => {
  if (request.method !== 'POST') return jsonResponse({ ok: false }, 405);

  try {
    // Ayrı secret açılmadı (0132 notu): öteki yapay zekâ cron'uyla aynı.
    const cronSecret = Deno.env.get('PRICE_ALERTS_CRON_SECRET');
    const eksik = cronSecretZorunlu(cronSecret, 'PRICE_ALERTS_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    // Bayrak: kapalıyken hiçbir şey yapma (ağ yok, yazma yok).
    if (Deno.env.get('FON_KALEM_ACIK') !== '1') {
      return jsonResponse({ ok: true, atlandi: 'kapali' });
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY runtime tarafından sağlanmadı.');
    }

    let dryRun = false;
    let bugun = trGunu(new Date());
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
      if (typeof body?.bugun === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(body.bugun)) bugun = body.bugun;
    } catch (_) { /* gövde opsiyonel */ }

    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    if (!apiKey && !dryRun) {
      console.error('fon-kalem-raporu: ANTHROPIC_API_KEY tanimli degil.');
      return jsonResponse({ ok: false, neden: 'anahtar_yok' }, 503);
    }

    const { donem, yil, ay } = oncekiAySonu(bugun);
    const client: SupabaseClient = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });

    const tutulan = await tutulanFonlar(client);
    const { data: islenmis, error: iErr } = await client.from('fon_kalemleri')
      .select('fon_kodu').eq('donem', donem).limit(10000);
    if (iErr) throw iErr;
    const bitti = new Set((islenmis ?? []).map((r) => String(r.fon_kodu)));
    const bekleyen = [...tutulan].filter((k) => !bitti.has(k)).sort();
    if (bekleyen.length === 0) return jsonResponse({ ok: true, donem, bekleyen: 0, islenen: [] });

    // Aylık harcama tavanı (varsayılan 10 $). Aşılınca tur boş geçer.
    const ayBasi = `${bugun.slice(0, 7)}-01T00:00:00Z`;
    const { data: harcamalar, error: hErr } = await client.from('fon_kalemleri')
      .select('dogrulama').gte('alindi', ayBasi).limit(10000);
    if (hErr) throw hErr;
    const harcama = (harcamalar ?? []).reduce(
      (t, r) => t + Number((r.dogrulama as Record<string, unknown>)?.maliyet_usd ?? 0), 0);
    const tavan = Number(Deno.env.get('FON_KALEM_AYLIK_TAVAN_USD') ?? '10');
    if (tavan > 0 && harcama >= tavan) {
      return jsonResponse({ ok: true, donem, atlandi: 'tavan', bekleyen: bekleyen.length });
    }

    // KAP liste taraması: gün başına bir istek, kesin günler önbellekten.
    const tumPdr: PdrSatiri[] = [];
    const kesikGunler: string[] = [];
    let kapaGidildi = false;
    for (const gun of taranacakGunler(donem, bugun)) {
      if (kapaGidildi) await bekle(KAP_ARASI_MS);
      try {
        const g = await gununPdrleri(client, gun);
        kapaGidildi = g.kapaGidildi;
        if (g.kesik) kesikGunler.push(gun);
        tumPdr.push(...g.pdr);
      } catch (e) {
        console.error('[fon-kalem-raporu] liste', gun, e instanceof GeciciHata ? e.kod : hataOzeti(e));
        kapaGidildi = true;
      }
    }
    const bildirimler = donemBildirimleri(tumPdr, yil, ay);
    const ust = Number(Deno.env.get('FON_KALEM_TUR_USTU') ?? '3') || 3;
    const kuyruk = bekleyen.filter((k) => bildirimler.has(k)).slice(0, ust);

    if (dryRun || kuyruk.length === 0) {
      return jsonResponse({
        ok: true, dry_run: dryRun, donem, bekleyen: bekleyen.length,
        raporu_yayinda: bekleyen.filter((k) => bildirimler.has(k)).length,
        kuyruk, kesik_gunler: kesikGunler, islenen: [],
      });
    }

    const { data: tipler } = await client.from('fon_dagilimlari')
      .select('fon_kodu, fon_tipi').in('fon_kodu', kuyruk);
    const tipOf = new Map((tipler ?? []).map((r) => [String(r.fon_kodu), r.fon_tipi as FonTipi]));

    const anthropic = new Anthropic({ apiKey });
    const islenen: Islem[] = [];
    for (const kod of kuyruk) {
      await bekle(KAP_ARASI_MS);
      islenen.push(await fonuIsle(client, anthropic, kod, bildirimler.get(kod)!, donem, tipOf.get(kod) ?? null));
    }
    return jsonResponse({
      ok: true, donem, bekleyen: bekleyen.length, kesik_gunler: kesikGunler,
      islenen: islenen.map(({ kod, sonuc, neden }) => ({ kod, sonuc, neden })),
    });
  } catch (e) {
    console.error('[fon-kalem-raporu] beklenmeyen hata:', hataOzeti(e));
    return jsonResponse({ ok: false, reason: 'internal_error' }, 500);
  }
});
