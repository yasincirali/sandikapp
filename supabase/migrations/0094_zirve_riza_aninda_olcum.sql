-- 0094 — Zirvedeki Portföyler: rıza verilince anında ölçüm (2026-10-01)
--
-- ## Neden
-- 0091'den beri havuz açık rızaya dayanıyor; ama rıza veren kullanıcı
-- ancak günlük `leaderboard-snapshot` cron'unda (18:40 TR, 0081) ölçülüyordu.
-- "Katılıyorum"a sabah basan akşama kadar havuzda yoktu. Kullanıcı kararı
-- (2026-10-01, "Anında ölçüm"): rıza kalsın, ölçüm rıza anında yapılsın.
--
-- ## Ne değişti
-- `zirve_rizasi_ayarla(true)` rızayı yazdıktan sonra `leaderboard-snapshot`
-- edge function'ını YALNIZ o kullanıcı için çağırır (`{"user_id": …}`).
-- Fonksiyon bu modda yalnız zirve tablolarına yazar; Yarış tablolarına
-- dokunmaz. İmza ve dönüş tipi aynı → eski istemci etkilenmez.
--
-- Uygunluk şartları (hesap ≥7 gün, varlık ≥5 gün, ≥2 farklı varlık) ve
-- 8 kişilik k-anonimlik eşiği DEĞİŞMEDİ: anında ölçüm yalnız cron beklemesini
-- kaldırır.
--
-- ## Kötüye kullanım sınırı
-- Çağrı yalnız rıza "yok → var" geçişinde yapılır; ayrıl/katıl döngüsüyle
-- fonksiyonu yormak için son rıza verilişinden 10 dk geçmiş olmalı (ayrılınca
-- ölçümler zaten silinir; 10 dk içindeki yeniden katılım cron'u bekler).
--
-- ## Dağıtım sırası
-- ÖNCE `leaderboard-snapshot` fonksiyonu (user_id parametresini tanıyan
-- sürüm), SONRA bu migration. Ters sırada eski fonksiyon `user_id`'yi yok
-- sayıp herkes için tam koşu yapar (zararsız ama gereksiz yük).
--
-- ## Hata
-- HTTP kuyruğa alınamazsa rıza YİNE yazılır (uyarı); kullanıcı akşam cron'unda
-- ölçülür. `net.http_post` asenkron: istek işlem commit edilince gider.

-- ── 1) Tek kullanıcı ölçüm tetikleyicisi ────────────────────────────────────
create or replace function public.zirve_tek_olcum(p_user_id uuid)
returns void
language plpgsql
security definer
set search_path = public, vault, net
as $$
begin
  perform net.http_post(
    url := public.edge_function_url('leaderboard-snapshot'),
    headers := public.cron_headers('leaderboard_snapshot_cron_secret'),
    body := jsonb_build_object('source', 'zirve_riza', 'user_id', p_user_id),
    timeout_milliseconds := 60000
  );
end;
$$;
revoke all on function public.zirve_tek_olcum(uuid) from public, anon, authenticated;

-- ── 2) RPC: rıza ver / geri çek (+ anında ölçüm) ────────────────────────────
-- Gövde 0091 ile aynı; rıza verilişine önceki durum okuması ve tetik eklendi.
create or replace function public.zirve_rizasi_ayarla(p_ver boolean, p_metin_surumu text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_onceki_verildi timestamptz;
  v_onceki_cekildi timestamptz;
  v_satir_var boolean := false;
begin
  if v_uid is null then
    raise exception 'oturum yok' using errcode = '42501';
  end if;
  if p_ver then
    if p_metin_surumu is null or length(p_metin_surumu) not between 1 and 32 then
      raise exception 'gecersiz metin surumu' using errcode = '22023';
    end if;
    select r.verildi_at, r.geri_cekildi_at, true
      into v_onceki_verildi, v_onceki_cekildi, v_satir_var
      from public.zirve_rizalari r
     where r.user_id = v_uid
     for update;
    insert into public.zirve_rizalari (user_id, verildi_at, metin_surumu, geri_cekildi_at)
    values (v_uid, now(), p_metin_surumu, null)
    on conflict (user_id) do update
      set verildi_at = now(),
          metin_surumu = excluded.metin_surumu,
          geri_cekildi_at = null;
    -- Anında ölçüm: yalnız "yok → var" geçişinde ve 10 dk sınırıyla.
    if not coalesce(v_satir_var, false)
       or (v_onceki_cekildi is not null
           and v_onceki_verildi < now() - interval '10 minutes') then
      begin
        perform public.zirve_tek_olcum(v_uid);
      exception when others then
        raise warning 'zirve anlik olcum kuyruga alinamadi: %', sqlerrm;
      end;
    end if;
  else
    update public.zirve_rizalari
       set geri_cekildi_at = now()
     where user_id = v_uid and geri_cekildi_at is null;
    -- Geri çekme = havuzdan çıkış + ölçümlerin silinmesi, aynı işlemde.
    delete from public.zirve_roi_snapshots        where user_id = v_uid;
    delete from public.zirve_allocation_snapshots where user_id = v_uid;
  end if;
end;
$$;
revoke all on function public.zirve_rizasi_ayarla(boolean, text) from public, anon;
grant execute on function public.zirve_rizasi_ayarla(boolean, text) to authenticated;

-- ── 3) Doğrulama ────────────────────────────────────────────────────────────
do $$
begin
  if has_function_privilege('authenticated', 'public.zirve_tek_olcum(uuid)', 'EXECUTE')
     or has_function_privilege('anon', 'public.zirve_tek_olcum(uuid)', 'EXECUTE') then
    raise exception '0094: zirve_tek_olcum istemciden cagrilamamali';
  end if;
  if not has_function_privilege('authenticated', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0094: zirve_rizasi_ayarla authenticated icin EXECUTE eksik';
  end if;
  if has_function_privilege('anon', 'public.zirve_rizasi_ayarla(boolean, text)', 'EXECUTE') then
    raise exception '0094: anon zirve_rizasi_ayarla cagiramamali';
  end if;
  if position('zirve_tek_olcum' in pg_get_functiondef('public.zirve_rizasi_ayarla(boolean, text)'::regprocedure)) = 0 then
    raise exception '0094: zirve_rizasi_ayarla anlik olcumu tetiklemiyor';
  end if;
  if position('zirve_roi_snapshots' in pg_get_functiondef('public.zirve_rizasi_ayarla(boolean, text)'::regprocedure)) = 0 then
    raise exception '0094: geri cekmede olcum silme kayboldu';
  end if;
  raise notice '0094 tamam: zirve rizasi aninda olcum.';
end $$;
