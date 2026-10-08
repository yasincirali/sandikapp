#!/usr/bin/env python3
"""Eurobond kaynaklarının yanıt BİÇİMİNİ döker (2026-10-08).

`kaynak_olcum.py` erişimi ve hızı ölçtü; ayrıştırıcı yazmak için yanıtın
kendisi gerekiyor ve bulut kabı bu hostlara gidemiyor. Yalnızca herkese
açık fiyat sayfaları/uçları; anahtar, çerez, secret yok.

2. tur: kupon oranının (katalog) anahtarsız bir kaynağı aranıyor.
"""
import re
import urllib.error
import urllib.request

UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/128.0 Safari/537.36')


def al(url):
    h = {'User-Agent': UA, 'Accept': 'application/json, text/html'}
    try:
        with urllib.request.urlopen(urllib.request.Request(url, headers=h), timeout=20) as r:
            return r.status, r.geturl(), r.read().decode('utf-8', 'ignore')
    except urllib.error.HTTPError as e:
        return e.code, url, (e.read() or b'').decode('utf-8', 'ignore')
    except Exception as e:
        return type(e).__name__, url, ''


ISIN = 'US900123DF45'
adaylar = [
    f'https://api.boerse-frankfurt.de/v1/global_search/limitedsearch/de?searchTerms={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/global_search/limitedsearch/en?searchTerms={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/data/instrument_information?slug={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/data/instrument_information?isin={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/data/bond_data?isin={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/data/master_data_bond?isin={ISIN}&mic=XFRA',
    f'https://api.boerse-frankfurt.de/v1/data/bond_master_data?isin={ISIN}&mic=XFRA',
    f'https://api.boerse-frankfurt.de/v1/data/master_data?isin={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/data/interest_rate_information?isin={ISIN}',
    f'https://api.boerse-frankfurt.de/v1/tradingview/symbols?symbol=XFRA:{ISIN}',
    f'https://api.boerse-frankfurt.de/v1/tradingview/search?query={ISIN}&limit=5',
    f'https://api.boerse-frankfurt.de/v1/tradingview/history?symbol=XFRA:{ISIN}&resolution=1D&from=1601510400&to=1759795200',
    f'https://live.deutsche-boerse.com/anleihe/{ISIN.lower()}',
    f'https://www.boerse-frankfurt.de/anleihe/{ISIN.lower()}',
    'https://www.ziraatbank.com.tr/en/retail/investment/eurobond',
]
for u in adaylar:
    kod, son, s = al(u)
    print('\n', u, '\n  ->', kod, son if son != u else '', len(s))
    if 'tradingview/history' in u:
        n = s.count(',') 
        print('  c uzunluğu ~', s[:80], '… t sayısı', len(re.findall(r'"t":\[([^\]]*)', s)[0].split(',')) if '"t":[' in s else 0)
        continue
    if s.lstrip().startswith('{') or s.lstrip().startswith('['):
        print('  ', s[:900].replace('\n', ' '))
    else:
        for m in re.finditer(r'(\d{1,2},\d{1,4}\s?%\s?\d{2}/\d{2})', s):
            print('   kupon ipucu:', re.sub(r'\s+', ' ', s[max(0, m.start() - 80):m.end() + 20]))
            break
        for anahtar in ['Kupon', 'Zinssatz', 'coupon', 'Coupon', 'Emissionsdatum', 'Erster Zinstermin']:
            i = s.find(anahtar)
            if i >= 0:
                print('  ', anahtar, '…', re.sub(r'<[^>]+>', ' ', s[i:i + 240]).replace('\n', ' ')[:200])
