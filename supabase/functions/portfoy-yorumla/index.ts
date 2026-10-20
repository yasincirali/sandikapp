// supabase/functions/portfoy-yorumla/index.ts
//
// Kişiye özel AI portföy yorumu (0145, 2026-10-13). Uygulama Performans ›
// Özet'te GEÇEN HAFTA / GEÇEN AY için yüzdeleri hesaplayıp yollar; burası
// kayıt yoksa Claude'a 3–4 maddelik betimleyici yorum yazdırır, kapıdan
// geçirip saklar. Gerekçe ve kapılar: `_shared/portfoy_yorum.ts`, 0145.
//
// Akış:
// 0. `PORTFOY_YORUM_ACIK` != '1' → 503 (sunucu tarafı kapı; uygulama bayrağı
//    `portfoy_ai_yorumu` ayrı). Yasal metin (Açık Rıza F) yayımlanmadan açılmaz.
// 1. JWT → kullanıcı. 1b. Premium (`premium_icerik_gorebilir`). 1c. Açık rıza
//    (`portfoy_yorum_rizalari`, geri çekilmemiş) yoksa 403 `riza`.
// 2. Paket biçim denetimi (tutar yok, kapanmış takvim dönemi).
// 3. KAYIT: aynı dönem + aynı parmak izi için yayında satır varsa onu döner,
//    model ÇAĞRILMAZ (yasin, 12 Eki: "her seferinde ai token tüketmeyelim").
// 4. Kota: kullanıcı başına günde PORTFOY_YORUM_GUNLUK (varsayılan 3) çağrı;
//    ay toplamı PORTFOY_YORUM_AYLIK_TAVAN_USD (varsayılan 100) aşılınca
//    Haiku 5.5'e iner, 3 katında o ay durur (429 `tavan`).
// 5. Messages API (Batch değil: kullanıcı bekliyor), yapılandırılmış JSON,
//    sayı + dil kapısı. Red/hata da satır olarak yazılır (günlük sayaca girer,
//    okura gitmez — RLS yalnız 'yayinda').
// 6. Saklama: son 4 hafta + 12 ay; aynı dönemin eski yayındaki satırı silinir.
//
// Seçili dönem / varlık kapsamı (0151, 2026-10-14): `tur` 'secili' + `donem_kodu`
// (1H…5Y), `kapsam` 'portfoy' | 'varlik' (+ `varlik_izi`). Kayıt anahtarı
// bitiş GÜNÜNÜ de içerir: kayan pencerenin yorumu o gün boyunca okunur,
// ertesi gün yeni pencere yeniden yazılabilir. Saklama 7 gün.
//
// Yanıt: { ok: true, yorum, onbellek } ya da { ok: false, neden }.
// `error.message`, ham model yanıtı, anahtar dönülmez (CLAUDE.md sunucu kuralı).

import { createClient } from 'jsr:@supabase/supabase-js@2';
import Anthropic from 'npm:@anthropic-ai/sdk@0';
import { maliyetUsd } from '../_shared/analiz.ts';
import { hataOzeti } from '../_shared/ekstre_esleme.ts';
import { trGun } from '../_shared/tefas_nav.ts';
import {
  istekGovdesi,
  kapidanGecir,
  MODEL,
  paketiDogrula,
  saklamaSiniri,
  seciliSaklamaSiniri,
  TAVAN_MODELI,
} from '../_shared/portfoy_yorum.ts';

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

const SECIM =
  'id, tur, donem, bitis, parmak_izi, baslik, maddeler, olcumler, olusturuldu, kapsam, donem_kodu, varlik_izi';

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return jsonResponse({ ok: false, neden: 'yontem' }, 405);

  if (Deno.env.get('PORTFOY_YORUM_ACIK') !== '1') {
    return jsonResponse({ ok: false, neden: 'kapali' }, 503);
  }
  const url = Deno.env.get('SUPABASE_URL')!;
  const anon = Deno.env.get('SUPABASE_ANON_KEY')!;
  const servis = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
  const apiKey = Deno.env.get('ANTHROPIC_API_KEY');
  if (!apiKey) return jsonResponse({ ok: false, neden: 'yapilandirma' }, 503);

  const auth = req.headers.get('Authorization');
  if (!auth) return jsonResponse({ ok: false, neden: 'kimlik' }, 401);
  const kullanici = createClient(url, anon, { global: { headers: { Authorization: auth } } });
  const { data: u, error: ue } = await kullanici.auth.getUser();
  if (ue || !u?.user) return jsonResponse({ ok: false, neden: 'kimlik' }, 401);
  const userId = u.user.id;

  // İstemci kilidi yalnız görünüm; asıl kapı burası (ekstre-esle ile aynı).
  const { data: gorebilir, error: pe } = await kullanici.rpc('premium_icerik_gorebilir');
  if (pe) {
    console.error('portfoy-yorumla premium', pe.code ?? 'hata');
    return jsonResponse({ ok: false, neden: 'sunucu' }, 500);
  }
  if (gorebilir !== true) return jsonResponse({ ok: false, neden: 'premium' }, 403);

  let govde: unknown;
  try {
    govde = await req.json();
  } catch {
    return jsonResponse({ ok: false, neden: 'govde' }, 400);
  }
  const bugun = trGun(new Date());
  const d = paketiDogrula(govde, bugun);
  if (!d.gecti) return jsonResponse({ ok: false, neden: d.neden }, 400);
  const p = d.paket;

  const db = createClient(url, servis);
  try {
    // Rıza: model çağrısından ÖNCE, her istekte (geri çekme anında geçerli).
    const { data: riza, error: re } = await db.from('portfoy_yorum_rizalari')
      .select('geri_cekildi_at').eq('user_id', userId).maybeSingle();
    if (re) throw re;
    if (!riza || riza.geri_cekildi_at !== null) return jsonResponse({ ok: false, neden: 'riza' }, 403);

    // Kayıt: aynı kapsam, dönem ve parmak izi → modeli çağırma.
    const kapsam = p.kapsam ?? 'portfoy';
    // deno-lint-ignore no-explicit-any
    const ayni = (q: any) => {
      q = q.eq('user_id', userId).eq('tur', p.tur).eq('donem', p.baslangic)
        .eq('bitis', p.bitis).eq('kapsam', kapsam);
      q = p.donem_kodu ? q.eq('donem_kodu', p.donem_kodu) : q.is('donem_kodu', null);
      return p.varlik_izi ? q.eq('varlik_izi', p.varlik_izi) : q.is('varlik_izi', null);
    };
    const { data: kayit, error: ke } = await ayni(db.from('portfoy_yorumlari').select(SECIM))
      .eq('parmak_izi', p.parmak_izi).eq('durum', 'yayinda')
      .order('olusturuldu', { ascending: false }).limit(1).maybeSingle();
    if (ke) throw ke;
    if (kayit) return jsonResponse({ ok: true, yorum: kayit, onbellek: true });

    const gunBasi = new Date();
    gunBasi.setUTCHours(0, 0, 0, 0);
    const { count, error: ce } = await db.from('portfoy_yorumlari')
      .select('id', { count: 'exact', head: true })
      .eq('user_id', userId).gte('olusturuldu', gunBasi.toISOString());
    if (ce) throw ce;
    // 10 (0151'e kadar 3): seçili dönem ve varlık detayı yüzeyleri eklendi;
    // her yüzey yorumu gün boyu saklar, sayaç yalnız yeni yazımları sayar.
    const hak = Number(Deno.env.get('PORTFOY_YORUM_GUNLUK') ?? '10') || 10;
    if ((count ?? 0) >= hak) return jsonResponse({ ok: false, neden: 'gunluk_hak' }, 429);

    const ayBasi = new Date();
    ayBasi.setUTCDate(1);
    ayBasi.setUTCHours(0, 0, 0, 0);
    const { data: ay, error: ae } = await db.from('portfoy_yorumlari')
      .select('maliyet_usd').gte('olusturuldu', ayBasi.toISOString()).limit(50000);
    if (ae) throw ae;
    const harcama = (ay ?? []).reduce((t, r) => t + Number(r.maliyet_usd ?? 0), 0);
    const tavan = Number(Deno.env.get('PORTFOY_YORUM_AYLIK_TAVAN_USD') ?? '100');
    if (tavan > 0 && harcama >= tavan * 3) return jsonResponse({ ok: false, neden: 'tavan' }, 429);
    const model = tavan > 0 && harcama >= tavan ? TAVAN_MODELI : MODEL[p.tur];

    // Atomik kapı (0159, 2026-10-20): yukarıdaki sayım satırı model
    // yanıtından SONRA yazıldığı için aynı anda gelen istekler sayımı
    // birlikte geçiyordu. `ai_hiz_kapisi` kullanıcı başına kilitleyip 24
    // saatlik pencerede sayar ve yazar; modeli çağırmadan önce. Kapı
    // okunamazsa para harcanmaz (fail-closed).
    const { data: izin, error: he } = await db.rpc('ai_hiz_kapisi', {
      p_subject: userId, p_scope: 'portfoy_yorum', p_max: hak, p_pencere_sn: 86400,
    });
    if (he) {
      console.error('portfoy-yorumla hiz kapisi', he.code ?? 'hata');
      return jsonResponse({ ok: false, neden: 'sunucu' }, 503);
    }
    if (izin !== true) return jsonResponse({ ok: false, neden: 'gunluk_hak' }, 429);

    const yanit = await new Anthropic({ apiKey }).messages.create(
      // deno-lint-ignore no-explicit-any
      istekGovdesi(p, model) as any,
    );
    const kullanim = {
      input_tokens: yanit.usage?.input_tokens ?? 0,
      output_tokens: yanit.usage?.output_tokens ?? 0,
      cache_read_input_tokens: yanit.usage?.cache_read_input_tokens ?? 0,
      cache_creation_input_tokens: yanit.usage?.cache_creation_input_tokens ?? 0,
    };
    const temel = {
      user_id: userId,
      tur: p.tur,
      donem: p.baslangic,
      bitis: p.bitis,
      parmak_izi: p.parmak_izi,
      olcumler: p.olcumler,
      kapsam,
      donem_kodu: p.donem_kodu ?? null,
      varlik_izi: p.varlik_izi ?? null,
      model,
      girdi_token: kullanim.input_tokens + kullanim.cache_read_input_tokens + kullanim.cache_creation_input_tokens,
      cikti_token: kullanim.output_tokens,
      maliyet_usd: maliyetUsd(model, kullanim, false),
    };

    let sonuc: ReturnType<typeof kapidanGecir> = { gecti: false, neden: `stop_reason: ${yanit.stop_reason}` };
    if (yanit.stop_reason === 'end_turn') {
      const metin = yanit.content.filter((c) => c.type === 'text').map((c) => ('text' in c ? c.text : '')).join('');
      try {
        sonuc = kapidanGecir(JSON.parse(metin), p);
      } catch (_) {
        sonuc = { gecti: false, neden: 'yapi: json degil' };
      }
    }
    if (!sonuc.gecti) {
      await db.from('portfoy_yorumlari').insert({
        ...temel, durum: 'reddedildi', red_nedeni: sonuc.neden.slice(0, 500),
      });
      return jsonResponse({ ok: false, neden: 'reddedildi' }, 422);
    }

    const { data: yeni, error: ie } = await db.from('portfoy_yorumlari').insert({
      ...temel, durum: 'yayinda', baslik: sonuc.yorum.baslik, maddeler: sonuc.yorum.maddeler,
    }).select(SECIM).single();
    if (ie) throw ie;

    // Saklama: aynı dönemin önceki yorumları (eski parmak izi) ve pencere
    // dışı dönemler. Reddedilen satırlar bugünün sayacı için bugün kalır.
    await ayni(db.from('portfoy_yorumlari').delete())
      .eq('durum', 'yayinda').neq('id', yeni.id);
    if (p.tur === 'secili') {
      await db.from('portfoy_yorumlari').delete()
        .eq('user_id', userId).eq('tur', 'secili').lt('bitis', seciliSaklamaSiniri(bugun));
    } else {
      await db.from('portfoy_yorumlari').delete()
        .eq('user_id', userId).eq('tur', p.tur).lt('donem', saklamaSiniri(p.tur, p.baslangic));
    }

    return jsonResponse({ ok: true, yorum: yeni, onbellek: false });
  } catch (e) {
    console.error('portfoy-yorumla', hataOzeti(e));
    return jsonResponse({ ok: false, neden: 'sunucu' }, 500);
  }
});
