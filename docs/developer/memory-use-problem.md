# podoc's memory use problem

Found 2026-11-20, after the performance fixes of that day (b725290):
the writers that lay text out through `PdLayout` (ms, ConTeXt,
markdown and plain) used a great deal of memory, and on large inputs
they ran out of poc's heap. Diagnosed and largely fixed the same day.
What is left is at the end.

## What was measured

pandoc 3.10's `MANUAL.txt` repeated 10 times (3 MB), `-OC` build, on
atla (i9-13900HX), with `/usr/bin/time`, `--wrap=none`:

| Output | Before: time | Before: peak RSS | After: time | After: peak RSS |
|---|---:|---:|---:|---:|
| json | 0.28 s | 101 MB | 0.29 s | 101 MB |
| html | 0.59 s | 141 MB | 0.63 s | 141 MB |
| ms | 1.27 s | 453 MB | 0.62 s | 140 MB |
| context | 1.20 s | 341 MB | 0.56 s | 142 MB |
| markdown | 1.40 s | 367 MB | 0.68 s | 140 MB |
| plain | 1.22 s | 364 MB | 0.54 s | 140 MB |

The "after" figures are `tools/bench`'s (median wall time; its
137–139 MiB are the 140–142 MB here). The layout writers now use what
the HTML writer uses. Under `-O2` they take about 125 MiB.

At ×40 (12 MB), `-t ms` and `-t markdown` used to reach poc's default
1 GB heap limit (`GarbageCollectedHeap.defaultHeapLimit`). The
collector then ran over and over for 2 to 4 minutes, `NEW` returned
NIL, and podoc stopped with "NIL pointer dereference". Now every
writer finishes:

| ×40 (12 MB) | json | html | ms | context | markdown | plain |
|---|---:|---:|---:|---:|---:|---:|
| time | 1.6 s | 3.0 s | 3.0 s | 2.7 s | 3.3 s | 2.8 s |
| peak RSS | 368 MB | 531 MB | 544 MB | 498 MB | 547 MB | 547 MB |

To repeat it:

```sh
for i in $(seq 10); do cat MANUAL.txt; echo; done > m10.md
/usr/bin/time -f '%e s %M KB' podoc --wrap=none -t ms -o /dev/null m10.md
```

## How it was measured

A temporary module, not committed, called `GarbageCollectedHeap.Census`
at the end of each step (reading, the body built, laid out, written).
`Census` collects first, so it counts only what is still reachable,
by type tag. For ms at ×10, before the fixes:

- **The heap grows to about twice the live memory**, and peak RSS is
  set while the body's `Doc` tree is being built.
- **2.58 million `Doc` nodes were live**, 1.72 million of them reachable
  from the body. The rest were `Chomp`'s copy of the body's spine.
- **The AST and its ropes took about 62 MB.**
- **The ms writer made a new rope leaf for every word**: 824,000
  leaves against the AST's 342,000. `EscapeStr` and `Literal` each took
  a `Ropes.Substring` of the whole word, and `Substring` copies a leaf
  even for its whole range.

## The fixes

All in `PdLayout` and the writers; output is unchanged. Each step was
checked against the build before it: `make test`, and podoc at HEAD
against the new podoc on 35,880 runs (test/cases, pandoc's
testsuite, tables, `MANUAL.txt` and test/command, Lost-Worlds and
Galactic-Bounty-Hunters; ms, context, markdown, plain, gfm and
commonmark; `--wrap=none`, `auto`, `preserve`, `auto --columns=30`
and `-s`), byte for byte.

1. **`Chomp` and `RemoveFinalNl` keep what they don't change.** They
   rebuild only the path to the last part, reusing every node whose
   right part is unchanged. Before, they copied the whole spine.
2. **Smaller `Doc` nodes.** `kind` is a `SYSTEM.INT8` and `n` a
   `SYSTEM.INT32`, so a node fits a 48-byte block, not 64. Spaces,
   carriage returns, new lines and single blank lines are shared nodes:
   a `Doc` is never changed once made.
3. **A streaming renderer.** doclayout flattens a document into a list,
   normalizes the list and renders it. `PdLayout` used to do the same,
   with a second node for every part. Now `RenderDoc` walks the tree
   and renders each part as it's reached. It holds back only what
   depends on what comes next:
   - the last part, which may yet collapse with the next;
   - a breaking space, until the next break;
   - a part printed only before something not blank, until the next
     part.
4. **No copy of a word that needs no change.** `PdMs.EscapeStr`
   returns its rope when nothing was escaped, and `Literal` makes a
   line of a rope without a new line directly.
5. **The body is laid out a block at a time.** Without a template,
   the ms, ConTeXt, markdown and plain writers give each top-level
   block to `PdLayout.Open`, `Put` or `PutAbove`, and `Close`. Each
   block is laid out, and can be collected, once the next block is
   made. `Close` chomps the last block (with any after it that chomp to
   nothing), so the output is what `Write(Chomp(body))` gave.
   `Render` may be called meanwhile: it saves and restores the layout
   state and uses a buffer of its own. The output is written out every
   64 KB.

Measured after each step, ms at ×10, peak RSS: 453 MB before, 329 MB
after 1, 317 MB after 2, 255 MB after 3, 217 MB after 4 and 140 MB
after 5.

**A quadratic lookup, found along the way.** At ×40, markdown and
plain took 15 s, against 3 s for ms. The markdown writer's `Used`
searched a linear list of the header identifiers used so far, as the
reader did before b725290. The list is now a hash table of 4,096
buckets keyed by `Ropes.Hash`, and plain takes 2.8 s at ×40.

## What is left

- **With a template (`-s`), the body is still built whole.** The
  template interpolates it as a `Doc`. At ×10, `-s -t ms` takes
  221 MB and `-s -t markdown` 278 MB. The user's documents, all far
  smaller, are built with `-s`.
- **ConTeXt's top-level blocks are its sections.** The writer wraps
  each section in a `Div` (`MakeSections`), so one level-one section
  is built whole at a time.
- **The AST is the rest.** At ×40 every writer, JSON included, needs
  370–550 MB, about 30–45 times the input: the AST, its ropes and the
  heap's room to grow. That is the reader's memory, not the layout
  writers'.
- **Running out of heap still ends in a NIL trap.** poc's
  `GarbageCollectedHeap.Allocate` answers 0 at the ceiling, and `NEW`
  gives NIL, with no hook for a message. A clear "out of memory" needs
  the runtime's help, or a check after every `NEW`.

## Allocation takes half the time

`perf` (cycles in user space, `-OC` build, `-t json` on MANUAL.txt
×1 to ×40), before the fixes, put poc's `GarbageCollectedHeap` at
45–52% of podoc's cycles at every size:

- `Allocate`: 20–24%;
- `TakeFromFreeList`: 9–13%;
- `MarkCandidate`: 7–10%.

The share doesn't grow with the input, so the collector scales; podoc
simply allocates a great deal. The fixes above allocate less, which is
why the layout writers got faster as well as smaller. Before the
fixes of 2026-11-20 (b725290, and Ropes 7af2400 for `Ropes.Equal`),
the share rose to 72% at ×10, which looked like the collector slowing
down. It was podoc's quadratic lookups (see
`docs/developer/performance.md`).
