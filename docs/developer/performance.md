# Performance: podoc and pandoc

Measured 2026-11-20, at 48a6875 (after the performance fixes of
b725290), with `tools/bench`.

**podoc is faster than pandoc on every input and output measured, and
it uses less memory.**

- **Small and medium inputs:** podoc is 2–9× faster, and uses 3–40 MiB
  where pandoc uses 23–234 MiB.
- **3 MB input:** podoc is 2.3–7.9× faster.
- **The user's Lost-Worlds builds:** podoc is about 65× faster, mostly
  because pandoc runs `pandoc-include`, a Python filter.

The layout writers' memory use on large inputs is the exception, and
an open problem: see `docs/developer/memory-use-problem.md`.

## How it was measured

- **Machine:** atla, an i9-13900HX running Fedora 44 (Linux 7.2). Each
  run used one thread, with the machine otherwise lightly loaded.
- **pandoc:** pandoc 3.10, `~/.cabal/bin/pandoc`, run as
  `pandoc --wrap=none --syntax-highlighting=none -f markdown -t FORMAT`.
- **podoc:** both builds, `build/OC/podoc` and `build/O2/podoc`, run as
  `podoc --wrap=none -t FORMAT`.
- **Inputs:**
  - an empty file;
  - pandoc's `test/testsuite.txt` (9 KB);
  - Lost-Worlds' `001-breakout.md`, without its includes (50 KB);
  - pandoc's `MANUAL.txt` (300 KB);
  - `MANUAL.txt` ten times over (3 MB).
- **Runs:** each case was run once to warm the file cache, then 20 times
  for the empty file and testsuite, 10 for breakout, 5 for MANUAL and 3
  for MANUAL ×10.
- **Reported:** the median wall-clock time, the median CPU time
  (user + system) and the largest peak RSS.
- **Peak RSS is GNU time's `%M`**, taken for the measured program
  alone. Measuring it from Python's `wait4` would be wrong: Linux keeps
  a child's peak RSS across `exec`, so a child forked from Python
  reports Python's 8–16 MiB as its own. That error inflated podoc's
  small-input figures to 7.8 MiB in the first comparison earlier the
  same day.
- **Run under a memory cap:**
  `systemd-run --user --scope -q -p MemoryMax=16G -p MemorySwapMax=0`
  (8G for the PDF runs).

To repeat it:

```sh
make
systemd-run --user --scope -q -p MemoryMax=16G -p MemorySwapMax=0 tools/bench convert build
systemd-run --user --scope -q -p MemoryMax=8G -p MemorySwapMax=0 tools/bench pdf
```

See the header of `tools/bench` for its settings (`PANDOC`,
`PANDOC_SRC`, `LOST_WORLDS`, `RUNS`, `BENCH_JSON`). Running every
case takes about 12 minutes.

CPU time is within a few percent of wall time for both programs:
neither runs work in parallel. The tables give wall time.

## Conversion, `--wrap=none`

The `-OC` build. The ratio is pandoc's time ÷ podoc's.

| Input | Output | pandoc | podoc | Ratio |
|---|---|---:|---:|---:|
| empty | all | 7–11 ms, 23–27 MiB | 4–5 ms, 3.7 MiB | 1.7–2.2× |
| testsuite (9 KB) | all | 50–54 ms, 120–122 MiB | 7–11 ms, 4–6 MiB | 4.9–6.8× |
| breakout (50 KB) | json | 64 ms, 122 MiB | 13 ms, 5.5 MiB | 5.0× |
| | html | 75 ms, 123 MiB | 15 ms, 7.3 MiB | 5.1× |
| | ms | 77 ms, 124 MiB | 24 ms, 12.8 MiB | 3.2× |
| | context | 73 ms, 122 MiB | 24 ms, 10.8 MiB | 3.1× |
| | markdown | 90 ms, 133 MiB | 28 ms, 12.5 MiB | 3.2× |
| | plain | 86 ms, 133 MiB | 22 ms, 12.2 MiB | 4.0× |
| MANUAL (300 KB) | json | 257 ms, 139 MiB | 29 ms, 11.5 MiB | 8.8× |
| | html | 303 ms, 144 MiB | 49 ms, 19.2 MiB | 6.2× |
| | ms | 502 ms, 230 MiB | 113 ms, 48.5 MiB | 4.4× |
| | context | 482 ms, 224 MiB | 83 ms, 36.2 MiB | 5.8× |
| | markdown | 355 ms, 175 MiB | 92 ms, 39.7 MiB | 3.9× |
| | plain | 336 ms, 175 MiB | 73 ms, 39.7 MiB | 4.6× |
| MANUAL ×10 (3 MB) | json | 2.18 s, 309 MiB | 0.28 s, 99 MiB | 7.9× |
| | html | 2.77 s, 415 MiB | 0.60 s, 138 MiB | 4.6× |
| | ms | 3.19 s, 510 MiB | 1.27 s, 445 MiB | 2.5× |
| | context | 2.96 s, 437 MiB | 1.21 s, 333 MiB | 2.5× |
| | markdown | 3.23 s, 610 MiB | 1.40 s, 359 MiB | 2.3× |
| | plain | 2.99 s, 600 MiB | 1.21 s, 355 MiB | 2.5× |

- **Startup:** pandoc takes about 7 ms and 23 MiB before reading
  anything; podoc takes about 4 ms and 3.7 MiB. Of podoc's 4 ms, about
  1.5 ms is GNU time's own startup, which the empty-file and testsuite
  times include. Without it, podoc takes about 3 ms. Above 50 KB, this
  overhead doesn't matter.
- **pandoc needs 120 MiB as soon as there is any text**, even 9 KB.
  podoc's memory grows with the input.
- **The JSON and HTML writers scale well:** on MANUAL ×10, podoc uses a
  third of pandoc's memory.
- **The four layout writers (ms, ConTeXt, markdown and plain) do not.**
  On MANUAL ×10, they use 60–87% of pandoc's memory, and ms comes close
  to pandoc's. At 12 MB (MANUAL ×40), ms and markdown run out of poc's
  1 GB heap, which pandoc does not. See
  `docs/developer/memory-use-problem.md`.

## The -O2 build

`-O2` is as fast as `-OC`, to within noise. It uses less memory on
large inputs, presumably because its integers and `LONGINT`s are
smaller:

| MANUAL ×10 | json | html | ms | context | markdown | plain |
|---|---:|---:|---:|---:|---:|---:|
| `-OC` | 99 MiB | 138 MiB | 445 MiB | 333 MiB | 359 MiB | 355 MiB |
| `-O2` | 86 MiB | 125 MiB | 331 MiB | 260 MiB | 304 MiB | 307 MiB |

## Standalone (`-s`) and default wrapping

| Case | Input | pandoc | podoc | Ratio |
|---|---|---:|---:|---:|
| `-s` html / ms / context | breakout | 86 / 78 / 79 ms | 23 / 23 / 26 ms | 3.1–3.7× |
| `-s` html / ms / context | MANUAL | 335 / 509 / 480 ms | 63 / 89 / 77 ms | 5.3–6.3× |
| wrapped plain / markdown / ms / context | MANUAL | 330 / 347 / 509 / 488 ms | 78 / 89 / 115 / 91 ms | 3.9–5.4× |

Memory with `-s` is within a few MiB of the same conversion without it,
for both programs.

## The Lost-Worlds builds

These run in the project's directory with its options and filters:

- **HTML** and **ConTeXt:** `001-breakout.md` with its includes.
- **Digest:** ten files combined into one ConTeXt document by
  `combine-docs.lua`.

pandoc runs `pandoc-include` (Python) and the Lua filters. podoc runs
its built-in versions and gets the substitutions with
`--metadata-file`, as `tools/subs2yaml` makes them.

| Build | pandoc | podoc | Ratio |
|---|---:|---:|---:|
| HTML | 1,902 ms, 135 MiB | 29 ms, 8.0 MiB | 66× |
| ConTeXt | 1,888 ms, 134 MiB | 29 ms, 12.5 MiB | 65× |
| Digest, 10 files | 301 ms, 139 MiB | 41 ms, 20.6 MiB | 7.4× |
| PDF through `context` | 2.93 s | 1.13 s | 2.6× |
| PDF through `pdfroff` | 2.01 s | 0.20 s | 9.9× |

- **Most of pandoc's time on the first two builds goes to
  `pandoc-include`**, a Python filter. The digest doesn't use it, so it
  is closer to a plain conversion.
- **The time for pandoc's ConTeXt build varies from run to run:** it
  took 1.3 s in an earlier run that day.
- **A PDF made through `context` is mostly ConTeXt's own time**, about
  1.1 s. The peak RSS for PDF runs is the largest of the whole process
  tree, so ConTeXt's 129 MiB shows on both sides.

## Executables

| | Size | Shared libraries |
|---|---:|---|
| pandoc 3.10 | 306 MB | libc, libm, libz, libgmp (Haskell and Lua linked in) |
| podoc `-OC` | 1.08 MB | libc, libm |
| podoc `-O2` | 1.08 MB | libc, libm |

## Before the performance fixes

The first comparison, earlier on 2026-11-20, before b725290. Its small-input memory figures are wrong (see above), but its
times hold.

Results:

- **Small and medium inputs:** the same as now, to within noise.
- **MANUAL ×10:** podoc was slower than pandoc, and four writers
  crashed.

| MANUAL ×10 | before | now |
|---|---:|---:|
| json | 2.42 s | 0.28 s |
| html | 2.74 s | 0.60 s |
| ms | 4.1 s, crashed (signal 11) | 1.27 s |
| context | 3.9 s, crashed (signal 11) | 1.21 s |
| markdown | 6.6 s, crashed (signal 11) | 1.40 s |
| plain | 6.2 s, crashed (signal 11) | 1.21 s |

## The changes that improved performance

All were made on 2026-11-20.

1. **`PdLayout` no longer recurses down long concatenations** (podoc
   b725290).
   - **The problem:** `Chomp` and `RemoveFinalNl` recursed down a
     document's right spine. They overflowed the stack (signal 11) for
     ms, ConTeXt, markdown and plain from about 1.2 MB of input.
   - **The fix:** both are loops now. They walk the spine with an
     explicit stack and rebuild it with `Cat`. `HasNewlines`,
     `MapText` and `AllText` now work on `Unfold`'s flat list of parts,
     with `Join`.
   - **The test:** `test/PdLayoutTest` checks these procedures on
     1,000,000-part left and right spines.
2. **The reader hashes header identifiers and reference keys** (podoc
   b725290).
   - **The problem:** `PdMarkdown` kept used identifiers, implicit
     header references and link reference keys in linear lists. Each
     new header searched the whole list, so the searches took quadratic
     time.
   - **The fix:** three 4,096-bucket hash tables keyed by
     `Ropes.Hash`, with `Find`, `Add` and `Remove`. `TableAt` removes
     the entries a table cell added when it rolls back. `-t json` on
     3 MB went from 2.41 s to 0.30 s.
3. **`Ropes.Equal` checks lengths first** (Ropes 7af2400).
   - **The problem:** `Equal` went through `Compare`, which allocates a
     walk stack for each rope, even when the lengths differ. That is
     why the linear searches made a quadratic number of allocations,
     which looked like the collector slowing down as the heap grew.
   - **The fix:** `Equal` compares the lengths first now, as
     `EqualNoCase` already did.
   - **The test:** a new RopeTest check catches an `Equal` that
     compares lengths only.
   - **What it does for podoc:** it benefits every caller, but on its
     own it doesn't remove the quadratic searches. Change 2 does that.

The memory use of the layout writers on large inputs is not fixed: see
`docs/developer/memory-use-problem.md`.
