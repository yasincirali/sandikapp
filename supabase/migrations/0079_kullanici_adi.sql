-- 0079 — Kullanıcı adı: benzersiz, uygunsuz söz filtreli, ortakta görünen ad
-- (2026-09-28, yasin)
--
-- Kullanıcı kararı: "Apple veya Google ile kaydolduğunda bir username alanı
-- isteyelim, müşterinin ortağında ve kendinde gözükecek ismidir. Proddaki
-- müşteriler için de bu alan güncelleme sonrası ilk loginde must olarak
-- istenmeli ve ayarlardan da değiştirilebilir ve unique olmalıdır, küfür
-- kötü söz vs gibi amacını aşan şeyler olmamalıdır."
--
-- Tasarım kararları:
--   · Ayrı kolon (`username`), ama GÖRÜNEN AD onun kopyasıdır: kullanıcı adı
--     seçildiği anda `display_name` ona eşitlenir (tetikleyici). Ortak adı,
--     brifing push'u, davet kodu yanıtı, lider tablosu… hepsi zaten
--     `display_name` okuyor; tek tek dokunmak yerine kaynak tek yerde
--     eşitlenir. İstemcinin `upsertProfile` ile gönderdiği `display_name`
--     de kullanıcı adı varsa ezilir — filtre arkadan dolanılamaz.
--   · `username IS NULL` = "henüz seçilmedi". İstemci bunu görünce zorunlu
--     ekranı açar (mevcut kullanıcılar dahil). Toplu doldurma YOK: eski
--     görünen adlar benzersiz değil ve filtreden geçmemiş olabilir.
--   · Kural SUNUCUDADIR (tek kaynak). İstemci yalnızca biçimi anında
--     gösterir; uygunluk/benzersizlik kararı `kullanici_adi_denetle`.
--   · Benzersizlik büyük/küçük harf ve i/ı/İ/I farkına duyarsız:
--     "Yasin", "yasin", "YASİN", "yasın" aynı ad sayılır (taklit önlemi).
--   · Biçim: 3–20 karakter; Türkçe/İngilizce harf, rakam, "." ve "_";
--     harfle başlar, ayraçla bitmez, iki ayraç yan yana gelmez. Boşluk yok.
--     Başka alfabeler bilinçli dışarıda: benzer görünen harflerle (Kiril
--     "а") başkasının adını taklit etmek kapanır.
--   · Uygunsuz söz filtresi en iyi çabadır: leetspeak (0→o, 1→i, 3→e…),
--     araya ayraç koyma ("o.r.o.s.p.u") ve harf uzatma ("siiiktir")
--     yakalanır. Kısa ve masum sözcüklerin içinde geçen kökler ("sik" ⊂
--     "ışık", "am" ⊂ "ahmet") yalnızca TAM parça olarak eşleşir.
--     Liste tablodadır; genişletmek yeni bir migration'la satır eklemektir
--     (iki sunucu birebir kuralı).

-- ── 1) Kolon ───────────────────────────────────────────────────────────────
alter table public.profiles add column if not exists username text;

-- ── 2) Yasaklı / ayrılmış sözcükler ────────────────────────────────────────
create table if not exists public.kullanici_adi_yasakli (
  kelime   text primary key,
  tur      text not null check (tur in ('uygunsuz', 'ayrilmis')),
  eslesme  text not null check (eslesme in ('icerir', 'tam'))
);
-- İstemci okumaz: listeyi yaymak, onu dolanmayı kolaylaştırır.
alter table public.kullanici_adi_yasakli enable row level security;
revoke all on table public.kullanici_adi_yasakli from anon, authenticated;

insert into public.kullanici_adi_yasakli (kelime, tur, eslesme) values
  -- Türkçe — uzun, masum sözcük içinde geçmeyen kökler
  ('orospu', 'uygunsuz', 'icerir'), ('orspu', 'uygunsuz', 'icerir'),
  ('amcik', 'uygunsuz', 'icerir'), ('aminako', 'uygunsuz', 'icerir'),
  -- "amina" değil: Amina bir ad.
  ('yarrak', 'uygunsuz', 'icerir'),
  ('dalyarak', 'uygunsuz', 'icerir'), ('siktir', 'uygunsuz', 'icerir'),
  ('sikis', 'uygunsuz', 'icerir'), ('sikik', 'uygunsuz', 'icerir'),
  ('sikim', 'uygunsuz', 'icerir'), ('siker', 'uygunsuz', 'icerir'),
  ('sikey', 'uygunsuz', 'icerir'), ('sikic', 'uygunsuz', 'icerir'),
  ('pezevenk', 'uygunsuz', 'icerir'), ('kahpe', 'uygunsuz', 'icerir'),
  ('gavat', 'uygunsuz', 'icerir'), ('kaltak', 'uygunsuz', 'icerir'),
  ('surtuk', 'uygunsuz', 'icerir'), ('yavsak', 'uygunsuz', 'icerir'),
  ('ibne', 'uygunsuz', 'icerir'), ('kancik', 'uygunsuz', 'icerir'),
  ('gerizekali', 'uygunsuz', 'icerir'), ('serefsiz', 'uygunsuz', 'icerir'),
  ('gotveren', 'uygunsuz', 'icerir'), ('gotlek', 'uygunsuz', 'icerir'),
  ('pust', 'uygunsuz', 'tam'),
  -- Türkçe — kısa kökler: yalnız tam parça ("ışık", "ahmet" korunur)
  ('sik', 'uygunsuz', 'tam'), ('got', 'uygunsuz', 'tam'),
  ('am', 'uygunsuz', 'tam'), ('amk', 'uygunsuz', 'tam'),
  ('aq', 'uygunsuz', 'tam'), ('mk', 'uygunsuz', 'tam'),
  ('oc', 'uygunsuz', 'tam'), ('pic', 'uygunsuz', 'tam'),
  ('seks', 'uygunsuz', 'tam'),
  -- İngilizce
  ('fuck', 'uygunsuz', 'icerir'), ('shit', 'uygunsuz', 'icerir'),
  ('bitch', 'uygunsuz', 'icerir'), ('cunt', 'uygunsuz', 'icerir'),
  ('pussy', 'uygunsuz', 'icerir'), ('asshole', 'uygunsuz', 'icerir'),
  ('whore', 'uygunsuz', 'icerir'), ('porn', 'uygunsuz', 'icerir'),
  ('penis', 'uygunsuz', 'icerir'), ('vagina', 'uygunsuz', 'icerir'),
  ('slut', 'uygunsuz', 'icerir'), ('hitler', 'uygunsuz', 'icerir'),
  ('nigger', 'uygunsuz', 'tam'), ('nigga', 'uygunsuz', 'tam'),
  ('dick', 'uygunsuz', 'tam'), ('cock', 'uygunsuz', 'tam'),
  ('fag', 'uygunsuz', 'tam'), ('sex', 'uygunsuz', 'tam'),
  ('anal', 'uygunsuz', 'tam'), ('rape', 'uygunsuz', 'tam'),
  ('ass', 'uygunsuz', 'tam'),
  -- Ayrılmış: resmi hesap / sistem sanılabilecek adlar
  ('sandik', 'ayrilmis', 'icerir'), ('admin', 'ayrilmis', 'icerir'),
  ('destek', 'ayrilmis', 'tam'), ('support', 'ayrilmis', 'tam'),
  ('yonetici', 'ayrilmis', 'tam'), ('moderator', 'ayrilmis', 'tam'),
  ('root', 'ayrilmis', 'tam'), ('sistem', 'ayrilmis', 'tam'),
  ('system', 'ayrilmis', 'tam'), ('resmi', 'ayrilmis', 'tam'),
  ('official', 'ayrilmis', 'tam'), ('ortak', 'ayrilmis', 'tam'),
  ('kullanici', 'ayrilmis', 'tam'), ('user', 'ayrilmis', 'tam'),
  ('null', 'ayrilmis', 'tam'), ('undefined', 'ayrilmis', 'tam'),
  ('anonim', 'ayrilmis', 'tam'), ('anonymous', 'ayrilmis', 'tam')
on conflict (kelime) do nothing;

-- ── 3) Yardımcılar ─────────────────────────────────────────────────────────

-- Benzersizlik anahtarı. `lower()` C yerelinde yalnız ASCII'yi küçültür;
-- Türkçe büyük harfler önce elle çevrilir, i/ı/İ/I tek harfe iner.
create or replace function public.kullanici_adi_anahtari(p text)
returns text
language sql
immutable
parallel safe
as $$
  select lower(translate(p, 'İIıÇĞÖŞÜ', 'iiiçğöşü'));
$$;

-- Filtre için sade biçim: ASCII, leetspeak çözülmüş. Ayraçlar KORUNUR
-- (parçalara bölmek için); `kullanici_adi_denetle` onları ayrıca atar.
create or replace function public.kullanici_adi_sade(p text)
returns text
language sql
immutable
parallel safe
as $$
  select translate(public.kullanici_adi_anahtari(p),
                   'çğıöşü0134578', 'cgiosuoieastb');
$$;

-- Harf uzatmayı söndürür: "siiiktir" → "siktir".
create or replace function public.kullanici_adi_sikistir(p text)
returns text
language sql
immutable
parallel safe
as $$
  select regexp_replace(p, '(.)\1+', '\1', 'g');
$$;

-- Tek karar noktası. Dönüş: 'ok' | 'bicim' | 'uygunsuz' | 'ayrilmis' |
-- 'alinmis'. SECURITY DEFINER: yasaklı tablo ve başkalarının adları
-- istemciye kapalı; yalnız sonuç kodu döner.
create or replace function public.kullanici_adi_denetle(p_ad text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  ad text := btrim(coalesce(p_ad, ''));
  sade text;
  duz text;
  parcalar text[];
  y record;
begin
  if ad !~ '^[A-Za-zÇĞİÖŞÜçğıöşü][A-Za-z0-9ÇĞİÖŞÜçğıöşü._]{2,19}$'
     or ad ~ '[._]{2}'
     or ad ~ '[._]$' then
    return 'bicim';
  end if;

  sade := kullanici_adi_sade(ad);
  -- Ayraçsız, yalnız harf: "o.r.o.s.p.u" ve "s1kt1r" burada yakalanır.
  duz := regexp_replace(sade, '[^a-z]', '', 'g');
  -- Parçalar: "yasin_sik" → {yasin, sik}; rakam kuyruğu atılır ("sik69").
  select coalesce(array_agg(t), '{}') into parcalar
    from (select regexp_replace(x, '[^a-z]', '', 'g') as t
            from regexp_split_to_table(sade, '[._]') x) s
   where t <> '';

  for y in select kelime, tur, eslesme from kullanici_adi_yasakli loop
    if (y.eslesme = 'icerir'
          and (strpos(duz, y.kelime) > 0
               or strpos(kullanici_adi_sikistir(duz),
                         kullanici_adi_sikistir(y.kelime)) > 0))
       or (y.eslesme = 'tam'
          and (duz = y.kelime
               or y.kelime = any(parcalar)
               -- Uzatılmış kısa kök ("siiik"). Sıkıştırınca değişen kök
               -- ("nigger" → "niger") bu yoldan eşleşmez: ülke adı düşerdi.
               or (kullanici_adi_sikistir(y.kelime) = y.kelime
                   and y.kelime = any(select kullanici_adi_sikistir(u)
                                        from unnest(parcalar) u))))
    then
      return y.tur;
    end if;
  end loop;

  if exists (select 1 from profiles
              where username is not null
                and kullanici_adi_anahtari(username) = kullanici_adi_anahtari(ad)
                and id is distinct from auth.uid()) then
    return 'alinmis';
  end if;

  return 'ok';
end;
$$;

-- ── 4) Benzersizlik ────────────────────────────────────────────────────────
create unique index if not exists profiles_username_anahtar_uidx
  on public.profiles (public.kullanici_adi_anahtari(username))
  where username is not null;

-- ── 5) Tetikleyici: kural her yazımda, görünen ad = kullanıcı adı ─────────
--
-- RPC'yi atlayıp `profiles`'a doğrudan yazan istemci (RLS
-- `profiles_update_own` buna izin verir) de aynı kuraldan geçer. Seçilmiş
-- ad geri NULL'a çekilemez — zorunlu ekran bir daha açılmasın, ortak adsız
-- kalmasın.
create or replace function public.profiles_kullanici_adi_bi()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  kod text;
begin
  if tg_op = 'UPDATE' and old.username is not null and new.username is null then
    new.username := old.username;
  end if;

  if new.username is not null
     and (tg_op = 'INSERT' or new.username is distinct from old.username) then
    new.username := btrim(new.username);
    kod := kullanici_adi_denetle(new.username);
    -- 'alinmis'i burada değil indeks söyler (yarış durumunda da doğru).
    if kod not in ('ok', 'alinmis') then
      raise exception 'kullanici_adi:%', kod using errcode = '22023';
    end if;
  end if;

  if new.username is not null then
    new.display_name := new.username;
  end if;
  return new;
end;
$$;

drop trigger if exists profiles_kullanici_adi_bi on public.profiles;
create trigger profiles_kullanici_adi_bi
  before insert or update on public.profiles
  for each row execute function public.profiles_kullanici_adi_bi();

-- ── 6) RPC'ler ─────────────────────────────────────────────────────────────

-- Yazarken anlık geri bildirim. Oturumsuz çağrı reddedilir (ad
-- taraması kayıt ekranından anonim yapılamasın).
create or replace function public.kullanici_adi_uygun_mu(p_ad text)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'oturum gerekli' using errcode = '42501';
  end if;
  return kullanici_adi_denetle(p_ad);
end;
$$;

-- Kaydet. Hata kodu istisna değil DÖNÜŞ değeridir: istemci kodu
-- kullanıcı diline çevirir, ham hata metni göstermez.
create or replace function public.kullanici_adi_ayarla(p_ad text)
returns text
language plpgsql
volatile
security definer
set search_path = public
as $$
declare
  uid uuid := auth.uid();
  ad text := btrim(coalesce(p_ad, ''));
  kod text;
begin
  if uid is null then
    raise exception 'oturum gerekli' using errcode = '42501';
  end if;
  kod := kullanici_adi_denetle(ad);
  if kod <> 'ok' then
    return kod;
  end if;
  begin
    update profiles set username = ad where id = uid;
  exception when unique_violation then
    return 'alinmis';
  end;
  if not found then
    return 'profil_yok';
  end if;
  return 'ok';
end;
$$;

-- ── 7) GRANT ───────────────────────────────────────────────────────────────
-- Postgres fonksiyonlara varsayılan olarak PUBLIC'e EXECUTE verir; iç
-- yardımcılar ve denetleyici istemciye kapatılır, yalnız iki RPC açılır.
revoke all on function public.kullanici_adi_denetle(text) from public, anon, authenticated;
revoke all on function public.profiles_kullanici_adi_bi() from public, anon, authenticated;
revoke all on function public.kullanici_adi_uygun_mu(text) from public, anon;
revoke all on function public.kullanici_adi_ayarla(text) from public, anon;
grant execute on function public.kullanici_adi_uygun_mu(text) to authenticated;
grant execute on function public.kullanici_adi_ayarla(text) to authenticated;

-- ── 8) Doğrulama ───────────────────────────────────────────────────────────
do $$
begin
  if not has_function_privilege('authenticated', 'public.kullanici_adi_ayarla(text)', 'execute')
     or not has_function_privilege('authenticated', 'public.kullanici_adi_uygun_mu(text)', 'execute') then
    raise exception '0079: kullanıcı adı RPC GRANT eksik';
  end if;
  if has_function_privilege('anon', 'public.kullanici_adi_ayarla(text)', 'execute')
     or has_function_privilege('authenticated', 'public.kullanici_adi_denetle(text)', 'execute') then
    raise exception '0079: kullanıcı adı RPC fazla açık';
  end if;
  if not exists (select 1 from pg_trigger
                  where tgname = 'profiles_kullanici_adi_bi' and not tgisinternal) then
    raise exception '0079: profiles_kullanici_adi_bi tetikleyicisi yok';
  end if;
  -- Filtrenin kendisi: masumlar geçer, yakalanması gerekenler yakalanır.
  if public.kullanici_adi_denetle('isik') <> 'ok'
     or public.kullanici_adi_denetle('Ahmet_1990') <> 'ok'
     or public.kullanici_adi_denetle('o.r.o.s.p.u') <> 'uygunsuz'
     or public.kullanici_adi_denetle('s1ktir') <> 'uygunsuz'
     or public.kullanici_adi_denetle('yasin_sik') <> 'uygunsuz'
     or public.kullanici_adi_denetle('SandikDestek') <> 'ayrilmis'
     or public.kullanici_adi_denetle('ab') <> 'bicim'
     or public.kullanici_adi_denetle('ali veli') <> 'bicim' then
    raise exception '0079: kullanıcı adı filtresi öz-denetimi başarısız';
  end if;
end;
$$;

comment on column public.profiles.username is
  'Kullanıcı adı (0079): benzersiz (kullanici_adi_anahtari), filtreli; '
  'NULL = henüz seçilmedi, istemci zorunlu ekran açar. display_name buna eşitlenir.';
