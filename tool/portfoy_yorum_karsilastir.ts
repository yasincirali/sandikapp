// AI portföy yorumu — haftalık model kararı için 30 örnek karşılaştırması
// (0145, 2026-10-14).
//
// ## Neden
// `_shared/portfoy_yorum.ts` › `MODEL`: haftalık yorum Haiku 5.5, aylık
// Sonnet 5.5. Karar (yasin, 12 Eki): bayrak açılmadan önce 30 örnek yan
// yana; Haiku'nun ret oranı %10'u geçerse haftalık da Sonnet'e geçer (tek
// satır). Bu betik aynı 30 haftalık paketi iki modele, fonksiyonun BİREBİR
// isteğiyle (`istekGovdesi`) yollar ve fonksiyonun kapısından
// (`kapidanGecir`) geçirir; ret oranı ve maliyet karşılaştırılır.
//
// ## Neden uydurma paket
// Örnekler sentetik ve sabit tohumlu: gerçek kullanıcının portföyü buraya
// (ve public repo'nun Actions çıktısına) girmez. Biçim istemcinin ürettiğiyle
// aynı (`PortfoyYorumPaketi.kur`: etiketler, `fmtPctIsaretli` gösterimi,
// U+2212 eksi). Her paket önce `paketiDogrula`dan geçer — sunucunun kabul
// etmeyeceği paket ölçülmez.
//
// ## Kullanım
// Actions › "Portföy yorumu model karşılaştırması" (secret
// `ANTHROPIC_API_KEY`). Yerelde:
//   ANTHROPIC_API_KEY=… deno run --allow-net --allow-env --allow-write \
//     tool/portfoy_yorum_karsilastir.ts [cikti.md]
// Anahtar hiçbir çıktıya yazılmaz. 60 istek, toplam birkaç sent.

import {
  beklenenDonem,
  istekGovdesi,
  kapidanGecir,
  paketiDogrula,
  type YorumOlcumu,
  type YorumPaketi,
} from '../supabase/functions/_shared/portfoy_yorum.ts';
import { maliyetUsd } from '../supabase/functions/_shared/analiz.ts';

const ORNEK = 30;
const ESIK = 0.10;
const MODELLER = ['claude-haiku-5-5', 'claude-sonnet-5-5'] as const;
const BUGUN = '2026-10-13';

// ── Sentetik paketler ──────────────────────────────────────────────────────

function tohumlu(tohum: number): () => number {
  let s = tohum >>> 0;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/// `fmtPct(v, digits: 1)`: '%4,2'; `fmtPctIsaretli`: '+%4,2' / '−%4,2' / '%0,0'.
function pay(v: number): string {
  return `%${v.toFixed(1).replace('.', ',')}`;
}
function isaretli(v: number): string {
  const m = pay(Math.abs(v));
  if (m === '%0,0') return m;
  return `${v > 0 ? '+' : '−'}${m}`;
}

const VARLIKLAR: [string, string][] = [
  ['THYAO', 'Hisse'], ['ASELS', 'Hisse'], ['BIMAS', 'Hisse'], ['TUPRS', 'Hisse'],
  ['KCHOL', 'Hisse'], ['SISE', 'Hisse'], ['AFT', 'Fon'], ['TTE', 'Fon'], ['IPJ', 'Fon'],
  ['YAY', 'Fon'], ['Gram Altın', 'Altın'], ['Çeyrek Altın', 'Altın'], ['USD', 'Döviz'],
  ['EUR', 'Döviz'], ['BTC', 'Kripto'], ['ETH', 'Kripto'], ['Gümüş', 'Emtia'],
];

function paketUret(i: number): YorumPaketi {
  const r = tohumlu(1000 + i);
  const n = 2 + Math.floor(r() * 9); // 2–10 varlık
  const secili = [...VARLIKLAR].sort(() => r() - 0.5).slice(0, n);
  // Sakin, olağan ve sert haftalar karışık.
  const oynaklik = [0.4, 2, 6][i % 3];
  const degisim = secili.map(() => (r() - 0.45) * oynaklik * 2);
  const agirlik = secili.map(() => 0.2 + r() * r() * 5);
  const toplam = agirlik.reduce((a, b) => a + b, 0);
  const paylar = agirlik.map((a) => (a / toplam) * 100);
  const getiri = degisim.reduce((t, d, k) => t + d * paylar[k] / 100, 0);

  // İstemci adında tutar izi olan ölçümü hiç koymaz (`tutarIziVar`;
  // sunucudaki `TUTAR_IZI` ile aynı): 'USD' adlı varlık ölçümü düşer.
  const o: YorumOlcumu[] = [];
  const ekle = (x: YorumOlcumu) => {
    if (!/[₺$€£]|\bTL\b|\bTRY\b|\bUSD\b|\d{4,}|\d{1,3}(?:\.\d{3})+(?!,\d*%)/u.test(x.ad)) o.push(x);
  };
  ekle({ anahtar: 'getiri', ad: 'Dönem getirisi', gosterim: isaretli(getiri) });
  const sirali = degisim.map((d, k) => [d, k] as const).sort((a, b) => b[0] - a[0]);
  const [iyiD, iyiK] = sirali[0];
  const [zayD, zayK] = sirali[sirali.length - 1];
  ekle({ anahtar: 'en_iyi', ad: `Dönemin en çok değer kazanan varlığı: ${secili[iyiK][0]}`, gosterim: isaretli(iyiD) });
  if (zayK !== iyiK) {
    ekle({ anahtar: 'en_zayif', ad: `Dönemin en zayıf varlığı: ${secili[zayK][0]}`, gosterim: isaretli(zayD) });
  }
  const turlar = new Map<string, number>();
  secili.forEach(([, tur], k) => turlar.set(tur, (turlar.get(tur) ?? 0) + paylar[k]));
  [...turlar.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).forEach(([tur, p]) => {
    ekle({ anahtar: `tur_payi_${tur.toLowerCase().replace('ı', 'i').replace('ö', 'o')}`, ad: `Dönem sonunda ${tur} payı`, gosterim: pay(p) });
  });
  const buyuk = paylar.indexOf(Math.max(...paylar));
  ekle({ anahtar: 'en_buyuk_pay', ad: `Dönem sonunda en büyük pay: ${secili[buyuk][0]}`, gosterim: pay(paylar[buyuk]) });
  ekle({ anahtar: 'pozisyon_sayisi', ad: 'Dönem sonunda varlık sayısı', gosterim: `${n}` });
  if (oynaklik > 0.5 || r() < 0.3) {
    const dd = Math.max(0.3, Math.abs(zayD) * (0.5 + r()));
    ekle({ anahtar: 'en_derin_dusus', ad: 'Dönem içindeki en derin geri çekilme', gosterim: isaretli(-dd) });
    if (r() < 0.6) ekle({ anahtar: 'toparlanma', ad: 'Geri çekilmeden toparlanma süresi', gosterim: `${1 + Math.floor(r() * 5)} gün` });
  }
  return {
    tur: 'haftalik',
    ...beklenenDonem('haftalik', BUGUN),
    parmak_izi: `v1:ornek${String(i).padStart(3, '0')}`,
    olcumler: o,
  };
}

// ── İstek ───────────────────────────────────────────────────────────────────

type Sonuc = {
  model: string;
  gecti: boolean;
  neden?: string;
  baslik?: string;
  maddeler?: string[];
  maliyet: number;
};

async function cagir(p: YorumPaketi, model: string, anahtar: string): Promise<Sonuc> {
  for (let deneme = 0; deneme < 3; deneme++) {
    const res = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: { 'content-type': 'application/json', 'x-api-key': anahtar, 'anthropic-version': '2023-06-01' },
      body: JSON.stringify(istekGovdesi(p, model)),
    });
    if (res.status === 429 || res.status >= 500) {
      await new Promise((r) => setTimeout(r, 2000 * (deneme + 1)));
      continue;
    }
    // deno-lint-ignore no-explicit-any
    const y: any = await res.json();
    if (!res.ok) return { model, gecti: false, neden: `api ${res.status}: ${y?.error?.type ?? '?'}`, maliyet: 0 };
    const maliyet = maliyetUsd(model, y.usage ?? {}, false) ?? 0;
    if (y.stop_reason !== 'end_turn') return { model, gecti: false, neden: `stop_reason: ${y.stop_reason}`, maliyet };
    // deno-lint-ignore no-explicit-any
    const metin = (y.content ?? []).filter((c: any) => c.type === 'text').map((c: any) => c.text).join('');
    let k;
    try {
      k = kapidanGecir(JSON.parse(metin), p);
    } catch (_) {
      return { model, gecti: false, neden: 'yapi: json degil', maliyet };
    }
    if (!k.gecti) return { model, gecti: false, neden: k.neden, maliyet };
    return { model, gecti: true, baslik: k.yorum.baslik, maddeler: k.yorum.maddeler.map((m) => m.metin), maliyet };
  }
  return { model, gecti: false, neden: 'api: tekrar denemeler bitti', maliyet: 0 };
}

// ── Rapor ───────────────────────────────────────────────────────────────────

const anahtar = Deno.env.get('ANTHROPIC_API_KEY');
if (!anahtar) {
  console.error('ANTHROPIC_API_KEY yok.');
  Deno.exit(2);
}
const cikti = Deno.args[0] ?? 'portfoy_yorum_karsilastirma.md';

const paketler: YorumPaketi[] = [];
for (let i = 0; i < ORNEK; i++) {
  const p = paketUret(i);
  const d = paketiDogrula(p, BUGUN);
  if (!d.gecti) throw new Error(`örnek ${i} sunucu doğrulamasından geçmiyor: ${d.neden}`);
  paketler.push(d.paket);
}

const sonuclar: Sonuc[][] = [];
for (const [i, p] of paketler.entries()) {
  sonuclar.push(await Promise.all(MODELLER.map((m) => cagir(p, m, anahtar))));
  console.log(`örnek ${i + 1}/${ORNEK}: ${sonuclar[i].map((s) => `${s.model.split('-')[1]} ${s.gecti ? 'geçti' : 'RED'}`).join(', ')}`);
}

const satirlar: string[] = ['# Portföy yorumu: haftalık model karşılaştırması', ''];
satirlar.push(`${ORNEK} sentetik haftalık paket, fonksiyonun isteği ve kapısı birebir. Eşik: Haiku reddi > %${ESIK * 100} ise haftalık Sonnet'e geçer.`, '');
satirlar.push('| Model | Geçti | Red | Red oranı | Toplam maliyet | Örnek başı |', '|---|---|---|---|---|---|');
const ozet: Record<string, number> = {};
for (const [k, m] of MODELLER.entries()) {
  const s = sonuclar.map((x) => x[k]);
  const red = s.filter((x) => !x.gecti).length;
  const maliyet = s.reduce((t, x) => t + x.maliyet, 0);
  ozet[m] = red / ORNEK;
  satirlar.push(`| ${m} | ${ORNEK - red} | ${red} | %${(red / ORNEK * 100).toFixed(1)} | $${maliyet.toFixed(4)} | $${(maliyet / ORNEK).toFixed(5)} |`);
}
const karar = ozet['claude-haiku-5-5'] > ESIK
  ? 'Haiku eşiği aştı → haftalık Sonnet 5.5\'e geçmeli (`MODEL.haftalik`).'
  : 'Haiku eşiğin altında → haftalık Haiku 5.5 kalır.';
satirlar.push('', `**Karar:** ${karar}`, '');

satirlar.push('## Red nedenleri', '');
for (const [k, m] of MODELLER.entries()) {
  const nedenler = sonuclar.map((x) => x[k]).filter((x) => !x.gecti).map((x) => x.neden);
  satirlar.push(`- ${m}: ${nedenler.length ? nedenler.join('; ') : 'yok'}`);
}
satirlar.push('', '## Örnekler (yan yana)', '');
for (const [i, p] of paketler.entries()) {
  satirlar.push(`### ${i + 1}. ${p.olcumler.map((o) => `${o.anahtar} ${o.gosterim}`).join(' · ')}`, '');
  for (const s of sonuclar[i]) {
    if (!s.gecti) {
      satirlar.push(`- **${s.model}** — RED (${s.neden})`);
      continue;
    }
    satirlar.push(`- **${s.model}** — ${s.baslik}`);
    for (const m of s.maddeler ?? []) satirlar.push(`  - ${m}`);
  }
  satirlar.push('');
}
await Deno.writeTextFile(cikti, satirlar.join('\n'));
console.log(`\n${karar}\nRapor: ${cikti}`);
