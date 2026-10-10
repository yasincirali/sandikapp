// Edge function paket boyutu kapısı (2026-10-10).
//
// `fon-kalem-raporu` ilk sürümde `npm:pdfjs-dist` tam paketini içe aktardı;
// fonksiyon paketi 32 MB oldu ve Supabase dağıtımı 413 "request entity too
// large" ile reddetti (run 38020347414): Frankfurt'ta migration'lar gitti,
// Tokyo iptal oldu, iki sunucu bir süre ayrıştı. PDF okuma sunucusuz derleme
// `npm:unpdf` ile yapılır (`_shared/pdf_metin.ts`). Bu test bilinen dev
// paketlerin hiçbir fonksiyona geri girmemesini kilitler.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/fonksiyon_paket_boyutu_test.ts

import { assertEquals } from 'jsr:@std/assert@1';

const YASAK = [
  'npm:pdfjs-dist', // ~37 MB; yerine npm:unpdf
];

async function* tsDosyalari(kok: URL): AsyncGenerator<URL> {
  for await (const g of Deno.readDir(kok)) {
    const u = new URL(g.name + (g.isDirectory ? '/' : ''), kok);
    if (g.isDirectory) yield* tsDosyalari(u);
    else if (g.name.endsWith('.ts')) yield u;
  }
}

Deno.test('edge function kaynaklarında dev npm paketi yok', async () => {
  const kok = new URL('../functions/', import.meta.url);
  const ihlaller: string[] = [];
  for await (const dosya of tsDosyalari(kok)) {
    const metin = await Deno.readTextFile(dosya);
    for (const y of YASAK) {
      if (metin.includes(`'${y}`) || metin.includes(`"${y}`)) {
        ihlaller.push(`${dosya.pathname.split('/functions/')[1]}: ${y}`);
      }
    }
  }
  assertEquals(ihlaller, []);
});

Deno.test('PDF metni unpdf ile okunur', async () => {
  const metin = await Deno.readTextFile(
    new URL('../functions/_shared/pdf_metin.ts', import.meta.url),
  );
  assertEquals(metin.includes("from 'npm:unpdf@"), true);
});
