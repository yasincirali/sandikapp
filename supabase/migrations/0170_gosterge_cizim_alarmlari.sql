-- 0170 — Gösterge ve çizgi alarmı: "fiyat EMA50'yi keserse / çizdiğim
-- trend çizgisine değerse haber ver" (2026-10-29)
--
-- ## İstek
-- yasin 2026-10-29: "Gösterge ya da çizgiye değdiğinde push gelmesi
-- yapılabilir mi?" — üç seçeneğin üçü de onaylandı:
--   1) Yatay çizgi alarmı: yatay grafikteki yatay çizgiden NORMAL fiyat
--      alarmı (`price_alerts`, şema değişmez; bu dosyada yer almaz).
--   2) Gösterge alarmı (Premium): fiyat EMA20/50/200, SMA20 ya da Bollinger
--      bandını keserse → `gosterge_alarmlari`.
--   3) Trend çizgisi / ışın alarmı (Premium): fiyat kullanıcının çizdiği
--      eğik çizgiye değerse → `cizim_alarmlari`.
--
-- ## Karar: AYRI tablolar, `price_alerts`'e dokunulmaz
-- 0169 ile aynı gerekçe: eski build `price_alerts.direction`'ı
-- `== 'below' ? below : above` okur ve satır `target_price > 0` sabit hedef
-- ister. Gösterge ve eğik çizginin hedefi her an değişir; aynı tabloya
-- yazmak eski sürümde uydurma bir hedefle görünürdü. Yeni tabloları eski
-- istemci hiç okumaz (CLAUDE.md "sunucu eski sürümlerle uyumlu": yalnız
-- EKLER). `check-price-alerts` yeni turu fiyat alarmından ÖNCE ve try
-- içinde koşar; fiyat alarmının sorgusu ve davranışı değişmez.
--
-- ## Tetikleme: TARAF DEĞİŞİMİ, tek atış
-- "Değdi" bir an değil bir GEÇİŞTİR: sunucu her turda fiyatın seviyenin
-- hangi tarafında olduğunu (`son_taraf`: 'ust' | 'alt') saklar ve taraf
-- değişince (yöne uyuyorsa) çalar. İlk değerlendirme yalnız tarafı yazar:
-- kurulduğu anda zaten öbür taraftaysa "kesti" demek uydurma olurdu.
-- Fiyat seviyenin etrafında salınırsa her turda bildirim gelmesin diye
-- fiyat alarmıyla aynı TEK ATIŞ: çalınca `enabled=false` + `triggered_at`.
-- Damga koşullu UPDATE ile atılır (`triggered_at is null`): çakışan iki tur
-- ikisi de push göndermez (0168 `alarmiSondur` gerekçesi).
--
-- ## Gösterge seviyesi: günlük kapanış + canlı fiyat
-- Seviye günlük kapanışlardan, son nokta CANLI fiyat olarak hesaplanır
-- (bugünün yarım çubuğu yerine canlı fiyat). EMA tüm geçmişten (istemcinin
-- `TechnicalAnalysisService.emaSeries`'i ile aynı tohum: ilk `periyot`
-- noktanın ortalaması); `technical_analysis.ts › ema()` yalnız son
-- periyot×3'e baktığı için kullanılmaz. EMA200 için 2 yıllık seri gerekir;
-- sinyal önbelleği (`price_history_cache`, 6 ay) yetmez ve onun aralığını
-- büyütmek sinyal hesabını değiştirirdi → ayrı önbellek tablosu
-- (`gosterge_seri_onbellegi`, yalnız service_role).
--
-- ## Kapsam (uydurma sayı yasak — fiyat kaynağı sözleşmesi madde 3)
-- Gösterge alarmı yalnız günlük kapanışı ve canlı fiyatı AYNI kaynaktan ve
-- aynı birimde gelen sembollerde: BIST, ABD hissesi, endeks, emtia, fon,
-- kripto, TL dışı parite. Altın ayarları ve TL dövizler HARİÇ: canlı fiyat
-- truncgil'den (yurt içi kotasyon), günlük seri Yahoo'dan (vadeli × kur);
-- ikisi arasında yüzde birkaçlık yapısal fark var ve "EMA50'yi kesti"
-- kararı tam o farkın içinde verilirdi. Kapsam kodda tek yerde
-- (`_shared/gosterge_alarmi.ts › gostergeAlarmKapsamindaMi`, istemci eşi
-- `FiyatKaynagi.gostergeAlarmiKapsamindaMi`); kapsam dışı satır DB'de
-- reddedilmez, sunucu onu değerlendirmez (0169 ile aynı karar).
--
-- Çizgi alarmının noktaları grafiğin birimindedir (TL); istemci yalnız
-- alarm fiyatı TL olan sembolde (altın, TL döviz, fon, kripto, BIST) sunar
-- (`cizimAlarmSembolu`). Noktalar duvar saatine göre doğrusal saklanır:
-- istemci çizimi "şu an" ve sonrası için grafikte göründüğü doğruya
-- çevirip yazar (`cizimAlarmDogrusu`).
--
-- ## Premium
-- Gösterge ve çizgi alarmı Premium (ürün kuralı: yeni özellik varsayılan
-- Premium). Yazma (INSERT/UPDATE) `premium_icerik_gorebilir()` (0116)
-- ister — 0141 deseni: sunucu kapısı kapalıyken her oturumlu kullanıcı,
-- açıkken yalnız Premium. Okuma ve silme her zaman sahibine açık
-- (aboneliği biten kullanıcı alarmını görür ve silebilir). Yatay çizgi
-- alarmı normal fiyat alarmıdır ve ücretsizdir (20 alarm tavanı içinde).
--
-- ## Sınır
-- Ücretsiz alarm tavanı (20) istemcide ve TOPLAM sayılır (fiyat + yüzde +
-- gösterge + çizgi, `etkinAlarmSayisi`). Burada yalnız kötüye kullanıma
-- karşı kaba üst sınır (tablo başına kullanıcı başı 100 satır, tetikleyici).
--
-- ## Çan kaydı
-- Çalan alarm `app_notifications`'a `gosterge_alarm` / `cizim_alarm`
-- türüyle yazılır (0066 gerekçesi: push kaçırılsa da iz kalsın). CHECK
-- GENİŞLETİLİR; hiçbir tür çıkmaz. Eski build bilinmeyen türü genel
-- "Hatırlatma" satırı olarak gösterir (başlık + gövde okunur).
--
-- ## Kişisel veri
-- Kullanıcının kendi kurduğu alarm (sembol, gösterge/çizgi, yön). Fiyat
-- alarmıyla aynı amaç, aynı saklama (hesap silinene kadar, `on delete
-- cascade`), üçüncü tarafa gitmez. Yasal metne dokunulmaz (0169 ile aynı).
-- Çizgi noktaları kişisel veri değildir (grafikte zaman + fiyat).
--
-- ## İki sunucu
-- Yalnız tablolar + politikalar + tetikleyiciler + CHECK genişletmesi;
-- cron yok (değerlendirme var olan `check-price-alerts` / `-hizli`
-- işlerinde). 0170 bir sunucuda henüz yoksa yeni tur hata verir, yakalanır
-- ve fiyat alarmı turu eskisi gibi koşar.

-- ── 1) Gösterge alarmları ───────────────────────────────────────────────────
create table if not exists public.gosterge_alarmlari (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                  references auth.users(id) on delete cascade,
  -- Fiyat alarmıyla aynı alfabe: 'THYAO.IS', 'AAPL', 'KRIPTO:BTC'.
  symbol          text not null check (char_length(symbol) between 1 and 40),
  -- Bildirimde okunan ad.
  label           text not null check (char_length(btrim(label)) between 1 and 80),
  gosterge        text not null
                  check (gosterge in ('ema20', 'ema50', 'ema200', 'sma20', 'bb_ust', 'bb_alt')),
  -- 'yukari' → fiyat seviyeyi aşağıdan yukarı keserse; 'asagi' → yukarıdan
  -- aşağı; 'her_ikisi' → hangi yöne olursa.
  yon             text not null check (yon in ('yukari', 'asagi', 'her_ikisi')),
  -- Son değerlendirmede fiyatın seviyeye göre tarafı; ilk değerlendirmeye
  -- kadar null (ilk tur yalnız yazar, çalmaz).
  son_taraf       text check (son_taraf in ('ust', 'alt')),
  -- Son hesaplanan seviye ve zamanı (listede "EMA50 ₺309,80" yazmak için;
  -- uydurma değil, sunucunun karşılaştırdığı sayının kendisi).
  son_seviye      numeric(24, 8),
  son_degerlendirme timestamptz,
  enabled         boolean not null default true,
  triggered_at    timestamptz,
  -- Çaldığı andaki fiyat ve seviye (bildirimdeki sayılar).
  tetik_fiyat     numeric(24, 8),
  tetik_seviye    numeric(24, 8),
  created_at      timestamptz not null default now()
);

create index if not exists ix_gosterge_alarmlari_active
  on public.gosterge_alarmlari (symbol)
  where enabled and triggered_at is null;

create index if not exists ix_gosterge_alarmlari_user
  on public.gosterge_alarmlari (user_id, created_at desc);

alter table public.gosterge_alarmlari enable row level security;
alter table public.gosterge_alarmlari force row level security;

drop policy if exists gosterge_alarmlari_own_select on public.gosterge_alarmlari;
create policy gosterge_alarmlari_own_select on public.gosterge_alarmlari
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists gosterge_alarmlari_own_insert on public.gosterge_alarmlari;
create policy gosterge_alarmlari_own_insert on public.gosterge_alarmlari
  for insert to authenticated
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists gosterge_alarmlari_own_update on public.gosterge_alarmlari;
create policy gosterge_alarmlari_own_update on public.gosterge_alarmlari
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists gosterge_alarmlari_own_delete on public.gosterge_alarmlari;
create policy gosterge_alarmlari_own_delete on public.gosterge_alarmlari
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Açık GRANT (0161 sonrası kural): istemci kendi satırını CRUD eder,
-- sunucu (check-price-alerts) okur ve damgalar. anon hiçbir şey göremez.
revoke all on table public.gosterge_alarmlari from public, anon, authenticated;
grant select, insert, update, delete on table public.gosterge_alarmlari to authenticated;
grant select, insert, update, delete on table public.gosterge_alarmlari to service_role;

-- ── 2) Çizgi (trend / ışın) alarmları ───────────────────────────────────────
create table if not exists public.cizim_alarmlari (
  id              uuid primary key default gen_random_uuid(),
  user_id         uuid not null default auth.uid()
                  references auth.users(id) on delete cascade,
  symbol          text not null check (char_length(symbol) between 1 and 40),
  label           text not null check (char_length(btrim(label)) between 1 and 80),
  -- Cihazdaki çizimin kimliği (`GrafikCizimi.id`): çizim silinince/taşınınca
  -- istemci alarmını bununla bulur. Çizimin kendisi cihazda kalır.
  cizim_id        text not null check (char_length(cizim_id) between 1 and 64),
  -- Çizimin alarm kurulduğundaki biçimi (istemci düzenlemeyi bununla fark
  -- eder ve alarmı günceller). Sunucu okumaz.
  cizim_imzasi    text check (char_length(cizim_imzasi) <= 400),
  -- Doğru: (t1, p1) → (t2, p2), t epoch ms, p alarm biriminde. Sunucu
  -- `p1 + (p2 − p1)·(şimdi − t1)/(t2 − t1)` ile bugünkü değeri bulur.
  t1              bigint not null,
  p1              numeric(24, 8) not null check (p1 > 0),
  t2              bigint not null,
  p2              numeric(24, 8) not null check (p2 > 0),
  -- true → ışın (t2'den sonra da uzar); false → parça (t2'den sonra susar).
  uzanir          boolean not null default false,
  yon             text not null check (yon in ('yukari', 'asagi', 'her_ikisi')),
  son_taraf       text check (son_taraf in ('ust', 'alt')),
  son_seviye      numeric(24, 8),
  son_degerlendirme timestamptz,
  enabled         boolean not null default true,
  triggered_at    timestamptz,
  tetik_fiyat     numeric(24, 8),
  tetik_seviye    numeric(24, 8),
  created_at      timestamptz not null default now(),
  constraint cizim_alarmlari_zaman_sirasi check (t2 > t1)
);

-- Çizim başına tek alarm: çalmış alarm yeniden kurulurken satır güncellenir.
create unique index if not exists ux_cizim_alarmlari_cizim
  on public.cizim_alarmlari (user_id, symbol, cizim_id);

create index if not exists ix_cizim_alarmlari_active
  on public.cizim_alarmlari (symbol)
  where enabled and triggered_at is null;

alter table public.cizim_alarmlari enable row level security;
alter table public.cizim_alarmlari force row level security;

drop policy if exists cizim_alarmlari_own_select on public.cizim_alarmlari;
create policy cizim_alarmlari_own_select on public.cizim_alarmlari
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists cizim_alarmlari_own_insert on public.cizim_alarmlari;
create policy cizim_alarmlari_own_insert on public.cizim_alarmlari
  for insert to authenticated
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists cizim_alarmlari_own_update on public.cizim_alarmlari;
create policy cizim_alarmlari_own_update on public.cizim_alarmlari
  for update to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id
              and public.premium_icerik_gorebilir());

drop policy if exists cizim_alarmlari_own_delete on public.cizim_alarmlari;
create policy cizim_alarmlari_own_delete on public.cizim_alarmlari
  for delete to authenticated using ((select auth.uid()) = user_id);

revoke all on table public.cizim_alarmlari from public, anon, authenticated;
grant select, insert, update, delete on table public.cizim_alarmlari to authenticated;
grant select, insert, update, delete on table public.cizim_alarmlari to service_role;

-- ── 3) Uzun günlük seri önbelleği (yalnız sunucu) ───────────────────────────
-- Sembol başına 2 yıllık günlük kapanış + zamanı. Zaman gerekir: bugünün
-- yarım çubuğu atılıp yerine canlı fiyat konur. İstemci okumaz.
create table if not exists public.gosterge_seri_onbellegi (
  symbol      text primary key check (char_length(symbol) between 1 and 40),
  zamanlar    bigint[] not null,
  kapanislar  double precision[] not null,
  fetched_at  timestamptz not null default now(),
  constraint gosterge_seri_onbellegi_esit_uzunluk
    check (cardinality(zamanlar) = cardinality(kapanislar))
);

alter table public.gosterge_seri_onbellegi enable row level security;
alter table public.gosterge_seri_onbellegi force row level security;
-- Politika YOK: authenticated/anon için RLS her satırı gizler, GRANT de yok.
revoke all on table public.gosterge_seri_onbellegi from public, anon, authenticated;
grant select, insert, update, delete on table public.gosterge_seri_onbellegi to service_role;

-- ── 4) Denetim tetikleyicileri ──────────────────────────────────────────────
-- Kaba üst sınır + değişmez alanlar. SECURITY INVOKER: sayım çağıranın
-- RLS'i altında yalnız kendi satırlarını görür (0141/0169 deseni).
create or replace function public.gosterge_alarmlari_denetim()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.gosterge_alarmlari g
         where g.user_id = new.user_id) >= 100 then
      raise exception 'gosterge_alarmlari: en fazla 100 alarm'
        using errcode = 'P0001';
    end if;
  else
    new.user_id := old.user_id;
    new.created_at := old.created_at;
    -- Gösterge ya da sembol değişirse eski taraf geçersiz: yeniden
    -- "ilk değerlendirme" gibi davranılır (uydurma kesişim yok).
    if (new.gosterge, new.symbol) is distinct from (old.gosterge, old.symbol) then
      new.son_taraf := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists gosterge_alarmlari_denetim on public.gosterge_alarmlari;
create trigger gosterge_alarmlari_denetim
  before insert or update on public.gosterge_alarmlari
  for each row execute function public.gosterge_alarmlari_denetim();

create or replace function public.cizim_alarmlari_denetim()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    if (select count(*) from public.cizim_alarmlari c
         where c.user_id = new.user_id) >= 100 then
      raise exception 'cizim_alarmlari: en fazla 100 alarm'
        using errcode = 'P0001';
    end if;
  else
    new.user_id := old.user_id;
    new.created_at := old.created_at;
    -- Çizgi taşındıysa eski taraf başka bir doğruya aitti.
    if (new.t1, new.p1, new.t2, new.p2, new.uzanir, new.symbol)
       is distinct from (old.t1, old.p1, old.t2, old.p2, old.uzanir, old.symbol) then
      new.son_taraf := null;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists cizim_alarmlari_denetim on public.cizim_alarmlari;
create trigger cizim_alarmlari_denetim
  before insert or update on public.cizim_alarmlari
  for each row execute function public.cizim_alarmlari_denetim();

-- ── 5) Çan kaydı türleri ────────────────────────────────────────────────────
-- 0169'daki liste + 'gosterge_alarm', 'cizim_alarm'. Hiçbir tür çıkmaz.
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge', 'temettu',
    'yuzde_alarm', 'gosterge_alarm', 'cizim_alarm'));

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
declare
  t text;
begin
  foreach t in array array['gosterge_alarmlari', 'cizim_alarmlari'] loop
    if has_table_privilege('anon', 'public.' || t, 'SELECT')
       or has_table_privilege('anon', 'public.' || t, 'INSERT') then
      raise exception '0170: anon % erisememeli', t;
    end if;
    if not (has_table_privilege('authenticated', 'public.' || t, 'SELECT')
        and has_table_privilege('authenticated', 'public.' || t, 'INSERT')
        and has_table_privilege('authenticated', 'public.' || t, 'UPDATE')
        and has_table_privilege('authenticated', 'public.' || t, 'DELETE')) then
      raise exception '0170: % authenticated CRUD GRANT eksik', t;
    end if;
    if not (has_table_privilege('service_role', 'public.' || t, 'SELECT')
        and has_table_privilege('service_role', 'public.' || t, 'UPDATE')) then
      raise exception '0170: % service_role okuma/damga GRANT eksik', t;
    end if;
    if not exists (select 1 from pg_class
                    where oid = ('public.' || t)::regclass
                      and relrowsecurity and relforcerowsecurity) then
      raise exception '0170: % RLS (enable + force) kapali', t;
    end if;
    if (select count(*) from pg_policies
         where schemaname = 'public' and tablename = t) <> 4 then
      raise exception '0170: % dort politika bekleniyordu', t;
    end if;
    if exists (select 1 from pg_policies
                where schemaname = 'public' and tablename = t
                  and not ('authenticated' = any(roles))) then
      raise exception '0170: % politikalari yalniz authenticated icin olmali', t;
    end if;
  end loop;

  if has_table_privilege('authenticated', 'public.gosterge_seri_onbellegi', 'SELECT')
     or has_table_privilege('anon', 'public.gosterge_seri_onbellegi', 'SELECT') then
    raise exception '0170: gosterge_seri_onbellegi yalniz service_role';
  end if;
  if not (has_table_privilege('service_role', 'public.gosterge_seri_onbellegi', 'SELECT')
      and has_table_privilege('service_role', 'public.gosterge_seri_onbellegi', 'INSERT')
      and has_table_privilege('service_role', 'public.gosterge_seri_onbellegi', 'UPDATE')) then
    raise exception '0170: gosterge_seri_onbellegi service_role GRANT eksik';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.gosterge_seri_onbellegi'::regclass
                    and relrowsecurity and relforcerowsecurity) then
    raise exception '0170: gosterge_seri_onbellegi RLS (enable + force) kapali';
  end if;

  if (select count(*) from pg_proc p
       join pg_namespace n on n.oid = p.pronamespace
      where n.nspname = 'public'
        and p.proname in ('gosterge_alarmlari_denetim', 'cizim_alarmlari_denetim')
        and p.proconfig @> array['search_path=public, pg_temp']) <> 2 then
    raise exception '0170: denetim fonksiyonlari search_path tasimali';
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'app_notifications_type_check'
                    and pg_get_constraintdef(oid) like '%gosterge_alarm%'
                    and pg_get_constraintdef(oid) like '%cizim_alarm%'
                    and pg_get_constraintdef(oid) like '%yuzde_alarm%'
                    and pg_get_constraintdef(oid) like '%temettu%') then
    raise exception '0170: app_notifications_type_check yeni turleri tanimiyor';
  end if;
  raise notice '0170 tamam: gosterge_alarmlari + cizim_alarmlari + gosterge_seri_onbellegi.';
end $$;
