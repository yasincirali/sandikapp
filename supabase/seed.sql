-- Yerel / CI tohum verisi — YALNIZCA `supabase start` / `supabase db reset`
-- ile yerel yığına yüklenir (config.toml [db.seed]). Canlı projeye `db push`
-- bu dosyayı KOŞMAZ.
--
-- ── Ne için ────────────────────────────────────────────────────────────────
-- Yol haritası 3.16: `integration_test/smoke_test.dart` (giriş → varlık ekle
-- → portföyü gör) ve `tool/supabase_smoke.sh` (aynı akışın başsız, REST
-- sürümü) bu kullanıcıyla girer. Şifre gerçek bir sır değil; yerel yığın
-- dışarıdan erişilemez ve her `db reset`'te sıfırlanır.
--
-- ── Neden auth.users'a doğrudan yazılıyor ──────────────────────────────────
-- GoTrue admin API'si CI adımına bir de service_role çağrısı eklerdi; SQL
-- tohumu ise `db reset` ile aynı işlemde, ek araçsız gelir. Kolon kümesi
-- GoTrue'nun okuduğu alanlarla sınırlı; `confirmation_token` ve benzeri
-- metin kolonları NULL bırakılırsa GoTrue "converting NULL to string"
-- hatasıyla girişi reddeder — bu yüzden boş dize.
--
-- Profil satırını `on_auth_user_created` tetikleyicisi (0000) açar;
-- `onboarding_completed = true` ile tanıtım turu atlanır. Yasal uyarı onayı
-- KASITLI olarak tohumlanmıyor: `disclaimer_acceptances` sürüm + hash
-- taşıyor ve metin değişince tohum bayatlardı. Duman testi o ekranı
-- gerçek kullanıcı gibi geçer.

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
  confirmation_token, recovery_token, email_change_token_new, email_change,
  is_sso_user
) values (
  '00000000-0000-0000-0000-000000000000',
  '11111111-1111-4111-8111-111111111111',
  'authenticated', 'authenticated',
  'smoke@sandik.test',
  crypt('Duman1234', gen_salt('bf')),
  now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  '{"display_name":"Duman Testi"}'::jsonb,
  now(), now(),
  '', '', '', '',
  false
)
on conflict (id) do nothing;

insert into auth.identities (
  id, user_id, provider_id, identity_data, provider,
  last_sign_in_at, created_at, updated_at
) values (
  gen_random_uuid(),
  '11111111-1111-4111-8111-111111111111',
  '11111111-1111-4111-8111-111111111111',
  '{"sub":"11111111-1111-4111-8111-111111111111","email":"smoke@sandik.test","email_verified":true}'::jsonb,
  'email',
  now(), now(), now()
)
on conflict (provider_id, provider) do nothing;

update public.profiles
   set onboarding_completed = true,
       display_name = 'Duman Testi'
 where id = '11111111-1111-4111-8111-111111111111';
