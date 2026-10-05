-- 0121 — Ekstre AI sütun eşleme sayacı (2026-10-05)
--
-- ## Neden
-- yasin: "tüm banka ve aracı kurumları kapsamalıyız"; karar kartında "AI
-- sütun eşleme" seçildi. Cihazdaki okuyucu bir ekstrenin sütunlarından emin
-- olamadığında kullanıcı "Yapay zekâyla eşle"ye basar; `ekstre-esle`
-- fonksiyonu tablonun ANONİM iskeletini Claude'a yollar, yalnız sütun
-- numaralarını döner (`_shared/ekstre_esleme.ts`).
--
-- Bu tablo yalnız KOTA ve MALİYET içindir: kullanıcı başına günlük hak ve
-- aylık harcama tavanı. İskelet ve model yanıtı SAKLANMAZ. Satırlar 40 gün
-- tutulur (fonksiyon her istekte eskileri siler; Gizlilik 1.6 §7); hesap
-- silinince hemen gider (FK cascade).
--
-- ## Eski sürümler
-- Yalnızca EKLER. Eski build'ler bu tabloyu ve fonksiyonu hiç çağırmaz.
--
-- ## Yetki
-- Yalnız service_role. İstemci tabloya hiç dokunmaz; sayaç fonksiyonda.

create table if not exists public.ekstre_esleme_kaydi (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users(id) on delete cascade,
  olusturuldu   timestamptz not null default now(),
  model         text not null,
  girdi_token   integer,
  cikti_token   integer,
  maliyet_usd   numeric(10, 5),
  -- Eşlemesi dönen tablo sayısı (0 = model hiçbir varlık tablosu bulamadı).
  tablo_sayisi  integer not null default 0
);

create index if not exists ekstre_esleme_kaydi_kullanici_zaman
  on public.ekstre_esleme_kaydi (user_id, olusturuldu desc);
create index if not exists ekstre_esleme_kaydi_zaman
  on public.ekstre_esleme_kaydi (olusturuldu);

alter table public.ekstre_esleme_kaydi enable row level security;
-- Politika YOK: authenticated/anon için RLS her satırı gizler; GRANT da yok.

revoke all on table public.ekstre_esleme_kaydi from public, anon, authenticated;
grant select, insert, update, delete on table public.ekstre_esleme_kaydi to service_role;

do $$
begin
  if has_table_privilege('authenticated', 'public.ekstre_esleme_kaydi', 'SELECT')
     or has_table_privilege('authenticated', 'public.ekstre_esleme_kaydi', 'INSERT')
     or has_table_privilege('anon', 'public.ekstre_esleme_kaydi', 'SELECT') then
    raise exception '0121: ekstre_esleme_kaydi istemciye kapali olmali';
  end if;
  if not (select relrowsecurity from pg_class
           where oid = 'public.ekstre_esleme_kaydi'::regclass) then
    raise exception '0121: ekstre_esleme_kaydi RLS acik olmali';
  end if;
end $$;
