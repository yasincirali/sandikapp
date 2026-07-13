// Analyze Signals Edge Function
//
// pg_cron tarafından günde iki kez tetiklenir (TR 11:00 & 15:00).
// Her aktif kullanıcının push token'ına "signal_analyze_request" tipinde bir
// FCM data-message atar. Client bunu yakalar, mevcut teknik analiz servisini
// çalıştırır, sinyal değişiklikleri varsa signal_notifications tablosuna yazar
// ve gerçek AL/SAT/NÖTR push'unu local notification olarak gösterir.
//
// Neden hibrit? Teknik göstergeler (RSI, MACD, Bollinger, EMA, Stochastic vs.)
// Dart'ta implement edildi ve canlı Yahoo/TEFAS fiyat çekimi client'ta zaten
// çalışıyor. Sunucuda tekrarlamak yerine cron sadece "analiz zamanı" tetikleyici
// görevi görür. Bu sayede:
//   1) Teknik analiz kodu tek yerde (client) kalır
//   2) Yahoo API rate-limit riski server'da patlamaz
//   3) İleride "premium canlı sinyaller" için bu function saatlik çalıştırılabilir

import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

type ServiceAccount = {
  client_email: string;
  private_key: string;
  token_uri?: string;
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      'Content-Type': 'application/json',
    },
  });
}

function base64UrlEncode(input: string | Uint8Array) {
  const bytes =
    typeof input === 'string' ? new TextEncoder().encode(input) : input;
  let binary = '';
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '');
}

function pemToArrayBuffer(pem: string) {
  const base64 = pem
    .replace('-----BEGIN PRIVATE KEY-----', '')
    .replace('-----END PRIVATE KEY-----', '')
    .replace(/\s+/g, '');

  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function createAccessToken(serviceAccount: ServiceAccount) {
  const now = Math.floor(Date.now() / 1000);
  const header = base64UrlEncode(JSON.stringify({ alg: 'RS256', typ: 'JWT' }));
  const claimSet = base64UrlEncode(
    JSON.stringify({
      iss: serviceAccount.client_email,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600,
    }),
  );

  const unsignedToken = `${header}.${claimSet}`;
  const privateKey = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(serviceAccount.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(
    serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token',
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
    },
  );

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Google access token alinamadi: ${errorText}`);
  }

  const tokenJson = await response.json();
  return tokenJson.access_token as string;
}

async function sendAnalyzeTrigger({
  accessToken,
  projectId,
  token,
  slot,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  slot: string;
}) {
  // Data-only message → client tarafında sessiz çalışır (bildirim göstermez).
  // Gerçek AL/SAT bildirimini client `analyzePortfolio` çağırdıktan sonra üretir.
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: JSON.stringify({
        message: {
          token,
          data: {
            type: 'signal_analyze_request',
            slot,
            triggered_at: new Date().toISOString(),
          },
          android: {
            priority: 'high',
            // Bildirim göstermiyoruz — sadece background handler çalışsın.
          },
          apns: {
            headers: {
              'apns-priority': '5',
              'apns-push-type': 'background',
            },
            payload: {
              aps: {
                'content-available': 1,
              },
            },
          },
        },
      }),
    },
  );

  const rawText = await response.text();
  if (response.ok) return { ok: true as const, rawText };

  return {
    ok: false as const,
    rawText,
    shouldDeleteToken:
      response.status === 404 ||
      rawText.includes('UNREGISTERED') ||
      rawText.includes('registration-token-not-registered'),
  };
}

Deno.serve(async (request) => {
  if (request.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL');
    const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');
    const cronSecret = Deno.env.get('ANALYZE_SIGNALS_CRON_SECRET');

    if (!supabaseUrl || !supabaseServiceRoleKey) {
      throw new Error('Supabase env degiskenleri eksik.');
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error('FCM env degiskenleri eksik.');
    }

    // Cron authentication: sadece pg_cron veya bilinen bir çağıran çalıştırabilir.
    // pg_cron çağrısında `Authorization: Bearer <ANALYZE_SIGNALS_CRON_SECRET>`
    // gönderilir. Yoksa 401.
    const authHeader = request.headers.get('Authorization');
    if (cronSecret) {
      if (authHeader !== `Bearer ${cronSecret}`) {
        return jsonResponse({ error: 'Yetkisiz cron cagrisi.' }, 401);
      }
    }

    // Slot: hangi zamanlanmış çağrı ("morning" / "afternoon")
    let slot = 'unknown';
    try {
      const body = await request.json();
      if (typeof body?.slot === 'string') slot = body.slot;
    } catch (_) {
      // Body opsiyonel
    }

    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    // Aktif tüm push token'ları çek (user başına birden fazla olabilir —
    // aynı user'da hem Android hem iOS gibi).
    const { data: tokens, error: tokenError } = await adminClient
      .from('user_push_tokens')
      .select('token, user_id');

    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }

    if (!tokens || tokens.length === 0) {
      return jsonResponse({
        ok: true,
        delivered: 0,
        skipped: 0,
        reason: 'Kayitli push token yok.',
      });
    }

    const accessToken = await createAccessToken(
      JSON.parse(fcmServiceAccountJson) as ServiceAccount,
    );

    // Concurrency: FCM'ye 25 paralel çağrı, sonra bir sonraki batch.
    const results: { token: string; ok: boolean; rawText: string }[] = [];
    const batchSize = 25;
    for (let i = 0; i < tokens.length; i += batchSize) {
      const batch = tokens.slice(i, i + batchSize);
      const batchResults = await Promise.all(
        batch.map(async ({ token }) => {
          const r = await sendAnalyzeTrigger({
            accessToken,
            projectId: fcmProjectId,
            token,
            slot,
          });
          if (!r.ok && r.shouldDeleteToken) {
            try {
              await adminClient
                .from('user_push_tokens')
                .delete()
                .eq('token', token);
            } catch (_) {}
          }
          return { token, ok: r.ok, rawText: r.rawText };
        }),
      );
      results.push(...batchResults);
    }

    const delivered = results.filter((r) => r.ok).length;
    const failed = results.length - delivered;

    return jsonResponse({
      ok: true,
      slot,
      delivered,
      failed,
      total: results.length,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
