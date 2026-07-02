// supabase/functions/delete-account/index.ts
//
// Hesap silme Edge Function (Deno).
// Akış:
// 1. JWT ile kullanıcıyı doğrula (auth-required)
// 2. Service-role client ile auth.admin.deleteUser() çağır
// 3. ON DELETE CASCADE ile bağlı tablolardaki tüm veri silinir
// 4. account_deletion_log'a anonim kayıt (KVKK kanıtı)
//
// Yasal dayanak: KVKK Madde 11(e), GDPR Article 17,
// Play Console 2024+ ve App Store Guideline 5.1.1(v) zorunluluğu.
//
// Deploy:
//   supabase functions deploy delete-account
//
// Test:
//   curl -i -X POST \
//     -H "Authorization: Bearer $USER_JWT" \
//     https://<project>.supabase.co/functions/v1/delete-account

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// Hash salt — production'da Supabase secret olarak set edin.
const HASH_SALT = Deno.env.get("DELETION_HASH_SALT") ?? "sandik-default-salt-CHANGE-ME";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const hash = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hash))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    // 1. JWT doğrulama
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return jsonResponse({ error: "No authorization header" }, 401);
    }

    const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      global: { headers: { Authorization: authHeader } },
    });

    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user || !user.email) {
      return jsonResponse({ error: "Invalid or expired token" }, 401);
    }

    // 2. Body'den password al ve re-auth (B5 fix)
    // Çalıntı cihaz/aktif JWT senaryosunda saldırgan sadece JWT ile
    // hesabı silemez; fresh password doğrulaması zorunlu.
    let body: { password?: string };
    try {
      body = await req.json();
    } catch {
      return jsonResponse({ error: "Invalid JSON body" }, 400);
    }

    const password = (body.password ?? "").trim();
    if (!password) {
      return jsonResponse({ error: "password_required" }, 400);
    }

    // Yeni bir anonymous client ile yalnızca password doğrulamak için login dene.
    // Bu, mevcut session'ı bozmaz (autoRefresh + persist kapalı).
    const verifyClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const { error: pwError } = await verifyClient.auth.signInWithPassword({
      email: user.email,
      password,
    });
    if (pwError) {
      return jsonResponse({ error: "invalid_password" }, 401);
    }

    // 3. Service-role client (admin işlemleri için)
    const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    // 4. Anonim silme logu — KVKK kanıtı (silmeden ÖNCE eklenir)
    const userIdHash = await sha256Hex(`${user.id}|${HASH_SALT}`);
    const emailDomain = user.email?.includes("@")
      ? user.email.split("@")[1]
      : null;

    const { error: logError } = await adminClient
      .from("account_deletion_log")
      .insert({
        user_id_hash: userIdHash,
        email_domain: emailDomain,
        reason: "user_request",
      });

    if (logError) {
      console.error("Failed to write deletion log:", logError);
      // Log yazılamazsa da devam et — yasal kanıt önemli ama
      // kullanıcı hakkı (silme) daha öncelikli.
    }

    // 4. Kullanıcı sil — CASCADE ile assets/snapshots/partnerships/...
    //    otomatik silinir (şemada ON DELETE CASCADE tanımlı).
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(
      user.id,
    );

    if (deleteError) {
      console.error("Failed to delete user:", deleteError);
      return jsonResponse(
        { error: "Failed to delete account", detail: deleteError.message },
        500,
      );
    }

    return jsonResponse({ success: true, deleted_at: new Date().toISOString() });
  } catch (e) {
    console.error("Unhandled error:", e);
    return jsonResponse({ error: "Internal server error" }, 500);
  }
});
