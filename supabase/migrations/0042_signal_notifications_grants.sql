-- `signal_notifications` için GRANT güvencesi.
--
-- ## Neden
-- Bildirim çanından silme çalışmıyordu. Üç ayrı kusur vardı; ikisi istemci
-- tarafında (sheet provider'ı izlemiyordu, hatalar `catch (_) {}` ile
-- yutuluyordu). Bu dosya ÜÇÜNCÜSÜNE karşı güvence:
--
-- RLS politikaları eksiksiz kurulmuş (0010/0016: select/insert/update/delete
-- hepsi `auth.uid() = user_id`), ama repoda tabloya hiç `grant` yazılmamış.
-- RLS politikası tek başına YETMEZ — tablo düzeyinde GRANT yoksa
-- `authenticated` rolü satıra hiç ulaşamaz ve UPDATE sessizce 0 satır etkiler.
--
-- Bu, `signal_state`'te BİREBİR yaşanmış bir hatadır:
--   0035 → RLS politikası eklendi, sorun sürdü
--   0036 → GRANT eksikmiş, asıl sebep oydu
-- Aynı tuzağa iki kez düşmemek için burada açıkça veriliyor.
--
-- Tablo şu an çalışıyorsa GRANT bir yerden gelmiş demektir (dashboard'dan
-- elle ya da Supabase'in varsayılanı). Bu dosya onu ŞEMAYA BAĞLAR: yeni bir
-- ortam sıfırdan kurulduğunda silme kendiliğinden çalışır.
--
-- `insert` VERİLMEZ: satırları yalnızca edge function (service_role) yazar.
-- İstemcinin bildirim uydurabilmesi için bir sebep yok.

grant select, update, delete on table signal_notifications to authenticated;

-- ── Doğrulama ─────────────────────────────────────────────────────────────
-- Sessizce eksik kalmasın: migration'ın kendisi kontrol eder.
do $$
declare
  grant_sayisi int;
begin
  select count(*) into grant_sayisi
  from information_schema.role_table_grants
  where table_name = 'signal_notifications'
    and grantee = 'authenticated'
    and privilege_type in ('SELECT', 'UPDATE', 'DELETE');

  if grant_sayisi <> 3 then
    raise exception
      'signal_notifications GRANT eksik: % / 3 (SELECT+UPDATE+DELETE)',
      grant_sayisi;
  end if;
end $$;

comment on table signal_notifications is
  'Gönderilen sinyal bildirimleri. Satırları edge function (service_role) '
  'yazar; kullanıcı yalnızca kendi satırlarını okur, dismiss eder (UPDATE '
  'dismissed_at) veya siler. RLS politikası + GRANT birlikte gerekir — '
  'yalnızca politika verilirse UPDATE sessizce 0 satır etkiler.';
