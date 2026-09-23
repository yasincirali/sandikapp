-- ============================================================
-- 0073 — Ortaklık onaysız kurulamaz, ortaklık satırı başka hesaba
-- çevrilemez, sinyal hafızası dışarıdan yazılamaz (2026-09-23)
--
-- Kaynak: 2026-09-23 güvenlik denetimi (statik; katalog + politika
-- metinleri). Üç açık da "başka kullanıcının portföyünü oku" ya da
-- "başka kullanıcının bildirimini sustur" sonucuna varıyordu.
--
-- ## C1 — Onaysız ortaklık
-- `invites_own_insert` yalnızca `from_user_id = auth.uid()` bakıyordu;
-- `to_user_id` / `requester_name` / `status` / `expires_at` istemciden
-- serbestti. Saldırgan kurbanın uuid'sini `to_user_id` olarak yazdığı bir
-- davet ekleyip `accept-invite`'ı kendi davetinin SAHİBİ olarak çağırınca
-- fonksiyon service-role ile `partnerships(saldırgan, kurban, active)`
-- açıyordu → `assets_partner_read` kurbanın tüm varlıklarını döndürür.
-- Kurbanın kodu girdiğine dair tek kanıt `redeem-invite-code`'un yazdığı
-- `to_user_id` + `requester_name`'dir; bu yüzden o iki kolonu YALNIZCA
-- sunucu yazar. İstemci daveti hedefsiz, 24 saatlik ve `pending` açar
-- (`AuthService.generatePartnerCode`), bu kısıt onu kırmaz. Süre sınırı
-- 25 saat: istemci 24 saat yazar, saat kayması için bir saat pay.
-- `invites_own_update` da aynı kısıtı taşır (UPDATE'te WITH CHECK yoksa
-- USING yeni satıra da uygulanır, o da hedef kolonlarına bakmıyordu).
--
-- ## C2 — Ortaklık satırını başka hesaba çevirme
-- `partnerships_update` WITH CHECK'siz ve tüm kolonlarda UPDATE yetkisi
-- vardı: (A,B) üyesi A, `user_id_2 = kurban` yazınca yeni satır yine
-- "A üye" koşulunu sağlıyordu → A, kurbanın varlıklarını okur. İstemci
-- bu tabloda yalnızca `active` günceller (`setPartnershipHidden`); yetki
-- o kolona daraltılır, politika üyelik koşulunu yeni satıra da uygular.
--
-- ## H1 — `touch_signal_state` anon'a açık
-- 0025 yetkiyi kaldırmıştı; 0039 fonksiyonu DROP + CREATE ile yeniden
-- kurunca varsayılan yetkiler (PUBLIC/anon/authenticated EXECUTE) geri
-- geldi. Fonksiyon `p_user_id` argümanına güvenip RLS'i geçiyor: yalnızca
-- anon anahtarla herkes, herhangi bir kullanıcının de-dup hafızasına
-- `p_at = 2099-01-01` yazıp sinyal push'larını kalıcı olarak susturabilirdi.
-- Tek çağıran `analyze-signals` (service-role).
--
-- ## M1 — Liderlik tablosu anlık görüntüsünde istemci tarihi
-- `created_at` istemciden yazılabiliyordu: geçmiş tarihli satırlar 1
-- dakikalık kısıtlamaya (`throttle_snapshot_insert`) hiç takılmaz, 0059'un
-- "5 farklı gün" kuralını tek seferde doldurur; 2099 tarihli satır da
-- sonsuza kadar "son 24 saat" ve "en güncel" sayılır. İstemci bu kolonu
-- hiç göndermiyor (`LeaderboardService`), tetikleyici artık `now()` yazar.
--
-- Bu dosyadaki her kısıt, sonunda bir `do` bloğuyla doğrulanır (0036/0042
-- deseni): yetki geri gelirse migration kırılır, sessizce geçmez.
-- ============================================================

-- ── C1: partner_invites ─────────────────────────────────────────────────────
drop policy if exists "invites_own_insert" on public.partner_invites;
create policy "invites_own_insert" on public.partner_invites
  for insert with check (
    auth.uid() = from_user_id
    and to_user_id is null
    and requester_name is null
    and used = false
    and status = 'pending'
    and expires_at <= now() + interval '25 hours'
  );

drop policy if exists "invites_own_update" on public.partner_invites;
create policy "invites_own_update" on public.partner_invites
  for update
  using (auth.uid() = from_user_id)
  with check (
    auth.uid() = from_user_id
    and to_user_id is null
    and requester_name is null
    and expires_at <= now() + interval '25 hours'
  );

-- ── C2: partnerships ────────────────────────────────────────────────────────
revoke update on public.partnerships from anon, authenticated;
grant update (active) on public.partnerships to authenticated;

drop policy if exists "partnerships_update" on public.partnerships;
create policy "partnerships_update" on public.partnerships
  for update
  using (auth.uid() = user_id_1 or auth.uid() = user_id_2)
  with check (auth.uid() = user_id_1 or auth.uid() = user_id_2);

-- ── H1: touch_signal_state ──────────────────────────────────────────────────
revoke all on function public.touch_signal_state(uuid, text, text, timestamptz, numeric)
  from public, anon, authenticated;
grant execute on function public.touch_signal_state(uuid, text, text, timestamptz, numeric)
  to service_role;

-- Olası zehirlenmenin temizliği: gelecekte tarihli bildirim hafızası
-- meşru olamaz (fonksiyon yalnızca `now()` ile çağrılıyor).
update public.signal_state
   set notified_at = null
 where notified_at > now() + interval '5 minutes';

-- Aynı DROP + CREATE tuzağına düşmüş, istemcinin çağırmadığı iki fonksiyon.
revoke all on function public.cleanup_expired_live_activities() from public, anon, authenticated;
revoke execute on function public.get_partner_rois(integer) from public, anon;

-- ── M1: liderlik anlık görüntüleri ──────────────────────────────────────────
revoke insert on public.user_roi_snapshots from anon, authenticated;
grant insert (user_id, period_days, roi_pct) on public.user_roi_snapshots to authenticated;
revoke insert on public.user_allocation_snapshots from anon, authenticated;
grant insert (user_id, allocation_pct, type_count) on public.user_allocation_snapshots to authenticated;

-- Kolon yetkisi istemciyi durdurur; tetikleyici service-role dahil her
-- yazımda saati sunucuya bağlar (kısıtlama sayımı da bu saate göre).
create or replace function public.throttle_snapshot_insert()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_recent integer;
begin
  new.created_at := now();

  if tg_table_name = 'user_roi_snapshots' then
    select count(*) into v_recent
    from public.user_roi_snapshots
    where user_id = new.user_id
      and period_days = new.period_days
      and created_at >= now() - interval '1 minute';
  else
    select count(*) into v_recent
    from public.user_allocation_snapshots
    where user_id = new.user_id
      and created_at >= now() - interval '1 minute';
  end if;

  if v_recent >= 1 then
    raise exception 'snapshot_throttled'
      using hint = 'Dakikada en fazla bir snapshot yazılabilir.';
  end if;

  return new;
end;
$$;

delete from public.user_roi_snapshots where created_at > now() + interval '5 minutes';
delete from public.user_allocation_snapshots where created_at > now() + interval '5 minutes';

-- ── Doğrulama ───────────────────────────────────────────────────────────────
do $$
begin
  if has_function_privilege('anon',
       'public.touch_signal_state(uuid, text, text, timestamptz, numeric)', 'execute')
     or has_function_privilege('authenticated',
       'public.touch_signal_state(uuid, text, text, timestamptz, numeric)', 'execute') then
    raise exception '0073: touch_signal_state hâlâ istemciye açık';
  end if;

  if has_column_privilege('authenticated', 'public.partnerships', 'user_id_1', 'update')
     or has_column_privilege('authenticated', 'public.partnerships', 'user_id_2', 'update') then
    raise exception '0073: partnerships üye kolonları hâlâ güncellenebilir';
  end if;

  if has_column_privilege('authenticated', 'public.user_roi_snapshots', 'created_at', 'insert')
     or has_column_privilege('authenticated', 'public.user_allocation_snapshots', 'created_at', 'insert') then
    raise exception '0073: snapshot created_at hâlâ istemciden yazılabilir';
  end if;

  if not exists (
    select 1 from pg_policies
     where schemaname = 'public' and tablename = 'partner_invites'
       and policyname = 'invites_own_insert'
       and with_check ilike '%to_user_id IS NULL%'
  ) then
    raise exception '0073: invites_own_insert hedef kolonunu kısıtlamıyor';
  end if;
end;
$$;
