Native recovery checks run independently of Flutter and card hardware.
The current implementation uses shared immutable pages for filters and nonce
maps. Earlier dense-build measurements are retained below for comparison;
the compact-page measurements follow them.

Candidate generation and brute force run workers whose launches failed on the
calling thread and join only successfully created threads. Candidate workers
share a work book; brute-force workers must each retain their bucket stride.
`hardnested_threads_check.c` injects first/middle/last/alternating/all candidate
launch failures, rejects invalid or repeated joins, and compares every state
in every nonempty candidate bucket (including multiplicity) with the successful
launch run. Compile/link it like the other internal checks and pass
`test/native/fixtures/hardnested-filtering.bin` as its argument.

The Linux `thread_fallback.c` shim fails all launches by default, or one in N
with `RECOVERY_TEST_FAIL_EVERY=N`. Complete captured/filtering/zero-key
recoveries passed with all and alternating launches failed; CI runs them on
both architectures. This exercises candidate generation and brute force
together, rather than stopping before the key search.

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
entries), verifies every filter's count, compares every packed table word
against original-table decompression (including the ignored-table decision), checks all fused-kernel
counts, partial-slice boundaries and multi-group fallbacks, and exercises mixed
ownership and repeated cleanup. Compact page checks cover chunk growth,
rehashing, deduplication, zero pages and hash collisions. Candidate predicates
are checked against the original arithmetic-first rule in both representations.
CI runs these on x86-64 and ARM64.

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

Candidate ordering and applicable filters are preserved. Dense scratch maps
are filtered with the existing vectorized kernels, in 256-byte pages. Finished
pages are interned in worker-owned pools and remain immutable. A page hash is
only an index: full word comparisons establish equality, so collisions cannot
merge unequal pages. Pointer directories keep membership constant-time and
avoid a hash lookup during candidate checks. This follows
[ChameLab's page-sharing idea](https://github.com/m0n5ter/ChameLab/blob/431be79c4e3a5a54cd34a681011a27a4f9cc5ef9/software/chamelab/ChameLab/Crypto/Hardnested/HardnestedBitSet.cs),
with page-wise vectorized filtering and the existing native candidate search.

`src/hardnested/generate_compact_tables.py` derives a packed table resource
from this repository's original XZ tables. It contains the same 241 effective
filters, sharing 23502 pages. The resource is 263756 compressed bytes and
9967960 decoded bytes. Regenerate it after changing `tables.c` or
`IGNORE_BITFLIP_THRESHOLD`; no generator
or external resource is needed when building or running the app. Exhaustive
native checks compare every packed word to the original tables.

Reduction uses at most four workers, each with two 2 MiB scratch maps and its
own page pool. An earlier nonce can eliminate a high-20-bit group from the
worker's local domain before the next nonce is filtered. The final shared
domain is applied when reading every immutable map, including earlier maps.
This preserves the final intersections while avoiding the 512 dense maps
that previously retained 1 GiB. Failed thread launches execute the same jobs
synchronously. Unused sum maps, the parity index, cached partial sums and
candidate scratch reductions from the earlier passes remain.

Run the eight deterministic cases from ChameLab's published benchmark:

```sh
python3 chameleonultragui/test/native/hardnested_corpus_check.py \
  build/native-recovery/librecovery.so --reference /path/to/baseline/librecovery.so \
  --repeats 3 --report build/native-recovery/corpus.json
python3 chameleonultragui/test/native/hardnested_cancel_check.py \
  build/native-recovery/librecovery.so
```

The corpus uses the published keys, UIDs, xorshift seeds and nonce counts,
including sparse/dense all-one keys. Captures are generated before timing.
Each native call checks both success status and recovered key. These runs
compare native builds on this host; the published managed results use a
different host and are not directly comparable.

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

The following measurements record checkpoint `28a3863a` before filter fusion.
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

The next optimization pass fuses each nonce's applicable filters into one scan,
counts only the final intersection, processes the low-20-bit projection a full
word at a time, and caches the fixed candidate traversal order. Partial-sum
construction uses up to eight workers with 32-state-aligned boundaries, preserving
exclusive ownership of every bitmap word.

Complete reduction snapshots still matched checkpoint `28a3863a` for both stored
fixtures, the generated all-one key, and an empty capture. The 32-case solver
comparison and six recoveries passed again, as did ASan/UBSan. Fused scans were
checked at every specialized arity, zero filters, repeated immutable pointers,
and the generic fallback. The group projection was checked against the scalar
half-word rule over every possible 16-bit input and zero-half combinations.
All partial-sum bits matched scalar construction for CPU counts 1, 6 and 8,
including forced thread-launch failures; six CPUs exercise non-power-of-two
partitioning. GCC and Clang builds passed.

Five-second baseline measurements against checkpoint `28a3863a`, same four-CPU host, five
fresh-process samples per build/fixture:

| Fixture | Checkpoint median | Fused median | Checkpoint peak RSS¹ | Fused peak RSS¹ |
| --- | ---: | ---: | ---: | ---: |
| Captured | 8.321 s | 5.079 s | 1150.9 MiB | 1156.8 MiB |
| Filtering | 8.874 s | 4.890 s | 1150.7 MiB | 1158.8 MiB |

¹ Median of per-process peaks. Current memory remains approximately 1.13 GiB.
The larger bounded table batch trades roughly 6–8 MiB for fewer bitmap scans.
CPU availability is captured once per worker partition so changing affinity
cannot produce an inconsistent worker count during partition calculations.

With one CPU, three fresh-process samples per build:

| Fixture | Checkpoint median | Fused median |
| --- | ---: | ---: |
| Captured | 20.650 s | 13.798 s |
| Filtering | 20.050 s | 12.888 s |

The single-CPU path improved too. These desktop results do not establish mobile
performance or a fixed recovery duration for arbitrary captures.

The three-second pass removes counts between filter batches entirely. Final
nonce counts are computed immediately before domain reduction consumes them;
both register halves reduce their own domains and sum tables in parallel.
Filtering operates on 512-word slices across nonce bytes so table slices remain
in cache. Larger batches reuse the same fixed-arity kernels in smaller groups.

Partial sums now evaluate shared subtrees of the four-bit path enumeration,
inspired by ChameLab's managed construction. Exhaustive scalar comparisons
verify every output bit in both halves. Candidate checks reuse the immutable
1 MiB Crypto1 lookup table already owned by the solver; no duplicate table is
retained. If that table is unavailable (`LOWMEM` or MSVC), scalar construction
and the arithmetic filter remain available. Temporary partial-sum allocation
failure also falls back to scalar construction.

Full reduction snapshots matched the five-second baseline for both fixtures,
the all-one-key capture and an empty capture. The 32-case solver comparisons,
six complete recoveries, ASan/UBSan, and scalar table checks passed again.
Tests cover every fused arity through 33 filters, repeated input pointers,
zero-length slices, unaligned slice starts, vector tails and cache-block
boundaries. GNU-compatible x86-64 builds use groups of eight filters to avoid
source-pointer register spills; other targets retain groups of sixteen.
Lookup tests cover every 20-bit input, ignored high bits, and the
arithmetic fallback. The `LOWMEM` build passed exhaustive partial-sum checks
and both stored recoveries. CI now checks its fallback path on x86-64 and ARM64.

Sparse candidate checks fetch each aligned group of low-bit alternatives with
one bitmap read and evaluate only the permitted states, preserving their order.
Dense sets retain the original arithmetic-first evaluation. Exhaustive group
extraction and comparisons with the original candidate predicate cover both
halves, empty/dense/sparse maps, the density threshold, and lookup/arithmetic
filters. Workers waiting for a shared candidate list now sleep on a condition
variable instead of repeatedly scanning the work book. A revision counter
prevents missed publications; checks exercise spurious notifications, normal
completion and cancellation.

Dense-build measurements against the saved five-second build, on the same four-CPU
host with five fresh-process samples per build/fixture:

| Fixture | Five-second build median | Current median | Previous peak RSS¹ | Current peak RSS¹ |
| --- | ---: | ---: | ---: | ---: |
| Captured | 5.225 s | 3.324 s | 1156.8 MiB | 1182.9 MiB |
| Filtering | 4.957 s | 3.225 s | 1158.8 MiB | 1182.9 MiB |

¹ Median of per-process peaks. The thirty-two-table batch costs approximately
24–26 MiB relative to the five-second build; current peak memory is about
1.16 GiB. Measured recovery time fell by 35–36%. Timings vary on this shared VM
and are specific to these fixtures and host; generated captures that
need additional guesses can take longer, and mobile performance is unmeasured.

The dense build again passed all 32 solver comparisons, six complete hardnested
recoveries (including zero-key and multi-guess captures), exact filtering
reduction comparison, ownership/candidate/cache checks, failed-launch fallback
checks, and ASan/UBSan. Clang-built kernels and a complete Clang recovery passed;
both stored captures also passed with `LOWMEM`. Sanitizer leak detection was
disabled only for the Python-hosted full recovery. ARM64 validation remains
configured in CI rather than executed locally.

With affinity restricted to one CPU, three fresh-process samples per build:

| Fixture | Five-second build median | Current median |
| --- | ---: | ---: |
| Captured | 13.887 s | 8.597 s |
| Filtering | 12.852 s | 7.777 s |

Both fixtures improved by approximately 38–39% on one CPU as well.

## Compact-page results

Compared with the saved three-second dense build from the start of this memory
pass, on the same four-CPU Linux x86-64 host. Five fresh-process samples per
build/fixture, sequentially with alternating build order:

| Fixture | Dense median | Compact median | Dense peak RSS¹ | Compact peak RSS¹ |
| --- | ---: | ---: | ---: | ---: |
| Captured | 3.325 s | 2.946 s | 1183.1 MiB | 162.7 MiB |
| Filtering | 3.201 s | 2.246 s | 1182.8 MiB | 159.7 MiB |

¹ Median of per-process peaks, including the same Python harness. Memory fell
by approximately 86%, to 167–171 MB decimal. Recovery time fell by 11–30%.
These are measured workloads, not a universal memory or duration bound.

Complete reductions matched the saved dense build word for word for both
stored fixtures, the generated all-one-key capture, and an empty capture.
One-, three- and four-worker reductions also matched, including forced launch
failures. Candidate tests compare 24576 cases against the original predicate
across both representations, both halves, lookup/scalar filters and both sides
of the density threshold. Page tests exercise zero pages, sharing, chunk growth,
hash-table growth, unequal-page hash collisions and cleanup after freezing.

Both stored captures and four generated known-key captures recovered correctly.
Native ASan/UBSan checks passed, as did a full recovery and cancellation followed
by successful recovery in the same process. Leak detection was disabled only
for the Python-hosted sanitizer calls. Clang and `LOWMEM` recoveries passed.
CI includes the packed-table oracle, page/candidate tests, complete reduction
comparisons, eight-case corpus and cancellation on x86-64 and ARM64. ARM64/mobile
execution was not available locally.

Three fresh-process samples per build for each of the eight published cases:

| Case | Dense median | Compact median | Compact peak RSS¹ |
| --- | ---: | ---: | ---: |
| reference | 2.881 s | 2.105 s | 158.5 MiB |
| sparse | 3.312 s | 2.026 s | 161.3 MiB |
| ones-sparse | 78.764 s | 76.949 s | 158.7 MiB |
| zero | 3.042 s | 1.602 s | 155.9 MiB |
| transport | 2.822 s | 2.034 s | 157.2 MiB |
| mixed | 3.228 s | 2.571 s | 163.8 MiB |
| new-seed | 3.004 s | 2.033 s | 158.5 MiB |
| ones-dense | 62.669 s | 61.749 s | 157.4 MiB |

All 48/48 paired corpus recoveries passed (24 per build). Every compact median
was faster; the hardest all-one-key cases remain dominated by their unchanged
brute-force search. The maximum observed compact peak over all corpus samples
was 163.8 MiB, approximately 172 MB decimal. These data use the same inputs
as the published corpus, but timings here compare our two native builds.

With affinity restricted to one CPU, three samples per build/fixture:

| Fixture | Dense median | Compact median | Compact peak RSS¹ |
| --- | ---: | ---: | ---: |
| Capture | 8.664 s | 8.659 s | 147.7 MiB |
| Filtering | 7.786 s | 4.610 s | 146.0 MiB |

Single-CPU captured recovery time was unchanged; filtering recovery improved
by approximately 41%. Both retained the memory reduction.

## Recovery-time pass after snapshot `38498e99`

This pass balances both register halves across every reduction worker. Each
worker still retains one scratch domain and one scratch nonce map. The last
map in each half already includes the preceding low-20-bit restrictions:
projecting those worker endpoints gives exactly the same shared domain as
projecting every map. Exhaustive snapshots verify this for both fixtures,
the all-one-key input and empty input, with one/three/four workers and failed
thread launches.

Counts visit only nonzero domain words. Partial-sum a8 tables construct the
low-20-bit region once and copy it into the other fifteen identical regions
after all construction workers join. All table bits matched scalar construction
for CPU counts 1, 3, 6 and 8, including launch failures.

Runtime page hashing now uses independent weighted products and final mixing;
full comparisons still determine page equality. GNU/glibc x86-64 builds select
AVX2 versions of hot kernels when supported. Other compilers/platforms keep
portable kernels. `-DHN_DISABLE_SIMD` explicitly tests the portable path;
portable, Clang and LOWMEM recovery checks passed. CI checks the portable build.

Five fresh-process samples per build/fixture on the same four-CPU Xeon host,
sequentially with alternating build order; optimized timings use AVX2 dispatch:

| Fixture | Snapshot median | Current median | Snapshot peak RSS¹ | Current peak RSS¹ |
| --- | ---: | ---: | ---: | ---: |
| Capture | 2.968 s | 1.670 s | 162.8 MiB | 168.2 MiB |
| Filtering | 2.167 s | 1.315 s | 159.8 MiB | 163.7 MiB |

¹ Median of process peaks, including the same Python harness. Recovery time
fell by 39–44%; peak RSS increased by approximately 4–5 MiB, remaining around
164–168 MiB (172–176 MB decimal). These are fixture-specific desktop results;
mobile/ARM timing remains unmeasured. Native page/table/candidate checks, six
complete recoveries, exact reduction comparisons and ASan/UBSan passed.
Cancellation followed by successful recovery in the same process passed under
ASan/UBSan; leak detection was disabled only for the Python-hosted calls.

Three fresh-process samples per build/fixture with affinity restricted to one CPU:

| Fixture | Snapshot median | Current median | Current peak RSS¹ |
| --- | ---: | ---: | ---: |
| Capture | 8.560 s | 4.305 s | 147.8 MiB |
| Filtering | 4.571 s | 2.598 s | 146.0 MiB |

Both single-CPU fixtures improved (43–50%), with essentially unchanged peak RSS.

The eight-case corpus passed again with one fresh-process recovery per case.
These are correctness runs, not repeated paired timing comparisons:

| Case | Recovery time | Peak RSS |
| --- | ---: | ---: |
| reference | 1.297 s | 162.1 MiB |
| sparse | 1.142 s | 167.2 MiB |
| ones-sparse | 77.269 s | 161.4 MiB |
| zero | 0.720 s | 156.9 MiB |
| transport | 1.093 s | 160.5 MiB |
| mixed | 1.557 s | 171.8 MiB |
| new-seed | 1.182 s | 162.8 MiB |
| ones-dense | 57.824 s | 159.3 MiB |

The largest observed corpus peak was 171.8 MiB (about 180 MB decimal),
approximately 8 MiB above the snapshot corpus maximum. The long all-one-key
cases remain dominated by the unchanged brute-force search; the 1.3–1.7 s
result applies to the two stored benchmark fixtures.
