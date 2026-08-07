-- 0021'deki push_cron_runs hatasını düzeltir.
--
-- Hata: "column d.jobname does not exist" (42703).
-- pg_cron'un bu sürümünde `cron.job_run_details` içinde jobname sütunu YOK;
-- yalnızca jobid var. Job adına ulaşmak için cron.job ile join gerekir.
--
-- Ayrıca job adına göre filtrelemek yerine artık TÜM çalışmalar döner:
-- job silinip yeniden kurulduğunda eski jobid'ler cron.job'da bulunmaz ve
-- inner join o kayıtları düşürürdü — hata geçmişi tam görünsün diye left join.

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
  select
    coalesce(j.jobname, '(silinmiş job #' || d.jobid || ')')::text,
    d.status::text,
    d.return_message::text,
    d.start_time
  from cron.job_run_details d
  left join cron.job j on j.jobid = d.jobid
  order by d.start_time desc
  limit least(p_limit, 100);
end;
$$;

revoke all on function public.push_cron_runs(int) from public, anon;
grant execute on function public.push_cron_runs(int) to authenticated;

comment on function public.push_cron_runs(int) is
  'Push teşhisi: cron çalışma geçmişi + hata mesajları. jobname cron.job '
  'join''inden gelir (job_run_details''te böyle bir sütun yok). Admin only.';
