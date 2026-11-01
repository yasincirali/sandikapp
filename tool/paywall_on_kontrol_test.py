"""python3 -m unittest tool/paywall_on_kontrol_test.py"""
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("paywall_on_kontrol.py")
_spec = importlib.util.spec_from_file_location("paywall_on_kontrol", _yol)
pk = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(pk)

SECRETLER = set(pk.GEREKLI_SECRETLER)


def _durum(**k):
    d = {"kapi_acik": False, "haklar": [], "hediyesiz_eski": 0,
         "cron": {"active": True, "schedule": "15 9 * * *"}}
    d.update(k)
    return d


class PaywallOnKontrolTest(unittest.TestCase):
    def test_hediyesiz_eski_kullanici_engel_degil(self):
        # Hediye kalktı (2026-11-01): hak satırsız eski kullanıcı beklenen durum.
        m, kod = pk.rapor(_durum(hediyesiz_eski=12), SECRETLER, "2026-10-28")
        self.assertEqual(kod, 0)
        self.assertIn("Hediye yok", m)
        self.assertIn("hak satırsız 12", m)

    def test_hediye_satiri_varsa_uyarir_ama_engel_degil(self):
        h = [{"kaynak": "erken_kullanici", "sandbox": False, "adet": 40, "gecerli": 40,
              "ilk_bitis": "2027-01-26T00:00:00+00:00", "son_bitis": "2027-02-09T00:00:00+00:00"}]
        m, kod = pk.rapor(_durum(haklar=h), SECRETLER, None)
        self.assertEqual(kod, 0)
        self.assertIn("Hediye satırı var: 40", m)
        self.assertIn("bilinçli değilse sil", m)

    def test_secret_eksik_ve_cron_kapali_engel(self):
        m, kod = pk.rapor(_durum(cron={"active": False, "schedule": "15 9 * * *"}),
                          {"REVENUECAT_API_KEY"}, None)
        self.assertEqual(kod, 1)
        self.assertIn("EKSİK REVENUECAT_WEBHOOK_SECRET", m)
        self.assertIn("hediye yokken etkisiz", m)

    def test_kesim_sql_tirnak_kacirilir(self):
        self.assertIn("'2026-10-28T00:00:00+03'::timestamptz", pk.sorgu("2026-10-28T00:00:00+03"))
        self.assertIn("'a''b'", pk.sorgu("a'b"))
        self.assertIn("null is not null", pk.sorgu(None))


if __name__ == "__main__":
    unittest.main()


class SunucuAyari0172(unittest.TestCase):
    """0172: kesim ve acil kapatma sunucuda; rapor bunları okur, RC satırı yok."""

    def test_sunucu_kesimi_doluysa_bilgi_engel_degil(self):
        d = _durum(hediye_kesim="2026-11-05T00:00:00+03:00")
        m, kod = pk.rapor(d, set(pk.GEREKLI_SECRETLER), None)
        self.assertEqual(kod, 0)
        self.assertIn("uygulama bu değeri kullanmaz", m)

    def test_acil_kapali_engel_ve_rc_satiri_yok(self):
        d = _durum(acil_kapali=True)
        m, kod = pk.rapor(d, set(pk.GEREKLI_SECRETLER), None)
        self.assertEqual(kod, 1)
        self.assertIn("askıda", m)
        self.assertNotIn("Remote Config `paywall_enabled`", m)
