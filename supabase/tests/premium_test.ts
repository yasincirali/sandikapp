// Premium hakkı — `_shared/premium.ts` saf yardımcılarının testleri (0116).
//
// ## Bu dosyanın kovaladığı şeyler
// 1. **Kimlik.** Yalnız UUID'ler yazılır; anonim RevenueCat kimliği atlanır.
// 2. **Uydurma yok.** Hak yoksa, bitişi yoksa ya da bozuksa satır çıkmaz.
// 3. **İade** hakkı iade anında bitirir; iptal (yenileme kapalı) bitirmez.
//
// Çalıştır:
//   deno test --allow-all supabase/tests/premium_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import { etkilenenKullanicilar, revenueCatHakki, uuidMi } from '../functions/_shared/premium.ts';

const A = '11111111-2222-3333-4444-555555555555';
const B = 'AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE';

Deno.test('etkilenenKullanicilar: sahip, takma ad, aktarma; yalnız UUID, tekil', () => {
  const ids = etkilenenKullanicilar({
    event: {
      type: 'TRANSFER',
      app_user_id: A,
      original_app_user_id: A,
      aliases: ['$RCAnonymousID:abc', A],
      transferred_from: ['$RCAnonymousID:abc'],
      transferred_to: [B],
    },
  });
  assertEquals(ids, [A, B.toLowerCase()]);
  assertEquals(etkilenenKullanicilar({}), []);
  assertEquals(etkilenenKullanicilar(null), []);
  assertEquals(uuidMi('$RCAnonymousID:abc'), false);
});

const yanit = (hak: Record<string, unknown> | null, ab: Record<string, unknown> = {}) => ({
  subscriber: {
    entitlements: hak === null ? {} : { premium: hak },
    subscriptions: { sandik_premium_aylik: ab },
  },
});

Deno.test('revenueCatHakki: etkin abonelik', () => {
  const h = revenueCatHakki(yanit(
    { expires_date: '2026-11-05T10:00:00Z', product_identifier: 'sandik_premium_aylik' },
    { store: 'app_store', is_sandbox: true, unsubscribe_detected_at: null },
  ));
  assertEquals(h, {
    urun: 'sandik_premium_aylik',
    magaza: 'app_store',
    bitis: '2026-11-05T10:00:00.000Z',
    iptal_edildi: false,
    sandbox: true,
  });
});

Deno.test('revenueCatHakki: iptal bitişi değiştirmez, iade öne çeker', () => {
  const iptal = revenueCatHakki(yanit(
    { expires_date: '2026-11-05T10:00:00Z', product_identifier: 'sandik_premium_aylik' },
    { store: 'play_store', unsubscribe_detected_at: '2026-10-10T08:00:00Z' },
  ));
  assertEquals(iptal?.iptal_edildi, true);
  assertEquals(iptal?.bitis, '2026-11-05T10:00:00.000Z');

  const iade = revenueCatHakki(yanit(
    { expires_date: '2026-11-05T10:00:00Z', product_identifier: 'sandik_premium_aylik' },
    { store: 'play_store', refunded_at: '2026-10-12T09:30:00Z' },
  ));
  assertEquals(iade?.iptal_edildi, true);
  assertEquals(iade?.bitis, '2026-10-12T09:30:00.000Z');
});

Deno.test('revenueCatHakki: hak yok / süresiz / bozuk → null (uydurma yok)', () => {
  assertEquals(revenueCatHakki(yanit(null)), null);
  assertEquals(revenueCatHakki(yanit({ expires_date: null, product_identifier: 'x' })), null);
  assertEquals(revenueCatHakki(yanit({ expires_date: 'dün', product_identifier: 'x' })), null);
  assertEquals(revenueCatHakki('bozuk'), null);
});
