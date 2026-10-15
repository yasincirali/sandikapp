// x-paylas — SANDIK X hesabının günlük gönderi TASLAĞI (0146, 2026-10-13).
//
// pg_cron hafta içi iki kez çağırır:
//   TR 19:40 (gövde kip yok/'aksam'; fon akışı 19:15 turundan sonra): fon
//     akışı, Cuma haftanın özeti, TÜİK TÜFE; ABD için (Türkçe) BLS TÜFE ve
//     Fed faiz kararı.
//   TR 09:30 (kip 'sabah', 0153; yasin 15 Eki "günde 2 gönderi"): Pazartesi
//     haftanın takvimi (`x_takvim`), diğer günler dünün fon getirileri.
// `yayin`/`taslak` modda gönderiyi kendisi ATMAZ: taslağı yazar, kartını
// çizer ve Telegram'da yöneticiye "Yayınla / Reddet" düğmeleriyle yollar;
// atma işi `x-onay`'da. `otomatik` modda (yasin, 15 Eki) aynı taslağı
// onaysız atar, Telegram'a yalnız sonucu bildirir.
//
// Kapılar (hepsi varsayılan KAPALI; canlıdaki uygulama kullanıcısı hiçbir
// şey görmez, uygulama bu tablolara hiç dokunmaz):
//   X_BOT_MODU  yok/'kapali' → 503, hiçbir şey yapılmaz (AI maliyeti de yok)
//               'taslak'     → taslak + Telegram önizleme, onay X'e GÖNDERMEZ
//               'yayin'      → onaylanan taslak X'e gider (x-onay)
//               'otomatik'   → taslak onaysız X'e gider, Telegram'a bilgi
//   X_KUR_IZINLI='1' → haftalık karta altın/döviz satırları (veri hakkı
//               netleşene kadar kapalı; bkz. _shared/x_paylasim.ts).
//   ANTHROPIC_API_KEY yoksa ya da X_BOT_AI='0' → şablon metin (model yok).
//
// Gün başına tür başına tek satır (`x_gonderileri` benzersiz anahtarı):
// cron iki kez koşsa da ikinci taslak açılmaz, model ikinci kez çağrılmaz.
// Gerekçe ve içerik kuralları: `_shared/x_paylasim.ts`.

import { createClient } from 'jsr:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';
import { maliyetUsd } from '../_shared/analiz.ts';
import { hataOzeti } from '../_shared/ekstre_esleme.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import {
  abdTufeGuncelMi,
  abdTufeOzeti,
  abdTufeTaslagi,
  akisOzeti,
  fedKarariBul,
  fedTaslagi,
  botModu,
  bugununFonGonderisi,
  fonAkisiTaslagi,
  fonGetiriTaslagi,
  getiriOzeti,
  gunEkle,
  haftalikTaslak,
  istekGovdesi,
  kartSvg,
  kurDegisimleri,
  metinKapisi,
  MODEL,
  sabahGonderisi,
  takvimTaslagi,
  type Taslak,
  tufeOzeti,
  tufeTaslagi,
  tufeYeniMi,
} from '../_shared/x_paylasim.ts';
import {
  telegramAyari,
  telegramTaslakGonder,
  telegramWebhookKur,
  xKartliGonder,
  XHatasi,
  xKimligi,
} from '../_shared/x_istemci.ts';
import { pngCiz } from '../bildirim-karti/cizici.ts';

/// ABD kamu verisi (BLS, New York Fed). Anahtarsız uçlar; 15 sn sınır.
/// Hata ya da beklenmeyen yanıt → null, o gönderi bu tur atlanır.
async function jsonGetir(url: string, init?: RequestInit): Promise<unknown | null> {
  try {
    const r = await fetch(url, { ...init, signal: AbortSignal.timeout(15000) });
    if (!r.ok) {
      console.error('[x-paylas] kaynak', new URL(url).host, r.status);
      return null;
    }
    return await r.json();
  } catch (e) {
    console.error('[x-paylas] kaynak', new URL(url).host, hataOzeti(e));
    return null;
  }
}

function yanit(govde: unknown, durum = 200): Response {
  return new Response(JSON.stringify(govde), { status: durum, headers: { 'Content-Type': 'application/json' } });
}

/// TR saatiyle o günün 18:00'i (UTC ISO) — kur karşılaştırmasının anı.
function trAksam(gun: string): string {
  return new Date(`${gun}T15:00:00Z`).toISOString();
}

/// Otomatik mod: `x-onay`'daki kilit + gönderim, onaysız. Satır
/// `taslak → gonderiliyor` koşullu güncellemesiyle kilitlenir; eşzamanlı ikinci
/// tur ya da bu arada Telegram'dan basılan düğme ikinci kez atamaz.
async function otomatikGonder(
  // deno-lint-ignore no-explicit-any
  db: any,
  kimlik: NonNullable<ReturnType<typeof xKimligi>>,
  id: number,
  metin: string,
  png: Uint8Array<ArrayBuffer> | null,
  tg: ReturnType<typeof telegramAyari>,
): Promise<string> {
  const { data: kilit, error: ke } = await db.from('x_gonderileri')
    .update({ durum: 'gonderiliyor', karar_at: new Date().toISOString() })
    .eq('id', id).eq('durum', 'taslak').select('id');
  if (ke) throw ke;
  if (!kilit?.length) return `zaten_isleniyor:${id}`;
  try {
    const xId = await xKartliGonder(kimlik, metin, png);
    await db.from('x_gonderileri').update({ durum: 'gonderildi', x_id: xId, gonderildi_at: new Date().toISOString() })
      .eq('id', id);
    if (tg) await telegramTaslakGonder(tg, id, `${metin}\n\n— Otomatik yayınlandı: https://x.com/i/status/${xId}`, png, false);
    return `gonderildi:${id}`;
  } catch (e) {
    const neden = e instanceof XHatasi ? e.message : hataOzeti(e);
    console.error('[x-paylas] otomatik gonderim', neden);
    await db.from('x_gonderileri').update({ durum: 'hata', hata: neden.slice(0, 200) }).eq('id', id);
    if (tg) await telegramTaslakGonder(tg, id, `${metin}\n\n— Otomatik gönderilemedi (${neden}).`, png, false);
    return `hata:${id}`;
  }
}

/// Akşam turu (0146): fon akışı / haftalık, TÜFE, ABD TÜFE, Fed.
async function aksamTaslaklari(
  // deno-lint-ignore no-explicit-any
  db: any,
  bugun: string,
  simdi: Date,
  sonuc: Record<string, string>,
): Promise<Taslak[]> {
  const taslaklar: Taslak[] = [];

  // 1) Fon akışı (hafta içi) / haftanın özeti (Cuma).
  const plan = bugununFonGonderisi(bugun);
  if (plan) {
    const { data, error } = await db.from('fon_akis_gunluk')
      .select('fon_kodu, tarih, fon_tipi, fon_turu, net_akis')
      .gte('tarih', plan.baslangic).lte('tarih', plan.bitis).eq('fon_tipi', 'YAT')
      .limit(20000);
    if (error) throw error;
    const ozet = akisOzeti(data ?? [], plan.baslangic, plan.bitis);
    if (!ozet) {
      sonuc[plan.tur] = 'veri_eksik';
    } else if (plan.tur === 'fon_akisi') {
      taslaklar.push(fonAkisiTaslagi(ozet));
    } else {
      let kurlar: ReturnType<typeof kurDegisimleri> = [];
      if (Deno.env.get('X_KUR_IZINLI') === '1') {
        const bas = trAksam(gunEkle(bugun, -7));
        const { data: k, error: ke } = await db.from('yurt_ici_kotasyon')
          .select('sembol, ts, fiyat')
          .in('sembol', ['ALTIN_GRAM24', 'USDTRY=X', 'EURTRY=X'])
          .gte('ts', new Date(Date.parse(bas) - 6 * 3600_000).toISOString())
          .lte('ts', trAksam(bugun))
          .limit(20000);
        if (ke) throw ke;
        kurlar = kurDegisimleri(k ?? [], bas, trAksam(bugun));
      }
      taslaklar.push(haftalikTaslak(ozet, kurlar));
    }
  }

  // 2) TÜFE — yalnız yeni yayımlandıysa.
  const { data: endeks, error: ee } = await db.from('inflation_index')
    .select('period, tufe_index, created_at').order('period', { ascending: false }).limit(25);
  if (ee) throw ee;
  const sonEndeks = endeks?.[0];
  if (sonEndeks && tufeYeniMi(sonEndeks.created_at, simdi)) {
    const t = tufeOzeti((endeks ?? []).map((r) => ({ period: r.period, tufe_index: Number(r.tufe_index) })));
    if (t) taslaklar.push(tufeTaslagi(t));
  }

  // 3) ABD — Türkçe anlatılır (yasin, 13 Eki). Yalnız ABD kamu verisi.
  const bls = await jsonGetir('https://api.bls.gov/publicAPI/v1/timeseries/data/', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ seriesid: ['CUSR0000SA0', 'CUUR0000SA0'] }),
  });
  const abd = bls ? abdTufeOzeti(bls) : null;
  if (abd && abdTufeGuncelMi(abd.donem, bugun)) taslaklar.push(abdTufeTaslagi(abd));
  else if (!bls) sonuc.abd_tufe = 'kaynak_yok';

  const nyfed = await jsonGetir('https://markets.newyorkfed.org/api/rates/unsecured/effr/last/10.json');
  const fed = nyfed ? fedKarariBul(nyfed) : null;
  // Karar en geç 4 gün önce yürürlüğe girdiyse (hafta sonu + cron yalnız hafta içi).
  if (fed && fed.tarih >= gunEkle(bugun, -4)) taslaklar.push(fedTaslagi(fed));
  else if (!nyfed) sonuc.fed = 'kaynak_yok';
  return taslaklar;
}

/// Sabah turu (0153): Pazartesi takvim, olay yoksa ya da diğer günler
/// bir önceki iş gününün kategori getirileri.
async function sabahTaslaklari(
  // deno-lint-ignore no-explicit-any
  db: any,
  bugun: string,
  sonuc: Record<string, string>,
): Promise<Taslak[]> {
  const plan = sabahGonderisi(bugun);
  if (!plan) return [];
  if (plan === 'takvim') {
    const { data, error } = await db.from('x_takvim')
      .select('tarih, saat, baslik').gte('tarih', bugun).lte('tarih', gunEkle(bugun, 4));
    if (error) throw error;
    const t = takvimTaslagi(bugun, data ?? []);
    if (t) return [t];
    sonuc.takvim = 'olay_yok';
  }
  // Son iki veri günü: hafta sonu ve bayram arası için 7 gün geriye bakılır.
  const { data, error } = await db.from('fon_akis_gunluk')
    .select('fon_kodu, tarih, fon_tipi, fon_turu, pay_adedi, portfoy_degeri')
    .gte('tarih', gunEkle(bugun, -7)).lt('tarih', bugun).eq('fon_tipi', 'YAT')
    .limit(20000);
  if (error) throw error;
  const o = getiriOzeti(
    (data ?? []).map((r: Record<string, unknown>) => ({
      ...r,
      pay_adedi: Number(r.pay_adedi),
      portfoy_degeri: Number(r.portfoy_degeri),
    })),
    bugun,
  );
  if (!o) {
    sonuc.fon_getiri = 'veri_eksik';
    return [];
  }
  return [fonGetiriTaslagi(o)];
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return yanit({ ok: false }, 405);
  // Fon akışı gözlemiyle aynı secret (0146 gerekçesi): yeni Vault kaydı
  // iki sunucuda elle kurulum isterdi; sızıntısı en çok bir taslak açtırır.
  const secret = Deno.env.get('TEFAS_NAV_CRON_SECRET');
  const eksik = cronSecretZorunlu(secret, 'TEFAS_NAV_CRON_SECRET');
  if (eksik) return eksik;
  const yetkisiz = cronYetkisiVarMi(req, secret);
  if (yetkisiz) return yetkisiz;

  const mod = botModu(Deno.env.get('X_BOT_MODU') ?? 'kapali');
  if (mod === 'kapali') return yanit({ ok: false, neden: 'kapali' }, 503);
  // Otomatik modda anahtar yoksa onaylı akışa düşülür (taslak + düğme).
  const kimlik = mod === 'otomatik' ? xKimligi() : null;

  const url = Deno.env.get('SUPABASE_URL')!;
  const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const simdi = new Date();
  const bugun = trGun(simdi);
  const sonuc: Record<string, string> = {};

  // Gövdesiz/bozuk gövde akşam turu sayılır: 0146'nın tetiği kip yollamaz.
  let kip = 'aksam';
  try {
    const g = await req.json();
    if (g?.kip === 'sabah') kip = 'sabah';
  } catch (_) { /* gövde yok */ }

  try {
    const taslaklar: Taslak[] = kip === 'sabah' ? await sabahTaslaklari(db, bugun, sonuc) : await aksamTaslaklari(db, bugun, simdi, sonuc);

    const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
    const aiAcik = !!apiKey && Deno.env.get('X_BOT_AI') !== '0';
    const tg = telegramAyari();
    if (tg) await telegramWebhookKur(tg, url);

    for (const t of taslaklar) {
      // Aynı tür + dönem zaten varsa dokunma (modeli de çağırma).
      const { data: var_, error: ve } = await db.from('x_gonderileri')
        .select('id').eq('tur', t.tur).eq('donem', t.donem).maybeSingle();
      if (ve) throw ve;
      if (var_) {
        sonuc[t.tur] = 'zaten_var';
        continue;
      }

      let metin = t.sablon_metin;
      let kaynak: 'model' | 'sablon' = 'sablon';
      let model: string | null = null;
      let maliyet: number | null = null;
      let red: string | null = null;
      if (aiAcik && !t.yalniz_sablon) {
        try {
          const y = await new Anthropic({ apiKey }).messages.create(
            // deno-lint-ignore no-explicit-any
            istekGovdesi(t) as any,
          );
          model = MODEL;
          maliyet = maliyetUsd(MODEL, {
            input_tokens: y.usage?.input_tokens ?? 0,
            output_tokens: y.usage?.output_tokens ?? 0,
            cache_read_input_tokens: y.usage?.cache_read_input_tokens ?? 0,
            cache_creation_input_tokens: y.usage?.cache_creation_input_tokens ?? 0,
          }, false);
          const ham = y.content.filter((c) => c.type === 'text').map((c) => ('text' in c ? c.text : '')).join('');
          let k: ReturnType<typeof metinKapisi> = { gecti: false, neden: `stop_reason: ${y.stop_reason}` };
          if (y.stop_reason === 'end_turn') {
            try {
              k = metinKapisi(JSON.parse(ham), t);
            } catch (_) {
              k = { gecti: false, neden: 'yapi: json degil' };
            }
          }
          if (k.gecti) {
            metin = k.metin;
            kaynak = 'model';
          } else {
            red = k.neden.slice(0, 300);
          }
        } catch (e) {
          red = `model: ${hataOzeti(e)}`;
        }
      }

      const { data: satir, error: ie } = await db.from('x_gonderileri').insert({
        tur: t.tur,
        donem: t.donem,
        metin,
        sablon_metin: t.sablon_metin,
        metin_kaynagi: kaynak,
        olgular: t.olgular,
        kart: t.kart,
        model,
        maliyet_usd: maliyet,
        model_red_nedeni: red,
        durum: 'taslak',
      }).select('id').single();
      if (ie) {
        // Eşzamanlı ikinci tur benzersiz anahtara takıldı: sorun değil.
        if ((ie as { code?: string }).code === '23505') {
          sonuc[t.tur] = 'zaten_var';
          continue;
        }
        throw ie;
      }

      let png: Uint8Array<ArrayBuffer> | null = null;
      try {
        png = await pngCiz(kartSvg(t.kart));
      } catch (e) {
        console.error('[x-paylas] kart', hataOzeti(e));
      }
      if (kimlik) {
        sonuc[t.tur] = await otomatikGonder(db, kimlik, satir.id, metin, png, tg);
        continue;
      }
      if (tg) {
        const not = mod === 'taslak' ? '\n\n(Taslak modu: onay X\'e göndermez.)'
          : mod === 'otomatik' ? '\n\n(Otomatik mod ama X anahtarı yok: onayla gönderilir.)' : '';
        await telegramTaslakGonder(tg, satir.id, `${metin}${not}`, png, true);
      }
      sonuc[t.tur] = `taslak:${satir.id}:${kaynak}`;
    }

    // Saklama: 120 günden eski satırlar (Free plan 500 MB).
    await db.from('x_gonderileri').delete().lt('olusturuldu', new Date(simdi.getTime() - 120 * 86400_000).toISOString());

    return yanit({ ok: true, bugun, sonuc });
  } catch (e) {
    console.error('[x-paylas]', hataOzeti(e));
    return yanit({ ok: false, neden: 'sunucu' }, 500);
  }
});
