#!/usr/bin/env python3
"""Known-key corpus from ChameLab's published 2026-11-04 benchmark.

Generate identical xorshift32 captures before timing; run each recovery in a
fresh process. --reference compares time/RSS against a saved native library.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import resource
import statistics
import subprocess
import sys
import time

from recovery_check import Engine, State, filter_bit, recover_hardnested_checked

# https://github.com/m0n5ter/ChameLab/blob/431be79c4e3a5a54cd34a681011a27a4f9cc5ef9/software/benchmarks/hardnested/CASES.json
CASES = {
    'reference': (12000, 0x112233445566, 0x12345678, 0x9325abcd),
    'sparse': (4096, 0x112233445566, 0x12345678, 0x9325abcd),
    'ones-sparse': (4096, 0xffffffffffff, 0x12345678, 0x9325abcd),
    'zero': (12000, 0, 0, 1),
    'transport': (12000, 0xa0a1a2a3a4a5, 0xdeadbeef, 0xcafebabe),
    'mixed': (12000, 0x3a94d6f07c21, 0x04a1b2c3, 0x13579bdf),
    'new-seed': (8192, 0x112233445566, 0x12345678, 0x2468ace1),
    'ones-dense': (24000, 0xffffffffffff, 0xffffffff, 0x9325abcd),
}


def capture(engine, case):
    count, key, uid, seed = CASES[case]
    encrypt = engine.lib.crypto1_byte
    encrypt.argtypes = [C.POINTER(State), C.c_uint8, C.c_int]
    encrypt.restype = C.c_uint8
    result = bytearray(uid.to_bytes(4, 'big') + bytes([0, 0x60]))
    pending = bytearray()
    packed_parity = 0
    seen = set()
    for sample in range(count):
        seed ^= (seed << 13) & 0xffffffff
        seed ^= seed >> 17
        seed ^= (seed << 5) & 0xffffffff
        state = engine.state(key)
        encrypted, parity = bytearray(), 0
        for shift in (24, 16, 8, 0):
            plain = (seed >> shift) & 255
            encrypted.append(plain ^ encrypt(C.byref(state), plain ^ ((uid >> shift) & 255), 0))
            parity = (parity << 1) | (1 ^ (plain.bit_count() & 1) ^ filter_bit(state.odd))
        seen.add(encrypted[0])
        pending.extend(encrypted)
        packed_parity = (packed_parity << 4) | parity
        if sample & 1:
            result.extend(pending)
            result.append(packed_parity)
            pending.clear()
            packed_parity = 0
    assert len(seen) == 256 and not pending
    return bytes(result)


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('library', type=Path)
    ap.add_argument('--reference', type=Path)
    ap.add_argument('--repeats', type=int, default=1)
    ap.add_argument('--case', choices=CASES, action='append')
    ap.add_argument('--report', type=Path)
    ap.add_argument('--worker', choices=CASES, help=argparse.SUPPRESS)
    args = ap.parse_args()
    if args.worker:
        engine = Engine(args.library)
        data = capture(engine, args.worker)
        start = time.perf_counter()
        key = recover_hardnested_checked(engine, data)
        elapsed = time.perf_counter() - start
        assert key == CASES[args.worker][1], hex(key)
        print('\nRESULT ' + json.dumps({'seconds': elapsed, 'peak_rss_kib': resource.getrusage(resource.RUSAGE_SELF).ru_maxrss}), flush=True)
        return
    assert sys.platform.startswith('linux') and args.repeats > 0
    libraries = [('optimized', args.library)]
    if args.reference:
        libraries.insert(0, ('reference', args.reference))
    samples = []
    for repeat in range(args.repeats):
        for case in args.case or CASES:
            for variant, library in libraries if repeat % 2 == 0 else libraries[::-1]:
                process = subprocess.run([sys.executable, __file__, str(library.resolve()), '--worker', case],
                                         check=True, capture_output=True, text=True)
                row = json.loads(next(line[7:] for line in process.stdout.splitlines() if line.startswith('RESULT ')))
                row.update(case=case, repeat=repeat, variant=variant)
                samples.append(row)
                print(json.dumps(row), flush=True)
    medians = {}
    for case in args.case or CASES:
        medians[case] = {}
        for variant, _ in libraries:
            rows = [r for r in samples if r['case'] == case and r['variant'] == variant]
            medians[case][variant] = {k: statistics.median(r[k] for r in rows) for k in ('seconds', 'peak_rss_kib')}
    report = {'samples': samples, 'medians': medians}
    if args.report:
        args.report.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(medians, indent=2))


if __name__ == '__main__':
    main()
