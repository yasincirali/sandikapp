-- 0096 - BES otomatik katkı (kullanıcı isteği, 2026-10-01)
--
-- *"Otomatik ekle seçeneği de olsun; tarihe göre, miktar değişmediği sürece
-- ekleyelim ve yatırma günü de. BES'in otomatik yatırıldı, tutarı
-- güncellemek ister misin deriz."*
--
-- Ekleme İSTEMCİDE yapılır (`SozlesmeNotifier.otomatikKatkilariIsle`): katkı
-- lotunun pay adedi o günün TEFAS fiyatından hesaplanır ve fiyat kaynağı
-- kararı istemcidedir (`fiyat_kaynagi.dart`). Sunucuda cron yok; uygulama
-- açılmadığı aylar sonraki açılışta kendi tarihleriyle yazılır.
--
-- `otomatik_katki_son`: otomatik işlemin BAKTIĞI son gün. Katkı lotundan
-- türetilemez: kullanıcı otomatik eklenen bir katkıyı silerse (o ay
-- yatırmadıysa) ay yine "katkısız" görünür ve bir sonraki açılış onu geri
-- yazardı. İmleç ilerler, silinen katkı geri gelmez. Açılışta ve seçenek
-- açıldığında bugüne kurulur: açılış birikimi o güne kadarki katkıları
-- zaten içerir.

alter table public.sozlesmeler
  add column if not exists otomatik_katki boolean not null default false;
alter table public.sozlesmeler
  add column if not exists otomatik_katki_son date;
-- Otomatik yazılan ve kullanıcının henüz "doğru" demediği katkının günü.
-- Kartta "otomatik eklendi, tutarı güncellemek ister misin" sorusu buna
-- bakar. Sunucuda durur (tercihte değil): soru telefon değişse de kalır ve
-- kullanıcı değişiminde başka hesaba sızmaz.
alter table public.sozlesmeler
  add column if not exists otomatik_katki_bekleyen date;

-- Otomatik katkı yalnız BES'te ve plan tamken anlamlıdır: tutar ya da gün
-- yoksa neyin ne zaman yazılacağı bilinmez; uydurma katkı yazılmaz.
do $$
begin
  if not exists (select 1 from pg_constraint
                  where conname = 'sozlesmeler_otomatik_katki') then
    alter table public.sozlesmeler
      add constraint sozlesmeler_otomatik_katki check (
        not otomatik_katki
        or (tur = 'bes'
            and aylik_katki is not null
            and katki_gunu is not null
            and otomatik_katki_son is not null)
      );
  end if;
  if not exists (select 1 from pg_constraint
                  where conname = 'sozlesmeler_otomatik_bekleyen') then
    alter table public.sozlesmeler
      add constraint sozlesmeler_otomatik_bekleyen check (
        otomatik_katki_bekleyen is null or tur = 'bes'
      );
  end if;
end $$;

-- GRANT/RLS: 0088'deki tablo düzeyi GRANT ve `sozlesmeler_own` politikası
-- yeni sütunları kapsar; yeni yetki gerekmez. Yine de doğrula (0036/0042).
do $$
declare
  g int;
begin
  select count(*) into g from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'sozlesmeler'
     and grantee = 'authenticated'
     and privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE');
  if g <> 4 then
    raise exception '0096: sozlesmeler GRANT eksik: % / 4', g;
  end if;
  if (select count(*) from information_schema.columns
       where table_schema = 'public' and table_name = 'sozlesmeler'
         and column_name in ('otomatik_katki', 'otomatik_katki_son',
                             'otomatik_katki_bekleyen')) <> 3 then
    raise exception '0096: otomatik katki sutunlari yok';
  end if;
  if (select count(*) from pg_constraint
       where conname in ('sozlesmeler_otomatik_katki',
                         'sozlesmeler_otomatik_bekleyen')) <> 2 then
    raise exception '0096: otomatik katki kisitlari yok';
  end if;
end $$;

comment on column public.sozlesmeler.otomatik_katki is
  'BES: katki gunu gelince aylik katki istemcide otomatik lot olarak yazilir. 0096.';
comment on column public.sozlesmeler.otomatik_katki_son is
  'BES otomatik katki imleci: bu gune kadar bakildi; silinen katki geri yazilmaz. 0096.';
comment on column public.sozlesmeler.otomatik_katki_bekleyen is
  'BES: otomatik yazilan ve kullanicinin henuz onaylamadigi katkinin gunu. 0096.';
