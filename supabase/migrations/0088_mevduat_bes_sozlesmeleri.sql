-- 0088 — Vadeli mevduat ve BES: sözleşme tabloları (2026-09-30)
--
-- ## Neden (kullanıcı kararı 2026-09-30, seçenek M2 + B3)
-- Mevduat 2026-09-14'te silinmişti (0058). Sebep veri modeli değil bakım
-- yüküydü: ayrı bir faiz motoru ve fiyat/sinyal/tarihçe motorlarının her
-- birinde "mevduat hariç" dalları. Yeni tasarım o dersi şemaya yazar:
--
--   · BAKİYE `assets` lot defterinde kalır (alım = para yatırma, satım =
--     çekim). Toplamlar, dağılım, kâr/zarar, ortak görünümü, yarış
--     değerlemesi mevcut lot yolundan çalışır; hiçbirine tür dalı eklenmez.
--   · SÖZLEŞME (faiz, vade, BES katkı planı) ayrı tablolardadır. Lot
--     `sozlesme_id` ile bağlanır. Sözleşme fiyatlamanın GİRDİSİDİR, bakiye
--     değildir: mevduatın birim değeri dönemlerden hesaplanır
--     (`lib/services/mevduat_hesabi.dart`), BES lotları TEFAS emeklilik
--     fonu (EMK) fiyatından fiyatlanır.
--
-- ## Neden jsonb değil ayrı dönem tablosu (mevduat)
-- Yenileme zinciri büyür (32 günlük vade yılda 11 kez yenilenir) ve her
-- dönemin kendi faizi, stopajı, vadesi vardır. Satır başına dönem:
-- `unique (sozlesme_id, baslangic)` çift kaydı engeller, yenileme tek
-- INSERT'tür (jsonb'de oku-değiştir-yaz yarışı olurdu).
--
-- ## Neden jsonb (BES fon dağılımı)
-- Dağılım bir TALİMATTIR ("katkımın %60'ı AH5'e"), tarihçesi tutulmaz ve
-- hep bütün olarak değişir. Asıl varlık (hangi fonda kaç pay) lotlardadır.

-- ── 1) Sözleşme ────────────────────────────────────────────────────────────
create table if not exists public.sozlesmeler (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid not null default auth.uid()
               references auth.users(id) on delete cascade,
  tur          text not null check (tur in ('mevduat', 'bes')),
  -- Banka ya da emeklilik şirketi — kullanıcının yazdığı ad.
  kurum        text not null check (char_length(btrim(kurum)) between 1 and 80),
  -- Mevduat: ilk dönemin başı. BES: sisteme giriş tarihi — devlet katkısı
  -- hak ediş oranı (%0/15/35/60) buradan geçen yıla bağlıdır.
  baslangic    date not null,
  -- v1 yalnız TL: döviz mevduatının değeri kurdan gelir ve kullanıcı onu
  -- Döviz varlığı olarak zaten izliyor (çalışma, seçenek M4).
  para_birimi  text not null default 'TRY' check (para_birimi = 'TRY'),

  -- BES alanları. Mevduatta hepsi NULL (aşağıdaki kısıt).
  aylik_katki  numeric(14, 2) check (aylik_katki is null or aylik_katki > 0),
  katki_gunu   smallint check (katki_gunu is null or katki_gunu between 1 and 28),
  -- [{"kod":"AH5","oran":60}, ...] — oranlar toplamı 100 (istemci doğrular;
  -- burada yalnız biçim: dizi, en çok 10 fon).
  fon_dagilimi jsonb check (
    fon_dagilimi is null or (
      jsonb_typeof(fon_dagilimi) = 'array'
      and jsonb_array_length(fon_dagilimi) between 1 and 10
    )
  ),
  -- Devlet katkısının yatırıldığı fon (TEFAS EMK kodu). Bilinmiyorsa NULL:
  -- devlet katkısı lotu yazılmaz, uydurma fiyatla değerlenmez.
  dk_fon_kodu  text check (dk_fon_kodu is null or dk_fon_kodu ~ '^[A-Z0-9]{3}$'),

  -- Sözleşme kapandıysa (mevduat çekildi, BES'ten ayrıldı) tarihi.
  kapandi      date,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now(),

  constraint sozlesmeler_bes_alanlari check (
    tur = 'bes'
    or (aylik_katki is null and katki_gunu is null
        and fon_dagilimi is null and dk_fon_kodu is null)
  ),
  constraint sozlesmeler_kapanis check (kapandi is null or kapandi >= baslangic),
  -- Bileşik FK hedefi: dönem ve lot, sözleşmeye ANCAK aynı kullanıcıyla
  -- bağlanabilsin (aşağıda). FK denetimi RLS'e tabi değildir; tek başına
  -- `sozlesme_id` FK'si başkasının sözleşme id'sine bağlanmaya izin verirdi.
  constraint sozlesmeler_id_user_uq unique (id, user_id)
);

create index if not exists sozlesmeler_user_idx on public.sozlesmeler(user_id);

-- ── 2) Mevduat dönemleri (yenileme zinciri) ────────────────────────────────
create table if not exists public.mevduat_donemleri (
  id           uuid primary key default gen_random_uuid(),
  sozlesme_id  uuid not null,
  user_id      uuid not null default auth.uid(),
  baslangic    date not null,
  -- NULL = vadesiz / günlük faizli hesap (seçenek M3): günlük bileşik
  -- tahakkuk, vade bildirimi yok.
  vade_sonu    date,
  -- Yıllık BRÜT faiz, yüzde (42.5 = %42,5).
  yillik_faiz  numeric(7, 4) not null check (yillik_faiz > 0 and yillik_faiz < 500),
  -- Stopaj yüzdesi. İstemci açılış tarihine ve vadeye göre tarihli
  -- tablodan önerir (10041 sayılı karar, 2025-07-09: %17,5 / %15 / %10);
  -- kullanıcı düzeltebilir. Dönem satırında SAKLANIR: oran kararla
  -- değişince eski dönemlerin getirisi geriye dönük değişmesin.
  stopaj       numeric(5, 2) not null check (stopaj >= 0 and stopaj <= 100),
  created_at   timestamptz not null default now(),

  constraint mevduat_donemleri_vade check (vade_sonu is null or vade_sonu > baslangic),
  constraint mevduat_donemleri_tekil unique (sozlesme_id, baslangic),
  constraint mevduat_donemleri_sozlesme_fk foreign key (sozlesme_id, user_id)
    references public.sozlesmeler(id, user_id) on delete cascade
);

create index if not exists mevduat_donemleri_user_idx
  on public.mevduat_donemleri(user_id);

-- ── 3) Lot → sözleşme bağı ─────────────────────────────────────────────────
alter table public.assets add column if not exists sozlesme_id uuid;

-- `on delete set null (sozlesme_id)`: PG15+ sütun listesi. Düz `set null`
-- bileşik FK'nin İKİ sütununu da boşaltır ve `user_id not null` patlardı.
-- Lot defteri sözleşme silinince SİLİNMEZ (hareket geçmişi korunur).
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'assets_sozlesme_fk') then
    alter table public.assets
      add constraint assets_sozlesme_fk foreign key (sozlesme_id, user_id)
      references public.sozlesmeler(id, user_id)
      on delete set null (sozlesme_id);
  end if;
end $$;

create index if not exists assets_sozlesme_idx
  on public.assets(sozlesme_id) where sozlesme_id is not null;

-- ── 4) updated_at ──────────────────────────────────────────────────────────
create or replace function public.sozlesmeler_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists sozlesmeler_updated_at on public.sozlesmeler;
create trigger sozlesmeler_updated_at
  before update on public.sozlesmeler
  for each row execute function public.sozlesmeler_updated_at();

-- ── 5) RLS ─────────────────────────────────────────────────────────────────
-- Sahip her şeyi yapar; ortak yalnız OKUR (assets_partner_read ile aynı
-- kural). Ortak okuması şart: ortağın mevduat lotunu değerlemek için onun
-- dönemleri gerekir, yoksa ortak görünümünde mevduat son yazılan fiyatta
-- donar.
alter table public.sozlesmeler       enable row level security;
alter table public.mevduat_donemleri enable row level security;
alter table public.sozlesmeler       force row level security;
alter table public.mevduat_donemleri force row level security;

drop policy if exists "sozlesmeler_own" on public.sozlesmeler;
create policy "sozlesmeler_own" on public.sozlesmeler
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "sozlesmeler_partner_read" on public.sozlesmeler;
create policy "sozlesmeler_partner_read" on public.sozlesmeler
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = user_id))
    )
  );

drop policy if exists "mevduat_donemleri_own" on public.mevduat_donemleri;
create policy "mevduat_donemleri_own" on public.mevduat_donemleri
  for all using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

drop policy if exists "mevduat_donemleri_partner_read" on public.mevduat_donemleri;
create policy "mevduat_donemleri_partner_read" on public.mevduat_donemleri
  for select using (
    exists (
      select 1 from public.partnerships p
      where p.active = true
        and ((p.user_id_1 = auth.uid() and p.user_id_2 = user_id)
          or (p.user_id_2 = auth.uid() and p.user_id_1 = user_id))
    )
  );

-- ── 6) GRANT ───────────────────────────────────────────────────────────────
-- RLS ile GRANT ayrı şeylerdir (0036/0042/0043): GRANT yoksa sorgu sessizce
-- 0 satır döner. anon hiçbir şey göremez.
revoke all on table public.sozlesmeler       from anon;
revoke all on table public.mevduat_donemleri from anon;
grant select, insert, update, delete on table public.sozlesmeler       to authenticated;
grant select, insert, update, delete on table public.mevduat_donemleri to authenticated;

-- ── 7) Doğrulama ───────────────────────────────────────────────────────────
do $$
declare
  g_soz int;
  g_don int;
  p_soz int;
  p_don int;
begin
  select count(*) into g_soz from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'sozlesmeler'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  select count(*) into g_don from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'mevduat_donemleri'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  select count(*) into p_soz from pg_policies
   where schemaname = 'public' and tablename = 'sozlesmeler';
  select count(*) into p_don from pg_policies
   where schemaname = 'public' and tablename = 'mevduat_donemleri';

  if g_soz <> 4 then
    raise exception '0088: sozlesmeler GRANT eksik: % / 4', g_soz;
  end if;
  if g_don <> 4 then
    raise exception '0088: mevduat_donemleri GRANT eksik: % / 4', g_don;
  end if;
  if p_soz <> 2 then
    raise exception '0088: sozlesmeler RLS politikasi eksik: % / 2', p_soz;
  end if;
  if p_don <> 2 then
    raise exception '0088: mevduat_donemleri RLS politikasi eksik: % / 2', p_don;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'assets_sozlesme_fk') then
    raise exception '0088: assets_sozlesme_fk yok';
  end if;
end $$;

comment on table public.sozlesmeler is
  'Mevduat/BES sozlesmesi: fiyatlamanin GIRDISI (faiz, vade, katki plani). '
  'Bakiye assets lot defterindedir (sozlesme_id ile bagli). 0088.';
comment on table public.mevduat_donemleri is
  'Mevduat yenileme zinciri: her donem kendi faizi, stopaji ve vadesiyle. '
  'Birim deger istemcide bu satirlardan hesaplanir (mevduat_hesabi.dart).';
