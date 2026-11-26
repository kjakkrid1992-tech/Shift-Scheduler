"""Convert the original BAAN JERGUN payslip workbook to a local, reconciled archive.
No database access. Never commit the output or original workbook to Git.
"""
import argparse
import hashlib
import json
from decimal import Decimal, ROUND_HALF_UP
from pathlib import Path

from openpyxl import load_workbook

TITLE = 'ใบแจ้งเงินเดือน (PAY SLIP)'
REFERENCE = {'บัตรลงเวลาบันทึกมือตามจริง', 'แบบฟอร์ม PAY SLIP', 'คำนวณค่าแรง บันทึกกันลืม'}


def txt(value):
    return '' if value is None else str(value).strip()


def satang(value):
    if isinstance(value, bool) or not isinstance(value, (int, float, Decimal)):
        raise ValueError('Expected cached numeric amount')
    n = Decimal(str(value)) * 100
    if not n.is_finite():
        raise ValueError('Non-finite amount')
    cents = int(n.quantize(Decimal('1'), rounding=ROUND_HALF_UP))
    if abs(n - cents) > Decimal('0.00001') or abs(cents) > 1_000_000_000:
        raise ValueError('Amount outside supported satang precision/range')
    return cents


def convert(path):
    cached = load_workbook(path, data_only=True, read_only=False)
    formulas = load_workbook(path, data_only=False, read_only=False)
    records, skipped = [], []
    try:
        for ws in cached:
            if ws.title.strip() in REFERENCE:
                skipped.append(ws.title)
                continue
            starts = [c.row for c in ws['A'] if txt(c.value) == TITLE]
            if not starts:
                raise ValueError(f'{ws.title}: no recognized payslip blocks')
            for start, stop in zip(starts, starts[1:] + [ws.max_row + 1]):
                def find(label):
                    matches = [r for r in range(start, stop) if txt(ws.cell(r, 1).value) == label]
                    if len(matches) != 1:
                        raise ValueError(f'{ws.title}:{start}: missing/ambiguous {label}')
                    return matches[0]
                def val(r, c):
                    return ws.cell(r, c).value
                def num(r, c):
                    v = val(r, c)
                    if v is None and formulas[ws.title].cell(r, c).data_type == 'f':
                        raise ValueError(f'{ws.title}:{r}: formula cache absent; recalculate original copy first')
                    return v
                period = txt(val(find('ประจำเดือน'), 2))
                pos = txt(val(find('ตำแหน่ง'), 2))
                names = [txt(val(r, 2)) for r in range(start, stop) if txt(val(r, 1)) == 'ชื่อ/สกุล']
                dates = [txt(val(r, 3)) for r in range(start, stop) if 'วันที่จ่าย' in txt(val(r, 3))]
                if not period or len(names) > 1 or len(dates) != 1:
                    raise ValueError(f'{ws.title}:{start}: missing or ambiguous header')
                header, total, net = find('รายได้'), find('รวมรายได้'), find('เงินรับสุทธิ')
                if not start < header < total < net < stop or txt(val(total, 3)) != 'รวมรายการหัก':
                    raise ValueError(f'{ws.title}:{start}: invalid block boundaries')
                lines = []
                for r in range(header+1, total):
                    for side, label_col, amount_col in [('income', 1, 2), ('deduction', 3, 4)]:
                        label, amount = txt(val(r, label_col)), num(r, amount_col)
                        if amount is None:
                            continue
                        if not label:
                            if isinstance(amount, (int, float)):
                                raise ValueError(f'{ws.title}:{r}: numeric amount without label')
                            continue  # unrelated text in a blank-label cell
                        lines.append({'side': side, 'label': label, 'amount_satang': satang(amount)})
                income, deduction, received = satang(num(total, 2)), satang(num(total, 4)), satang(num(net, 4))
                if (sum(x['amount_satang'] for x in lines if x['side'] == 'income') != income
                        or sum(x['amount_satang'] for x in lines if x['side'] == 'deduction') != deduction
                        or income - deduction != received):
                    raise ValueError(f'{ws.title}:{start}: source totals do not reconcile')
                records.append(dict(sheet=ws.title, row=start, period_label=period, recorded_date=dates[0], source_name=names[0] if names else '', position=pos, income_satang=income, deduction_satang=deduction, net_satang=received, lines=lines))
    finally:
        cached.close()
        formulas.close()
    if not 1 <= len(records) <= 300:
        raise ValueError('Archive must contain 1–300 records')
    seen = set()
    for record in records:
        key = json.dumps({k: v for k, v in record.items() if k not in ('sheet', 'row')}, sort_keys=True, ensure_ascii=False)
        if key in seen:
            raise ValueError('Possible duplicate source content; review before importing')
        seen.add(key)
        if len(record['lines']) > 60 or any(len(record[k]) > 500 for k in ('period_label', 'recorded_date', 'source_name', 'position')) or not 1 <= len(record['sheet']) <= 100 or any(not 1 <= len(x['label']) <= 500 for x in record['lines']):
            raise ValueError('Archive exceeds server validation bounds')
    return {'format': 'baanjergun-legacy-payroll-v1', 'source_sha256': hashlib.sha256(Path(path).read_bytes()).hexdigest(), 'records': records, 'skipped': skipped}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('workbook', type=Path)
    parser.add_argument('output', type=Path, help='New local JSON path outside repository')
    args = parser.parse_args()
    result = convert(args.workbook)
    output = args.output.resolve()
    if output.suffix.lower() != '.json' or any((parent / '.git').exists() for parent in output.parents):
        parser.error('Choose a new .json path outside any Git working tree')
    raw = json.dumps(result, ensure_ascii=False, indent=2).encode('utf-8')
    if len(raw) > 1_500_000:
        parser.error('Archive exceeds server size limit')
    with output.open('xb') as f:
        f.write(raw)
    print(f"Reconciled {len(result['records'])} records; {sum(not r['source_name'] for r in result['records'])} unnamed/group records remain unlinked. No database changes.")


if __name__ == '__main__':
    main()
