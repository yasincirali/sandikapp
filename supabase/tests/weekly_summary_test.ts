// Haftalık özet — saf yardımcıların testleri.
//
// `Deno.serve` gövdesi ağ ve veritabanı istediği için test edilmiyor;
// yardımcılar bu yüzden export edildi (`daily_brief_test.ts` ile aynı
// yaklaşım).
//
// ## Bu dosyanın kovaladığı iki şey
//
// 1. **Yanlış yüzde gitmemeli.** `snapshots` BRÜT piyasa değeri tutuyor:
//    hafta içinde para ekleyen kullanıcının uçtan uca farkı getiri
//    DEĞİLDİR. Fonksiyon o haftayı sessiz geçiyor; buradaki testler
//    yüzdenin hangi durumlarda HİÇ hesaplanmadığını kilitliyor.
//
// 2. **Aynı gün iki push gitmemeli.** Faz 2'nin kabul kriteri bu:
//    Pazartesi bir kullanıcı `daily-brief` ile `weekly-summary`'yi BİRDEN
//    ALMAMALI. Cron zamanlamaları migration'da yazıyor ve bu dosya onları
//    metin olarak denetliyor — SQL'i koşturmadan doğrulanabilen tek yol.
//
// Çalıştır:
//   deno test --allow-read supabase/tests/weekly_summary_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  buildWeeklyMessage,
  collapseTokens,
  periodChangePct,
  pickEndpoints,
  snapshotTotal,
} from '../functions/weekly-summary/index.ts';

// ── snapshotTotal ───────────────────────────────────────────────────────────

Deno.test('tüm kategoriler toplanır', () => {
  assertEquals(snapshotTotal({ hisse: 100, altin: 50, doviz: 25 }), 175);
});

Deno.test('null / boş veri sıfır döner', () => {
  assertEquals(snapshotTotal(null), 0);
  assertEquals(snapshotTotal({}), 0);
});

Deno.test('string değerler sayıya çevrilir (eski snapshot\'lar)', () => {
  // `SupabaseService.fetchSanpshots` aynı savunmayı yapıyor: eski
  // kayıtlarda değer string olabiliyor.
  assertEquals(snapshotTotal({ hisse: '100', altin: 50 }), 150);
});

Deno.test('bozuk ve negatif değerler atlanır', () => {
  assertEquals(snapshotTotal({ hisse: 100, altin: 'abc', doviz: -5 }), 100);
});

// ── periodChangePct ─────────────────────────────────────────────────────────

Deno.test('dönem yüzdesi iki uçtan', () => {
  // Kayan nokta: `110/100 - 1` tam 0,1 değil 0,10000000000000009 veriyor.
  // Yüzde bildirimde tek ondalıkla yazıldığı için bu fark görünmez;
  // testin tam eşitlik araması gereksiz kırılganlıktı.
  const artis = periodChangePct(100, 110)!;
  const dusus = periodChangePct(100, 90)!;
  assertEquals(artis.toFixed(1), '10.0');
  assertEquals(dusus.toFixed(1), '-10.0');
});

Deno.test('dönem başı sıfırsa null — sonsuza bölünme yok', () => {
  assertEquals(periodChangePct(0, 500), null);
  assertEquals(periodChangePct(-10, 500), null);
});

Deno.test('bozuk sayı null döner — uydurma yüzde üretilmez', () => {
  assertEquals(periodChangePct(Number.NaN, 100), null);
  assertEquals(periodChangePct(100, Number.POSITIVE_INFINITY), null);
});

// ── pickEndpoints ───────────────────────────────────────────────────────────

const SAAT = 60 * 60 * 1000;
const GUN = 24 * SAAT;

/// Pencere: şimdi − 7 gün … şimdi
function pencere(simdi: number) {
  return { fromMs: simdi - 7 * GUN, toMs: simdi };
}

function snap(tsMs: number, total: number) {
  return {
    user_id: 'u1',
    ts: new Date(tsMs).toISOString(),
    data: { hisse: total },
  };
}

Deno.test('uçlar pencerenin kenarlarına yakınsa kabul edilir', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  const out = pickEndpoints(
    [snap(fromMs + 2 * SAAT, 100000), snap(toMs - 2 * SAAT, 108000)],
    fromMs,
    toMs,
  );
  assertEquals(out, { bas: 100000, son: 108000 });
});

Deno.test('KAPSAMA BOŞLUĞU: hafta başı snapshot yoksa atlanır', () => {
  // Kullanıcı Pazartesi uygulamayı açmamış; ilk snapshot Çarşamba.
  // "Haftalık" yüzde aslında iki günlük farkı anlatırdı.
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  const out = pickEndpoints(
    [snap(fromMs + 4 * GUN, 100000), snap(toMs - 1 * SAAT, 108000)],
    fromMs,
    toMs,
  );
  assertEquals(out, { reason: 'coverage' });
});

Deno.test('KAPSAMA BOŞLUĞU: hafta sonu snapshot bayatsa atlanır', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  const out = pickEndpoints(
    [snap(fromMs + 1 * SAAT, 100000), snap(toMs - 5 * GUN, 108000)],
    fromMs,
    toMs,
  );
  assertEquals(out, { reason: 'coverage' });
});

Deno.test('tek snapshot yüzde TAŞIMAZ', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  assertEquals(
    pickEndpoints([snap(fromMs + SAAT, 100000)], fromMs, toMs),
    { reason: 'empty' },
  );
});

Deno.test('hiç snapshot yok → empty', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  assertEquals(pickEndpoints([], fromMs, toMs), { reason: 'empty' });
});

Deno.test('pencere DIŞI snapshot\'lar uç seçimine girmez', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  const out = pickEndpoints(
    [
      snap(fromMs - 30 * GUN, 10), // çok eski — girmemeli
      snap(fromMs + SAAT, 100000),
      snap(toMs - SAAT, 105000),
    ],
    fromMs,
    toMs,
  );
  assertEquals(out, { bas: 100000, son: 105000 });
});

Deno.test('sıfır toplamlı snapshot uç olamaz', () => {
  const simdi = Date.parse('2026-09-14T09:45:00Z');
  const { fromMs, toMs } = pencere(simdi);
  const out = pickEndpoints(
    [snap(fromMs + SAAT, 0), snap(fromMs + 2 * SAAT, 100000), snap(toMs - SAAT, 104000)],
    fromMs,
    toMs,
  );
  assertEquals(out, { bas: 100000, son: 104000 });
});

// ── buildWeeklyMessage ──────────────────────────────────────────────────────

Deno.test('yükseliş: yön oku başlıkta en solda', () => {
  const m = buildWeeklyMessage(2.34, null);
  assertEquals(m.title, '▲ Geçen hafta piyasadan %2,3');
});

Deno.test('düşüş: eksi işareti yazılır', () => {
  const m = buildWeeklyMessage(-3.17, null);
  assertEquals(m.title, '▼ Geçen hafta piyasadan −%3,2');
});

Deno.test('ondalık ayırıcı Türkçe virgüldür', () => {
  const m = buildWeeklyMessage(2.5, null);
  assertEquals(m.title.includes('%2,5'), true, m.title);
  assertEquals(m.title.includes('.'), false, 'nokta kullanılmamalı');
});

Deno.test('KAYIP haftasında uzun pencere BAĞLAMI verilir', () => {
  // RETENTION_STRATEJISI §8: kayıp anında ya sus ya bağlam ver.
  const m = buildWeeklyMessage(-3.0, 31.8);
  assertEquals(
    m.body,
    'Hafta ekside. Daha uzun pencerede hâlâ +%31,8. Ayrıntı için sandık\'ı aç.',
  );
});

Deno.test('KAZANÇ haftasında uzun pencereyle dengelenmez', () => {
  // Kazancı "ama yıl ekside" diye dengelemek kutlamayı azarlamaya
  // çevirirdi.
  const m = buildWeeklyMessage(3.0, -12.0);
  assertEquals(m.body.includes('ekside'), false, m.body);
});

Deno.test('kutlama / uyarı / eylem dili YOK', () => {
  for (const [pct, uzun] of [[5.5, null], [-5.5, 31.8], [-5.5, null]] as const) {
    const m = buildWeeklyMessage(pct, uzun);
    const s = `${m.title} ${m.body}`.toLowerCase();
    for (
      const yasak of [
        'tebrikler', 'harika', 'muhteşem', 'bravo', 'devam et',
        'düştü!', 'dikkat', 'kaybettin', 'acele', 'kaçırma',
        '🎉', '🔥', '📈', '📉', '💰',
        ' al ', ' sat ', 'alın', 'satın', 'öneri', 'tavsiye ederiz',
      ]
    ) {
      assertEquals(s.includes(yasak), false, `yasaklı ifade "${yasak}": ${s}`);
    }
  }
});

Deno.test('TUTAR sızmaz — yalnızca yüzde', () => {
  const m = buildWeeklyMessage(2.3, null);
  const s = `${m.title}${m.body}`;
  assertEquals(s.includes('₺'), false);
  assertEquals(/\d{4,}/.test(s), false, 'dört haneli sayı tutar demektir');
});

Deno.test('SPK ibaresi kazanç mesajında bulunur', () => {
  const m = buildWeeklyMessage(4.0, null);
  assertEquals(m.body.includes('Yatırım tavsiyesi değildir.'), true, m.body);
});

// ── collapseTokens ──────────────────────────────────────────────────────────

Deno.test('aynı cihazın iki tokenı → tek gönderim, tazesi kazanır', () => {
  const out = collapseTokens([
    { token: 'eski', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-01-01T00:00:00Z' },
    { token: 'yeni', user_id: 'u1', device_id: 'dev-a', platform: 'android', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 1);
  assertEquals(out[0].token, 'yeni');
});

Deno.test('farklı kullanıcılar birbirini elemez', () => {
  const out = collapseTokens([
    { token: 'a', user_id: 'u1', device_id: null, platform: 'ios', updated_at: '2026-09-01T00:00:00Z' },
    { token: 'b', user_id: 'u2', device_id: null, platform: 'ios', updated_at: '2026-09-01T00:00:00Z' },
  ]);
  assertEquals(out.length, 2);
});

// ── FAZ 2 KABUL KRİTERİ ─────────────────────────────────────────────────────
//
// "Pazartesi günü bir kullanıcı `daily-brief` ile `weekly-summary`'yi
// BİRDEN ALMAMALI."
//
// Cron zamanlamaları SQL'de; burada migration metni denetleniyor. SQL'i
// koşturmadan doğrulanabilen tek yol bu ve kapı gerçekten kritik:
// ayrışırsa kullanıcı Pazartesi iki push alır ve bunu ancak kullanıcı
// bildirir.

const migration = Deno.readTextFileSync(
  new URL('../migrations/0052_weekly_summary.sql', import.meta.url),
);

Deno.test('haftalık özet PAZARTESİ koşuyor', () => {
  assertEquals(
    migration.includes("cron.schedule('weekly-summary', '45 6 * * 1'"),
    true,
    'weekly-summary Pazartesi (1) TR 09:45 = 06:45 UTC olmalı',
  );
});

Deno.test('sabah brifingi PAZARTESİ SUSTURULUYOR', () => {
  assertEquals(
    migration.includes("cron.schedule('daily-brief', '45 6 * * 2-5'"),
    true,
    'daily-brief 2-5 olmalı — Pazartesi sözü haftalık özete ait',
  );
  // Eski zamanlama geri gelmemeli.
  assertEquals(
    migration.includes("'45 6 * * 1-5'"),
    false,
    '1-5 geri gelmiş: Pazartesi iki push riski',
  );
});

Deno.test('brifing yeniden zamanlanmadan ÖNCE unschedule ediliyor', () => {
  // `cron.schedule` aynı isimle ikinci kez çağrılırsa hata verir; sıra
  // önemli.
  const unschedIdx = migration.indexOf("where jobname = 'daily-brief'");
  const schedIdx = migration.indexOf("cron.schedule('daily-brief'");
  assertEquals(unschedIdx !== -1 && schedIdx !== -1, true);
  assertEquals(
    unschedIdx < schedIdx,
    true,
    'unschedule, schedule\'dan önce gelmeli',
  );
});

Deno.test('migration kendi sonucunu doğruluyor', () => {
  // Sessizce uygulanmamış cron, "çalıştığı sanılan ama çalışmayan" en
  // pahalı hata sınıfı (bkz. 0040_cron_http_timeout.sql).
  assertEquals(
    migration.includes('raise exception \'weekly-summary cron kurulamadi\''),
    true,
  );
  assertEquals(
    migration.includes('ayni gun iki push riski'),
    true,
    'brifing susturulamadıysa migration patlamalı',
  );
});

Deno.test('gönderim defteri ve tercih kolonu var', () => {
  assertEquals(migration.includes('weekly_summary_log'), true);
  assertEquals(migration.includes('weekly_summary_push'), true);
  // Defter istemciye KAPALI olmalı.
  assertEquals(
    migration.includes(
      'revoke all on table public.weekly_summary_log from anon, authenticated',
    ),
    true,
  );
});

Deno.test('pg_net timeout AÇIKÇA veriliyor', () => {
  // Varsayılan 5 sn yetersiz; süre aşımında yanıt sessizce kaybolur ve
  // sistem "bazen çalışıyor" gibi görünür.
  assertEquals(migration.includes('timeout_milliseconds := 60000'), true);
});
