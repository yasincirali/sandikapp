"""Frankfurt veritabanının yerel yedeği (yasin 2026-11-06: "Hazırla + Frankfurt yedeği").

Neden var: Tokyo duraklatılıp silinince elde ikinci kopya kalmıyor ve
Frankfurt Free planda — Supabase otomatik günlük yedek almıyor. Tokyo zaten
yedek değildi: 18 Ekim'de donmuş bir anlık görüntüydü.

Neden GitHub Actions değil de senin bilgisayarın: yedek tüm hesap verisini
taşır. Actions runner'ında (repo herkese açık; artifact'ler oturum açmış
herkese iner) şifreli bile olsa veri GitHub'ın makinesinde açık hâlde işlenir —
bu, gizlilik metnine yeni bir "kişisel veri alan üçüncü taraf" eklemek, yani
"Onay sürümü" artışı ve herkese yeniden onay kapısı demek. Yedek veri
sorumlusunun (senin) makinesinde kalınca metin değişmez. Otomatik isteniyorsa
temiz yol Supabase Pro'nun günlük yedeği (aynı işleyici, metin değişmez).

Neden pg_dump değil: veri_tasima.py ile aynı gerekçe — makinede PostgreSQL
istemcisi/Docker gerekmez, sürüm eşleme derdi yok. Şema zaten yedeklenmez:
tek kaynağı `supabase/migrations/` (CLAUDE.md "Sunucu"). Geri yükleme = boş
projeye migration'lar + bu yedeğin verisi.

Değişmezler:
  * SALT OKUMA — `al` tek `REPEATABLE READ READ ONLY` işlemde okur: tüm
    tablolar aynı anın hâli; Frankfurt'a hiçbir şey yazılmaz.
  * REF KİLİDİ — `al` yalnız Frankfurt adresini kabul eder (Tokyo'nun bayat
    kopyasını "yedek" diye almayalım).
  * BOŞ HEDEF — `geri-yukle` dolu bir veritabanına yazmaz; tek işlemde yazar,
    sayım tutmazsa COMMIT etmez; `--onay <hedef ref>` ister.
  * SAKLAMA SINIRLI — en yeni `--sakla` (varsayılan 8 ≈ 2 ay haftalık) klasör
    kalır, eskiler silinir: hesabını silen kullanıcının verisi yedekte sonsuza
    kadar yaşamasın.
  * Gizli değer basılmaz; çıktı yalnız tablo adı ve satır sayısı.

Bağlantı: Panel → Connect → **Session pooler** (veri_tasima.py'deki YENI_DB_URL
ile aynı). Şifre ayrı değişkende (adrese gömülen @ / # ? adresi böler).

    set YEDEK_DB_URL=postgresql://postgres.ynwymnpdiwudrlxfrmuo@aws-0-eu-central-1.pooler.supabase.com:5432/postgres
    set YEDEK_DB_SIFRE=<şifre>
    python tool/yedek/frankfurt_yedek.py al                       # → ~/sandik-yedek/frankfurt-<tarih>/
    python tool/yedek/frankfurt_yedek.py dogrula <klasör>          # dosyalar bozulmamış mı
    set HEDEF_DB_URL=...  &  set HEDEF_DB_SIFRE=...
    python tool/yedek/frankfurt_yedek.py geri-yukle <klasör> --onay <hedef ref>

Haftalık zamanlama (Windows, bir kez): YAPMAN_GEREKENLER.md "Frankfurt yedeği".
"""
from __future__ import annotations

import argparse
import datetime as dt
import gzip
import hashlib
import json
import os
import pathlib
import shutil
import sys

try:
    import psycopg
    from psycopg import sql
except ImportError:  # pragma: no cover
    sys.exit('psycopg yok: python -m pip install "psycopg[binary]>=3.2"')

FRANKFURT_REF = "ynwymnpdiwudrlxfrmuo"
TOKYO_REF = "ybdbzouzhzwthjgwlbmk"

# Yerel deneme (tool/yedek/test/calistir.py): ref kilidi yerine veritabanı adı.
TEST = os.environ.get("YEDEK_TEST") == "1"
KAYNAK_REF = os.environ.get("YEDEK_TEST_KAYNAK", "kaynak_db") if TEST else FRANKFURT_REF

# auth'tan yalnız hesabın kendisi (şifre özeti users'ta, sağlayıcı bağı
# identities'te). Oturumlar BİLEREK yok: JWT projeye özgü, geri yüklenen
# projede herkes bir kez yeniden giriş yapar (veri_tasima.py ile aynı karar).
AUTH_TABLOLARI = ("users", "identities")
# Varsayılan dışarıda: hata/debug kaydı (en büyük tablo, 1–30 gün tutuluyor),
# geri yüklenen projede anlamı yok.
VARSAYILAN_HARIC = ("public.db_logs",)
BICIM = 1  # manifest biçimi; değişirse geri-yukle eskisini tanısın


# ── Bağlantı ────────────────────────────────────────────────────────────────

def _ref(url: str) -> str:
    """Adresten proje ref'i: pooler kullanıcısı `postgres.<ref>` ya da `db.<ref>.supabase.co`."""
    from urllib.parse import urlsplit
    p = urlsplit(url)
    if TEST:
        return (p.path or "/").lstrip("/")
    kullanici, host = p.username or "", p.hostname or ""
    if kullanici.startswith("postgres."):
        return kullanici.split(".", 1)[1]
    if host.startswith("db.") and host.endswith(".supabase.co"):
        return host.split(".")[1]
    return ""


def baglan(url_degiskeni: str, sifre_degiskeni: str, salt_okuma: bool) -> tuple[psycopg.Connection, str]:
    url = os.environ.get(url_degiskeni, "").strip()
    if not url and url_degiskeni == "YEDEK_DB_URL":
        # veri_tasima.py'yi kullanmış makinede Frankfurt adresi zaten bu adla duruyor.
        url, sifre_degiskeni = os.environ.get("YENI_DB_URL", "").strip(), "YENI_DB_SIFRE"
    if not url:
        sys.exit(f"{url_degiskeni} ortam değişkeni yok (dosya başındaki biçim).")
    govde = url.split("://", 1)[-1]
    kimlik = govde.rsplit("@", 1)[0] if "@" in govde else ""
    if any(ch in kimlik for ch in "@/#?"):
        sys.exit(f"{url_degiskeni}: şifrede özel karakter (@ / # ?) var — şifreyi adresten çıkar, "
                 f"{sifre_degiskeni} değişkenine yaz.")
    sifre = os.environ.get(sifre_degiskeni, "")
    ek = {"password": sifre} if sifre else {}
    try:
        conn = psycopg.connect(url, autocommit=False, connect_timeout=15,
                               application_name="sandik-yedek", **ek)
    except psycopg.OperationalError as e:
        # Ham mesaj adresi (şifre dahil) yankılayabilir — yalnız ipucu.
        m = str(e).lower()
        ipucu = ("şifre yanlış" if "password" in m else
                 "sunucu adı çözülemedi" if "resolve" in m or "getaddrinfo" in m else
                 "zaman aşımı (Session pooler adresi mi?)" if "timeout" in m else
                 "kullanıcı adı 'postgres.<ref>' olmalı" if "tenant" in m else "bağlantı reddedildi")
        sys.exit(f"{url_degiskeni} veritabanına bağlanılamadı: {ipucu}.")
    if salt_okuma:
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
        conn.read_only = True
    return conn, _ref(url)


# ── Katalog ─────────────────────────────────────────────────────────────────

def tablolar(cur, haric: set[str]) -> list[tuple[str, str]]:
    cur.execute("""
        select n.nspname, c.relname
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where c.relkind in ('r', 'p') and not c.relispartition
           and (n.nspname = 'public' or (n.nspname = 'auth' and c.relname = any(%s)))
         order by n.nspname desc, c.relname
    """, (list(AUTH_TABLOLARI),))
    return [(s, t) for s, t in cur.fetchall() if f"{s}.{t}" not in haric]


def kolonlar(cur, sema: str, tablo: str) -> list[str]:
    """GENERATED kolonlar hariç (hedef kendisi hesaplar; COPY onlara yazamaz)."""
    cur.execute("""
        select a.attname from pg_attribute a
         where a.attrelid = (quote_ident(%s) || '.' || quote_ident(%s))::regclass
           and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
         order by a.attnum
    """, (sema, tablo))
    return [r[0] for r in cur.fetchall()]


def migration_surumu(cur) -> str | None:
    cur.execute("select to_regclass('supabase_migrations.schema_migrations') is not null")
    if not cur.fetchone()[0]:
        return None
    cur.execute("select max(version) from supabase_migrations.schema_migrations")
    return cur.fetchone()[0]


def _ozet(yol: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(yol, "rb") as f:
        for parca in iter(lambda: f.read(1 << 20), b""):
            h.update(parca)
    return h.hexdigest()


def _dosya(sema: str, tablo: str) -> str:
    return f"{sema}.{tablo}.csv.gz"


# ── Komutlar ────────────────────────────────────────────────────────────────

def al(args) -> None:
    conn, ref = baglan("YEDEK_DB_URL", "YEDEK_DB_SIFRE", salt_okuma=True)
    if ref != KAYNAK_REF or (not TEST and ref == TOKYO_REF):
        sys.exit(f"REF KİLİDİ: adres Frankfurt'a ({KAYNAK_REF}) ait değil (bulunan '{ref or '?'}'). Hiçbir şey alınmadı.")
    kok = pathlib.Path(args.kok).expanduser()
    an = dt.datetime.now(dt.timezone.utc)
    hedef = kok / f"frankfurt-{an:%Y-%m-%dT%H%M%SZ}"
    gecici = kok / (hedef.name + ".yarim")
    gecici.mkdir(parents=True, exist_ok=False)
    haric = set(VARSAYILAN_HARIC) | set(args.haric or [])
    manifest = {"bicim": BICIM, "ref": ref, "alinma": an.isoformat(), "tablolar": []}
    try:
        with conn, conn.cursor() as cur:
            manifest["migration"] = migration_surumu(cur)
            for sema, tablo in tablolar(cur, haric):
                kols = kolonlar(cur, sema, tablo)
                kol_sql = sql.SQL(", ").join(map(sql.Identifier, kols))
                yol = gecici / _dosya(sema, tablo)
                satir = 0
                with gzip.open(yol, "wb") as f, cur.copy(
                        sql.SQL("copy (select {} from {}.{}) to stdout (format csv, header true)").format(
                            kol_sql, sql.Identifier(sema), sql.Identifier(tablo))) as kopya:
                    for parca in kopya:
                        f.write(parca)
                cur.execute(sql.SQL("select count(*) from {}.{}").format(
                    sql.Identifier(sema), sql.Identifier(tablo)))
                satir = cur.fetchone()[0]
                manifest["tablolar"].append({"ad": f"{sema}.{tablo}", "kolonlar": kols,
                                             "satir": satir, "sha256": _ozet(yol)})
                print(f"  {sema}.{tablo}: {satir}")
            conn.rollback()  # salt okuma işlemini kapat
    except BaseException:
        shutil.rmtree(gecici, ignore_errors=True)  # yarım yedek "yedek" diye kalmasın
        raise
    (gecici / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
    gecici.rename(hedef)
    toplam = sum(t["satir"] for t in manifest["tablolar"])
    print(f"YEDEK TAMAM: {hedef} — {len(manifest['tablolar'])} tablo, {toplam} satır, "
          f"migration {manifest['migration']}")
    eski = sorted(p for p in kok.glob("frankfurt-*") if p.is_dir() and not p.name.endswith(".yarim"))
    for p in eski[:-args.sakla] if args.sakla > 0 else []:
        shutil.rmtree(p)
        print(f"  eski yedek silindi: {p.name}")


def _manifest(klasor: pathlib.Path) -> dict:
    yol = klasor / "manifest.json"
    if not yol.exists():
        sys.exit(f"{klasor}: manifest.json yok — tamamlanmış bir yedek klasörü değil.")
    m = json.loads(yol.read_text(encoding="utf-8"))
    if m.get("bicim") != BICIM:
        sys.exit(f"Manifest biçimi {m.get('bicim')}, bu araç {BICIM} bekliyor.")
    return m


def dogrula(args) -> None:
    klasor = pathlib.Path(args.klasor).expanduser()
    m = _manifest(klasor)
    hata = 0
    for t in m["tablolar"]:
        sema, tablo = t["ad"].split(".", 1)
        yol = klasor / _dosya(sema, tablo)
        if not yol.exists() or _ozet(yol) != t["sha256"]:
            print(f"  ✗ {t['ad']}: dosya yok ya da özeti tutmuyor"); hata += 1; continue
        with gzip.open(yol, "rt", encoding="utf-8", newline="") as f:
            import csv
            satir = sum(1 for _ in csv.reader(f)) - 1  # başlık
        if satir != t["satir"]:
            print(f"  ✗ {t['ad']}: {t['satir']} beklenen, dosyada {satir}"); hata += 1
    if hata:
        sys.exit(f"DOĞRULAMA BAŞARISIZ: {hata} tablo.")
    print(f"DOĞRULANDI: {len(m['tablolar'])} tablo, alınma {m['alinma']}, migration {m['migration']}")


def geri_yukle(args) -> None:
    klasor = pathlib.Path(args.klasor).expanduser()
    m = _manifest(klasor)
    dogrula(args)
    conn, ref = baglan("HEDEF_DB_URL", "HEDEF_DB_SIFRE", salt_okuma=False)
    if not ref or args.onay != ref:
        sys.exit(f"Bu komut yazar. Devam için: --onay {ref or '<hedef ref>'}")
    with conn.cursor() as cur:
        hedef_mig = migration_surumu(cur)
        if m["migration"] and hedef_mig and hedef_mig < m["migration"]:
            sys.exit(f"Hedefin şeması eski (migration {hedef_mig} < yedek {m['migration']}). "
                     "Önce `supabase db push` ile migration'ları koş.")
        # BOŞ HEDEF: dolu tabloya eklemek çift satır ya da id çakışması üretir.
        dolu = []
        for t in m["tablolar"]:
            sema, tablo = t["ad"].split(".", 1)
            cur.execute("select to_regclass(%s) is not null", (t["ad"],))
            if not cur.fetchone()[0]:
                sys.exit(f"Hedefte {t['ad']} yok — migration'lar eksik. Hiçbir şey yazılmadı.")
            cur.execute(sql.SQL("select exists(select 1 from {}.{})").format(
                sql.Identifier(sema), sql.Identifier(tablo)))
            if cur.fetchone()[0]:
                dolu.append(t["ad"])
        if dolu:
            sys.exit("Hedef boş değil (" + ", ".join(dolu[:5]) + (" …" if len(dolu) > 5 else "")
                     + "). Geri yükleme yalnız boş projeye yapılır. Hiçbir şey yazılmadı.")
        # Tetikleyiciler ve FK kapalı: auth.users eklenince profil tetikleyicisi
        # ikinci satır üretmesin, tablo sırası derdi olmasın (veri_tasima.py).
        cur.execute("set local session_replication_role = replica")
        for t in m["tablolar"]:
            sema, tablo = t["ad"].split(".", 1)
            kol_sql = sql.SQL(", ").join(map(sql.Identifier, t["kolonlar"]))
            with gzip.open(klasor / _dosya(sema, tablo), "rb") as f, cur.copy(
                    sql.SQL("copy {}.{} ({}) from stdin (format csv, header true)").format(
                        sql.Identifier(sema), sql.Identifier(tablo), kol_sql)) as kopya:
                for parca in iter(lambda: f.read(1 << 20), b""):
                    kopya.write(parca)
            cur.execute(sql.SQL("select count(*) from {}.{}").format(sql.Identifier(sema), sql.Identifier(tablo)))
            yazilan = cur.fetchone()[0]
            if yazilan != t["satir"]:
                conn.rollback()
                sys.exit(f"{t['ad']}: {t['satir']} beklenen, {yazilan} yazıldı — GERİ ALINDI.")
            print(f"  {t['ad']}: {yazilan}")
        # serial/identity dizileri yüklenen en büyük id'nin ötesine.
        cur.execute("""
            select quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname,
                   pg_get_serial_sequence(quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname)
              from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
               and pg_get_serial_sequence(quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname) is not null
        """)
        for tablo, kol, dizi in cur.fetchall():
            cur.execute(sql.SQL("select max({}) from {}").format(sql.Identifier(kol), sql.SQL(tablo)))
            en_buyuk = cur.fetchone()[0]
            if en_buyuk is not None:
                cur.execute("select setval(%s, %s, true)", (dizi, en_buyuk))
    conn.commit()
    print(f"GERİ YÜKLENDİ → {ref}: {len(m['tablolar'])} tablo. Herkes bir kez yeniden giriş yapar.")


def main() -> None:
    p = argparse.ArgumentParser(description="Frankfurt yerel yedeği (salt okuma) ve boş projeye geri yükleme.")
    alt = p.add_subparsers(dest="komut", required=True)
    a = alt.add_parser("al", help="Frankfurt'u salt okur, ~/sandik-yedek altına yazar")
    a.add_argument("--kok", default=os.environ.get("YEDEK_KOK", "~/sandik-yedek"))
    a.add_argument("--sakla", type=int, default=8, help="tutulacak en yeni yedek sayısı (0 = silme)")
    a.add_argument("--haric", action="append", help="şema.tablo — ek dışarıda bırakılacak tablo")
    d = alt.add_parser("dogrula", help="yedek dosyalarının özetini ve satır sayısını denetler")
    d.add_argument("klasor")
    g = alt.add_parser("geri-yukle", help="yedeği BOŞ bir projeye yükler (migration'lar önceden koşulmuş)")
    g.add_argument("klasor")
    g.add_argument("--onay", default="")
    args = p.parse_args()
    {"al": al, "dogrula": dogrula, "geri-yukle": geri_yukle}[args.komut](args)


if __name__ == "__main__":
    main()
