-- 0177 — Aylık notta kamuya açık haber (2026-11-07, yasin: "önemli haber
-- akışlarıyla önemli bilgi olan varlıklar görüntülenmeli").
--
-- ## Neden
-- Aylık not ölçüm paketinden yazılır ve haber bilmiyordu; rapor "haber yok"
-- diyordu. `analiz-hazirla`, `ANALIZ_HABER_ACIK=1` iken her varlık için ayrı
-- bir haber batch'i gönderir (Anthropic sunucu taraflı `web_search`, varlık
-- başına en çok 2 arama, yalnız o ayın tarihleri); `analiz-topla` sonucu
-- haber kapısından geçirip (rakamsız özet, aramada gerçekten dönen bağlantı,
-- SPK dili) not satırına yazar. Ayrıntı: `_shared/analiz_haber.ts`.
--
-- ## Neden yeni sütun (0117 `kaynaklar` değil)
-- `kaynaklar` 0117'de `[{baslik, url}]` diye ayrıldı ve hiç yazılmadı. Haber
-- satırı özet + yayın adı + bağlantı + tarih taşır; aynı adla farklı biçim
-- yerine ayrı alan. `kaynaklar` dokunulmadan kalır.
--
-- ## Eski sürümler
-- Yalnız EKLER. Eski istemci `varlik_analizi`'nden adıyla sütun seçer
-- (`ticker, tur, donem, baslik, maddeler, rozet, girdi`); `haberler`i hiç
-- istemez, görmezden gelir. Varsayılan '[]': haber batch'i gelmeyen her
-- satır "haber yok" demektir. `analiz_batch.amac` varsayılanı 'not': var olan
-- defter satırları not batch'i olarak kalır.
--
-- ## Yetki
-- Yeni tablo yok. `varlik_analizi` okuma politikası satır bazlıdır (yayında +
-- Premium); yeni sütun aynı politikayla okunur, tablo GRANT'i değişmez.
-- `analiz_batch` yalnız service_role (0117) — değişmez.

alter table public.varlik_analizi
  add column if not exists haberler jsonb not null default '[]'::jsonb;
alter table public.varlik_analizi
  drop constraint if exists varlik_analizi_haberler_dizi;
alter table public.varlik_analizi
  add constraint varlik_analizi_haberler_dizi
  check (jsonb_typeof(haberler) = 'array' and jsonb_array_length(haberler) <= 4);
-- Haber kapısının red nedeni (izleme; RLS'te yine yalnız yayındaki satır).
alter table public.varlik_analizi
  add column if not exists haber_red text
  check (haber_red is null or length(haber_red) <= 500);

comment on column public.varlik_analizi.haberler is
  'Aylik notun haber satirlari (0177): [{metin, kaynak, url, tarih}], en cok 2. '
  'analiz-topla haber kapisindan gecirip yazar; rakamsiz ozet, aramada donen https baglanti.';

alter table public.analiz_batch
  add column if not exists amac text not null default 'not';
alter table public.analiz_batch
  drop constraint if exists analiz_batch_amac_check;
alter table public.analiz_batch
  add constraint analiz_batch_amac_check check (amac in ('not', 'haber'));
-- Haber batch'inin gerçek maliyeti (token + arama); aylık tavan bunu da sayar.
alter table public.analiz_batch
  add column if not exists maliyet_usd numeric(10, 5);

do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'varlik_analizi' and column_name = 'haberler'
  ) or not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'analiz_batch' and column_name = 'amac'
  ) or not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'analiz_batch' and column_name = 'maliyet_usd'
  ) then
    raise exception '0177: haber sutunlari eksik';
  end if;
  raise notice '0177 tamam: varlik_analizi.haberler, analiz_batch.amac/maliyet_usd eklendi.';
end $$;
