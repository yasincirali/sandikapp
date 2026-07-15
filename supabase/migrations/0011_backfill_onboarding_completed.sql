-- Onboarding tamamlanma flag'i: kolonu garanti altına al + mevcut kullanıcıları
-- "görüldü" olarak işaretle.
--
-- Neden: supabase_schema.sql üretim DB'sine uygulanmamış → `onboarding_completed`
-- kolonu prod'da yok. Client tarafı bu alanı okur/yazar; yoksa okuma null döner
-- ve `isCompleted` false verir → her girişte onboarding tekrar açılır.
--
-- Strateji:
--   1) Kolonu DEFAULT false ile ekle (idempotent).
--   2) Mevcut kayıtları toplu true'ya çek — bugüne kadar hesap oluşturmuş
--      kullanıcılar onboarding'i görmüş sayılır. Yeni kayıtlar default false
--      ile başlar ve normal akışta işaretlenir.

alter table public.profiles
  add column if not exists onboarding_completed boolean not null default false;

update public.profiles
set onboarding_completed = true
where onboarding_completed is distinct from true;
