-- 0156 — Lot bazlı satış/temettü/silme kaydı yazılamıyordu (2026-10-19)
--
-- 0133'ün `assets_portfoy_mirasi` tetikleyicisi `a.id = new.ref_asset_id`
-- karşılaştırıyordu: `assets.id` uuid, `ref_asset_id` ise 0009'dan beri
-- text. Postgres'te `uuid = text` operatörü yok; tetikleyici portfoy_id
-- NULL (Ana portföy) ve ref_asset_id dolu HER satırda 42883 atıp INSERT'i
-- düşürüyordu. Etkilenen yollar: tek lottan satış, temettü, lot silmenin
-- mezar taşı (`delete_log` yazılamayınca silme de yarıda kalıyor).
-- Pozisyon düzeyindeki satış (`pos:` kimliği → ref NULL) etkilenmedi; bu
-- yüzden fark edilmedi. Canlı duman testinde (Frankfurt, 2026-10-18) bulundu;
-- 10 Ekim'den beri db_logs'ta 34 "uuid = text" hatası var.
--
-- Düzeltme: ref_asset_id uuid biçimindeyse ::uuid ile birincil anahtardan
-- bak (indeks kullanılır). Biçim dışı eski değer (olmamalı) cast hatası
-- atmasın diye önce regex; tutmazsa satır Ana'da kalır — 0133'ün "bulunamazsa
-- Ana" davranışıyla aynı. Kolon tipine dokunulmaz (eski istemciler text yazar).
-- Yalnız fonksiyon gövdesi değişir: imza, tetikleyici ve yetkiler aynı;
-- eski sürümlerle uyumlu.

create or replace function public.assets_portfoy_mirasi()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.portfoy_id is null
     and new.ref_asset_id is not null
     and new.ref_asset_id ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then
    select a.portfoy_id into new.portfoy_id
      from public.assets a
     where a.id = new.ref_asset_id::uuid
       and a.user_id = new.user_id;
  end if;
  return new;
end;
$$;

-- Doğrulama: gövde artık uuid = text karşılaştırmıyor; tetikleyici yerinde.
do $$
begin
  if position('::uuid' in (select prosrc from pg_proc
                            where oid = 'public.assets_portfoy_mirasi()'::regprocedure)) = 0 then
    raise exception '0156: assets_portfoy_mirasi hala uuid = text karsilastiriyor';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.assets'::regclass
       and tgname = 'assets_portfoy_mirasi' and not tgisinternal
  ) then
    raise exception '0156: assets_portfoy_mirasi tetikleyicisi yok';
  end if;
  raise notice '0156 tamam: lot bazli satis/temettu/silme kaydi yazilabilir.';
end $$;
