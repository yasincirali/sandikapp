"""python3 -m unittest tool/magaza_yorumlari_test.py"""
import datetime as dt
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("magaza_yorumlari.py")
_spec = importlib.util.spec_from_file_location("magaza_yorumlari", _yol)
my = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(my)

T = dt.datetime(2026, 10, 19, tzinfo=dt.timezone.utc)


class MagazaYorumlariTest(unittest.TestCase):
    def test_hata_kelimesi(self):
        self.assertTrue(my.hata_mi("Uygulama açılmıyor"))
        self.assertTrue(my.hata_mi("Fon fiyatı GÜNCELLENMİYOR"))
        self.assertFalse(my.hata_mi("Harika uygulama"))

    def test_taslak_puana_gore(self):
        self.assertIn("teşekkürler", my.taslak(5, "Süper").lower())
        self.assertIn("üzgünüz", my.taslak(1, "Beğenmedim"))
        self.assertIn("inceliyoruz", my.taslak(5, "güzel ama çöküyor"))

    def test_rapor_gonderilmedi_ve_adsiz(self):
        y = [{"magaza": "App Store", "puan": 1, "tarih": T, "surum": None,
              "ulke": "TUR", "metin": "Giriş yapamıyorum"}]
        m = my.rapor(y, ["Google Play"], 8)
        self.assertIn("GÖNDERİLMEDİ", m)
        self.assertIn("Google Play atlandı", m)
        self.assertIn("## Hata bildirimleri\n\n- App Store · 1★", m)

    def test_bos(self):
        self.assertIn("Bu dönemde yeni yorum yok.", my.rapor([], [], 8))


if __name__ == "__main__":
    unittest.main()
