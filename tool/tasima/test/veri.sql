-- Kaynak (Tokyo taklidi) verisi: zor karakterler, NULL'lar, tetikleyiciyle profil.
insert into auth.users (id, email, encrypted_password, email_confirmed_at, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', 'ali@example.com', '$2a$10$abc/def', now(), '{"display_name":"Ali Çıralı"}'),
  ('22222222-2222-2222-2222-222222222222', 'ayşe@example.com', '$2a$10$xyz', null, '{"display_name":"Ayşe \"tırnak\""}'),
  ('33333333-3333-3333-3333-333333333333', 'ölü@example.com', null, now(), null);

insert into auth.identities (id, user_id, provider, identity_data) values
  ('aaaaaaaa-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111', 'email', '{"sub":"1"}'),
  ('aaaaaaaa-0000-0000-0000-000000000002', '22222222-2222-2222-2222-222222222222', 'apple', '{"sub":"2","email":"x@privaterelay.appleid.com"}');

-- Oturum TAŞINMAMALI.
insert into auth.sessions values ('bbbbbbbb-0000-0000-0000-000000000001', '11111111-1111-1111-1111-111111111111');

insert into public.assets (user_id, tip, ticker, quantity, notes, etiketler, meta, deleted_at) values
  ('11111111-1111-1111-1111-111111111111', 'hisse', 'THYAO.IS', 620, E'sekme\there\nyeni satır\\ters bölü', '{a,"b c",NULL}', '{"k":[1,2,{"x":null}]}', null),
  ('11111111-1111-1111-1111-111111111111', 'altin', 'ALTIN_GRAM', 100.12345678, null, null, null, now()),
  ('22222222-2222-2222-2222-222222222222', 'kripto', 'KRIPTO:BTC', 0.00000001, 'ğüşıöçİ', '{}', '{}', null);
-- Kimlik boşluğu: silinmiş satırlar sırayı atlatır (id 4,5 yok, sonraki 6).
insert into public.assets (user_id, tip, ticker, quantity) values ('33333333-3333-3333-3333-333333333333', 'hisse', 'SIL1', 1), ('33333333-3333-3333-3333-333333333333', 'hisse', 'SIL2', 1);
delete from public.assets where ticker like 'SIL%';
insert into public.assets (user_id, tip, ticker, quantity) values ('33333333-3333-3333-3333-333333333333', 'hisse', 'KCHOL.IS', 5);

insert into public.db_logs (mesaj) select 'log ' || g from generate_series(1, 2500) g;

insert into public.partnerships (user_id_1, user_id_2, status)
  values ('11111111-1111-1111-1111-111111111111', '22222222-2222-2222-2222-222222222222', 'accepted');
insert into public.account_deletion_log (user_id_hash) values ('silinen-baskasi');
