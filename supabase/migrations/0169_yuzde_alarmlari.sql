-- 0169 — Yüzde alarmı: "Gram altın bugün %2 düşerse haber ver" (2026-10-27)
--
-- ## İstek
-- Ar-Ge fikri 2026-10-27 08:45 §1 (yasin onayı). Fiyat alarmı yalnız sabit
-- hedef biliyor (`price_alerts.target_price` + `direction`); altın/döviz
-- takipçisinin sorusu çoğu zaman "şu fiyatı geçerse" değil "bugün sert
-- oynarsa". Hedefi her gün yeniden kurmak gerekiyordu.
--
-- ## Karar: AYRI tablo, `price_alerts`'e yeni `direction` YOK
-- Eski build'ler `price_alerts.direction`'ı `== 'below' ? below : above`
-- diye okur (`PriceAlert.fromMap`), sunucunun eski sürümü de bilinmeyen
-- yönü "altına" sayardı (`check-price-alerts` `isTriggered`). Aynı tabloya
-- `pct_down` gibi bir değer yazmak eski sürümde alarmı yanlış hedefle
-- gösterir ve satırı `target_price > 0` kısıtı yüzünden uydurma bir hedef
-- ister. Ayrı tabloyu eski istemci hiç okumaz (CLAUDE.md "sunucu eski
-- sürümlerle uyumlu": yalnız EKLER).
--
-- ## Kapsam
-- Yalnız günlük yüzdesi SUNUCUDA ölçülen semboller: altın ayarları + TL
-- dövizler (`yurt_ici_kotasyon.degisim_pct`, 0101) ve kripto
-- (`kripto_fiyat`, gün açılışına göre). `widget-fiyat` ile aynı kapsam
-- kararı (`_shared/widget_fiyat.ts › widgetSembolTuru`, fon HARİÇ: fonun
-- günde tek NAV'ı var, "bugün %2 düşerse" gün içi bir soru). Kapsam dışı
-- sembol satırı DB'de reddedilmez — sunucu onu değerlendirmez (sembol
-- listesi kodda, tek yerde; burada ikinci kopyası olmasın).
--
-- ## Günde bir kez
-- `son_tetik_gunu` TR günü (UTC+3). Tetiklenen alarm o gün bir daha
-- çalmaz, ertesi gün KENDİLİĞİNDEN yeniden kurulur — fiyat alarmının tek
-- atışı (`triggered_at` + `enabled=false`) burada yok, çünkü kullanıcının
-- istediği her gün tekrar eden bir nöbet. Damga koşullu UPDATE ile atılır
-- (`son_tetik_gunu is distinct from bugün`): çakışan iki tur ikisi de
-- push göndermez (0168 `alarmiSondur` gerekçesi).
--
-- ## Sınır
-- Ücretsiz alarm tavanı (20, Remote Config `free_price_alert_limit`)
-- istemcide; fiyat alarmıyla TOPLAM sayılır (`alarmSiniriDoluysaUyar`).
-- Fiyat alarmı tavanı da yalnız istemcide (0046). Burada yalnız kötüye
-- kullanıma karşı kaba bir üst sınır var (kullanıcı başına 100 satır):
-- RLS satır sayamaz, tetikleyici sayar.
--
-- ## Çan kaydı
-- Tetiklenen yüzde alarmı `app_notifications`'a `yuzde_alarm` türüyle
-- yazılır (push kaçırılsa da uygulamada izi kalsın — 0065/0066 gerekçesi).
-- CHECK kısıtı GENİŞLETİLİR; var olan türlerin hiçbiri çıkmaz. Eski build
-- bilinmeyen türü genel "Hatırlatma" satırı olarak gösterir (başlık +
-- gövde okunur, dokununca bir yere gitmez); yüzde alarmını yalnız yeni
-- build kurabildiği için bu satırı eski build ancak aynı hesabın ikinci,
-- güncellenmemiş cihazında görür.
--
-- ## Kişisel veri
-- Kullanıcının kendi kurduğu alarm (sembol, eşik, yön). Fiyat alarmıyla
-- aynı amaç ("kurduğun alarmların çalışması"), aynı saklama (hesap
-- silinene kadar, `on delete cascade`), üçüncü tarafa gitmez. Yasal metne
-- dokunulmaz (CLAUDE.md "Yasal metin tek kaynak").
--
-- ## İki sunucu
-- Yalnız tablo + politika + tetikleyici + CHECK genişletmesi; cron yok
-- (değerlendirme var olan `check-price-alerts` / `-hizli` işlerinde).

create table if not exists public.yuzde_alarmlari (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                  references auth.users(id) on delete cascade,
  -- Fiyat alarmıyla aynı alfabe: 'ALTIN_GRAM', 'USDTRY=X', 'KRIPTO:BTC'.
  symbol          text not null check (char_length(symbol) between 1 and 40),
  -- Bildirimde okunan ad ("Gram altın"); kod kimseye bir şey ifade etmez.
  label           text not null check (char_length(btrim(label)) between 1 and 80),
  -- Günlük değişim eşiği, mutlak yüzde. İstemci 1/2/3 sunar; üst sınır
  -- ileride başka çiplere yer bırakır, 0 ve negatif anlamsız.
  esik_pct        numeric(4, 2) not null check (esik_pct > 0 and esik_pct <= 20),
  -- 'dusus' → bugün en az eşik kadar düşünce; 'yukselis' → yükselince;
  -- 'ikisi' → hangi yöne olursa.
  yon             text not null check (yon in ('dusus', 'yukselis', 'ikisi')),
  enabled         boolean not null default true,
  -- Son tetiklendiği TR günü; bugünse bu gün bir daha çalmaz.
  son_tetik_gunu  date,
  son_tetik_at    timestamptz,
  -- Tetiklendiği andaki günlük yüzde ve fiyat (listede "bugün çalıştı ·
  -- %−2,1" yazmak için; uydurma değil, bildirimdeki sayının kendisi).
  son_tetik_pct   numeric(9, 3),
  son_tetik_fiyat numeric(24, 8),
  created_at      timestamptz not null default now()
);

create index if not exists ix_yuzde_alarmlari_active
  on public.yuzde_alarmlari (symbol)
  where enabled;

create index if not exists ix_yuzde_alarmlari_user
  on public.yuzde_alarmlari (user_id, created_at desc);

alter table public.yuzde_alarmlari enable row level security;
alter table public.yuzde_alarmlari force row level security;

-- Kullanıcı yalnızca KENDİ alarmlarını görür ve yönetir (0046 ile aynı).
drop policy if exists yuzde_alarmlari_own_select on public.yuzde_alarmlari;
create policy yuzde_alarmlari_own_select on public.yuzde_alarmlari
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists yuzde_alarmlari_own_insert on public.yuzde_alarmlari;
create policy yuzde_alarmlari_own_insert on public.yuzde_alarmlari
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists yuzde_alarmlari_own_update on public.yuzde_alarmlari;
create policy yuzde_alarmlari_own_update on public.yuzde_alarmlari
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists yuzde_alarmlari_own_delete on public.yuzde_alarmlari;
create policy yuzde_alarmlari_own_delete on public.yuzde_alarmlari
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Açık GRANT (0161 sonrası kural): istemci kendi satırını CRUD eder,
-- sunucu (check-price-alerts) okur ve damgalar. anon hiçbir şey göremez.
revoke all on table public.yuzde_alarmlari from public, anon, authenticated;
grant select, insert, update, delete on table public.yuzde_alarmlari to authenticated;
grant select, insert, update, delete on table public.yuzde_alarmlari to service_role;

-- Kaba üst sınır + değişmez alanlar. SECURITY INVOKER: sayım çağıranın
-- RLS'i altında yalnız kendi satırlarını görür (0141 deseni).
create or replace function public.yuzde_alarmlari_denetim()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.yuzde_alarmlari y
         where y.user_id = new.user_id) >= 100 then
      raise exception 'yuzde_alarmlari: en fazla 100 alarm'
        using errcode = 'P0001';
    end if;
  else
    new.user_id := old.user_id;
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists yuzde_alarmlari_denetim on public.yuzde_alarmlari;
create trigger yuzde_alarmlari_denetim
  before insert or update on public.yuzde_alarmlari
  for each row execute function public.yuzde_alarmlari_denetim();

-- ── Çan kaydı türü ──────────────────────────────────────────────────────────
-- 0086'daki liste + 'yuzde_alarm'. Hiçbir tür çıkmaz.
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge', 'temettu',
    'yuzde_alarm'));

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if has_table_privilege('anon', 'public.yuzde_alarmlari', 'SELECT')
     or has_table_privilege('anon', 'public.yuzde_alarmlari', 'INSERT') then
    raise exception '0169: anon yuzde_alarmlari erisememeli';
  end if;
  if not (has_table_privilege('authenticated', 'public.yuzde_alarmlari', 'SELECT')
      and has_table_privilege('authenticated', 'public.yuzde_alarmlari', 'INSERT')
      and has_table_privilege('authenticated', 'public.yuzde_alarmlari', 'UPDATE')
      and has_table_privilege('authenticated', 'public.yuzde_alarmlari', 'DELETE')) then
    raise exception '0169: authenticated CRUD GRANT eksik';
  end if;
  if not (has_table_privilege('service_role', 'public.yuzde_alarmlari', 'SELECT')
      and has_table_privilege('service_role', 'public.yuzde_alarmlari', 'UPDATE')) then
    raise exception '0169: service_role okuma/damga GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.yuzde_alarmlari'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0169: yuzde_alarmlari RLS (enable + force) kapali';
  end if;
  if (select count(*) from pg_policies
       where schemaname = 'public' and tablename = 'yuzde_alarmlari') <> 4 then
    raise exception '0169: yuzde_alarmlari dort politika bekleniyordu';
  end if;
  if exists (select 1 from pg_policies
              where schemaname = 'public' and tablename = 'yuzde_alarmlari'
                and not ('authenticated' = any(roles))) then
    raise exception '0169: yuzde_alarmlari politikalari yalniz authenticated icin olmali';
  end if;
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.proname = 'yuzde_alarmlari_denetim'
      and p.proconfig @> array['search_path=public, pg_temp']
  ) then
    raise exception '0169: yuzde_alarmlari_denetim search_path tasimali';
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'app_notifications_type_check'
                    and pg_get_constraintdef(oid) like '%yuzde_alarm%'
                    and pg_get_constraintdef(oid) like '%temettu%') then
    raise exception '0169: app_notifications_type_check yuzde_alarm turunu tanimiyor';
  end if;
  raise notice '0169 tamam: yuzde_alarmlari + app_notifications yuzde_alarm turu.';
end $$;
