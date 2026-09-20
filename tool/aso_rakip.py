"""Rakip metadata madenciliği — iTunes Search API (anahtarsız, herkese açık).

Bir sorgu için ilk N uygulamanın adı, puanı, yorum sayısı, çıkış tarihi ve
açıklamasının ilk satırları. Subtitle/keyword alanı API'de yok; başlık
(`trackName`) ve açıklama başlangıcı rakiplerin hangi kelimeleri hedeflediğini
yeterince gösterir.

Kullanım:
    python tool/aso_rakip.py "portföy takibi" 15
    python tool/aso_rakip.py --kendi          # sandık'ın kendi kaydı
"""

import json
import sys
import urllib.parse
import urllib.request
from collections import Counter

APP_ID = 6786837699
COUNTRY = "tr"


def ara(term, limit):
    q = urllib.parse.urlencode(
        {"term": term, "country": COUNTRY, "entity": "software", "limit": limit}
    )
    with urllib.request.urlopen("https://itunes.apple.com/search?" + q, timeout=30) as r:
        return json.loads(r.read().decode("utf-8"))["results"]


def kendi():
    q = urllib.parse.urlencode({"id": APP_ID, "country": COUNTRY})
    with urllib.request.urlopen("https://itunes.apple.com/lookup?" + q, timeout=30) as r:
        d = json.loads(r.read().decode("utf-8"))["results"]
    if not d:
        print("kayıt yok")
        return
    a = d[0]
    print("trackName     :", a.get("trackName"))
    print("version       :", a.get("version"), "| released:", a.get("currentVersionReleaseDate"))
    print("rating        :", a.get("averageUserRating"), "×", a.get("userRatingCount"))
    print("genres        :", a.get("genres"))
    print("languages     :", a.get("languageCodesISO2A"))
    print("minOs         :", a.get("minimumOsVersion"))
    print("description   :")
    for satir in (a.get("description") or "").splitlines()[:6]:
        print("   ", satir)
    print("releaseNotes  :", (a.get("releaseNotes") or "")[:200].replace("\n", " | "))


def main(argv):
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    if argv and argv[0] == "--kendi":
        kendi()
        return
    term = argv[0] if argv else "portföy takibi"
    limit = int(argv[1]) if len(argv) > 1 else 15
    rows = ara(term, limit)
    kelime = Counter()
    print(f"# '{term}' — ilk {len(rows)} (App Store {COUNTRY.upper()})")
    print(f"{'#':>2} {'puan':>4} {'yorum':>6} {'çıkış':<10} ad")
    for i, a in enumerate(rows, 1):
        ad = a.get("trackName", "")
        print(
            f"{i:>2} {a.get('averageUserRating', 0):>4.1f} {a.get('userRatingCount', 0):>6} "
            f"{(a.get('releaseDate') or '')[:10]:<10} {ad}"
        )
        for w in ad.lower().replace(":", " ").replace("-", " ").replace("&", " ").replace(",", " ").split():
            if len(w) > 2:
                kelime[w] += 1
    print("\nBaşlıkta en sık kelimeler:")
    for w, c in kelime.most_common(20):
        print(f"  {c:>2}  {w}")


if __name__ == "__main__":
    main(sys.argv[1:])
