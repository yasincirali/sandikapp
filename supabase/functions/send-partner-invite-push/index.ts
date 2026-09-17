import { createClient } from 'jsr:@supabase/supabase-js@2';

// JWT imzalama ve FCM gönderimi `_shared/fcm.ts`'ten (2026-09-14): bu
// fonksiyon üçüncü kopyayı taşıyordu; silme kuralı ve Android ikon/renk
// artık diğer bildirim tipleriyle aynı.
import {
  createAccessToken,
  sendFcmNotification,
  ServiceAccount,
} from '../_shared/fcm.ts';
import {
  appNotificationRow,
  recordAppNotification,
} from '../_shared/app_notifications.ts';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    // Çan sayfası kaydı — token yoksa ya da push düşse de davet listede
    // görünsün. Kayıt hatası gönderimi düşürmez; yanıta da yazılmaz (ham DB
    // mesajı istemciye dönmez).
    await recordAppNotification(
      adminClient,
      appNotificationRow({
        userId: invite.from_user_id,
        type: 'partner_invite',
        title: 'Yeni ortaklik istegi',
        body: `${String(invite.requester_name ?? '').trim() || 'Bir kullanici'} ortaklik kodunuzu girdi.`,
        data: { invite_id: inviteId },
      }),
    );

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
        const result = await sendFcmNotification({
          accessToken,
          projectId: fcmProjectId,
          token,
          title: 'Yeni ortaklik istegi',
          body: `${requesterName} ortaklik kodunuzu girdi.`,
          channelId: 'partner_invite_channel',
          data: {
            type: 'partner_invite',
            invite_id: inviteId,
            requester_name: requesterName,
          },
          // Davet anlık bir istek: kullanıcı karşı tarafı bekletmemeli.
          priority: 'high',
        });

        if (!result.ok && result.shouldDeleteToken) {
          await adminClient.from('user_push_tokens').delete().eq('token', token);
        }

        // Ham FCM yanıtı yalnızca sunucu log'una. Cevaba token ya da
        // rawText KOYMA: çağıran davetin HEDEFİ, token'lar davet SAHİBİNİN
        // cihazlarına ait — herkese açık paylaşılmış bir kodla başkasının
        // kalıcı cihaz kimlikleri sızıyordu.
        if (!result.ok) {
          console.error('FCM gonderimi basarisiz:', result.rawText);
        }
        return result.ok;
      }),
    );

    return jsonResponse({
      ok: true,
      delivered: deliveryResults.some(Boolean),
    });
  } catch (error) {
    console.error('send-partner-invite-push:', error);
    return jsonResponse({ error: 'internal_error' }, 500);
  }
});
