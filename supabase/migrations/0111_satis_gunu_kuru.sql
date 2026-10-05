-- 0111 — Dövizli satışta satış günü kuru: assets.sell_fx_rate (2026-10-05)
--
-- ## Neden (kullanıcı onayı 2026-10-05)
-- Satış satırı `purchase_fx_rate`'te ALIM kurunu taşır ve ele geçen tutar
-- da o kurla TL'ye çevriliyordu. 30 TL'den alınıp 41 TL'den satılan dolar
-- varlığın kur kazancı gerçekleşen kâra ve nakit akışına (para ağırlıklı
-- getiri, XIRR) hiç girmiyordu. Maliyet alım kuruyla kalır; yalnız satış
-- tarafı için ayrı kur gerekir.
--
-- ## Eski sürümler
-- Yalnızca EKLER: boş geçilebilir yeni sütun, varsayılan yok. Eski build'ler
-- sütunu hiç yazmaz (NULL → istemci alım kuruna düşer, eski hesap) ve
-- `select *` ile okusalar da tanımadıkları anahtarı yok sayar. Yeni istemci
-- sütunu YALNIZ Remote Config `satis_gunu_kuru` açıkken ve değer doluyken
-- yazar (`Asset.toSupabase`); bayrak bu migration iki sunucuya ulaşmadan
-- açılmamalı, yoksa PostgREST satışı reddeder (PGRST204).
--
-- ## Yetki
-- Yeni tablo/RPC yok. Sütun `assets`'in mevcut RLS politikaları ve
-- GRANT'leri altında: satır sahibi yazar/okur, ortak okuma politikası aynen.
-- Geçmiş satırlar DOLDURULMAZ: satış günü kuru bilinmiyor, uydurulmaz.

alter table public.assets
  add column if not exists sell_fx_rate numeric
  check (sell_fx_rate is null or sell_fx_rate > 0);

comment on column public.assets.sell_fx_rate is
  'Satis gunu kuru (1 doviz = ? TL), yalniz dovizli sell satirlarinda (0111). NULL: alim kuru (purchase_fx_rate) kullanilir.';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'assets'
       and column_name = 'sell_fx_rate' and is_nullable = 'YES'
  ) then
    raise exception '0111: assets.sell_fx_rate kurulmadi';
  end if;
  raise notice '0111 tamam: assets.sell_fx_rate (bos gecilebilir) yerinde.';
end $$;
