"""python3 -m unittest tool/db_boyut_test.py"""
import importlib.util
import pathlib
import unittest

_yol = pathlib.Path(__file__).with_name("db_boyut.py")
_spec = importlib.util.spec_from_file_location("db_boyut", _yol)
db = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(db)

MB = 1024 * 1024


class DbBoyutTest(unittest.TestCase):
    def _s(self, **k):
        s = {"db": 81 * MB, "storage": 0, "aktif_30g": 14, "tablolar": [], "api": None}
        s.update(k)
        return s

    def test_rahat(self):
        metin, kod = db.rapor(self._s())
        self.assertEqual(kod, 0)
        self.assertIn("🟢 Rahat.", metin)
        self.assertIn("Aktif kullanıcı", metin)

    def test_olculemeyen_uydurulmaz(self):
        metin, _ = db.rapor(self._s())
        self.assertIn("Dışarı trafik (egress) | panelden elle bak", metin)
        self.assertIn("Edge Function çağrısı | panelden elle bak", metin)
        self.assertIn("API istekleri, 7 gün | panelden elle bak", metin)

    def test_storage_yuzde_doksan_kirmizi(self):
        _, kod = db.rapor(self._s(storage=int(0.95 * 1024 * MB)))
        self.assertEqual(kod, 1)

    def test_mau_yuzde_yetmis_sari_is_dusmez(self):
        metin, kod = db.rapor(self._s(aktif_30g=36_000))
        self.assertEqual(kod, 0)
        self.assertIn("🟡", metin)

    def test_db_esigi_korunur(self):
        _, kod = db.rapor(self._s(db=460 * MB))
        self.assertEqual(kod, 1)

    def test_api_sayilari_yazilir(self):
        metin, _ = db.rapor(self._s(api={"total_rest_requests": 12345}))
        self.assertIn("API istekleri, 7 gün (rest) | 12.345", metin)


if __name__ == "__main__":
    unittest.main()
