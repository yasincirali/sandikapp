-- `signal_state` üzerinde RLS politikaları — istemci kendi de-dup durumunu
-- okuyabilsin ve SIFIRLAYABİLSİN.
--
-- ## Sorun
-- Tabloda `row level security` AÇIK ama HİÇBİR politika tanımlı değildi.
-- Postgres'te bu kombinasyon "her şeyi reddet" demektir: `select`, `delete`,
-- hepsi sessizce boş döner ya da hata verir.
--
-- Fark edilmemesinin sebebi, tabloyu bugüne kadar yalnızca `analyze-signals`
-- edge function'ının yazmasıydı — o `service_role` ile bağlanır ve RLS'i
-- tamamen atlar. İstemcinin bu tabloya ilk kez dokunduğu an hata çıktı:
-- push teşhis ekranındaki "De-dup sıfırla" düğmesi `signal_state`'i silmeye
-- çalışınca reddedildi.
--
-- Bu, sistemin en can sıkıcı arıza sınıfı: de-dup 9 sinyali atlıyor,
-- kullanıcı ekrandaki düğmeye basıyor, düğme sessizce başarısız oluyor ve
-- push yine gelmiyor. Teşhis aracının kendisi işe yaramaz hale geliyor.
--
-- ## Neden yalnızca SELECT + DELETE
-- `signal_state` bir OTORİTE kaydıdır: "bu varlık için en son şu sinyal
-- gönderildi". İstemciye `insert`/`update` vermek, uygulamanın hiç
-- gönderilmemiş bir sinyali "gönderilmiş" olarak işaretlemesine izin
-- verirdi — o varlık için push kalıcı olarak susardı.
--
-- Silme ise güvenli: en kötü ihtimalle sinyaller bir kez daha gönderilir.
-- Yazma yetkisi sunucuda (`service_role`) kalır.
--
-- Not: `service_role` bu politikalardan etkilenmez, RLS'i baştan atlar.

alter table signal_state enable row level security;

-- Kendi durumunu okuyabilsin — teşhis ekranı "kaç satır de-dup'ı sürüyor"
-- sorusunu yanıtlayabilmeli.
drop policy if exists signal_state_own_select on signal_state;
create policy signal_state_own_select
  on signal_state for select
  using (auth.uid() = user_id);

-- Kendi durumunu sıfırlayabilsin — "De-dup sıfırla" düğmesinin ihtiyacı
-- olan tek yetki budur.
drop policy if exists signal_state_own_delete on signal_state;
create policy signal_state_own_delete
  on signal_state for delete
  using (auth.uid() = user_id);

comment on table signal_state is
  'Her varlik icin son GONDERILEN sinyal — de-dup kaynagi. Istemci yalnizca '
  'kendi satirlarini okuyabilir ve silebilir; yazma service_role''dedir.';

-- Doğrulama: politikalar gerçekten oluştu mu?
--
-- RLS eksikliği SESSİZ bir arızadır — tablo çalışıyor görünür, yalnızca
-- istemci işlemleri hiçbir satır etkilemez. Bu migration'ın sessizce
-- yarım uygulanması, düzeltmeye çalıştığı hatanın aynısını üretirdi.
do $$
declare
  n int;
begin
  select count(*) into n
  from pg_policies
  where tablename = 'signal_state'
    and policyname in ('signal_state_own_select', 'signal_state_own_delete');

  if n <> 2 then
    raise exception
      'signal_state RLS politikalari eksik: % / 2 olustu', n;
  end if;
end $$;
