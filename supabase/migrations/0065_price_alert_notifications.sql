-- 0065 — Fiyat alarmı bildirimleri uygulama içi listede görünsün
--
-- ## Belirti
--
-- Fiyat alarmı tetiklendiğinde push gidiyordu ama bildirim çanı sayfasında
-- HİÇ görünmüyordu. Push'u kaçıran kullanıcı için o alarm kayboluyordu:
-- "alarm kurmuştum, çalıştı mı?" sorusunun uygulama içinde cevabı yoktu.
--
-- ## Neden AYRI tablo (signal_notifications'a kolon eklemek yerine)
--
-- `signal_notifications` teknik sinyale özgü: `buy_count`, `sell_count`,
-- `confidence`, `signal` (al/sat/nötr). Fiyat alarmının hiçbirinde karşılığı
-- yok — o tabloya sokmak dört kolonu kalıcı olarak nullable yapmak ve
-- `SignalAlert` modelinin iki işi birden taşıması demekti. Alarmın kendi
-- alanları da (`target_price`, `direction`, `triggered_price`) sinyal
-- tarafında anlamsız kalırdı.
--
-- İki tür bildirim, iki tablo; birleştirme İSTEMCİDE, zaman sırasına göre
-- yapılır (bkz. `bildirimAkisi`).
--
-- ## asset_id YOK, symbol VAR — bilinçli
--
-- Alarm sembol üstünden kurulur (`price_alerts.symbol`) ve sunucu hangi
-- lot'tan geldiğini bilmez; aynı sembolde birden çok lot olabilir. İstemci
-- sembolü `alarmSembolu()` ile varlığa geri eşler (bkz.
-- `NotificationService.openPriceAlertAsset`). Buraya bir `asset_id` yazmak,
-- sunucuyu olmayan bir bilgiyi uydurmaya zorlardı.

create table if not exists public.price_alert_notifications (
  id             uuid primary key default gen_random_uuid(),
  user_id        uuid not null references auth.users(id) on delete cascade,

  -- Alarmın kendisi silinse de bildirim listede kalır: kullanıcı "dün ne
  -- oldu"yu sorabilmeli. Bu yüzden `set null` — cascade DEĞİL.
  alert_id       uuid references public.price_alerts(id) on delete set null,

  -- Fiyat kaynağının anladığı sembol ('ALTIN_GRAM', 'THYAO.IS').
  symbol         text not null,
  -- Kullanıcıya gösterilecek ad — sembol kodu listede okunmaz.
  label          text not null,

  target_price   numeric(18, 4) not null,
  -- Tetiklendiği ANDAKİ fiyat. `target_price`'tan farklı olabilir (fiyat
  -- hedefi aşarak geçer) ve kullanıcının görmek istediği sayı budur.
  triggered_price numeric(18, 4) not null,
  direction      text not null check (direction in ('above', 'below')),

  sent_at        timestamptz not null default now(),
  -- Sinyal tarafıyla AYNI sözleşme: dismissed = listeden düşürülmüş ama
  -- geçmişte duruyor (bkz. 0010_signal_notifications).
  dismissed_at   timestamptz
);

create index if not exists ix_price_alert_notifications_user
  on public.price_alert_notifications (user_id, sent_at desc);

alter table public.price_alert_notifications enable row level security;
-- FORCE: tablo sahibi de politikalara tabi (0056 deseni).
alter table public.price_alert_notifications force row level security;

-- ── RLS ─────────────────────────────────────────────────────────────────────
--
-- INSERT politikası YOK ve bu kasıtlı: satırı yalnızca edge function
-- (service_role) yazar. service_role RLS'i baypas eder; kullanıcının kendi
-- adına sahte "alarm tetiklendi" kaydı yazabilmesi için bir sebep yok.
drop policy if exists price_alert_notifications_own_select
  on public.price_alert_notifications;
create policy price_alert_notifications_own_select
  on public.price_alert_notifications
  for select to authenticated using (auth.uid() = user_id);

-- UPDATE: yalnızca dismiss için (kullanıcı listeden düşürür).
drop policy if exists price_alert_notifications_own_update
  on public.price_alert_notifications;
create policy price_alert_notifications_own_update
  on public.price_alert_notifications
  for update to authenticated using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists price_alert_notifications_own_delete
  on public.price_alert_notifications;
create policy price_alert_notifications_own_delete
  on public.price_alert_notifications
  for delete to authenticated using (auth.uid() = user_id);

-- ── GRANT ───────────────────────────────────────────────────────────────────
--
-- RLS ve GRANT AYRI şeylerdir (CLAUDE.md): politika yazmak yetmez, tablo
-- ayrıcalığı da verilmeli. Eksikse istemci "permission denied for table"
-- alır ve bu RLS hatası sanılır.
--
-- INSERT bilinçli olarak YOK — yukarıdaki nota bak.
grant select, update, delete on public.price_alert_notifications
  to authenticated;
revoke all on public.price_alert_notifications from anon;

-- ── Temizlik ────────────────────────────────────────────────────────────────
--
-- Sinyal tarafında 90 günlük saklama var; aynı ölçü. Alarm bildirimi
-- dismissed olsun olmasın 90 gün sonra tarihsel değerini yitirir.
create or replace function public.cleanup_price_alert_notifications()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.price_alert_notifications
   where sent_at < now() - interval '90 days';
$$;

revoke all on function public.cleanup_price_alert_notifications()
  from public, anon, authenticated;

select cron.schedule('price-alert-notifications-cleanup', '45 22 * * 0',
  $$select public.cleanup_price_alert_notifications()$$);

-- ── Kendini doğrula ─────────────────────────────────────────────────────────
--
-- `0054`'ün dersi: sessizce uygulanmamış migration en pahalı hata sınıfı.
-- GRANT eksikliği özellikle sinsi — RLS doğru görünürken istemci okuyamaz.
do $$
begin
  if not exists (
    select 1 from information_schema.table_privileges
     where table_schema = 'public'
       and table_name = 'price_alert_notifications'
       and grantee = 'authenticated'
       and privilege_type = 'SELECT'
  ) then
    raise exception
      '0065: authenticated rolunde SELECT grant yok — istemci listeyi okuyamaz.';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public'
       and tablename = 'price_alert_notifications'
       and policyname = 'price_alert_notifications_own_select'
  ) then
    raise exception '0065: select politikasi kurulamadi.';
  end if;

  raise notice '0065 tamam: price_alert_notifications + RLS + GRANT yerinde.';
end;
$$;
