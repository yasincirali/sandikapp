// supabase/functions/ekstre-esle/index.ts
//
// Ekstre AI sütun eşleme (2026-10-05, 0121). Uygulamanın okuyucusu bir
// ekstrenin sütunlarından emin olamadığında, kullanıcı "Yapay zekâyla
// eşle"ye basar; uygulama tablonun ANONİM iskeletini yollar, burası
// Claude'dan yalnız sütun numaralarını alır. Gerekçe, kişisel veri ve
// doğrulama kuralları: `_shared/ekstre_esleme.ts`.
//
// Akış:
// 1. JWT → kullanıcı (anonim çağrı yok).
// 1b. Premium kapısı (`premium_icerik_gorebilir`, 0116) → 403 `premium`.
// 2. İskelet biçim + maske denetimi (maskesiz rakam → 400, model çağrılmaz).
// 3. Kota: kullanıcı başına günde EKSTRE_GUNLUK_HAK (varsayılan 10) istek;
//    ay toplamı EKSTRE_AYLIK_TAVAN_USD (varsayılan 10) aşılınca 429.
// 4. Messages API, zorunlu araç çağrısı; yanıt iskelet boyutlarıyla denetlenir.
// 5. `ekstre_esleme_kaydi`'na yalnız sayaç/maliyet (iskelet ve yanıt YOK);
//    40 günden eski satırlar aynı istekte silinir.
//
// Metin yolu (v2, 2026-10-13, 0147): önce banka şablonu hafızası
// (`ekstre_sablonlari`) — tutarsa model ÇAĞRILMAZ, kota düşmez, maliyet 0.
// Tutmazsa önce Haiku 5.5, hiç tablo bulamazsa bir kez Sonnet 5.5; bulunan
// eşlemeler şablon olarak saklanır. `sablonsuz: true` = cihaz şablonun
// verdiği eşlemeyi sağlamada reddetti: şablonun hata sayacı artar, model
// sorulur. Metin yolu açık rıza ister (`ekstre_ai_rizalari`; yoksa 403
// `riza`). v1 iskelet birebir eskisi gibi (Sonnet, şablon yok, rıza yok).
//
// Yanıt: { ok: true, tablolar: Esleme[], kaynak: 'ai' | 'sablon' } ya da
// { ok: false, neden }.
// `error.message` ve ham model yanıtı dönülmez (CLAUDE.md sunucu kuralı).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { maliyetUsd } from '../_shared/analiz.ts';
import {
  adayIzler,
  ARAC,
  type Esleme,
  hataOzeti,
  ILK_MODEL,
  istekGovdesi,
  iskeletiDogrula,
  izOzeti,
  SABLON_HATA_SINIRI,
  type Sablon,
  sablonlaEsle,
  sablonRolleri,
  tablolariAyikla,
  YEDEK_MODEL,
  yanitiDogrula,
  yeniSablonlar,
} from '../_shared/ekstre_esleme.ts';

const MODEL = YEDEK_MODEL;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ ok: false, neden: 'yontem' }, 405);

  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const servis = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) return jsonResponse({ ok: false, neden: 'yapilandirma' }, 503);

  const auth = req.headers.get('Authorization');
  if (!auth) return jsonResponse({ ok: false, neden: 'kimlik' }, 401);
  const kullanici = createClient(url, anon, {
    global: { headers: { Authorization: auth } },
  });
  const { data: u, error: ue } = await kullanici.auth.getUser();
  if (ue || !u?.user) return jsonResponse({ ok: false, neden: 'kimlik' }, 401);
  const userId = u.user.id;

  // Premium'a özel (yasin, 2026-10-05: "ai ile okutup ekletmek premium wall
  // arkasında olmalı"). Kapı varlık notlarıyla aynı: `premium_icerik_gorebilir`
  // (0116) — paywall kapısı kapalıyken herkes, açıkken yalnız Premium.
  // İstemci kilidi yalnız görünüm; asıl kapı burası.
  const { data: gorebilir, error: pe } = await kullanici.rpc('premium_icerik_gorebilir');
  if (pe) {
    console.error('ekstre-esle premium', pe.code ?? 'hata');
    return jsonResponse({ ok: false, neden: 'sunucu' }, 500);
  }
  if (gorebilir !== true) return jsonResponse({ ok: false, neden: 'premium' }, 403);

  let govde: { iskelet?: unknown; sablonsuz?: unknown };
  try {
    govde = await req.json();
  } catch {
    return jsonResponse({ ok: false, neden: 'govde' }, 400);
  }
  const d = iskeletiDogrula(govde.iskelet);
  if (!d.gecti) return jsonResponse({ ok: false, neden: d.neden }, 400);
  const iskelet = govde.iskelet as string;
  const metinYolu = d.surum === 'metin';

  const db = createClient(url, servis);
  try {
    // Metin yolunda kelimeler modele gider: işlemi isteyen kullanıcının
    // açık rızası şart (0147 `ekstre_ai_rizalari`, ilk kullanımda sorulur).
    if (metinYolu) {
      const { data: riza, error: re } = await db.from('ekstre_ai_rizalari')
        .select('geri_cekildi_at').eq('user_id', userId).maybeSingle();
      if (re) throw re;
      if (!riza || riza.geri_cekildi_at !== null) {
        return jsonResponse({ ok: false, neden: 'riza' }, 403);
      }
    }

    // Şablon hafızası (yalnız metin yolu): iz → SHA-256 → saklı eşleme.
    const tablolarMetni = metinYolu ? tablolariAyikla(iskelet) : [];
    const adaylar = await Promise.all(
      adayIzler(tablolarMetni).map(async (a) => ({ ...a, iz: await izOzeti(a.iz) })),
    );
    const sablonlar = new Map<string, Sablon>();
    if (adaylar.length > 0) {
      const { data: sr, error: se } = await db.from('ekstre_sablonlari')
        .select('iz, roller, sutun_sayisi')
        // Çok sayfalı PDF her sayfada aynı başlığı tekrarlar; tekil izler
        // azdır. Üst sınır GET adresinin uzunluğu için (150 × 64 ≈ 10 KB).
        .in('iz', [...new Set(adaylar.map((a) => a.iz))].slice(0, 150))
        .lt('hata', SABLON_HATA_SINIRI);
      if (se) throw se;
      for (const r of sr ?? []) {
        const roller = sablonRolleri(r.roller, Number(r.sutun_sayisi));
        if (roller) sablonlar.set(r.iz, { roller, sutun_sayisi: Number(r.sutun_sayisi) });
      }
    }
    const sablondan = sablonlaEsle(tablolarMetni, adaylar, sablonlar);
    if (sablondan.kullanilan.length > 0) {
      if (govde.sablonsuz === true) {
        // Cihaz bu şablonların verdiği değerleri reddetti.
        await db.rpc('ekstre_sablon_say', { p_izler: sablondan.kullanilan, p_hata: true });
      } else {
        await db.rpc('ekstre_sablon_say', { p_izler: sablondan.kullanilan, p_hata: false });
        await db.from('ekstre_esleme_kaydi').insert({
          user_id: userId,
          model: 'sablon',
          girdi_token: 0,
          cikti_token: 0,
          maliyet_usd: 0,
          tablo_sayisi: sablondan.eslemeler.length,
        });
        return jsonResponse({ ok: true, tablolar: sablondan.eslemeler, kaynak: 'sablon' });
      }
    }

    const gunBasi = new Date();
    gunBasi.setUTCHours(0, 0, 0, 0);
    const { count, error: ce } = await db.from('ekstre_esleme_kaydi')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId).gte('olusturuldu', gunBasi.toISOString())
      .neq('model', 'sablon'); // şablon isteği modele gitmez, hak yemez
    if (ce) throw ce;
    const hak = Number(Deno.env.get('EKSTRE_GUNLUK_HAK') ?? '10') || 10;
    if ((count ?? 0) >= hak) return jsonResponse({ ok: false, neden: 'gunluk_hak' }, 429);

    const ayBasi = new Date();
    ayBasi.setUTCDate(1);
    ayBasi.setUTCHours(0, 0, 0, 0);
    const { data: ay, error: ae } = await db.from('ekstre_esleme_kaydi')
      .select('maliyet_usd').gte('olusturuldu', ayBasi.toISOString()).limit(10000);
    if (ae) throw ae;
    const harcama = (ay ?? []).reduce((t, r) => t + Number(r.maliyet_usd ?? 0), 0);
    const tavan = Number(Deno.env.get('EKSTRE_AYLIK_TAVAN_USD') ?? '10');
    if (tavan > 0 && harcama >= tavan) return jsonResponse({ ok: false, neden: 'tavan' }, 429);

    const anthropic = new Anthropic({ apiKey });
    const sor = async (model: string) => {
      const yanit = await anthropic.messages.create(
        // deno-lint-ignore no-explicit-any
        istekGovdesi(iskelet, model) as any,
      );
      const arac = yanit.content.find((c) => c.type === 'tool_use' && c.name === ARAC.name);
      return {
        tablolar: yanitiDogrula(arac && 'input' in arac ? arac.input : null, d.tablolar),
        maliyet: maliyetUsd(model, {
          input_tokens: yanit.usage?.input_tokens,
          output_tokens: yanit.usage?.output_tokens,
        }, false) ?? 0,
        girdi: yanit.usage?.input_tokens ?? 0,
        cikti: yanit.usage?.output_tokens ?? 0,
      };
    };
    // v1: doğrudan Sonnet (eski davranış). v2: Haiku, boşsa bir kez Sonnet.
    let sonModel = metinYolu ? ILK_MODEL : MODEL;
    let sonuc = await sor(sonModel);
    let maliyet = sonuc.maliyet, girdi = sonuc.girdi, cikti = sonuc.cikti;
    if (metinYolu && sonuc.tablolar.length === 0) {
      sonModel = YEDEK_MODEL;
      sonuc = await sor(sonModel);
      maliyet += sonuc.maliyet;
      girdi += sonuc.girdi;
      cikti += sonuc.cikti;
    }
    const tablolar: Esleme[] = sonuc.tablolar;

    if (metinYolu) {
      for (const y of yeniSablonlar(tablolarMetni, tablolar)) {
        const { error: ye } = await db.from('ekstre_sablonlari').upsert({
          iz: await izOzeti(y.iz),
          roller: y.sablon.roller,
          sutun_sayisi: y.sablon.sutun_sayisi,
          model: sonModel,
          guncellendi: new Date().toISOString(),
          hata: 0,
        }, { onConflict: 'iz' });
        // Şablon yazılamazsa kullanıcı yine yanıtını alır; yalnız kod loga.
        if (ye) console.error('ekstre-esle sablon', hataOzeti(ye));
      }
    }

    // Saklama 40 gün (Gizlilik 1.6 §7): kota yalnız bugünü ve bu ayı okur.
    const sinir = new Date(Date.now() - 40 * 86_400_000).toISOString();
    await db.from('ekstre_esleme_kaydi').delete().lt('olusturuldu', sinir);
    await db.from('ekstre_esleme_kaydi').insert({
      user_id: userId,
      model: sonModel,
      girdi_token: girdi,
      cikti_token: cikti,
      maliyet_usd: maliyet,
      tablo_sayisi: tablolar.length,
    });
    return jsonResponse({ ok: true, tablolar, kaynak: 'ai' });
  } catch (e) {
    console.error('ekstre-esle', hataOzeti(e));
    return jsonResponse({ ok: false, neden: 'sunucu' }, 500);
  }
});
