#!/usr/bin/env python3
"""Check static-nonce timing variants and require agreement from both captures."""
import sys

from recovery_check import Engine, Static


def capture(engine, key, uid, nt, first, step, kind):
    encrypted = []
    for distance in (first, first + step):
        nonce = engine.lib.prng_successor(nt, distance)
        encrypted.append(nonce ^ engine.word(engine.state(key), nonce ^ uid))
    return Static(uid, kind, nt, encrypted[0], nt, encrypted[1])


def main():
    engine = Engine(sys.argv[1])
    cases = 0
    for key in (0, 0xFFFFFFFFFFFF, 0xA0A1A2A3A4A5):
        for nt, steps in ((0x01200145, (160,)), (0x009080A2, (160, 161))):
            for kind in (0x60, 0x61):
                for first in steps:
                    for step in steps:
                        data = capture(engine, key, 0xAAC9C063, nt, first, step, kind)
                        keys = engine.keys('static_nested', data)
                        assert key in keys, (hex(key), hex(nt), hex(kind), first, step, len(keys))
                        assert keys == sorted(set(keys))
                        # Some weak keys have multiple genuine solutions. Every
                        # returned key must explain BOTH observations under one
                        # supported timing, not merely occur in either list.
                        for candidate in keys:
                            observations = []
                            for start in steps:
                                for stride in steps:
                                    probe = capture(engine, candidate, data.uid, nt, start, stride, kind)
                                    observations.append((probe.enc0, probe.enc1))
                            assert (data.enc0, data.enc1) in observations, (hex(candidate), first, step)
                        cases += 1

    # Individually valid captures encrypted with different keys must not turn
    # into a huge list of tied singleton candidates.
    a = capture(engine, 0x112233445566, 0xAAC9C063, 0x009080A2, 160, 160, 0x61)
    b = capture(engine, 0xA0A1A2A3A4A5, a.uid, a.nt0, 160, 160, a.type)
    a.enc1 = b.enc1
    assert engine.keys('static_nested', a) == []
    a.nt0 = a.nt1 = 0x12345678
    assert engine.keys('static_nested', a) == []

    data = capture(engine, 0, 0xAAC9C063, 0x009080A2, 161, 161, 0x61)
    engine.lib.recovery_set_cancelled(1)
    try:
        assert engine.keys('static_nested', data) == []
    finally:
        engine.lib.recovery_set_cancelled(0)
    assert 0 in engine.keys('static_nested', data)
    print(f'{cases} static timing recoveries, inconsistent/unsupported captures and cancellation passed', flush=True)


if __name__ == '__main__':
    main()
