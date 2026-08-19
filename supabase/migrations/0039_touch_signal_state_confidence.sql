-- `touch_signal_state` artık de-dup hafızasını da yazar.
--
-- 0038 `notified_at` ve `confidence` sütunlarını ekledi ama bu RPC onları
-- doldurmuyordu. Sütunlar NULL kaldığı sürece yeni de-dup kuralı (cooldown,
-- 24 saatlik hatırlatma, güven sıçraması) hiç devreye giremez — kod
-- "bilinmiyor" dalına düşer ve eski davranışı sürdürür.
--
-- Bu, sessiz bir yarım-uygulama olurdu: migration başarılı görünür, kural
-- yazılmıştır, ama pratikte hiçbir şey değişmez.
--
-- `p_confidence` VARSAYILANLI: eski imzayla yapılan çağrılar (deploy sırası
-- ters giderse) hata almaz, yalnızca güven bilgisi yazılmaz.
--
-- `notified_at` = `p_at`: bu RPC yalnızca gönderim BAŞARILI olduğunda
-- çağrılır (bkz. `sentSignalOf`), dolayısıyla damga gerçek bildirim anıdır.

-- ÖNCE eski 4 parametreli imzayı düşür.
--
-- `create or replace` farklı parametre listesiyle çağrıldığında REPLACE
-- etmez, İKİNCİ bir aşırı yükleme yaratır. İki imza yan yana durunca
-- PostgREST'in hangisini seçeceği belirsizleşir ve `comment on function`
-- "is not unique" hatası verir. Daha kötüsü: eski imza seçilirse
-- `confidence` sessizce hiç yazılmaz.
drop function if exists touch_signal_state(uuid, text, text, timestamptz);

create or replace function touch_signal_state(
  p_user_id uuid,
  p_asset_id text,
  p_signal text,
  p_at timestamptz,
  p_confidence numeric default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into signal_state (
    user_id, asset_id, signal, updated_at, notified_at, confidence
  )
  values (p_user_id, p_asset_id, p_signal, p_at, p_at, p_confidence)
  on conflict (user_id, asset_id)
  do update set
    signal      = excluded.signal,
    updated_at  = excluded.updated_at,
    notified_at = excluded.notified_at,
    -- Güven bilinmiyorsa ESKİ değeri koru; null yazmak "hiç bildirilmemiş"
    -- gibi görünür ve sıçrama karşılaştırmasını sessizce devre dışı bırakır.
    confidence  = coalesce(excluded.confidence, signal_state.confidence);
end;
$$;

comment on function touch_signal_state is
  'De-dup durumunu yazar: sinyal + son bildirim ani + o bildirimdeki guven. '
  'Yalnizca gonderim BASARILI oldugunda cagrilir.';

do $$
begin
  if not exists (
    select 1 from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where p.proname = 'touch_signal_state'
      and n.nspname = 'public'
      and pg_get_function_identity_arguments(p.oid) like '%numeric%'
  ) then
    raise exception 'touch_signal_state p_confidence parametresi eklenemedi';
  end if;
end $$;
