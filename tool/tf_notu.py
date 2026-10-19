#!/usr/bin/env python3
"""TestFlight "What to Test" metnini build'e giren PR'lardan üretir.

yasin (2026-10-19): "her yeni TF sürümü indirildiğinde o sürümle neyin test
edilmesi gerektiğini, neyi çözdüğünü açıkça yaz". Eskiden iç testçi
`whats_new.txt`'yi (İngilizce mağaza notu), harici testçi her build'de aynı
sabit cümleyi (`HARICI_VARSAYILAN_NOT`) görüyordu.

Kaynak: son BAŞARILI ios-testflight koşusunun commit'inden HEAD'e kadar
birleşen PR'lar. Her PR için başlık ("ne çözdü") ve gövdedeki
`## TestFlight'ta test et` bölümü ("ne test edilecek"). Bölüm yoksa PR'ın
uygulamayı değiştirip değiştirmediğine göre tek satır yazılır; uydurma test
adımı yazılmaz.

Ağ ya da API hatasında betik sessizce boş çıkar (exit 0, dosya yazmaz):
Fastfile o zaman eski metne düşer, upload bu yüzden düşmez.

Kullanım (CI): GITHUB_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA ortamda;
    python3 tool/tf_notu.py ios/fastlane/tf_notu.txt
"""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.request

LIMIT = 3900  # ASC "What to Test" 4000; kimlik satırına yer kalsın
BOLUM = re.compile(r"^#{2,3}\s*TestFlight'?ta test et\s*$", re.I | re.M)
SONRAKI_BASLIK = re.compile(r"^#{1,3}\s", re.M)
MERGE = re.compile(r"Merge pull request #(\d+)")
# Bu yollar dışında değişiklik yoksa PR uygulamaya dokunmamıştır.
UYGULAMA_YOLLARI = ("lib/", "ios/", "android/", "assets/", "pubspec")


def test_bolumu(govde: str) -> list[str]:
    """PR gövdesinden `## TestFlight'ta test et` bölümünün satırları."""
    if not govde:
        return []
    m = BOLUM.search(govde)
    if not m:
        return []
    kalan = govde[m.end():]
    s = SONRAKI_BASLIK.search(kalan)
    if s:
        kalan = kalan[: s.start()]
    satirlar = []
    for ham in kalan.splitlines():
        t = ham.strip()
        if not t or t.startswith("<!--"):
            continue
        t = re.sub(r"^[-*•]\s*(\[[ xX]\]\s*)?", "", t)
        satirlar.append(f"• {t}")
    return satirlar


def pr_metni(no: int, baslik: str, govde: str, dosyalar: list[str]) -> str | None:
    """Tek PR'ın testçi bloğu; testçiye söylenecek bir şey yoksa None.

    Metin testçi dilindedir (yasin 2026-10-19: "teknik bilgiden ziyade basit
    testerlarım anlayacağı şekilde"): PR numarası ve teknik başlık yazılmaz,
    bölümün kendisi "ne değişti + nasıl denenir" diye yazılır. Bölümü olmayan
    uygulama PR'ında başlık son çare olarak kalır, uydurma adım yazılmaz.
    """
    adimlar = test_bolumu(govde)
    if adimlar:
        return "\n".join(adimlar)
    if not any(f.startswith(UYGULAMA_YOLLARI) for f in dosyalar):
        return None
    return f"• {baslik.strip()}"


def notu_kur(prler: list[dict]) -> str:
    """prler: [{no, baslik, govde, dosyalar}] → What to Test metni."""
    if not prler:
        return ""
    bloklar = [b for p in prler
               if (b := pr_metni(p["no"], p["baslik"], p.get("govde") or "",
                                 p.get("dosyalar") or []))]
    if not bloklar:
        return ("Bu sürümde uygulamada görünen bir değişiklik yok. "
                "Her zamanki gibi kullanmaya devam et.")
    metin = "Bu sürümde bunları dene:\n\n" + "\n\n".join(bloklar)
    return metin if len(metin) <= LIMIT else metin[: LIMIT - 1] + "…"


def _api(yol: str) -> object:
    istek = urllib.request.Request(
        f"https://api.github.com/repos/{os.environ['GITHUB_REPOSITORY']}{yol}",
        headers={
            "Authorization": f"Bearer {os.environ['GITHUB_TOKEN']}",
            "Accept": "application/vnd.github+json",
        },
    )
    with urllib.request.urlopen(istek, timeout=20) as y:
        return json.load(y)


def prleri_topla() -> list[dict]:
    head = os.environ["GITHUB_SHA"]
    kosular = _api("/actions/workflows/ios-testflight.yml/runs?branch=main&status=success&per_page=1")
    onceki = (kosular.get("workflow_runs") or [{}])[0].get("head_sha")
    if onceki and onceki != head:
        commitler = _api(f"/compare/{onceki}...{head}").get("commits", [])
        mesajlar = [c["commit"]["message"] for c in commitler]
    else:
        mesajlar = [_api(f"/commits/{head}")["commit"]["message"]]
    numaralar = []
    for m in mesajlar:
        for no in MERGE.findall(m):
            if int(no) not in numaralar:
                numaralar.append(int(no))
    prler = []
    for no in numaralar[-15:]:
        pr = _api(f"/pulls/{no}")
        dosyalar = [f["filename"] for f in _api(f"/pulls/{no}/files?per_page=100")]
        prler.append({"no": no, "baslik": pr.get("title", ""), "govde": pr.get("body") or "",
                      "dosyalar": dosyalar})
    return prler


def main() -> int:
    hedef = sys.argv[1] if len(sys.argv) > 1 else "tf_notu.txt"
    try:
        metin = notu_kur(prleri_topla())
    except Exception as e:  # ağ/API: upload'ı düşürme, eski metne düş
        print(f"tf_notu: PR'lar okunamadı ({type(e).__name__}); eski metin kullanılacak")
        return 0
    if not metin:
        print("tf_notu: birleşen PR bulunamadı; eski metin kullanılacak")
        return 0
    with open(hedef, "w", encoding="utf-8") as f:
        f.write(metin)
    print(metin)
    return 0


if __name__ == "__main__":
    sys.exit(main())
