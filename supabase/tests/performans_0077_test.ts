// 0077 — performans migration'ının kararlarını kilitler.
//
// En kırılgan karar: anlık görüntü seyreltmesi TEKİL İNDEKSLE değil
// TETİKLEYİCİYLE. Mağazadaki eski sürüm düz INSERT yapıyor; tekil indeks
// saatteki ikinci yazımda 409 döndürür ve istemci her fiyat turunda
// "Fiyatlar güncellenemedi" gösterirdi.

import { assertEquals } from 'jsr:@std/assert@1';

const sql = await Deno.readTextFile(
  new URL('../migrations/0077_performans_rls_indeks_snapshot.sql', import.meta.url),
);
const calisan = sql.split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');

Deno.test('anlık görüntüde TEKİL indeks yok — eski sürüm 409 almasın', () => {
  assertEquals(/create\s+unique\s+index[^;]*snapshots/i.test(calisan), false);
  assertEquals(calisan.includes('before insert on public.snapshots'), true);
});

Deno.test('tetikleyici INVOKER + sabit search_path (kendi satırını RLS ile günceller)', () => {
  const govde = calisan.slice(calisan.indexOf('function public.snapshots_saatlik()'));
  const bas = govde.slice(0, govde.indexOf('as $$'));
  assertEquals(/security\s+definer/i.test(bas), false);
  assertEquals(bas.includes('set search_path = public'), true);
});

Deno.test('saklama süresi istemciden cron\'a taşındı', () => {
  assertEquals(calisan.includes("cron.schedule('snapshots-retention'"), true);
  assertEquals(calisan.includes("interval '730 days'"), true);
});

Deno.test('RLS dönüşümü çift sarmaz ve kendini doğrular', () => {
  assertEquals(calisan.includes("'(?<!SELECT )auth\\.uid\\(\\)'"), true);
  assertEquals(calisan.includes('hâlâ satır başına auth.uid()'), true);
});

Deno.test('silinen indeksler başka indeksle kapsanıyor (yorumda gerekçe)', () => {
  for (const ad of [
    'assets_user_id_idx',
    'partnerships_user1_idx',
    'signal_preferences_user_idx',
    'user_push_tokens_user_idx',
    'ix_user_roi_snapshots_user',
  ]) {
    const satir = calisan.split('\n').find((l) => l.includes(`drop index if exists public.${ad};`));
    assertEquals(satir !== undefined, true, `${ad} silinmiyor`);
  }
  // Gerekçe yorumları: her drop satırında "⊂" ya da "=" ile kapsayan indeks.
  const yorumlu = sql.split('\n').filter((l) => l.includes('drop index if exists')).every((l) => /--\s*[⊂=]/.test(l));
  assertEquals(yorumlu, true);
});
