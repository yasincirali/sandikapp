-- 0171 — Fiyat alarmı "Her geçişte haber ver" (2026-10-29)
--
-- ## İstek
-- Ar-Ge 2026-10-29 20:45 #1, yasin onayı: dolar 42 TL, gram altın 4.300 TL
-- gibi bir SEVİYE izleyen kişi o seviyeyi her geçişte duymak istiyor. Bugün
-- alarm tek atış (0046): çalınca `enabled=false` + `triggered_at`; kişi her
-- seferinde "yeniden kur"a basıyor, unutursa sonraki geçişi kaçırıyor. 5
-- dakikalık tur (0168) boşluğu büyüttü: seviyenin etrafında oynayan fiyatta
-- alarm bir kez çalıp susuyor.
--
-- ## Karar: aynı tabloya EKLEYEREK, varsayılan kapalı
-- `tekrar=false` (varsayılan, eski satırların hepsi) bugünkü tek atış
-- davranışını birebir korur; sunucunun o dalı değişmez. Ayrı tablo
-- açılmadı (0169/0170'in aksine): hedef yine sabit bir fiyat, yön yine
-- above/below — eski build satırı doğru okur, yalnız `tekrar`ı bilmez.
--
-- ## Tekrarlı alarmın yaşamı (`_shared/fiyat_alarmi_tekrar.ts`)
--   · nöbette (`triggered_at` null) → fiyat hedefe ulaşınca ÇALAR; alarm
--     söndürülmez (`enabled` true kalır), `triggered_at` + `son_tetik_at`
--     yazılır, günlük sayaç artar.
--   · çalmış (`triggered_at` dolu) → fiyat hedefin ÖBÜR tarafına %0,5
--     tamponla geçince nöbete döner: `triggered_at` yeniden null.
--     Tampon, seviyenin etrafındaki oynamada 5 dakikada bir bildirim
--     gelmesini önler.
--   · günlük tavan: aynı alarm bir TR gününde en çok 3 kez çalar. Tavan
--     dolunca o gün nöbete DÖNDÜRÜLMEZ (sessiz damga yok); ertesi gün fiyat
--     geri dönünce nöbete girer, sonraki geçiş çalar.
--
-- ## Eski sürümler (CLAUDE.md "sunucu eski sürümlerle uyumlu")
-- Eski build `tekrar`'ı okumaz ve `enabled && triggered_at == null`'ı
-- "bekleyen" sayar. Nöbetteki tekrarlı alarm (`triggered_at` null,
-- `enabled` true) orada da bekleyen görünür — doğru. Çalmış ve geri dönüşü
-- bekleyen alarm eski build'de "çalıştı" görünür; o da doğru (çaldı) ve
-- eski "yeniden kur" yalnız `triggered_at`'i temizler, `tekrar` korunur.
-- Kolon kaldırma/yeniden adlandırma yok; yanıt biçimi değişmez.
--
-- ## `son_tetik_tarafi` neden yok
-- Ar-Ge notu "son tetik tarafı" önermişti. Fiyat alarmının yönü sabit
-- (above/below): çaldığı taraf her zaman yönün tarafıdır, nöbete dönüş
-- tarafı da onun tersi. Saklamak türetilebilir bir değeri ikinci kez
-- yazmak, ikisi ayrışınca hangisine inanılacağı sorusunu açmak olurdu.
-- Onun yerine `son_tetik_at`: nöbete dönüşte `triggered_at` temizlendiği
-- için listedeki "son çaldı" satırı ayrı bir damgaya muhtaç.
--
-- ## İzinler
-- Var olan tabloya kolon: GRANT değişmez (tablo düzeyindeki izinler yeni
-- kolonları kapsar), RLS politikaları (0046, satır sahibi) aynen geçerli.
-- İstemci yalnız insert'te `tekrar` yazar; sayaçları sunucu (service_role)
-- yazar. Kişi kendi satırının sayacıyla oynarsa yalnız kendi alarmını
-- etkiler.

alter table public.price_alerts
  add column if not exists tekrar boolean not null default false,
  -- Son çalış anı; nöbete dönüşte silinmez (liste alt satırı).
  add column if not exists son_tetik_at timestamptz,
  -- Günlük tavan sayacı: [gunluk_tetik_gunu] TR takvim günündeki çalış
  -- sayısı. Gün değişince sunucu sayacı sıfırdan sayar (satırı gece
  -- sıfırlayan iş yok — okurken gün karşılaştırılır).
  add column if not exists gunluk_tetik_sayisi smallint not null default 0,
  add column if not exists gunluk_tetik_gunu date;

do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'price_alerts_gunluk_tetik_sayisi_check') then
    alter table public.price_alerts
      add constraint price_alerts_gunluk_tetik_sayisi_check
      check (gunluk_tetik_sayisi >= 0);
  end if;
end $$;

-- Nöbete dönüş sorgusu: `enabled and tekrar and triggered_at is not null`.
-- Bekleyen alarm indeksi (0046, `triggered_at is null`) bunu kapsamaz.
create index if not exists ix_price_alerts_tekrar_donus
  on public.price_alerts (symbol)
  where enabled and tekrar and triggered_at is not null;

comment on column public.price_alerts.tekrar is
  'Her geciste haber ver (0171). false: tek atis (0046). true: calinca '
  'sonmez; hedefin obur tarafina %0,5 tamponla gecince nobete doner; '
  'gunde en cok 3 kez.';

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
declare
  k text;
begin
  foreach k in array array['tekrar', 'son_tetik_at', 'gunluk_tetik_sayisi',
                           'gunluk_tetik_gunu'] loop
    if not exists (select 1 from information_schema.columns
                    where table_schema = 'public' and table_name = 'price_alerts'
                      and column_name = k) then
      raise exception '0171: price_alerts.% eksik', k;
    end if;
  end loop;
  if (select column_default from information_schema.columns
       where table_schema = 'public' and table_name = 'price_alerts'
         and column_name = 'tekrar') is distinct from 'false' then
    raise exception '0171: price_alerts.tekrar varsayilani false olmali (eski davranis)';
  end if;
  if not exists (select 1 from pg_class
                  where oid = 'public.price_alerts'::regclass
                    and relrowsecurity) then
    raise exception '0171: price_alerts RLS kapali';
  end if;
  raise notice '0171 tamam: price_alerts tekrar + son_tetik_at + gunluk tavan.';
end $$;
