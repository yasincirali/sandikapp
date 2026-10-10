// `bist-hisse-katalog` ayrıştırıcılarını CANLI kaynakta dener (salt okunur,
// anahtarsız). Bulut kabı finans hostlarına çıkamadığı için GitHub runner'da
// koşar (`BIST hisse evreni` iş akışı). Yazma yok; yalnız özet basar.
import { evrenKur, kapUnvanlari, kisaAd, type TvSatiri } from '../supabase/functions/_shared/bist_katalog.ts';

async function tv(ek: Record<string, unknown>): Promise<TvSatiri[]> {
  const r = await fetch('https://scanner.tradingview.com/turkey/scan', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'User-Agent': 'Mozilla/5.0' },
    body: JSON.stringify({
      filter: [{ left: 'exchange', operation: 'equal', right: 'BIST' }],
      columns: ['name', 'description', 'type', 'subtype'],
      range: [0, 2000],
      ...ek,
    }),
  });
  const j = await r.json() as { data: { d: unknown[] }[] };
  return j.data.map((x) => x.d as TvSatiri);
}

const evren = evrenKur(await tv({}));
const x100 = await tv({ symbols: { symbolset: ['SYML:BIST;XU100'] } });
const kap = kapUnvanlari(await (await fetch('https://www.kap.org.tr/tr/bist-sirketler', {
  headers: { 'User-Agent': 'Mozilla/5.0' },
})).text());
const seed = new Set(
  [...(await Deno.readTextFile('supabase/migrations/0139_bist_hisse_katalogu.sql'))
    .matchAll(/^  \('([A-Z0-9]+)'/gm)].map((m) => m[1]),
);
console.log('evren', evren.size, 'xu100', x100.length, 'kap', kap.size,
  'kapli', [...evren.keys()].filter((k) => kap.has(k)).length, 'seed', seed.size);
console.log('seedde olmayan (yeni):', [...evren.keys()].filter((k) => !seed.has(k)));
console.log('evrende olmayan (pasif olacak):', [...seed].filter((k) => !evren.has(k)));
for (const k of ['THYAO', 'KUTPO', 'AYGAZ', 'TRALT', 'GRSEL', 'ISGSY', 'TSGYO', 'A1CAP']) {
  console.log('ad', k, '|', kisaAd(kap.get(k) ?? evren.get(k), k));
}
