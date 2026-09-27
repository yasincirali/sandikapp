"""Tokyo → Frankfurt veri taşıma aracı (docs/SUPABASE_FRANKFURT_TASIMA.md, K3/K4).

Neden pg_dump değil: makinede PostgreSQL istemcisi yok, `supabase db dump`
Docker istiyor, pg_dump sunucu sürümüne eşlenmek zorunda. Bu araç tablo tablo
`COPY … TO STDOUT` → `COPY … FROM STDIN` akıtır; sürüm/Docker derdi yok ve
sayım, koruma ve geri dönüş aynı yerde durur.

Değişmezler (her biri bir kazayı önler):
  * YÖN KİLİDİ — kaynak yalnızca Tokyo, hedef yalnızca Frankfurt. Bağlantı
    adresindeki proje ref'i doğrulanır; ters verilirse Tokyo'yu boşaltmak
    mümkün değildir. Yazan her komut `--onay <hedef ref>` ister.
  * TUTARLI ANLIK GÖRÜNTÜ — kaynak tek `REPEATABLE READ READ ONLY` işlemde
    okunur: tüm tablolar aynı anın hâli (lot ile satışı arasında kopma yok).
  * YA HEP YA HİÇ — hedef tek işlemde yazılır; hata → hiçbir şey kalmaz.
  * TETİKLEYİCİLER KAPALI — `session_replication_role = replica`. Açık
    olsaydı auth.users'a eklenen her satır `handle_new_user` benzeri
    tetikleyicilerle profil satırını İKİNCİ kez üretirdi; FK sırası da
    derdimiz olmaz.
  * TAŞINMAYANLAR — auth oturumları/refresh token'lar (JWT projeye özgü →
    herkes bir kez yeniden giriş yapar), vault/cron/migration geçmişi
    (Faz 2'de kuruldu), üretilen (GENERATED) kolonlar (hedef kendisi hesaplar).

Bağlantı: Panel → Connect → **Session pooler** (IPv4; doğrudan `db.<ref>`
Free planda yalnız IPv6). Şifre ortam değişkeninde kalır, ekrana basılmaz.

    export ESKI_DB_URL='postgresql://postgres.ybdbzouzhzwthjgwlbmk:<şifre>@aws-0-ap-northeast-1.pooler.supabase.com:5432/postgres'
    export YENI_DB_URL='postgresql://postgres.ynwymnpdiwudrlxfrmuo:<şifre>@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'

Komutlar (sırası runbook'ta):
    python tool/tasima/veri_tasima.py kontrol                 # salt okuma: şema/yetki/boşluk
    python tool/tasima/veri_tasima.py sayim                   # salt okuma: tablo tablo satır
    python tool/tasima/veri_tasima.py bosalt --onay ynwymnpdiwudrlxfrmuo
    python tool/tasima/veri_tasima.py tasi   --onay ynwymnpdiwudrlxfrmuo
    python tool/tasima/veri_tasima.py tek-kullanici --email x@y.com --onay ynwymnpdiwudrlxfrmuo [--ortaklarla]
    python tool/tasima/veri_tasima.py tokyo-kapat --onay ybdbzouzhzwthjgwlbmk   # K4.2
    python tool/tasima/veri_tasima.py tokyo-ac    --onay ybdbzouzhzwthjgwlbmk   # geri dönüş
"""
from __future__ import annotations

import argparse
import os
import sys
import time

try:
    import psycopg
    from psycopg import sql
except ImportError:  # pragma: no cover
    sys.exit('psycopg yok: python -m pip install "psycopg[binary]>=3.2"')

ESKI_REF = "ybdbzouzhzwthjgwlbmk"   # Tokyo — yalnız OKUNUR (tokyo-kapat/ac hariç)
YENI_REF = "ynwymnpdiwudrlxfrmuo"   # Frankfurt — yalnız YAZILIR

# Yerel deneme (Docker'daki iki veritabanı): ref kilidi yerine bu adlar aranır.
TEST = os.environ.get("TASIMA_TEST") == "1"
if TEST:
    ESKI_REF = os.environ.get("TASIMA_TEST_ESKI", "kaynak_db")
    YENI_REF = os.environ.get("TASIMA_TEST_YENI", "hedef_db")

# auth şemasından yalnız hesabın kendisi: kullanıcı + kimlik (şifre özeti
# users'ta, sağlayıcı bağları identities'te). Oturum tabloları BİLEREK yok.
AUTH_TABLOLARI = ("users", "identities")
# bosalt'ta auth.users'a bağlı artıklar da silinir (replica modunda FK
# çalışmadığı için kendiliğinden gitmezler).
AUTH_ARTIKLARI = (
    "sessions", "refresh_tokens", "mfa_amr_claims", "mfa_challenges",
    "mfa_factors", "one_time_tokens", "flow_state", "identities", "users",
)


# ── Bağlantı ve kilit ────────────────────────────────────────────────────────

def _url(ad: str) -> str:
    v = os.environ.get(ad, "").strip()
    if not v:
        sys.exit(f"{ad} ortam değişkeni yok (docstring'deki biçim).")
    return v


def baglan(taraf: str, anlik: bool = False) -> psycopg.Connection:
    """`eski` ya da `yeni`. Adres beklenen projeye ait değilse DURUR.

    `anlik=True`: tüm okumalar tek REPEATABLE READ READ ONLY işlemde — aynı
    anın hâli. (psycopg işlemi ilk sorguda kendisi açar; elle `begin
    isolation level …` yazmak ETKİSİZ kalır ve uyarıyla geçer.)
    """
    url = _url("ESKI_DB_URL" if taraf == "eski" else "YENI_DB_URL")
    beklenen, oteki = (ESKI_REF, YENI_REF) if taraf == "eski" else (YENI_REF, ESKI_REF)
    if beklenen not in url or oteki in url:
        sys.exit(
            f"YÖN KİLİDİ: {taraf.upper()} adresi {beklenen} projesine ait değil. "
            "ESKI_DB_URL = Tokyo, YENI_DB_URL = Frankfurt olmalı. Hiçbir şey yapılmadı."
        )
    conn = psycopg.connect(url, autocommit=False, connect_timeout=15,
                           application_name=f"sandik-tasima-{taraf}")
    if anlik:
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
        conn.read_only = True
    return conn


def onay_iste(args, ref: str) -> None:
    if args.onay != ref:
        sys.exit(f"Bu komut yazar. Devam için: --onay {ref}")


# ── Katalog ─────────────────────────────────────────────────────────────────

def tablolar(cur) -> list[tuple[str, str]]:
    """Kopyalanacak (şema, tablo) listesi — kaynaktaki sıra.

    public: tüm kalıcı tablolar (bölüm çocukları hariç — ebeveyn üzerinden
    akar). auth: yalnız AUTH_TABLOLARI.
    """
    cur.execute("""
        select n.nspname, c.relname
          from pg_class c join pg_namespace n on n.oid = c.relnamespace
         where c.relkind in ('r', 'p') and not c.relispartition
           and (n.nspname = 'public' or (n.nspname = 'auth' and c.relname = any(%s)))
         order by n.nspname desc, c.relname
    """, (list(AUTH_TABLOLARI),))
    return [(s, t) for s, t in cur.fetchall()]


def kolonlar(cur, sema: str, tablo: str) -> dict[str, tuple[str, bool, bool]]:
    """ad → (tip, not_null, varsayılan_var). GENERATED kolonlar dahil değil."""
    cur.execute("""
        select a.attname, format_type(a.atttypid, a.atttypmod), a.attnotnull,
               (a.atthasdef or a.attidentity <> '')
          from pg_attribute a
         where a.attrelid = (quote_ident(%s) || '.' || quote_ident(%s))::regclass
           and a.attnum > 0 and not a.attisdropped and a.attgenerated = ''
         order by a.attnum
    """, (sema, tablo))
    return {ad: (tip, nn, dv) for ad, tip, nn, dv in cur.fetchall()}


def satir_sayisi(cur, sema: str, tablo: str) -> int:
    cur.execute(sql.SQL("select count(*) from {}.{}").format(
        sql.Identifier(sema), sql.Identifier(tablo)))
    return cur.fetchone()[0]


def tablo_var_mi(cur, sema: str, tablo: str) -> bool:
    cur.execute("select to_regclass(%s) is not null", (f"{sema}.{tablo}",))
    return cur.fetchone()[0]


# ── Komutlar ────────────────────────────────────────────────────────────────

def kontrol(_args) -> int:
    """Salt okuma. Taşımayı engelleyecek her şeyi ÖNCEDEN söyler."""
    hata = 0
    with baglan("eski") as eski, baglan("yeni") as yeni:
        ec, yc = eski.cursor(), yeni.cursor()
        liste = tablolar(ec)
        print(f"Kopyalanacak tablo: {len(liste)} (public + auth.{', auth.'.join(AUTH_TABLOLARI)})")

        for sema, tablo in liste:
            ad = f"{sema}.{tablo}"
            if not tablo_var_mi(yc, sema, tablo):
                print(f"  ✗ {ad}: Frankfurt'ta YOK (migration eksik?)")
                hata += 1
                continue
            k, h = kolonlar(ec, sema, tablo), kolonlar(yc, sema, tablo)
            yalniz_kaynak = [c for c in k if c not in h]
            if yalniz_kaynak:
                print(f"  ✗ {ad}: Frankfurt'ta olmayan kolon(lar) — VERİ KAYBOLUR: {yalniz_kaynak}")
                hata += 1
            zorunlu_bos = [c for c, (_, nn, dv) in h.items() if c not in k and nn and not dv]
            if zorunlu_bos:
                print(f"  ✗ {ad}: Frankfurt'ta varsayılansız NOT NULL yeni kolon: {zorunlu_bos}")
                hata += 1
            tip_farki = [c for c in k if c in h and k[c][0] != h[c][0]]
            if tip_farki:
                print(f"  ! {ad}: tip farkı {[(c, k[c][0], h[c][0]) for c in tip_farki]}")

        dolu = [(f"{s}.{t}", n) for s, t in liste
                if tablo_var_mi(yc, s, t) and (n := satir_sayisi(yc, s, t)) > 0]
        if dolu:
            print(f"  ! Frankfurt BOŞ DEĞİL ({len(dolu)} tablo) — önce `bosalt`: "
                  + ", ".join(f"{a}={n}" for a, n in dolu[:8]) + (" …" if len(dolu) > 8 else ""))

        yc.execute("select count(*) filter (where active) from cron.job")
        aktif = yc.fetchone()[0]
        print(f"  {'✓' if aktif == 0 else '!'} Frankfurt'ta etkin cron: {aktif}"
              + ("" if aktif == 0 else "  (K3 provasında 0 olmalı — çift push)"))

        # Yazma yetkileri ve replica modu — işlem geri alınır, iz bırakmaz.
        for s, t in [("public", liste[0][1] if liste else "x"), ("auth", "users")]:
            yc.execute("select has_table_privilege(%s, 'INSERT') and has_table_privilege(%s, 'DELETE')",
                       (f"{s}.{t}", f"{s}.{t}"))
            if not yc.fetchone()[0]:
                print(f"  ✗ Frankfurt: {s}.{t} için INSERT/DELETE yetkisi yok")
                hata += 1
        try:
            yc.execute("set local session_replication_role = replica")
            print("  ✓ session_replication_role = replica kullanılabiliyor")
        except psycopg.Error as e:
            print(f"  ✗ session_replication_role ayarlanamıyor: {e.diag.message_primary}")
            hata += 1
        yeni.rollback()

        ec.execute("select has_schema_privilege('anon', 'public', 'USAGE'), "
                   "has_schema_privilege('authenticated', 'public', 'USAGE'), "
                   "exists (select 1 from pg_namespace n, aclexplode(n.nspacl) a "
                   "        where n.nspname = 'public' and a.grantee = 0 and a.privilege_type = 'USAGE')")
        anon, auth, herkese = ec.fetchone()
        print(f"  Tokyo public USAGE: anon={anon} authenticated={auth}"
              + ("" if anon and auth else "  ← tokyo-kapat uygulanmış görünüyor"))
        print("  Tokyo `public` şeması PUBLIC'e açık: "
              + ("EVET → tokyo-kapat İŞE YARAMAZ, K4'te panelden Data API kapatılır"
                 if herkese else "hayır → tokyo-kapat kullanılabilir"))

    print("\nKONTROL " + ("TEMİZ" if hata == 0 else f"— {hata} ENGEL"))
    return 1 if hata else 0


def sayim(_args) -> int:
    """Salt okuma. Tablo tablo Tokyo ↔ Frankfurt satır sayısı."""
    fark = 0
    with baglan("eski", anlik=True) as eski, baglan("yeni") as yeni:
        ec, yc = eski.cursor(), yeni.cursor()
        print(f"{'tablo':46} {'Tokyo':>10} {'Frankfurt':>10}")
        for sema, tablo in tablolar(ec):
            e = satir_sayisi(ec, sema, tablo)
            y = satir_sayisi(yc, sema, tablo) if tablo_var_mi(yc, sema, tablo) else -1
            isaret = "" if e == y else "  ←"
            fark += e != y
            print(f"{sema + '.' + tablo:46} {e:>10} {y:>10}{isaret}")
    print(f"\n{'EŞİT' if fark == 0 else f'{fark} tabloda fark'}")
    return 1 if fark else 0


def bosalt(args) -> int:
    """Frankfurt'taki kopyalanacak tabloları ve auth artıklarını siler."""
    onay_iste(args, YENI_REF)
    with baglan("yeni") as yeni:
        yc = yeni.cursor()
        yc.execute("set local session_replication_role = replica")
        toplam = 0
        for sema, tablo in tablolar(yc):
            if sema == "auth":
                continue  # aşağıda bağımlılık sırasıyla
            yc.execute(sql.SQL("delete from {}.{}").format(sql.Identifier(sema), sql.Identifier(tablo)))
            toplam += yc.rowcount
        for tablo in AUTH_ARTIKLARI:
            if tablo_var_mi(yc, "auth", tablo):
                yc.execute(sql.SQL("delete from auth.{}").format(sql.Identifier(tablo)))
                toplam += yc.rowcount
        yeni.commit()
    print(f"Frankfurt boşaltıldı: {toplam} satır silindi.")
    return 0


def tasi(args) -> int:
    """Tokyo anlık görüntüsü → Frankfurt, tek işlem."""
    onay_iste(args, YENI_REF)
    bas = time.monotonic()
    with baglan("eski", anlik=True) as eski, baglan("yeni") as yeni:
        ec, yc = eski.cursor(), yeni.cursor()
        liste = tablolar(ec)

        dolu = [f"{s}.{t}" for s, t in liste if satir_sayisi(yc, s, t) > 0]
        if dolu:
            sys.exit(f"Frankfurt boş değil ({', '.join(dolu[:5])}…) — önce `bosalt`. Hiçbir şey yazılmadı.")

        yc.execute("set local session_replication_role = replica")
        for sema, tablo in liste:
            k, h = kolonlar(ec, sema, tablo), kolonlar(yc, sema, tablo)
            ortak = [c for c in k if c in h]
            if len(ortak) != len(k):
                sys.exit(f"{sema}.{tablo}: kolon uyuşmazlığı — önce `kontrol`. Hiçbir şey yazılmadı.")
            kol = sql.SQL(", ").join(map(sql.Identifier, ortak))
            ad = sql.SQL("{}.{}").format(sql.Identifier(sema), sql.Identifier(tablo))
            with ec.copy(sql.SQL("copy (select {} from {}) to stdout").format(kol, ad)) as cikis, \
                 yc.copy(sql.SQL("copy {} ({}) from stdin").format(ad, kol)) as giris:
                for parca in cikis:
                    giris.write(parca)
            print(f"  {sema}.{tablo:40} {satir_sayisi(yc, sema, tablo):>9}")

        # Diziler: public'teki her sequence kaynağın değerine.
        ec.execute("""select schemaname, sequencename, last_value
                        from pg_sequences where schemaname = 'public'""")
        for sema, dizi, deger in ec.fetchall():
            if deger is not None:
                yc.execute("select setval(%s, %s, true)", (f"{sema}.{dizi}", deger))

        # Son denetim — tutmazsa COMMIT etme.
        fark = [(f"{s}.{t}", satir_sayisi(ec, s, t), satir_sayisi(yc, s, t)) for s, t in liste]
        fark = [f for f in fark if f[1] != f[2]]
        if fark:
            yeni.rollback()
            sys.exit(f"Sayım tutmadı, GERİ ALINDI: {fark[:5]}")
        yeni.commit()
    print(f"\nTAŞINDI: {len(liste)} tablo, {time.monotonic() - bas:.1f} sn. "
          "Sıradaki: `sayim` (bağımsız doğrulama).")
    return 0


# Tek kullanıcı kopyasında: bu tablolar başka kullanıcıların izini taşır ya da
# yalnız o projenin işleyişine aittir — pilota kopyalanmaz.
TEK_KULLANICI_ATLA = {"account_deletion_log", "rate_limit_attempts",
                      "calendar_nudge_log", "inflation_push_log"}


def kullanici_fk_kolonlari(cur, sema: str, tablo: str) -> list[str]:
    """Tablonun auth.users(id)'ye bakan FK kolonları (tek seviye yeter:
    2026-09-27 şemasında her kullanıcı tablosu doğrudan auth.users'a bağlı)."""
    cur.execute("""
        select a.attname
          from pg_constraint k
          join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any(k.conkey)
         where k.contype = 'f' and k.conrelid = (quote_ident(%s) || '.' || quote_ident(%s))::regclass
           and k.confrelid = 'auth.users'::regclass
         order by a.attnum
    """, (sema, tablo))
    return [r[0] for r in cur.fetchall()]


def _kume_kosulu(kolonlar_: list[str], kume: list[str]) -> sql.Composable:
    """Satır, dolu her kullanıcı kolonu kümedeyse ve en az biri doluysa seçilir.
    Ortaklık gibi iki taraflı satır, karşı taraf kümede değilse GELMEZ — hedefte
    yarım (öksüz) ilişki kalmaz."""
    lit = sql.SQL("{}::uuid[]").format(sql.Literal(kume))
    her_biri = sql.SQL(" and ").join(
        sql.SQL("({c} is null or {c} = any({k}))").format(c=sql.Identifier(c), k=lit) for c in kolonlar_)
    en_az_biri = sql.SQL(" or ").join(
        sql.SQL("{c} = any({k})").format(c=sql.Identifier(c), k=lit) for c in kolonlar_)
    return sql.SQL("({}) and ({})").format(her_biri, en_az_biri)


def tek_kullanici(args) -> int:
    """Tek kullanıcıyı (ve istenirse ortaklarını) Tokyo'dan Frankfurt'a kopyalar.

    Pilot/prova içindir: tam taşımada `bosalt` bunu da siler. Tokyo'ya yazmaz.
    Tekrar koşulabilir: kullanıcı Frankfurt'ta varsa önce onun satırları silinir;
    diğer deneme hesaplarına dokunulmaz.
    """
    onay_iste(args, YENI_REF)
    if not args.email:
        sys.exit("--email gerekli.")
    bas = time.monotonic()
    with baglan("eski", anlik=True) as eski, baglan("yeni") as yeni:
        ec, yc = eski.cursor(), yeni.cursor()
        ec.execute("select id::text from auth.users where lower(email) = lower(%s)", (args.email,))
        r = ec.fetchone()
        if not r:
            sys.exit(f"Tokyo'da {args.email} yok. Hiçbir şey yazılmadı.")
        kume = [r[0]]
        if args.ortaklarla and tablo_var_mi(ec, "public", "partnerships"):
            ec.execute("""select distinct case when user_id_1 = %(u)s::uuid then user_id_2 else user_id_1 end::text
                            from public.partnerships
                           where %(u)s::uuid in (user_id_1, user_id_2)""", {"u": kume[0]})
            kume += [x for (x,) in ec.fetchall() if x and x not in kume]
        print(f"Kullanıcı kümesi: {len(kume)} hesap"
              + (" (ortaklar dahil)" if len(kume) > 1 else ""))

        yc.execute("set local session_replication_role = replica")
        liste = [(s, t) for s, t in tablolar(ec) if not (s == "public" and t in TEK_KULLANICI_ATLA)]
        lit = sql.SQL("{}::uuid[]").format(sql.Literal(kume))

        # 1) Hedefte bu kümenin eski izini sil (yeniden koşulabilirlik). Aynı
        #    e-postayla FARKLI id'li hesap varsa o da gider (e-posta tekildir).
        yc.execute(sql.SQL("select id::text from auth.users where id = any({}) or lower(email) = any({})")
                   .format(lit, sql.Literal([args.email.lower()])))
        hedef_kume = sorted({x for (x,) in yc.fetchall()} | set(kume))
        hlit = sql.SQL("{}::uuid[]").format(sql.Literal(hedef_kume))
        for sema, tablo in liste:
            if sema != "public" or not tablo_var_mi(yc, sema, tablo):
                continue
            fk = kullanici_fk_kolonlari(yc, sema, tablo)
            if fk:
                kosul = sql.SQL(" or ").join(sql.SQL("{} = any({})").format(sql.Identifier(c), hlit) for c in fk)
                yc.execute(sql.SQL("delete from {}.{} where {}").format(
                    sql.Identifier(sema), sql.Identifier(tablo), kosul))
        for tablo in AUTH_ARTIKLARI:
            if tablo_var_mi(yc, "auth", tablo):
                kol = "id" if tablo == "users" else "user_id"
                yc.execute(sql.SQL("select 1 from information_schema.columns where table_schema='auth' "
                                   "and table_name={} and column_name={}").format(sql.Literal(tablo), sql.Literal(kol)))
                if yc.fetchone():
                    yc.execute(sql.SQL("delete from auth.{} where {} = any({})").format(
                        sql.Identifier(tablo), sql.Identifier(kol), hlit))

        # 2) Kopyala.
        ozet = []
        for sema, tablo in liste:
            k, h = kolonlar(ec, sema, tablo), kolonlar(yc, sema, tablo)
            ortak = [c for c in k if c in h]
            if len(ortak) != len(k):
                sys.exit(f"{sema}.{tablo}: kolon uyuşmazlığı — önce `kontrol`. Hiçbir şey yazılmadı.")
            ad = sql.SQL("{}.{}").format(sql.Identifier(sema), sql.Identifier(tablo))
            if sema == "auth":
                kol = "id" if tablo == "users" else "user_id"
                kosul = sql.SQL("{} = any({})").format(sql.Identifier(kol), lit)
            else:
                fk = kullanici_fk_kolonlari(ec, sema, tablo)
                if fk:
                    kosul = _kume_kosulu(fk, kume)
                elif satir_sayisi(yc, sema, tablo) == 0:
                    kosul = sql.SQL("true")       # ortak referans tablosu, hedef boş
                else:
                    continue                      # ortak tablo, hedef dolu → dokunma
            secim = sql.SQL(", ").join(map(sql.Identifier, ortak))
            once = satir_sayisi(yc, sema, tablo)
            with ec.copy(sql.SQL("copy (select {} from {} where {}) to stdout").format(secim, ad, kosul)) as cikis, \
                 yc.copy(sql.SQL("copy {} ({}) from stdin").format(ad, secim)) as giris:
                for parca in cikis:
                    giris.write(parca)
            eklenen = satir_sayisi(yc, sema, tablo) - once
            ec.execute(sql.SQL("select count(*) from {} where {}").format(ad, kosul))
            beklenen = ec.fetchone()[0]
            if eklenen != beklenen:
                yeni.rollback()
                sys.exit(f"{sema}.{tablo}: {beklenen} beklenen, {eklenen} yazıldı — GERİ ALINDI.")
            if eklenen:
                ozet.append((f"{sema}.{tablo}", eklenen))

        # 3) Kimlik/serial dizileri kopyalanan en büyük değerin ÖTESİNE: pilot
        #    kullanıcı Frankfurt'ta satır ekleyince Tokyo'dan gelen id'lerle çakışmasın.
        yc.execute("""
            select quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname,
                   pg_get_serial_sequence(quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname)
              from pg_attribute a join pg_class c on c.oid = a.attrelid join pg_namespace n on n.oid = c.relnamespace
             where n.nspname = 'public' and c.relkind = 'r' and a.attnum > 0 and not a.attisdropped
               and pg_get_serial_sequence(quote_ident(n.nspname) || '.' || quote_ident(c.relname), a.attname) is not null
        """)
        for tablo, kol, dizi in yc.fetchall():
            yc.execute(sql.SQL("select max({}) from {}").format(sql.Identifier(kol), sql.SQL(tablo)))
            en_buyuk = yc.fetchone()[0]
            if en_buyuk is not None:
                yc.execute("select setval(%s, greatest(%s, (select last_value from " + dizi + ")), true)",
                           (dizi, en_buyuk))
        yeni.commit()

    for ad, n in ozet:
        print(f"  {ad:40} {n:>8}")
    print(f"\nTEK KULLANICI TAŞINDI: {args.email} ({len(kume)} hesap), "
          f"{sum(n for _, n in ozet)} satır, {time.monotonic() - bas:.1f} sn.")
    print("Frankfurt build'inde AYNI şifreyle giriş yap. Frankfurt'ta yapılan değişiklikler "
          "Tokyo'ya GİTMEZ ve tam taşımada `bosalt` ile silinir.")
    return 0


def tokyo_kapat(args) -> int:
    """K4.2 — Tokyo'da istemci rollerinin public erişimini keser.

    Tek ifade, tam geri alınabilir: anon/authenticated `public` şemasını
    göremez → PostgREST okuma/yazma ve RPC'ler reddedilir. Edge function'lar
    (service_role) ve Auth (supabase_auth_admin) etkilenmez. Yetki tablo
    tablo geri alınmadığı için `tokyo-ac` tek satırla eski hâle döndürür.
    """
    onay_iste(args, ESKI_REF)
    with baglan("eski") as eski:
        eski.execute("revoke usage on schema public from anon, authenticated")
        # KENDİNİ DOĞRULA: PostgreSQL `public` şemasının USAGE'ını varsayılan
        # olarak PUBLIC sözde-rolüne verir; o durumda yukarıdaki revoke HİÇBİR
        # ŞEYİ kapatmaz (roller yetkiyi PUBLIC'ten alır). Yerel denemede
        # tam olarak bu oldu (2026-09-27). Kapanmadıysa geri al — yanlış
        # "kapalı" güvencesi, açık kalmasından kötüdür.
        acik = eski.execute(
            "select has_schema_privilege('anon', 'public', 'USAGE') "
            "or has_schema_privilege('authenticated', 'public', 'USAGE')").fetchone()[0]
        if acik:
            eski.rollback()
            print("KAPATILAMADI (geri alındı): `public` şeması PUBLIC rolüne açık, istemciler\n"
                  "yetkiyi oradan alıyor. Bunun yerine panelden: Tokyo → Project Settings →\n"
                  "Data API → 'Enable Data API' KAPAT (geri dönüşte aç). Veritabanı\n"
                  "yetkilerine dokunmaz; tüm REST/RPC çağrılarını keser, Auth çalışır.")
            return 1
        eski.commit()
    print("Tokyo: anon/authenticated public erişimi KAPALI (doğrulandı). Geri almak: tokyo-ac")
    return 0


def tokyo_ac(args) -> int:
    """Geri dönüş — Supabase'in varsayılan şema yetkisini geri verir."""
    onay_iste(args, ESKI_REF)
    with baglan("eski") as eski:
        eski.execute("grant usage on schema public to anon, authenticated")
        eski.commit()
    print("Tokyo: anon/authenticated public erişimi AÇIK.")
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    alt = p.add_subparsers(dest="komut", required=True)
    for ad, f in [("kontrol", kontrol), ("sayim", sayim), ("bosalt", bosalt),
                  ("tasi", tasi), ("tek-kullanici", tek_kullanici),
                  ("tokyo-kapat", tokyo_kapat), ("tokyo-ac", tokyo_ac)]:
        s = alt.add_parser(ad)
        s.add_argument("--onay", default="")
        s.add_argument("--email", default="")
        s.add_argument("--ortaklarla", action="store_true",
                       help="tek-kullanici: ortaklık kurduğu hesapları da taşı")
        s.set_defaults(f=f)
    args = p.parse_args()
    if TEST:
        print(f"[TEST MODU] kaynak={ESKI_REF} hedef={YENI_REF}")
    return args.f(args)


if __name__ == "__main__":
    sys.exit(main())
