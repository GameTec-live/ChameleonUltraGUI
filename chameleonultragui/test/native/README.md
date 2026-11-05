Native recovery checks run independently of Flutter and card hardware.

Build the library:

```sh
cmake -S chameleonultragui/src -B build/native-recovery -DCMAKE_BUILD_TYPE=Release
cmake --build build/native-recovery -j4
```

Compare against a separately built baseline (the current work used `6f3b0c22`):

```sh
python3 chameleonultragui/test/native/recovery_check.py \
  build/native-recovery/librecovery.so --reference /path/to/baseline/librecovery.so \
  --cases 32 --repeats 1 --hardnested --hardnested-generated 4
```

The solver comparisons check full candidate lists, including ordering and
multiplicity. Generated hardnested captures use known keys, including zero;
the test checks the success status as well as the key. These captures use
8192 or more encrypted nonces to constrain the search. The older independent
reference used in CI has a known bitflip-filtering bug, so generated captures
use their known keys as the oracle rather than requiring that reference to
recover them.

Compile each internal check against the library:

```sh
for check in hardnested_tables_check hardnested_memory_check; do
  cc -O3 -D_GNU_SOURCE "chameleonultragui/test/native/$check.c" \
    -Lbuild/native-recovery -Wl,-rpath,"$PWD/build/native-recovery" \
    -lrecovery -pthread -lm -o "build/native-recovery/$check"
  "build/native-recovery/$check"
done
```

`hardnested_tables_check` checks every partial-sum bitmap bit against the
scalar construction. `hardnested_memory_check` compares shared and owned
bitmap intersections against the original in-place operation, checks all
65536 parity lookups against list traversal (including missing and duplicate
entries), verifies every filter's count, compares every concurrently decoded table byte
against serial decompression (including ignored tables), and exercises mixed
ownership and repeated cleanup. CI runs these on x86-64 and ARM64.

For sanitizer checks, build the library and check executable with
`-fsanitize=address,undefined -fno-omit-frame-pointer`. The bundled LZMA decoder
requires `-Wno-error=conversion` for this GCC configuration because instrumentation
exposes existing conversion warnings. No decoder source changes are needed.

Measure elapsed recovery time and peak process RSS on Linux:

```sh
python3 chameleonultragui/test/native/hardnested_benchmark.py \
  build/native-recovery/librecovery.so --reference /path/to/baseline/librecovery.so \
  --repeats 5 --report build/native-recovery/benchmark.json
```

Each sample runs in a fresh process; reference and optimized order alternates.
Run without competing builds/tests. The report includes raw samples and medians.
RSS includes the Python harness and library, consistently for both builds.
Timing includes table initialization, reduction, brute force and cleanup.
Use `taskset -c 0` before the command to measure the single-CPU path.
Desktop measurements do not establish mobile performance.

The changes preserve the dense bitmap lookup path and candidate ordering.
Bitflip tables are decoded in batches of at most eight, applied to disjoint
ranges of nonce bytes, then freed. Intersections commute, so every applicable
filter still contributes to the same final bitmap. Decoder state is thread-local;
failed thread launches run the same work synchronously. The decoder helpers
compile together to permit inlining (as they already did in Apple builds).

The earlier optimizations also remain: unused sum bitmaps are removed,
unfiltered nonce halves share an immutable all-ones bitmap until the first
intersection, second-byte parity uses a 64 KiB index instead of list traversal,
and candidate scratch bitmaps allocate 2 MiB instead of 4 MiB.
[ChameLab](https://github.com/m0n5ter/ChameLab) was inspected for ideas. Its sparse
page representation was not ported; fully filtered nonce bitmaps can still
occupy 1 GiB. These changes do not make hardnested fit every phone.

For a complete reduction comparison, compile `hardnested_reduction_check.c`
against both libraries. The host check also requires zlib (`-lz`). For the eager
table reference, add `-DREFERENCE_REDUCTION` and
`-DRECOVERY_SOURCE='"/absolute/path/to/reference-hardnested.c"'`, plus
`-Ichameleonultragui/src`. Use the same link/rpath options as the other checks.
Run the reference executable with a binary nonce fixture and output filename:

```sh
reference-check capture.bin reduction.snapshot.gz
current-check capture.bin reduction.snapshot.gz --verify
```

The snapshot uses lossless canonical run encoding and gzip. Verification compares
every encoded word, with no hashes or sampling: all 512 nonce bitmaps/counts,
both shared domains, every partial-sum bitmap, and all partial-sum counts.
Locally these matched the previous eager implementation for both stored fixtures,
a generated all-one-key capture, and an empty capture. This also tests the extreme
all-one key without spending hours in its unchanged brute-force search.

The 32-case solver comparison and six complete hardnested recoveries passed
again after batching. ASan/UBSan passed for the concurrent table/ownership check
and full filtering fixture; leak detection was disabled only for the Python-hosted
full recovery run. GCC and Clang builds passed. ARM64 checks are configured in
CI, but were not run locally.

Measured locally on Linux x86-64 with four exposed Xeon E5-2620 v3 CPUs,
Release/GCC, five fresh-process samples per build/fixture. The reference for
this second pass is the saved library from the first optimization pass:

| Fixture | Previous median | Current median | Previous peak RSS¹ | Current peak RSS¹ |
| --- | ---: | ---: | ---: | ---: |
| Captured | 11.938 s | 8.236 s | 1624.7 MiB | 1148.7 MiB |
| Filtering | 11.894 s | 8.555 s | 1626.6 MiB | 1150.7 MiB |

¹ Median of per-process peak RSS measurements, including the same Python harness.
Current peaks are approximately 1.12 GiB (1.21 GB decimal). Individual timings
vary on the shared VM. These measurements establish the result for these desktop
workloads; they do not guarantee a fixed duration or memory bound for every key,
capture or mobile device.

With affinity restricted to one CPU, three fresh-process samples per build:

| Fixture | Previous median | Current median |
| --- | ---: | ---: |
| Captured | 23.483 s | 20.465 s |
| Filtering | 22.987 s | 19.168 s |

Both fixtures improved on one CPU as well. A three-CPU filtering recovery and a
Clang-built captured recovery also passed. Forced worker-launch failures produced
exactly the reference reduction snapshot for the filtering fixture.
