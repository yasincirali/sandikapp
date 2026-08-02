-- Eksik sinyal/push tablolarını garantiye alır.
--
-- Neden gerekli: 0015 uygulandıktan sonra canlı veritabanında
-- `signal_notifications` ve `user_push_tokens` tablolarının BULUNMADIĞI
-- tespit edildi (PostgREST: "Could not find the table ... in the schema
-- cache"). Buna karşın 0007/0012/0014'ün tabloları mevcut — yani 0010
-- bir noktada uygulanmadan atlanmış (muhtemelen migration geçmişi elle
-- `repair` edilmiş ya da tablo dashboard'dan silinmiş).
--
-- `user_push_tokens` için repoda hiç migration yoktu; tablo yalnızca
-- dashboard'da elle oluşturulmuştu. Bu dosya onu da şemaya bağlar, böylece
-- yeni bir ortam sıfırdan kurulduğunda push akışı kendiliğinden çalışır.
--
-- Tümü `if not exists` — mevcut ortamda zararsız, tekrar çalıştırılabilir.

-- ── Push token'ları ─────────────────────────────────────────────────────────
-- Bir kullanıcının birden çok cihazı olabilir (Android + iOS). Benzersizlik
-- token üzerinde: aynı token iki kullanıcıya yazılamaz, cihaz el değiştirirse
-- upsert son sahibine taşır.
create table if not exists user_push_tokens (
  token      text primary key,
  user_id    uuid references auth.users(id) on delete cascade not null,
  platform   text not null default 'unknown',
  updated_at timestamptz not null default now()
);

-- Edge function kullanıcı başına toplu okur.
create index if not exists user_push_tokens_user_idx
  on user_push_tokens(user_id);

alter table user_push_tokens enable row level security;

-- Kullanıcı yalnızca kendi token'ını yönetir.
-- (Edge function service_role ile bağlanır, RLS'i bypass eder.)
drop policy if exists "user_push_tokens_own_select" on user_push_tokens;
create policy "user_push_tokens_own_select"
  on user_push_tokens for select
  using (auth.uid() = user_id);

drop policy if exists "user_push_tokens_own_insert" on user_push_tokens;
create policy "user_push_tokens_own_insert"
  on user_push_tokens for insert
  with check (auth.uid() = user_id);

drop policy if exists "user_push_tokens_own_update" on user_push_tokens;
create policy "user_push_tokens_own_update"
  on user_push_tokens for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "user_push_tokens_own_delete" on user_push_tokens;
create policy "user_push_tokens_own_delete"
  on user_push_tokens for delete
  using (auth.uid() = user_id);


-- ── Sinyal bildirim geçmişi ─────────────────────────────────────────────────
-- 0010 ile aynı şema; orada uygulanmadıysa burada oluşur.
create table if not exists signal_notifications (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  asset_id     text not null,
  asset_name   text not null,
  asset_ticker text,
  asset_type   text not null,
  signal       text not null check (signal in ('buy', 'sell', 'neutral')),
  buy_count    int not null default 0,
  sell_count   int not null default 0,
  confidence   numeric not null default 0,
  sent_at      timestamptz not null default now(),
  dismissed_at timestamptz
);

create index if not exists signal_notifications_user_sent_idx
  on signal_notifications(user_id, sent_at desc);

-- De-dup sorgusu: "bu varlık için son sinyal neydi?"
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
