// x-paylas — SANDIK X hesabının günlük gönderi TASLAĞI (0146, 2026-10-13).
//
// pg_cron hafta içi TR 19:40'ta çağırır (fon akışı 19:15 turundan sonra).
// İçerik: fon akışı, Cuma haftanın özeti, TÜİK TÜFE; ABD için (Türkçe) BLS
// TÜFE ve Fed faiz kararı.
// Gönderiyi kendisi ATMAZ: taslağı yazar, kartını çizer ve Telegram'da
// yöneticiye "Yayınla / Reddet" düğmeleriyle yollar. Atma işi `x-onay`'da.
//
// Kapılar (hepsi varsayılan KAPALI; canlıdaki uygulama kullanıcısı hiçbir
// şey görmez, uygulama bu tablolara hiç dokunmaz):
//   X_BOT_MODU  yok/'kapali' → 503, hiçbir şey yapılmaz (AI maliyeti de yok)
//               'taslak'     → taslak + Telegram önizleme, onay X'e GÖNDERMEZ
//               'yayin'      → onaylanan taslak X'e gider (x-onay)
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
  bugununFonGonderisi,
  fonAkisiTaslagi,
  gunEkle,
  haftalikTaslak,
  istekGovdesi,
  kartSvg,
  kurDegisimleri,
  metinKapisi,
  MODEL,
  type Taslak,
  tufeOzeti,
  tufeTaslagi,
  tufeYeniMi,
} from '../_shared/x_paylasim.ts';
import { telegramAyari, telegramTaslakGonder, telegramWebhookKur } from '../_shared/x_istemci.ts';
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

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return yanit({ ok: false }, 405);
  // Fon akışı gözlemiyle aynı secret (0146 gerekçesi): yeni Vault kaydı
  // iki sunucuda elle kurulum isterdi; sızıntısı en çok bir taslak açtırır.
  const secret = Deno.env.get('TEFAS_NAV_CRON_SECRET');
  const eksik = cronSecretZorunlu(secret, 'TEFAS_NAV_CRON_SECRET');
  if (eksik) return eksik;
  const yetkisiz = cronYetkisiVarMi(req, secret);
  if (yetkisiz) return yetkisiz;

  const mod = Deno.env.get('X_BOT_MODU') ?? 'kapali';
  if (mod !== 'taslak' && mod !== 'yayin') return yanit({ ok: false, neden: 'kapali' }, 503);

  const url = Deno.env.get('SUPABASE_URL')!;
  const db = createClient(url, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!);
  const simdi = new Date();
  const bugun = trGun(simdi);
  const sonuc: Record<string, string> = {};

  try {
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
      if (aiAcik) {
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
      if (tg) {
        const not = mod === 'yayin' ? '' : '\n\n(Taslak modu: onay X\'e göndermez.)';
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
