#!/usr/bin/env python3
"""ABD hissesi ve eurobond fiyat kaynaklarının erişim/hız ölçümü (2026-10-08).

Neden: Claude bulut kabının ağ politikası finans hostlarının hepsini
reddediyor; karşılaştırma ancak gerçek bir sunucudan yapılabilir. Bu betik
GitHub Actions koşucusundan (`kaynak-olcum.yml`) her kaynağa birkaç kez
gider; durum kodu, medyan süre, boyut ve verinin İŞE YARAR olup olmadığını
(ISIN sayısı, nokta sayısı) yazar.

Anahtar KULLANMAZ: anahtarlı kaynaklar (Finnhub, Tiingo, Twelve Data)
yalnızca kapının kapalı olduğunu (401/403) gösterir. Supabase edge IP'leri
GitHub koşucusundan farklıdır; Yahoo'nun IP bazlı sınırı orada başka
davranabilir — o ölçüm ilk cron turunda yapılır.
"""
import json
import re
import statistics
import sys
import time
import urllib.error
import urllib.request

UA_TARAYICI = (
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/128.0 Safari/537.36'
)
UA_SEC = 'sandik-portfoy github.com/yasincirali/sandikapp'

ISIN = re.compile(r'\b(?:US|XS|TR)[A-Z0-9]{9}\d\b')


def _say_isin(b: bytes) -> str:
    s = set(ISIN.findall(b.decode('utf-8', 'ignore')))
    return f'{len(s)} ISIN'


def _yahoo_nokta(b: bytes) -> str:
    try:
        r = json.loads(b)['chart']['result'][0]
        ts = r.get('timestamp') or []
        ev = r.get('events') or {}
        return f"{len(ts)} nokta, temettü {len(ev.get('dividends', {}))}, bölünme {len(ev.get('splits', {}))}"
    except Exception:
        return 'çözülemedi'


def _yahoo_spark(b: bytes) -> str:
    try:
        j = json.loads(b)
        if 'spark' in j:
            return f"{len(j['spark']['result'] or [])} sembol"
        return f'{len(j)} sembol'
    except Exception:
        return 'çözülemedi'


def _satir(b: bytes) -> str:
    n = b.count(b'\n')
    return f'{n} satır'


def _json_uzunluk(b: bytes) -> str:
    try:
        j = json.loads(b)
        if isinstance(j, dict) and 'data' in j:
            d = j['data']
            if isinstance(d, dict) and 'tradesTable' in d:
                return f"{len((d['tradesTable'] or {}).get('rows') or [])} gün"
            if isinstance(d, dict) and 'primaryData' in d:
                return f"son {d['primaryData'].get('lastSalePrice')}"
            if isinstance(d, list):
                return f'{len(d)} kayıt'
            return 'data var'
        if isinstance(j, dict):
            return f'{len(j)} anahtar'
        return f'{len(j)} kayıt'
    except Exception:
        return 'json değil'


def _bas(b: bytes) -> str:
    return b[:60].decode('utf-8', 'ignore').replace('\n', ' ')


SEMBOLLER20 = ','.join([
    'AAPL', 'MSFT', 'NVDA', 'AMZN', 'GOOGL', 'META', 'TSLA', 'BRK-B', 'JPM', 'V',
    'SPY', 'QQQ', 'VOO', 'VTI', 'KO', 'PLTR', 'AMD', 'NFLX', 'COST', 'AVGO',
])

KAYNAKLAR = [
    # (grup, ad, url, başlıklar, doğrulayıcı)
    ('ABD', 'Yahoo chart 1G (5dk)',
     'https://query1.finance.yahoo.com/v8/finance/chart/AAPL?range=1d&interval=5m',
     {'User-Agent': UA_TARAYICI}, _yahoo_nokta),
    ('ABD', 'Yahoo chart 5Y günlük + temettü',
     'https://query1.finance.yahoo.com/v8/finance/chart/KO?range=5y&interval=1d&events=div%2Csplits',
     {'User-Agent': UA_TARAYICI}, _yahoo_nokta),
    ('ABD', 'Yahoo spark 20 sembol (toplu)',
     f'https://query1.finance.yahoo.com/v7/finance/spark?symbols={SEMBOLLER20}&range=1d&interval=5m',
     {'User-Agent': UA_TARAYICI}, _yahoo_spark),
    ('ABD', 'Yahoo quote v7 (crumb ister)',
     f'https://query1.finance.yahoo.com/v7/finance/quote?symbols={SEMBOLLER20}',
     {'User-Agent': UA_TARAYICI}, _bas),
    ('ABD', 'Nasdaq API anlık',
     'https://api.nasdaq.com/api/quote/AAPL/info?assetclass=stocks',
     {'User-Agent': UA_TARAYICI, 'Accept': 'application/json'}, _json_uzunluk),
    ('ABD', 'Nasdaq API geçmiş',
     'https://api.nasdaq.com/api/quote/AAPL/historical?assetclass=stocks&fromdate=2021-10-01&limit=9999',
     {'User-Agent': UA_TARAYICI, 'Accept': 'application/json'}, _json_uzunluk),
    ('ABD', 'Stooq CSV anlık',
     'https://stooq.com/q/l/?s=aapl.us&f=sd2t2ohlcv&h&e=csv',
     {'User-Agent': UA_TARAYICI}, _bas),
    ('ABD', 'Finnhub (anahtarsız)',
     'https://finnhub.io/api/v1/quote?symbol=AAPL',
     {'User-Agent': UA_TARAYICI}, _bas),
    ('Katalog', 'Nasdaq Trader nasdaqlisted',
     'https://www.nasdaqtrader.com/dynamic/SymDir/nasdaqlisted.txt',
     {'User-Agent': UA_TARAYICI}, _satir),
    ('Katalog', 'Nasdaq Trader otherlisted',
     'https://www.nasdaqtrader.com/dynamic/SymDir/otherlisted.txt',
     {'User-Agent': UA_TARAYICI}, _satir),
    ('Katalog', 'SEC company_tickers_exchange',
     'https://www.sec.gov/files/company_tickers_exchange.json',
     {'User-Agent': UA_SEC}, _json_uzunluk),
    ('Eurobond', 'Ziraat eurobond tablosu',
     'https://www.ziraatbank.com.tr/tr/bireysel/yatirim/eurobond',
     {'User-Agent': UA_TARAYICI}, _say_isin),
    ('Eurobond', 'İş Bankası eurobond',
     'https://www.isbank.com.tr/eurobond',
     {'User-Agent': UA_TARAYICI}, _say_isin),
    ('Eurobond', 'Deutsche Börse ürün sayfası',
     'https://live.deutsche-boerse.com/anleihe/us900123df45-tuerkei-republik-9-875-22-28',
     {'User-Agent': UA_TARAYICI}, _say_isin),
    ('Eurobond', 'Börse Frankfurt API (imzasız)',
     'https://api.boerse-frankfurt.de/v1/data/price_information/single?isin=US900123DF45&mic=XFRA',
     {'User-Agent': UA_TARAYICI, 'Accept': 'application/json'}, _bas),
    ('Eurobond', 'Börse Frankfurt API geçmiş (imzasız)',
     'https://api.boerse-frankfurt.de/v1/data/price_history?isin=US900123DF45&mic=XFRA'
     '&minDate=2025-10-01&maxDate=2026-10-07&limit=500&offset=0&cleanSplit=false'
     '&cleanPayout=false&cleanSubscription=false',
     {'User-Agent': UA_TARAYICI, 'Accept': 'application/json'}, _json_uzunluk),
    ('Kıyas', 'ABD Hazine getiri XML',
     'https://home.treasury.gov/resource-center/data-chart-center/interest-rates/pages/xml'
     '?data=daily_treasury_yield_curve&field_tdr_date_value_month=202610',
     {'User-Agent': UA_TARAYICI}, _say_isin),
    ('Kıyas', 'FRED DGS10 CSV',
     'https://fred.stlouisfed.org/graph/fredgraph.csv?id=DGS10',
     {'User-Agent': UA_TARAYICI}, _satir),
]

DENEME = 5


def olc(url, basliklar):
    t0 = time.perf_counter()
    try:
        req = urllib.request.Request(url, headers=basliklar)
        with urllib.request.urlopen(req, timeout=20) as r:
            b = r.read()
            return r.status, (time.perf_counter() - t0) * 1000, b
    except urllib.error.HTTPError as e:
        return e.code, (time.perf_counter() - t0) * 1000, e.read() or b''
    except Exception as e:  # zaman aşımı, DNS
        return type(e).__name__, (time.perf_counter() - t0) * 1000, b''


def main():
    satirlar = []
    for grup, ad, url, bas, dog in KAYNAKLAR:
        kodlar, sureler, son = [], [], b''
        for _ in range(DENEME):
            kod, ms, b = olc(url, bas)
            kodlar.append(str(kod))
            sureler.append(ms)
            if b:
                son = b
            time.sleep(0.5)
        basari = sum(1 for k in kodlar if k == '200')
        satirlar.append((grup, ad, f'{basari}/{DENEME}', ','.join(sorted(set(kodlar))),
                         round(statistics.median(sureler)), len(son),
                         dog(son) if son else '-'))
        print(f'[{grup}] {ad}: {kodlar} medyan {statistics.median(sureler):.0f} ms', flush=True)

    # Dayanıklılık: 40 ardışık Yahoo chart isteği (farklı semboller), 429 var mı?
    semboller = SEMBOLLER20.split(',') * 2
    kodlar, sureler = [], []
    for s in semboller:
        kod, ms, _ = olc(
            f'https://query1.finance.yahoo.com/v8/finance/chart/{s}?range=1mo&interval=1d',
            {'User-Agent': UA_TARAYICI})
        kodlar.append(str(kod))
        sureler.append(ms)
    satirlar.append(('ABD', 'Yahoo chart 40 ardışık istek',
                     f"{kodlar.count('200')}/40", ','.join(sorted(set(kodlar))),
                     round(statistics.median(sureler)), 0, f'p95 {sorted(sureler)[37]:.0f} ms'))

    tablo = ['| Grup | Kaynak | Başarı | Kodlar | Medyan ms | Bayt | Veri |',
             '|---|---|---|---|---|---|---|']
    for r in satirlar:
        tablo.append('| ' + ' | '.join(str(x) for x in r) + ' |')
    metin = '\n'.join(tablo)
    print('\n' + metin)
    print('\nJSON ' + json.dumps(satirlar, ensure_ascii=False))
    import os
    ozet = os.environ.get('GITHUB_STEP_SUMMARY')
    if ozet:
        with open(ozet, 'a', encoding='utf-8') as f:
            f.write('## Kaynak ölçümü\n\n' + metin + '\n')
    return 0


if __name__ == '__main__':
    sys.exit(main())
