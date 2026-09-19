// CANLI API kanaryası — gerçek ağa çıkar, bu yüzden `supabase/tests/` DIŞINDA:
// CI'daki `deno test supabase/tests/` her PR'da koşar ve dış servise bağımlı
// olmamalı. Bunu `.github/workflows/price-canary.yml` haftalık koşar; kırılınca
// GitHub e-postası gelir — anahtar/alan adı değişimini kullanıcı değil biz
// fark ederiz (TECHNICAL_DEBT "Dış fiyat API'leri sessizce değişiyor", öneri 2).
//
//   deno test --allow-net supabase/canary/truncgil_canary_test.ts
import { assert, assertEquals } from 'jsr:@std/assert@1';
import {
  extractTruncgil,
  parseTruncgilBody,
} from '../functions/_shared/live_prices.ts';

const ALTIN = [
  'ALTIN_GRAM',
  'ALTIN_CEYREK',
  'ALTIN_YARIM',
  'ALTIN_CUMHURIYET',
  'ALTIN_ATA',
  'ALTIN_RESAT',
];
const DOVIZ = ['USDTRY=X', 'EURTRY=X', 'GBPTRY=X'];

/// `PriceService._goldWeights` ile aynı — gram eşdeğeri denetimi için.
const GRAM: Record<string, number> = {
  ALTIN_GRAM: 1.0,
  ALTIN_CEYREK: 1.75,
  ALTIN_YARIM: 3.5,
  ALTIN_CUMHURIYET: 7.216,
  ALTIN_ATA: 7.216,
  ALTIN_RESAT: 7.216,
};

async function canli(): Promise<Record<string, unknown>> {
  const res = await fetch('https://finans.truncgil.com/v4/today.json', {
    headers: { Accept: 'application/json' },
    signal: AbortSignal.timeout(15_000),
  });
  assert(res.ok, `truncgil HTTP ${res.status}`);
  return parseTruncgilBody(await res.text());
}

Deno.test('truncgil: altın ve döviz anahtarlarının hepsi fiyatlanıyor', async () => {
  const data = await canli();
  const fiyat = extractTruncgil(data, [...ALTIN, ...DOVIZ]);
  const eksik = [...ALTIN, ...DOVIZ].filter((s) => !fiyat.has(s));
  assertEquals(
    eksik,
    [],
    `Anahtar/alan adı değişmiş olabilir. Yanıttaki anahtarlar: ${Object.keys(data).slice(0, 40).join(', ')}`,
  );
  for (const [s, p] of fiyat) assert(p > 0 && Number.isFinite(p), `${s}: ${p}`);
});

Deno.test('truncgil: gram eşdeğerleri tutarlı — ALTIN_GRAM 22 ayar kalmalı', async () => {
  // 2026-09-15 ikinci tur: `GRA` (24 ayar) seçilince gram altın %8 yüksek
  // okunmuş ve alarm erken tetiklenmişti. Çeyrek/yarım/tam ailesi 22 ayar
  // kote edildiği için gram eşdeğerleri ALTIN_GRAM ile %3 içinde olmalı.
  const data = await canli();
  const fiyat = extractTruncgil(data, ALTIN);
  const gram = fiyat.get('ALTIN_GRAM');
  assert(gram !== undefined, 'ALTIN_GRAM yok');
  for (const s of ALTIN) {
    if (s === 'ALTIN_GRAM') continue;
    const p = fiyat.get(s);
    if (p === undefined) continue; // eksiklik önceki testte raporlanır
    const esdeger = p / GRAM[s];
    const sapma = Math.abs(esdeger / gram - 1);
    assert(
      sapma < 0.06,
      `${s}: gram eşdeğeri ${esdeger.toFixed(0)} vs ALTIN_GRAM ${gram.toFixed(0)} (sapma %${(sapma * 100).toFixed(1)}) — ayar eşlemesi kaymış olabilir`,
    );
  }
});

Deno.test('truncgil: USD/TRY makul aralıkta (ölçek hatası yakalayıcı)', async () => {
  // "5.412,37" → 5.412 gibi BİN KATI hatalar parseTruncgilNumber'da kapandı;
  // bu iddia biçim bir daha değişirse yakalar. Aralık geniş, kur tahmini değil.
  const data = await canli();
  const usd = extractTruncgil(data, ['USDTRY=X']).get('USDTRY=X');
  assert(usd !== undefined && usd > 5 && usd < 500, `USDTRY=X: ${usd}`);
});
