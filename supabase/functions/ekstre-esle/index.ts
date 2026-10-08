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
// Yanıt: { ok: true, tablolar: Esleme[] } ya da { ok: false, neden }.
// `error.message` ve ham model yanıtı dönülmez (CLAUDE.md sunucu kuralı).

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { maliyetUsd } from '../_shared/analiz.ts';
import { ARAC, hataOzeti, istekGovdesi, iskeletiDogrula, yanitiDogrula } from '../_shared/ekstre_esleme.ts';

const MODEL = 'claude-sonnet-5-5';

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

  let govde: { iskelet?: unknown };
  try {
    govde = await req.json();
  } catch {
    return jsonResponse({ ok: false, neden: 'govde' }, 400);
  }
  const d = iskeletiDogrula(govde.iskelet);
  if (!d.gecti) return jsonResponse({ ok: false, neden: d.neden }, 400);
  const iskelet = govde.iskelet as string;

  const db = createClient(url, servis);
  try {
    const gunBasi = new Date();
    gunBasi.setUTCHours(0, 0, 0, 0);
    const { count, error: ce } = await db.from('ekstre_esleme_kaydi')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId).gte('olusturuldu', gunBasi.toISOString());
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

    const yanit = await new Anthropic({ apiKey }).messages.create(
      // deno-lint-ignore no-explicit-any
      istekGovdesi(iskelet, MODEL) as any,
    );
    const arac = yanit.content.find((c) => c.type === 'tool_use' && c.name === ARAC.name);
    const tablolar = yanitiDogrula(arac && 'input' in arac ? arac.input : null, d.tablolar);

    // Saklama 40 gün (Gizlilik 1.6 §7): kota yalnız bugünü ve bu ayı okur.
    const sinir = new Date(Date.now() - 40 * 86_400_000).toISOString();
    await db.from('ekstre_esleme_kaydi').delete().lt('olusturuldu', sinir);
    await db.from('ekstre_esleme_kaydi').insert({
      user_id: userId,
      model: MODEL,
      girdi_token: yanit.usage?.input_tokens ?? null,
      cikti_token: yanit.usage?.output_tokens ?? null,
      maliyet_usd: maliyetUsd(MODEL, {
        input_tokens: yanit.usage?.input_tokens,
        output_tokens: yanit.usage?.output_tokens,
      }, false),
      tablo_sayisi: tablolar.length,
    });
    return jsonResponse({ ok: true, tablolar });
  } catch (e) {
    console.error('ekstre-esle', hataOzeti(e));
    return jsonResponse({ ok: false, neden: 'sunucu' }, 500);
  }
});
