-- 0123 — Admin hesabı Premium içeriği kilitsiz görür (2026-10-05)
--
-- ## Neden
-- yasin (2026-10-05): "bu paywall'a özel alanların hepsi admin hesabı için
-- açık olmalı." Admin kimliği zaten var: `push_admins` (0060; UUID'ye bağlı,
-- istemci erişimi yok). Premium kararının TEK kaynağı `premium_mi_kullanici`
-- (0116); `premium_mi()` ve `premium_icerik_gorebilir()` onu çağırır. Admin
-- satırı orada sayılınca not içeriği, aylık rapor, radar ayrıntısı ve ekstre
-- AI eşleme (`ekstre-esle`, 0121) paywall açıkken de admin'e açık olur.
--
-- ## Eski sürümler
-- Fonksiyon imzası aynı (create or replace); yalnız admin için true döner.
-- Admin olmayan herkes için sonuç birebir eski. Tablo/GRANT değişmez.

create or replace function public.premium_mi_kullanici(p_user_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.premium_haklari h
     where h.user_id = p_user_id
       and (h.bitis is null or h.bitis > now())
  )
  or exists (
    select 1 from public.push_admins a where a.user_id = p_user_id
  );
$$;

revoke all on function public.premium_mi_kullanici(uuid) from public, anon, authenticated;
grant execute on function public.premium_mi_kullanici(uuid) to service_role;

do $$
begin
  if has_function_privilege('authenticated', 'public.premium_mi_kullanici(uuid)', 'EXECUTE') then
    raise exception '0123: premium_mi_kullanici istemciye kapali olmali';
  end if;
  if not has_function_privilege('authenticated', 'public.premium_mi()', 'EXECUTE') then
    raise exception '0123: premium_mi authenticated icin acik olmali';
  end if;
end $$;
