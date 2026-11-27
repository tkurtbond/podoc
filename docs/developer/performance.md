# Performance: podoc and pandoc

Measured 2026-11-20 with `tools/bench`, after the performance fixes of
b725290 and the memory fixes made later that day, the last of which
lays the body out a block at a time with a template too (see
`docs/developer/memory-use-problem.md`).

**podoc is faster than pandoc on every input and output measured, and
it uses less memory.** Times are wall-clock; neither program works in
parallel, so CPU time is within a few percent of them. Memory is peak
RSS.

| | podoc is faster by | podoc's memory | pandoc's memory | pandoc uses more by |
|---|---:|---:|---:|---:|
| Small and medium inputs (up to 300 KB) | 1.9–11× | 4–23 MiB | 23–234 MiB | 6–29× |
| 3 MB input | 4.5–7.7× | 99–141 MiB | 309–610 MiB | 3.0–4.5× |
| The user's Lost-Worlds builds | 8–68× | 8–14 MiB | 135–140 MiB | 10–17× |
| reStructuredText, up to 180 KB (2026-11-21) | 3.3–28× | 5–19 MiB | 117–204 MiB | 7–26× |
| reStructuredText, 1.8 MB (2026-11-21) | 3.2–4.3× | 86–125 MiB | 274–337 MiB | 2.3–3.5× |

The Lost-Worlds builds that use `pandoc-include` are about 65× faster,
mostly because pandoc runs that Python filter.

The layout writers' memory use on large inputs, the exception before,
is fixed: see `docs/developer/memory-use-problem.md`. Above about
35 MB, podoc needs a larger heap than poc's default 1 GB
(`PODOC_HEAP_LIMIT`); with it, podoc is still 3.2–3.5× faster at 45 MB,
in about half pandoc's memory (see "Very large inputs").

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
systemd-run --user --scope -q -p MemoryMax=16G -p MemorySwapMax=0 tools/bench rst
systemd-run --user --scope -q -p MemoryMax=12G -p MemorySwapMax=0 tools/bench org
```

See the header of `tools/bench` for its settings (`PANDOC`,
`PANDOC_SRC`, `LOST_WORLDS`, `RST_SRD`, `RST_MERCHANT`, `ORG_LARGE`, `RUNS`,
`BENCH_JSON`). Running every
case takes about 12 minutes.

CPU time is within a few percent of wall time for both programs:
neither runs work in parallel. The tables give wall time.

## Conversion, `--wrap=none`

The `-OC` build. The ratios are pandoc's time ÷ podoc's and pandoc's
peak RSS ÷ podoc's.

| Input | Output | pandoc | podoc | Time ratio | Memory ratio |
|---|---|---:|---:|---:|---:|
| empty | all | 9–12 ms, 23–27 MiB | 2.5–4.9 ms, 3.8 MiB | 1.9–3.7× | 6–7× |
| testsuite (9 KB) | all | 49–55 ms, 120–122 MiB | 4–10 ms, 4–5 MiB | 5.4–11.4× | 25–29× |
| breakout (50 KB) | json | 68 ms, 122 MiB | 12 ms, 5.6 MiB | 5.7× | 22× |
| | html | 74 ms, 123 MiB | 20 ms, 7.3 MiB | 3.7× | 17× |
| | ms | 76 ms, 123 MiB | 21 ms, 7.3 MiB | 3.7× | 17× |
| | context | 74 ms, 122 MiB | 22 ms, 8.0 MiB | 3.4× | 15× |
| | markdown | 89 ms, 133 MiB | 19 ms, 7.1 MiB | 4.6× | 19× |
| | plain | 85 ms, 133 MiB | 20 ms, 7.3 MiB | 4.4× | 18× |
| MANUAL (300 KB) | json | 257 ms, 138 MiB | 29 ms, 11.6 MiB | 8.9× | 12× |
| | html | 310 ms, 144 MiB | 56 ms, 19.1 MiB | 5.6× | 7.5× |
| | ms | 507 ms, 230 MiB | 50 ms, 18.3 MiB | 10.1× | 12.6× |
| | context | 489 ms, 224 MiB | 48 ms, 21.9 MiB | 10.2× | 10.2× |
| | markdown | 356 ms, 175 MiB | 52 ms, 18.0 MiB | 6.8× | 9.7× |
| | plain | 336 ms, 175 MiB | 44 ms, 17.7 MiB | 7.6× | 9.9× |
| MANUAL ×10 (3 MB) | json | 2.21 s, 309 MiB | 0.29 s, 99 MiB | 7.7× | 3.1× |
| | html | 2.75 s, 415 MiB | 0.61 s, 138 MiB | 4.5× | 3.0× |
| | ms | 3.24 s, 510 MiB | 0.59 s, 137 MiB | 5.5× | 3.7× |
| | context | 2.96 s, 436 MiB | 0.56 s, 141 MiB | 5.3× | 3.1× |
| | markdown | 3.18 s, 610 MiB | 0.65 s, 137 MiB | 4.9× | 4.5× |
| | plain | 2.98 s, 599 MiB | 0.53 s, 137 MiB | 5.6× | 4.4× |

- **Startup:** pandoc takes about 9 ms and 23 MiB before reading
  anything; podoc takes about 4 ms and 3.8 MiB. Of podoc's 4 ms, about
  1.5 ms is GNU time's own startup, which the empty-file and testsuite
  times include. Without it, podoc takes about 3 ms. Above 50 KB, this
  overhead doesn't matter.
- **pandoc needs 120 MiB as soon as there is any text**, even 9 KB.
  podoc's memory grows with the input.
- **Every writer scales:** on MANUAL ×10, podoc uses a third of
  pandoc's memory or less. The layout writers (ms, ConTeXt, markdown
  and plain) used 333–445 MiB before the memory fixes; now they use
  what the HTML writer uses. At 12 MB (MANUAL ×40), every writer
  finishes in 1.6–3.3 s within 370–550 MiB, where ms and markdown used
  to run out of poc's 1 GB heap.

## The -O2 build

`-O2` is as fast as `-OC`, to within noise. It uses less memory on
large inputs, presumably because its integers and `LONGINT`s are
smaller. These figures are from the run before the template change,
which doesn't touch conversions without `-s`:

| MANUAL ×10 | json | html | ms | context | markdown | plain |
|---|---:|---:|---:|---:|---:|---:|
| `-OC` | 99 MiB | 138 MiB | 137 MiB | 139 MiB | 137 MiB | 137 MiB |
| `-O2` | 86 MiB | 125 MiB | 125 MiB | 126 MiB | 125 MiB | 125 MiB |

## Standalone (`-s`) and default wrapping

| Case | Input | pandoc | podoc | Ratio |
|---|---|---:|---:|---:|
| `-s` html / ms / context | breakout | 85 / 81 / 75 ms | 21 / 18 / 20 ms | 3.8–4.6× |
| `-s` html / ms / context | MANUAL | 330 / 521 / 484 ms | 65 / 52 / 56 ms | 5.1–10.1× |
| `-s` html / ms / context, memory | MANUAL | 147 / 234 / 219 MiB | 18.9 / 18.8 / 23.3 MiB | 7.8–12.4× |
| wrapped plain / markdown / ms / context | MANUAL | 334 / 350 / 500 / 480 ms | 44 / 55 / 50 / 51 ms | 6.4–9.9× |

With `-s`, podoc takes at most 1.4 MiB more than without it. Before
the template change (see `docs/developer/memory-use-problem.md`), the
body was built whole before it was laid out, and ms and ConTeXt took
5–7 MiB more with `-s` on MANUAL: ms 25.7 MiB, ConTeXt 24.1 MiB.
pandoc's memory is within a few MiB either way.

## Very large inputs

MANUAL ×150 (45 MB), measured 2026-11-20 with `/usr/bin/time`, one run
each, not `tools/bench`. podoc's heap may grow to poc's default
limit, 1 GB, which this input passes. At that limit podoc ran for
6 min 15 s before it stopped with "heap exhausted" (status 11): near
the limit, poc's collector runs a full collection for nearly every
allocation (Peaseblossom's "Ongoing implementation enhancements", 16).
With the limit raised by `PODOC_HEAP_LIMIT` (decision 24), every writer
finishes:

| MANUAL ×150, `--wrap=none` | pandoc | podoc `-OC` | Time ratio | Memory ratio |
|---|---:|---:|---:|---:|
| json | 34.1 s, 2.89 GiB | 9.6 s, 1.56 GiB | 3.5× | 1.9× |
| ms | 45.8 s, 4.60 GiB | 14.4 s, 1.94 GiB | 3.2× | 2.4× |
| html | | 14.8 s, 1.92 GiB | | |
| context | | 14.2 s, 1.96 GiB | | |
| markdown | | 17.6 s, 1.96 GiB | | |

- **Limits used:** 3 GB for json and ms, 4 GB for the others. 2 GB was
  enough for json; the larger limit made no difference to it.
- **`-O2`:** json 9.6 s, 1.51 GiB; ms 14.7 s, 1.78 GiB.
- **podoc's time grows faster than its input.** From ×10 to ×150, 15
  times the input, podoc's times grow 24–27 times for the layout
  writers and HTML and 33 times for JSON, against about 15 times for
  pandoc's. Its memory grows 16 times (json, 99 MiB to 1.56 GiB),
  pandoc's about 10 times. Most likely each collection marks a larger
  live heap, but this was not measured.

## reStructuredText

Measured 2026-11-21 with `tools/bench rst`, after the fixes listed
as change 6 and change 8 below. pandoc was run as podoc was:
`--wrap=none -f rst -t FORMAT`. podoc's output was pandoc's JSON, byte
for byte, on every input here, under both models.

| Input | Format | pandoc | podoc `-OC` | Faster by |
|---|---|---:|---:|---:|
| pandoc's `test/rst-reader.rst` (10 KB) | json | 42 ms, 118 MiB | 6.2 ms, 5.3 MiB | 6.8× |
| | html | 225 ms, 204 MiB | 8.8 ms, 5.3 MiB | 26× |
| | ms | 225 ms, 203 MiB | 8.0 ms, 5.3 MiB | 28× |
| | context | 51 ms, 123 MiB | 7.8 ms, 5.3 MiB | 6.5× |
| pandoc's `test/tables.rst` | json, html | 27 ms, 117 MiB | 3.7–3.8 ms, 4.5–4.7 MiB | 7.2–7.4× |
| | ms, context | 27–30 ms, 117 MiB | 8.3–8.4 ms, 5.0–5.1 MiB | 3.3–3.5× |
| The Mini Six SRD (179 KB) | json | 309 ms, 133 MiB | 47 ms, 12.5 MiB | 6.5× |
| | html | 341 ms, 137 MiB | 63 ms, 14.8 MiB | 5.4× |
| | ms | 342 ms, 138 MiB | 73 ms, 14.0 MiB | 4.7× |
| | context | 342 ms, 133 MiB | 68 ms, 18.5 MiB | 5.0× |
| The SRD ×10 (1.8 MB) | json | 2.72 s, 274 MiB | 0.63 s, 86 MiB | 4.3× |
| | html | 3.13 s, 337 MiB | 0.86 s, 108 MiB | 3.7× |
| | ms | 3.10 s, 311 MiB | 0.98 s, 95 MiB | 3.2× |
| | context | 3.08 s, 290 MiB | 0.97 s, 125 MiB | 3.2× |
| The merchant scenario (47 KB, 11 includes) | all four | 122–135 ms, 123–124 MiB | 25–30 ms, 7.8–8.3 MiB | 4.5–4.8× |

pandoc's html and ms on `rst-reader.rst` take about five times its
json. Why was not found: removing the lines that mention math made no
difference.

**Stress inputs.** Generated by `tools/bench`, 12,000 items each, to
json. Each was quadratic or worse in podoc before change 6; "before"
is the `-OC` build at 5e2f6e4, timed once with `/usr/bin/time`.

| 12,000 | Before | pandoc | podoc `-OC` | Faster by |
|---|---:|---:|---:|---:|
| anonymous references | 4.83 s | 2.02 s, 167 MiB | 0.12 s, 27 MiB | 17× |
| substitutions | 11.06 s | 0.98 s, 158 MiB | 0.18 s, 34 MiB | 5.3× |
| footnotes | 5.00 s | 1.87 s, 164 MiB | 0.18 s, 33 MiB | 10× |
| citations | 3.73 s | 1.30 s, 187 MiB | 0.27 s, 53 MiB | 4.8× |
| section titles, 50 repeated | 397.73 s | 1.17 s, 182 MiB | 0.18 s, 40 MiB | 6.4× |

- **Other constructs, not quadratic before either:** named hyperlink
  references and targets, standalone URIs, directives, line blocks,
  literal blocks, definition lists, field lists, nested lists, grid
  and simple tables and paragraphs. At 3,000 to 12,000 items, podoc
  was 10–20× faster than pandoc in about a seventh of its memory.
  These were timed once each with `/usr/bin/time`, not by
  `tools/bench`.
- **Past `-60000`:** 60,005 identical titles took pandoc 258 s and
  podoc 0.67 s, with the same output: pandoc's `uniqueIdent` searches
  every suffix from `-1` for each title, and repeats the base after
  `-60000`. podoc does the same, but starts from the last suffix it
  tried. Markdown is the same: 257 s against 0.34 s.
- **`-O2`:** within 10% of `-OC` for time, and 5–20% less memory.
- **Time grows a little faster than the input,** as for markdown: the
  SRD ×10 takes 13–14 times as long as the SRD in podoc, against about
  9 times in pandoc. 48,000 identical titles take 0.52 s against
  0.18 s for 24,000.

## Org mode

Measured 2026-11-26 with `tools/bench org`, after change 9 below.
pandoc was run as podoc was: `--wrap=none -f org -t FORMAT`. podoc's
JSON is pandoc's, byte for byte, on every input here. The largest of
the user's Org files is 502 KB, with 3,288 headlines; ×10 is that
file ten times over.

| Input | Format | pandoc | podoc `-OC` | Faster by |
|---|---|---:|---:|---:|
| pandoc's `test/writer.org` | json | 45 ms, 121 MiB | 8.6 ms, 5.3 MiB | 5.2× |
| | html | 336 ms, 283 MiB | 6.1 ms, 5.5 MiB | 55× |
| | ms | 343 ms, 291 MiB | 10.8 ms, 5.4 MiB | 32× |
| | context | 324 ms, 279 MiB | 6.3 ms, 5.5 MiB | 51× |
| pandoc's `test/tables.org` | all four | 9.5–11.7 ms, 34–37 MiB | 3.1–3.4 ms, 4.5–4.8 MiB | 3.1–3.5× |
| The largest Org file (502 KB) | json | 463 ms, 161 MiB | 93 ms, 28 MiB | 5.0× |
| | html | 562 ms, 171 MiB | 130 ms, 36 MiB | 4.3× |
| | ms | 676 ms, 234 MiB | 134 ms, 29 MiB | 5.0× |
| | context | 561 ms, 165 MiB | 175 ms, 47 MiB | 3.2× |
| The largest ×10 (5 MB) | json | 4.34 s, 494 MiB | 1.25 s, 229 MiB | 3.5× |
| | html | 5.44 s, 644 MiB | 1.85 s, 313 MiB | 2.9× |
| | ms | 6.44 s, 1,260 MiB | 2.55 s, 313 MiB | 2.5× |
| | context | 5.52 s, 650 MiB | 2.45 s, 313 MiB | 2.3× |

pandoc's html, ms and context on `writer.org` take seven times its
json, as for rST's `rst-reader.rst`. Before change 9, podoc's ms on
the largest ×10 took 7.0 s, slower than pandoc, and its ConTeXt 3.9 s.

**Stress inputs.** Generated by `tools/bench`, 12,000 items each, to
json. Notes and targets were quadratic before change 9 (4.57 s and
3.82 s).

| 12,000 | pandoc | podoc `-OC` | Faster by |
|---|---:|---:|---:|
| footnotes, each referenced | 1.45 s, 155 MiB | 0.11 s, 37 MiB | 13× |
| headlines, repeated, linked to by name | 0.83 s, 161 MiB | 0.14 s, 42 MiB | 6.1× |
| targets, each linked | 0.83 s, 149 MiB | 0.12 s, 38 MiB | 6.9× |

**`-O2`:** as fast as `-OC` or up to 16% faster, in 0–15% less
memory. html on the two small files varies between runs of the bench
for both models: 6–11 ms on `writer.org` and 3.4–6.4 ms on
`tables.org`.

## The Lost-Worlds builds

These run in the project's directory with its options and filters:

- **HTML** and **ConTeXt:** `001-breakout.md` with its includes.
- **Digest:** ten files combined into one ConTeXt document by
  `combine-docs.lua`.

pandoc runs `pandoc-include` (Python) and the Lua filters. podoc runs
its built-in versions and gets the substitutions with
`--metadata-file`, as `tools/subs2yaml` makes them.

| Build | pandoc | podoc | Time ratio | Memory ratio |
|---|---:|---:|---:|---:|
| HTML | 1,883 ms, 135 MiB | 28 ms, 8.0 MiB | 68× | 17× |
| ConTeXt | 1,898 ms, 135 MiB | 30 ms, 8.2 MiB | 64× | 16× |
| Digest, 10 files | 300 ms, 140 MiB | 37 ms, 13.5 MiB | 8.1× | 10.4× |
| PDF through `context` | 2.96 s | 1.13 s | 2.6× | |
| PDF through `pdfroff` | 2.02 s | 0.21 s | 9.6× | |

- **The ConTeXt build and the digest use templates.** Before the
  template change, podoc took 12.5 and 20.6 MiB for them.
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

The first comparison, earlier on 2026-11-20, before b725290 and the
memory fixes. Its small-input memory figures are wrong (see above), but its
times hold.

Results:

- **Small and medium inputs:** the same as now, to within noise.
- **MANUAL ×10:** podoc was slower than pandoc, and four writers
  crashed.

| MANUAL ×10 | before | after b725290 | now |
|---|---:|---:|---:|
| json | 2.42 s | 0.28 s | 0.29 s |
| html | 2.74 s | 0.60 s | 0.61 s |
| ms | 4.1 s, crashed (signal 11) | 1.27 s, 445 MiB | 0.59 s, 137 MiB |
| context | 3.9 s, crashed (signal 11) | 1.21 s, 333 MiB | 0.56 s, 141 MiB |
| markdown | 6.6 s, crashed (signal 11) | 1.40 s, 359 MiB | 0.65 s, 137 MiB |
| plain | 6.2 s, crashed (signal 11) | 1.21 s, 355 MiB | 0.53 s, 137 MiB |

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

4. **The layout writers use far less memory.**
   - **The problem:** ms, ConTeXt, markdown and plain used 333–445 MiB
     on MANUAL ×10, and ms and markdown ran out of poc's 1 GB heap at
     ×40.
   - **The fix:** `Chomp` keeps the nodes it doesn't change; `Doc`
     nodes are smaller and the breaks shared; `PdLayout` renders as it
     walks the tree, without a flattened copy; the ms writer no longer
     copies words that need no escaping; and the body is laid out a
     block at a time (`PdLayout.Open`, `Put`, `PutAbove`, `Close`),
     with a template too (`PdTemplate.Slot`, `PdLayout.OpenWhole`). The details, with what each step saved, are
     in `docs/developer/memory-use-problem.md`.
   - **What it does:** 137–141 MiB on MANUAL ×10, as the HTML writer,
     and about twice as fast.
5. **The markdown writer hashes header identifiers.**
   - **The problem:** `PdMdWriter.Used` searched a linear list, so
     markdown and plain took quadratic time: 15 s at ×40, against 3 s
     for ms.
   - **The fix:** a 4,096-bucket hash table keyed by `Ropes.Hash`, as
     the reader's. Plain takes 2.8 s at ×40.

6. **The rST reader's tables are hashed, and the searches start where
   they stopped** (2026-11-21; see "reStructuredText").
   - **The problems:** each was quadratic or worse in the number of
     items, so 12,000 of them took seconds or minutes.
     - Anonymous references (`__`): `FirstAnonymous` searched every
       key for the least one starting with `_` (4.83 s).
     - Substitution definitions and footnotes were linear lists, and
       resolving each reference searched them (11.06 s and 5.00 s).
     - Citations were kept sorted by inserting into a linked list
       (3.73 s).
     - Section identifiers were a linear list, and each repeated title
       tried `-1`, `-2`, … from the start (cubic: 397.73 s).
   - **The fixes:**
     - The keys starting with `_` are kept in a min-heap, in
       `Ropes.Compare`'s order. A deleted key stays until it reaches
       the top.
     - Footnotes, substitutions, citations and identifiers are in hash
       tables. Citations are sorted once, by a merge sort, when the
       citations `Div` is made.
     - Each identifier records the last suffix tried with it as the
       base. Identifiers are never removed, so the next search starts
       there.
   - **A bug found on the way:** an anonymous key was `_` and the key
     count modulo 10,000. Past 9,999 anonymous targets, keys collided
     and gave "Anonymous reference with no target" warnings. They are
     pandoc's full `_%04d` now.
7. **The markdown reader resumes its identifier suffixes too.** Each
   of 12,000 headers repeating 50 titles took 1.64 s, against pandoc's
   0.64 s, because `RegisterHeader` retried from `-1`. A table of
   bases now holds the last suffix tried. It is cleared when `TableAt`
   takes identifiers back out, since a suffix may then be free again.
   That input now takes 0.06 s. Both readers stop at `-60000` and
   repeat the base after that, as pandoc's `uniqueIdent` does.
8. **The hash tables have a prime number of buckets.** `Ropes.Hash` is
   sdbm, and modulo 4,096 its low bits leave most buckets empty for
   keys that differ only in their last characters: 48,000 identifiers
   `t-1` … `t-48000` fell into 1,541 of 4,096 buckets, up to 125 to a
   bucket. With 4,093 buckets, every bucket is used, with at most 22
   in any. The reader's, the rST reader's and the markdown writer's
   tables all have 4,093 now. 48,000 identical rST titles went from
   0.87 s to 0.52 s.
9. **The Org reader's notes and anchors are hashed, and the roff and
   ConTeXt writers build escapes in a buffer.** 12,000 Org notes went
   from 4.57 s to 0.11 s and 12,000 targets from 3.82 s to 0.11 s:
   both were lists searched for each reference. Anchors can be taken
   back by backtracking, so they are indexed when a link is resolved,
   from the newest to the newest indexed before. The ms writer
   escaped each header's PDF bookmark, and made its ASCII anchor, a
   character at a time, and ConTeXt its labels: on the largest Org
   file ×10, with 32,880 headlines, collection took most of the
   time. Filling a buffer and making one rope took ms from 7.0 s to
   2.8 s and ConTeXt from 3.9 s to 2.6 s, under `-OC`; the ms writer
   also makes the bookmark only for a PDF engine and the backlink
   only for the table of contents.

Each was checked by comparing podoc's output before and after on
35,910 runs over the test cases, pandoc's tests and MANUAL, and the
Lost-Worlds and Galactic-Bounty-Hunters files, in six formats with
five sets of options: none differed.
