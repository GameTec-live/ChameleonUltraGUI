#!/usr/bin/env python3
"""Native correctness and benchmark suite, independent of Flutter/hardware.

python3 recovery_check.py /path/to/librecovery.so --reference /path/to/original.so
Uses deterministic synthetic authentications, complete state multiset comparisons,
and the captured nested/darkside/hardnested fixtures from the Flutter tests.
"""
import argparse
import ctypes as C
import json
from pathlib import Path
import random
import statistics
import time


class State(C.Structure):
    _fields_ = [('odd', C.c_uint32), ('even', C.c_uint32)]


def record(name, fields):
    return type(name, (C.Structure,), {'_fields_': fields})


U32 = C.c_uint32
U64 = C.c_uint64
Nested = record('Nested', [(n, U32) for n in ('uid', 'dist', 'nt0', 'enc0', 'par0', 'nt1', 'enc1', 'par1')])
Static = record('Static', [(n, U32) for n in ('uid', 'type', 'nt0', 'enc0', 'nt1', 'enc1')])
Encrypted = record('Encrypted', [(n, U32) for n in ('uid', 'nt', 'enc', 'par')])
Mf32 = record('Mf32', [(n, U32) for n in ('uid', 'nt0', 'nt1', 'nr0', 'ar0', 'nr1', 'ar1')])
Mf64 = record('Mf64', [(n, U32) for n in ('uid', 'nt', 'nr', 'ar', 'at')])
Hard = record('Hard', [('data', C.c_char_p), ('length', U32)])
Item = record('Item', [('nt', U32), ('ks', U64), ('par', U64), ('nr', U32), ('ar', U32)])
Dark = record('Dark', [('uid', U32), ('items', C.POINTER(Item)), ('count', U32)])
FREE = C.CDLL(None).free
FREE.argtypes = [C.c_void_p]


class Engine:
    def __init__(self, path):
        self.lib = C.CDLL(str(Path(path).resolve()))
        for name in ('lfsr_recovery32', 'lfsr_recovery64'):
            f = getattr(self.lib, name)
            f.argtypes = [U32, U32]
            f.restype = C.POINTER(State)
        for name, typ in [('nested', Nested), ('static_nested', Static), ('static_encrypted_nested', Encrypted), ('darkside', Dark)]:
            f = getattr(self.lib, name)
            f.argtypes = [C.POINTER(typ), C.POINTER(U32)]
            f.restype = C.POINTER(U64)
        for name, typ in [('mfkey32', Mf32), ('mfkey64', Mf64), ('hardnested', Hard)]:
            f = getattr(self.lib, name)
            f.argtypes = [C.POINTER(typ)]
            f.restype = U64
        self.lib.crypto1_init.argtypes = [C.POINTER(State), U64]
        self.lib.crypto1_word.argtypes = [C.POINTER(State), U32, C.c_int]
        self.lib.crypto1_word.restype = U32
        self.lib.prng_successor.argtypes = [U32, U32]
        self.lib.prng_successor.restype = U32
        self.lib.lfsr_rollback_word.argtypes = [C.POINTER(State), U32, C.c_int]
        self.lib.crypto1_get_lfsr.argtypes = [C.POINTER(State), C.POINTER(U64)]

    def states(self, name, a, b):
        ptr = getattr(self.lib, name)(a, b)
        assert ptr
        result = []
        i = 0
        while ptr[i].odd | ptr[i].even:
            result.append((ptr[i].odd, ptr[i].even))
            i += 1
        FREE(ptr)
        return result

    def keys(self, name, data):
        count = U32()
        ptr = getattr(self.lib, name)(C.byref(data), C.byref(count))
        assert ptr or not count.value
        result = [ptr[i] for i in range(count.value)]
        FREE(ptr)
        return result

    def word(self, state, value=0, encrypted=0):
        return self.lib.crypto1_word(C.byref(state), value, encrypted)

    def state(self, key):
        s = State()
        self.lib.crypto1_init(C.byref(s), key)
        return s

    def auth(self, key, uid, nt, nr):
        s = self.state(key)
        self.word(s, uid ^ nt)
        self.word(s, nr, 1)
        p64 = self.lib.prng_successor(nt, 64)
        ar = self.word(s) ^ p64
        at = self.word(s) ^ self.lib.prng_successor(p64, 32)
        return ar, at


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('library')
    ap.add_argument('--reference')
    ap.add_argument('--cases', type=int, default=32)
    ap.add_argument('--repeats', type=int, default=3)
    ap.add_argument('--hardnested', action='store_true')
    ap.add_argument('--report', type=Path)
    args = ap.parse_args()
    engine = Engine(args.library)
    reference = Engine(args.reference) if args.reference else None
    rng = random.Random(0xC1A551C)
    timings = {}

    def measure(name, call, expected=None, compare=True, use_reference=True):
        samples = []
        outputs = []
        engines = [reference, engine] if reference and use_reference else [engine]
        for e in engines:
            values = []
            result = None
            for _ in range(args.repeats):
                start = time.perf_counter()
                result = call(e)
                values.append(time.perf_counter() - start)
                if expected is not None:
                    assert expected in result if isinstance(result, list) else expected == result, (name, expected, result)
            samples.append(statistics.median(values))
            outputs.append(result)
        if len(outputs) == 2 and compare:
            assert outputs[0] == outputs[1], (name, 'candidate sets differ')
        timings[name] = samples
        print(name, samples, flush=True)

    if reference:
        # The key/register maps are linear permutations. Check every basis bit
        # (including ignored high bits), then mixed full-width values.
        for key in [1 << bit for bit in range(64)] + [rng.getrandbits(64) for _ in range(4096)]:
            assert bytes(engine.state(key)) == bytes(reference.state(key))
        for odd, even in ([(1 << bit, 0) for bit in range(32)] + [(0, 1 << bit) for bit in range(32)] + [(rng.getrandbits(32), rng.getrandbits(32)) for _ in range(4096)]):
            state = State(odd, even)
            outputs = [U64(), U64()]
            for e, output in zip((reference, engine), outputs):
                e.lib.crypto1_get_lfsr(C.byref(state), C.byref(output))
            assert outputs[0].value == outputs[1].value
        print('8320 key/register permutation comparisons passed', flush=True)

    # Include zero/all-one keys and full-width internal states, not only the
    # 24-bit states produced by crypto1_init. High contribution bits must vanish.
    rollback = engine.lib.crypto1_rollback_key
    rollback.argtypes = [C.POINTER(State), U32]
    rollback.restype = U64
    for _ in range(4096):
        state = State(rng.getrandbits(32), rng.getrandbits(32))
        value = rng.getrandbits(32)
        actual = rollback(C.byref(state), value)
        engine.lib.lfsr_rollback_word(C.byref(state), value, 0)
        expected = U64()
        engine.lib.crypto1_get_lfsr(C.byref(state), C.byref(expected))
        assert actual == expected.value
    print('4096 full-width rollback equivalence checks passed', flush=True)

    from collections import Counter
    rank = engine.lib.most_frequent_uint64
    rank.argtypes = [C.POINTER(U64), U32, C.POINTER(U32)]
    rank.restype = C.POINTER(U64)
    for size in (1, 2, 1023, 1024, 1025, 10000):
        for values in ([rng.getrandbits(64) for _ in range(size)], [0xffffffffffffffff] * size, [i % 17 for i in range(size)]):
            counts = Counter(values)
            expected = sorted(k for k, n in counts.items() if n == max(counts.values()))
            data = (U64 * size)(*values)
            n = U32()
            result = rank(data, size, C.byref(n))
            assert list(result[:n.value]) == expected
            FREE(result)
    if reference:
        words = 1 << 19
        a = (U32 * words)(*(rng.getrandbits(32) for _ in range(words)))
        b = (U32 * words)(*(rng.getrandbits(32) for _ in range(words)))
        for name in ('count_states', 'count_bitarray_AND', 'count_bitarray_low20_AND', 'count_bitarray_AND2', 'count_bitarray_AND3', 'count_bitarray_AND4'):
            if not hasattr(engine.lib, name):
                continue
            results = []
            for e in (reference, engine):
                copy = (U32 * words).from_buffer_copy(a)
                f = getattr(e.lib, name)
                f.restype = U32
                # Extra pointer arguments are harmless for the one/two/three
                # input variants and keep this check independent of signatures.
                results.append((f(copy, b, a, b), bytes(copy)))
            assert results[0] == results[1], name
    print('radix boundaries, full-width keys and bitarray comparisons passed', flush=True)

    for i in range(args.cases):
        key = [0, 0xffffffffffff, 0xa0a1a2a3a4a5][i] if i < 3 else rng.getrandbits(48)
        uid, nt0, nt1, nr0, nr1 = [rng.getrandbits(32) for _ in range(5)]
        ar0, at0 = engine.auth(key, uid, nt0, nr0)
        ar1, _ = engine.auth(key, uid, nt1, nr1)
        m32 = Mf32(uid, nt0, nt1, nr0, ar0, nr1, ar1)
        m64 = Mf64(uid, nt0, nr0, ar0, at0)
        measure(f'mfkey32/{i}', lambda e: e.lib.mfkey32(C.byref(m32)), key)
        measure(f'mfkey64/{i}', lambda e: e.lib.mfkey64(C.byref(m64)), key)
        # A random 32-bit stream with arbitrary input exercises the shared
        # solver independently of the public wrappers. Compare multiplicities.
        if reference:
            ks, inp = rng.getrandbits(32), rng.getrandbits(32)
            if i < 2:
                ks = inp = (0 if i == 0 else 0xffffffff)
            measure(f'states32/{i}', lambda e: e.states('lfsr_recovery32', ks, inp))
            measure(f'states64/{i}', lambda e: e.states('lfsr_recovery64', ks, inp))
            p64 = engine.lib.prng_successor(nt0, 64)
            p96 = engine.lib.prng_successor(p64, 32)
            measure(f'states64-valid/{i}', lambda e: e.states('lfsr_recovery64', ar0 ^ p64, at0 ^ p96))
        for gen, nt, kind, dist in [(1, 0x01200145, 0x60, 160), (2, 0x009080a2, 0x60, 160), (2, 0x009080a2, 0x61, 161)]:
            enc = []
            for d in (dist, dist + 160):
                probe = engine.lib.prng_successor(nt, d)
                s = engine.state(key)
                enc.append(probe ^ engine.word(s, probe ^ uid))
            static = Static(uid, kind, nt, enc[0], nt, enc[1])
            # The original accidentally drops its final candidate; its traversal
            # order is not a valid oracle for this wrapper. Check the known key.
            measure(f'static/{i}/{gen}/{kind}', lambda e: e.keys('static_nested', static), key, compare=False)
        s = engine.state(key)
        stream = engine.word(s, nt0 ^ uid)
        kspar = engine.word(s) >> 24 & 1
        enc = nt0 ^ stream
        last_error = 1 ^ (nt0 & 255).bit_count() % 2 ^ kspar ^ (1 ^ (enc & 255).bit_count() % 2)
        encrypted = Encrypted(uid, nt0, enc, last_error)
        measure(f'encrypted/{i}', lambda e: e.keys('static_encrypted_nested', encrypted), key)

    nested = Nested(2374329723, 613, 1999585272, 3173333529, 3, 128306861, 2363514210, 7)
    measure('nested/capture', lambda e: e.keys('nested', nested), 0xffffffffffff, compare=False)
    items = (Item * 2)(Item(913032415, 216745674933338888, 0, 0, 0), Item(913032415, 1010230244403446283, 0, 1, 0))
    dark = Dark(2374329723, items, 2)
    measure('darkside/capture', lambda e: e.keys('darkside', dark), 0xffffffffffff)
    if args.hardnested:
        import re
        fixture = Path(__file__).parents[1] / 'recovery_test.dart'
        data = bytes.fromhex(max(re.findall(r"'([0-9a-f]+)'", fixture.read_text()), key=len))
        hard = Hard(data, len(data))
        measure('hardnested/capture', lambda e: e.lib.hardnested(C.byref(hard)), 0xfbf225dc5d58)
        data = (Path(__file__).parent / 'fixtures' / 'hardnested-filtering.bin').read_bytes()
        hard = Hard(data, len(data))
        # The independent reference also confuses decompressed bytes with state
        # counts and rejects this key. Use the synthetic key as the oracle.
        measure('hardnested/filtering', lambda e: e.lib.hardnested(C.byref(hard)),
                0x405044544951, use_reference=False)
    if args.report:
        args.report.write_text(json.dumps(timings, indent=2) + "\n")
    print(json.dumps(timings, indent=2))


if __name__ == '__main__':
    main()
