// supabase/functions/redeem-invite-code/index.ts
//
// Davet kodunu doğrula ve mevcut kullanıcıyı hedef (to_user_id) olarak yaz.
//
// Mağduriyet senaryosu önlemleri:
//   - Tüm sorgular service-role ile yapılır (RLS bypass)
//   - Authenticated kullanıcının JWT'si zorunlu
//   - Kullanıcı kendi davetini kullanamaz
//   - Tek kullanımlık + zamanı dolmamış olmalı
//   - Aynı kullanıcılar arasında zaten partnership varsa reddedilir
//   - Yalnızca gereken alanlar dönülür (hedef hassas veri ifşa edilmez)
//
// Deploy:
//   supabase functions deploy redeem-invite-code
//
// Body:
//   { code: "ABCDE-12345" }
// Returns 200:
//   { invite_id, partner_user_id, partner_display_name }

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

const CODE_REGEX = /^[A-Z2-9]{5}-[A-Z2-9]{5}$/

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  try {
    // 1. JWT doğrulama
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) return json({ error: 'No authorization header' }, 401)

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    })
    const { data: { user }, error: authError } = await userClient.auth.getUser()
    if (authError || !user) return json({ error: 'Invalid or expired token' }, 401)

    // 2. Body parse
    let body: { code?: string }
    try {
      body = await req.json()
    } catch {
      return json({ error: 'Invalid JSON body' }, 400)
    }

    const code = (body.code ?? '').trim().toUpperCase()
    if (!CODE_REGEX.test(code)) {
      return json({ error: 'invalid_code_format' }, 400)
    }

    const admin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    // 2b. SUNUCU TARAFLI RATE LIMIT (S1 fix)
    //
    // Önceden bu sınır yalnızca istemcide (SharedPreferences) vardı;
    // uygulama verisini silmek veya bu endpoint'e doğrudan istek atmak
    // limiti tamamen ortadan kaldırıyordu — davet kodları sınırsızca
    // denenebiliyordu.
    //
    // Sayaç yalnızca KONTROL edilir; kayıt aşağıda, sadece gerçek bir
    // tahmin başarısızlığında (kod bulunamadı) yapılır. Aksi halde
    // kullanıcı hataları (kendi kodunu girme, zaten ortak olma) da
    // brute-force denemesi gibi sayılır ve meşru kullanıcı kilitlenir
    // (S8 — sahada gözlendi).
    const { data: rlPeek, error: rlPeekErr } = await admin.rpc(
      'peek_rate_limit',
      {
        p_subject: user.id,
        p_scope: 'redeem_invite',
        p_max_attempts: 5,
        p_window_seconds: 600,
      },
    )

    if (rlPeekErr) {
      // Fail-closed: sayaç çalışmıyorsa brute-force'a açık kalmaktansa
      // isteği reddet. Bu akış nadir kullanılır; kısa kesinti kabul edilebilir.
      console.error('Rate limit check failed:', rlPeekErr)
      return json({ error: 'rate_limit_unavailable' }, 503)
    }

    const rlRow = Array.isArray(rlPeek) ? rlPeek[0] : rlPeek
    if (rlRow && rlRow.allowed === false) {
      return json(
        {
          error: 'rate_limited',
          retry_after_seconds: rlRow.retry_after_seconds ?? 600,
        },
        429,
      )
    }

    /** Yalnızca gerçek tahmin başarısızlığında sayacı artırır. */
    const recordFailedGuess = async () => {
      try {
        await admin.rpc('record_rate_limit_attempt', {
          p_subject: user.id,
          p_scope: 'redeem_invite',
        })
      } catch (e) {
        console.error('record_rate_limit_attempt failed:', e)
      }
    }

    // 3. Daveti bul
    const { data: invite, error: inviteErr } = await admin
      .from('partner_invites')
      .select('id, from_user_id, to_user_id, used, expires_at, status')
      .eq('code', code)
      .eq('used', false)
      .gt('expires_at', new Date().toISOString())
      .maybeSingle()

    if (inviteErr) {
      console.error('Invite fetch error:', inviteErr)
      return json({ error: 'lookup_failed' }, 500)
    }
    // BURASI gerçek tahmin başarısızlığı: girilen kod hiçbir geçerli
    // davete karşılık gelmiyor. Brute-force yalnızca bu yoldan ilerler,
    // dolayısıyla sayaç yalnızca burada artar.
    if (!invite) {
      await recordFailedGuess()
      return json({ error: 'invite_not_found_or_expired' }, 404)
    }

    // Aşağıdakiler kullanıcı hatasıdır, tahmin değil: kod DOĞRU
    // bulundu. Bunları saymak meşru kullanıcıyı kilitler ve saldırgana
    // hiçbir maliyet yüklemez (zaten geçerli bir kodu var).
    if (invite.from_user_id === user.id) {
      return json({ error: 'cannot_use_own_code' }, 400)
    }

    if (invite.to_user_id && invite.to_user_id !== user.id) {
      return json({ error: 'already_claimed' }, 409)
    }

    // 4. Mevcut partnership kontrolü
    //
    // GÜVENLİK: Daha önce burada `.or()` içine şablon dizesiyle
    // user.id / from_user_id gömülüyordu. `.or()` argümanı PostgREST
    // tarafından bir FİLTRE İFADESİ olarak ayrıştırılır — SQL değil ama
    // yine de bir dil. İçine virgül/parantez giren bir değer ifadeyi
    // yeniden yazabilir (PostgREST filtre enjeksiyonu).
    //
    // Bu iki değer bugün doğrulanmış UUID'ler olduğu için sömürülebilir
    // değildi; ancak kalıp kırılgan — kaynağı değişen ilk gün açık hale
    // gelir. Enjeksiyonun mümkün olmadığı parametrik forma geçiyoruz:
    // iki taraf da `.in()` ile verilir, eşleşme kodda kontrol edilir.
    const pair = [user.id, invite.from_user_id]
    const { data: existingPartnerships, error: partnershipErr } = await admin
      .from('partnerships')
      .select('id, user_id_1, user_id_2')
      .in('user_id_1', pair)
      .in('user_id_2', pair)

    if (partnershipErr) {
      console.error('Partnership lookup error:', partnershipErr)
      return json({ error: 'lookup_failed' }, 500)
    }

    // `.in()` çapraz çarpım verir (ör. user_id_1 = user_id_2 = user.id
    // gibi alakasız satırlar); gerçek eşleşmeyi burada süzüyoruz.
    const alreadyPartners = (existingPartnerships ?? []).some(
      (p) =>
        (p.user_id_1 === user.id && p.user_id_2 === invite.from_user_id) ||
        (p.user_id_1 === invite.from_user_id && p.user_id_2 === user.id),
    )

    if (alreadyPartners) {
      return json({ error: 'already_partners' }, 409)
    }

    // 5. Requester'ın profilini çek (push bildirimi için)
    const { data: requester } = await admin
      .from('profiles')
      .select('display_name')
      .eq('id', user.id)
      .maybeSingle()

    const requesterName =
      (requester?.display_name as string | null)?.trim() || 'Kullanıcı'

    // 6. Davet hedefini yaz
    const { error: updateErr } = await admin
      .from('partner_invites')
      .update({
        to_user_id: user.id,
        requester_name: requesterName.slice(0, 60),
        status: 'pending',
      })
      .eq('id', invite.id)

    if (updateErr) {
      console.error('Update error:', updateErr)
      return json({ error: 'update_failed' }, 500)
    }

    // 7. Davet sahibinin display_name'ini dön (UI'da gösterilecek)
    const { data: ownerProfile } = await admin
      .from('profiles')
      .select('display_name')
      .eq('id', invite.from_user_id)
      .maybeSingle()

    // 8. Başarılı redeem — deneme sayacını sıfırla ki meşru kullanıcı
    // birden fazla ortaklık kurarken birikmiş denemeler yüzünden
    // kilitlenmesin.
    try {
      await admin.rpc('clear_rate_limit', {
        p_subject: user.id,
        p_scope: 'redeem_invite',
      })
    } catch (e) {
      // Sayaç temizlenemezse işlem yine başarılı — sadece logla.
      console.error('clear_rate_limit failed:', e)
    }

    return json({
      invite_id: invite.id,
      partner_user_id: invite.from_user_id,
      partner_display_name:
        (ownerProfile?.display_name as string | null) ?? 'Kullanıcı',
    })
  } catch (e) {
    console.error('Unhandled error:', e)
    return json({ error: 'internal_error' }, 500)
  }
})
