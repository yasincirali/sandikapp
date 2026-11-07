-- 0176 — Aylık notta "hareketli" rozeti (2026-11-07, yasin: "aylık raporda
-- tüm varlıkları yapay zekâyla yorumlatmalıyız").
--
-- Aylık not artık akış/hacim verisi olmayan türleri de (yurt dışı hisse,
-- altın, döviz, emtia, eurobond) FİYAT serisinden ölçer
-- (`_shared/analiz.ts › fiyatPaketi`). Öne çıkma sinyali veriden gelir:
-- değişim varlığın olağan oynaklığının 2 katı ya da üstü, oynaklık
-- sıçraması ya da 52 haftalık uç → rozet `hareketli`. Ad istemcinin var olan
-- `HaftaRozeti.hareketli` kademesiyle aynı (orta kademe; çip etiketi hazır).
--
-- Yalnız GENİŞLETİR (eski sürüm uyumu): var olan değerler aynen geçerli.
-- Eski istemci bilmediği rozeti `null` okur (`haftaRozetiSunucudan`), notu
-- rozetsiz gösterir; yeni anahtarları (HISSE:…, ALTIN:GRAM…) zaten istemez.
-- Yeni tablo yok; GRANT değişmez.

alter table public.varlik_analizi drop constraint if exists varlik_analizi_rozet_check;
alter table public.varlik_analizi add constraint varlik_analizi_rozet_check
  check (rozet is null or rozet in ('buyuk_giris', 'buyuk_cikis', 'olagandisi_hacim',
    'alici_istekli', 'satici_istekli', 'hareketli', 'sakin'));

do $$
begin
  if not exists (
    select 1 from pg_constraint
     where conrelid = 'public.varlik_analizi'::regclass
       and conname = 'varlik_analizi_rozet_check'
       and pg_get_constraintdef(oid) like '%hareketli%'
  ) then
    raise exception '0176: varlik_analizi_rozet_check hareketli icermiyor';
  end if;
  raise notice '0176 tamam: varlik_analizi rozet kisiti hareketli ile genisledi.';
end $$;
