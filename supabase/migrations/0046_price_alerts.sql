-- 0046_price_alerts.sql
-- ============================================================
-- Fiyat alarmları — "gram altın 5.400 olunca haber ver".
--
-- ÜRÜN GEREKÇESİ: bu, kullanıcının KENDİSİNİN kurduğu tek bildirimdir.
-- Alaka garantili, opt-out riski yok, ve alarm kuran kullanıcı uygulamayı
-- kurulu bırakmak için bir sebep edinir. Sunucu tarafında değerlendirilir
-- ki uygulama kapalıyken de çalışsın — açıkken çalışan bir alarm, geri
-- getirme kanalı değildir.
-- ============================================================

create table if not exists public.price_alerts (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,

  -- Fiyat kaynağının anladığı sembol: 'THYAO.IS', 'ALTIN_GRAM', 'USDTRY=X'.
  -- İstemcideki `PriceService` ile aynı alfabe (bkz. _shared/live_prices.ts).
  symbol       text not null,
  -- Kullanıcıya gösterilecek ad — sembol kodu bildirimde okunmaz
  -- ("ALTIN_GRAM 5.400'ü geçti" kimseye bir şey ifade etmez).
  label        text not null,

  target_price numeric(18, 4) not null check (target_price > 0),
  -- 'above' → fiyat hedefe ULAŞINCA ya da geçince
  -- 'below' → fiyat hedefin ALTINA inince
  direction    text not null check (direction in ('above', 'below')),

  enabled      boolean not null default true,
  -- Tetiklendiği an. Dolduğunda alarm KENDİLİĞİNDEN susar.
  --
  -- Neden tek atış: hedefin etrafında salınan bir fiyat, tekrar eden alarmda
  -- dakikada bir bildirim üretirdi. Kullanıcı yeniden kurmak isterse bir
  -- dokunuş yeter; her turda bildirim yemek geri alınamaz.
  triggered_at timestamptz,
  created_at   timestamptz not null default now()
);

create index if not exists ix_price_alerts_active
  on public.price_alerts (symbol)
  where enabled and triggered_at is null;

create index if not exists ix_price_alerts_user
  on public.price_alerts (user_id, created_at desc);

alter table public.price_alerts enable row level security;

-- Kullanıcı yalnızca KENDİ alarmlarını görür ve yönetir.
drop policy if exists price_alerts_own_select on public.price_alerts;
create policy price_alerts_own_select on public.price_alerts
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists price_alerts_own_insert on public.price_alerts;
create policy price_alerts_own_insert on public.price_alerts
  for insert to authenticated with check (auth.uid() = user_id);

drop policy if exists price_alerts_own_update on public.price_alerts;
create policy price_alerts_own_update on public.price_alerts
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists price_alerts_own_delete on public.price_alerts;
create policy price_alerts_own_delete on public.price_alerts
  for delete to authenticated using (auth.uid() = user_id);

-- ── Tetikleyici ─────────────────────────────────────────────────────────────
create or replace function public.trigger_check_price_alerts()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
declare
  function_url text := 'https://ybdbzouzhzwthjgwlbmk.supabase.co/functions/v1/check-price-alerts';
  cron_secret  text;
begin
  select decrypted_secret into cron_secret
  from vault.decrypted_secrets
  where name = 'price_alerts_cron_secret';

  if cron_secret is null then
    raise exception 'Vault secret price_alerts_cron_secret bulunamadi';
  end if;

  perform net.http_post(
    url := function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || cron_secret
    ),
    body := jsonb_build_object('source', 'cron')
  );
end;
$$;

revoke all on function public.trigger_check_price_alerts() from public, anon, authenticated;

select cron.unschedule(jobid) from cron.job
 where jobname = 'check-price-alerts';

-- pg_cron UTC. `*/30 5-18` = TR 08:00–21:30, yarım saatte bir.
--
-- Pencere SESSİZ SAATLERE göre seçildi (TR 22:00–08:00 bildirim yasak,
-- bkz. RETENTION_STRATEJISI.md §7). Son tur 18:30 UTC = TR 21:30.
--
-- Hafta sonu da koşar: altın ve döviz BIST saatlerine bağlı değil ve
-- Türkiye'de hafta sonu altın fiyatı takip eden kullanıcı çok.
select cron.schedule('check-price-alerts', '*/30 5-18 * * *',
  $$select public.trigger_check_price_alerts()$$);
