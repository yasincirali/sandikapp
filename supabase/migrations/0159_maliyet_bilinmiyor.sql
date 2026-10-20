-- 0159 — Alış fiyatı bilinmeyen lot işareti: assets.maliyet_bilinmiyor (2026-10-20)
--
-- ## Neden (yasin onayı 2026-10-20, Ar-Ge raporu 13:15 #1 + 17:15 #3)
-- Ekran görüntüsünden/toplu eklemede maliyeti okunamayan satır sepette
-- "maliyet sonra" diye işaretleniyor, kayıtta ise işaret kayboluyordu:
-- lot o günün fiyatıyla yazılıyor, kâr/zarar sıfır görünüyor ve kullanıcı
-- maliyeti girmeyi unutuyor. Ana ekrandaki "N varlıkta bilgi eksik" satırı
-- ve Portföy'deki "Alış fiyatı eksik" etiketi bu işaretten okur.
--
-- ## Neden sunucuda (yerel liste değil)
-- Yerel tercih telefon değişince kaybolur, iki cihazda tutarsız olur; lotun
-- kendi bilgisi lotun satırında durur.
--
-- ## Eski sürümler
-- Yalnızca EKLER: boş geçilebilir sütun, varsayılan yok. Eski build'ler
-- sütunu hiç yazmaz (NULL = bilinmiyor değil, "işaret yok") ve `select *`
-- ile okusalar da tanımadıkları anahtarı yok sayar. Yeni istemci anahtarı
-- YALNIZ değer doluyken yazar (`Asset.toSupabase`): `true` yalnız maliyeti
-- okunamayan yeni lotta, `false` yalnız kullanıcı o lotun maliyetini
-- girince. Bu migration canlıya ulaşmadan yayınlanan build'de INSERT
-- PGRST204 alırsa istemci anahtarsız yeniden dener (`SupabaseService`
-- `_sutunsuzYenidenDene`): kayıt düşmez, yalnız işaret kalıcı olmaz.
--
-- ## Yetki
-- Yeni tablo/RPC yok. Sütun `assets`'in mevcut RLS politikaları ve
-- GRANT'leri altında: satır sahibi yazar/okur, ortak okuma politikası aynen.
-- Geçmiş satırlar DOLDURULMAZ: hangi eski lotun maliyetinin tahmin olduğu
-- bilinmiyor, uydurulmaz.

alter table public.assets
  add column if not exists maliyet_bilinmiyor boolean;

comment on column public.assets.maliyet_bilinmiyor is
  'Alis fiyati okunamadan kaydedilen lot (0159). true: maliyet tahmin (o gunun fiyati), kullanici girince false. NULL: isaret yok (eski satir).';

-- ── Doğrulama ──────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'assets'
       and column_name = 'maliyet_bilinmiyor' and is_nullable = 'YES'
       and data_type = 'boolean'
  ) then
    raise exception '0159: assets.maliyet_bilinmiyor kurulmadi';
  end if;
  raise notice '0159 tamam: assets.maliyet_bilinmiyor (bos gecilebilir) yerinde.';
end $$;
