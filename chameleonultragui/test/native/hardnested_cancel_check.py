#!/usr/bin/env python3
"""Cancel during construction/reduction, then recover again in the same process."""
import ctypes as C
from pathlib import Path
import sys
import threading

from recovery_check import Engine, Hard, recover_hardnested_checked


engine = Engine(sys.argv[1])
engine.lib.recovery_set_cancelled.argtypes = [C.c_int]
data = (Path(__file__).parent / 'fixtures/hardnested-filtering.bin').read_bytes()
expected = 0x405044544951
for delay in list(map(float, sys.argv[2:])) or (0, 0.1, 0.5):
    engine.lib.recovery_set_cancelled(0)
    cancel = threading.Timer(delay, engine.lib.recovery_set_cancelled, args=[1])
    cancel.start()
    hard = Hard(data, len(data))
    result = engine.lib.hardnested(C.byref(hard))
    cancel.join()
    # A fast host may finish before the timer fires.
    assert result in (0, expected), hex(result)
    engine.lib.recovery_set_cancelled(0)
    assert recover_hardnested_checked(engine, data) == expected
print('Cancellation and subsequent recovery passed', flush=True)
