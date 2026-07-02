# delete-account Edge Function

Kullanıcının hesabını ve tüm verisini kalıcı olarak siler.

## Deploy

```bash
# Supabase CLI gerekli — https://supabase.com/docs/guides/cli
supabase login
supabase link --project-ref <PROJECT_REF>

# Hash salt set et (production secret)
supabase secrets set DELETION_HASH_SALT="$(openssl rand -hex 32)"

# Deploy
supabase functions deploy delete-account
```

## Migration

Önce `account_deletion_log` tablosunu oluştur:

```bash
supabase db push
# veya manuel olarak:
psql $DATABASE_URL -f supabase/migrations/0007_account_deletion_log.sql
```

## Test

```bash
# Bir test hesabı oluştur, JWT'yi al, sonra:
curl -i -X POST \
  -H "Authorization: Bearer $USER_JWT" \
  https://<PROJECT_REF>.supabase.co/functions/v1/delete-account

# Beklenen: 200 { "success": true, "deleted_at": "..." }
```

## Güvenlik Notları

- Endpoint **authenticated** kullanıcı gerektirir (anon erişim yok).
- Flutter tarafında **şifre re-authentication** zorunlu (AuthService.deleteAccount).
- `SUPABASE_SERVICE_ROLE_KEY` Edge runtime environment'ta tanımlıdır;
  client'a hiç gönderilmez.
- `DELETION_HASH_SALT` production'da random 32+ byte olmalı, asla commit edilmez.

## CASCADE Tabloları

`auth.users` silindiğinde otomatik silinen tablolar
(`supabase_schema.sql`'de ON DELETE CASCADE tanımlı):

- `public.profiles`
- `public.assets`
- `public.snapshots`
- `public.partner_invites` (from_user_id ve to_user_id)
- `public.partnerships` (user_id_1 ve user_id_2)
- `public.user_push_tokens`
- `public.disclaimer_acceptances`

`public.db_logs` — `ON DELETE SET NULL` (logları silmeyiz, sadece user_id null'lar).

## Saklanan Anonim Kayıt

`account_deletion_log`:
- `user_id_hash`: SHA-256(user_id + DELETION_HASH_SALT) — geri çevrilemez
- `email_domain`: sadece "@" sonrası (örn. "gmail.com")
- `deleted_at`: silme zamanı
- `reason`: 'user_request' / 'admin_action' / 'inactive' / 'tos_violation'

3 yıl saklanır (TBK Madde 146 zamanaşımı). Sonra cron ile silinir.
