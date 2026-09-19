// Fiyat kaynağı kanaryası.
//
// Neden var: 2026-09-15'te truncgil v4 anahtarlarını değiştirdi, `fetchLivePrices`
// boş map döndü ve `check-price-alerts` her turda `{"reason":"Fiyat alinamadi.",
// "sent":0}` dedi — HTTP 200, hiçbir yerde hata yok. Fiyat alarmı özelliği
// günlerce ölü kaldı ve bunu yalnızca `net._http_response`'a bakan biri
// görebilirdi (TECHNICAL_DEBT "Dış fiyat API'leri sessizce değişiyor").
//
// Bu modül "alarm var ama fiyat yok" durumunu BAĞIRTIR:
//   1. `console.error` — fonksiyon günlüğünde görünür.
//   2. `db_logs`'a `is_error=true`, `op='kanarya'` satırı — Push Teşhisi ekranı ve
//      SQL sorguları için kalıcı iz.
//   3. `push_admins`'teki kullanıcılara push — 12 saatte en çok bir kez, yoksa
//      her yarım saatlik cron turu aynı bildirimi yağdırır.
//
// Bilerek yapılmayan: kullanıcıya bildirim. Kullanıcı için "fiyat alınamadı" ile
// "hedefe ulaşılmadı" aynı görünür; sorun bizim tarafımızda ve bize gelmeli.
import type { SupabaseClient } from 'jsr:@supabase/supabase-js@2';
import { createAccessToken, sendFcmNotification, ServiceAccount } from './fcm.ts';
import { collapseTokens, TokenRow } from './push_tokens.ts';

/** Aynı kaynak için iki admin push'u arasındaki en kısa süre. */
export const KANARYA_SESSIZLIK_SAAT = 12;

/**
 * Saf karar: son kanarya kaydı `sonKayit` iken şimdi bildirim gitmeli mi?
 * Kayıt yoksa gider; 12 saatten eskiyse gider; yoksa susar.
 */
export function kanaryaBildirilmeliMi(
  sonKayit: Date | null,
  simdi: Date,
  sessizlikSaat = KANARYA_SESSIZLIK_SAAT,
): boolean {
  if (!sonKayit) return true;
  const farkMs = simdi.getTime() - sonKayit.getTime();
  return farkMs >= sessizlikSaat * 3600_000;
}

export type KanaryaSonucu = {
  /** db_logs satırı yazıldı mı */
  kaydedildi: boolean;
  /** admin push'u gitti mi (sessizlik penceresi ya da FCM yoksa false) */
  bildirildi: boolean;
  sebep: string;
};

export async function fiyatKaynagiKanaryasi(
  admin: SupabaseClient,
  args: {
    kaynak: string;
    alarmSayisi: number;
    semboller: string[];
    /** null → kuru koşu / FCM yok: yalnızca kayıt */
    fcm: { projectId: string; serviceAccountJson: string; channelId: string } | null;
  },
): Promise<KanaryaSonucu> {
  const { kaynak, alarmSayisi, semboller, fcm } = args;
  console.error(
    `[kanarya] ${kaynak}: ${alarmSayisi} alarm bekliyor ama ${semboller.length} sembolün hiçbiri fiyatlanamadı: ${semboller.join(', ')}`,
  );

  // Son kayıt — sessizlik penceresi için. Kayıt sorgusu düşerse bildirim
  // yine gider: "kanarya susmuş" en kötü sonuç.
  let sonKayit: Date | null = null;
  try {
    const { data } = await admin
      .from('db_logs')
      .select('ts')
      .eq('source', kaynak)
      .eq('op', 'kanarya')
      .order('ts', { ascending: false })
      .limit(1)
      .maybeSingle();
    if (data?.ts) sonKayit = new Date(data.ts as string);
  } catch (e) {
    console.error('[kanarya] son kayıt okunamadı:', e);
  }

  let kaydedildi = false;
  try {
    const { error } = await admin.from('db_logs').insert({
      user_id: null,
      sdk: 'edge',
      source: kaynak,
      table_name: 'price_alerts',
      op: 'kanarya',
      request_json: { semboller },
      response_json: { alarmSayisi, mesaj: 'fiyat kaynağı boş döndü' },
      duration_ms: 0,
      is_error: true,
    });
    kaydedildi = !error;
    if (error) console.error('[kanarya] db_logs yazılamadı:', error.message);
  } catch (e) {
    console.error('[kanarya] db_logs yazılamadı:', e);
  }

  if (!fcm) return { kaydedildi, bildirildi: false, sebep: 'fcm yok / kuru koşu' };
  if (!kanaryaBildirilmeliMi(sonKayit, new Date())) {
    return { kaydedildi, bildirildi: false, sebep: 'sessizlik penceresi' };
  }

  try {
    const { data: adminler } = await admin.from('push_admins').select('user_id');
    const ids = (adminler ?? []).map((r) => r.user_id as string);
    if (ids.length === 0) return { kaydedildi, bildirildi: false, sebep: 'push_admins boş' };

    const { data: tokenRows } = await admin
      .from('user_push_tokens')
      .select('token, user_id, device_id, platform, updated_at')
      .in('user_id', ids);
    const tokens = collapseTokens((tokenRows ?? []) as TokenRow[]);
    if (tokens.length === 0) return { kaydedildi, bildirildi: false, sebep: 'admin token yok' };

    const accessToken = await createAccessToken(
      JSON.parse(fcm.serviceAccountJson) as ServiceAccount,
    );
    let gonderilen = 0;
    for (const t of tokens) {
      const r = await sendFcmNotification({
        accessToken,
        projectId: fcm.projectId,
        token: t.token,
        title: 'sandık kanarya',
        body: `${kaynak}: ${alarmSayisi} alarm bekliyor, fiyat kaynağı boş döndü.`,
        // Çağıranın kanalı: istemcide kayıtlı bir kanal olsun ki Android
        // bildirimi varsayılana düşürmesin.
        channelId: fcm.channelId,
        data: { type: 'kanarya', kaynak },
        priority: 'high',
      });
      if (r.ok) gonderilen++;
    }
    return { kaydedildi, bildirildi: gonderilen > 0, sebep: `${gonderilen}/${tokens.length} admin cihazı` };
  } catch (e) {
    console.error('[kanarya] admin push başarısız:', e);
    return { kaydedildi, bildirildi: false, sebep: 'push hatası' };
  }
}
