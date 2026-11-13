// İki sunucu birebir (kullanıcı kuralı, 2026-09-28 → 2026-11-06 Tokyo emekli) — kararları kilitler.

import { assertEquals } from 'jsr:@std/assert@1';

const oku = (yol: string) => Deno.readTextFile(new URL(yol, import.meta.url));
const kod = (s: string) =>
  s.split('\n').filter((l) => !l.trimStart().startsWith('--') && !l.trimStart().startsWith('#')).join('\n');

const m0078 = kod(await oku('../migrations/0078_sunucu_esitleme.sql'));
const m0077 = kod(await oku('../migrations/0077_performans_rls_indeks_snapshot.sql'));
const deploy = await oku('../../.github/workflows/supabase-deploy.yml');

Deno.test('ortak profili politikası kimliği AÇIKÇA niteler (p.id tuzağı)', () => {
  const govde = m0078.slice(m0078.indexOf('create policy "profiles_select_partner"'));
  const politika = govde.slice(0, govde.indexOf(';'));
  assertEquals(politika.includes('p.user_id_2 = profiles.id'), true);
  assertEquals(politika.includes('p.user_id_1 = profiles.id'), true);
  assertEquals(/=\s*id\b/.test(politika), false);
});

Deno.test('user_push_tokens hedefi Tokyo biçimi: PK token', () => {
  assertEquals(m0078.includes('primary key (token)'), true);
});

Deno.test('0077 iki projede de bulunan user_id indeksini silmez', () => {
  assertEquals(m0077.includes('drop index if exists public.user_push_tokens_user_idx;'), false);
});

// 2026-11-06 (yasin: "Tokyo'yu kapatalım"): iki sunucu birebir kuralı bitti.
// Tokyo 18 Ekim'den beri donmuş ve duraklatılacak; duraklatılmış projeye
// giden deploy/eşitlik adımı her koşuyu kırmızıya çevirirdi.
Deno.test('deploy varsayılanı tek sunucu Frankfurt; ikisi ve eşitlik kapısı yok', () => {
  assertEquals(/hedef:[\s\S]*?default: frankfurt/.test(deploy), true);
  assertEquals(deploy.includes('options: [frankfurt]'), true);
  // 2026-11-13: Tokyo silindi — deploy onun ref'ini ve şifre secret'ını taşımaz.
  assertEquals(kod(deploy).includes('ybdbzouzhzwthjgwlbmk'), false);
  assertEquals(kod(deploy).includes('SUPABASE_DB_PASSWORD'), false);
  const govde = kod(deploy); // yorumdaki tarihçe sayılmaz
  assertEquals(govde.includes(`'["frankfurt","tokyo"]'`), false);
  assertEquals(govde.includes('tool/sema_esitlik.py'), false);
  assertEquals(govde.includes('frankfurt_esitle'), false);
});

Deno.test('project_url kapısı push öncesi (0076 sessiz cron ölümü)', () => {
  const kapi = deploy.indexOf("Vault project_url var mı");
  const push = deploy.indexOf('supabase db push --dry-run');
  assertEquals(kapi > 0 && kapi < push, true);
});
