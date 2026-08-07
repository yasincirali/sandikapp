-- Push zinciri teşhisi: cron → net.http_post → edge function → FCM
--
-- Neden gerekli: "push çalışmıyor" şikayetinde zincirin hangi halkasının
-- koptuğunu görmenin yolu yoktu. cron.job / cron.job_run_details ve
-- net._http_response tabloları yalnızca postgres rolüne açık; istemciden
-- (hatta CLI'dan) okunamıyor. Bu fonksiyonlar o üç tabloyu ADMIN'e özel,
-- SALT OKUNUR biçimde dışarı verir.
--
-- Güvenlik: security definer + sabit search_path + admin e-posta kontrolü.
-- Yalnızca uygulama sahibinin hesabı çağırabilir; anon/authenticated'a
-- doğrudan tablo erişimi verilmez.

-- Admin kontrolü tek yerde: e-posta değişirse burası güncellenir.
create or replace function public.is_push_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce(
    (select email = 'vasin_dirali@hotmail.com'
     from auth.users where id = auth.uid()),
    false
  );
$$;

-- ── 1. Cron job'ları kurulu mu, aktif mi? ────────────────────────────────
create or replace function public.push_cron_jobs()
returns table (
  jobid    bigint,
  jobname  text,
  schedule text,
  active   boolean
)
language plpgsql
stable
security definer
set search_path = public, cron
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select j.jobid, j.jobname::text, j.schedule::text, j.active
  from cron.job j
  where j.jobname like 'analyze-signals%'
  order by j.jobid;
end;
$$;

-- ── 2. Cron gerçekten çalıştı mı, çıktısı ne? ────────────────────────────
-- `status` = 'failed' ise return_message hatayı söyler (örn. vault secret
-- bulunamadı). Hiç satır yoksa cron HİÇ tetiklenmemiş demektir.
create or replace function public.push_cron_runs(p_limit int default 20)
returns table (
  jobname        text,
  status         text,
  return_message text,
  start_time     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, cron
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select d.jobname::text, d.status::text,
         d.return_message::text, d.start_time
  from cron.job_run_details d
  where d.jobname like 'analyze-signals%'
  order by d.start_time desc
  limit least(p_limit, 100);
end;
$$;

-- ── 3. Edge function çağrısı ne yanıt döndü? ─────────────────────────────
-- net.http_post asenkron: yanıt buraya düşer. 401 → cron secret ile edge
-- function secret'ı uyuşmuyor. 5xx → fonksiyon içinde hata.
create or replace function public.push_http_responses(p_limit int default 20)
returns table (
  id          bigint,
  status_code int,
  content     text,
  created     timestamptz
)
language plpgsql
stable
security definer
set search_path = public, net
as $$
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  return query
  select r.id, r.status_code,
         -- Yanıt gövdesi kırpılır: token/secret sızıntısına karşı.
         left(r.content, 500) as content,
         r.created
  from net._http_response r
  order by r.created desc
  limit least(p_limit, 100);
end;
$$;

revoke all on function public.is_push_admin()          from public, anon;
revoke all on function public.push_cron_jobs()         from public, anon;
revoke all on function public.push_cron_runs(int)      from public, anon;
revoke all on function public.push_http_responses(int) from public, anon;

grant execute on function public.push_cron_jobs()         to authenticated;
grant execute on function public.push_cron_runs(int)      to authenticated;
grant execute on function public.push_http_responses(int) to authenticated;

comment on function public.push_cron_jobs() is
  'Push teşhisi: analyze-signals cron job''ları kurulu/aktif mi. Admin only.';
comment on function public.push_cron_runs(int) is
  'Push teşhisi: cron çalışma geçmişi + hata mesajları. Admin only.';
comment on function public.push_http_responses(int) is
  'Push teşhisi: net.http_post yanıtları (401 = secret uyuşmazlığı). Admin only.';
