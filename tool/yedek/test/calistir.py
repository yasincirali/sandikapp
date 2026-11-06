"""frankfurt_yedek.py'yi yerel PostgreSQL üzerinde uçtan uca dener.

Canlıya dokunmaz. Supabase'e benzeyen asgari şemayı (auth.users/identities
+ profil tetikleyicisi, GENERATED/serial, jsonb, dizi, db_logs) iki
veritabanına kurar; `al` → `dogrula` → `geri-yukle` zincirini ve reddetmesi
gereken durumları (yanlış ref, dolu hedef, onaysız yazma, bozuk dosya) dener.

    python tool/yedek/test/calistir.py
    # sunucu: YEDEK_TEST_TABAN (varsayılan postgresql://postgres:test@localhost:55432,
    # veri_tasima testindeki Docker postgres:17 ile aynı port)

2026-11-06 ilk koşu (PostgreSQL 16): hepsi ✓.
"""
import gzip, os, pathlib, subprocess, sys, tempfile
import psycopg

D = pathlib.Path(__file__).parent
ARAC = str(D.parent / "frankfurt_yedek.py")
TABAN = os.environ.get("YEDEK_TEST_TABAN", "postgresql://postgres:test@localhost:55432")
KAYNAK, HEDEF = f"{TABAN}/kaynak_db", f"{TABAN}/hedef_db"
basarisiz = 0

SEMA = """
create schema auth;
create table auth.users (id uuid primary key, email text, encrypted_password text);
create table auth.identities (id uuid primary key, user_id uuid references auth.users, provider text);
create table auth.sessions (id uuid primary key, user_id uuid);
create table public.profiles (id uuid primary key references auth.users, ad text);
create function public.yeni_kullanici() returns trigger language plpgsql as $$
begin insert into public.profiles(id, ad) values (new.id, 'tetik'); return new; end $$;
create trigger t after insert on auth.users for each row execute function public.yeni_kullanici();
create table public.assets (id serial primary key, user_id uuid references auth.users, ad text,
  miktar numeric, notlar jsonb, etiket text[], toplam numeric generated always as (miktar * 2) stored);
create table public.db_logs (id bigserial primary key, mesaj text);
create schema supabase_migrations;
create table supabase_migrations.schema_migrations (version text primary key);
insert into supabase_migrations.schema_migrations values ('0172');
"""
VERI = """
insert into auth.users values ('00000000-0000-0000-0000-000000000001', 'a@b.c', 'hash');
insert into auth.identities values ('00000000-0000-0000-0000-0000000000a1', '00000000-0000-0000-0000-000000000001', 'email');
insert into auth.sessions values ('00000000-0000-0000-0000-0000000000b1', '00000000-0000-0000-0000-000000000001');
update public.profiles set ad = 'yasin, "tırnak"' where id = '00000000-0000-0000-0000-000000000001';
insert into public.assets (user_id, ad, miktar, notlar, etiket) values
  ('00000000-0000-0000-0000-000000000001', 'THYAO', 10.5, '{"a": [1, 2]}', '{x,y}'),
  ('00000000-0000-0000-0000-000000000001', E'çok\\nsatır', null, null, null);
insert into public.db_logs (mesaj) select 'log' from generate_series(1, 5);
"""


def kontrol_et(ad, kosul):
    global basarisiz
    print(("  ✓ " if kosul else "  ✗ ") + ad)
    basarisiz += not kosul


def arac(*a, kaynak=KAYNAK, hedef=HEDEF):
    env = dict(os.environ, YEDEK_TEST="1", YEDEK_DB_URL=kaynak, HEDEF_DB_URL=hedef, PYTHONIOENCODING="utf-8")
    env.pop("YENI_DB_URL", None)
    r = subprocess.run([sys.executable, ARAC, *a], capture_output=True, text=True, encoding="utf-8", env=env)
    return r.returncode, r.stdout + r.stderr


def sorgu(url, q):
    with psycopg.connect(url) as c:
        return c.execute(q).fetchall()


def kur():
    with psycopg.connect(f"{TABAN}/postgres", autocommit=True) as c:
        for db in ("kaynak_db", "hedef_db"):
            c.execute(f"drop database if exists {db}")
            c.execute(f"create database {db}")
    for url in (KAYNAK, HEDEF):
        with psycopg.connect(url) as c:
            c.execute(SEMA)
    with psycopg.connect(KAYNAK) as c:
        c.execute(VERI)


def main():
    kur()
    kok = pathlib.Path(tempfile.mkdtemp(prefix="yedek_test_"))

    kod, cikti = arac("al", "--kok", str(kok), kaynak=HEDEF)
    kontrol_et("ref kilidi: kaynak dışı adresten yedek almaz", kod != 0 and "REF KİLİDİ" in cikti)

    kod, cikti = arac("al", "--kok", str(kok))
    kontrol_et("al başarılı", kod == 0 and "YEDEK TAMAM" in cikti)
    klasorler = sorted(kok.glob("frankfurt-*"))
    kontrol_et("tek tamamlanmış klasör, yarım klasör yok", len(klasorler) == 1 and not list(kok.glob("*.yarim")))
    k = klasorler[0]
    adlar = {p.name for p in k.iterdir()}
    kontrol_et("auth.sessions ve db_logs yedekte yok",
               "auth.sessions.csv.gz" not in adlar and "public.db_logs.csv.gz" not in adlar)
    kontrol_et("auth.users, identities, profiles, assets yedekte",
               {"auth.users.csv.gz", "auth.identities.csv.gz", "public.profiles.csv.gz",
                "public.assets.csv.gz", "manifest.json"} <= adlar)
    kontrol_et("çıktıda e-posta/şifre özeti yok", "a@b.c" not in cikti and "hash" not in cikti)

    kod, cikti = arac("dogrula", str(k))
    kontrol_et("dogrula temiz yedekte geçer", kod == 0 and "DOĞRULANDI" in cikti)

    kod, cikti = arac("geri-yukle", str(k))
    kontrol_et("onaysız geri yükleme reddedilir", kod != 0 and "--onay hedef_db" in cikti)

    kod, cikti = arac("geri-yukle", str(k), "--onay", "hedef_db")
    kontrol_et("boş hedefe geri yükleme başarılı", kod == 0 and "GERİ YÜKLENDİ" in cikti)
    kontrol_et("profil tetikleyicisi ikinci satır üretmedi, metin aynı",
               sorgu(HEDEF, "select ad from public.profiles") == [('yasin, "tırnak"',)])
    kontrol_et("assets: jsonb/dizi/çok satırlı metin/null korunur, GENERATED hesaplanır",
               sorgu(HEDEF, "select ad, miktar, notlar, etiket, toplam from public.assets order by id")
               == sorgu(KAYNAK, "select ad, miktar, notlar, etiket, toplam from public.assets order by id"))
    kontrol_et("serial dizisi en büyük id'nin ötesinde",
               sorgu(HEDEF, "insert into public.assets (ad) values ('yeni') returning id") == [(3,)])
    kontrol_et("oturumlar taşınmadı", sorgu(HEDEF, "select count(*) from auth.sessions") == [(0,)])

    kod, cikti = arac("geri-yukle", str(k), "--onay", "hedef_db")
    kontrol_et("dolu hedefe geri yükleme reddedilir", kod != 0 and "Hedef boş değil" in cikti)

    # Bozuk dosya: dogrula ve geri-yukle durmalı.
    yol = k / "public.assets.csv.gz"
    with gzip.open(yol, "ab") as f:
        f.write(b"999,x\n")
    kod, cikti = arac("dogrula", str(k))
    kontrol_et("bozulmuş dosyayı dogrula yakalar", kod != 0 and "BAŞARISIZ" in cikti)

    # Saklama: --sakla 2 ile üç yedek → en eski silinir.
    for _ in range(2):
        import time; time.sleep(1.1)  # klasör adı saniye çözünürlüğünde
        arac("al", "--kok", str(kok), "--sakla", "2")
    kontrol_et("--sakla 2: en yeni iki yedek kalır, en eski (bozuk) silinir",
               len(list(kok.glob("frankfurt-*"))) == 2 and not k.exists())

    print(f"\n{'HEPSİ GEÇTİ' if not basarisiz else f'{basarisiz} BAŞARISIZ'}")
    sys.exit(1 if basarisiz else 0)


if __name__ == "__main__":
    main()
