do $$
declare
  v_secret text := '636943c728e9095109d168d68e2560d8c3cf80cf178d3d306d8a2d461b246348';
  v_name text := 'daily_brief_cron_secret';
begin
  if exists (select 1 from vault.secrets where name = v_name) then
    perform vault.update_secret(
      (select id from vault.secrets where name = v_name order by created_at desc limit 1),
      v_secret, v_name, null);
  else
    perform vault.create_secret(v_secret, v_name, null);
  end if;
end $$;