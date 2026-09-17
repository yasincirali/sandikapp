// Genel bildirim kaydı — saf yardımcıların testleri (0066).
//
//   deno test supabase/tests/app_notifications_test.ts

import { assertEquals } from 'jsr:@std/assert@1';
import {
  type AppNotificationRow,
  appNotificationRow,
  recordAppNotification,
} from '../functions/_shared/app_notifications.ts';

Deno.test('appNotificationRow: alanlar kırpılır, data varsayılanı boş', () => {
  const r = appNotificationRow({
    userId: 'u1',
    type: 'daily_brief',
    title: '  THYAO %5 yükseldi ',
    body: ' 2 varlık daha hareketli ',
  });
  assertEquals(r, {
    user_id: 'u1',
    type: 'daily_brief',
    title: 'THYAO %5 yükseldi',
    body: '2 varlık daha hareketli',
    data: {},
  });
});

Deno.test('appNotificationRow: boş başlık ya da kullanıcı → null', () => {
  assertEquals(
    appNotificationRow({ userId: 'u1', type: 'calendar_nudge', title: ' ', body: 'x' }),
    null,
  );
  assertEquals(
    appNotificationRow({ userId: '', type: 'calendar_nudge', title: 'a', body: 'x' }),
    null,
  );
});

function sahteYazici(yazilan: AppNotificationRow[], hata?: string) {
  return {
    from: (_t: string) => ({
      insert: (row: AppNotificationRow) => {
        yazilan.push(row);
        return Promise.resolve({ error: hata ? { message: hata } : null });
      },
    }),
  };
}

Deno.test('recordAppNotification: kullanıcı başına TEK kayıt (çok cihaz)', async () => {
  const yazilan: AppNotificationRow[] = [];
  const kaydedilen = new Set<string>();
  const row = appNotificationRow({
    userId: 'u1', type: 'weekly_summary', title: 'Hafta', body: '+%2',
  });
  assertEquals(await recordAppNotification(sahteYazici(yazilan), row, kaydedilen), null);
  assertEquals(await recordAppNotification(sahteYazici(yazilan), row, kaydedilen), null);
  assertEquals(yazilan.length, 1, 'ikinci cihaz ikinci satır yazmamalı');
});

Deno.test('recordAppNotification: DB hatası gönderimi düşürmez, mesaj döner', async () => {
  const yazilan: AppNotificationRow[] = [];
  const row = appNotificationRow({
    userId: 'u2', type: 'partner_invite', title: 'Davet', body: 'x',
  });
  const sonuc = await recordAppNotification(sahteYazici(yazilan, 'permission denied'), row);
  assertEquals(sonuc, 'bildirim kaydı: permission denied');
});

Deno.test('recordAppNotification: null satır sessizce atlanır', async () => {
  const yazilan: AppNotificationRow[] = [];
  assertEquals(await recordAppNotification(sahteYazici(yazilan), null), null);
  assertEquals(yazilan.length, 0);
});
