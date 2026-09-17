-- 0066 — Genel uygulama bildirimleri çan sayfasında görünsün
--
-- ## Belirti (kullanıcı, 2026-09-17)
--
-- "Gelen tüm bildirimler — fiyat alarmı, sinyal, ortaklık bildirimi, özet
-- bilgisi gibi tüm push'lar — bildirim çanı altında görünebilmeli."
--
-- Sinyal (`signal_notifications`, 0010) ve fiyat alarmı
-- (`price_alert_notifications`, 0065) kendi tablolarına yazılıyordu; ortaklık
-- daveti, günlük brifing, haftalık özet ve takvim hatırlatması ise YALNIZCA
-- push olarak gidiyor, kaçırılırsa uygulama içinde izi kalmıyordu.
--
-- ## Neden TEK genel tablo (dört ayrı tablo yerine)
--
-- Bu dört türün ortak yapısı var: başlık + gövde + küçük bir veri sözlüğü
-- (yönlendirme için). Sinyal/alarm gibi türe özgü sayısal alanları yok. Dört
-- ayrı tablo dört ayrı RLS + GRANT + temizlik + istemci provider'ı demekti;
-- tek tablo + `type` sütunu yeter. Sinyal ve alarm ise kendi tablolarında
-- KALIR (türe özgü alanlar); üç kaynak istemcide zaman sırasına göre
-- birleştirilir (bkz. `bildirimAkisi`).
--
-- `data` jsonb: yönlendirme için gereken kimlikler (`invite_id` vb.). Şema
-- dayatılmaz — tür başına farklı ve küçük.

create table if not exists public.app_notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null references auth.users(id) on delete cascade,
  type         text not null check (type in (
                 'partner_invite', 'daily_brief', 'weekly_summary',
                 'calendar_nudge')),
  title        text not null,
  body         text not null,
  data         jsonb not null default '{}'::jsonb,
  sent_at      timestamptz not null default now(),
  -- 0010/0065 ile AYNI sözleşme: dismissed = listeden düşürülmüş, geçmişte
  -- duruyor; kalıcı silme ayrı.
  dismissed_at timestamptz
);

create index if not exists ix_app_notifications_user
  on public.app_notifications (user_id, sent_at desc);

alter table public.app_notifications enable row level security;
alter table public.app_notifications force row level security;

-- ── RLS ─────────────────────────────────────────────────────────────────────
--
-- INSERT politikası YOK (0065 deseni): satırı yalnızca edge function
-- (service_role) yazar. Kullanıcının kendi adına sahte "ortaklık daveti"
-- kaydı üretebilmesi için sebep yok.
drop policy if exists app_notifications_own_select on public.app_notifications;
create policy app_notifications_own_select
  on public.app_notifications
  for select to authenticated using (auth.uid() = user_id);

drop policy if exists app_notifications_own_update on public.app_notifications;
create policy app_notifications_own_update
  on public.app_notifications
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists app_notifications_own_delete on public.app_notifications;
create policy app_notifications_own_delete
  on public.app_notifications
  for delete to authenticated using (auth.uid() = user_id);

-- ── GRANT ───────────────────────────────────────────────────────────────────
-- RLS ve GRANT ayrı şeylerdir (CLAUDE.md). INSERT bilinçli olarak yok.
grant select, update, delete on public.app_notifications to authenticated;
revoke all on public.app_notifications from anon;

-- ── Temizlik ────────────────────────────────────────────────────────────────
-- Sinyal ve alarmla aynı ölçü: 90 gün.
create or replace function public.cleanup_app_notifications()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.app_notifications
   where sent_at < now() - interval '90 days';
$$;

revoke all on function public.cleanup_app_notifications()
  from public, anon, authenticated;

select cron.schedule('app-notifications-cleanup', '50 22 * * 0',
  $$select public.cleanup_app_notifications()$$);

-- ── Kendini doğrula ─────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.table_privileges
     where table_schema = 'public'
       and table_name = 'app_notifications'
       and grantee = 'authenticated'
       and privilege_type = 'SELECT'
  ) then
    raise exception
      '0066: authenticated rolunde SELECT grant yok — istemci listeyi okuyamaz.';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'app_notifications'
       and policyname = 'app_notifications_own_select'
  ) then
    raise exception '0066: select politikasi kurulamadi.';
  end if;

  raise notice '0066 tamam: app_notifications + RLS + GRANT yerinde.';
end;
$$;
