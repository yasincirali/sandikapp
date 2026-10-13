// Kişiye özel AI portföy yorumu — SAF yardımcılar (0145, 2026-10-13).
//
// `portfoy-yorumla` ağ ve veritabanı işini yapar; buradaki her şey girdi alıp
// çıktı döner ki `supabase/tests/portfoy_yorum_test.ts` Anthropic'e ve
// Postgres'e dokunmadan sınayabilsin.
//
// ── Varlık notundan farkı ───────────────────────────────────────────────────
// Varlık notu (`analiz.ts`) herkese aynıdır ve piyasa verisi taşır. Bu yorum
// KİŞİNİN portföyünü anlatır; ölçümleri telefon hesaplar (Performans'taki
// sayılarla aynı kaynak — yüzeyler arası fark olmasın) ve fonksiyona yollar.
// Sunucu sayıların DOĞRULUĞUNU denetleyemez (kişinin kendi verisi; yanlışsa
// yalnız kendini yanıltır); denetlediği şey BİÇİMDİR:
//   1) Pakette tutar yok. Gösterim yalnız yüzde / puan / gün / küçük adet;
//      ₺ $ € ve 4+ haneli sayı hiçbir alanda geçemez. Veri minimizasyonu
//      istemcinin iyi niyetine bırakılmaz.
//   2) Dönem KAPANMIŞ bir takvim dönemi (geçen hafta Pzt–Paz, geçen ay).
//      Kayan pencere her gün değişir ve "kaydet, yeniden yazma" kuralını
//      (yasin, 12 Eki) boşa çıkarır.
//
// ── Dil kapısı: danışmanlık sınırı daha yakın ───────────────────────────────
// Varlık notunun yasakları (`YASAK`) aynen geçerli. Kişiye özel metin "şunu
// azalt" dediği an kişiye özel yatırım tavsiyesine döner; yönlendirme fiili,
// gereklilik/öneri kipi, değer yargısı ve gelecek dili de reddedilir.
// "Portföyünün %46'sı tek varlıkta" yazılır; "bu riskli, azaltmalısın" yazılmaz.

import { gunAy, NOT_SEMASI, sayilar, YASAK } from './analiz.ts';
import { gunEkle } from './balina.ts';

export type YorumTuru = 'haftalik' | 'aylik';

export type YorumOlcumu = {
  anahtar: string;
  /// Okunur ad, varlık adı burada ('THYAO payı').
  ad: string;
  /// Metinde ve kanıt çipinde aynen kullanılacak gösterim ('+%4,2').
  gosterim: string;
};

export type YorumPaketi = {
  tur: YorumTuru;
  baslangic: string;
  bitis: string;
  parmak_izi: string;
  olcumler: YorumOlcumu[];
};

export type Dogrulama = { gecti: true; paket: YorumPaketi } | { gecti: false; neden: string };

// ── Dönem ───────────────────────────────────────────────────────────────────

/// [bugunIso]'dan önceki son TAM hafta (Pzt–Paz). Pazar günü bile içinde
/// bulunulan hafta henüz kapanmadı: bir önceki döner.
export function sonKapaliHafta(bugunIso: string): { baslangic: string; bitis: string } {
  const d = new Date(`${bugunIso}T12:00:00Z`);
  const haftaGunu = (d.getUTCDay() + 6) % 7; // Pzt=0 … Paz=6
  const buPazartesi = gunEkle(bugunIso, -haftaGunu);
  const bas = gunEkle(buPazartesi, -7);
  return { baslangic: bas, bitis: gunEkle(bas, 6) };
}

/// [bugunIso]'dan önceki tam takvim ayı.
export function sonKapaliAy(bugunIso: string): { baslangic: string; bitis: string } {
  const [y, a] = bugunIso.split('-').map(Number);
  const [oy, oa] = a === 1 ? [y - 1, 12] : [y, a - 1];
  const bas = `${oy}-${String(oa).padStart(2, '0')}-01`;
  const bit = gunEkle(`${y}-${String(a).padStart(2, '0')}-01`, -1);
  return { baslangic: bas, bitis: bit };
}

export function beklenenDonem(tur: YorumTuru, bugunIso: string) {
  return tur === 'haftalik' ? sonKapaliHafta(bugunIso) : sonKapaliAy(bugunIso);
}

// ── Paket denetimi ──────────────────────────────────────────────────────────

const ANAHTAR = /^[a-z][a-z0-9_]{0,39}$/;
const ISO_GUN = /^\d{4}-\d{2}-\d{2}$/;
const PARMAK_IZI = /^[A-Za-z0-9:_.,|=-]{1,128}$/;

/// İzinli gösterim biçimleri — `fmtPct` / `fmtPctIsaretli` (1–2 ondalık),
/// puan, gün ve küçük adet. Tutar biçimi ('₺3,32Mr', '1.234,56') yok.
const GOSTERIM: RegExp[] = [
  /^[+−]?%-?\d{1,3}(?:\.\d{3})?(?:,\d{1,2})?$/,
  /^[+−]?\d{1,3}(?:,\d{1,2})? puan$/,
  /^\d{1,4} gün$/,
  /^\d{1,3}$/,
];

/// Hiçbir alanda geçemeyenler: para birimi ve 4+ haneli sayı (tutar, adet,
/// hesap numarası kaçırma yolu). Varlık adlarında rakam olabilir ('GLDTR',
/// 'ALTIN 22 AYAR') ama tutar boyunda olmaz.
const TUTAR_IZI = /[₺$€£]|\bTL\b|\bTRY\b|\bUSD\b|\d{4,}|\d{1,3}(?:\.\d{3})+(?!,\d*%)/u;

export const OLCUM_UST_SINIRI = 30;

export function paketiDogrula(govde: unknown, bugunIso: string): Dogrulama {
  const g = govde as Partial<YorumPaketi> | null;
  if (!g || typeof g !== 'object') return { gecti: false, neden: 'govde' };
  if (g.tur !== 'haftalik' && g.tur !== 'aylik') return { gecti: false, neden: 'tur' };
  if (typeof g.baslangic !== 'string' || typeof g.bitis !== 'string' ||
      !ISO_GUN.test(g.baslangic) || !ISO_GUN.test(g.bitis)) {
    return { gecti: false, neden: 'donem' };
  }
  const beklenen = beklenenDonem(g.tur, bugunIso);
  if (g.baslangic !== beklenen.baslangic || g.bitis !== beklenen.bitis) {
    return { gecti: false, neden: 'donem' };
  }
  if (typeof g.parmak_izi !== 'string' || !PARMAK_IZI.test(g.parmak_izi)) {
    return { gecti: false, neden: 'parmak_izi' };
  }
  if (!Array.isArray(g.olcumler) || g.olcumler.length < 2 || g.olcumler.length > OLCUM_UST_SINIRI) {
    return { gecti: false, neden: 'olcum_sayisi' };
  }
  const goruldu = new Set<string>();
  const olcumler: YorumOlcumu[] = [];
  for (const o of g.olcumler as unknown[]) {
    const x = o as Partial<YorumOlcumu> | null;
    if (!x || typeof x.anahtar !== 'string' || typeof x.ad !== 'string' || typeof x.gosterim !== 'string') {
      return { gecti: false, neden: 'olcum_yapi' };
    }
    if (!ANAHTAR.test(x.anahtar) || goruldu.has(x.anahtar)) return { gecti: false, neden: 'olcum_anahtar' };
    goruldu.add(x.anahtar);
    const ad = x.ad.trim();
    if (ad.length < 2 || ad.length > 80) return { gecti: false, neden: 'olcum_ad' };
    if (!GOSTERIM.some((r) => r.test(x.gosterim!))) return { gecti: false, neden: 'olcum_gosterim' };
    if (TUTAR_IZI.test(ad) || /[₺$€£]/u.test(x.gosterim)) return { gecti: false, neden: 'tutar' };
    olcumler.push({ anahtar: x.anahtar, ad, gosterim: x.gosterim });
  }
  return {
    gecti: true,
    paket: { tur: g.tur, baslangic: g.baslangic, bitis: g.bitis, parmak_izi: g.parmak_izi, olcumler },
  };
}

// ── İstek ───────────────────────────────────────────────────────────────────

/// Model seçimi (yasin, 12 Eki 23:25 "dediğin gibi ilerle"): haftalık yorum
/// dar ve kalıplı bir iş → Haiku 5.5; aylık yorum iki ölçümü birleştiren
/// "asıl hikâye"yi bulmalı → Sonnet 5.5. Bayrak açılmadan önce 30 örnekle
/// yan yana karşılaştırılır; Haiku'nun ret oranı %10'u geçerse haftalık da
/// Sonnet'e alınır (tek satır).
export const MODEL: Record<YorumTuru, string> = {
  haftalik: 'claude-haiku-5-5',
  aylik: 'claude-sonnet-5-5',
};
export const TAVAN_MODELI = 'claude-haiku-5-5';

/// Sabit sistem talimatı — önbelleğe alınır; değişirse her istek tam fiyat.
export const SISTEM_TALIMATI = `Sen sandık adlı bir portföy takip uygulamasında, kullanıcının KENDİ portföyünün geçmiş bir dönemini anlatan kısa yorumlar yazan bir editörsün.

Görev: Sana bir portföyün kapanmış bir dönemine (bir hafta ya da bir ay) ait ÖLÇÜMLER verilecek. Bu ölçümlere dayanarak o dönemde portföyde ne olduğunu betimle: getirinin nereden geldiği, ağırlığın nerede olduğu, dönem içindeki en büyük geri çekilme gibi.

Kesin kurallar:
1. Yalnız verilen ölçümleri kullan. Metne yazdığın her sayı, bir ölçümün "gosterim" ya da "ad" alanında AYNEN geçmeli. Hesap yapma, yuvarlama, toplama, iki sayıyı karşılaştırıp yeni sayı türetme.
2. Yalnız geçmişi anlat. Tahmin, beklenti, "devam edebilir", "önümüzdeki dönemde" gibi gelecek dili yok.
3. Hiçbir şey önerme ve yönlendirme. "azalt", "artır", "çeşitlendir", "dengele", "ağırlık ver", "yeniden dağıt", "al", "sat", "tut", "ekle", "çık" yok. "-meli/-malı", "önerilir", "mantıklı olur", "düşünebilir", "gerekir" gibi kipler yok.
4. Değer yargısı yok: portföyü ya da bir varlığı "riskli", "güvenli", "iyi", "kötü", "agresif", "dengeli", "başarılı" diye niteleme. Oranı yaz, yorumu okura bırak.
5. Kullanıcıya "portföyün" diye ikinci tekil şahısla seslen; sade Türkçe; ünlem ve emoji yok. "Yatırım tavsiyesi değildir" yazma; uygulama kendisi ekler.
6. Dönem sakinse kısa yaz: başlık + 1–2 madde yeter.

Çıktı: "baslik" tek cümle (en çok 140 karakter), dönemin en önemli gözlemi. "maddeler" en az 1, en çok 4; her madde tek cümle (en çok 220 karakter) ve "kanit" alanında dayandığı ölçümlerin "anahtar" değerleri.`;

export function kullaniciMesaji(p: YorumPaketi): string {
  const donem = p.tur === 'haftalik' ? 'hafta' : 'ay';
  return [
    `Dönem (${donem}): ${gunAy(p.baslangic)} – ${gunAy(p.bitis)}`,
    'Ölçümler:',
    JSON.stringify(p.olcumler.map(({ anahtar, ad, gosterim }) => ({ anahtar, ad, gosterim })), null, 1),
  ].join('\n');
}

export function istekGovdesi(p: YorumPaketi, model: string): Record<string, unknown> {
  return {
    model,
    max_tokens: 4000,
    system: [{ type: 'text', text: SISTEM_TALIMATI, cache_control: { type: 'ephemeral' } }],
    messages: [{ role: 'user', content: kullaniciMesaji(p) }],
    output_config: { format: { type: 'json_schema', schema: NOT_SEMASI }, effort: 'low' },
  };
}

// ── Kapı ────────────────────────────────────────────────────────────────────

/// Kişiye özel ek yasaklar (Türkçe ekleriyle). Kelime başı sınırı: 'artış'
/// (betimleyici) serbest, 'artırmalı'/'artırabilirsin' yasak.
export const KISISEL_YASAK: RegExp[] = [
  /(^|[^\p{L}])(azalt|artır|arttır|çeşitlendir|dengele|yeniden dağıt|ağırlık ver)/iu,
  /(^|[^\p{L}])(tut(un|mal|abilir))/iu,
  /\p{L}(meli|malı)(sin|sın|siniz|sınız|dir|dır)?([^\p{L}]|$)/iu,
  /mantıklı ol|düşünebilir|gözden geçir|dikkat et|değerlendirebilir/iu,
  /(^|[^\p{L}])(riskli|güvenli|agresif|başarılı|başarısız|kötü|iyi bir)([^\p{L}]|$)/iu,
  /önümüzdeki|gelecek (hafta|ay|dönem)|devam edebilir|sürebilir/iu,
];

export type YorumMaddesi = { metin: string; kanit: string[] };
export type Yorum = { baslik: string; maddeler: YorumMaddesi[] };
export type KapiSonucu = { gecti: true; yorum: Yorum } | { gecti: false; neden: string };

export function kapidanGecir(n: unknown, p: YorumPaketi): KapiSonucu {
  const y = n as Yorum;
  if (!y || typeof y.baslik !== 'string' || !Array.isArray(y.maddeler)) {
    return { gecti: false, neden: 'yapi: baslik/maddeler yok' };
  }
  const baslik = y.baslik.trim();
  if (baslik.length < 10 || baslik.length > 200) return { gecti: false, neden: 'yapi: baslik uzunlugu' };
  if (y.maddeler.length < 1 || y.maddeler.length > 4) return { gecti: false, neden: 'yapi: madde sayisi' };
  const anahtarlar = new Set(p.olcumler.map((o) => o.anahtar));
  const maddeler: YorumMaddesi[] = [];
  for (const m of y.maddeler) {
    if (typeof m?.metin !== 'string' || m.metin.trim().length < 5 || m.metin.length > 300) {
      return { gecti: false, neden: 'yapi: madde metni' };
    }
    if (!Array.isArray(m.kanit) || m.kanit.some((k) => !anahtarlar.has(k))) {
      return { gecti: false, neden: 'kanit: bilinmeyen olcum anahtari' };
    }
    maddeler.push({ metin: m.metin.trim(), kanit: m.kanit });
  }

  const izinli = new Set<string>();
  for (const o of p.olcumler) {
    sayilar(o.gosterim).forEach((s) => izinli.add(s));
    sayilar(o.ad).forEach((s) => izinli.add(s));
  }
  for (const t of [p.baslangic, p.bitis]) sayilar(gunAy(t)).forEach((s) => izinli.add(s));

  for (const metin of [baslik, ...maddeler.map((m) => m.metin)]) {
    for (const s of sayilar(metin)) {
      if (!izinli.has(s)) return { gecti: false, neden: `sayi: ${s} girdide yok` };
    }
    for (const r of [...YASAK, ...KISISEL_YASAK]) {
      if (r.test(metin)) return { gecti: false, neden: `dil: ${r.source.slice(0, 40)}` };
    }
  }
  return { gecti: true, yorum: { baslik, maddeler } };
}

// ── Saklama ─────────────────────────────────────────────────────────────────

/// Son 4 hafta + 12 ay (Supabase Free 500 MB): bu günden ÖNCE başlayan
/// dönemlerin satırları silinir.
export function saklamaSiniri(tur: YorumTuru, baslangic: string): string {
  if (tur === 'haftalik') return gunEkle(baslangic, -21);
  const [y, a] = baslangic.split('-').map(Number);
  const toplam = y * 12 + (a - 1) - 11;
  return `${Math.floor(toplam / 12)}-${String((toplam % 12) + 1).padStart(2, '0')}-01`;
}
