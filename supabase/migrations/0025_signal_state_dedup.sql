-- Sinyal de-dup durumu — ayrı tablo.
--
-- Kural: aynı varlık için aynı sinyal art arda push edilmez. Sabah SAT
-- verildiyse akşam yine SAT çıkarsa bildirim gitmez; NÖTR veya AL'a
-- dönerse gider.
--
-- Neden AYRI tablo (signal_notifications yeterli değil):
--
--   1. signal_notifications kullanıcıya ait bir GEÇMİŞ listesidir; kullanıcı
--      bildirimleri silebilir. De-dup o tabloya bakınca, liste temizlenince
--      "hiç gönderilmemiş" sanılıp aynı sinyal yeniden gidiyordu.
--
--   2. De-dup kontrolü artık analizden ÖNCE yapılıyor (yükü azaltmak için).
--      Varlık başına ayrı sorgu yerine tek toplu okuma gerekiyordu;
--      "her varlığın son satırı" sorgusu geçmiş tablosunda pahalı,
--      burada ise satır başına tek kayıt olduğu için doğrudan.
--
-- Bu tablo kullanıcıya gösterilmez; yalnızca sunucunun karar hafızasıdır.

create table if not exists signal_state (
  user_id    uuid references auth.users(id) on delete cascade not null,
  asset_id   text not null,
  -- En son PUSH EDİLEN sinyal. Gönderilmeyen (eşiği geçmeyen, sıklık
  -- yüzünden atlanan) sinyaller buraya yazılmaz — aksi halde hiç
  -- bildirilmemiş bir sinyal bir sonrakini bloklardı.
  signal     text not null check (signal in ('buy','sell','neutral')),
  updated_at timestamptz not null default now(),
  primary key (user_id, asset_id)
);

alter table signal_state enable row level security;

-- Yalnızca service_role (edge function) erişir. Kullanıcıya politika
-- verilmez: bu tablo silinirse/değiştirilirse de-dup bozulur.
revoke all on table signal_state from anon, authenticated;

comment on table signal_state is
  'De-dup karar hafızası: varlık başına son PUSH EDİLEN sinyal. '
  'signal_notifications''tan ayrıdır çünkü kullanıcı geçmişi silebilir.';

-- ── Mevcut durumu geçmişten doldur ───────────────────────────────────────
-- Böylece bu migration'dan hemen sonraki cron, zaten bildirilmiş sinyalleri
-- yeniden göndermez.
insert into signal_state (user_id, asset_id, signal, updated_at)
select distinct on (user_id, asset_id)
       user_id, asset_id, signal, sent_at
from signal_notifications
order by user_id, asset_id, sent_at desc
on conflict (user_id, asset_id) do nothing;

-- ── Durum yazımı ─────────────────────────────────────────────────────────
create or replace function public.touch_signal_state(
  p_user_id  uuid,
  p_asset_id text,
  p_signal   text,
  p_at       timestamptz
) returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into signal_state (user_id, asset_id, signal, updated_at)
  values (p_user_id, p_asset_id, p_signal, p_at)
  on conflict (user_id, asset_id)
  do update set signal = excluded.signal, updated_at = excluded.updated_at;
end;
$$;

revoke all on function public.touch_signal_state(uuid, text, text, timestamptz)
  from public, anon, authenticated;

comment on function public.touch_signal_state(uuid, text, text, timestamptz) is
  'De-dup durumunu günceller. Yalnızca push BAŞARILI olduğunda çağrılır.';
