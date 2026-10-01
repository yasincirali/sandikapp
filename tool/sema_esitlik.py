"""Tokyo ile Frankfurt şeması birebir aynı mı? (2026-09-28)

Kullanıcı kuralı: iki sunucu hep senkron gider — bir migration birine
uygulandıysa öbürüne de uygulanır. Bu betik `supabase/audit/sema_parmak_izi.sql`
sorgusunu İKİ projede salt okunur koşar ve farkı listeler. Fark yoksa 0,
varsa 1 ile çıkar (CI ve `supabase-deploy.yml` bunu kapı olarak kullanır).

Yerelde:  python tool/sema_esitlik.py [--ayrinti]
  (--ayrinti: "tanım farklı" satırlarının iki taraftaki metnini diff'ler.)
  (supabase CLI oturumu açık olmalı; betik sırayla iki projeye `link` olur,
  sonda eski bağlantıyı geri kurar. Yazma YOK.)

CI'da:    (GITHUB_ACTIONS) SUPABASE_ACCESS_TOKEN ile Management API'ye gider.
  Yerelde ortamda token olsa bile CLI oturumu kullanılır: 2026-09-28'de
  terminalde kalmış kısıtlı bir taşıma token'ı (salt okunur kapsam) betiği
  403'e düşürdü. API yolunu yerelde zorlamak için --api.

`cron_aktif` farkı hata DEĞİLDİR: geçişe kadar Frankfurt'ta cron kapalı
olmak zorunda (iki sunucu aynı kişiye iki push atmasın). Ayrı raporlanır.
"""
import difflib
import io
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding="utf-8", errors="replace")

KOK = Path(__file__).resolve().parent.parent
SORGU = (KOK / "supabase/audit/sema_parmak_izi.sql").read_text(encoding="utf-8")
PROJELER = {
    "tokyo": os.environ.get("TOKYO_REF", "ybdbzouzhzwthjgwlbmk"),
    "frankfurt": os.environ.get("FRANKFURT_REF", "ynwymnpdiwudrlxfrmuo"),
}
# Farkı hata sayılmayan türler (bkz. modül açıklaması).
BILGI_TURLERI = {"cron_aktif"}


def satirlari_coz(metin: str) -> list[dict]:
    """CLI çıktısı iki biçimde gelebiliyor: düz dizi ya da {rows: [...]}."""
    i = min((k for k in (metin.find("["), metin.find("{")) if k >= 0), default=-1)
    if i < 0:
        raise ValueError("JSON bulunamadı: " + metin[:200])
    veri = json.loads(metin[i:])
    return veri["rows"] if isinstance(veri, dict) else veri


def api_ile(ref: str, token: str) -> list[dict]:
    istek = urllib.request.Request(
        f"https://api.supabase.com/v1/projects/{ref}/database/query",
        data=json.dumps({"query": SORGU}).encode(),
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(istek, timeout=120) as y:
            return satirlari_coz(y.read().decode())
    except urllib.error.HTTPError as h:
        # Gövde API'nin yetki mesajıdır (eksik izin adı); token içermez.
        raise SystemExit(f"{ref}: Management API HTTP {h.code} — {h.read().decode(errors='replace')[:300]}")


def cli_ile(ref: str) -> list[dict]:
    # CLI de SUPABASE_ACCESS_TOKEN'ı okur ve oturumdaki token'ın ÖNÜNE koyar;
    # kısıtlı bir token ortamda kaldıysa link bile 403 alır. Alt sürece geçme.
    ortam = {k: v for k, v in os.environ.items() if k != "SUPABASE_ACCESS_TOKEN"}
    kos = lambda *a: subprocess.run(["supabase", *a], capture_output=True, cwd=KOK, env=ortam)
    b = kos("link", "--project-ref", ref)
    if b.returncode != 0:
        raise RuntimeError(f"link {ref}: {b.stderr.decode(errors='replace')[-300:]}")
    s = kos("db", "query", "--linked", "-f", "supabase/audit/sema_parmak_izi.sql",
            "--output-format", "json")
    if s.returncode != 0:
        raise RuntimeError(f"sorgu {ref}: {s.stderr.decode(errors='replace')[-300:]}")
    return satirlari_coz(s.stdout.decode("utf-8", errors="replace"))


def main() -> int:
    api = bool(os.environ.get("GITHUB_ACTIONS")) or "--api" in sys.argv
    token = os.environ.get("SUPABASE_ACCESS_TOKEN") if api else None
    if api and not token:
        raise SystemExit("API modu için SUPABASE_ACCESS_TOKEN gerekli.")
    # Frankfurt ayrı hesapta olabilir (2026-10-01: ortak token 403); `_EU`
    # varsa onunla, yoksa ortak token'la sorgulanır.
    tokenlar = {"tokyo": token,
                "frankfurt": (os.environ.get("SUPABASE_ACCESS_TOKEN_EU") or token) if api else None}
    ref_dosyasi = KOK / "supabase/.temp/project-ref"
    onceki = ref_dosyasi.read_text().strip() if ref_dosyasi.exists() else None
    ayrinti = "--ayrinti" in sys.argv
    izler: dict[str, dict[tuple, str]] = {}
    tanimlar: dict[str, dict[tuple, str]] = {}
    try:
        for ad, ref in PROJELER.items():
            satirlar = api_ile(ref, tokenlar[ad]) if token else cli_ile(ref)
            izler[ad] = {(r["tur"], r["ad"]): r["ozet"] for r in satirlar}
            tanimlar[ad] = {(r["tur"], r["ad"]): r.get("tanim") or "" for r in satirlar}
            print(f"{ad:10} {len(satirlar)} satır")
    finally:
        if not token and onceki:
            subprocess.run(["supabase", "link", "--project-ref", onceki], capture_output=True, cwd=KOK,
                           env={k: v for k, v in os.environ.items() if k != "SUPABASE_ACCESS_TOKEN"})

    t, f = izler["tokyo"], izler["frankfurt"]
    farklar, bilgi = [], []
    for anahtar in sorted(set(t) | set(f)):
        a, b = t.get(anahtar), f.get(anahtar)
        if a == b:
            continue
        durum = ("yalnız Frankfurt'ta" if a is None else
                 "yalnız Tokyo'da" if b is None else "tanım farklı")
        if anahtar[0] == "cron_aktif":
            durum = (f"tokyo={tanimlar['tokyo'].get(anahtar)} "
                     f"frankfurt={tanimlar['frankfurt'].get(anahtar)}")
        (bilgi if anahtar[0] in BILGI_TURLERI else farklar).append((anahtar, durum))

    for (tur, ad), durum in bilgi:
        print(f"  bilgi  {tur:12} {ad:45} {durum}")
    if not farklar:
        print("\nŞEMA EŞİT — iki sunucu birebir aynı (cron açık/kapalı bayrağı hariç).")
        return 0
    print(f"\nŞEMA FARKLI — {len(farklar)} fark:")
    for (tur, ad), durum in farklar:
        print(f"  {tur:12} {ad:60} {durum}")
        if ayrinti and durum == "tanım farklı":
            fark = difflib.unified_diff(
                tanimlar["tokyo"][(tur, ad)].splitlines(),
                tanimlar["frankfurt"][(tur, ad)].splitlines(),
                "tokyo", "frankfurt", lineterm="", n=1)
            for satir in list(fark)[2:]:
                print("      " + satir)
    return 1


if __name__ == "__main__":
    sys.exit(main())
