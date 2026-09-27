// Proje adresi tek kaynaktan — TAŞINABİLİRLİK KAPISI (0076)
//
// 14 tetikleyici eski projenin adresini sabit yazıyordu. Frankfurt'a taşımada
// migration zinciri yeni projeye olduğu gibi koşulsaydı, yeni projenin
// cron'ları eski projenin fonksiyonlarını çağırmaya devam edecekti — hata
// yalnızca `net._http_response`'ta görünürdü.
//
// Bu testler her fonksiyonun SON tanımına bakar (migration'lar sırayla
// koşar, son `create or replace` kazanır): eski migration'larda sabit adres
// tarih olarak kalabilir, ama hiçbir fonksiyonun güncel hâlinde kalamaz.

import { assertEquals } from 'jsr:@std/assert@1';

const dir = new URL('../migrations/', import.meta.url);
const dosyalar: string[] = [];
for await (const e of Deno.readDir(dir)) {
  if (e.isFile && e.name.endsWith('.sql')) dosyalar.push(e.name);
}
dosyalar.sort();

const yorumsuz = (s: string) =>
  s.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');

/// fonksiyon adı → { dosya, gövde } — son tanım.
const sonTanim = new Map<string, { dosya: string; govde: string }>();
for (const d of dosyalar) {
  const sql = yorumsuz(await Deno.readTextFile(new URL(d, dir)));
  const re = /create\s+or\s+replace\s+function\s+(public\.[a-z_]+)\s*\([\s\S]*?\$\$[\s\S]*?\$\$\s*;/gi;
  for (const m of sql.matchAll(re)) sonTanim.set(m[1], { dosya: d, govde: m[0] });
}

const SABIT_ADRES = /[a-z0-9]{20}\.supabase\.co/;

Deno.test('hiçbir fonksiyonun SON tanımında sabit proje adresi yok', () => {
  const kalanlar = [...sonTanim]
    .filter(([, t]) => SABIT_ADRES.test(t.govde))
    .map(([ad, t]) => `${ad} (${t.dosya})`);
  assertEquals(kalanlar, [], `sabit adres taşıyan fonksiyonlar: ${kalanlar.join(', ')}`);
});

Deno.test('net.http_post çağıran her fonksiyon adresi edge_function_url\'den alıyor', () => {
  for (const [ad, t] of sonTanim) {
    if (!t.govde.includes('net.http_post')) continue;
    assertEquals(
      /url\s*:=\s*public\.edge_function_url\('[a-z0-9-]+'\)/.test(t.govde),
      true,
      `${ad} (${t.dosya}) adresi başka yerden kuruyor`,
    );
  }
});

Deno.test('hiçbir migration cron.schedule gövdesine adres gömmüyor', async () => {
  // Fonksiyon dışı yol: `cron.schedule('x', '* * * * *', $$ select net.http_post('https://…') $$)`.
  for (const d of dosyalar) {
    const sql = yorumsuz(await Deno.readTextFile(new URL(d, dir)));
    for (const m of sql.matchAll(/cron\.schedule\([\s\S]*?\);/g)) {
      assertEquals(SABIT_ADRES.test(m[0]), false, `${d}: cron gövdesinde sabit adres`);
    }
  }
});

const m0076 = await Deno.readTextFile(new URL('0076_edge_function_url_vault.sql', dir));

Deno.test('project_url için tohum EKİLMİYOR', () => {
  // Yer tutucu bir adres canlıda kalırsa istekler sessizce yanlış yere
  // gider. Eksiklik çağrı anında patlamalı (fail-closed), doldurulmamalı.
  for (const d of dosyalar) {
    const sql = yorumsuz(Deno.readTextFileSync(new URL(d, dir)));
    // `'(?!')`: uyarı metnindeki örnek komut (`''https://…'', ''project_url''`)
    // bir string literal'in içinde — çalışan çağrı değil.
    assertEquals(
      /vault\.create_secret\(\s*'(?!')[^)]*,\s*'project_url'\s*\)/.test(sql),
      false,
      `${d} project_url tohumluyor`,
    );
  }
});

Deno.test('yardımcı istemciye kapalı ve search_path sabit', () => {
  assertEquals(
    m0076.includes('revoke all on function public.edge_function_url(text) from public, anon, authenticated'),
    true,
  );
  const blok = yorumsuz(m0076).split('create or replace function public.edge_function_url')[1];
  assertEquals(/set search_path = public/.test(blok.split('$$')[0]), true);
});

Deno.test('fonksiyon adı yol enjeksiyonuna kapalı', () => {
  assertEquals(m0076.includes("fn !~ '^[a-z0-9-]+$'"), true);
});

Deno.test('push_test_trigger da gateway desenine geçti', () => {
  // 0023'ten beri Authorization'a cron secret koyuyordu (0054'ün atlanmış örneği).
  const t = sonTanim.get('public.push_test_trigger');
  assertEquals(t?.dosya, '0076_edge_function_url_vault.sql');
  assertEquals(t!.govde.includes("public.cron_headers('analyze_signals_cron_secret')"), true);
  assertEquals(t!.govde.includes("'Bearer ' || cron_secret"), false);
});
