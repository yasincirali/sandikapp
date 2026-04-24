import { createClient } from 'jsr:@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
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
    {
      name: 'RSASSA-PKCS1-v1_5',
      hash: 'SHA-256',
    },
    false,
    ['sign'],
  );

  const signature = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    privateKey,
    new TextEncoder().encode(unsignedToken),
  );

  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const response = await fetch(serviceAccount.token_uri ?? 'https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/x-www-form-urlencoded',
    },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: jwt,
    }),
  });

  if (!response.ok) {
    const errorText = await response.text();
    throw new Error(`Google access token alinamadi: ${errorText}`);
  }

  const tokenJson = await response.json();
  return tokenJson.access_token as string;
}

async function sendFcmMessage({
  accessToken,
  projectId,
  token,
  inviteId,
  requesterName,
}: {
  accessToken: string;
  projectId: string;
  token: string;
  inviteId: string;
  requesterName: string;
}) {
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
          notification: {
            title: 'Yeni ortaklik istegi',
            body: `${requesterName} ortaklik kodunuzu girdi.`,
          },
          data: {
            type: 'partner_invite',
            invite_id: inviteId,
            requester_name: requesterName,
          },
          android: {
            priority: 'high',
            notification: {
              channel_id: 'partner_invite_channel',
              click_action: 'FLUTTER_NOTIFICATION_CLICK',
            },
          },
          apns: {
            headers: {
              'apns-priority': '10',
            },
            payload: {
              aps: {
                sound: 'default',
              },
            },
          },
        },
      }),
    },
  );

  const rawText = await response.text();
  if (response.ok) {
    return { ok: true as const, rawText };
  }

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
    const supabaseAnonKey = Deno.env.get('SUPABASE_ANON_KEY');
    const supabaseServiceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const fcmProjectId = Deno.env.get('FCM_PROJECT_ID');
    const fcmServiceAccountJson = Deno.env.get('FCM_SERVICE_ACCOUNT_JSON');

    if (!supabaseUrl || !supabaseAnonKey || !supabaseServiceRoleKey) {
      throw new Error('Supabase env degiskenleri eksik.');
    }
    if (!fcmProjectId || !fcmServiceAccountJson) {
      throw new Error('FCM env degiskenleri eksik.');
    }

    const authHeader = request.headers.get('Authorization');
    if (!authHeader?.startsWith('Bearer ')) {
      return jsonResponse({ error: 'Authorization header eksik.' }, 401);
    }

    const jwt = authHeader.replace('Bearer ', '');
    const authClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: {
        headers: { Authorization: authHeader },
      },
    });
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

    const {
      data: { user },
      error: authError,
    } = await authClient.auth.getUser(jwt);

    if (authError || !user) {
      return jsonResponse({ error: 'Kullanici dogrulanamadi.' }, 401);
    }

    const body = await request.json();
    const inviteId = String(body?.inviteId ?? '').trim();
    if (!inviteId) {
      return jsonResponse({ error: 'inviteId gerekli.' }, 400);
    }

    const { data: invite, error: inviteError } = await adminClient
      .from('partner_invites')
      .select('id, from_user_id, to_user_id, requester_name, status, used')
      .eq('id', inviteId)
      .maybeSingle();

    if (inviteError || !invite) {
      return jsonResponse({ error: 'Davet bulunamadi.' }, 404);
    }

    if (invite.to_user_id !== user.id) {
      return jsonResponse({ error: 'Bu davet icin push gonderme yetkiniz yok.' }, 403);
    }

    if (invite.status !== 'pending' || invite.used === true) {
      return jsonResponse({ error: 'Davet artik push gonderilebilir durumda degil.' }, 409);
    }

    const { data: tokens, error: tokenError } = await adminClient
      .from('user_push_tokens')
      .select('token')
      .eq('user_id', invite.from_user_id);

    if (tokenError) {
      throw new Error(`Push tokenlari alinamadi: ${tokenError.message}`);
    }

    if (!tokens || tokens.length === 0) {
      return jsonResponse({
        ok: true,
        delivered: false,
        reason: 'Kod sahibinin kayitli push tokeni yok.',
      });
    }

    const accessToken = await createAccessToken(
      JSON.parse(fcmServiceAccountJson) as ServiceAccount,
    );
    const requesterName =
      String(invite.requester_name ?? '').trim() || 'Bir kullanici';

    const deliveryResults = await Promise.all(
      tokens.map(async ({ token }) => {
        const result = await sendFcmMessage({
          accessToken,
          projectId: fcmProjectId,
          token,
          inviteId,
          requesterName,
        });

        if (!result.ok && result.shouldDeleteToken) {
          await adminClient.from('user_push_tokens').delete().eq('token', token);
        }

        return {
          token,
          ok: result.ok,
          rawText: result.rawText,
        };
      }),
    );

    return jsonResponse({
      ok: true,
      delivered: deliveryResults.some((item) => item.ok),
      results: deliveryResults,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
