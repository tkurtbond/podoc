# Size comparisons: podoc and pandoc

Measured 2026-11-20, at Phase 18.3 (emoji widths).

Overall, for features podoc and pandoc both have, podoc is about the
same size: **18,500 lines of code against pandoc's 21,500**, a ratio
of 0.86. That ratio overstates how dense Haskell is, though, because
most of the pandoc files counted also implement things podoc doesn't.

## How it was counted

- **Pairing:** each group of podoc modules is paired with the pandoc
  3.10 files or Hackage packages that do the same job. The packages are
  the versions pandoc 3.10 builds against (pandoc-types 1.23.1,
  doclayout 0.5, doctemplates 0.11.1, yaml 0.11.11.2), unpacked from
  `~/.cabal/packages`.
- **"Code":** non-blank, non-comment lines. Haskell, Lua, Python and C
  were counted with tokei 15.0.0. Oberon was counted with a small
  script that strips nested `(* *)` comments.
- **Repeating it:** `tools/sizes` makes these tables (see its header
  for the paths it uses).

| Feature | podoc modules | podoc lines / code | pandoc counterpart | pandoc lines / code | podoc ÷ pandoc (code) |
|---|---|---:|---|---:|---:|
| Markdown reader | PdMarkdown, PdMdBase, PdMdInline, PdGridTable, PdSource | 6,138 / 5,102 | Readers/Markdown, Parsing + Parsing/*, Sources, App/Input, Asciify | 5,108 / 4,075 | 1.25 |
| YAML metadata | PdYaml | 1,078 / 901 | Readers/Metadata, yaml, libyaml (Haskell binding only) | 2,763 / 1,998 | 0.45 |
| AST and JSON | PdAst, PdJson | 1,546 / 1,217 | pandoc-types | 2,583 / 1,559 | 0.78 |
| Templates | PdTemplate, PdContext | 1,807 / 1,476 | doctemplates, Templates | 1,535 / 894 | 1.65 |
| Layout and wrapping | PdLayout, PdWidth | 1,456 / 1,208 | doclayout | 1,576 / 1,165 | 1.04 |
| Shared writer code | PdShared | 735 / 620 | Shared, Writers/Shared | 1,828 / 1,356 | 0.46 |
| HTML writer | PdHtml | 1,640 / 1,432 | Writers/HTML | 1,834 / 1,644 | 0.87 |
| ms writer | PdMs | 1,197 / 1,022 | Writers/Ms, Roff, RoffChar | 1,235 / 1,095 | 0.93 |
| ConTeXt writer | PdConTeXt | 985 / 857 | Writers/ConTeXt | 839 / 750 | 1.14 |
| Markdown and plain writers | PdMdWriter | 2,272 / 1,959 | Writers/Markdown + Markdown/*, GridTable | 2,109 / 1,845 | 1.06 |
| Command line and driver | podoc, PdOptions, PdIO | 1,273 / 1,011 | App, App/{CommandLineOptions,Opt,OutputSettings}, Options, Extensions, Error | 4,343 / 3,792 | 0.27 |
| PDF | PdPdf, PdRun | 557 / 419 | PDF, Process | 792 / 656 | 0.64 |
| Includes and filters | PdInclude, PdGlob (+ `.c`), PdFilters | 1,622 / 1,279 | pandoc-include's `main.py` and the user's 5 Lua filters | 915 / 690 | 1.85 |
| **Total, hand-written** | | **22,306 / 18,503** | | **27,460 / 21,519** | **0.86** |
| Generated tables | PdEntities, PdAscii, PdMime, PdWords, PdDefaults | 1,407 / 1,334 | MIME (the rest is data files or other packages) | 278 / 237 | — |

## What the numbers mean

- **Where the work is the same, podoc is the same size or a little
  bigger.** Compare the writers (ms, ConTeXt, HTML, markdown), layout
  and the reader: podoc ranges from 0.87× to 1.25× pandoc's size.
  Haskell is denser, but by about 1.0–1.6×, not the 2–3× that
  `docs/research/podoc-scope.md` §13 guessed.
- **Where podoc looks smaller, the pandoc files do much more.**
  - pandoc's command line handles every format, option and extension.
  - Its Shared modules serve some 60 writers.
  - pandoc-types includes Builder and Walk for every user.
  - Its YAML goes through a general binding to libyaml.

  podoc carries only what the user's builds need, so the 0.27–0.46
  ratios measure scope, not language.
- **Includes and filters are bigger in podoc because Lua and Python
  lean on runtimes.** podoc's version (1.85×) has to do globbing, file
  walking and AST traversal itself, which the Lua filters get from
  pandoc's Lua engine.
- **Not counted: what pandoc pulls in from other libraries for these
  features:**
  - parsec and text;
  - aeson for JSON;
  - blaze-html for the HTML writer;
  - texmath for math (about 12,300 code lines);
  - commonmark, for HTML entities;
  - the libyaml C library;
  - pandoc-lua-engine (about 4,100 code lines), which runs the filters.

  Counting the parts that clearly apply would make pandoc's side
  considerably bigger.
- **The plan's estimate was low.** `docs/research/podoc-scope.md`
  estimated 11,000–14,500 lines; the finished code is 18,500 code lines
  (22,300 in all) of hand-written Oberon and C.

## Whole projects

| | Lines | Code |
|---|---:|---:|
| pandoc's own Haskell (`src/`) | 97,657 | 79,512 |
| pandoc-lua-engine | 5,362 | 4,088 |
| texmath | 13,540 | 12,256 |
| pandoc, pandoc-lua-engine, pandoc-types, doclayout, doctemplates, texmath, commonmark | 128,262 | 104,815 |
| podoc: all `src/` (with the generated tables; `tools/` not included) | 23,713 | 19,837 |
| podoc: tests (git-tracked files under `test/`) | 16,437 | |

So podoc is about a quarter the size of pandoc's own source, and about
a fifth once those libraries are added. The feature-by-feature table
above is the fairer comparison.

## Why not scc or tokei for Oberon

Neither tokei nor scc knows Oberon-2: both count `.Mod` files as
nothing. scc can count them as another language with the same comment
syntax (`scc --count-as mod:Pascal,Mod:Pascal`, or `Mod:Modula3`), but
neither choice reads Oberon correctly, as small test files showed
(2026-11-20):

- **As Pascal**, scc does not take `"..."` as a string, so a `{` or
  `(*` inside one starts a comment. `PdYaml.Mod` has `ch = "{"` several
  times, and everything up to the next `}` is counted as comment: its
  code falls from 901 lines to 547. `PdMdInline.Mod` falls from 1,580
  to 1,334.
- **As Modula-3**, scc takes `\` as an escape inside a string, which
  Oberon has not. `PdRun.Mod` has `AddChar(c, "\")`; that string never
  closes for scc, and the comments after it are counted as code. PdRun
  rises from 120 lines to 147, and most files come out too high.
- **Neither** nests comments, as Oberon does (podoc has no nested
  comments today).

`tools/sizes` therefore counts Oberon itself: comments nest, and
strings, which have no escapes, hide comment brackets. It counts every
test case correctly. Over all of `src/*.Mod` the three give:

| | `tools/sizes` | scc as Pascal | scc as Modula-3 |
|---|---:|---:|---:|
| All `src/*.Mod`, code | 19,804 | 19,159 | 20,252 |
| Hand-written total, code | 18,503 | about 17,906 | about 18,943 |
| podoc ÷ pandoc | 0.86 | 0.83 | 0.88 |
| YAML metadata ratio | 0.45 | 0.27 | 0.45 |
| Markdown reader ratio | 1.25 | 1.19 | about 1.27 |

The other groups move by 1–3%, so the conclusions above hold under any
of the three, but as Pascal the YAML reader looks almost twice as
compact as it is.
