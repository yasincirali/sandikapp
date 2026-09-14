-- 0057 — Sessiz saatler: kullanıcı başına tek global bildirim penceresi
--
-- `quiet_start` / `quiet_end` TR saati (0-23). İkisi de null → kapalı.
-- Sarmalı pencere desteklenir (22 → 7). Kullanan fonksiyonlar:
-- daily-brief, weekly-summary, calendar-nudge, check-price-alerts
-- (`_shared/quiet_hours.ts`). analyze-signals kendi tür bazlı penceresini
-- kullanmaya devam eder (signal_preferences.window_start/end).
--
-- Alarm sessiz saatte ATLANIR, damgalanmaz: pencere bitince koşul
-- sürüyorsa bir sonraki turda gider.

alter table public.profiles
  add column if not exists quiet_start smallint,
  add column if not exists quiet_end smallint;

alter table public.profiles
  drop constraint if exists profiles_quiet_hours_range;
alter table public.profiles
  add constraint profiles_quiet_hours_range check (
    (quiet_start is null and quiet_end is null) or
    (quiet_start between 0 and 23 and quiet_end between 0 and 23)
  );

comment on column public.profiles.quiet_start is
  'Sessiz saat başlangıcı, TR saati 0-23. null = sessiz saat kapalı.';
comment on column public.profiles.quiet_end is
  'Sessiz saat bitişi (hariç), TR saati 0-23. start > end ise gece yarısını sarar.';
