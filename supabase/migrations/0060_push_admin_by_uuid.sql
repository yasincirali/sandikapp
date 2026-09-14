-- 0060_push_admin_by_uuid.sql
-- ============================================================
-- M9 (2026-09): `is_push_admin()` yönetici kararını e-posta eşitliğiyle
-- veriyordu (0021). E-posta değiştirilebilir bir alan: hesap e-postası
-- güncellenirse yetki kaybolur; e-posta yeniden kullanılabilirse
-- (hesap silinip aynı adresle açılırsa) yetki yeni hesaba geçer.
--
-- Çözüm: yetki KİMLİĞE bağlanır. `push_admins(user_id)` tablosu bir kez
-- bugünkü e-postadan çözülerek doldurulur; sonrası UUID üstünden gider.
-- Tabloya istemci erişimi yoktur (RLS + GRANT yok); yalnızca fonksiyon
-- okur. Yeni yönetici eklemek = SQL Editor'da bir INSERT.
-- ============================================================

create table if not exists public.push_admins (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.push_admins enable row level security;
alter table public.push_admins force row level security;
revoke all on public.push_admins from public, anon, authenticated;

-- Bir kerelik tohum: 0021'deki adres bugün hangi hesaba aitse o.
insert into public.push_admins (user_id)
select id from auth.users where email = 'vasin_dirali@hotmail.com'
on conflict do nothing;

create or replace function public.is_push_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.push_admins where user_id = auth.uid()
  );
$$;

revoke all on function public.is_push_admin() from public, anon;
grant execute on function public.is_push_admin() to authenticated;

do $$
begin
  if (select count(*) from public.push_admins) = 0 then
    raise warning 'push_admins bos: 0021 e-postasi auth.users''ta bulunamadi; SQL Editor''dan INSERT gerekir.';
  end if;
end $$;
