-- Hedef (Frankfurt taklidi): Faz 2 denemelerinden kalan veri + kapalı cron.
insert into cron.job (jobname, active) values ('kripto-fiyat', false), ('daily-brief', false);
insert into auth.users (id, email, raw_user_meta_data)
  values ('99999999-9999-9999-9999-999999999999', 'sandikapp.destek+tasimatest@gmail.com', '{"display_name":"Tasima Test"}');
insert into public.db_logs (mesaj) values ('frankfurt deneme');
