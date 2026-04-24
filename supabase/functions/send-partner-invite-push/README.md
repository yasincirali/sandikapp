# send-partner-invite-push

Bu Edge Function, ortaklik kodunu giren kullanicinin istegini kod sahibine FCM remote push olarak gonderir.

Gerekli secret'lar:

- `FCM_PROJECT_ID`
- `FCM_SERVICE_ACCOUNT_JSON`

Ornek:

```bash
supabase secrets set FCM_PROJECT_ID=your-firebase-project-id
supabase secrets set FCM_SERVICE_ACCOUNT_JSON='{"type":"service_account","project_id":"..."}'
```

Deploy:

```bash
supabase functions deploy send-partner-invite-push
```
