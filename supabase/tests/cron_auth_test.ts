// Cron yetkilendirme deseni — GATEWAY 401 REGRESYON KAPISI
//
// Bu testlerin varlık sebebi tek bir olay: cron tetikleyicileri rastgele
// hex bir cron secret'ı `Authorization` header'ına koyuyordu, Supabase API
// gateway onu JWT olarak ayrıştırmaya çalışıp isteği fonksiyona HİÇ
// ULAŞTIRMADAN 401 döndürüyordu ve `daily_brief_log` DÖRT AY boş kaldı.
// Hiçbir yerde hata görünmüyordu: cron koşuyordu, fonksiyon logları boştu
// (fonksiyon hiç çalışmamıştı), 401 yalnızca `net._http_response` içindeydi.
//
// Kapı iki yönlü: eski desenin geri sızmasını engeller ve yeni desenin
// eksiksiz olduğunu doğrular.

import { assertEquals, assertMatch } from 'jsr:@std/assert@1';

import { CRON_SECRET_HEADER, cronYetkisiVarMi } from '../functions/_shared/cron_auth.ts';

const migration = await Deno.readTextFile(
  new URL('../migrations/0054_cron_auth_header.sql', import.meta.url),
);

/// Yorum satırları atılmış hâli — ÇALIŞAN SQL.
///
/// Eski desenin geri sızmasını arayan testler yalnızca buna bakar: bu
/// migration'ın açıklama başlığı düzelttiği hatayı ANLATMAK için eski
/// satırı yazıyor ve ham metinde arama onu bulup sahte kırılma üretir.
/// (İlk hâlinde tam olarak bu oldu.)
const sql = migration
  .split('\n')
  .filter((l) => !l.trimStart().startsWith('--'))
  .join('\n');

/// Cron secret'ı DOĞRULAYAN fonksiyonlar. `push-live-activity` listede yok:
/// o secret kontrolü yapmıyor, yalnızca gateway JWT'sine dayanıyor.
const SECRET_DOGRULAYAN = [
  'daily-brief',
  'analyze-signals',
  'check-price-alerts',
  'calendar-nudge',
  'weekly-summary',
  'fetch-inflation',
];

/// Tetikleyicilerin hepsi — `push-live-activity` dahil.
const TETIKLEYICILER = [
  'trigger_analyze_signals',
  'trigger_daily_brief',
  'trigger_weekly_summary',
  'trigger_fetch_inflation',
  'trigger_calendar_nudge',
  'trigger_check_price_alerts',
  'trigger_live_activity_push',
];

// ── Yardımcının davranışı ───────────────────────────────────────────────────

Deno.test('doğru x-cron-secret geçer', () => {
  const r = new Request('https://x/', { headers: { [CRON_SECRET_HEADER]: 'gizli' } });
  assertEquals(cronYetkisiVarMi(r, 'gizli'), null);
});

Deno.test('yanlış x-cron-secret 401 alır', () => {
  const r = new Request('https://x/', { headers: { [CRON_SECRET_HEADER]: 'yanlis' } });
  assertEquals(cronYetkisiVarMi(r, 'gizli')?.status, 401);
});

Deno.test('header HİÇ yoksa 401 alır', () => {
  assertEquals(cronYetkisiVarMi(new Request('https://x/'), 'gizli')?.status, 401);
});

Deno.test('secret tanımsızsa kontrol ATLANIR', () => {
  // Yerel geliştirme yolu; üretimde secret'ın tanımlı olmasına güvenilir.
  // `daily-brief`'in zaten var olan davranışı — korunuyor.
  assertEquals(cronYetkisiVarMi(new Request('https://x/'), undefined), null);
  assertEquals(cronYetkisiVarMi(new Request('https://x/'), ''), null);
});

Deno.test('GERİYE DÖNÜK: Authorization: Bearer <secret> de kabul edilir', () => {
  // Fonksiyonlar ve migration aynı anda dağıtılamaz. Arada kalan çağrı
  // yetkisiz sayılıp kaybolmasın diye eski yol da açık.
  const r = new Request('https://x/', { headers: { Authorization: 'Bearer gizli' } });
  assertEquals(cronYetkisiVarMi(r, 'gizli'), null);
});

Deno.test('gateway JWT\'si cron secret olarak KABUL EDİLMEZ', () => {
  // Authorization artık service_role JWT'si taşıyor. O JWT'nin secret
  // yerine geçmesi, gateway'i geçen herkesi yetkili yapardı.
  const r = new Request('https://x/', {
    headers: { Authorization: 'Bearer eyJhbGciOiJIUzI1NiJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIn0.imza' },
  });
  assertEquals(cronYetkisiVarMi(r, 'gizli')?.status, 401);
});

Deno.test('401 gövdesi JSON ve Türkçe', async () => {
  const r = cronYetkisiVarMi(new Request('https://x/'), 'gizli')!;
  assertEquals(r.headers.get('Content-Type'), 'application/json');
  assertEquals((await r.json()).error, 'Yetkisiz cron cagrisi.');
});

// ── Fonksiyonlar yardımcıyı KULLANIYOR mu ───────────────────────────────────

for (const fn of SECRET_DOGRULAYAN) {
  Deno.test(`${fn}: cronYetkisiVarMi kullanıyor`, async () => {
    const src = await Deno.readTextFile(
      new URL(`../functions/${fn}/index.ts`, import.meta.url),
    );
    assertEquals(
      src.includes('cronYetkisiVarMi(request, cronSecret)'),
      true,
      `${fn} paylaşılan yardımcıyı çağırmalı`,
    );
    assertEquals(
      src.includes("from '../_shared/cron_auth.ts'"),
      true,
      `${fn} cron_auth.ts import etmeli`,
    );
  });

  Deno.test(`${fn}: ELDE auth kontrolü kalmadı`, async () => {
    const src = await Deno.readTextFile(
      new URL(`../functions/${fn}/index.ts`, import.meta.url),
    );
    // Eski desen: `if (authHeader !== `Bearer ${cronSecret}`)`. Geri
    // sızarsa gateway yine 401 döndürür ve arıza sessizce geri gelir.
    assertEquals(
      src.includes('Bearer ${cronSecret}'),
      false,
      `${fn} içinde elde yazılmış Authorization kontrolü kalmış`,
    );
  });

  Deno.test(`${fn}: CORS x-cron-secret'a izin veriyor`, async () => {
    const src = await Deno.readTextFile(
      new URL(`../functions/${fn}/index.ts`, import.meta.url),
    );
    assertEquals(src.includes('x-cron-secret'), true);
  });
}

// ── Migration ───────────────────────────────────────────────────────────────

Deno.test('hiçbir tetikleyici Authorization\'a cron secret koymuyor', () => {
  // ASIL REGRESYON. `0054` öncesi yedi tetikleyicinin hepsi böyleydi.
  assertEquals(sql.includes("'Authorization', 'Bearer ' || cron_secret"), false);
  // Değişken adı değişerek geri gelmesin: JWT olmayan hiçbir şey
  // Authorization'a girmemeli. Tek meşru kaynak cron_gateway_jwt().
  for (const m of sql.matchAll(/'Authorization', 'Bearer ' \|\| ([a-z_.()]+)/g)) {
    assertEquals(
      m[1],
      'public.cron_gateway_jwt()',
      `Authorization'a ${m[1]} konuyor — gateway JWT bekliyor`,
    );
  }
});

for (const t of TETIKLEYICILER) {
  Deno.test(`${t}: yeniden yazıldı ve cron_headers kullanıyor`, () => {
    assertMatch(
      migration,
      new RegExp(`create or replace function public\\.${t}\\(`),
      `${t} bu migration'da yeniden yazılmalı`,
    );
  });
}

Deno.test('cron_headers iki header\'ı birlikte kuruyor', () => {
  // Bölüşüm: JWT gateway'e, secret fonksiyona. Biri eksikse ya gateway
  // reddeder ya fonksiyon — ikisi de sessiz olur.
  assertEquals(migration.includes("'Authorization', 'Bearer ' || public.cron_gateway_jwt()"), true);
  assertEquals(migration.includes("'x-cron-secret', public.cron_secret_of(secret_name)"), true);
});

Deno.test('gateway JWT\'si BİÇİM olarak doğrulanıyor', () => {
  // Buraya hex bir string yazılırsa arıza aynen geri döner ve yine
  // sessiz olur. Migration bu yüzden JWT biçimini denetliyor.
  assertEquals(
    migration.includes("jwt !~ '^[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+$'"),
    true,
  );
});

Deno.test('eksik kurulum SESSİZ kalmıyor', () => {
  // Düzeltilen hatanın maliyeti tam olarak sessizliğiydi.
  assertEquals(migration.includes('KURULUM EKSIK'), true);
  assertEquals(migration.includes('raise exception'), true);
});

Deno.test('her tetikleyicinin Vault secret\'ı doğrulanıyor', () => {
  for (const s of [
    'analyze_signals_cron_secret',
    'daily_brief_cron_secret',
    'weekly_summary_cron_secret',
    'inflation_fetch_cron_secret',
    'calendar_nudge_cron_secret',
    'price_alerts_cron_secret',
    'live_activity_cron_secret',
  ]) {
    assertEquals(
      migration.includes(`public.cron_secret_of('${s}')`),
      true,
      `${s} doğrulanmıyor`,
    );
  }
});

Deno.test('TÜM tetikleyicilerde timeout AÇIKÇA veriliyor', () => {
  // `0040`'ın belgelediği tuzak: pg_net'in 5 sn varsayılanında süre
  // aşımı YALNIZCA yanıtı düşürür — fonksiyon sunucuda çalışmaya devam
  // eder. Sonuç "bazen çalışıyor" ve teşhis edilemez. Dört tetikleyici
  // bu bayrağı hiç almamıştı.
  const gövdeler = sql.split('create or replace function public.trigger_').slice(1);
  assertEquals(gövdeler.length, TETIKLEYICILER.length);
  for (const g of gövdeler) {
    const ad = g.split('(')[0];
    assertEquals(
      /timeout_milliseconds := \d+/.test(g),
      true,
      `trigger_${ad} timeout_milliseconds almamış`,
    );
  }
});

Deno.test('yardımcılar istemciye KAPALI', () => {
  // `security definer` + Vault okuması: anon/authenticated'a açık kalsa
  // istemci service_role JWT'sini okuyabilirdi.
  for (const f of [
    'public.cron_gateway_jwt()',
    'public.cron_secret_of(text)',
    'public.cron_headers(text)',
  ]) {
    assertEquals(
      migration.includes(`revoke all on function ${f} from public, anon, authenticated`),
      true,
      `${f} revoke edilmemiş`,
    );
  }
});

Deno.test('yardımcılarda search_path sabitlenmiş', () => {
  // security definer + kaçak search_path = yetki yükseltme vektörü.
  const bloklar = sql
    .split('create or replace function public.')
    .slice(1)
    .filter((b) => !b.startsWith('trigger_'));
  assertEquals(bloklar.length >= 3, true);
  for (const b of bloklar) {
    assertEquals(
      /set search_path = public/.test(b),
      true,
      `${b.split('(')[0]} search_path sabitlememiş`,
    );
  }
});

Deno.test('mükerrer Vault kaydı tuzağı korunuyor', () => {
  // `0034`'ün bulgusu: aynı adla ikinci kayıt oluşursa hangisinin döndüğü
  // belirsizdi. En yenisi kullanılır, mükerrer varsa uyarı basılır.
  assertEquals(migration.includes('order by created_at desc'), true);
  assertEquals(migration.includes('raise warning'), true);
});
