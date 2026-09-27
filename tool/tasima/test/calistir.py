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

subprocess.run(["docker", "rm", "-f", "tasima-pg"], capture_output=True)
print(f"\nSONUÇ: {'HEPSİ GEÇTİ' if basarisiz == 0 else f'{basarisiz} KIRIK'}")
sys.exit(1 if basarisiz else 0)
