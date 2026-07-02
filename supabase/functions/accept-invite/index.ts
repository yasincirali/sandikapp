// supabase/functions/accept-invite/index.ts
//
// Davet sahibi (from_user_id) gelen ortaklık isteğini onaylar veya reddeder.
// Partnership oluşturma yalnızca burada (service-role) yapılır — RLS
// üzerinden doğrudan INSERT yasak (A3 fix).
//
// Body:
//   { invite_id: "uuid", action: "accept" | "reject" }
// Returns 200:
//   { partnership_id?: "uuid", status: "accepted" | "rejected" }

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.45.4'

const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')!
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'No authorization header' }, 401)

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return json({ error: 'Invalid or expired token' }, 401)

    let body: { invite_id?: string; action?: string }
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid JSON body' }, 400)
    }

    const inviteId = (body.invite_id ?? '').trim()
    const action = body.action
    if (!inviteId) return json({ error: 'invite_id required' }, 400)
    if (action !== 'accept' && action !== 'reject') {
      return json({ error: 'action must be accept or reject' }, 400)
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // Daveti çek
    const { data: invite, error: inviteErr } = await admin
      .from('partner_invites')
      .select('id, from_user_id, to_user_id, used, expires_at, status')
      .eq('id', inviteId)
      .maybeSingle()

    if (inviteErr) {
      console.error('Invite fetch error:', inviteErr)
      return json({ error: 'lookup_failed' }, 500)
    }
    if (!invite) return json({ error: 'invite_not_found' }, 404)

    // Yalnızca davet sahibi onaylayabilir/reddedebilir
    if (invite.from_user_id !== user.id) {
      return json({ error: 'forbidden' }, 403)
    }

    if (invite.used) {
      return json({ error: 'already_processed' }, 409)
    }

    if (new Date(invite.expires_at) <= new Date()) {
      return json({ error: 'expired' }, 410)
    }

    if (!invite.to_user_id) {
      return json({ error: 'no_target' }, 400)
    }

    if (action === 'reject') {
      await admin
        .from('partner_invites')
        .update({ status: 'rejected', used: true })
        .eq('id', inviteId)
      return json({ status: 'rejected' })
    }

    // action === 'accept'
    // Çift partnership kontrolü
    const { data: existing } = await admin
      .from('partnerships')
      .select('id')
      .or(
        `and(user_id_1.eq.${invite.from_user_id},user_id_2.eq.${invite.to_user_id}),` +
        `and(user_id_1.eq.${invite.to_user_id},user_id_2.eq.${invite.from_user_id})`,
      )
      .maybeSingle()

    if (existing) {
      // Yine de daveti accepted olarak işaretle (UI tutarlılığı)
      await admin
        .from('partner_invites')
        .update({ status: 'accepted', used: true })
        .eq('id', inviteId)
      return json({ partnership_id: existing.id, status: 'accepted' })
    }

    const partnershipId = crypto.randomUUID()
    const { error: insertErr } = await admin.from('partnerships').insert({
      id: partnershipId,
      user_id_1: invite.from_user_id,
      user_id_2: invite.to_user_id,
    })
    if (insertErr) {
      console.error('Partnership insert error:', insertErr)
      return json({ error: 'partnership_insert_failed' }, 500)
    }

    await admin
      .from('partner_invites')
      .update({ status: 'accepted', used: true })
      .eq('id', inviteId)

    return json({ partnership_id: partnershipId, status: 'accepted' })
  } catch (e) {
    console.error('Unhandled error:', e)
    return json({ error: 'internal_error' }, 500)
  }
})
