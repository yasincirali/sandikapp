// Yıl sonu özeti anı (calendar-nudge + 0087) — saf parçalar ve migration.
//
// Pencere istemciyle BİREBİR olmalı (`RecapService.isYearlyWindow`): sunucu
// pencere dışında "özetin hazır" derse kullanıcı dokunur ve afişi bulamaz.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/yil_sonu_ani_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  YIL_SONU,
  yilSonuDonemi,
  yilSonuHedefleri,
  yilSonuMesaji,
  yilSonuPenceresindeMi,
  yilSonuYili,
} from '../functions/calendar-nudge/index.ts';

/// TR saatiyle an → Date (TR = UTC+3).
const tr = (s: string) => new Date(`${s}+03:00`);

Deno.test('pencere: 26 Aralık – 10 Ocak (TR takvimi), uçlar dahil', () => {
  assertEquals(yilSonuPenceresindeMi(tr('2026-12-26T00:00:00')), true);
  assertEquals(yilSonuPenceresindeMi(tr('2026-12-26T20:00:00')), true);
  assertEquals(yilSonuPenceresindeMi(tr('2026-12-31T23:59:00')), true);
  assertEquals(yilSonuPenceresindeMi(tr('2027-01-01T00:30:00')), true);
  assertEquals(yilSonuPenceresindeMi(tr('2027-01-10T23:59:00')), true);
  assertEquals(yilSonuPenceresindeMi(tr('2026-12-25T23:59:00')), false);
  assertEquals(yilSonuPenceresindeMi(tr('2027-01-11T00:00:00')), false);
  assertEquals(yilSonuPenceresindeMi(tr('2026-09-29T12:00:00')), false);
});

Deno.test('pencere TR saatine göre: 25 Aralık 21:30 UTC = 26 Aralık 00:30 TR', () => {
  assertEquals(yilSonuPenceresindeMi(new Date('2026-12-25T21:30:00Z')), true);
  assertEquals(yilSonuPenceresindeMi(new Date('2026-12-25T20:30:00Z')), false);
});

Deno.test('cron anı (17:00 UTC, 26 Aralık) pencere içinde', () => {
  assertEquals(yilSonuPenceresindeMi(new Date('2026-12-26T17:00:00Z')), true);
});

Deno.test('yıl: Aralık o yıl, Ocak önceki yıl (RecapService.yearFor)', () => {
  assertEquals(yilSonuYili(tr('2026-12-26T20:00:00')), 2026);
  assertEquals(yilSonuYili(tr('2027-01-05T10:00:00')), 2026);
  assertEquals(yilSonuDonemi(2026), '2026-12-01');
});

Deno.test('mesaj kişiye özel RAKAM taşımaz, yılı söyler', () => {
  const m = yilSonuMesaji(2026);
  assertEquals(m.title, '2026 sandık Özetin hazır');
  // Yıl dışında rakam yok: sunucuda kişinin getirisi yok, uydurulmaz.
  assertEquals(/\d/.test(m.body), false);
  assertEquals(/%|₺/.test(m.title + m.body), false);
});

Deno.test('hedef: yalnız kaydı olan kullanıcıların token\'ları', () => {
  const t = [
    { token: 'a', user_id: 'u1' },
    { token: 'b', user_id: 'u2' },
    { token: 'c', user_id: 'u1' },
  ];
  assertEquals(yilSonuHedefleri(t, new Set(['u1'])).map((x) => x.token), ['a', 'c']);
  assertEquals(yilSonuHedefleri(t, new Set()), []);
});

// ── Fonksiyon kaynağı ──────────────────────────────────────────────────────

const kaynak = await Deno.readTextFile(
  new URL('../functions/calendar-nudge/index.ts', import.meta.url),
);

Deno.test('yıl sonu yolu defteri okuyup yazar ve sessiz saatlere uyar', () => {
  const govde = kaynak.slice(kaynak.indexOf('async function yilSonuAni('));
  assertEquals(govde.includes(".eq('occasion', YIL_SONU)"), true);
  assertEquals(govde.includes('upsert({ occasion: YIL_SONU, period: donem }'), true);
  assertEquals(govde.includes('sessizKullanicilar('), true);
  assertEquals(govde.includes("data: { type: 'calendar_nudge', occasion: YIL_SONU }"), true);
});

Deno.test('an seçimi cron kapısından SONRA', () => {
  const kapi = kaynak.indexOf('cronYetkisiVarMi(request, cronSecret)');
  const secim = kaynak.indexOf('if (occasion === YIL_SONU)');
  assertEquals(kapi > 0 && secim > kapi, true);
  assertEquals(YIL_SONU, 'year_end_recap');
});

// ── Migration 0087 ──────────────────────────────────────────────────────────

const sql = (await Deno.readTextFile(
  new URL('../migrations/0087_yil_sonu_ozeti_ani.sql', import.meta.url),
)).split('\n').filter((l) => !l.trimStart().startsWith('--')).join('\n');

Deno.test('0087: 26 Aralık 17:00 UTC (20:00 TR), yeni tetikleyici', () => {
  assertEquals(sql.includes("cron.schedule('calendar-nudge-year-end', '0 17 26 12 *'"), true);
  assertEquals(sql.includes("url := public.edge_function_url('calendar-nudge')"), true);
  assertEquals(sql.includes("headers := public.cron_headers('calendar_nudge_cron_secret')"), true);
  assertEquals(sql.includes("jsonb_build_object('occasion', 'year_end_recap')"), true);
  assertEquals(sql.includes('timeout_milliseconds :='), true);
});

Deno.test('0087: var olan trigger_calendar_nudge()\'a dokunmaz', () => {
  assertEquals(/function public\.trigger_calendar_nudge\(\)/.test(sql), false);
  assertEquals(sql.includes("'Authorization'"), false);
});

Deno.test('0087: istemciye kapalı, search_path sabit, Frankfurt kipi', () => {
  assertEquals(
    sql.includes('revoke all on function public.trigger_calendar_nudge_yil_sonu() from public, anon, authenticated;'),
    true,
  );
  assertEquals(/security definer\s+set search_path = public, vault, net/.test(sql), true);
  assertEquals(sql.includes('cron.alter_job(job_id := jobid, active := false)'), true);
  assertEquals(sql.includes('raise exception'), true);
});
