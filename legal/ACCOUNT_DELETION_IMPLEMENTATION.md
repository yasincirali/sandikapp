# Hesap Silme Akışı — Implementation Spec

Bu dokümanda hesap silme özelliğinin teknik tasarımı ve uygulama adımları yer alır. Bu özellik **Google Play 2024+ ve App Store Guideline 5.1.1(v) zorunluluğudur**.

---

## 1. Mimari

```
┌─────────────────┐
│ Flutter UI      │  Profile → Settings → "Hesabımı Sil"
│ (sandık app)    │
└────────┬────────┘
         │ 1. Onay dialog (2 kademeli)
         │ 2. Şifre tekrar doğrulama
         │
         ▼
┌─────────────────────────────────────────┐
│ Supabase Edge Function: delete-account  │
│ (Deno runtime)                          │
└────────┬────────────────────────────────┘
         │ 3. JWT doğrula
         │ 4. Service role ile auth.admin.deleteUser()
         │ 5. ON DELETE CASCADE → tüm tablolardaki user data silinir
         │ 6. Log: account_deletion_log (anonim)
         │
         ▼
┌─────────────────┐
│ Client          │
│ - Local cache   │  7. SharedPreferences temizle
│   temizle       │  8. SQLite cache sil
│ - Logout        │  9. LoginScreen'e yönlendir
└─────────────────┘
```

---

## 2. Frontend — Flutter Implementation

### 2.1 Dosya: `lib/screens/settings_screen.dart` (yeni)

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:portfoy_takip/services/auth_service.dart';
import 'package:portfoy_takip/theme/sandik.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _deleting = false;

  Future<void> _confirmDeleteAccount() async {
    // 1. kademe — uyarı
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hesabını silmek üzeresin'),
        content: const Text(
          'Bu işlem GERİ ALINAMAZ.\n\n'
          'Tüm portföy kayıtların, performans geçmişin ve ortaklık '
          'bağlantıların 30 gün içinde kalıcı olarak silinecek.\n\n'
          'Devam etmek istiyor musun?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Sandik.loss),
            child: const Text('Devam Et'),
          ),
        ],
      ),
    );

    if (firstConfirm != true || !mounted) return;

    // 2. kademe — şifre doğrulama
    final passwordCtrl = TextEditingController();
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Şifrenle onayla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Hesap silme işlemi için şifreni gir.'),
            const SizedBox(height: 12),
            TextField(
              controller: passwordCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Şifre',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Sandik.loss),
            child: const Text('HESABI SİL'),
          ),
        ],
      ),
    );

    if (secondConfirm != true || !mounted || passwordCtrl.text.isEmpty) return;

    setState(() => _deleting = true);
    try {
      await AuthService.instance.deleteAccount(password: passwordCtrl.text);
      if (!mounted) return;
      // AuthService.deleteAccount içinde signOut + local cache cleanup yapılır
      Navigator.of(context).popUntil((r) => r.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hesabın silindi. Üzgünüz, görüşürüz.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _deleting = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hesap silinemedi: ${_friendly(e)}')),
      );
    }
  }

  String _friendly(Object e) {
    final s = e.toString();
    if (s.contains('Invalid') || s.contains('credentials')) {
      return 'Şifre hatalı';
    }
    return 'Bağlantı hatası, tekrar deneyin';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Ayarlar')),
      body: ListView(
        children: [
          // ... diğer ayarlar (tema, bildirim, vb.)
          const Divider(),
          ListTile(
            leading: const Icon(Icons.delete_forever, color: Sandik.loss),
            title: const Text(
              'Hesabımı Sil',
              style: TextStyle(color: Sandik.loss),
            ),
            subtitle: const Text('Tüm verilerin kalıcı olarak silinir'),
            trailing: _deleting
                ? const SizedBox(
                    width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.chevron_right),
            onTap: _deleting ? null : _confirmDeleteAccount,
          ),
        ],
      ),
    );
  }
}
```

### 2.2 Dosya: `lib/services/auth_service.dart` — Yeni metot

```dart
/// Kullanıcının hesabını ve tüm verilerini siler.
/// Şifre re-authentication gerekir (hassas işlem).
Future<void> deleteAccount({required String password}) async {
  final user = _client.auth.currentUser;
  if (user == null) throw Exception('Oturum yok');

  // 1. Şifre doğrulama (re-auth)
  await _client.auth.signInWithPassword(
    email: user.email!,
    password: password,
  );

  // 2. Edge Function çağır
  final response = await _client.functions.invoke('delete-account');
  if (response.status != 200) {
    throw Exception('Edge function failed: ${response.data}');
  }

  // 3. Local cleanup
  final prefs = await SharedPreferences.getInstance();
  await prefs.clear();

  // 4. Sign out (zaten user silindi ama session token cleanup için)
  await _client.auth.signOut();
}
```

---

## 3. Backend — Supabase Edge Function

### 3.1 Dosya: `supabase/functions/delete-account/index.ts` (yeni)

```typescript
import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

serve(async (req) => {
  // CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
        "Access-Control-Allow-Methods": "POST, OPTIONS",
      },
    });
  }

  try {
    // 1. JWT doğrulama
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "No auth header" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    const userClient = createClient(SUPABASE_URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await userClient.auth.getUser();
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Invalid token" }), {
        status: 401,
        headers: { "Content-Type": "application/json" },
      });
    }

    // 2. Service-role client (admin yetki)
    const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // 3. Anonim silme logu (yasal kanıt — 3 yıl saklanır)
    await adminClient.from("account_deletion_log").insert({
      deleted_at: new Date().toISOString(),
      user_id_hash: await hashUserId(user.id), // SHA-256, geri çevrilemez
      email_domain: user.email?.split("@")[1] ?? null, // sadece domain
      reason: "user_request",
    });

    // 4. Kullanıcı verilerini sil (CASCADE ile bağlantılı tablolar otomatik silinir)
    // Şema'da ON DELETE CASCADE var: assets, snapshots, partner_invites,
    // partnerships, user_push_tokens, disclaimer_acceptances, db_logs
    const { error: deleteError } = await adminClient.auth.admin.deleteUser(user.id);

    if (deleteError) {
      console.error("Delete user error:", deleteError);
      return new Response(JSON.stringify({ error: deleteError.message }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ success: true }), {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
      },
    });
  } catch (e) {
    console.error("Unhandled error:", e);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});

async function hashUserId(id: string): Promise<string> {
  const encoder = new TextEncoder();
  const data = encoder.encode(id + "sandik-salt-2026");
  const hashBuffer = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
```

### 3.2 Deploy
```bash
supabase functions deploy delete-account --no-verify-jwt=false
```

> `--no-verify-jwt=false` (default) zorunlu — endpoint sadece authenticated kullanıcı için.

---

## 4. Veritabanı Migration

### 4.1 Yeni tablo: `account_deletion_log`

```sql
-- migrations/0007_account_deletion_log.sql

CREATE TABLE IF NOT EXISTS public.account_deletion_log (
    id          BIGSERIAL PRIMARY KEY,
    deleted_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    user_id_hash TEXT NOT NULL,         -- SHA-256, geri çevrilemez
    email_domain TEXT,                   -- yalnızca @sonrası ("gmail.com")
    reason      TEXT NOT NULL CHECK (reason IN ('user_request', 'admin_action', 'inactive', 'tos_violation')),
    notes       TEXT
);

-- 3 yıl sonra otomatik temizleme (TBK 146 zamanaşımı)
CREATE INDEX idx_deletion_log_deleted_at ON public.account_deletion_log(deleted_at);

-- RLS — yalnızca service-role yazabilir/okuyabilir
ALTER TABLE public.account_deletion_log ENABLE ROW LEVEL SECURITY;
-- (RLS politikası tanımlanmadığında hiçbir kullanıcı erişemez; service-role her zaman bypass eder)

COMMENT ON TABLE public.account_deletion_log IS
  'Anonim hesap silme kayıtları. KVKK kanıtı için 3 yıl saklanır. PII içermez.';
```

### 4.2 Mevcut tablolarda CASCADE doğrulama

Mevcut şemada (`supabase_schema.sql`) `user_id` foreign key'leri için `ON DELETE CASCADE` zaten tanımlı olmalı. Doğrulamak için:

```sql
SELECT
    tc.table_name,
    kcu.column_name,
    rc.delete_rule
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu
    ON tc.constraint_name = kcu.constraint_name
JOIN information_schema.referential_constraints rc
    ON tc.constraint_name = rc.constraint_name
WHERE tc.constraint_type = 'FOREIGN KEY'
    AND kcu.column_name = 'user_id';
```

`delete_rule = 'CASCADE'` olmayan tablolar için ALTER yapılmalı.

---

## 5. 30 Günlük Soft-Delete (Opsiyonel ama önerilen)

KVKK'da "kalıcı silme" zorunlu, ama Apple/Google "30 gün undo periyodu" izin verir. Eğer kullanıcı yanlışlıkla silerse iade etmek istiyorsanız:

### 5.1 Schema güncelle:

```sql
ALTER TABLE public.profiles ADD COLUMN deleted_at TIMESTAMPTZ;
ALTER TABLE public.profiles ADD COLUMN scheduled_purge_at TIMESTAMPTZ;
```

### 5.2 Edge function değişikliği:
- `auth.admin.deleteUser()` çağrısı yerine `profiles.deleted_at = NOW()` set et
- Background cron 30 gün sonra gerçek `auth.admin.deleteUser()` çağırır

### 5.3 Cron (pg_cron veya external):

```sql
SELECT cron.schedule(
  'purge-deleted-accounts',
  '0 3 * * *',  -- her gece 03:00
  $$ SELECT delete_user_function() $$
);
```

**Karar:** İlk versiyonda **soft-delete kullanmayın** (basit tutun). Sonradan ekleme yaparsınız.

---

## 6. Web Sayfası — Halka Açık Veri Silme

Google Play "Account deletion" zorunluluğu için web sayfası da şart. `[WEBSITE]/data-deletion` URL'inde [DATA_DELETION_REQUEST_FORM.md](DATA_DELETION_REQUEST_FORM.md) içindeki HTML formu yayınlayın.

---

## 7. Test Planı

| Test | Beklenen Sonuç |
|---|---|
| Yanlış şifre ile silme dene | Edge function 401, "Şifre hatalı" mesajı |
| Doğru şifre ile silme | 1. Account deletion log eklenir, 2. auth.users'dan silinir, 3. CASCADE ile assets/snapshots/partnerships silinir, 4. Local cache temizlenir, 5. LoginScreen'e döner |
| Silme sonrası eski JWT ile API isteği | 401, "User not found" |
| Aynı e-posta ile yeniden kayıt | Yeni hesap, eski veriler GELMEZ |
| Ortaklık varken silme | Karşı tarafın "active partners" listesinden de düşer |

---

## 8. Store Listing'de Belirtilecekler

### Google Play Console — Data Safety:
- "Users can request that data be deleted" → ✓ Yes
- "User data deletion link" → `[WEBSITE]/data-deletion`
- "Users can delete their account from within the app" → ✓ Yes

### App Store Connect — App Privacy:
- "Account Deletion Method" → "In-app + URL"
- URL: `[WEBSITE]/data-deletion`

---

## 9. KVKK Uyumluluk Notu

Bu akış aşağıdaki KVKK gereksinimlerini karşılar:

- **Madde 7** — Kişisel verilerin silinmesi, yok edilmesi veya anonim hâle getirilmesi
- **Madde 11(e)** — Silme talep hakkı
- **Madde 12** — Veri güvenliği (re-authentication ile yetkisiz silme engellenir)
- **Madde 13** — 30 gün içinde yanıt (anlık siliniyor — daha hızlı)
- **TBK Madde 146** — 3 yıl saklama (anonim log)

---

## 10. Tahmini Geliştirme Süresi

| İş | Süre |
|---|---|
| SettingsScreen + delete UI | 4 saat |
| AuthService.deleteAccount metodu | 2 saat |
| Edge Function (delete-account) | 4 saat |
| Schema migration (account_deletion_log + CASCADE doğrulama) | 2 saat |
| Web sayfası (data-deletion HTML) | 2 saat |
| Manuel + integration test | 4 saat |
| **TOPLAM** | **~2 iş günü** |
