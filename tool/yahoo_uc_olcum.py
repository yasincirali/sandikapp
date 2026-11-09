"""Hisse kotasyonunun iki Yahoo ucu: erişim, kısıtlama ve yüzde tanımı (2026-10-30).

Soru (müşteri raporu 30 Eki 13:15 #3, Ar-Ge 16:45 #1, yasin "yap"):
1. Uygulamanın toplu ucu `v7/finance/quote` bugün ne dönüyor? (çerez/crumb
   istediği için 401 döndüğü biliniyor, ölçülmedi.)
2. Toplu uç kaldırılırsa her fiyat turunda hisse başına bir `v8/finance/chart`
   isteği gider. 20 hisseli tek telefon = tek IP'den 20 paralel istek:
   kaç tanesi 429 (ya da başka hata) alıyor, en yavaşı ne kadar?
3. v7 `regularMarketChangePercent` ile grafik yanıtının `chartPreviousClose`'undan
   hesaplanan yüzde (uygulamanın yedek yolu, `yahooGrafikKotasyonu`) aynı
   referansı mı kullanıyor? Fark varsa piyasa bandı ile varlık sayfası ayrışır.

Uygulamanın isteğini birebir taklit eder (aynı host, parametre ve User-Agent).
Bulut kabı Yahoo'ya çıkamadığı için GitHub Actions'tan koşar
(`kaynak-olcum.yml`). Salt okunur, anahtarsız; log herkese açık, bu yüzden
yalnız HTTP kodu, süre ve yüzde farkı yazılır.

Seans içinde (10:00–18:00 TR) ve birkaç saat arayla birkaç kez koşulmalı:
seans dışında iki yüzde aynı çıkabilir, kısıtlama da saate göre değişir.
"""
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone

# lib/services/price_service.dart › PriceService._ua ile aynı.
UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) '
      'AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0.0.0 Safari/537.36')

# 20 hisseli bir portföy: BIST 30'dan likit semboller.
SEMBOLLER = [
    'THYAO.IS', 'GARAN.IS', 'AKBNK.IS', 'ASELS.IS', 'BIMAS.IS',
    'KCHOL.IS', 'SAHOL.IS', 'TUPRS.IS', 'EREGL.IS', 'SISE.IS',
    'YKBNK.IS', 'ISCTR.IS', 'FROTO.IS', 'TCELL.IS', 'PGSUS.IS',
    'TOASO.IS', 'KOZAL.IS', 'PETKM.IS', 'SASA.IS', 'HEKTS.IS',
]


def istek(url):
    """(HTTP kodu, süre sn, gövde ya da None). Hata gövdesi okunmaz."""
    req = urllib.request.Request(
        url, headers={'User-Agent': UA, 'Accept': 'application/json'})
    t0 = time.time()
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return r.status, time.time() - t0, json.loads(r.read())
    except urllib.error.HTTPError as e:
        return e.code, time.time() - t0, None
    except Exception as e:  # noqa: BLE001 — zaman aşımı, bağlantı
        return type(e).__name__, time.time() - t0, None


def v7():
    q = urllib.parse.urlencode({
        'symbols': ','.join(SEMBOLLER),
        'lang': 'en-US',
        'region': 'US',
        'corsDomain': 'finance.yahoo.com',
        'fields': 'regularMarketPrice,currency,shortName,longName,'
                  'regularMarketChangePercent',
    })
    kod, sure, govde = istek(f'https://query1.finance.yahoo.com/v7/finance/quote?{q}')
    yuzde = {}
    if govde:
        for r in (govde.get('quoteResponse') or {}).get('result') or []:
            p = r.get('regularMarketChangePercent')
            if p is not None:
                yuzde[r['symbol'].upper()] = float(p)
    return kod, sure, yuzde


def grafik(sym, interval):
    q = urllib.parse.urlencode(
        {'interval': interval, 'range': '1d', 'includePrePost': 'false'})
    kod, sure, govde = istek(
        f'https://query1.finance.yahoo.com/v8/finance/chart/{sym}?{q}')
    yuzde = None
    if govde:
        res = (govde.get('chart') or {}).get('result') or []
        m = (res[0].get('meta') or {}) if res else {}
        fiyat, onceki = m.get('regularMarketPrice'), m.get('chartPreviousClose')
        # price_service.dart › yahooGrafikKotasyonu ile aynı tanım.
        if fiyat and onceki and onceki > 0:
            yuzde = (fiyat / onceki - 1) * 100
    return sym, kod, sure, yuzde


def paralel(interval):
    with ThreadPoolExecutor(max_workers=len(SEMBOLLER)) as ex:
        return list(ex.map(lambda s: grafik(s, interval), SEMBOLLER))


def kod_dagilimi(sonuclar):
    say = {}
    for _, kod, _, _ in sonuclar:
        say[str(kod)] = say.get(str(kod), 0) + 1
    return ', '.join(f'{k}×{v}' for k, v in sorted(say.items()))


def main():
    tr = datetime.now(timezone.utc) + timedelta(hours=3)
    satirlar = [f'## Yahoo uçları — {tr:%Y-%m-%d %H:%M} TR', '']
    if tr.weekday() >= 5 or not (10 <= tr.hour < 18):
        satirlar += ['> Seans dışı: yüzde karşılaştırması anlamlı olmayabilir.', '']

    v7_kod, v7_sure, v7_yuzde = v7()
    satirlar += [
        '| Uç | Sonuç | Süre |', '|---|---|---|',
        f'| v7 toplu (20 sembol, 1 istek) | HTTP {v7_kod}, {len(v7_yuzde)} yüzde | {v7_sure:.2f} sn |',
    ]
    g1 = []
    for interval, ad in (('1d', 'kotasyon yedeği'), ('5m', 'gün içi seri')):
        t0 = time.time()
        s = paralel(interval)
        if interval == '1d':
            g1 = s
        en_yavas = max(x[2] for x in s)
        satirlar.append(
            f'| v8 grafik {interval} ({ad}, 20 paralel) | {kod_dagilimi(s)} | '
            f'toplam {time.time() - t0:.2f} sn, en yavaş {en_yavas:.2f} sn |')

    satirlar += ['', '### İki yüzde tanımı (v7 − grafik)', '']
    farklar = []
    for sym, _, _, gy in g1:
        vy = v7_yuzde.get(sym.upper())
        if vy is not None and gy is not None:
            farklar.append((abs(vy - gy), sym, vy, gy))
    if not farklar:
        satirlar.append('Karşılaştırılacak çift yok (v7 yüzde dönmedi).')
    else:
        farklar.sort(reverse=True)
        satirlar.append(
            f'{len(farklar)} sembol; en büyük fark {farklar[0][0]:.3f} puan, '
            f'0,01 puandan büyük fark: {sum(1 for f in farklar if f[0] > 0.01)}')
        satirlar += ['', '| Sembol | v7 % | grafik % | fark |', '|---|---|---|---|']
        for f, sym, vy, gy in farklar[:5]:
            satirlar.append(f'| {sym} | {vy:.3f} | {gy:.3f} | {f:.3f} |')

    metin = '\n'.join(satirlar)
    print(metin)
    ozet = os.environ.get('GITHUB_STEP_SUMMARY')
    if ozet:
        with open(ozet, 'a', encoding='utf-8') as f:
            f.write(metin + '\n')


if __name__ == '__main__':
    main()
