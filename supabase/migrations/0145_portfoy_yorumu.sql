-- 0145 — Kişiye özel AI portföy yorumu (2026-10-13)
--
-- ## Neden
-- yasin (12 Eki): "appte ai ile portföy analizi var mı … bunu ayrıca
-- tasarlayalım, yatırım tavsiyesi değildiri belirtelim." Tasarım:
-- https://claude.ai/artifact/DMeJXyFCGt2Ff4vjUgRb6z. Performans › Özet'te
-- GEÇEN HAFTA ve GEÇEN AY için 3–4 maddelik betimleyici yorum; uygulama
-- yüzdeleri hesaplar, `portfoy-yorumla` fonksiyonu Claude'a yazdırır.
--
-- ## Kaydet, yeniden yazma (yasin, 12 Eki 23:09)
-- "Periyodikse sonraki zamana kadar kaydedelim, her seferinde token
-- tüketmeyelim." Yorum kapanmış bir takvim dönemini anlatır; satır o dönem
-- boyunca okunur, model yeniden çağrılmaz. Yalnız portföyün parmak izi
-- (varlıklar + 5 puana yuvarlanmış paylar) değişirse yeni satır yazılabilir.
-- Saklama: kullanıcı başına son 4 hafta + 12 ay (fonksiyon temizler) —
-- Supabase Free 500 MB sınırı yüzünden sınırlı.
--
-- ## Rıza ve kapılar
-- Modele kişinin kendi portföy yüzdeleri gider (tutar/adet/kimlik GİTMEZ);
-- yine de kişiye bağlanabilen veri. Bu yüzden Zirve'deki gibi ayrı açık
-- rıza (`portfoy_yorum_rizalari`), ilk kullanımda istenir. Yasal metindeki
-- F bölümü ve Onay sürümü bu migration'la GELMEZ: bayrak (`portfoy_ai_yorumu`)
-- açılmadan önceki ayrı adımdır (YAPMAN_GEREKENLER) — Onay sürümü artışı
-- bayraktan bağımsız olarak canlıdaki herkese onay ekranı açardı.
-- Sunucu tarafı ikinci kapı: `PORTFOY_YORUM_ACIK` function secret'ı '1'
-- değilse fonksiyon hiçbir şey göndermez.
--
-- ## Eski sürümler
-- Yalnızca EKLER. Eski build'ler bu tablolara ve RPC'ye hiç dokunmaz.

-- ── 1) Rıza ────────────────────────────────────────────────────────────────
-- `profiles` yerine ayrı tablo: gerekçe 0091 (ortak görmesin, ispat saklansın).
create table if not exists public.portfoy_yorum_rizalari (
  user_id         uuid primary key references auth.users(id) on delete cascade,
  verildi_at      timestamptz not null default now(),
  metin_surumu    text not null check (length(metin_surumu) between 1 and 32),
  geri_cekildi_at timestamptz
);

comment on table public.portfoy_yorum_rizalari is
  'AI portfoy yorumu acik riza kaydi (0145). Yalniz portfoy_yorum_rizasi_ayarla '
  'RPC yazar; kullanici yalniz kendi satirini okur.';

alter table public.portfoy_yorum_rizalari enable row level security;
alter table public.portfoy_yorum_rizalari force row level security;

drop policy if exists portfoy_yorum_rizalari_own_select on public.portfoy_yorum_rizalari;
create policy portfoy_yorum_rizalari_own_select
  on public.portfoy_yorum_rizalari
  for select to authenticated
  using ((select auth.uid()) = user_id);

revoke all on table public.portfoy_yorum_rizalari from public, anon, authenticated;
grant select on table public.portfoy_yorum_rizalari to authenticated;
grant select, insert, update, delete on table public.portfoy_yorum_rizalari to service_role;

-- ── 2) Yorumlar ────────────────────────────────────────────────────────────
create table if not exists public.portfoy_yorumlari (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  tur           text not null check (tur in ('haftalik', 'aylik')),
  -- Dönemin ilk ve son günü (haftalık Pzt–Paz, aylık takvim ayı).
  donem         date not null,
  bitis         date not null,
  parmak_izi    text not null check (length(parmak_izi) between 1 and 128),
  durum         text not null check (durum in ('yayinda', 'reddedildi', 'hata')),
  baslik        text,
  maddeler      jsonb not null default '[]'::jsonb,
  -- Kanıt çipleri için gönderilen ölçümler (yalnız yüzde/puan/gün; tutar yok,
  -- fonksiyon reddeder). Kullanıcının kendi satırı.
  olcumler      jsonb not null default '[]'::jsonb,
  model         text not null,
  girdi_token   integer,
  cikti_token   integer,
  maliyet_usd   numeric(10, 5),
  red_nedeni    text,
  olusturuldu   timestamptz not null default now()
);

create index if not exists portfoy_yorumlari_kullanici_donem
  on public.portfoy_yorumlari (user_id, tur, donem desc, olusturuldu desc);
-- Günlük sınır ve aylık tavan sayımı.
create index if not exists portfoy_yorumlari_zaman
  on public.portfoy_yorumlari (olusturuldu);

comment on table public.portfoy_yorumlari is
  'AI portfoy yorumu (0145). Yalniz portfoy-yorumla (service_role) yazar; '
  'kullanici yalniz kendi yayindaki satirlarini okur.';

alter table public.portfoy_yorumlari enable row level security;
alter table public.portfoy_yorumlari force row level security;

-- Yalnız yayındaki satır: reddedilen metin hiç okura gitmez.
drop policy if exists portfoy_yorumlari_own_select on public.portfoy_yorumlari;
create policy portfoy_yorumlari_own_select
  on public.portfoy_yorumlari
  for select to authenticated
  using ((select auth.uid()) = user_id and durum = 'yayinda');

revoke all on table public.portfoy_yorumlari from public, anon, authenticated;
grant select on table public.portfoy_yorumlari to authenticated;
grant select, insert, update, delete on table public.portfoy_yorumlari to service_role;

-- ── 3) RPC: rıza ver / geri çek ────────────────────────────────────────────
-- Geri çekme = yazılmış yorumların silinmesi, aynı işlemde (0091 deseni).
create or replace function public.portfoy_yorum_rizasi_ayarla(p_ver boolean, p_metin_surumu text)
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
    insert into public.portfoy_yorum_rizalari (user_id, verildi_at, metin_surumu, geri_cekildi_at)
    values (v_uid, now(), p_metin_surumu, null)
    on conflict (user_id) do update
      set verildi_at = now(),
          metin_surumu = excluded.metin_surumu,
          geri_cekildi_at = null;
  else
    update public.portfoy_yorum_rizalari
       set geri_cekildi_at = now()
     where user_id = v_uid and geri_cekildi_at is null;
    delete from public.portfoy_yorumlari where user_id = v_uid;
  end if;
end;
$$;
revoke all on function public.portfoy_yorum_rizasi_ayarla(boolean, text) from public, anon;
grant execute on function public.portfoy_yorum_rizasi_ayarla(boolean, text) to authenticated;

-- ── 4) Doğrulama: GRANT ve RLS ayrı şeyler (0036/0042 deseni) ───────────────
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.portfoy_yorumlari'::regclass) then
    raise exception '0145: portfoy_yorumlari RLS kapali';
  end if;
  if not (select relrowsecurity from pg_class where oid = 'public.portfoy_yorum_rizalari'::regclass) then
    raise exception '0145: portfoy_yorum_rizalari RLS kapali';
  end if;
  if has_table_privilege('anon', 'public.portfoy_yorumlari', 'select') then
    raise exception '0145: anon portfoy_yorumlari okuyabiliyor';
  end if;
  if has_table_privilege('authenticated', 'public.portfoy_yorumlari', 'insert') then
    raise exception '0145: authenticated portfoy_yorumlari yazabiliyor';
  end if;
  if has_function_privilege('anon', 'public.portfoy_yorum_rizasi_ayarla(boolean, text)', 'execute') then
    raise exception '0145: anon riza RPC calistirabiliyor';
  end if;
end;
$$;
