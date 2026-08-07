-- Kullanıcı tanımlı bildirim sıklığı (varlık türü başına).
--
-- Önceden sinyal push'u herkes için sabit iki slottaydı (TR 11:00 / 15:00).
-- Artık kullanıcı her varlık türü için ayrı sıklık seçebilir:
--   hourly | every_2h | every_3h | twice_daily | daily
--
-- Zamanlama tasarımı: cron 10:00–18:00 arası SAATBAŞI çalışır; hangi
-- kullanıcıya gönderileceğine edge function karar verir. Böylece her periyot
-- için ayrı cron job'a gerek kalmaz ve sıklık değişince cron'a dokunulmaz.
--
-- Saat penceresi: bildirimler TR saatiyle 10:00–18:00 dışına ASLA çıkmaz.
-- Kullanıcının seçtiği saatler bu aralığa check constraint ile kısıtlanır.

alter table signal_preferences
  -- Bildirim sıklığı.
  add column if not exists frequency text not null default 'twice_daily'
    check (frequency in ('hourly','every_2h','every_3h','twice_daily','daily')),

  -- Kullanıcının seçtiği bildirim saatleri (TR saati, 0-23).
  -- twice_daily → 2 eleman, daily → 1 eleman beklenir.
  -- hourly/every_2h/every_3h için kullanılmaz (pencere boyunca periyodik).
  add column if not exists notify_hours int[] not null default array[11,15],

  -- Sıklık penceresinin başı/sonu (TR saati). 10–18 dışına çıkılamaz.
  add column if not exists window_start int not null default 10
    check (window_start between 10 and 18),
  add column if not exists window_end int not null default 18
    check (window_end between 10 and 18),

  -- Son gönderim zamanı — periyodik sıklıkta "yeterince zaman geçti mi"
  -- kontrolü için. Slot bazlı değil süre bazlı çalışır ki cron gecikse
  -- veya kaçsa bile bir sonraki turda telafi edilsin.
  add column if not exists last_notified_at timestamptz;

-- Pencere tutarlılığı: başlangıç bitişten büyük olamaz.
do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'signal_preferences_window_order'
  ) then
    alter table signal_preferences
      add constraint signal_preferences_window_order
      check (window_start <= window_end);
  end if;
end $$;

-- notify_hours içindeki her saat pencere içinde olmalı.
-- (Dizi elemanı check'i için yardımcı fonksiyon.)
create or replace function public.hours_within_window(
  hours int[], w_start int, w_end int
) returns boolean
language sql
immutable
as $$
  select coalesce(bool_and(h between w_start and w_end), true)
  from unnest(hours) as h;
$$;

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'signal_preferences_hours_in_window'
  ) then
    alter table signal_preferences
      add constraint signal_preferences_hours_in_window
      check (public.hours_within_window(notify_hours, window_start, window_end));
  end if;
end $$;

comment on column signal_preferences.frequency is
  'Bildirim sıklığı: hourly|every_2h|every_3h|twice_daily|daily';
comment on column signal_preferences.notify_hours is
  'twice_daily/daily için TR saatleri. Pencere (10-18) dışına çıkamaz.';
comment on column signal_preferences.last_notified_at is
  'Periyodik sıklıkta süre bazlı kontrol için son gönderim zamanı.';

-- ── Sıklık damgası yazımı ────────────────────────────────────────────────
-- Edge function gönderim sonrası last_notified_at günceller. Düz `upsert`
-- KULLANILAMAZ: tercih satırı zaten varsa upsert eksik kolonları tablo
-- varsayılanına döndürür ve kullanıcının threshold/indicators ayarlarını
-- sessizce sıfırlardı. Bu fonksiyon yalnızca damgaya dokunur.
create or replace function public.touch_signal_notified(
  p_user_id uuid,
  p_asset_type text,
  p_at timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into signal_preferences (user_id, asset_type, last_notified_at)
  values (p_user_id, p_asset_type, p_at)
  on conflict (user_id, asset_type)
  do update set last_notified_at = excluded.last_notified_at;
end;
$$;

revoke all on function public.touch_signal_notified(uuid, text, timestamptz)
  from public, anon, authenticated;

comment on function public.touch_signal_notified(uuid, text, timestamptz) is
  'Yalnızca last_notified_at günceller; diğer tercihlere dokunmaz. '
  'Edge function (service_role) çağırır.';

-- ── Cron: saatbaşı çalış, kararı edge function versin ────────────────────
-- pg_cron UTC. TR = UTC+3, yani TR 10:00–18:00 = UTC 07:00–15:00.
-- Saatbaşı tetiklenir; kimin sırası geldiğini fonksiyon hesaplar.
select cron.unschedule(jobid) from cron.job
 where jobname in ('analyze-signals-morning', 'analyze-signals-afternoon',
                   'analyze-signals-hourly');

select cron.schedule('analyze-signals-hourly', '0 7-15 * * *',
  $$select public.trigger_analyze_signals('hourly')$$);
