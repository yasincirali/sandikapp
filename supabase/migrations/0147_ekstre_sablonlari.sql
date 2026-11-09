-- 0147 — Ekstre banka şablonu hafızası (2026-10-13)
--
-- ## Neden
-- yasin (2026-10-13): "direkt okutmak pahalı gözüküyor", "banka şablonları
-- da değişebilir", sonra "bahsettiğimiz şekilde geliştirmeyi yap".
-- `ekstre-esle` modelin bir tablo için verdiği sütun eşlemesini başlık
-- satırının izine bağlayıp burada saklar; aynı başlıklı tablo bir daha
-- geldiğinde model çağrılmaz (maliyet dosya başına değil düzen başına).
-- Kurallar ve iz tanımı: `supabase/functions/_shared/ekstre_esleme.ts`
-- "Banka şablonu hafızası".
--
-- ## Kişisel veri
-- `iz` başlık satırının SHA-256 özetidir, metni değil. `roller` yalnız
-- sütun numaralarıdır. Kullanıcıya bağlı hiçbir kolon yok: şablon bir
-- kurumun tablo düzenidir, kimin yüklediği tutulmaz.
--
-- ## Değişen tasarım
-- Yeni düzen yeni iz demektir, ayrı satır olur; eskisi silinmez. İz tutup
-- değerler tutmazsa cihaz şablonu reddeder, fonksiyon `hata`yı artırır ve
-- modelin yeni eşlemesini aynı satıra yazar (`hata` sıfırlanır).
-- `hata >= 3` olan şablon kullanılmaz.
--
-- ## Eski sürümler
-- Yalnızca EKLER. Eski build'ler v1 iskelet yollar; v1 bu tabloya hiç
-- dokunmaz.
--
-- ## Rıza (yasin 2026-10-13: "herkese peşinen değil de işlemi talep
-- ettiklerinde sorsak nasıl olur")
-- Metin yolunda tablodaki kelimeler Anthropic'e gider. Genel "Onay sürümü"
-- artırılıp herkese onay ekranı açılmaz; rıza yalnız işlemi isteyen
-- kullanıcıdan, ilk "Yapay zekâyla eşle"de alınır (`ekstre_ai_rizalari`,
-- 0145 `portfoy_yorum_rizalari` deseni). Fonksiyon rızası olmayanın metnini
-- işlemez (403 `riza`). Geri çekmede silinecek kişisel kayıt yok: şablonlar
-- kullanıcıya bağlı değil, sayaç satırları 40 günde düşer.
--
-- ## Yetki
-- Şablon: yalnız service_role (fonksiyon). İstemci tabloya ve sayaca dokunmaz —
-- herkese açık bir yazma yolu başkalarının şablonunu bozabilirdi.

create table if not exists public.ekstre_sablonlari (
  iz            text primary key check (iz ~ '^[0-9a-f]{64}$'),
  roller        jsonb not null,
  sutun_sayisi  integer not null check (sutun_sayisi between 1 and 200),
  model         text not null,
  olusturuldu   timestamptz not null default now(),
  guncellendi   timestamptz not null default now(),
  kullanim      integer not null default 0,
  hata          integer not null default 0,
  son_kullanim  timestamptz
);

alter table public.ekstre_sablonlari enable row level security;
-- Politika YOK: authenticated/anon için RLS her satırı gizler; GRANT da yok.

revoke all on table public.ekstre_sablonlari from public, anon, authenticated;
grant select, insert, update, delete on table public.ekstre_sablonlari to service_role;

-- Sayaç: kullanılan şablonların `kullanim`/`hata`sı tek ifadede artar
-- (fonksiyonda oku-yaz yarışı olmasın).
create or replace function public.ekstre_sablon_say(p_izler text[], p_hata boolean)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  update public.ekstre_sablonlari
     set kullanim = kullanim + case when p_hata then 0 else 1 end,
         hata = hata + case when p_hata then 1 else 0 end,
         son_kullanim = now()
   where iz = any(p_izler);
$$;

revoke all on function public.ekstre_sablon_say(text[], boolean) from public, anon, authenticated;
grant execute on function public.ekstre_sablon_say(text[], boolean) to service_role;

-- ── Rıza ──────────────────────────────────────────────────────────────────
create table if not exists public.ekstre_ai_rizalari (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  verildi_at      timestamptz not null default now(),
  metin_surumu    text not null check (length(metin_surumu) between 1 and 32),
  geri_cekildi_at timestamptz
);
comment on table public.ekstre_ai_rizalari is
  'Ekstre AI metin yolu acik riza kaydi (0147). Yalniz ekstre_ai_rizasi_ayarla '
  'RPC yazar; kullanici yalniz kendi satirini okur.';

alter table public.ekstre_ai_rizalari enable row level security;
alter table public.ekstre_ai_rizalari force row level security;
drop policy if exists ekstre_ai_rizalari_own_select on public.ekstre_ai_rizalari;
create policy ekstre_ai_rizalari_own_select
  on public.ekstre_ai_rizalari
  for select to authenticated
  using ((select auth.uid()) = user_id);
revoke all on table public.ekstre_ai_rizalari from public, anon, authenticated;
grant select on table public.ekstre_ai_rizalari to authenticated;
grant select, insert, update, delete on table public.ekstre_ai_rizalari to service_role;

create or replace function public.ekstre_ai_rizasi_ayarla(p_ver boolean, p_metin_surumu text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
begin
  if v_uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  if p_ver then
    if p_metin_surumu is null or length(p_metin_surumu) not between 1 and 32 then
      raise exception 'gecersiz metin surumu' using errcode = '22023';
    end if;
    insert into public.ekstre_ai_rizalari (user_id, verildi_at, metin_surumu, geri_cekildi_at)
    values (v_uid, now(), p_metin_surumu, null)
    on conflict (user_id) do update
      set verildi_at = now(),
          metin_surumu = excluded.metin_surumu,
          geri_cekildi_at = null;
  else
    update public.ekstre_ai_rizalari
       set geri_cekildi_at = now()
     where user_id = v_uid and geri_cekildi_at is null;
  end if;
end;
$$;
revoke all on function public.ekstre_ai_rizasi_ayarla(boolean, text) from public, anon;
grant execute on function public.ekstre_ai_rizasi_ayarla(boolean, text) to authenticated;

do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.ekstre_ai_rizalari'::regclass) then
    raise exception '0147: ekstre_ai_rizalari RLS kapali';
  end if;
  if has_table_privilege('authenticated', 'public.ekstre_ai_rizalari', 'INSERT')
     or has_table_privilege('anon', 'public.ekstre_ai_rizalari', 'SELECT') then
    raise exception '0147: ekstre_ai_rizalari istemciye yazilabilir olmamali';
  end if;
  if has_function_privilege('anon', 'public.ekstre_ai_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0147: anon riza RPC calistirabiliyor';
  end if;
  if has_table_privilege('authenticated', 'public.ekstre_sablonlari', 'SELECT')
     or has_table_privilege('authenticated', 'public.ekstre_sablonlari', 'INSERT')
     or has_table_privilege('anon', 'public.ekstre_sablonlari', 'SELECT') then
    raise exception '0147: ekstre_sablonlari istemciye kapali olmali';
  end if;
  if not (select relrowsecurity from pg_class
           where oid = 'public.ekstre_sablonlari'::regclass) then
    raise exception '0147: ekstre_sablonlari RLS acik olmali';
  end if;
  if has_function_privilege('authenticated', 'public.ekstre_sablon_say(text[], boolean)', 'EXECUTE')
     or has_function_privilege('anon', 'public.ekstre_sablon_say(text[], boolean)', 'EXECUTE') then
    raise exception '0147: ekstre_sablon_say istemciye kapali olmali';
  end if;
end $$;
