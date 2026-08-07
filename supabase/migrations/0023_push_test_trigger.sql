-- Push zincirini ELLE tetikleme — teşhis/doğrulama için.
--
-- Neden gerekli: cron günde yalnızca 2 kez çalışır (TR 11:00 / 15:00).
-- Bir düzeltmenin işe yarayıp yaramadığını görmek için ertesi günü beklemek
-- gerekiyordu. Bu fonksiyon `trigger_analyze_signals` ile AYNI yolu kullanır
-- (vault secret → net.http_post → edge function), yani gerçek cron akışının
-- provasıdır — ayrı bir kod yolu değil.
--
-- Güvenlik: admin e-postasına kısıtlı (0021'deki is_push_admin). Cron
-- secret'ı istemciye HİÇ verilmez; vault'tan sunucu tarafında okunur.

create or replace function public.push_test_trigger(
  p_slot     text default 'morning',
  p_dry_run  boolean default true
)
returns text
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/analyze-signals';
  cron_secret  text;
  req_id       bigint;
begin
  if not public.is_push_admin() then
    raise exception 'Yetkisiz';
  end if;

  if p_slot not in ('morning', 'afternoon') then
    raise exception 'Gecersiz slot: %', p_slot;
  end if;

  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'analyze_signals_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret analyze_signals_cron_secret bulunamadi';
  end if;

  select net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('slot', p_slot, 'dry_run', p_dry_run)
  ) into req_id;

  -- net.http_post asenkron: yanıt net._http_response'a düşer.
  -- push_http_responses() ile birkaç saniye sonra okunabilir.
  return 'İstek kuyruğa alındı (id=' || req_id ||
         '). Birkaç saniye sonra yenileyip 3. bölüme bakın.';
end;
$$;

revoke all on function public.push_test_trigger(text, boolean) from public, anon;
grant execute on function public.push_test_trigger(text, boolean) to authenticated;

comment on function public.push_test_trigger(text, boolean) is
  'Push teşhisi: analyze-signals''ı elle tetikler. dry_run=true yan etki '
  'bırakmaz. Admin only.';
