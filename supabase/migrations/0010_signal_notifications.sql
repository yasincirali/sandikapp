-- Signal notifications: kullanıcının varlıkları için üretilmiş AL/SAT/NÖTR sinyalleri.
-- De-duplication: aynı asset için son gönderilen sinyal ile aynıysa yeniden atılmaz.
-- dismissed_at: kullanıcı sildiyse. Statü değişmeden yeniden push atılmaz.

create table if not exists signal_notifications (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid references auth.users(id) on delete cascade not null,
  asset_id    text not null,
  asset_name  text not null,
  asset_ticker text,
  asset_type  text not null,
  signal      text not null check (signal in ('buy', 'sell', 'neutral')),
  buy_count   int not null default 0,
  sell_count  int not null default 0,
  confidence  numeric not null default 0,
  sent_at     timestamptz not null default now(),
  dismissed_at timestamptz
);

create index if not exists signal_notifications_user_sent_idx
  on signal_notifications(user_id, sent_at desc);

create index if not exists signal_notifications_dedup_idx
  on signal_notifications(user_id, asset_id, sent_at desc);

alter table signal_notifications enable row level security;

drop policy if exists "signal_notifications_own_select" on signal_notifications;
create policy "signal_notifications_own_select"
  on signal_notifications for select
  using (auth.uid() = user_id);

drop policy if exists "signal_notifications_own_insert" on signal_notifications;
create policy "signal_notifications_own_insert"
  on signal_notifications for insert
  with check (auth.uid() = user_id);

drop policy if exists "signal_notifications_own_update" on signal_notifications;
create policy "signal_notifications_own_update"
  on signal_notifications for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "signal_notifications_own_delete" on signal_notifications;
create policy "signal_notifications_own_delete"
  on signal_notifications for delete
  using (auth.uid() = user_id);
