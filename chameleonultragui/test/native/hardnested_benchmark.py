#!/usr/bin/env python3
"""Linux hardnested elapsed time / peak RSS, using a fresh process per sample.

Run after building Release libraries, with no other CPU/memory intensive work:
python3 hardnested_benchmark.py optimized.so --reference baseline.so --repeats 5
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import re
import resource
import statistics
import subprocess
import sys
import time

from recovery_check import Engine, Hard


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('library', type=Path)
    ap.add_argument('--reference', type=Path)
    ap.add_argument('--repeats', type=int, default=5)
    ap.add_argument('--report', type=Path)
    ap.add_argument('--worker', choices=['capture', 'filtering'], help=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.worker:
        engine = Engine(args.library)
        root = Path(__file__).parent
        if args.worker == 'capture':
            data = bytes.fromhex(max(re.findall(r"'([0-9a-f]+)'", (root.parent / 'recovery_test.dart').read_text()), key=len))
            expected = 0xfbf225dc5d58
        else:
            data = (root / 'fixtures/hardnested-filtering.bin').read_bytes()
            expected = 0x405044544951
        hard = Hard(data, len(data))
        start = time.perf_counter()
        key = engine.lib.hardnested(C.byref(hard))
        elapsed = time.perf_counter() - start
        assert key == expected, hex(key)
        print('RESULT ' + json.dumps({'seconds': elapsed, 'peak_rss_kib': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}), flush=True)
        return
    assert sys.platform.startswith('linux'), 'RSS units in this report assume Linux'
    assert args.repeats > 0
    rows = []
    libraries = [('optimized', args.library)]
    if args.reference:
        libraries.insert(0, ('reference', args.reference))
    for repeat in range(args.repeats):
        for fixture in ('capture', 'filtering'):
            # Alternate order to reduce warmup / thermal bias.
            for variant, library in (libraries if repeat % 2 == 0 else libraries[::-1]):
                result = subprocess.run([sys.executable, __file__, str(library.resolve()), '--worker', fixture], text=True, capture_output=True, check=True)
                row = json.loads(next(line[7:] for line in result.stdout.splitlines() if line.startswith('RESULT ')))
                row.update(variant=variant, fixture=fixture, repeat=repeat)
                rows.append(row)
                print(json.dumps(row), flush=True)
    medians = {}
    for fixture in ('capture', 'filtering'):
        medians[fixture] = {}
        for variant, _ in libraries:
            samples = [row for row in rows if row['fixture'] == fixture and row['variant'] == variant]
            medians[fixture][variant] = {
                metric: statistics.median(row[metric] for row in samples)
                for metric in ('seconds', 'peak_rss_kib')
            }
    report = {'samples': rows, 'medians': medians}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(medians, indent=2))


if __name__ == '__main__':
    main()
