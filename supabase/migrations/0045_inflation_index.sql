-- 0045_inflation_index.sql
-- ============================================================
-- TÜFE endeksi — reel getiri hesabının veri tabanı.
--
-- ÜRÜN GEREKÇESİ: Türk tasarrufçusunun asıl sorusu "kaç kazandım" değil,
-- "eridim mi?". Yastık altındaki altının sebebi de bu. Rakiplerin hiçbiri
-- (Midas, Foreks, Fintables, Investing TR) reel getiriyi portföy seviyesinde
-- birinci sınıf metrik yapmıyor — nominal getiri gösteriyorlar.
--
-- TABLO BOŞ DOĞAR. Endeks değerleri uydurulamaz: yanlış bir TÜFE, portföy
-- getirisini olduğundan iyi ya da kötü gösterir ve kullanıcı bunu TÜİK'in
-- açıkladığı rakamla karşılaştırdığında uygulamaya olan güvenini kaybeder.
-- Satır yokken uygulama rozeti hiç göstermez (bkz. InflationService).
--
-- Doldurma: TCMB EVDS API'si (TP.FG.J0 serisi) ya da elle giriş.
-- Bkz. YAPMAN_GEREKENLER.md → "TÜFE endeksi".
-- ============================================================

create table if not exists public.inflation_index (
  -- Ayın İLK günü. TÜİK aylık yayımlar; gün alanı sabit tutulur ki
  -- "2026-03" ile "2026-03-15" iki ayrı satır olmasın.
  period      date primary key,
  -- Endeks DEĞERİ saklanır, aylık yüzde değişim değil.
  --
  -- Neden: iki tarih arası enflasyon tek bölmeyle çıkar
  -- (sonEndeks / ilkEndeks - 1). Yüzde saklansaydı aradaki bütün ayları
  -- birbiriyle çarpmak gerekirdi ve her ay bir yuvarlama hatası eklenirdi.
  tufe_index  numeric(12, 4) not null check (tufe_index > 0),
  -- Hangi seriden geldiği — TÜİK zaman zaman baz yılı değiştirir
  -- (ör. 2003=100). Baz değişince seri adı da değişir ve eski satırlarla
  -- yeni satırlar DOĞRUDAN karşılaştırılamaz.
  source      text not null default 'TUIK-TP.FG.J0',
  created_at  timestamptz not null default now()
);

comment on table public.inflation_index is
  'TÜFE endeks değerleri. Reel getiri hesabı için; boşken özellik kapalıdır.';

alter table public.inflation_index enable row level security;

-- Herkes OKUR: bu kamuya açık istatistik, kullanıcıya özel bir veri değil.
-- Kullanıcı bazlı bir satır olmadığı için `using (true)` güvenlidir.
drop policy if exists inflation_index_read on public.inflation_index;
create policy inflation_index_read
  on public.inflation_index for select
  to authenticated
  using (true);

-- YAZMA yalnızca service role'a (RLS'yi baypas eder). İstemciye açılmaz:
-- endeksi değiştirebilen bir kullanıcı kendi reel getirisini istediği gibi
-- gösterebilirdi.
revoke insert, update, delete on public.inflation_index from anon, authenticated;
