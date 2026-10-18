"""veri_tasima.py'yi iki yerel PostgreSQL 17 veritabanı arasında uçtan uca dener.

Canlıya dokunmaz: Docker'da `postgres:17` açar (port 55432), Supabase'e
benzeyen asgari şemayı (auth.users + profil tetikleyicisi, GENERATED/IDENTITY/
serial, enum, jsonb, dizi) iki veritabanına kurar ve aracın her komutunu —
reddetmesi gerekenler dahil — dener. Araç değişince koş:

    python tool/tasima/test/calistir.py     # Docker Desktop açık olmalı

2026-09-27 ilk koşu: 36/36. Yakaladığı gerçek tuzak: `public` şeması PUBLIC'e
açıkken anon/authenticated'dan USAGE geri almak hiçbir şeyi kapatmıyor —
`tokyo-kapat` bu yüzden kendini doğruluyor.
"""
import os, pathlib, subprocess, sys, time
import psycopg

D = pathlib.Path(__file__).parent
ARAC = str(D.parent / "veri_tasima.py")
PORT = 55432
TABAN = f"postgresql://postgres:test@localhost:{PORT}"
KAYNAK, HEDEF = f"{TABAN}/kaynak_db", f"{TABAN}/hedef_db"
basarisiz = 0


def kontrol_et(ad, kosul):
    global basarisiz
    print(("  ✓ " if kosul else "  ✗ ") + ad)
    basarisiz += not kosul


def arac(*a, eski=KAYNAK, yeni=HEDEF):
    env = dict(os.environ, TASIMA_TEST="1", ESKI_DB_URL=eski, YENI_DB_URL=yeni, PYTHONIOENCODING="utf-8")
    r = subprocess.run([sys.executable, ARAC, *a], capture_output=True, text=True, encoding="utf-8", env=env)
    return r.returncode, r.stdout + r.stderr


def sorgu(url, q):
    with psycopg.connect(url) as c:
        return c.execute(q).fetchall()


def usage(url, rol="anon"):
    return sorgu(url, f"select has_schema_privilege('{rol}','public','USAGE')")[0][0]


# ── Düzenek ──
# Docker yoksa (bulut oturumu): TASIMA_PG_TABAN ile hazır bir sunucu verilir,
# ör. postgresql://postgres:test@localhost:55432 (initdb ile açılmış).
DOCKER = not os.environ.get("TASIMA_PG_TABAN")
if not DOCKER:
    TABAN = os.environ["TASIMA_PG_TABAN"]
    KAYNAK, HEDEF = f"{TABAN}/kaynak_db", f"{TABAN}/hedef_db"
    with psycopg.connect(f"{TABAN}/postgres", autocommit=True) as c:
        c.execute("drop database if exists kaynak_db"); c.execute("drop database if exists hedef_db")
else:
    subprocess.run(["docker", "rm", "-f", "tasima-pg"], capture_output=True)
    subprocess.run(["docker", "run", "-d", "--name", "tasima-pg", "-e", "POSTGRES_PASSWORD=test",
                    "-p", f"{PORT}:5432", "postgres:17"], check=True, capture_output=True)
for _ in range(60):
    try:
        psycopg.connect(f"{TABAN}/postgres", connect_timeout=2).close(); break
    except Exception:
        time.sleep(1)
with psycopg.connect(f"{TABAN}/postgres", autocommit=True) as c:
    c.execute("create database kaynak_db"); c.execute("create database hedef_db")
for url in (KAYNAK, HEDEF):
    with psycopg.connect(url) as c:
        c.execute((D / "sema.sql").read_text(encoding="utf-8"))
with psycopg.connect(KAYNAK) as c:
    c.execute((D / "veri.sql").read_text(encoding="utf-8"))
with psycopg.connect(HEDEF) as c:
    c.execute((D / "hedef_on.sql").read_text(encoding="utf-8"))

print("1) kontrol — hedef dolu uyarısı")
kod, out = arac("kontrol")
kontrol_et("BOŞ DEĞİL uyarısı", "BOŞ DEĞİL" in out)
kontrol_et("replica kullanılabiliyor", "replica kullanılabiliyor" in out)
kontrol_et("etkin cron 0", "etkin cron: 0" in out)

print("2) tasi — hedef doluyken REDDETMELİ")
kod, out = arac("tasi", "--onay", "hedef_db")
kontrol_et("reddetti", kod != 0 and "boş değil" in out)
kontrol_et("hedefte hâlâ yalnız deneme verisi", sorgu(HEDEF, "select count(*) from public.db_logs")[0][0] == 1)

print("3) yön kilidi — URL'ler ters verilirse")
kod, out = arac("bosalt", "--onay", "hedef_db", eski=HEDEF, yeni=KAYNAK)
kontrol_et("YÖN KİLİDİ", kod != 0 and "YÖN KİLİDİ" in out)
kontrol_et("kaynak dokunulmadı", sorgu(KAYNAK, "select count(*) from public.db_logs")[0][0] == 2500)

print("4) onaysız bosalt reddedilir")
kod, out = arac("bosalt")
kontrol_et("--onay istendi", kod != 0 and "--onay" in out)

print("5) bosalt")
kod, out = arac("bosalt", "--onay", "hedef_db")
kontrol_et("çıkış 0", kod == 0)
kontrol_et("hedef auth.users boş", sorgu(HEDEF, "select count(*) from auth.users")[0][0] == 0)
kontrol_et("cron'a dokunulmadı", sorgu(HEDEF, "select count(*) from cron.job")[0][0] == 2)

print("6) tasi")
kod, out = arac("tasi", "--onay", "hedef_db")
print("     " + out.strip().splitlines()[-1])
kontrol_et("çıkış 0", kod == 0)

print("7) sayim — bağımsız doğrulama")
kod, out = arac("sayim")
kontrol_et("EŞİT", kod == 0 and "EŞİT" in out)

print("8) içerik birebir (tablo md5)")
for t, kolon in [("auth.users", "id, email, encrypted_password, email_confirmed_at, raw_user_meta_data, confirmed_at"),
                 ("auth.identities", "*"), ("public.profiles", "*"),
                 ("public.assets", "*"), ("public.db_logs", "*")]:
    q = f"select md5(string_agg(t::text, '|' order by t::text)) from (select {kolon} from {t}) t"
    kontrol_et(f"{t} aynı", sorgu(KAYNAK, q) == sorgu(HEDEF, q))

print("9) davranış")
kontrol_et("oturumlar TAŞINMADI", sorgu(HEDEF, "select count(*) from auth.sessions")[0][0] == 0)
kontrol_et("tetikleyici çift profil üretmedi (3 = 3)",
           sorgu(HEDEF, "select count(*) from public.profiles")[0][0] == 3)
kontrol_et("generated kolon hedefte hesaplandı",
           sorgu(HEDEF, "select deger from public.assets where ticker='THYAO.IS'")[0][0] == 1240)
with psycopg.connect(HEDEF) as c:
    yeni_id = c.execute("insert into public.assets (user_id, tip, ticker) values "
                        "('11111111-1111-1111-1111-111111111111','hisse','YENI') returning id").fetchone()[0]
    yeni_log = c.execute("insert into public.db_logs (mesaj) values ('x') returning id").fetchone()[0]
kaynak_max = sorgu(KAYNAK, "select max(id) from public.assets")[0][0]
kontrol_et(f"identity devam ediyor ({yeni_id} > {kaynak_max}, çakışma yok)", yeni_id > kaynak_max)
kontrol_et(f"serial devam ediyor ({yeni_log} > 2500)", yeni_log > 2500)
kontrol_et("zor metin korundu",
           sorgu(HEDEF, "select notes from public.assets where ticker='THYAO.IS'")[0][0]
           == "sekme\there\nyeni satır\\ters bölü")

print("10) tasi ikinci kez — hedef artık dolu, REDDETMELİ")
kod, out = arac("tasi", "--onay", "hedef_db")
kontrol_et("reddetti", kod != 0)

print("11a) tokyo-kapat — public PUBLIC'e AÇIKKEN (PostgreSQL varsayılanı)")
kod, out = arac("kontrol")
kontrol_et("kontrol uyarıyor: İŞE YARAMAZ", "İŞE YARAMAZ" in out)
kod, out = arac("tokyo-kapat", "--onay", "kaynak_db")
kontrol_et("kapatamadığını söyledi, çıkış≠0", kod != 0 and "KAPATILAMADI" in out)
kontrol_et("geri aldı: anon'un açık grant'ı yerinde (yarım revoke kalmadı)",
           sorgu(KAYNAK, "select count(*) from pg_namespace n, aclexplode(n.nspacl) a, pg_roles r "
                         "where n.nspname='public' and a.grantee=r.oid and r.rolname='anon'")[0][0] == 1)

print("11b) tokyo-kapat — PUBLIC kapalıyken")
with psycopg.connect(KAYNAK) as c:
    c.execute("revoke usage on schema public from public")
kod, out = arac("kontrol")
kontrol_et("kontrol: kullanılabilir", "tokyo-kapat kullanılabilir" in out)
kod, out = arac("tokyo-kapat", "--onay", "kaynak_db")
kontrol_et("kapattı (doğrulandı)", kod == 0 and "doğrulandı" in out)
kontrol_et("anon USAGE yok", usage(KAYNAK) is False)
kontrol_et("authenticated USAGE yok", usage(KAYNAK, "authenticated") is False)
kod, _ = arac("tokyo-ac", "--onay", "kaynak_db")
kontrol_et("tokyo-ac: anon USAGE geri geldi", usage(KAYNAK) is True)
kod, out = arac("tokyo-kapat", "--onay", "hedef_db")
kontrol_et("tokyo-kapat yanlış onayla reddedilir", kod != 0)

print("12) tek-kullanici — hedef sıfırlanıp yalnız deneme hesabı varken")
kod, _ = arac("bosalt", "--onay", "hedef_db")
with psycopg.connect(HEDEF) as c:
    c.execute("insert into auth.users (id, email, raw_user_meta_data) values "
              "('99999999-9999-9999-9999-999999999999', 'sandikapp.destek+tasimatest@gmail.com', '{}')")
    c.execute("insert into public.db_logs (mesaj) values ('frankfurt deneme')")
ALI, AYSE = "11111111-1111-1111-1111-111111111111", "22222222-2222-2222-2222-222222222222"

kod, out = arac("tek-kullanici", "--email", "yok@example.com", "--onay", "hedef_db")
kontrol_et("olmayan e-posta: reddetti, hiçbir şey yazmadı",
           kod != 0 and sorgu(HEDEF, "select count(*) from public.assets")[0][0] == 0)

kod, out = arac("tek-kullanici", "--email", "ALI@example.com")
kontrol_et("onaysız reddedilir", kod != 0 and "--onay" in out)

kod, out = arac("tek-kullanici", "--email", "ALI@example.com", "--onay", "hedef_db")
print("     " + [l for l in out.splitlines() if "TAŞINDI" in l][0] if "TAŞINDI" in out else out[-400:])
kontrol_et("çıkış 0 (e-posta büyük/küçük harf duyarsız)", kod == 0)
kontrol_et("ali geldi", sorgu(HEDEF, f"select count(*) from auth.users where id='{ALI}'")[0][0] == 1)
kontrol_et("ayşe GELMEDİ", sorgu(HEDEF, f"select count(*) from auth.users where id='{AYSE}'")[0][0] == 0)
kontrol_et("ali'nin 2 varlığı geldi, ayşe'ninki gelmedi",
           sorgu(HEDEF, "select string_agg(ticker, ',' order by ticker) from public.assets")[0][0] == "ALTIN_GRAM,THYAO.IS")
kontrol_et("ali'nin kimliği ve profili geldi",
           sorgu(HEDEF, f"select (select count(*) from auth.identities where user_id='{ALI}'), "
                        f"(select count(*) from public.profiles where id='{ALI}')")[0] == (1, 1))
kontrol_et("ortaklık (karşı taraf yok) GELMEDİ — öksüz ilişki yok",
           sorgu(HEDEF, "select count(*) from public.partnerships")[0][0] == 0)
kontrol_et("başkasının silme logu GELMEDİ",
           sorgu(HEDEF, "select count(*) from public.account_deletion_log")[0][0] == 0)
kontrol_et("oturum GELMEDİ", sorgu(HEDEF, "select count(*) from auth.sessions")[0][0] == 0)
kontrol_et("hedefteki deneme hesabına DOKUNULMADI",
           sorgu(HEDEF, "select count(*) from auth.users where email like 'sandikapp.destek%'")[0][0] == 1)
kontrol_et("ortak tablo (db_logs) hedefte doluydu → dokunulmadı",
           sorgu(HEDEF, "select count(*) from public.db_logs")[0][0] == 1)
q = f"select md5(string_agg(t::text,'|' order by t::text)) from (select * from public.assets where user_id='{ALI}') t"
kontrol_et("ali'nin varlıkları birebir", sorgu(KAYNAK, q) == sorgu(HEDEF, q))

print("13) tek-kullanici tekrar — yeniden koşulabilir, çift satır yok")
# Pilotta Frankfurt'ta giriş yapılmış gibi: ali'nin hedefte oturumu + METİN
# tipli refresh token'ı var. Yeniden koşu ikisini de silmeli (varchar = uuid tuzağı).
with psycopg.connect(HEDEF) as c:
    c.execute(f"insert into auth.sessions values ('cccccccc-0000-0000-0000-000000000001', '{ALI}')")
    c.execute(f"insert into auth.refresh_tokens (user_id, token) values ('{ALI}', 'rt')")
kod, out = arac("tek-kullanici", "--email", "ali@example.com", "--onay", "hedef_db")
kontrol_et("çıkış 0 (varchar user_id'li tabloda patlamadı)", kod == 0)
kontrol_et("ali'nin hedefteki oturumu ve refresh token'ı silindi",
           sorgu(HEDEF, "select (select count(*) from auth.sessions), (select count(*) from auth.refresh_tokens)")[0] == (0, 0))
kontrol_et("ali hâlâ 1 hesap, 2 varlık",
           sorgu(HEDEF, f"select (select count(*) from auth.users where id='{ALI}'), "
                        "(select count(*) from public.assets)")[0] == (1, 2))
with psycopg.connect(HEDEF) as c:
    yeni_id = c.execute(f"insert into public.assets (user_id, tip, ticker) values "
                        f"('{ALI}','hisse','PILOT') returning id").fetchone()[0]
kontrol_et(f"dizi kopyalanan id'lerin ötesinde ({yeni_id} > 6)", yeni_id > 6)

print("13b) hedefe BAŞKA oturum yazarken — sayım karışmamalı")
# 2026-09-27 canlı: Frankfurt'a bağlı uygulama açıkken araç "218.577 beklenen,
# 218.580 yazıldı" deyip haksız yere geri aldı (önce/sonra farkı sayıyordu).
import threading
dur = threading.Event()


def yazici():
    with psycopg.connect(HEDEF, autocommit=True) as c:
        while not dur.is_set():
            c.execute("insert into public.assets (user_id, tip, ticker) values "
                      "('99999999-9999-9999-9999-999999999999','hisse','ESZAMANLI')")


t = threading.Thread(target=yazici); t.start()
time.sleep(0.3)
kod, out = arac("tek-kullanici", "--email", "ali@example.com", "--onay", "hedef_db")
dur.set(); t.join()
eszamanli = sorgu(HEDEF, "select count(*) from public.assets where ticker='ESZAMANLI'")[0][0]
kontrol_et(f"eşzamanlı {eszamanli} yazıma rağmen kopya geçti", kod == 0 and eszamanli > 0)
kontrol_et("ali yine tam 2 varlık",
           sorgu(HEDEF, f"select count(*) from public.assets where user_id='{ALI}'")[0][0] == 2)
with psycopg.connect(HEDEF) as c:
    c.execute("delete from public.assets where ticker='ESZAMANLI'")

print("14) tek-kullanici --ortaklarla")
kod, out = arac("tek-kullanici", "--email", "ali@example.com", "--onay", "hedef_db", "--ortaklarla")
kontrol_et("çıkış 0, 2 hesap", kod == 0 and "2 hesap" in out)
kontrol_et("ayşe ve ortaklık geldi",
           sorgu(HEDEF, f"select (select count(*) from auth.users where id='{AYSE}'), "
                        "(select count(*) from public.partnerships)")[0] == (1, 1))
kontrol_et("pilotta Frankfurt'a eklenen satır yeniden koşuda silindi (kaynak esas)",
           sorgu(HEDEF, "select count(*) from public.assets where ticker='PILOT'")[0][0] == 0)
kontrol_et("kaynak hiç değişmedi", sorgu(KAYNAK, "select count(*) from public.assets")[0][0] == 4)

print("15) birlestir — geçmiş kişilere dokunmadan geri kalanı Tokyo'dan yenile (18 Ekim)")
# 14 Ekim'in tam kopyası: Frankfurt = Tokyo, sonra iki taraf ayrı yaşadı.
kod, _ = arac("bosalt", "--onay", "hedef_db")
kod, _ = arac("tasi", "--onay", "hedef_db")
kesim = sorgu(KAYNAK, "select now()::text")[0][0]
time.sleep(0.2)
OLU, DENIZ, YENI_FR = ("33333333-3333-3333-3333-333333333333", "44444444-4444-4444-4444-444444444444",
                       "55555555-5555-5555-5555-555555555555")
with psycopg.connect(HEDEF) as c:   # Frankfurt: ali TestFlight'tan geçti
    c.execute(f"update auth.users set last_sign_in_at = now() where id = '{ALI}'")
    fr_varlik = c.execute(f"insert into public.assets (user_id, tip, ticker, quantity) values "
                          f"('{ALI}','hisse','FRANKFURT_ALI', 3) returning id").fetchone()[0]
    fr_hareket = c.execute(f"insert into public.transactions (user_id, asset_id, miktar) values "
                           f"('{ALI}', {fr_varlik}, 3) returning id").fetchone()[0]
    c.execute(f"update public.assets set quantity = 999 where user_id = '{ALI}' and ticker = 'THYAO.IS'")
    c.execute(f"insert into public.olay_sayaci (user_id, olay) values ('{ALI}', 'frankfurt')")
    c.execute(f"insert into auth.users (id, email, raw_user_meta_data) values ('{YENI_FR}', 'yeni@fr.example', '{{}}')")
    c.execute(f"insert into public.assets (user_id, tip, ticker) values ('{YENI_FR}','hisse','FR_KAYIT')")
with psycopg.connect(KAYNAK) as c:  # Tokyo: mağaza kullanıcıları yaşamaya devam etti
    tk_varlik = c.execute(f"insert into public.assets (user_id, tip, ticker, quantity) values "
                          f"('{AYSE}','hisse','TOKYO_AYSE', 7) returning id").fetchone()[0]
    tk_hareket = c.execute(f"insert into public.transactions (user_id, asset_id, miktar) values "
                           f"('{AYSE}', {tk_varlik}, 7) returning id").fetchone()[0]
    c.execute(f"insert into public.assets (user_id, tip, ticker) values ('{ALI}','hisse','TOKYO_ALI')")
    c.execute(f"update auth.users set last_sign_in_at = now() where id = '{ALI}'")
    c.execute(f"insert into auth.users (id, email, raw_user_meta_data) values ('{DENIZ}', 'deniz@example.com', '{{}}')")
    c.execute(f"insert into public.assets (user_id, tip, ticker) values ('{DENIZ}','kripto','DENIZ_BTC')")
    c.execute(f"insert into public.olay_sayaci (user_id, olay) values ('{AYSE}', 'tokyo')")
    c.execute("update public.partnerships set status = 'tokyo-degisti'")
    c.execute("insert into public.katalog values ('YENI', 'Tokyo kataloğu')")
    c.execute(f"delete from public.assets where user_id = '{OLU}'")
    c.execute(f"delete from auth.users where id = '{OLU}'")
kontrol_et(f"düzenek gerçek çakışma kurdu (varlık id {fr_varlik} = {tk_varlik}, hareket {fr_hareket} = {tk_hareket})",
           fr_varlik == tk_varlik and fr_hareket == tk_hareket)

once = sorgu(HEDEF, "select md5(string_agg(t::text,'|' order by t::text)) from public.assets t")
kod, out = arac("birlestir", "--kesim", kesim, "--kuru", "--onay", "hedef_db")
kontrol_et("kuru koşu temiz", kod == 0 and "KURU KOŞU TEMİZ" in out)
kontrol_et("kuru koşu hiçbir şey yazmadı",
           sorgu(HEDEF, "select md5(string_agg(t::text,'|' order by t::text)) from public.assets t") == once)
kontrol_et("geçmiş kişi sayısı raporlandı (ali + Frankfurt'ta kayıt olan = 2)", "Geçmiş kişi (dokunulmaz): 2" in out)
kontrol_et("ali'nin Tokyo'daki girişi uyarıldı", "Tokyo'da da giriş" in out)
kod, out = arac("birlestir", "--kesim", kesim, "--gecmis-sayisi", "5", "--onay", "hedef_db")
kontrol_et("beklenen sayı tutmazsa durdu", kod != 0 and "DURDU" in out)
kod, out = arac("birlestir", "--kesim", kesim)
kontrol_et("onaysız reddedilir", kod != 0 and "--onay" in out)

kod, out = arac("birlestir", "--kesim", kesim, "--gecmis-sayisi", "2", "--onay", "hedef_db")
print("     " + (out.strip().splitlines()[-1] if out.strip() else ""))
kontrol_et("çıkış 0", kod == 0 and "BİRLEŞTİRİLDİ" in out)
a = lambda q: sorgu(HEDEF, q)
kontrol_et("ali'nin Frankfurt'ta eklediği varlık KALDI",
           a("select count(*) from public.assets where ticker='FRANKFURT_ALI'")[0][0] == 1)
kontrol_et("ali'nin Frankfurt'taki düzenlemesi KALDI (999)",
           a(f"select quantity from public.assets where user_id='{ALI}' and ticker='THYAO.IS'")[0][0] == 999)
kontrol_et("ali'nin Tokyo'da eklediği GELMEDİ", a("select count(*) from public.assets where ticker='TOKYO_ALI'")[0][0] == 0)
kontrol_et("ayşe'nin Tokyo varlığı Tokyo'daki numarasıyla geldi",
           a("select id from public.assets where ticker='TOKYO_AYSE'")[0][0] == tk_varlik)
yeni_no = a("select id from public.assets where ticker='FRANKFURT_ALI'")[0][0]
kontrol_et(f"çakışan ali varlığı yeni numara aldı ({fr_varlik} → {yeni_no})", yeni_no != fr_varlik)
kontrol_et("ali'nin hareketi yeni numaraya bağlı (FK taşındı)",
           a(f"select asset_id from public.transactions where user_id='{ALI}'")[0][0] == yeni_no)
kontrol_et("ayşe'nin hareketi kendi varlığına bağlı",
           a(f"select asset_id from public.transactions where user_id='{AYSE}'")[0][0] == tk_varlik)
kontrol_et("öksüz hareket yok",
           a("select count(*) from public.transactions t where not exists "
             "(select 1 from public.assets v where v.id = t.asset_id)")[0][0] == 0)
kontrol_et("Tokyo'da yeni kayıt olan geldi",
           a(f"select (select count(*) from auth.users where id='{DENIZ}'), "
             "(select count(*) from public.assets where ticker='DENIZ_BTC')")[0] == (1, 1))
kontrol_et("Frankfurt'ta kayıt olan geçmiş kişi KALDI",
           a(f"select (select count(*) from auth.users where id='{YENI_FR}'), "
             "(select count(*) from public.assets where ticker='FR_KAYIT')")[0] == (1, 1))
kontrol_et("Tokyo'da silinen hesap Frankfurt'tan da silindi",
           a(f"select (select count(*) from auth.users where id='{OLU}'), "
             f"(select count(*) from public.assets where user_id='{OLU}')")[0] == (0, 0))
kontrol_et("geçmiş kişiyle ortak ortaklık Frankfurt'taki hâliyle kaldı",
           a("select string_agg(status, ',') from public.partnerships")[0][0] == "accepted")
kontrol_et("ortak katalog Tokyo'dan geldi", a("select count(*) from public.katalog where kod='YENI'")[0][0] == 1)
kontrol_et("FK'sız user_id tablosu: ali'nin Frankfurt satırı kaldı, ayşe'ninki Tokyo'dan geldi",
           a("select string_agg(olay, ',' order by olay) from public.olay_sayaci")[0][0] == "frankfurt,tokyo")
q = f"select md5(string_agg(t::text,'|' order by t::text)) from (select * from public.assets where user_id='{AYSE}') t"
kontrol_et("ayşe'nin varlıkları Tokyo ile birebir", sorgu(KAYNAK, q) == sorgu(HEDEF, q))
kontrol_et("ali'nin kimliği/profili yerinde",
           a(f"select (select count(*) from auth.identities where user_id='{ALI}'), "
             f"(select count(*) from public.profiles where id='{ALI}')")[0] == (1, 1))
with psycopg.connect(HEDEF) as c:
    son = c.execute(f"insert into public.assets (user_id, tip, ticker) values ('{AYSE}','hisse','SONRA') "
                    "returning id").fetchone()[0]
    son_h = c.execute(f"insert into public.transactions (user_id, miktar) values ('{AYSE}', 1) returning id").fetchone()[0]
kontrol_et(f"diziler iki tarafın da ötesinde (varlık {son} > {yeni_no}, hareket {son_h})",
           son > yeni_no and son_h > max(fr_hareket, tk_hareket))

if DOCKER:
    subprocess.run(["docker", "rm", "-f", "tasima-pg"], capture_output=True)
print(f"\nSONUÇ: {'HEPSİ GEÇTİ' if basarisiz == 0 else f'{basarisiz} KIRIK'}")
sys.exit(1 if basarisiz else 0)
