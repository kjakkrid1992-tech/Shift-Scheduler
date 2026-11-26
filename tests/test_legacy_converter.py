import importlib.util
import tempfile
import unittest
from pathlib import Path
from openpyxl import Workbook

spec = importlib.util.spec_from_file_location('legacy', Path(__file__).resolve().parents[1] / 'scripts' / 'prepare-legacy-payroll.py')
legacy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(legacy)

class ArchiveTest(unittest.TestCase):
    def fixture(self, path, *, net=900.50, formula=False, duplicate=False, unnamed=False):
        w = Workbook()
        s = w.active
        s.title = 'Synthetic'
        block = [
            [legacy.TITLE], ['ประจำเดือน', 'มกราคม'],
            ['ชื่อ/สกุล' if not unnamed else None, 'Synthetic Person' if not unnamed else None, 'วันที่จ่าย(DATE) 25/01/2567'],
            ['ตำแหน่ง', 'ทดสอบ'], ['รายได้','จำนวน','รายการหัก','จำนวน'],
            ['ค่าแรง', '=500+500.50' if formula else 1000.50, 'เงินเบิก', 100],
            ['รวมรายได้',1000.50,'รวมรายการหัก',100], ['เงินรับสุทธิ',None,None,net]
        ]
        for row in block * (2 if duplicate else 1):
            s.append(row)
        w.create_sheet('แบบฟอร์ม PAY SLIP')
        w.save(path)
        w.close()

    def test_reconcile_and_keep_unnamed_unlinked(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'synthetic.xlsx'
            self.fixture(path, unnamed=True)
            result = legacy.convert(path)
            self.assertEqual(len(result['records']),1)
            r = result['records'][0]
            self.assertEqual((r['income_satang'],r['deduction_satang'],r['net_satang']),(100050,10000,90050))
            self.assertEqual(r['source_name'],'')
            self.assertEqual(len(result['skipped']),1)

    def test_reject_mismatch_cacheless_formula_duplicate(self):
        with tempfile.TemporaryDirectory() as d:
            path = Path(d) / 'synthetic.xlsx'
            for options, pattern in [({'net':901},'do not reconcile'),({'formula':True},'formula cache absent'),({'duplicate':True},'duplicate')]:
                self.fixture(path, **options)
                with self.assertRaisesRegex(ValueError,pattern):
                    legacy.convert(path)

if __name__ == '__main__':
    unittest.main()
