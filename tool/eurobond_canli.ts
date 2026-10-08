// Eurobond ayrıştırıcılarının GERÇEK kaynaklara karşı sınaması (2026-10-08).
//
// `supabase/tests/eurobond_test.ts` kayıtlı örneklerle çalışır; bu betik
// aynı `_shared/eurobond.ts` fonksiyonlarını canlı Ziraat ve Frankfurt
// yanıtlarına uygular ve eurobond-fiyat'ın bir turda yazacağı şeyi döker.
// Bulut geliştirme kabı bu hostlara çıkamadığı için GitHub koşucusunda
// koşar (`kaynak-olcum.yml`). Salt okunur; secret yok.
//
//   deno run --allow-net tool/eurobond_canli.ts
import {
  BF_API,
  bfAdiniCoz,
  bfFiyatiniCoz,
  bfGecmisiniCoz,
  kuponSikligi,
  tahvilAdi,
  TARAYICI_UA,
  ZIRAAT_URL,
  ziraatTablosunuCoz,
} from '../supabase/functions/_shared/eurobond.ts';

const al = async (u: string, json: boolean) => {
  const t0 = performance.now();
  const r = await fetch(u, { headers: { 'User-Agent': TARAYICI_UA, Accept: json ? 'application/json' : 'text/html' } });
  const metin = await r.text();
  let g: unknown = metin;
  if (json) {
    try {
      g = JSON.parse(metin);
    } catch (_) {
      g = null; // boş gövde (vadesi gelen tahvil) — fonksiyon da null sayar
    }
  }
  return { g, ms: Math.round(performance.now() - t0), kod: r.status };
};

// 30/360 işlemiş faiz — Dart `EurobondSozlesmesi.islemisFaiz` eşi, yalnız sınama için.
function islemis(kupon: number, siklik: number, vade: string, gun: Date): number {
  const v = new Date(vade + 'T00:00:00Z');
  const adim = 12 / siklik;
  let onceki = v;
  for (let i = 1; ; i++) {
    const d = new Date(Date.UTC(v.getUTCFullYear(), v.getUTCMonth() - adim * i, v.getUTCDate()));
    if (d <= gun) { onceki = d; break; }
  }
  let d1 = onceki.getUTCDate(), d2 = gun.getUTCDate();
  if (d1 === 31) d1 = 30;
  if (d2 === 31 && d1 === 30) d2 = 30;
  const gecen = 360 * (gun.getUTCFullYear() - onceki.getUTCFullYear()) +
    30 * (gun.getUTCMonth() - onceki.getUTCMonth()) + (d2 - d1);
  return (100 * kupon / siklik) * gecen / (360 / siklik);
}

const z = await al(ZIRAAT_URL, false);
const banka = ziraatTablosunuCoz(z.g as string);
console.log(`Ziraat: ${z.kod} ${z.ms} ms, ${banka.length} tahvil`);

const bugun = new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate()));
let tutan = 0, kuponsuz = 0, fiyatsiz = 0;
const satirlar: string[] = [];
for (const b of banka) {
  const s = await al(`${BF_API}/tradingview/symbols?symbol=XFRA:${b.isin}`, true);
  const ad = (s.g as Record<string, unknown>)?.description;
  const c = typeof ad === 'string' ? bfAdiniCoz(ad) : null;
  if (!c || String(c.vade_yili) !== b.vade.slice(0, 4)) {
    kuponsuz++;
    satirlar.push(`${b.isin} ${b.vade} ${b.para_birimi}  kupon okunamadı (${String(ad)})`);
    continue;
  }
  const p = await al(`${BF_API}/data/price_information/single?isin=${b.isin}&mic=XFRA`, true);
  const f = bfFiyatiniCoz(p.g);
  if (!f) {
    fiyatsiz++;
    satirlar.push(`${tahvilAdi(c.kupon_orani, b.vade)} ${b.isin}  Frankfurt fiyatı yok · banka ${b.banka_alis}/${b.banka_satis}`);
    continue;
  }
  const isl = islemis(c.kupon_orani, kuponSikligi(b.para_birimi), b.vade, bugun);
  const kirli = f.temiz_fiyat + isl;
  const ici = kirli >= b.banka_alis - 0.5 && kirli <= b.banka_satis + 0.5;
  if (ici) tutan++;
  satirlar.push(
    `${tahvilAdi(c.kupon_orani, b.vade).padEnd(22)} ${b.isin} temiz ${f.temiz_fiyat.toFixed(3)} + işl ${isl.toFixed(3)} = ${kirli.toFixed(3)}` +
      ` | banka ${b.banka_alis.toFixed(3)}/${b.banka_satis.toFixed(3)} ${ici ? 'TUTARLI' : 'FARKLI'} (${p.ms} ms)`,
  );
}
console.log(satirlar.join('\n'));
console.log(`\nÖzet: ${banka.length} tahvil · kirli fiyat banka aralığında ${tutan} · kupon okunamayan ${kuponsuz} · Frankfurt fiyatı olmayan ${fiyatsiz}`);

const h = await al(`${BF_API}/tradingview/history?symbol=XFRA:US900123DG28&resolution=1D&from=${Math.floor(Date.now() / 1000) - 5 * 366 * 86400}&to=${Math.floor(Date.now() / 1000)}`, true);
const g = bfGecmisiniCoz(h.g);
console.log(`Geçmiş DG28 1D 5y: ${g.length} nokta, ${h.ms} ms, ilk ${new Date(g[0]?.[0] ?? 0).toISOString().slice(0, 10)}`);
const h15 = await al(`${BF_API}/tradingview/history?symbol=XFRA:US900123DG28&resolution=15&from=${Math.floor(Date.now() / 1000) - 86400 * 3}&to=${Math.floor(Date.now() / 1000)}`, true);
console.log(`Geçmiş DG28 15dk 3g: ${bfGecmisiniCoz(h15.g).length} nokta, ${h15.ms} ms`);
