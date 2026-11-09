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

    export ESKI_DB_URL='postgresql://postgres.ybdbzouzhzwthjgwlbmk:<şifre>@aws-1-ap-northeast-1.pooler.supabase.com:5432/postgres'
    export YENI_DB_URL='postgresql://postgres.ynwymnpdiwudrlxfrmuo:<şifre>@aws-0-eu-central-1.pooler.supabase.com:5432/postgres'

Komutlar (sırası runbook'ta):
    python tool/tasima/veri_tasima.py kontrol                 # salt okuma: şema/yetki/boşluk
    python tool/tasima/veri_tasima.py sayim                   # salt okuma: tablo tablo satır
    python tool/tasima/veri_tasima.py bosalt --onay ynwymnpdiwudrlxfrmuo
    python tool/tasima/veri_tasima.py tasi   --onay ynwymnpdiwudrlxfrmuo
    python tool/tasima/veri_tasima.py tek-kullanici --email x@y.com --onay ynwymnpdiwudrlxfrmuo [--ortaklarla]
    python tool/tasima/veri_tasima.py birlestir --kuru --onay ynwymnpdiwudrlxfrmuo   # K4: geçmiş kişilere dokunmaz
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
    # Şifre ayrı değişkenden de verilebilir (ESKI_DB_SIFRE / YENI_DB_SIFRE):
    # adrese gömülen şifredeki `@ / : # ?` adresi böler ve psycopg anlamsız bir
    # "label empty" hatası verir (2026-09-27'de yaşandı).
    sifre = os.environ.get("ESKI_DB_SIFRE" if taraf == "eski" else "YENI_DB_SIFRE", "")
    ek = {"password": sifre} if sifre else {}
    _adresi_tani(url, taraf)
    try:
        conn = psycopg.connect(url, autocommit=False, connect_timeout=15,
                               application_name=f"sandik-tasima-{taraf}", **ek)
    except psycopg.OperationalError as e:
        # Ham mesaj adresi (şifre dahil) yankılayabilir — yalnız sunucu + ipucu.
        from urllib.parse import urlsplit
        host = urlsplit(url).hostname or "?"
        m = str(e).lower()
        ipucu = ("şifre yanlış" if "password" in m else
                 "sunucu adı çözülemedi (adresi panelden tam kopyala)" if "resolve" in m or "getaddrinfo" in m else
                 "zaman aşımı (Session pooler adresi mi? doğrudan db.<ref> Free planda IPv6)" if "timeout" in m else
                 "Tenant or user not found → kullanıcı adı 'postgres.<ref>' biçiminde olmalı" if "tenant" in m else
                 "bağlantı reddedildi")
        sys.exit(f"{taraf.upper()} veritabanına bağlanılamadı (sunucu '{host}'): {ipucu}.")
    if anlik:
        conn.isolation_level = psycopg.IsolationLevel.REPEATABLE_READ
        conn.read_only = True
    return conn


def _adresi_tani(url: str, taraf: str) -> None:
    """Bağlanmadan önce adresi çöz; bozuksa ŞİFREYİ GÖSTERMEDEN neresi bozuk söyle."""
    from urllib.parse import urlsplit
    # Kimlik bölümü `scheme://` ile SON `@` arası. Şifrede @ / # ? varsa adres
    # bölünür — urlsplit bile yanlış sunucu çıkarır, psycopg hatası şifrenin
    # PARÇASINI basar. Önce ham metinde yakala.
    govde = url.split("://", 1)[-1]
    kimlik = govde.rsplit("@", 1)[0] if "@" in govde else ""
    if any(ch in kimlik for ch in "@/#?"):
        sys.exit(f"{taraf.upper()} adresindeki şifrede özel karakter (@ / # ?) var — adres bölünüyor.\n"
                 f"Şifreyi adresten çıkar, ayrı ver:\n"
                 f"  export {taraf.upper()}_DB_URL='postgresql://postgres.<ref>@<paneldeki-sunucu>:5432/postgres'\n"
                 f"  export {taraf.upper()}_DB_SIFRE='şifre'")
    try:
        p = urlsplit(url)
        host, port, kullanici = p.hostname or "", p.port, p.username or ""
    except ValueError as e:
        sys.exit(f"{taraf.upper()} adresi çözülemedi ({e}). Şifrede özel karakter olabilir → "
                 f"şifreyi adresten çıkar, {taraf.upper()}_DB_SIFRE değişkenine yaz.")
    sorun = []
    if not host or ".." in host or host.startswith(".") or "..." in url:
        sorun.append(f"sunucu adı geçersiz: '{host}' (örnekteki '...' kaldı mı? paneldeki TAM adresi kopyala)")
    if p.scheme not in ("postgresql", "postgres"):
        sorun.append(f"şema '{p.scheme}' — 'postgresql://' ile başlamalı")
    if "[YOUR-PASSWORD]" in url:
        sorun.append("'[YOUR-PASSWORD]' yer tutucusu adreste duruyor")
    if sorun:
        sys.exit(f"{taraf.upper()} adresi bozuk — kullanıcı='{kullanici}', sunucu='{host}', port={port}:\n  - "
                 + "\n  - ".join(sorun)
                 + f"\nÖneri: şifresiz adres + ayrı değişken:\n"
                   f"  export {taraf.upper()}_DB_URL='postgresql://{kullanici or 'postgres.<ref>'}@<paneldeki-sunucu>:5432/postgres'\n"
                   f"  export {taraf.upper()}_DB_SIFRE='şifre'")


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
        fark = []
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
            # COPY'nin kendi raporu (bkz. tek_kullanici): hedefe başka bir oturum
            # yazsa bile yalnız BİZİM akıttığımız satırlar sayılır.
            okunan, yazilan = ec.rowcount, yc.rowcount
            if okunan != yazilan:
                fark.append((f"{sema}.{tablo}", okunan, yazilan))
            print(f"  {sema}.{tablo:40} {yazilan:>9}")

        # Diziler: public'teki her sequence kaynağın değerine.
        ec.execute("""select schemaname, sequencename, last_value
                        from pg_sequences where schemaname = 'public'""")
        for sema, dizi, deger in ec.fetchall():
            if deger is not None:
                yc.execute("select setval(%s, %s, true)", (f"{sema}.{dizi}", deger))

        # Son denetim — tutmazsa COMMIT etme.
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
                      "calendar_nudge_log", "inflation_push_log",
                      # Destek logu: bir hesap için 218 bin satır (2026-09-27).
                      # Pilotun sorusu "uygulama Frankfurt'ta doğru mu" — log
                      # bunu cevaplamaz, kopyayı dakikalarca uzatır. Tam
                      # taşımada (`tasi`) loglar YİNE gelir.
                      "db_logs"}


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
                    # METİN karşılaştırması: Supabase'de auth.refresh_tokens.user_id
                    # `varchar`, diğerleri `uuid` — `varchar = uuid` operatörü yok
                    # (2026-09-27 canlıda patladı; işlem geri alındı).
                    yc.execute(sql.SQL("delete from auth.{} where {}::text = any({}::text[])").format(
                        sql.Identifier(tablo), sql.Identifier(kol), sql.Literal(hedef_kume)))

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
            with ec.copy(sql.SQL("copy (select {} from {} where {}) to stdout").format(secim, ad, kosul)) as cikis, \
                 yc.copy(sql.SQL("copy {} ({}) from stdin").format(ad, secim)) as giris:
                for parca in cikis:
                    giris.write(parca)
            # Sayım COPY'nin KENDİ raporundan: "tablo ne kadar büyüdü" değil.
            # Hedef canlı (Frankfurt'a bağlı uygulama açıkken db_logs'a yazıyor):
            # önce/sonra farkı başka oturumların satırlarını da sayıp işlemi
            # haksız yere geri aldırdı (2026-09-27: 218.577 beklenen, 218.580).
            beklenen, eklenen = ec.rowcount, yc.rowcount
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


# ── Birleştirme (K4, 18 Ekim 2026) ─────────────────────────────────────────
#
# yasin (18 Ekim): "Halihazırda geçmiş kişileri elleme." 14 Ekim'den beri
# TestFlight testçileri Frankfurt'ta yaşıyor; `bosalt` + `tasi` onların
# Frankfurt'ta yaptığı her şeyi Tokyo'nun eski hâliyle ezerdi. `birlestir`
# yalnız GEÇMEMİŞ hesapları (ve ortak tabloları) Tokyo'dan yeniler:
#
#   * GEÇMİŞ kişi = Frankfurt'ta kesimden sonra giriş yapmış (son giriş
#     zamanı ya da oturumu) ya da kesimden sonra Frankfurt'ta kayıt olmuş hesap. Satırlarına DOKUNULMAZ; Tokyo'daki
#     satırları taşınmaz (Tokyo'da sonradan yazdıkları rapor edilir).
#   * Bir satır, dolu her kullanıcı kolonu "yenilenecek" kümedeyse Tokyo'dan
#     gelir. Geçmiş kişiyle ortak satır (ortaklık) Frankfurt'taki hâliyle kalır.
#   * Kullanıcı kolonu olmayan tablolar (katalog, fiyat…) Tokyo'nun hâlidir.
#   * Tokyo'da silinmiş hesap (Frankfurt'ta var, Tokyo'da yok, kesimden önce
#     açılmış) Frankfurt'tan da silinir.
#   * SAYI ÇAKIŞMASI: kopyadan (14 Ekim) beri iki sunucu dizileri AYNI
#     değerden sürdürdü; geçmiş kişinin Frankfurt'ta aldığı id Tokyo'da başka
#     bir satırın id'si olabilir. Çakışan geçmiş-kişi satırı yeni numara alır,
#     ona FK ile bakan satırlar da güncellenir (aynı işlemde).
#   * `--kuru`: hepsini yapar, raporlar, GERİ ALIR. Gerçek koşudan önce şart.

GECIS_KESIM = "2026-10-14 21:00+00"   # K3 tam kopyasının bittiği an


def kullanici_kolonlari(cur, sema: str, tablo: str) -> list[str]:
    """FK ile auth.users'a bakan kolonlar + FK'sız `user_id` (uuid) kolonu.

    FK'sız `user_id` tutan tablo (log, sayaç) da kullanıcının izini taşır;
    ortak tablo sanılıp Tokyo'nunkiyle ezilirse geçmiş kişinin satırı giderdi."""
    kol = kullanici_fk_kolonlari(cur, sema, tablo)
    cur.execute("""select 1 from information_schema.columns
                    where table_schema = %s and table_name = %s and column_name = 'user_id'
                      and data_type = 'uuid'""", (sema, tablo))
    if cur.fetchone() and "user_id" not in kol:
        kol.append("user_id")
    return kol


def _hepsi_kumede(kolonlar_: list[str], kume: list[str]) -> sql.Composable:
    """Dolu her kullanıcı kolonu kümede (hepsi boşsa da doğru: o satır ortaktır)."""
    lit = sql.SQL("{}::uuid[]").format(sql.Literal(kume))
    return sql.SQL(" and ").join(
        sql.SQL("({c} is null or {c} = any({k}))").format(c=sql.Identifier(c), k=lit) for c in kolonlar_)


def _tekil_sayi_anahtari(cur, sema: str, tablo: str) -> str | None:
    """Tek kolonlu, diziden beslenen (serial/identity) birincil anahtar adı."""
    cur.execute("""
        select a.attname
          from pg_constraint k
          join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
         where k.contype = 'p' and array_length(k.conkey, 1) = 1
           and k.conrelid = (quote_ident(%s) || '.' || quote_ident(%s))::regclass
           and (a.attidentity <> ''
                or pg_get_serial_sequence(quote_ident(%s) || '.' || quote_ident(%s), a.attname) is not null)
    """, (sema, tablo, sema, tablo))
    r = cur.fetchone()
    return r[0] if r else None


def _yeniden_numarala(yc, ec, sema: str, tablo: str, pk: str, gecmis: list[str],
                      ukol: list[str], yenile: list[str]) -> int:
    """Frankfurt'ta kalan (geçmiş kişi) satırlardan Tokyo'dan gelecek bir
    satırla AYNI id'yi taşıyanlara yeni numara verir; FK ile bakanları taşır."""
    ad = sql.SQL("{}.{}").format(sql.Identifier(sema), sql.Identifier(tablo))
    yc.execute(sql.SQL("select {pk} from {ad}").format(pk=sql.Identifier(pk), ad=ad))
    kalan = [r[0] for r in yc.fetchall()]
    if not kalan:
        return 0
    ec.execute(sql.SQL("select {pk} from {ad} where {pk} = any(%s) and {k}").format(
        pk=sql.Identifier(pk), ad=ad, k=_hepsi_kumede(ukol, yenile)), (kalan,))
    cakisan = sorted(r[0] for r in ec.fetchall())
    if not cakisan:
        return 0
    ec.execute(sql.SQL("select coalesce(max({}), 0) from {}").format(sql.Identifier(pk), ad))
    yc.execute(sql.SQL("select coalesce(max({}), 0) from {}").format(sql.Identifier(pk), ad))
    taban = max(ec.fetchone()[0], yc.fetchone()[0])
    harita = [(eski, taban + i + 1) for i, eski in enumerate(cakisan)]
    yc.execute("create temp table _harita (eski bigint primary key, yeni bigint) on commit drop")
    with yc.copy("copy _harita from stdin") as c:
        for e, y in harita:
            c.write_row((e, y))
    kol = [k for k in kolonlar(yc, sema, tablo)]
    secim = sql.SQL(", ").join(
        sql.SQL("h.yeni") if k == pk else sql.SQL("t.{}").format(sql.Identifier(k)) for k in kol)
    # Sil + yeniden ekle (UPDATE değil): GENERATED ALWAYS kimlik kolonu
    # güncellenemez; diğer benzersiz kısıtlar da arada çakışmaz.
    yc.execute(sql.SQL("create temp table _tasinan on commit drop as "
                       "select {s} from {ad} t join _harita h on h.eski = t.{pk}").format(
        s=secim, ad=ad, pk=sql.Identifier(pk)))
    yc.execute(sql.SQL("delete from {ad} t using _harita h where t.{pk} = h.eski").format(
        ad=ad, pk=sql.Identifier(pk)))
    yc.execute(sql.SQL("insert into {ad} ({k}) overriding system value select * from _tasinan").format(
        ad=ad, k=sql.SQL(", ").join(map(sql.Identifier, kol))))
    # Bu satıra FK ile bakanlar (yalnız tek kolonlu FK'lar; şemada başkası yok).
    yc.execute("""
        select n.nspname, c.relname, a.attname
          from pg_constraint k
          join pg_class c on c.oid = k.conrelid join pg_namespace n on n.oid = c.relnamespace
          join pg_attribute a on a.attrelid = k.conrelid and a.attnum = k.conkey[1]
         where k.contype = 'f' and array_length(k.conkey, 1) = 1
           and k.confrelid = (quote_ident(%s) || '.' || quote_ident(%s))::regclass
    """, (sema, tablo))
    for rs, rt, rk in yc.fetchall():
        yc.execute(sql.SQL("update {}.{} r set {k} = h.yeni from _harita h where r.{k} = h.eski").format(
            sql.Identifier(rs), sql.Identifier(rt), k=sql.Identifier(rk)))
    yc.execute("drop table _harita, _tasinan")
    return len(harita)


def birlestir(args) -> int:
    """Geçmiş kişilere dokunmadan geri kalan herkesi Tokyo'dan yeniler."""
    onay_iste(args, YENI_REF)
    kesim = args.kesim or GECIS_KESIM
    bas = time.monotonic()
    with baglan("eski", anlik=True) as eski, baglan("yeni") as yeni:
        ec, yc = eski.cursor(), yeni.cursor()

        # 1) Kümeler.
        ec.execute("select id::text from auth.users")
        tokyo = {x for (x,) in ec.fetchall()}
        # İki iz: son giriş zamanı (kopyayla Tokyo'nun kesimdeki değeri geldi;
        # büyüğü Frankfurt'ta giriş demektir, çıkış yapınca da kalır) ve oturum.
        yc.execute("""select id::text, created_at > %(k)s::timestamptz,
                             coalesce(last_sign_in_at > %(k)s::timestamptz, false)
                        from auth.users""", {"k": kesim})
        satirlar = yc.fetchall()
        frankfurt = {u: yeni_kayit for u, yeni_kayit, _ in satirlar}
        yc.execute("select distinct user_id::text from auth.sessions where created_at > %s::timestamptz", (kesim,))
        gecmis = sorted({x for (x,) in yc.fetchall() if x in frankfurt}
                        | {u for u, yeni_kayit, girdi in satirlar if yeni_kayit or girdi})
        yenile = sorted(tokyo - set(gecmis))
        silinmis = sorted(u for u, yeni_kayit in frankfurt.items()
                          if u not in tokyo and u not in gecmis)
        print(f"Geçmiş kişi (dokunulmaz): {len(gecmis)}  ·  Tokyo'dan yenilenecek: {len(yenile)}"
              f"  ·  Tokyo'da silinmiş, Frankfurt'tan da silinecek: {len(silinmis)}")
        if args.gecmis_sayisi is not None and args.gecmis_sayisi != len(gecmis):
            sys.exit(f"Geçmiş kişi sayısı {len(gecmis)}, beklenen {args.gecmis_sayisi} — DURDU. Hiçbir şey yazılmadı.")

        # Geçmiş kişinin kesimden sonra TOKYO'ya yazdıkları (ör. Android'den):
        # bunlar taşınmaz. Durdurmaz, söyler.
        if gecmis:
            lit = sql.SQL("{}::uuid[]").format(sql.Literal(gecmis))
            ec.execute(sql.SQL("select count(*) from auth.users "
                               "where last_sign_in_at > %s::timestamptz and id = any({})").format(lit), (kesim,))
            tokyoda = ec.fetchone()[0]
            if tokyoda:
                print(f"  ! {tokyoda} geçmiş kişi kesimden sonra Tokyo'da da giriş yapmış — "
                      "Tokyo'da yaptıkları TAŞINMAZ (Frankfurt'taki hâlleri kalır).")

        yc.execute("set local session_replication_role = replica")
        liste = tablolar(ec)
        for sema, tablo in liste:
            if not tablo_var_mi(yc, sema, tablo):
                sys.exit(f"{sema}.{tablo}: Frankfurt'ta yok — önce `kontrol`. Hiçbir şey yazılmadı.")
            k, h = kolonlar(ec, sema, tablo), kolonlar(yc, sema, tablo)
            if any(c not in h for c in k):
                sys.exit(f"{sema}.{tablo}: kolon uyuşmazlığı — önce `kontrol`. Hiçbir şey yazılmadı.")

        # 2) Frankfurt'tan sil: yenilenecek + silinmiş hesapların satırları ve
        #    ortak tablolar. Geçmiş kişinin satırı (ya da onunla ortak satır) kalır.
        sil = sorted(set(yenile) | set(silinmis))
        ukol: dict[tuple[str, str], list[str]] = {}
        silinen = 0
        for sema, tablo in liste:
            if sema != "public":
                continue
            ukol[(sema, tablo)] = kullanici_kolonlari(ec, sema, tablo)
            ad = sql.SQL("{}.{}").format(sql.Identifier(sema), sql.Identifier(tablo))
            kosul = _hepsi_kumede(ukol[(sema, tablo)], sil) if ukol[(sema, tablo)] else sql.SQL("true")
            yc.execute(sql.SQL("delete from {} where {}").format(ad, kosul))
            silinen += yc.rowcount
        for tablo in AUTH_ARTIKLARI:
            if tablo_var_mi(yc, "auth", tablo):
                kol = "id" if tablo == "users" else "user_id"
                yc.execute(sql.SQL("select 1 from information_schema.columns where table_schema='auth' "
                                   "and table_name={} and column_name={}").format(sql.Literal(tablo), sql.Literal(kol)))
                if yc.fetchone():
                    yc.execute(sql.SQL("delete from auth.{} where {}::text = any({}::text[])").format(
                        sql.Identifier(tablo), sql.Identifier(kol), sql.Literal(sil)))
                    silinen += yc.rowcount

        # 3) Sayı çakışmaları — kopyadan ÖNCE (gelen satırlar eski numarayı alacak).
        numara = []
        for sema, tablo in liste:
            if sema != "public" or not ukol[(sema, tablo)]:
                continue
            pk = _tekil_sayi_anahtari(yc, sema, tablo)
            if pk:
                n = _yeniden_numarala(yc, ec, sema, tablo, pk, gecmis, ukol[(sema, tablo)], yenile)
                if n:
                    numara.append((f"{sema}.{tablo}", n))

        # 4) Kopyala.
        ozet = []
        lit = sql.SQL("{}::uuid[]").format(sql.Literal(yenile))
        for sema, tablo in liste:
            ad = sql.SQL("{}.{}").format(sql.Identifier(sema), sql.Identifier(tablo))
            ortak = list(kolonlar(ec, sema, tablo))
            if sema == "auth":
                kol = "id" if tablo == "users" else "user_id"
                kosul = sql.SQL("{} = any({})").format(sql.Identifier(kol), lit)
            elif ukol[(sema, tablo)]:
                kosul = _hepsi_kumede(ukol[(sema, tablo)], yenile)
            else:
                kosul = sql.SQL("true")
            secim = sql.SQL(", ").join(map(sql.Identifier, ortak))
            with ec.copy(sql.SQL("copy (select {} from {} where {}) to stdout").format(secim, ad, kosul)) as cikis, \
                 yc.copy(sql.SQL("copy {} ({}) from stdin").format(ad, secim)) as giris:
                for parca in cikis:
                    giris.write(parca)
            beklenen, eklenen = ec.rowcount, yc.rowcount
            if eklenen != beklenen:
                yeni.rollback()
                sys.exit(f"{sema}.{tablo}: {beklenen} beklenen, {eklenen} yazıldı — GERİ ALINDI.")
            ozet.append((f"{sema}.{tablo}", eklenen))

        # 5) Diziler en büyük değerin ötesine (iki tarafın da).
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

        # 6) Denetim: her Tokyo hesabı ya geçmiş kişi ya da Frankfurt'ta.
        yc.execute("select count(*) from auth.users where id::text = any(%s)", (yenile,))
        gelen = yc.fetchone()[0]
        yc.execute("select count(*) from auth.users where id::text = any(%s)", (gecmis,))
        kalan = yc.fetchone()[0]
        if gelen != len(yenile) or kalan != len(gecmis):
            yeni.rollback()
            sys.exit(f"Hesap denetimi tutmadı (gelen {gelen}/{len(yenile)}, geçmiş {kalan}/{len(gecmis)}) — GERİ ALINDI.")

        for ad_, n in ozet:
            if n:
                print(f"  {ad_:46} {n:>9}")
        print(f"  Frankfurt'tan silinen satır: {silinen}")
        for ad_, n in numara:
            print(f"  yeni numara (çakışma): {ad_} {n} satır")
        if args.kuru:
            yeni.rollback()
            print(f"\nKURU KOŞU TEMİZ — hiçbir şey yazılmadı ({time.monotonic() - bas:.1f} sn).")
            return 0
        yeni.commit()
    print(f"\nBİRLEŞTİRİLDİ: {len(gecmis)} geçmiş kişiye dokunulmadı, {len(yenile)} hesap Tokyo'dan "
          f"yenilendi ({time.monotonic() - bas:.1f} sn).")
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
                  ("tasi", tasi), ("tek-kullanici", tek_kullanici), ("birlestir", birlestir),
                  ("tokyo-kapat", tokyo_kapat), ("tokyo-ac", tokyo_ac)]:
        s = alt.add_parser(ad)
        s.add_argument("--onay", default="")
        s.add_argument("--email", default="")
        s.add_argument("--ortaklarla", action="store_true",
                       help="tek-kullanici: ortaklık kurduğu hesapları da taşı")
        s.add_argument("--kuru", action="store_true",
                       help="birlestir: her şeyi yap, raporla, GERİ AL")
        s.add_argument("--kesim", default="",
                       help=f"birlestir: geçmiş kişi sınırı (varsayılan {GECIS_KESIM})")
        s.add_argument("--gecmis-sayisi", type=int, default=None,
                       help="birlestir: beklenen geçmiş kişi sayısı; tutmazsa durur")
        s.set_defaults(f=f)
    args = p.parse_args()
    if TEST:
        print(f"[TEST MODU] kaynak={ESKI_REF} hedef={YENI_REF}")
    return args.f(args)


if __name__ == "__main__":
    sys.exit(main())
