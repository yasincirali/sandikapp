// Bildirim kartı — push'un açılınca görünen markalı görseli (2026-10-01).
//
// ## Neden
// Kullanıcı (yasin) bildirimlerin "C · Kart" tasarımını seçti: koyu yeşil
// zemin, ikonun amber dalgaları, Dynamic Island'daki renkli yön halkası ve
// büyük rakam. Tasarım dosyası: proje klasörü `bildirim-secenekleri/`.
//
// ## Yalnız yeni sürüme (kullanıcı kuralı, 2026-10-01)
// "Store kullanıcılarını etkilemesin, yeni versiyondan güncellenmiş olsun."
// Kart, token satırı `bildirim_surumu >= KART_SURUMU` olan cihazlara gider
// (0092; yalnız yeni istemci yazar). Eski sürümlerin satırı NULL kalır ve
// FCM gövdesi BİREBİR eskisi gibi kurulur — `gorselUrl` verilmezse
// `sendFcmNotification` hiçbir yeni alan eklemez (fcm_send_test kilitler).
//
// ## Görsel nasıl taşınır
// FCM `notification.image` bir URL ister; Android onu kendisi indirir ve
// gösterir (kapalıyken küçük resim, aşağı çekince tam kart). URL,
// `bildirim-karti` fonksiyonuna gider; kartın verisi sorgu dizesinde
// taşınır ve HMAC ile imzalanır — imzasız istek 403 alır, bizim alan
// adımızda keyfi metinli görsel üretilemez. Anahtar her fonksiyonda zaten
// bulunan `SUPABASE_SERVICE_ROLE_KEY`; yeni secret gerekmez. Tokyo ve
// Frankfurt'un anahtarı farklıdır ama URL'yi üreten ve çözen aynı projedir.
//
// ## Ne YAZILMAZ
// Tutar yok (kilit ekranında görünür): yalnız kod, yüzde/fiyat ve kısa
// bağlam. Grafik çizgisi yok: bu fonksiyonların elinde seri yok ve
// "uydurma sayı yasak" (fiyat kaynağı sözleşmesi) — eğri ancak gerçek
// seriyle eklenebilir.

/// Kartı alabilen en düşük `user_push_tokens.bildirim_surumu`.
export const KART_SURUMU = 2;

export type KartYonu = 'u' | 'd' | 'n';

export type KartVerisi = {
  /// Varlık kodu ya da adı — kartın üst satırı (≤ 14 karakter).
  e: string;
  /// Büyük satır, yön oku HARİÇ: "%4,2" ya da "₺321,40" (≤ 12 karakter).
  b: string;
  /// Yön: yukarı / aşağı / nötr.
  y: KartYonu;
  /// Halkanın doluluğu için yüzde (−3…+3 tam tur yarısı). Yoksa halka
  /// yön renginde tam çizilir (fiyat alarmı: değişim değil eşik).
  p?: number;
  /// Alt satır — bağlam (≤ 32 karakter; kartın sağ yarısına sığar).
  a: string;
};

const SINIR = { e: 14, b: 12, a: 32 } as const;

/// Kart verisini kısaltır ve doğrular. Geçersizse null — çağıran görselsiz
/// gönderir (bildirim yine gider).
export function kartVerisiniHazirla(v: KartVerisi): KartVerisi | null {
  const e = v.e.trim().slice(0, SINIR.e);
  const b = v.b.trim().slice(0, SINIR.b);
  const a = v.a.trim().slice(0, SINIR.a);
  if (e === '' || b === '') return null;
  if (!['u', 'd', 'n'].includes(v.y)) return null;
  const p = v.p === undefined || !Number.isFinite(v.p)
    ? undefined
    : Math.round(v.p * 100) / 100;
  return p === undefined ? { e, b, y: v.y, a } : { e, b, y: v.y, p, a };
}

/// Türkçe biçim: 4.2 → "4,2" (tek ondalık, işaretsiz).
export function yuzdeYazisi(pct: number): string {
  return Math.abs(pct).toFixed(1).replace('.', ',');
}

/// Günlük değişim kartı (brifing, takip listesi): yüzde hem büyük satırda
/// hem halkada.
export function degisimKarti(etiket: string, pct: number, alt: string): KartVerisi | null {
  if (!Number.isFinite(pct)) return null;
  return kartVerisiniHazirla({
    e: etiket,
    b: `%${yuzdeYazisi(pct)}`,
    y: pct > 0 ? 'u' : pct < 0 ? 'd' : 'n',
    p: pct,
    a: alt,
  });
}

/// Kartı üretecek ayar — `kartUrl`'nin iki girdisi. Verilmezse (kuru koşu,
/// eksik env) kart hiç üretilmez.
export type KartAyari = { supabaseUrl: string; anahtar: string };

/// Bu cihaza kart gönderilebilir mi? Eski sürümlerin satırı NULL'dır.
export function kartAlabilir(t: { bildirim_surumu?: number | null }): boolean {
  return (t.bildirim_surumu ?? 0) >= KART_SURUMU;
}

/// Token kartı alabiliyorsa imzalı URL, değilse `undefined` — yani eski
/// gövde. Hata YUTULUR: görsel yüzünden bildirim düşmemeli.
export async function kartGorseli(
  ayar: KartAyari | null | undefined,
  token: { bildirim_surumu?: number | null },
  veri: KartVerisi | null,
): Promise<string | undefined> {
  if (!ayar || !veri || !kartAlabilir(token)) return undefined;
  try {
    return await kartUrl(ayar.supabaseUrl, ayar.anahtar, veri);
  } catch (e) {
    console.error('[bildirim-karti] url uretilemedi:', e instanceof Error ? e.message : String(e));
    return undefined;
  }
}

// ── İmza ─────────────────────────────────────────────────────────────────

function b64url(bytes: Uint8Array): string {
  let s = '';
  for (const x of bytes) s += String.fromCharCode(x);
  return btoa(s).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}

function b64urlCoz(s: string): Uint8Array {
  const t = s.replaceAll('-', '+').replaceAll('_', '/');
  const ham = atob(t + '='.repeat((4 - (t.length % 4)) % 4));
  return Uint8Array.from(ham, (c) => c.charCodeAt(0));
}

async function imza(anahtar: string, d: string): Promise<string> {
  const k = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(`bildirim-karti:${anahtar}`),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = new Uint8Array(
    await crypto.subtle.sign('HMAC', k, new TextEncoder().encode(d)),
  );
  // 128 bit yeter: tahmin edilemez olması yeterli, URL kısa kalsın.
  return b64url(mac.slice(0, 16));
}

/// `bildirim-karti` fonksiyonunun imzalı URL'si.
export async function kartUrl(
  supabaseUrl: string,
  anahtar: string,
  veri: KartVerisi,
): Promise<string> {
  const d = b64url(new TextEncoder().encode(JSON.stringify(veri)));
  const s = await imza(anahtar, d);
  return `${supabaseUrl.replace(/\/+$/, '')}/functions/v1/bildirim-karti?d=${d}&s=${s}`;
}

/// İmzayı doğrular ve veriyi çözer; herhangi bir aksaklıkta null.
export async function kartUrlCoz(
  anahtar: string,
  d: string | null,
  s: string | null,
): Promise<KartVerisi | null> {
  if (!d || !s || d.length > 600) return null;
  const beklenen = await imza(anahtar, d);
  if (beklenen.length !== s.length) return null;
  let fark = 0;
  for (let i = 0; i < s.length; i++) fark |= beklenen.charCodeAt(i) ^ s.charCodeAt(i);
  if (fark !== 0) return null;
  try {
    const ham = JSON.parse(new TextDecoder().decode(b64urlCoz(d))) as KartVerisi;
    return kartVerisiniHazirla(ham);
  } catch (_) {
    return null;
  }
}

// ── Çizim ────────────────────────────────────────────────────────────────

const RENK = {
  zemin: '#0A1E15',
  amber: '#F5A623',
  altin: '#F5C842',
  kazanc: '#3DB77F',
  kayip: '#FF6B52',
  notr: 'rgba(255,255,255,0.55)',
} as const;

function kacis(s: string): string {
  return s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;').replaceAll("'", '&apos;');
}

/// Yön işareti ÇİZİLİR, yazılmaz: DM Sans'ta ▲▼◆ glifi yok (₺ var) ve
/// sunucu yalnız DM Sans yükler — metin olarak basılsa boş kutu çıkardı.
/// (x, y) işaretin sol-alt köşesi, h yüksekliği.
function yonIsareti(y: KartYonu, x: number, taban: number, h: number, renk: string): string {
  const w = h * 1.15;
  if (y === 'u') {
    return `<polygon points="${x},${taban} ${x + w},${taban} ${x + w / 2},${taban - h}" fill="${renk}"/>`;
  }
  if (y === 'd') {
    return `<polygon points="${x},${taban - h} ${x + w},${taban - h} ${x + w / 2},${taban}" fill="${renk}"/>`;
  }
  const m = taban - h / 2;
  return `<polygon points="${x + w / 2},${taban - h} ${x + w},${m} ${x + w / 2},${taban} ${x},${m}" fill="${renk}"/>`;
}

/// İkondaki dalga (kenarlarda çukur, ortada tepe), 64'lük tuvalde.
function dalga(b: number, a = 9): string {
  return `M-2 ${b + a * 0.45} C4 ${b + a * 0.9} 8 ${b + a} 13 ${b + a} ` +
    `C21 ${b + a} 24 ${b} 32 ${b} C40 ${b} 43 ${b + a} 51 ${b + a} ` +
    `C56 ${b + a} 60 ${b + a * 0.9} 66 ${b + a * 0.45} V70 H-2 Z`;
}

/// Marka işareti ("E · İkon-sandık", `SandikLogoMark.swift` ile aynı).
function isaret(): string {
  const kasa = 'M20,4 L44,4 Q60,4 60,20 L60,23 L4,23 L4,20 Q4,4 20,4 Z ' +
    'M4,26 L60,26 L60,44 Q60,60 44,60 L20,60 Q4,60 4,44 Z';
  return `<defs><clipPath id="ik"><path d="${kasa}"/></clipPath>
<linearGradient id="ig" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#FCD35A"/><stop offset="1" stop-color="#EAA12B"/></linearGradient></defs>
<g clip-path="url(#ik)"><rect width="64" height="64" fill="url(#ig)"/>
<path d="${dalga(24)}" fill="#E2861F"/><path d="${dalga(34)}" fill="#C56314"/><path d="${dalga(44)}" fill="#993D0A"/></g>
<rect x="25.5" y="19" width="13" height="16" rx="3.5" fill="#5A2405"/>
<path d="M32 22.5 a2.6 2.6 0 0 1 1.4 4.8 l0.7 4.2 h-4.2 l0.7 -4.2 a2.6 2.6 0 0 1 1.4 -4.8 z" fill="#FCD35A"/>`;
}

/// Yön halkası — Dynamic Island'daki `SandikYonHalkasi`'nın kart hâli.
/// Merkez (cx, cy), yarıçap r; yay tepeden başlar, ±3 puan yarım tur.
function halka(v: KartVerisi, cx: number, cy: number, r: number, renk: string): string {
  const iz = `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="rgba(255,255,255,0.12)" stroke-width="${r * 0.17}"/>`;
  // Büyüklük varsa işaret küçük ve üstte, yüzde altta; yoksa işaret tek
  // başına ortada.
  const h = v.p === undefined ? r * 0.5 : r * 0.3;
  const taban = v.p === undefined ? cy + h / 2 : cy - r * 0.08;
  const merkez = yonIsareti(v.y, cx - h * 0.575, taban, h, renk) +
    (v.p === undefined ? '' :
      `<text x="${cx}" y="${cy + r * 0.45}" text-anchor="middle" font-family="DM Sans" font-weight="700" font-size="${r * 0.46}" fill="#FFFFFF">${yuzdeYazisi(v.p)}</text>`);
  if (v.p === undefined || v.y === 'n') {
    // Eşik bildirimi: büyüklük yok, yön var — halka yön renginde tam.
    const tam = v.y === 'n' ? '' :
      `<circle cx="${cx}" cy="${cy}" r="${r}" fill="none" stroke="${renk}" stroke-width="${r * 0.17}"/>`;
    return iz + tam + merkez;
  }
  const oran = Math.max(-1, Math.min(1, v.p / 3));
  const a0 = -Math.PI / 2;
  const a1 = a0 + oran * Math.PI;
  const x0 = cx + r * Math.cos(a0), y0 = cy + r * Math.sin(a0);
  const x1 = cx + r * Math.cos(a1), y1 = cy + r * Math.sin(a1);
  const yay = Math.abs(oran) < 0.004 ? '' :
    `<path d="M${x0.toFixed(2)} ${y0.toFixed(2)} A${r} ${r} 0 0 ${oran >= 0 ? 1 : 0} ${x1.toFixed(2)} ${y1.toFixed(2)}" fill="none" stroke="${renk}" stroke-width="${r * 0.17}" stroke-linecap="round"/>` +
    `<circle cx="${x1.toFixed(2)}" cy="${y1.toFixed(2)}" r="${r * 0.13}" fill="${renk}"/>`;
  return iz + yay + merkez;
}

/// Kartın SVG'si — 1200×600 (FCM/Android'in önerdiği 2:1).
///
/// Halka ortanın soluna, x 300…580 bandına oturur: Android kapalı
/// bildirimdeki küçük resmi kareye ORTADAN kırpar (x 300…900); küçük hâl
/// böylece halkayı ve rakamın başını gösterir.
export function kartSvg(v: KartVerisi): string {
  const renk = v.y === 'u' ? RENK.kazanc : v.y === 'd' ? RENK.kayip : RENK.notr;
  // Büyük satır 540 px'e sığmalı: "₺1.234,56" gibi uzun fiyatta punto
  // küçülür (DM Sans rakam genişliği ≈ 0,6 em; işaret + boşluk ≈ 1,6 em).
  const buyuk = Math.min(128, Math.floor(540 / (0.6 * v.b.length + 1.6)));
  const isaretH = buyuk * 0.62;
  const dalgalar = [[0, 0.045], [48, 0.06], [92, 0.08]].map(([b, o]) =>
    `<path d="M0 ${b} C160 ${b + 44} 240 ${b + 44} 360 ${b + 20} S640 ${b - 24} 800 ${b} S1080 ${b + 40} 1200 ${b + 12} V400 H0Z" fill="${RENK.amber}" opacity="${o}"/>`
  ).join('');
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="600" viewBox="0 0 1200 600">
<rect width="1200" height="600" fill="${RENK.zemin}"/>
<g transform="translate(0,440)">${dalgalar}</g>
${halka(v, 440, 300, 140, renk)}
<g transform="translate(640,0)">
<text x="0" y="200" font-family="DM Sans" font-weight="700" font-size="52" letter-spacing="4" fill="${RENK.altin}">${kacis(v.e)}</text>
${yonIsareti(v.y, 4, 330 - buyuk * 0.04, isaretH, renk)}
<text x="${isaretH * 1.15 + buyuk * 0.3}" y="330" font-family="DM Sans" font-weight="700" font-size="${buyuk}" fill="${renk}">${kacis(v.b)}</text>
<text x="0" y="400" font-family="DM Sans" font-weight="500" font-size="32" fill="rgba(255,255,255,0.62)">${kacis(v.a)}</text>
</g>
<g transform="translate(944,52) scale(0.8125)">${isaret()}</g>
<text x="1008" y="92" font-family="DM Sans" font-weight="700" font-size="38" fill="${RENK.altin}">sandık</text>
</svg>`;
}
