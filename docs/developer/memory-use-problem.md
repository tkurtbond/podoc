# podoc's memory use problem

Found 2026-11-20, after the performance fixes of that day (b725290):
the writers that lay text out through `PdLayout` use a great deal of
memory, and on large inputs they run out of poc's heap. Recorded in
PLAN.md's "Later".

## What was measured

pandoc 3.10's `MANUAL.txt` repeated 10 times (3 MB), `-OC` build, on
atla (i9-13900HX), with `/usr/bin/time`:

| Output | Time | Peak RSS | RSS ÷ input |
|---|---:|---:|---:|
| json | 0.28 s | 101 MB | ~33× |
| html | 0.59 s | 141 MB | ~47× |
| context | 1.20 s | 341 MB | ~110× |
| plain | 1.22 s | 364 MB | ~120× |
| markdown | 1.40 s | 367 MB | ~120× |
| ms | 1.27 s | 453 MB | ~150× |

- The JSON writer adds little, so its 100 MB is roughly what reading
  costs: the AST, its ropes and the reader's tables.
- HTML adds about 40 MB.
- The four writers that lay text out through `PdLayout` add another
  240–350 MB.
- At ×40 (12 MB), `-t ms` and `-t markdown` reach poc's default 1 GB
  heap limit (`GarbageCollectedHeap.defaultHeapLimit`). The collector
  then runs over and over for 2 to 4 minutes (243 s for ms, 119 s for
  markdown), `NEW` returns NIL, and podoc stops with "NIL pointer
  dereference" rather than an error message.

To repeat it:

```sh
for i in $(seq 10); do cat MANUAL.txt; echo; done > m10.md
/usr/bin/time -f '%e s %M KB' podoc -t ms -o /dev/null m10.md
```

## Unknown: how much is still in use

- **RSS also counts garbage that hasn't been collected yet.** Before
  that day's fixes, a gdb breakpoint on `GarbageCollectedHeap.Collect`
  was hit only once per run, even at ×10. The heap grows rather than
  collecting, so the 450 MB may be mostly garbage.
- **The collection count hasn't been re-checked since the fixes.**
- **Failing at 1 GB does show that the memory still in use at ×40 is
  large**, but how large has not been measured.

## Allocation takes half the time

`perf` (cycles in user space, `-OC` build, `-t json` on MANUAL.txt
×1 to ×40) put poc's `GarbageCollectedHeap` at 45–52% of podoc's
cycles at every size:

- `Allocate`: 20–24%;
- `TakeFromFreeList`: 9–13%;
- `MarkCandidate`: 7–10%.

The share doesn't grow with the input, so the collector scales; podoc
simply allocates a great deal. Fewer allocations, the aim of the likely
fixes at the end of this note, would make podoc faster as well as smaller. Before the fixes
of 2026-11-20 (b725290, and Ropes 7af2400 for `Ropes.Equal`), the
share rose to 72% at ×10, which looked like the collector slowing
down. It was podoc's quadratic lookups (see
`docs/developer/performance.md`).

## Suspects

These come from reading the code; none has been measured. The layout
writers keep several full copies of the document:

1. **The `Doc` tree.** The writer builds the whole document as one tree
   before laying anything out. Every word, space and break is its own
   node, and each word also gets its own rope.
2. **`Unfold`'s array.** It holds one pointer per part. It grows by
   doubling, so the old arrays become garbage.
3. **`Flatten`'s list.** It makes a second node for every part, and
   `Normalize` then walks it.
4. **The output buffer.** It grows by doubling through `PdIO.Reserve`,
   and `Render` then copies it into a rope.
5. **Templates (`-s`).** The body goes through a template as a `Doc`
   and is laid out again.
6. **Rebuilding concatenations.** `Chomp`, `Delimited`,
   `SplitSentences` and similar procedures rebuild trees with `Unfold`
   and `Join`, which allocates more nodes and arrays.

pandoc avoids most of this: Haskell's laziness lets doclayout consume
the document as it's produced. podoc builds everything first.

## Does it matter

- **Not for the user's documents, which are far smaller than 12 MB.**
  Nothing fails today.
- **It limits large inputs.**
- **It may matter on the small systems podoc is meant for**, where
  1 GB may not be available at all.

## Finding out properly

What it would take:

1. **Measure the memory actually in use.** Force a collection at the
   end of each step (reading, writing, layout, template) and read the
   heap size.
2. **Count what each kind of allocation contributes**: `Doc`, `Flat`,
   ropes and buffers.

Likely fixes, once that is known:

- **Lay out and write each block as it's done**, instead of the whole
  body at once.
- **Drop the intermediate copies** listed above.
- **End with a clear "out of memory" message** instead of a NIL trap
  when the heap runs out. This is needed whatever else is done.
