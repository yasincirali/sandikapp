-- 0095 — Yarış ve Zirve ölçüsü: zaman ağırlıklı getiri (TWR) (2026-10-01)
--
-- ## Neden
-- Yarış/Zirve getirisi bugüne kadar SİMÜLASYONDU: bugünkü sepet dönem
-- başından beri tutulmuş sayılıyordu. Ölçü kıyası ("Yarış Ölçüsü Kıyası",
-- 2026-10-01) gösterdi ki simülasyon gerçek kararları görmüyor (Y'yi satıp
-- X alan, hep X tutmuş sayılıyor) ve geç, küçük girişe bütün yılı veriyor.
-- Kullanıcı kararı R1: sıralama TWR ("Seçimlerinin getirisi"), kişinin
-- kendi satırında ek bilgi olarak XIRR ("Paranın getirisi", Performans ile
-- aynı sayı — istemcide, sunucu yazmaz).
--
-- TWR para girişinin ZAMANINDAN etkilenmez ama girişin TARİHİNE güvenir:
-- dipte alınmış gibi geriye tarihli kayıt (senaryoda "Gül") TWR'yi şişirir.
-- Bu migration o açığı kapatır; hesap `leaderboard-snapshot`'ta
-- (`donemTwr`) ve istemcide (`secim_getirisi.dart`), ikisi aynı kuralla.
--
-- ## Ne değişti
-- 1) `assets.created_at`: satırın SUNUCUYA GİRİLDİĞİ an. İstemci yazamaz —
--    tetikleyici her INSERT'te `now()` basar; UPDATE'te ekonomik alan
--    (tarih, miktar, sembol, tür, işlem türü, para birimi) değişirse
--    `now()`'a çeker, değişmezse eski değeri korur. "Eski bir satırın
--    tarihini sonradan değiştirmek" de "şimdi girildi" sayılır.
--    Kural (yarışta sayılan an): `added_date` girişten 3 günden fazla
--    gerideyse satır GİRİLDİĞİ anda yapılmış sayılır; 3 günlük pay "dün
--    aldım, bugün giriyorum" kullanıcısını cezalandırmasın diye. Kural
--    yalnız ANONİM sıralamada (Zirve, genel — bu sunucunun yazdığı her
--    şey); ortaklar arası Yarış cihazda ölçülür ve beyan edilen tarihe
--    güvenir (kullanıcı kararı 2026-10-01, içe aktarılan geçmiş hemen
--    sayılsın).
-- 2) Mevcut satırlar: `created_at = added_date` (geleceğe tarihliyse
--    şimdi). Eski kayıtların tarihine GÜVENİLİR: kullanıcılar geçmiş
--    varlıklarını ilk alış tarihiyle girdi; satırları geçiş anına kaydırmak
--    herkesin yarış geçmişini sıfırlardı. Hile denetimi bundan sonraki
--    kayıtlar ve düzenlemeler için çalışır.
-- 3) `user_roi_snapshots`: istemci artık YAZAMAZ (yalnız service role,
--    yani cron). Eski sürümler simülasyon değeri yazmayı sürdürürse iki
--    ölçü aynı havuzda karışırdı; insert yetkisi kalkınca eski istemcinin
--    denemesi sessizce düşer (`uploadRoiSnapshot` hatayı yutar).
-- 4) Simülasyonla yazılmış ROI satırları silinir (`user_roi_snapshots`,
--    `zirve_roi_snapshots`): iki ölçü aynı sıralamada karışmasın. Havuz
--    sıfırdan dolar — Yarış uygunluğu (son 30 günde ≥5 farklı gün) ve
--    Zirve'nin 8 kişilik eşiği yeniden dolana kadar havuz boş görünür.
--    Dağılım tabloları ölçüden bağımsız, dokunulmaz.
--
-- ## Dağıtım sırası
-- ÖNCE bu migration (fonksiyon `created_at`'i seçer; sütun yoksa sorgu
-- düşer), HEMEN ARDINDAN `leaderboard-snapshot`. Arada cron koşarsa eski
-- fonksiyon simülasyon satırı yazar; temizliği bu dosyanın 4. adımını
-- (iki `delete`) yeniden koşmaktır.

-- ── 1) Sütun ve mevcut satırlar ─────────────────────────────────────────────
alter table public.assets add column if not exists created_at timestamptz;

update public.assets
   set created_at = least(added_date, now())
 where created_at is null;

alter table public.assets alter column created_at set default now();
alter table public.assets alter column created_at set not null;

-- ── 2) Tetikleyici: giriş anı istemciden gelmez ────────────────────────────
-- SECURITY DEFINER DEĞİL: yalnız NEW/OLD'a dokunur, hiçbir tablo okumaz.
-- search_path yine sabit (tetikleyici gövdesi adla hiçbir şey çözmez ama
-- kural her fonksiyonda aynı olsun).
create or replace function public.assets_giris_ani()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'INSERT' then
    new.created_at := now();
    return new;
  end if;
  -- Tarih ve miktar TOLERANSLA kıyaslanır: istemci fiyat turunda satırın
  -- TAMAMINI geri yazar (`updateAsset`, her 30 sn). Gidiş-dönüşte bir
  -- yuvarlama farkı (mikro saniye, kayan nokta) olsaydı her tur bütün
  -- satırları "şimdi girildi" sayar, herkesin yarış geçmişi silinirdi.
  if new.added_date is null or old.added_date is null
     or abs(extract(epoch from new.added_date - old.added_date)) > 1
     or abs(new.quantity - old.quantity)
          > 1e-9 * greatest(abs(old.quantity), 1)
     or new.ticker    is distinct from old.ticker
     or new.type      is distinct from old.type
     or new.kind      is distinct from old.kind
     or new.currency  is distinct from old.currency
     or new.sub_category is distinct from old.sub_category then
    new.created_at := now();
  else
    -- Fiyat tazelemesi (`current_price`, her 30 sn), not, ad, silme damgası:
    -- giriş anı değişmez — ve istemci onu elle de değiştiremez.
    new.created_at := old.created_at;
  end if;
  return new;
end;
$$;

drop trigger if exists assets_giris_ani on public.assets;
create trigger assets_giris_ani
  before insert or update on public.assets
  for each row execute function public.assets_giris_ani();

-- ── 3) ROI anlık görüntüsünü yalnız sunucu yazar ────────────────────────────
-- 0073 sütun yetkisi vermişti (user_id, period_days, roi_pct); ikisi de geri.
revoke insert on public.user_roi_snapshots from anon, authenticated;
revoke insert (user_id, period_days, roi_pct) on public.user_roi_snapshots
  from anon, authenticated;
drop policy if exists user_roi_snapshots_own_insert on public.user_roi_snapshots;

-- ── 4) Simülasyon satırları: havuz TWR ile sıfırdan dolar ───────────────────
delete from public.user_roi_snapshots;
delete from public.zirve_roi_snapshots;

-- ── 5) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if not exists (
    select 1 from information_schema.columns
     where table_schema = 'public' and table_name = 'assets'
       and column_name = 'created_at' and is_nullable = 'NO'
  ) then
    raise exception '0095: assets.created_at not null degil';
  end if;
  if not exists (
    select 1 from pg_trigger
     where tgrelid = 'public.assets'::regclass
       and tgname = 'assets_giris_ani' and not tgisinternal
  ) then
    raise exception '0095: assets_giris_ani tetikleyicisi yok';
  end if;
  if has_table_privilege('authenticated', 'public.user_roi_snapshots', 'INSERT')
     or has_column_privilege('authenticated', 'public.user_roi_snapshots', 'roi_pct', 'INSERT')
     or has_table_privilege('anon', 'public.user_roi_snapshots', 'INSERT') then
    raise exception '0095: istemci user_roi_snapshots yazabiliyor';
  end if;
  if not has_table_privilege('service_role', 'public.user_roi_snapshots', 'INSERT') then
    raise exception '0095: service_role user_roi_snapshots yazamiyor (cron duser)';
  end if;
  -- İstemcinin SELECT'i (kendi satırları, `hasServerSideOptIn`) kalmalı.
  if not has_table_privilege('authenticated', 'public.user_roi_snapshots', 'SELECT') then
    raise exception '0095: authenticated kendi ROI satirlarini okuyamiyor';
  end if;
  raise notice '0095 tamam: assets.created_at + tetikleyici, ROI yalniz sunucuda, havuz sifirlandi.';
end $$;
