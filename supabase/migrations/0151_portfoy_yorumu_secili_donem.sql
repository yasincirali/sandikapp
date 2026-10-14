-- 0151 — AI yorumu: seçili dönem ve varlık detayı (2026-10-14)
--
-- ## Neden
-- yasin (14 Eki): "daha ekonomist gibi ve varlık detayında ve varlıklar
-- bütününde de seçili dönem için data detaylı yorum yapılabilir". 0145 yalnız
-- kapanmış hafta/ay için portföy yorumu yazıyordu. Bu migration iki boyut
-- ekler:
--   · `tur` = 'secili' + `donem_kodu` (1H, 1A, 3A, 6A, 1Y, 5Y): Performans'ta
--     ve varlık detayında seçili dönem, bugünde biten kayan pencere.
--   · `kapsam` = 'portfoy' | 'varlik' (+ `varlik_izi`: pozisyon anahtarının
--     SHA-256 özeti; ham anahtar sunucuya gitmez).
--
-- ## Kaydet, yeniden yazma — gün başına
-- Kayan pencere her gün değişir. 12 Eki kuralı ("her seferinde token
-- tüketmeyelim") burada gün başına uygulanır: aynı kapsam + dönem + bitiş
-- günü + parmak izi için yazılmış yorum o gün boyunca okunur. Seçili dönem
-- yorumları 7 gün saklanır (fonksiyon temizler; Supabase Free 500 MB).
--
-- ## Eski sürümler
-- Yalnızca EKLER. Yeni kolonların varsayılanı eski satırları ve eski
-- istemcinin isteğini olduğu gibi tanımlar (kapsam 'portfoy', dönem kodu ve
-- varlık izi yok). `tur` kısıtı genişler, daralmaz. Eski build'lerin okuduğu
-- kolonlar ve RLS aynı.

alter table public.portfoy_yorumlari
  add column if not exists kapsam text not null default 'portfoy',
  add column if not exists donem_kodu text,
  add column if not exists varlik_izi text;

-- `tur` kısıtını genişlet (0145'teki satır içi kısıtın adı Postgres'in
-- verdiği `portfoy_yorumlari_tur_check`). Adı ne olursa olsun `tur`
-- üzerindeki eski kısıt bulunup düşürülür ki yerel yığın ve iki sunucu
-- aynı sonuca varsın.
do $$
declare
  v_ad text;
begin
  for v_ad in
    select c.conname
      from pg_constraint c
     where c.conrelid = 'public.portfoy_yorumlari'::regclass
       and c.contype = 'c'
       and pg_get_constraintdef(c.oid) ilike '%tur%haftalik%aylik%'
       and pg_get_constraintdef(c.oid) not ilike '%secili%'
  loop
    execute format('alter table public.portfoy_yorumlari drop constraint %I', v_ad);
  end loop;
end;
$$;

alter table public.portfoy_yorumlari
  drop constraint if exists portfoy_yorumlari_tur_check2,
  add constraint portfoy_yorumlari_tur_check2
    check (tur in ('haftalik', 'aylik', 'secili'));

alter table public.portfoy_yorumlari
  drop constraint if exists portfoy_yorumlari_kapsam_check,
  add constraint portfoy_yorumlari_kapsam_check
    check (kapsam in ('portfoy', 'varlik'));

-- Dönem kodu yalnız seçili dönemde; varlık izi yalnız varlık kapsamında.
alter table public.portfoy_yorumlari
  drop constraint if exists portfoy_yorumlari_donem_kodu_check,
  add constraint portfoy_yorumlari_donem_kodu_check
    check (
      (tur = 'secili' and donem_kodu in ('1H', '1A', '3A', '6A', '1Y', '5Y'))
      or (tur <> 'secili' and donem_kodu is null)
    );

alter table public.portfoy_yorumlari
  drop constraint if exists portfoy_yorumlari_varlik_izi_check,
  add constraint portfoy_yorumlari_varlik_izi_check
    check (
      (kapsam = 'varlik' and varlik_izi ~ '^v1:[a-f0-9]{24}$')
      or (kapsam = 'portfoy' and varlik_izi is null)
    );

-- Seçili dönem kaydını bulma (kapsam + varlık + dönem kodu + bitiş günü).
create index if not exists portfoy_yorumlari_secili
  on public.portfoy_yorumlari (user_id, kapsam, varlik_izi, donem_kodu, bitis desc)
  where tur = 'secili';

comment on column public.portfoy_yorumlari.kapsam is
  'portfoy (Performans) ya da varlik (varlik detayi) — 0151.';
comment on column public.portfoy_yorumlari.donem_kodu is
  'Yalniz tur=secili: 1H/1A/3A/6A/1Y/5Y — 0151.';
comment on column public.portfoy_yorumlari.varlik_izi is
  'Yalniz kapsam=varlik: pozisyon anahtarinin SHA-256 ozeti (v1:24 hex) — 0151.';

-- Doğrulama: RLS ve GRANT 0145'teki gibi kalmalı (0036/0042 deseni).
do $$
begin
  if not (select relrowsecurity from pg_class where oid = 'public.portfoy_yorumlari'::regclass) then
    raise exception '0151: portfoy_yorumlari RLS kapali';
  end if;
  if has_table_privilege('anon', 'public.portfoy_yorumlari', 'select') then
    raise exception '0151: anon portfoy_yorumlari okuyabiliyor';
  end if;
  if has_table_privilege('authenticated', 'public.portfoy_yorumlari', 'insert') then
    raise exception '0151: authenticated portfoy_yorumlari yazabiliyor';
  end if;
  if (select count(*) from pg_constraint c
       where c.conrelid = 'public.portfoy_yorumlari'::regclass and c.contype = 'c'
         and pg_get_constraintdef(c.oid) ilike '%tur%haftalik%aylik%'
         and pg_get_constraintdef(c.oid) not ilike '%secili%') > 0 then
    raise exception '0151: eski tur kisiti duruyor';
  end if;
end;
$$;
