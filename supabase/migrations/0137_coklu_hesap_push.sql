-- 0137 — Çoklu hesap: aynı cihazdaki PASİF hesapların bildirimleri
--         (bayrak `coklu_hesap`, istemci 2026-10-10).
--
-- Kullanıcı isteği (yasin, 2026-10-10): "hesap ekleme ve aralarında session
-- switch, instagramdaki gibi; tüm fazları yap". Faz 1 yalnız istemcidir
-- (oturumlar cihaz kasasında, geçişte yer değiştirir). Faz 2 bu dosya:
-- telefonda açık duran ama o an seçili OLMAYAN hesap da bildirim alır,
-- başlığında hesap adıyla.
--
-- ## Neden ayrı tablo (user_push_tokens'ın anahtarı DEĞİŞMEDİ)
-- `user_push_tokens` birincil anahtarı `token` (0078); `claim_push_token`
-- (0069) ve `push_token_devral` tetikleyicisi bir token'ı TEK hesaba
-- devreder. Bu kurala yayındaki her sürüm ve on edge function dayanıyor;
-- anahtarı (token, user_id) yapmak eski sürümde devralmayı bozar ve
-- "canlıdaki kullanıcı etkilenmez" kuralını çiğner. Bunun yerine YALNIZ
-- EKLENEN bir tablo: `push_ek_hesaplar` = "bu token'ın cihazında şu hesap
-- da açık". Birincil satır her zaman aktif hesabındır (bugünkü gibi);
-- ek satır yalnız yeni istemcinin RPC'siyle yazılır. Eski sürüm bu tabloyu
-- hiç görmez, hiçbir davranışı değişmez.
--
-- ## Ek satır ne zaman geçerli (gönderen fonksiyon `push_ek_hesap_hedefleri`)
-- 1) Token hâlâ yaşıyor: aynı token `user_push_tokens`'ta BAŞKA bir hesapla
--    duruyor (cihazın aktif hesabı). FCM token'ı öldürünce gönderenler
--    birincil satırı siler (`shouldDeleteToken`); ek satır o an kendiliğinden
--    geçersizleşir — ayrıca silme yolu gerekmez.
-- 2) Aynı hesabın aynı token'da birincil satırı YOK (aktifken çift bildirim
--    olmasın; istemci aktifleşince ek satırını da siler, bu ikinci emniyet).
-- 3) Tek aktif cihaz kuralı (0098): hesap şu an BU cihazda aktif
--    (`aktif_cihaz.cihaz_id` = satırın `cihaz_id`'si) ya da muaf. Hesap başka
--    telefonda açılınca bu cihazdaki oturumu düşer; ek satır da o an susar.
--    Yoksa eski telefon başkasının bildirimlerini almaya devam ederdi.
--
-- Hesap silinince satırlar `on delete cascade` ile gider. Kişisel veri
-- kategorisi yeni değil (push token zaten işleniyor, aynı amaçla); yasal
-- metin değişmez — gerekçe PR özetinde.

-- ── 1) Tablo ────────────────────────────────────────────────────────────────
create table if not exists public.push_ek_hesaplar (
  token           text        not null check (length(token) between 20 and 4096),
  user_id         uuid        not null references auth.users(id) on delete cascade,
  cihaz_id        text        not null check (cihaz_id ~ '^[0-9a-f]{32}$'),
  platform        text        not null default 'unknown'
                              check (platform in ('android', 'ios', 'unknown')),
  device_id       text,
  bildirim_surumu integer,
  updated_at      timestamptz not null default now(),
  primary key (token, user_id)
);

comment on table public.push_ek_hesaplar is
  'Coklu hesap (0137): token''in cihazinda acik duran PASIF hesaplar. '
  'Birincil sahip user_push_tokens''tadir; burasi yalniz ek alicidir. '
  'Yalniz ek_hesap_push_bagla / ek_hesap_push_coz RPC yazar.';

create index if not exists push_ek_hesaplar_user_idx
  on public.push_ek_hesaplar (user_id);

alter table public.push_ek_hesaplar enable row level security;
alter table public.push_ek_hesaplar force row level security;
-- İstemci tabloya doğrudan dokunmaz (politika yok); RPC'ler SECURITY DEFINER.
revoke all on table public.push_ek_hesaplar from public, anon, authenticated;
grant select, insert, update, delete on table public.push_ek_hesaplar to service_role;

-- ── 2) RPC: ek_hesap_push_bagla ─────────────────────────────────────────────
-- Çağıran hesap (auth.uid) bu token'ın cihazında PASİF olarak kalacak.
-- İstemci hesaptan AYRILMADAN hemen önce, hâlâ o hesabın oturumuyla çağırır.
-- Token başına en çok 5 ek hesap (istemci sınırıyla aynı): kötü niyetli bir
-- istemci başkasının token'ına sınırsız hesap bağlayıp bildirim yağdıramaz;
-- zaten başkasının token'ını bilmesi gerekir ve bildirim o cihaza gider,
-- çağırana değil.
create or replace function public.ek_hesap_push_bagla(
  p_token           text,
  p_platform        text,
  p_cihaz_id        text,
  p_device_id       text    default null,
  p_bildirim_surumu integer default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_sayi integer;
begin
  if v_uid is null then
    raise exception 'ek_hesap_push_bagla: oturum yok' using errcode = '42501';
  end if;
  if p_token is null or length(p_token) < 20 or length(p_token) > 4096 then
    raise exception 'ek_hesap_push_bagla: gecersiz token' using errcode = '22023';
  end if;
  if p_platform is null or p_platform not in ('android', 'ios', 'unknown') then
    raise exception 'ek_hesap_push_bagla: gecersiz platform' using errcode = '22023';
  end if;
  if p_cihaz_id is null or p_cihaz_id !~ '^[0-9a-f]{32}$' then
    raise exception 'ek_hesap_push_bagla: gecersiz cihaz' using errcode = '22023';
  end if;

  select count(*) into v_sayi
    from public.push_ek_hesaplar
   where token = p_token and user_id <> v_uid;
  if v_sayi >= 5 then
    raise exception 'ek_hesap_push_bagla: sinir' using errcode = '54000';
  end if;

  -- Aynı hesabın aynı cihazdaki ESKİ token'ları (FCM rotasyonu) düşer.
  delete from public.push_ek_hesaplar
   where user_id = v_uid and cihaz_id = p_cihaz_id and token <> p_token;

  insert into public.push_ek_hesaplar
    (token, user_id, cihaz_id, platform, device_id, bildirim_surumu, updated_at)
  values
    (p_token, v_uid, p_cihaz_id, p_platform, nullif(p_device_id, ''),
     p_bildirim_surumu, now())
  on conflict (token, user_id) do update
    set cihaz_id        = excluded.cihaz_id,
        platform        = excluded.platform,
        device_id       = coalesce(excluded.device_id, push_ek_hesaplar.device_id),
        bildirim_surumu = coalesce(excluded.bildirim_surumu, push_ek_hesaplar.bildirim_surumu),
        updated_at      = now();
end;
$$;

comment on function public.ek_hesap_push_bagla(text, text, text, text, integer) is
  'Coklu hesap (0137): cagiran hesap bu token''in cihazinda pasif kalir ve '
  'bildirimlerini hesap adiyla almaya devam eder.';

revoke all on function public.ek_hesap_push_bagla(text, text, text, text, integer)
  from public, anon;
grant execute on function public.ek_hesap_push_bagla(text, text, text, text, integer)
  to authenticated;

-- ── 3) RPC: ek_hesap_push_coz ───────────────────────────────────────────────
-- Hesap bu cihazda AKTİF olunca (birincil satırı claim_push_token yazar) ya
-- da cihazdan çıkılınca çağrılır. `p_token` null → hesabın bütün ek
-- satırları (ör. "tüm hesaplardan çık" sırasında token bilinmiyorsa).
create or replace function public.ek_hesap_push_coz(p_token text default null)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'ek_hesap_push_coz: oturum yok' using errcode = '42501';
  end if;
  delete from public.push_ek_hesaplar
   where user_id = v_uid
     and (p_token is null or token = p_token);
end;
$$;

revoke all on function public.ek_hesap_push_coz(text) from public, anon;
grant execute on function public.ek_hesap_push_coz(text) to authenticated;

-- ── 4) Gönderenlerin okuduğu fonksiyon ──────────────────────────────────────
-- Edge function'lar (service_role) hedef kullanıcıların EK satırlarını
-- buradan alır; geçerlilik kuralları (başlıktaki 1–3) tek yerde. `hesap_etiketi`
-- bildirim başlığının önüne yazılır: kullanıcı adı, yoksa görünen ad.
-- `p_user_ids` null → bütün geçerli ek satırlar (hedefi geniş fonksiyonlar).
create or replace function public.push_ek_hesap_hedefleri(p_user_ids uuid[] default null)
returns table (
  token           text,
  user_id         uuid,
  device_id       text,
  platform        text,
  updated_at      timestamptz,
  bildirim_surumu integer,
  hesap_etiketi   text
)
language sql
stable
security definer
set search_path = public
as $$
  select e.token, e.user_id, e.device_id, e.platform, e.updated_at,
         e.bildirim_surumu,
         coalesce(nullif(p.username, ''), nullif(p.display_name, ''), 'sandık')
    from public.push_ek_hesaplar e
    left join public.profiles p on p.id = e.user_id
   where (p_user_ids is null or e.user_id = any (p_user_ids))
     -- 1) token yaşıyor ve cihazın aktif hesabı başkası
     and exists (select 1 from public.user_push_tokens t
                  where t.token = e.token and t.user_id <> e.user_id)
     -- 2) aynı hesabın bu token'da birincil satırı yok
     and not exists (select 1 from public.user_push_tokens t
                      where t.token = e.token and t.user_id = e.user_id)
     -- 3) tek aktif cihaz: hesap hâlâ bu cihazda (ya da muaf)
     and (
       exists (select 1 from public.cihaz_kontrol_muafiyeti m
                where m.user_id = e.user_id)
       or exists (select 1 from public.aktif_cihaz a
                   where a.user_id = e.user_id and a.cihaz_id = e.cihaz_id)
     );
$$;

comment on function public.push_ek_hesap_hedefleri(uuid[]) is
  'Coklu hesap (0137): gonderen edge function''larin pasif hesap alicilari. '
  'Gecerlilik: token yasiyor, hesap aktif degil, tek aktif cihaz kurali.';

revoke all on function public.push_ek_hesap_hedefleri(uuid[]) from public, anon, authenticated;
grant execute on function public.push_ek_hesap_hedefleri(uuid[]) to service_role;

-- ── 5) Doğrulama — GRANT ve RLS ayrı katmanlar, sessizce eksik kalmasın ─────
do $$
begin
  if not has_function_privilege('authenticated',
       'public.ek_hesap_push_bagla(text, text, text, text, integer)', 'execute') then
    raise exception '0137: ek_hesap_push_bagla authenticated EXECUTE yok';
  end if;
  if has_function_privilege('anon',
       'public.ek_hesap_push_bagla(text, text, text, text, integer)', 'execute') then
    raise exception '0137: ek_hesap_push_bagla anon EXECUTE olmamali';
  end if;
  if not has_function_privilege('authenticated', 'public.ek_hesap_push_coz(text)', 'execute') then
    raise exception '0137: ek_hesap_push_coz authenticated EXECUTE yok';
  end if;
  if has_function_privilege('anon', 'public.ek_hesap_push_coz(text)', 'execute') then
    raise exception '0137: ek_hesap_push_coz anon EXECUTE olmamali';
  end if;
  if has_function_privilege('authenticated', 'public.push_ek_hesap_hedefleri(uuid[])', 'execute') then
    raise exception '0137: push_ek_hesap_hedefleri istemciye acik olmamali';
  end if;
  if has_table_privilege('authenticated', 'public.push_ek_hesaplar', 'select')
     or has_table_privilege('anon', 'public.push_ek_hesaplar', 'select') then
    raise exception '0137: push_ek_hesaplar istemciye acik olmamali';
  end if;
  if not exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'public' and c.relname = 'push_ek_hesaplar'
                    and c.relrowsecurity and c.relforcerowsecurity) then
    raise exception '0137: push_ek_hesaplar RLS zorunlu degil';
  end if;
  if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public'
                and p.proname in ('ek_hesap_push_bagla', 'ek_hesap_push_coz',
                                  'push_ek_hesap_hedefleri')
                and not p.prosecdef) then
    raise exception '0137: RPC security definer degil';
  end if;
end $$;
