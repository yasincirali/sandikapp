-- 0078 — Tokyo ile Frankfurt şemasını birebir eşitle (2026-09-28)
--
-- Kullanıcı kuralı: "iki sunucu hep senkron, birebir aynı gitmeli".
-- `tool/sema_esitlik.py` (parmak izi: supabase/audit/sema_parmak_izi.sql)
-- iki projeyi karşılaştırınca migration defteri aynı olduğu hâlde şemanın
-- AYRIŞTIĞI görüldü. Sebep: Tokyo yıllar içinde elle/SQL Editor'la
-- evrildi; `0000_base_schema.sql` sonradan yazılmış bir TAHMİNDİ ve
-- Frankfurt ondan kuruldu. Tokyo canlı gerçeklik olduğu için her maddede
-- hedef TOKYO'NUN hâlidir — bir istisna dışında (1: Frankfurt'taki hata).
--
-- Her adım idempotent ve koşullu: Tokyo'da çoğu no-op'tur.

-- ── 1) profiles_select_partner — Frankfurt'ta ortak profili GÖRÜNMÜYORDU ──
--
-- 0000'daki gövde alt sorguda nitelenmemiş `id` kullanıyor:
--   where (p.user_id_1 = auth.uid() and p.user_id_2 = id)
-- `partnerships`'in de `id` kolonu var; Postgres en içteki kapsamı seçer →
-- `p.id` (ortaklık satırının kimliği). Koşul hiç tutmaz, ortak adı/profili
-- okunamaz. Tokyo'daki politika elle `profiles.id` ile yazılmıştı. Açık
-- niteleme ile iki projede aynı ve doğru gövde. auth.uid() initplan
-- biçiminde (0077).
drop policy if exists "profiles_select_partner" on public.profiles;
create policy "profiles_select_partner" on public.profiles
  for select using (
    exists (
      select 1 from public.partnerships p
      where (p.user_id_1 = (select auth.uid()) and p.user_id_2 = profiles.id)
         or (p.user_id_2 = (select auth.uid()) and p.user_id_1 = profiles.id)
    )
  );

-- ── 2) user_push_tokens — Tokyo biçimi: PK = token ──────────────────────────
--
-- Tokyo: (token PK, user_id, platform default 'unknown', updated_at,
-- device_id). 0000 ise (id uuid PK, token unique, created_at) kurdu.
-- Push token'ı cihaza bağlıdır, doğal anahtarı token'dır; 0069'daki
-- devralma (claim_push_token) da bunu varsayar. `id` / `created_at`
-- uygulamada ve edge function'larda hiç okunmuyor (grep, 2026-09-28).
-- Frankfurt'taki satırlar geçişte Tokyo'dan yeniden kopyalanır; kolon
-- kaybı pilot kopyadan ibaret.
do $$
begin
  if exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'user_push_tokens'
               and column_name = 'id') then
    alter table public.user_push_tokens drop constraint if exists user_push_tokens_pkey;
    alter table public.user_push_tokens drop column id;
    alter table public.user_push_tokens drop constraint if exists user_push_tokens_token_key;
    alter table public.user_push_tokens add constraint user_push_tokens_pkey primary key (token);
  end if;
end;
$$;
alter table public.user_push_tokens drop column if exists created_at;
alter table public.user_push_tokens alter column platform set default 'unknown';

-- ── 3) disclaimer_acceptances — tekil kısıtın adı ───────────────────────────
--
-- Anlam aynı (user_id, disclaimer_version); yalnız ad farklı. Ad, upsert
-- `on_conflict` hata mesajlarında ve karşılaştırıcıda görünür.
do $$
begin
  if exists (select 1 from pg_constraint
             where conrelid = 'public.disclaimer_acceptances'::regclass
               and conname = 'disclaimer_acceptances_user_id_disclaimer_version_key')
     and not exists (select 1 from pg_constraint
             where conrelid = 'public.disclaimer_acceptances'::regclass
               and conname = 'disclaimer_acceptances_user_version_unique') then
    alter table public.disclaimer_acceptances
      rename constraint disclaimer_acceptances_user_id_disclaimer_version_key
      to disclaimer_acceptances_user_version_unique;
  end if;
end;
$$;

-- ── 4) Yeni tabloda RLS otomatik açık (Tokyo'da panelden açılmıştı) ─────────
--
-- Supabase panelinin "yeni tablolarda RLS'yi otomatik etkinleştir" ayarı
-- Tokyo'da `rls_auto_enable()` + `ensure_rls` event trigger'ını kurmuş;
-- Frankfurt'ta yok. Güvenlik ağıdır: migration'da RLS satırı unutulan yeni
-- bir tablo herkese açık doğmaz. Gövde Tokyo'dakinin birebir kopyası.
create or replace function public.rls_auto_enable()
 returns event_trigger
 language plpgsql
 security definer
 set search_path to 'pg_catalog'
as $function$
DECLARE
  cmd record;
BEGIN
  FOR cmd IN
    SELECT *
    FROM pg_event_trigger_ddl_commands()
    WHERE command_tag IN ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      AND object_type IN ('table','partitioned table')
  LOOP
     IF cmd.schema_name IS NOT NULL AND cmd.schema_name IN ('public') AND cmd.schema_name NOT IN ('pg_catalog','information_schema') AND cmd.schema_name NOT LIKE 'pg_toast%' AND cmd.schema_name NOT LIKE 'pg_temp%' THEN
      BEGIN
        EXECUTE format('alter table if exists %s enable row level security', cmd.object_identity);
        RAISE LOG 'rls_auto_enable: enabled RLS on %', cmd.object_identity;
      EXCEPTION
        WHEN OTHERS THEN
          RAISE LOG 'rls_auto_enable: failed to enable RLS on %', cmd.object_identity;
      END;
     ELSE
        RAISE LOG 'rls_auto_enable: skip % (either system schema or not in enforced list: %.)', cmd.object_identity, cmd.schema_name;
     END IF;
  END LOOP;
END;
$function$;

do $$
begin
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    create event trigger ensure_rls on ddl_command_end
      when tag in ('CREATE TABLE', 'CREATE TABLE AS', 'SELECT INTO')
      execute function public.rls_auto_enable();
  end if;
end;
$$;

-- ── Kendini doğrula ─────────────────────────────────────────────────────────
do $$
begin
  if exists (select 1 from pg_policies
             where schemaname = 'public' and tablename = 'profiles'
               and policyname = 'profiles_select_partner'
               and qual ~ 'p\.id\M') then
    raise exception '0078: profiles_select_partner hâlâ p.id''ye bakıyor';
  end if;
  if (select array_agg(a.attname::text order by a.attname::text)
      from pg_index i
      join pg_attribute a on a.attrelid = i.indrelid and a.attnum = any(i.indkey)
      where i.indrelid = 'public.user_push_tokens'::regclass and i.indisprimary)
     is distinct from array['token'] then
    raise exception '0078: user_push_tokens birincil anahtarı token değil';
  end if;
  if not exists (select 1 from pg_event_trigger where evtname = 'ensure_rls') then
    raise exception '0078: ensure_rls event trigger kurulamadı';
  end if;
  raise notice '0078 tamam: iki sunucu şeması eşitlendi.';
end;
$$;
