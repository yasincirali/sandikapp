-- 0188 — Saatli fiyat bildirimi (Premium; yasin 2026-11-26 11:38)
--
-- ## İstek
-- "Her varlık için kullanıcının seçtiği saatlerde o anki fiyat bilgisi push.
-- Varlık başına günde 5 saat, toplam 5 varlık." Tasarım:
-- sandik-arge/saatli-bildirim/tasarim.md. Kararlar (varsayılanlar): ücretsiz
-- tadımlık YOK (yalnız Premium), hızlı alarm turuna dokunulmadı, günlük push
-- tavanı eklenmedi.
--
-- ## Veri
-- `saatli_bildirimler`: kullanıcı başına sembol başına TEK satır
-- (unique user_id+symbol; saatleri değiştirmek satırı günceller, ikinci
-- satır açmaz). `saatler` TR gününün dakikası (0 = 00:00, 1425 = 23:45),
-- 15'in katı, en çok 5. `gunler` hafta günü bit maskesi: bit 0 pazartesi …
-- bit 6 pazar (ISO sırası), 127 = her gün. İstemci (`SaatliBildirim`) ve
-- sunucu (`_shared/saatli_bildirim.ts`) aynı sırayı kullanır.
-- `saatli_bildirim_gonderim`: (user_id, slot_ts) birincil anahtar — fonksiyon
-- push'tan ÖNCE yazar, yazamazsa (zaten var) göndermez: yeniden deneme ya da
-- çakışan iki çağrı çift push üretmez. Yalnız sunucu (service_role) görür.
--
-- ## Kapı — 0181 ile AYNI mantık
-- Premium değilse yeni satırı AKTİF yapan yazma (insert ya da pasif → aktif)
-- reddedilir. Kapının uygulandığı durum 0181'in birebir eşi:
-- premium_ayar.kapi_acik açık, acil_kapali kapalı, hesabın aktif cihazı iOS
-- ve premium_mi_kullanici false. Gerekçeler 0181'de (Android build'i
-- paywall'sızken canlı kullanıcı duvara çarpmasın; acil kapatma kilitleri
-- askıya alır). Kapı fonksiyonu `saatli_premium_gerekli` olarak ayrı: tek
-- yerde okunsun.
-- Sınırlar herkese (Premium dahil): en çok 5 aktif satır; satır başına 1–5
-- saat, 15'in katı, 0..1425; gün maskesi 1..127. Aktif satırı düzenlemek
-- (saat, ad) sayıma girmez; kapatma ve silme serbest.
-- Premium'u biten kullanıcının satırları SİLİNMEZ (tasarım: "satırlar
-- görünür, Premium'la yeniden gönderilir"); gönderimi fonksiyon keser.
--
-- ## Gönderim kapısı (fonksiyon)
-- `saatli_gonderilmez_kullanicilar(uuid[])`: kapı açık, acil kapalı ve
-- Premium değil → gönderilmez. Tetikleyiciden farkı yalnız platform şartı:
-- gönderimde yok. Neden: tetikleyicinin platform şartı, paywall'u görmeyen
-- build'in kullanıcısını duvardan korur; o kullanıcı istemcide bu özelliği
-- zaten açık göremez (`saatliBildirimDurumuProvider`: paywall kapalıyken
-- yalnız admin, admin Premium sayılır). Gönderimde şartı tutmak, Premium'u
-- biten Android kullanıcısına süresiz push demek olurdu.
--
-- ## Hata
-- SQLSTATE 54000 + mesajda sabit `saatli_siniri` (0181 `alarm_siniri`
-- deseni). İstemci mesajdan tanır (`saatliSiniriHatasiMi`), ham metin
-- kullanıcıya gitmez.
--
-- ## Cron
-- `saatli-bildirim` her 15 dakikada (`*/15 * * * *`, ayda 2.880 çağrı).
-- Secret `price_alerts_cron_secret` PAYLAŞILIR (emsal hacim-gozlem,
-- analiz-topla): yeni Vault anahtarı gerekmez. Projede tüm cron işleri
-- kapalıysa bu iş de kapalı kurulur (0174 kuralı).
--
-- ## Çan kaydı
-- `app_notifications` CHECK'i `saatli_bildirim` ile GENİŞLER; var olan tür
-- çıkmaz (0170 listesi + yeni tür).
--
-- ## Kişisel veri
-- Kullanıcının kendi kurduğu bildirim (sembol, saat, gün). Alarmla aynı
-- amaç, aynı saklama (hesap silinene kadar, on delete cascade), üçüncü
-- tarafa gitmez. Yasal metne dokunulmaz.
--
-- ## Eski sürümler
-- Yalnız EKLER: iki tablo, üç fonksiyon, bir tetikleyici, bir cron, CHECK
-- genişletmesi. Eski build yeni tabloları okumaz. İstemci tablo yokken
-- (bu migration canlıya gitmeden) bölümü tamamen gizler.

-- ── 1) Tablolar ─────────────────────────────────────────────────────────────
create table if not exists public.saatli_bildirimler (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
              references auth.users(id) on delete cascade,
  -- Fiyat alarmıyla aynı alfabe: 'ALTIN_GRAM', 'USDTRY=X', 'THYAO.IS'.
  symbol      text not null check (char_length(symbol) between 1 and 40),
  -- Bildirimde okunan ad ("Gram altın").
  label       text not null check (char_length(btrim(label)) between 1 and 80),
  saatler     smallint[] not null,
  gunler      smallint not null default 127,
  aktif       boolean not null default true,
  created_at  timestamptz not null default now(),
  constraint saatli_bildirimler_sembol_tek unique (user_id, symbol)
);

-- Fonksiyonun sorgusu: aktif satırlar, saat dizisi içinde dilim (GIN).
create index if not exists ix_saatli_bildirimler_saatler
  on public.saatli_bildirimler using gin (saatler)
  where aktif;

alter table public.saatli_bildirimler enable row level security;
alter table public.saatli_bildirimler force row level security;

drop policy if exists saatli_bildirimler_own_select on public.saatli_bildirimler;
create policy saatli_bildirimler_own_select on public.saatli_bildirimler
  for select to authenticated using ((select auth.uid()) = user_id);

drop policy if exists saatli_bildirimler_own_insert on public.saatli_bildirimler;
create policy saatli_bildirimler_own_insert on public.saatli_bildirimler
  for insert to authenticated with check ((select auth.uid()) = user_id);

drop policy if exists saatli_bildirimler_own_update on public.saatli_bildirimler;
create policy saatli_bildirimler_own_update on public.saatli_bildirimler
  for update to authenticated using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

drop policy if exists saatli_bildirimler_own_delete on public.saatli_bildirimler;
create policy saatli_bildirimler_own_delete on public.saatli_bildirimler
  for delete to authenticated using ((select auth.uid()) = user_id);

-- Açık GRANT (0161): istemci kendi satırını CRUD eder, sunucu okur.
revoke all on table public.saatli_bildirimler from public, anon, authenticated;
grant select, insert, update, delete on table public.saatli_bildirimler to authenticated;
grant select, insert, update, delete on table public.saatli_bildirimler to service_role;

create table if not exists public.saatli_bildirim_gonderim (
  user_id    uuid not null references auth.users(id) on delete cascade,
  -- Dilimin UTC başlangıcı (15 dakikaya yuvarlanmış).
  slot_ts    timestamptz not null,
  created_at timestamptz not null default now(),
  primary key (user_id, slot_ts)
);

-- Fonksiyonun eski kayıt temizliği `slot_ts < now() - 2 gün` ile.
create index if not exists ix_saatli_bildirim_gonderim_slot
  on public.saatli_bildirim_gonderim (slot_ts);

alter table public.saatli_bildirim_gonderim enable row level security;
alter table public.saatli_bildirim_gonderim force row level security;
-- Politika YOK: istemci rollerine kapalı; service_role RLS'i atlar.
revoke all on table public.saatli_bildirim_gonderim from public, anon, authenticated;
grant select, insert, delete on table public.saatli_bildirim_gonderim to service_role;

-- ── 2) Kapı fonksiyonları ───────────────────────────────────────────────────
-- 0181 `alarm_tavani_denetim` kapısının birebir eşi: true = bu kullanıcıda
-- Premium şartı uygulanır ve kullanıcı Premium değil.
create or replace function public.saatli_premium_gerekli(p_user_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_kapi boolean;
  v_acil boolean;
begin
  select a.kapi_acik, a.acil_kapali
    into v_kapi, v_acil
    from public.premium_ayar a
   where a.tek;
  if not coalesce(v_kapi, false) or coalesce(v_acil, false) then
    return false;
  end if;
  if not exists (
    select 1
      from public.aktif_cihaz ac
      join public.kayitli_cihazlar k
        on k.user_id = ac.user_id and k.cihaz_id = ac.cihaz_id
     where ac.user_id = p_user_id
       and k.platform = 'ios'
  ) then
    return false;
  end if;
  return not public.premium_mi_kullanici(p_user_id);
end;
$$;

revoke all on function public.saatli_premium_gerekli(uuid) from public, anon, authenticated;

comment on function public.saatli_premium_gerekli(uuid) is
  'Saatli bildirim yazma kapısı: 0181 alarm tavanıyla aynı koşullar (0188).';

-- Gönderim kapısı (fonksiyon): kapı açık, acil kapalı ve Premium değil.
-- Platform şartı yok (gerekçe başlıkta). Tek çağrıda tüm kullanıcılar.
create or replace function public.saatli_gonderilmez_kullanicilar(p_user_ids uuid[])
returns setof uuid
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  v_kapi boolean;
  v_acil boolean;
begin
  select a.kapi_acik, a.acil_kapali
    into v_kapi, v_acil
    from public.premium_ayar a
   where a.tek;
  if not coalesce(v_kapi, false) or coalesce(v_acil, false) then
    return;
  end if;
  return query
    select u from unnest(p_user_ids) as u
     where not public.premium_mi_kullanici(u);
end;
$$;

revoke all on function public.saatli_gonderilmez_kullanicilar(uuid[]) from public, anon, authenticated;
grant execute on function public.saatli_gonderilmez_kullanicilar(uuid[]) to service_role;

comment on function public.saatli_gonderilmez_kullanicilar(uuid[]) is
  'Saatli bildirim gönderilmeyecek (Premium olmayan) kullanıcılar; service_role (0188).';

-- ── 3) Tetikleyici ──────────────────────────────────────────────────────────
-- SECURITY DEFINER: kapı tabloları istemciye kapalı; sayım kullanıcının tüm
-- satırlarını görmeli. Dışarıdan girdi yalnız NEW/OLD satırı.
create or replace function public.saatli_bildirim_denetim()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := (select auth.uid());
  v_aktif integer;
begin
  -- Değişmez alanlar.
  if tg_op = 'UPDATE' then
    new.user_id := old.user_id;
    new.created_at := old.created_at;
  end if;

  -- Sunucu yazmaları (service_role, oturumsuz) muaf — 0181 ile aynı.
  if v_uid is null then
    return new;
  end if;

  -- Şekil: herkese, her yazmada.
  if new.saatler is null
     or cardinality(new.saatler) not between 1 and 5
     or exists (select 1 from unnest(new.saatler) s
                 where s is null or s < 0 or s > 1425 or s % 15 <> 0)
     or (select count(distinct s) from unnest(new.saatler) s) <> cardinality(new.saatler)
     or new.gunler is null or new.gunler not between 1 and 127 then
    raise exception 'saatli_siniri: saat 15 dakikalik adimla, en fazla 5; gun maskesi 1-127'
      using errcode = '54000', hint = 'saatli_siniri';
  end if;

  -- Yalnız bir satırı AKTİF YAPAN yazma kapıya ve sayıma girer.
  if not new.aktif then
    return new;
  end if;
  if tg_op = 'UPDATE' and old.aktif then
    return new;
  end if;

  if public.saatli_premium_gerekli(new.user_id) then
    raise exception 'saatli_siniri: saatli bildirim Premium ister'
      using errcode = '54000', hint = 'saatli_siniri';
  end if;

  -- Eşzamanlı iki yazma ikisi de 4 görüp 6 yapmasın (0181 deseni).
  perform pg_advisory_xact_lock(
    hashtextextended('saatli_bildirim:' || new.user_id::text, 0));

  select count(*) into v_aktif
    from public.saatli_bildirimler b
   where b.user_id = new.user_id and b.aktif;
  if v_aktif >= 5 then
    raise exception 'saatli_siniri: en fazla 5 aktif saatli bildirim'
      using errcode = '54000', hint = 'saatli_siniri';
  end if;
  return new;
end;
$$;

revoke all on function public.saatli_bildirim_denetim() from public, anon, authenticated;

comment on function public.saatli_bildirim_denetim() is
  'Saatli bildirim: şekil sınırları, 5 aktif satır, 0181 Premium kapısı (0188).';

drop trigger if exists saatli_bildirim_denetim on public.saatli_bildirimler;
create trigger saatli_bildirim_denetim
  before insert or update on public.saatli_bildirimler
  for each row execute function public.saatli_bildirim_denetim();

-- ── 4) Çan kaydı türü ───────────────────────────────────────────────────────
-- 0170 listesi + 'saatli_bildirim'. Hiçbir tür çıkmaz.
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;
alter table public.app_notifications
  add constraint app_notifications_type_check check (type in (
    'partner_invite', 'daily_brief', 'weekly_summary', 'monthly_summary',
    'watchlist_move', 'inflation_day', 'calendar_nudge', 'temettu',
    'yuzde_alarm', 'gosterge_alarm', 'cizim_alarm', 'saatli_bildirim'));

-- ── 5) Cron: her 15 dakika ──────────────────────────────────────────────────
create or replace function public.trigger_saatli_bildirim()
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('saatli-bildirim'),
    headers := public.cron_headers('price_alerts_cron_secret'),
    body := jsonb_build_object('source', 'cron'),
    timeout_milliseconds := 60000
  );
end;
$$;

revoke all on function public.trigger_saatli_bildirim() from public, anon, authenticated;

comment on function public.trigger_saatli_bildirim() is
  'Saatli fiyat bildirimi, 15 dakikada bir (0188).';

select cron.unschedule(jobid) from cron.job where jobname = 'saatli-bildirim';
select cron.schedule('saatli-bildirim', '*/15 * * * *',
  $$select public.trigger_saatli_bildirim()$$);

-- Projede tüm cron işleri kapalıysa (yerel yığın / donmuş proje) bu iş de
-- kapalı kurulur (0174 kuralı).
do $$
begin
  if exists (select 1 from cron.job where jobname <> 'saatli-bildirim')
     and not exists (select 1 from cron.job
                      where jobname <> 'saatli-bildirim' and active) then
    perform cron.alter_job(job_id := jobid, active := false)
       from cron.job where jobname = 'saatli-bildirim';
    raise notice '0188: projede tum cron isleri kapali — saatli-bildirim da kapali kuruldu.';
  end if;
end $$;

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
declare
  f text;
begin
  -- İzinler.
  if has_table_privilege('anon', 'public.saatli_bildirimler', 'SELECT')
     or has_table_privilege('anon', 'public.saatli_bildirimler', 'INSERT') then
    raise exception '0188: anon saatli_bildirimler erisememeli';
  end if;
  if not (has_table_privilege('authenticated', 'public.saatli_bildirimler', 'SELECT')
      and has_table_privilege('authenticated', 'public.saatli_bildirimler', 'INSERT')
      and has_table_privilege('authenticated', 'public.saatli_bildirimler', 'UPDATE')
      and has_table_privilege('authenticated', 'public.saatli_bildirimler', 'DELETE')) then
    raise exception '0188: authenticated saatli_bildirimler CRUD izni eksik';
  end if;
  if has_table_privilege('authenticated', 'public.saatli_bildirim_gonderim', 'SELECT')
     or has_table_privilege('anon', 'public.saatli_bildirim_gonderim', 'SELECT') then
    raise exception '0188: saatli_bildirim_gonderim istemciye kapali olmali';
  end if;
  if not has_table_privilege('service_role', 'public.saatli_bildirim_gonderim', 'INSERT') then
    raise exception '0188: service_role saatli_bildirim_gonderim yazamiyor';
  end if;
  if not (select relrowsecurity and relforcerowsecurity from pg_class
           where oid = 'public.saatli_bildirimler'::regclass)
     or not (select relrowsecurity from pg_class
           where oid = 'public.saatli_bildirim_gonderim'::regclass) then
    raise exception '0188: RLS acik degil';
  end if;

  -- Fonksiyonlar: SECURITY DEFINER + search_path, istemciye kapalı.
  foreach f in array array['public.saatli_premium_gerekli(uuid)',
                           'public.saatli_gonderilmez_kullanicilar(uuid[])',
                           'public.saatli_bildirim_denetim()',
                           'public.trigger_saatli_bildirim()'] loop
    if not exists (
      select 1 from pg_proc p
       where p.oid = f::regprocedure
         and p.prosecdef
         and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%')) then
      raise exception '0188: % SECURITY DEFINER + search_path olmali', f;
    end if;
    if has_function_privilege('authenticated', f, 'EXECUTE')
       or has_function_privilege('anon', f, 'EXECUTE') then
      raise exception '0188: % istemciye acik olmamali', f;
    end if;
  end loop;
  if not has_function_privilege('service_role',
       'public.saatli_gonderilmez_kullanicilar(uuid[])', 'EXECUTE') then
    raise exception '0188: service_role saatli_gonderilmez_kullanicilar cagiramiyor';
  end if;

  if not exists (
    select 1 from pg_trigger t
     where t.tgrelid = 'public.saatli_bildirimler'::regclass
       and t.tgname = 'saatli_bildirim_denetim'
       and not t.tgisinternal
       and t.tgenabled <> 'D') then
    raise exception '0188: saatli_bildirim_denetim tetikleyicisi yok';
  end if;

  if not exists (select 1 from pg_constraint
                  where conname = 'app_notifications_type_check'
                    and pg_get_constraintdef(oid) like '%saatli_bildirim%'
                    and pg_get_constraintdef(oid) like '%cizim_alarm%'
                    and pg_get_constraintdef(oid) like '%yuzde_alarm%'
                    and pg_get_constraintdef(oid) like '%partner_invite%') then
    raise exception '0188: app_notifications_type_check saatli_bildirim tanimiyor';
  end if;

  if not exists (select 1 from cron.job
                  where jobname = 'saatli-bildirim'
                    and schedule = '*/15 * * * *') then
    raise exception '0188: saatli-bildirim cron isi */15 * * * * ile kurulmali';
  end if;

  raise notice '0188 tamam: saatli_bildirimler + gonderim kaydi + 15 dk cron.';
end $$;
