-- Takip listesi — sahip OLMADIĞIN varlıkları izleme.
--
-- ## Neden AYRI tablo (assets'e `kind` eklemek yerine)
-- `assets` tablosuna `kind = 'watch'` gibi bir değer eklemek daha az kod gibi
-- görünür ama YANLIŞTIR: o satırlar her aggregate'in, her toplamın, her grafik
-- serisinin yoluna düşer ve her birinde ayrı ayrı elenmeleri gerekir. Bir tek
-- yerde unutulursa portföy toplamı sessizce şişer.
--
-- Bu proje bu hata sınıfını İKİ KEZ yaşadı:
--   · ortak lot'ları tek havuzda toplanıyordu → yanlış kâr/zarar,
--   · tür dökümü ayrı bir veri yolundan besleniyordu → toplamlar tutmuyordu.
-- Ayrı tablo, takip edilen varlığın bir toplama girmesini ŞEMA DÜZEYİNDE
-- imkânsız kılar: `assets`'i sorgulayan hiçbir kod onu göremez.
--
-- ## Miktar/maliyet YOK
-- Takip edilen varlığın miktarı ve alış fiyatı yoktur — sahip değilsin.
-- Bu yüzden `quantity`/`purchase_price` sütunları BİLEREK eklenmedi; boş
-- bırakılan sütunlar zamanla "0 mı, bilinmiyor mu?" belirsizliği üretir.

create table if not exists watchlist (
  id           uuid primary key default gen_random_uuid(),
  user_id      uuid references auth.users(id) on delete cascade not null,
  -- Fiyat çözümü için gereken alanlar. `assets` ile aynı adlandırma:
  -- `resolveSymbol(ticker, type)` iki tarafta da aynı çalışsın.
  ticker       text not null,
  name         text not null,
  type         text not null,
  -- Altın/döviz alt kategorisi (Çeyrek, Gram, USD...). `positionKey` bunu
  -- kullanır; olmadan Gram ve Çeyrek altın aynı satıra düşer.
  sub_category text,
  currency     text not null default 'TRY',
  added_at     timestamptz not null default now()
);

-- Aynı kullanıcı aynı varlığı iki kez takip edemez.
-- Anahtar `positionKey` mantığıyla hizalı: tür + sembol + alt kategori.
-- `coalesce` şart — `sub_category` null olduğunda unique kısıt çalışmaz
-- (SQL'de null'lar birbirine eşit sayılmaz) ve kopya satır oluşurdu.
create unique index if not exists watchlist_user_asset_uidx
  on watchlist(user_id, type, upper(ticker), coalesce(upper(sub_category), ''));

create index if not exists watchlist_user_idx on watchlist(user_id);

alter table watchlist enable row level security;

-- ── RLS ────────────────────────────────────────────────────────────────────
drop policy if exists "watchlist_own_select" on watchlist;
create policy "watchlist_own_select"
  on watchlist for select
  using (auth.uid() = user_id);

drop policy if exists "watchlist_own_insert" on watchlist;
create policy "watchlist_own_insert"
  on watchlist for insert
  with check (auth.uid() = user_id);

drop policy if exists "watchlist_own_delete" on watchlist;
create policy "watchlist_own_delete"
  on watchlist for delete
  using (auth.uid() = user_id);

-- UPDATE politikası YOK: takip kaydının güncellenecek bir alanı yok.
-- Değiştirmek isteyen siler ve yeniden ekler.

-- ── GRANT ──────────────────────────────────────────────────────────────────
-- RLS politikası TEK BAŞINA YETMEZ. Tablo düzeyinde GRANT yoksa
-- `authenticated` rolü satıra hiç ulaşamaz ve sorgu sessizce 0 satır döner.
--
-- Bu projede İKİ KEZ ayrı ayrı unutuldu:
--   0035 → signal_state'e RLS eklendi, sorun sürdü; 0036 → GRANT'mış.
--   0042 → signal_notifications aynı hata; silme çalışmıyordu.
-- Üçüncü kez düşmemek için politikayla AYNI dosyada veriliyor.
grant select, insert, delete on table watchlist to authenticated;

-- ── Doğrulama ──────────────────────────────────────────────────────────────
-- Sessizce eksik kalmasın: migration kendini denetler.
do $$
declare
  grant_sayisi  int;
  policy_sayisi int;
begin
  select count(*) into grant_sayisi
  from information_schema.role_table_grants
  where table_name = 'watchlist'
    and grantee = 'authenticated'
    and privilege_type in ('SELECT', 'INSERT', 'DELETE');

  select count(*) into policy_sayisi
  from pg_policies where tablename = 'watchlist';

  if grant_sayisi <> 3 then
    raise exception 'watchlist GRANT eksik: % / 3 (SELECT+INSERT+DELETE)',
      grant_sayisi;
  end if;
  if policy_sayisi <> 3 then
    raise exception 'watchlist RLS politikasi eksik: % / 3', policy_sayisi;
  end if;
end $$;

comment on table watchlist is
  'Takip listesi: kullanicinin sahip OLMADIGI, yalnizca izledigi varliklar. '
  'assets tablosundan AYRIDIR ve hicbir portfoy toplamina, kar/zarara, tur '
  'dokumune veya grafik serisine girmez. Ayri tablo olmasi bu degismezi sema '
  'duzeyinde garanti eder.';
