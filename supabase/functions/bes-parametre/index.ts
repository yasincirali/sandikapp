// bes-parametre — BES devlet katkısı yıllık parametrelerini EGM'den çeker.
//
// Cron (0089, her gün 10:40 TR) çağırır. EGM'nin resmî "Devlet Katkısı"
// sayfasını okur, yılı + katkı payı üst sınırını + azami devlet katkısını +
// oranı ayrıştırır, üçünü birbirine karşı doğrular ve `bes_devlet_katkisi`
// tablosuna yazar. İstemci (`BesParametreleri`) tabloyu okur; her Ocak
// sınırı elle koda eklemek gerekmez (kullanıcı kararı 2026-10-01).
//
// ## Uydurma sayı yok
// Ayrıştırma ya da doğrulama tutmazsa HİÇBİR ŞEY yazılmaz (422). Tablo
// son doğru değerinde kalır; yeni yıl henüz yoksa istemci sınırı
// "bilinmiyor" sayar ve tutarı düzenlenebilir gösterir — yanlış bir sınırla
// kırpmaktan iyidir.
//
// ## Secret
// `INFLATION_FETCH_CRON_SECRET` PAYLAŞILIR (0089 gerekçesi): aynı sınıftan
// salt-okur resmî parametre çekimi; yeni secret elle kurulum isterdi.
//
// Gövde: `{"dry_run": true}` → ayrıştırır, doğrular, YAZMAZ.

import { cronSecretZorunlu, cronYetkisiVarMi } from '../_shared/cron_auth.ts';

export const EGM_URL = 'https://www.egm.org.tr/bireysel-emeklilik/devlet-katkisi/';

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

export type BesParametre = {
  yil: number;
  katki_ust_siniri: number;
  azami_devlet_katkisi: number;
  oran_yuzde: number;
};

/// EGM sayfası windows-1254 ya da UTF-8 gelebilir; önce katı UTF-8, olmazsa
/// Türkçe kod sayfası. Yanlış çözülen "ı/ş/ğ" regex'i sessizce kaçırırdı.
export function metneCevir(bytes: Uint8Array): string {
  try {
    return new TextDecoder('utf-8', { fatal: true }).decode(bytes);
  } catch {
    return new TextDecoder('windows-1254').decode(bytes);
  }
}

/// HTML → düz metin: script/style atılır, etiketler boşluğa, varlıklar
/// (`&#246;`, `&#x131;`, `&nbsp;` …) çözülür, boşluklar teke iner.
export function duzMetin(html: string): string {
  const adli: Record<string, string> = {
    nbsp: ' ', amp: '&', lt: '<', gt: '>', quot: '"', apos: "'", rsquo: '’',
    lsquo: '‘',
  };
  return html
    .replace(/<script[\s\S]*?<\/script>|<style[\s\S]*?<\/style>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&#x([0-9a-f]+);/gi, (_, h) => String.fromCodePoint(parseInt(h, 16)))
    .replace(/&#(\d+);/g, (_, d) => String.fromCodePoint(parseInt(d, 10)))
    .replace(/&([a-z]+);/gi, (m, ad) => adli[ad.toLowerCase()] ?? m)
    .replace(/\s+/g, ' ')
    .trim();
}

/// "396.360" / "79.272,50" → sayı. Türkçe binlik nokta, ondalık virgül.
export function trSayi(s: string): number {
  return Number(s.replace(/\./g, '').replace(',', '.'));
}

/// Düz metinden parametreleri çıkarır; bulamazsa `null`.
///
/// Aranan cümle (2026-10-01'de sayfada): "2026 yılı Devlet katkısı üst
/// limitinden yararlanabilmek için ödenmesi gereken katkı payı tutarı
/// 396.360 TL'dir. Bu tutara karşılık ilgili yılda alınabilecek maksimum
/// Devlet katkısı tutarı 79.272 TL'dir." ve "katkı paylarının %20'si".
/// Sayfada "üstlimitinden" bitişik de yazılmış — boşluk isteğe bağlı.
export function ayristir(metin: string): BesParametre | null {
  const sinir = metin.match(
    /(\d{4})\s*yılı\s*Devlet\s*katkısı\s*üst\s*limit[\s\S]{0,200}?katkı\s*payı\s*tutarı\s*([\d.]+(?:,\d+)?)\s*TL[\s\S]{0,200}?maksimum\s*Devlet\s*katkısı\s*tutarı\s*([\d.]+(?:,\d+)?)\s*TL/i,
  );
  const oran = metin.match(/katkı\s*paylarının\s*%\s*(\d+(?:,\d+)?)/i);
  if (!sinir || !oran) return null;
  return {
    yil: Number(sinir[1]),
    katki_ust_siniri: trSayi(sinir[2]),
    azami_devlet_katkisi: trSayi(sinir[3]),
    oran_yuzde: trSayi(oran[1]),
  };
}

/// Ayrıştırılan değerler makul mü? Hata metni döner, geçerliyse `null`.
///
/// Asıl kapı iç tutarlılık: katkı × oran = azami (±1 TL). Bir sayı yanlış
/// okunursa ikisi birbirini tutmaz. Ek olarak yıl bugüne yakın olmalı
/// (eski bir haber kutusundaki yıl değil) ve önceki yıla göre akıl dışı
/// bir sıçrama olmamalı (asgari ücret bir yılda 3 katına çıkmaz).
export function dogrula(
  p: BesParametre,
  buYil: number,
  oncekiAzami: number | null,
): string | null {
  const sayilar = [p.katki_ust_siniri, p.azami_devlet_katkisi, p.oran_yuzde];
  if (!sayilar.every((n) => Number.isFinite(n) && n > 0)) return 'sayi_gecersiz';
  if (p.yil < buYil - 1 || p.yil > buYil + 1) return 'yil_uzak';
  if (p.oran_yuzde > 100) return 'oran_gecersiz';
  if (p.azami_devlet_katkisi < 1000 || p.azami_devlet_katkisi > 10_000_000) {
    return 'azami_aralik_disi';
  }
  if (Math.abs(p.katki_ust_siniri * p.oran_yuzde / 100 - p.azami_devlet_katkisi) > 1) {
    return 'ic_tutarsiz';
  }
  if (oncekiAzami != null && oncekiAzami > 0) {
    const kat = p.azami_devlet_katkisi / oncekiAzami;
    if (kat < 0.5 || kat > 3) return 'sicrama';
  }
  return null;
}

const EGM_BASLIKLARI: Record<string, string> = {
  // Varsayılan Deno UA'sı ve çıplak "Mozilla/5.0" EGM'nin WAF'ında 245
  // baytlık çerez sınamasına düşüyor (ölçüldü 2026-10-01).
  'User-Agent': 'Mozilla/5.0 (compatible; sandik-bes-parametre/1.0)',
  'Accept-Language': 'tr-TR,tr;q=0.9',
  'Accept': 'text/html',
};

/// EGM sayfasını getirir.
///
/// ## Neden iki yol (canlıda bulundu, 2026-10-01)
/// İlk dağıtımda fonksiyon 500 verdi: Deno'nun `fetch`'i (hyper) EGM'nin
/// yanıtını "invalid HTTP header parsed" diye REDDEDİYOR; curl aynı yanıtı
/// kabul ediyor. Kaynak sunucuyu düzeltemeyiz. Önce `fetch` denenir; o hata
/// verirse TLS üstünden ham HTTP/1.1 isteği atılır ve yanıt hoşgörülü
/// ayrıştırılır (durum satırı + gövde; chunked desteklenir). WAF çerez
/// sınaması (küçük gövde + Set-Cookie) gelirse çerezle bir kez yenilenir.
export async function egmSayfasi(): Promise<{ status: number; govde: Uint8Array }> {
  try {
    const y = await fetch(EGM_URL, { headers: EGM_BASLIKLARI, signal: AbortSignal.timeout(20_000) });
    const govde = new Uint8Array(await y.arrayBuffer());
    if (y.status === 200 && govde.length > 2000) return { status: 200, govde };
  } catch (e) {
    console.warn('bes-parametre: fetch reddetti, ham yola geçiliyor:', e instanceof Error ? e.message : e);
  }
  let cerez = '';
  for (let deneme = 0; deneme < 2; deneme++) {
    const y = await hamGet(EGM_URL, cerez ? { ...EGM_BASLIKLARI, Cookie: cerez } : EGM_BASLIKLARI);
    if (y.status === 200 && y.govde.length > 2000) return y;
    if (!y.cerezler.length) return y;
    cerez = y.cerezler.join('; ');
  }
  return { status: 502, govde: new Uint8Array() };
}

/// Hoşgörülü HTTP/1.1 GET (yalnız https, yönlendirme izlemez).
export async function hamGet(
  url: string,
  basliklar: Record<string, string>,
  zamanAsimiMs = 20_000,
): Promise<{ status: number; govde: Uint8Array; cerezler: string[] }> {
  const u = new URL(url);
  const conn = await Deno.connectTls({ hostname: u.hostname, port: 443 });
  const saat = setTimeout(() => {
    try { conn.close(); } catch { /* zaten kapalı */ }
  }, zamanAsimiMs);
  try {
    const satirlar = [
      `GET ${u.pathname}${u.search} HTTP/1.1`,
      `Host: ${u.hostname}`,
      ...Object.entries(basliklar).map(([k, v]) => `${k}: ${v}`),
      'Accept-Encoding: identity',
      'Connection: close',
      '', '',
    ];
    await conn.write(new TextEncoder().encode(satirlar.join('\r\n')));
    const parcalar: Uint8Array[] = [];
    let toplam = 0;
    const buf = new Uint8Array(16384);
    while (true) {
      let n: number | null;
      try {
        n = await conn.read(buf);
      } catch (e) {
        // EGM bağlantıyı TLS close_notify göndermeden kapatıyor; rustls bunu
        // UnexpectedEof sayar. `Connection: close` isteğinde bu, yanıtın
        // BİTTİĞİ demektir (ölçüldü 2026-10-01). Başka hata yükselir.
        if (toplam > 0 && String(e).includes('close_notify')) break;
        throw e;
      }
      if (n === null) break;
      parcalar.push(buf.slice(0, n));
      toplam += n;
      if (toplam > 5_000_000) throw new Error('yanit cok buyuk');
    }
    const tum = new Uint8Array(toplam);
    let o = 0;
    for (const p of parcalar) {
      tum.set(p, o);
      o += p.length;
    }
    return hamYanitiCoz(tum);
  } finally {
    clearTimeout(saat);
    try { conn.close(); } catch { /* zaten kapalı */ }
  }
}

/// Ham yanıt baytları → durum, gövde, çerezler. Başlık satırları katı
/// doğrulanmaz (hyper'ın reddettiği yanıt bu yüzden okunur).
export function hamYanitiCoz(tum: Uint8Array): { status: number; govde: Uint8Array; cerezler: string[] } {
  let ayrim = -1;
  for (let i = 0; i + 3 < tum.length; i++) {
    if (tum[i] === 13 && tum[i + 1] === 10 && tum[i + 2] === 13 && tum[i + 3] === 10) {
      ayrim = i;
      break;
    }
  }
  if (ayrim < 0) return { status: 0, govde: new Uint8Array(), cerezler: [] };
  const bas = new TextDecoder('latin1').decode(tum.subarray(0, ayrim));
  const satirlar = bas.split(/\r?\n/);
  const status = Number(satirlar[0].match(/^HTTP\/\d(?:\.\d)?\s+(\d{3})/)?.[1] ?? 0);
  const baslik = (ad: string) =>
    satirlar.filter((s) => s.toLowerCase().startsWith(`${ad}:`)).map((s) => s.slice(ad.length + 1).trim());
  const cerezler = baslik('set-cookie').map((c) => c.split(';')[0]).filter(Boolean);
  let govde = tum.subarray(ayrim + 4);
  if (baslik('transfer-encoding').some((v) => v.toLowerCase().includes('chunked'))) {
    const out: number[] = [];
    let i = 0;
    while (i < govde.length) {
      let j = i;
      while (j + 1 < govde.length && !(govde[j] === 13 && govde[j + 1] === 10)) j++;
      const boy = parseInt(new TextDecoder().decode(govde.subarray(i, j)).split(';')[0].trim(), 16);
      if (!Number.isFinite(boy) || boy <= 0) break;
      const bas2 = j + 2;
      for (let k = bas2; k < bas2 + boy && k < govde.length; k++) out.push(govde[k]);
      i = bas2 + boy + 2;
    }
    govde = new Uint8Array(out);
  } else {
    const uz = Number(baslik('content-length')[0]);
    if (Number.isFinite(uz) && uz >= 0 && uz <= govde.length) govde = govde.subarray(0, uz);
  }
  return { status, govde, cerezler };
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const cronSecret = Deno.env.get('INFLATION_FETCH_CRON_SECRET');

    // FAIL-CLOSED: secret yoksa 503, başlık tutmazsa 401 (cron_auth.ts).
    const eksik = cronSecretZorunlu(cronSecret, 'INFLATION_FETCH_CRON_SECRET');
    if (eksik) return eksik;
    const yetkisiz = cronYetkisiVarMi(request, cronSecret);
    if (yetkisiz) return yetkisiz;

    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL / SUPABASE_SERVICE_ROLE_KEY yok.');
    }

    let dryRun = false;
    try {
      const body = await request.json();
      if (body?.dry_run === true) dryRun = true;
    } catch {
      // Gövdesiz çağrı — gerçek koşu.
    }

    // ── 1) EGM sayfası ──────────────────────────────────────────────────────
    const yanit = await egmSayfasi();
    if (yanit.status !== 200) {
      console.error('bes-parametre: EGM HTTP', yanit.status);
      return jsonResponse({ ok: false, reason: 'kaynak_http', status: yanit.status }, 502);
    }
    const metin = duzMetin(metneCevir(yanit.govde));

    // ── 2) Ayrıştır + doğrula ───────────────────────────────────────────────
    const p = ayristir(metin);
    if (!p) {
      // Sayfa yapısı değişmiş olabilir — yazmadan dur, iz bırak.
      console.error('bes-parametre: cumle bulunamadi');
      return jsonResponse({ ok: false, reason: 'ayristirilamadi' }, 422);
    }

    const { createClient } = await import('jsr:@supabase/supabase-js@2');
    const admin = createClient(supabaseUrl, serviceRoleKey);

    const { data: satirlar, error: okumaHatasi } = await admin
      .from('bes_devlet_katkisi')
      .select('yil, katki_ust_siniri, azami_devlet_katkisi, oran_yuzde')
      .order('yil', { ascending: false });
    if (okumaHatasi) {
      console.error('bes-parametre: tablo okunamadi:', okumaHatasi.message);
      return jsonResponse({ ok: false, reason: 'tablo_okunamadi' }, 500);
    }
    const mevcut = (satirlar ?? []).find((s) => s.yil === p.yil);
    const onceki = (satirlar ?? []).find((s) => s.yil === p.yil - 1);

    const buYil = Number(new Intl.DateTimeFormat('en-GB', {
      timeZone: 'Europe/Istanbul', year: 'numeric',
    }).format(new Date()));
    const hata = dogrula(p, buYil, onceki ? Number(onceki.azami_devlet_katkisi) : null);
    if (hata) {
      console.error('bes-parametre: dogrulama', hata, JSON.stringify(p));
      return jsonResponse({ ok: false, reason: 'dogrulama', detay: hata, okunan: p }, 422);
    }

    const ayni = mevcut != null &&
      Number(mevcut.katki_ust_siniri) === p.katki_ust_siniri &&
      Number(mevcut.azami_devlet_katkisi) === p.azami_devlet_katkisi &&
      Number(mevcut.oran_yuzde) === p.oran_yuzde;

    if (dryRun || ayni) {
      return jsonResponse({ ok: true, dry_run: dryRun, okunan: p, degisti: !ayni, yazildi: false });
    }

    // ── 3) Yaz ──────────────────────────────────────────────────────────────
    const { error: yazmaHatasi } = await admin
      .from('bes_devlet_katkisi')
      .upsert({ ...p, kaynak: 'egm', guncellendi: new Date().toISOString() },
        { onConflict: 'yil' });
    if (yazmaHatasi) {
      console.error('bes-parametre: yazilamadi:', yazmaHatasi.message);
      return jsonResponse({ ok: false, reason: 'yazilamadi' }, 500);
    }
    return jsonResponse({ ok: true, dry_run: false, okunan: p, degisti: true, yazildi: true });
  } catch (e) {
    // Ham hata metni yanıta DÖNMEZ (CLAUDE.md sunucu kuralı); log'a gider.
    console.error('bes-parametre hata:', e instanceof Error ? e.message : e);
    return jsonResponse({ ok: false, reason: 'ic_hata' }, 500);
  }
});
