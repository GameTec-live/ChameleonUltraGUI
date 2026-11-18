#!/usr/bin/env python3
"""Require weak nested keys to explain both captures and their timing windows."""
import ctypes as C
import sys

from recovery_check import Engine, Nested, State, filter_bit


def observation(engine, key, uid, nt, distance):
    nonce = engine.lib.prng_successor(nt, distance % 65535)
    state = engine.state(key)
    encrypt = engine.lib.crypto1_byte
    encrypt.argtypes = [C.POINTER(State), C.c_uint8, C.c_int]
    encrypt.restype = C.c_uint8
    encrypted, parity = bytearray(), 0
    for i, (plain, uid_byte) in enumerate(zip(nonce.to_bytes(4, 'big'), uid.to_bytes(4, 'big'))):
        cipher = plain ^ encrypt(C.byref(state), plain ^ uid_byte, 0)
        encrypted.append(cipher)
        if i < 3:
            # Wire parity is plaintext odd parity XOR the next filter bit.
            wire = 1 ^ (plain.bit_count() & 1) ^ filter_bit(state.odd)
            parity |= (wire ^ 1 ^ (cipher.bit_count() & 1)) << i
    return int.from_bytes(encrypted, 'big'), parity


def capture(engine, key, distance, first, second, second_key=None):
    uid = 0x11223344
    nt0, nt1 = (engine.lib.prng_successor(0x01200145, n) for n in (47, 921))
    enc0, par0 = observation(engine, key, uid, nt0, first)
    enc1, par1 = observation(engine, key if second_key is None else second_key, uid, nt1, second)
    return Nested(uid, distance, nt0, enc0, par0, nt1, enc1, par1)


def explains(engine, key, data):
    for nt, encrypted, parity in ((data.nt0, data.enc0, data.par0), (data.nt1, data.enc1, data.par1)):
        if not any(observation(engine, key, data.uid, nt, data.dist + delta) == (encrypted, parity)
                   for delta in range(-14, 15)):
            return False
    return True


def main():
    engine = Engine(sys.argv[1])
    cases = 0
    for key in (0, 0xFFFFFFFFFFFF, 0xA0A1A2A3A4A5):
        for distance, first, second in ((613, 599, 627), (0, 65534, 1), (65534, 0, 65520)):
            data = capture(engine, key, distance, first, second)
            keys = engine.keys('nested', data)
            assert key in keys, (hex(key), distance, len(keys))
            assert keys == sorted(set(keys))
            assert all(explains(engine, candidate, data) for candidate in keys)
            cases += 1

    # Reproduce the attached card's unstable timing with a synthetic UID/key:
    # measured 617 clocks, but the captured nonces were 36892/33619 apart.
    # Also reject unrelated keys and a single out-of-window observation.
    for data in (
        capture(engine, 0x112233445566, 617, 36892, 33619),
        capture(engine, 0x112233445566, 613, 613, 613, second_key=0xA0A1A2A3A4A5),
        capture(engine, 0x112233445566, 613, 613, 900),
    ):
        assert engine.keys('nested', data) == []

    data = capture(engine, 0, 613, 613, 613)
    data.nt1, data.enc1, data.par1 = data.nt0, data.enc0, data.par0
    assert engine.keys('nested', data) == []

    data = capture(engine, 0, 613, 613, 613)
    engine.lib.recovery_set_cancelled(1)
    try:
        assert engine.keys('nested', data) == []
    finally:
        engine.lib.recovery_set_cancelled(0)
    assert 0 in engine.keys('nested', data)
    print(f'{cases} weak nested recoveries, inconsistent/repeated captures and cancellation passed', flush=True)


if __name__ == '__main__':
    main()
