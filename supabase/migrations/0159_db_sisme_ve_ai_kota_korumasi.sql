-- 0159 — Veritabanı şişme koruması: db_logs tavanı, eski anlık görüntüler
--        günlüğe iner, yeni politikalar initplan biçimine; AI kotası için
--        atomik hız kapısı; ekstre şablonu hata sayımı kişi başına (2026-10-20)
--
-- Kullanıcı isteği (2026-10-20, iyileştirme raporu): "db'yi şişirmeyecek
-- değişiklikleri de ekle". Free plan 500 MB; dolunca proje HERKES için salt
-- okunura düşer (2026-10-05'te Tokyo 342 MB'ı görmüştü, 0112–0114).
--
-- Eklemeli: tablo/kolon/RPC kaldırılmaz, istemci değişmez. Eski sürümler
-- etkilenmez: `DbLogger` ekleme hatasını zaten yutuyor, tetikleyici de hata
-- fırlatmıyor (sessizce atlıyor).
--
-- ## 1) db_logs: satır boyutu ve saatlik tavan
-- `db_logs_insert` politikası yalnız `user_id`'ye bakıyordu; jsonb kolonları
-- sınırsızdı. Oturum açmış tek bir hesap döngüyle büyük satır yazıp tabloyu
-- (ve projeyi) doldurabilirdi (denetim L6, 2026-09-23'ten açık).
-- * request_json / response_json 4 KB'ı aşarsa yerine `{"kirpildi": true,
--   "bayt": n}` yazılır. Gerçek hata özetleri ~200 bayt (`_summarize`,
--   `_sanitizeMessage`); teşhis için kayıp yok.
-- * Kullanıcı başına saatte 300 satırdan sonrası atlanır (`return null`, hata
--   değil). Yayın build'i yalnız hata yazar; saatte 300 hata zaten bir
--   arızadır ve ilk 300 satır onu anlatır. Debug build'in 30 sn'lik nabzı
--   saatte ~120 satır yazar, tavanın altında kalır.
-- * Sayım (user_id, ts desc) indeksini kullanır (0000 `db_logs_user_ts_idx`).
--
-- ## 2) snapshots: 35 günden eskisi günde bir nokta
-- 0077 saatte bir noktaya indirmişti; 730 gün saklamayla etkin kullanıcı
-- başına ~17.500 satır demek. Okuyanlar (Yıllık Özet `recap_screen`,
-- `weekly-summary`, performans ilk/son değeri) pencerenin İLK ve SON değerini
-- kullanır; 35 günden eski pencerelerde günlük nokta yeter. Her (kullanıcı,
-- UTC günü) için SON satır kalır → kullanıcı başına ~35×24 + 695 ≈ 1.500
-- satır. Saklama süresi (730 gün) DEĞİŞMEZ; yasal metne dokunmaz.
-- `weekly-summary` tüm kullanıcıların bir yıllık serisini tek sorguda
-- çektiği için satır sayısı orada da doğrudan zaman/limit baskısıydı.
--
-- ## 3) Politikalar: çıplak auth.uid() yeniden sarılır
-- 0077 tüm politikaları `(select auth.uid())` biçimine almıştı; sonraki
-- migration'lar (0088, 0126, 0133, 0135) yine çıplak çağrı ekledi. Aynı
-- döngü tekrar koşar (idempotent; anlam değişmez, yalnız değerlendirme
-- sayısı — satır başına değil sorgu başına bir kez).
--
-- ## 4) AI istekleri: atomik hız kapısı
-- `portfoy-yorumla` ve `ekstre-esle` önce bugünkü satırları sayıyor, sonra
-- modeli çağırıp en son yazıyordu: aynı anda gelen N istek sayımı birlikte
-- geçer, hepsi model çağırır. `ai_hiz_kapisi` kullanıcı+kapsam başına
-- danışma kilidi alıp penceredeki denemeyi sayar ve yazar — tek işlemde,
-- yarışsız. 0028'in `rate_limit_attempts` tablosunu ve saatlik temizliğini
-- (24 saat) kullanır; yeni tablo yok. Fonksiyonlar modelden ÖNCE çağırır.
--
-- ## 5) Ekstre şablonu: hata sayımı kullanıcı başına bir kez
-- Şablonlar tüm kullanıcılar için ortak. İstemcinin `sablonsuz: true`
-- bildirimi `hata`'yı artırıyordu ve 3'te şablon kapanıyordu: tek bir
-- kullanıcı üç çağrıyla bir bankanın şablonunu herkes için kapatıp herkesi
-- ücretli model yoluna düşürebilirdi. Artık her (şablon, kullanıcı) çifti
-- bir kez sayılır; kapatmak için üç FARKLI kullanıcının reddi gerekir.
-- Eski `ekstre_sablon_say` duruyor (başarı sayacı onu kullanmaya devam eder).
--
-- ## Boyut notu (0112/0114 ile aynı)
-- DELETE yeri diske hemen geri vermez; ilk temizlikten sonra bir kez
-- `vacuum full public.snapshots;` (YAPMAN_GEREKENLER.md).

-- ── 1) db_logs ──────────────────────────────────────────────────────────────
create or replace function public.db_logs_tavan()
returns trigger
language plpgsql
-- INVOKER: sayım çağıranın RLS'iyle (db_logs_select_own) yalnız kendi
-- satırlarını görür. search_path sabit (CLAUDE.md kuralı).
set search_path = public
as $$
declare
  boyut int;
  son_saat int;
begin
  if new.request_json is not null then
    boyut := pg_column_size(new.request_json);
    if boyut > 4096 then
      new.request_json := jsonb_build_object('kirpildi', true, 'bayt', boyut);
    end if;
  end if;
  if new.response_json is not null then
    boyut := pg_column_size(new.response_json);
    if boyut > 4096 then
      new.response_json := jsonb_build_object('kirpildi', true, 'bayt', boyut);
    end if;
  end if;
  -- Kaynak/tablo adları serbest metin: uzun metin satırı şişirmesin.
  new.source := left(new.source, 200);
  new.table_name := left(new.table_name, 100);
  new.op := left(new.op, 40);
  new.sdk := left(new.sdk, 100);

  if new.user_id is not null then
    select count(*) into son_saat
      from public.db_logs
     where user_id = new.user_id
       and ts > now() - interval '1 hour';
    if son_saat >= 300 then
      return null;  -- sessizce atla: istemci hata görmez
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists db_logs_tavan on public.db_logs;
create trigger db_logs_tavan
  before insert on public.db_logs
  for each row execute function public.db_logs_tavan();

-- ── 2) snapshots: eski veriyi günlüğe indir ─────────────────────────────────
create or replace function public.snapshots_gunluge_indir()
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.snapshots s
   using (
     select id, row_number() over (
              partition by user_id, date_trunc('day', ts at time zone 'UTC')
              order by ts desc, id desc) as sira
       from public.snapshots
      where ts < now() - interval '35 days'
   ) d
   where s.id = d.id and d.sira > 1;
$$;

revoke all on function public.snapshots_gunluge_indir() from public, anon, authenticated;
grant execute on function public.snapshots_gunluge_indir() to service_role;

-- İlk temizlik şimdi; sonrası her gece (snapshots-retention 03:25'ten sonra).
select public.snapshots_gunluge_indir();

select cron.unschedule(jobid) from cron.job where jobname = 'snapshots-gunluk';
select cron.schedule('snapshots-gunluk', '35 3 * * *',
  $$select public.snapshots_gunluge_indir()$$);

-- ── 3) Politikalar: initplan ────────────────────────────────────────────────
do $$
declare
  p record;
  yeni_qual text;
  yeni_check text;
  sql text;
  sayi int := 0;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
      from pg_policies
     where schemaname = 'public'
       and (coalesce(qual, '') ~ '(?<!SELECT )auth\.uid\(\)'
         or coalesce(with_check, '') ~ '(?<!SELECT )auth\.uid\(\)')
  loop
    yeni_qual := regexp_replace(p.qual, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    yeni_check := regexp_replace(p.with_check, '(?<!SELECT )auth\.uid\(\)', '(select auth.uid())', 'g');
    sql := format('alter policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
    if yeni_qual is not null then sql := sql || format(' using (%s)', yeni_qual); end if;
    if yeni_check is not null then sql := sql || format(' with check (%s)', yeni_check); end if;
    execute sql;
    sayi := sayi + 1;
  end loop;
  raise notice '0159: % politika initplan biçimine alındı.', sayi;
end;
$$;

-- ── 4) AI hız kapısı ────────────────────────────────────────────────────────
create or replace function public.ai_hiz_kapisi(
  p_subject text,
  p_scope text,
  p_max integer,
  p_pencere_sn integer
)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  sayi integer;
begin
  p_max := greatest(1, least(coalesce(p_max, 1), 1000));
  p_pencere_sn := greatest(1, least(coalesce(p_pencere_sn, 60), 86400));
  -- Aynı kullanıcı+kapsamın eşzamanlı istekleri burada sıraya girer.
  perform pg_advisory_xact_lock(hashtextextended(p_subject || '|' || p_scope, 0));
  select count(*) into sayi
    from public.rate_limit_attempts
   where subject = p_subject
     and scope = p_scope
     and attempted_at >= now() - make_interval(secs => p_pencere_sn);
  if sayi >= p_max then
    return false;
  end if;
  insert into public.rate_limit_attempts (subject, scope) values (p_subject, p_scope);
  return true;
end;
$$;

revoke all on function public.ai_hiz_kapisi(text, text, integer, integer) from public, anon, authenticated;
grant execute on function public.ai_hiz_kapisi(text, text, integer, integer) to service_role;

-- ── 5) Ekstre şablonu hata bildirimi ────────────────────────────────────────
create table if not exists public.ekstre_sablon_hata_bildirimleri (
  iz         text not null references public.ekstre_sablonlari(iz) on delete cascade,
  user_id    uuid not null references auth.users(id) on delete cascade,
  bildirildi timestamptz not null default now(),
  primary key (iz, user_id)
);

alter table public.ekstre_sablon_hata_bildirimleri enable row level security;
-- Politika YOK (0147 ekstre_sablonlari gibi): yalnız service_role.
revoke all on table public.ekstre_sablon_hata_bildirimleri from public, anon, authenticated;
grant select, insert, delete on table public.ekstre_sablon_hata_bildirimleri to service_role;

create or replace function public.ekstre_sablon_hata_bildir(p_izler text[], p_user_id uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  with yeni as (
    insert into public.ekstre_sablon_hata_bildirimleri (iz, user_id)
    select distinct i, p_user_id
      from unnest(p_izler) as i
     where exists (select 1 from public.ekstre_sablonlari s where s.iz = i)
    on conflict do nothing
    returning iz
  )
  update public.ekstre_sablonlari s
     set hata = s.hata + 1,
         son_kullanim = now()
    from yeni
   where s.iz = yeni.iz;
$$;

revoke all on function public.ekstre_sablon_hata_bildir(text[], uuid) from public, anon, authenticated;
grant execute on function public.ekstre_sablon_hata_bildir(text[], uuid) to service_role;

-- ── Kendini doğrulama ───────────────────────────────────────────────────────
do $$
declare
  ciplak int;
begin
  if not exists (select 1 from pg_trigger where tgname = 'db_logs_tavan'
                   and tgrelid = 'public.db_logs'::regclass) then
    raise exception '0159: db_logs_tavan tetikleyicisi kurulmadı';
  end if;
  if has_function_privilege('anon', 'public.snapshots_gunluge_indir()', 'execute')
     or has_function_privilege('authenticated', 'public.snapshots_gunluge_indir()', 'execute') then
    raise exception '0159: snapshots_gunluge_indir istemciye açık kaldı';
  end if;
  if not exists (select 1 from cron.job where jobname = 'snapshots-gunluk') then
    raise exception '0159: snapshots-gunluk cron işi kurulmadı';
  end if;
  if has_function_privilege('authenticated', 'public.ai_hiz_kapisi(text, text, integer, integer)', 'execute')
     or has_function_privilege('authenticated', 'public.ekstre_sablon_hata_bildir(text[], uuid)', 'execute') then
    raise exception '0159: AI kota/şablon fonksiyonu istemciye açık kaldı';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.ekstre_sablon_hata_bildirimleri'::regclass) then
    raise exception '0159: ekstre_sablon_hata_bildirimleri RLS kapalı';
  end if;
  select count(*) into ciplak from pg_policies
   where schemaname = 'public'
     and (coalesce(qual, '') || coalesce(with_check, '')) ~ '(?<!SELECT )auth\.uid\(\)';
  if ciplak > 0 then
    raise exception '0159: % politika hâlâ çıplak auth.uid() taşıyor', ciplak;
  end if;
end;
$$;
