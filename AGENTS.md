# AGENTS.md

Notes for agents (and people) working in this repository.

## What this is

podoc is a proof of concept: an Oberon-2 program, built with the
Peaseblossom Oberon Compiler (`poc`), that replaces the parts of pandoc
the user's writing builds need. It reads pandoc markdown with YAML
metadata blocks and writes HTML, groff `ms`, ConTeXt, markdown and groff
`mom` (podoc's own), and it runs `pdfroff`, `groff -Tpdf`, `context`
or `pdfmom` to make PDFs. The user's Lua
filters and `pandoc-include` are built in as Oberon code. pandoc is
too big to install on small and less common systems; podoc is meant
to build wherever poc does.

Read `docs/research/podoc-scope.md` before writing code: it records how
the user uses pandoc, what podoc must do, and why. The plan, phase by
phase, is `PLAN.md`; each phase's state is recorded there.

The user's decisions on the research's open questions are in
`PLAN.md`'s "Decisions" (2026-11-20). Do not settle a new question
silently. Raise it with the user, then record the decision, dated,
there.

## Status

As of 2026-11-20, Phases 1 to 15 are done and the proof of concept
is finished:

- the reader, `PdMarkdown`, and YAML metadata, `PdYaml`;
- the writers: JSON, HTML (`PdHtml`), ms (`PdMs`), mom (`PdMom`), ConTeXt
  (`PdConTeXt`), markdown and plain text (`PdMdWriter`), with templates
  (`PdTemplate`);
- the command line, `PdOptions`;
- includes, `PdInclude`, with globs in `PdGlob`;
- the built-in filters, `PdFilters`;
- PDF output, `PdRun` and `PdPdf`;
- builds and tests on FreeBSD, NetBSD and OpenBSD, `make install`, and
  docs/user/podoc.md.

Phases 16 (plain text, grid and pipe tables), 17 and 18 (wrapping)
are done too: 16.1 (`-t plain`), 16.2 (grid tables in the reader,
`PdGridTable`; character widths from doclayout's table, `PdWidth`),
16.3 (grid and pipe tables in the markdown and plain writers), 16.4
(`-t plain+gutenberg`), 17.1 (`--wrap=auto` and `--columns` for
plain), 17.2 (wrapping for markdown), 18.1 (wrapping for ms), 18.2
(wrapping for ConTeXt) and 18.3 (emoji sequences in `PdWidth`, as
doclayout counts them). Phase 21 (images in ms output, decision 23)
is done: `PdImages` copies images for `--extract-media` and converts
them to PDF for ms, with `PdSha1` for pandoc's SHA-1 names; its tests
are `tools/runimages`. Further work is in PLAN.md's "Later".

A reStructuredText reader, all of pandoc's `-f rst`, came into scope
on 2026-11-20 (PLAN.md's decisions 18 to 22), planned as Phase 19.
Phase 19 is done: 19.1 (blocks, with references and footnotes), 19.2
(roles, substitutions and the directive framework), 19.3 (every
directive, with `include`), 19.4 (grid and simple tables and the table
directives) and 19.5 (`-s`'s title and docinfo, `--verbose` and
podoc's `--unknown=warn|error`; the user's 73 rST files match pandoc):
`PdRst` and `PdRstInline`. Read `docs/research/rst-implementation.md`
first.
Phase 20 (the `%` title block, `pandoc_title_block`) is done too, and
Phase 22 (EPS images converted with Ghostscript for `groff -Tpdf`,
decision 26).
Phase 23, a mom writer and pdfmom (decision 27), is podoc's own, as
pandoc has none: 23.1 (`PdRoff`, the roff writers' shared code, from
`PdMs`), 23.2 and 23.3 (`PdMom`: blocks, inlines, tables, figures and
images), 23.4 (`data/templates/default.mom`, podoc's own, and the
example `data/examples/statement.mom`) and 23.5 (`--pdf-engine=pdfmom`
in `PdPdf`). Read `docs/research/pdfmom-backend.md` first.
Phase 24, podoc's own code highlighting (decisions 30 to 47), is
done: `PdCode` (the scanner and the languages' reserved words),
`PdCodeAlign` (the layout of aligned code), `PdKeywords` (users'
lists, `--code-keywords`), and `--code-style` and `--code-align` in
the HTML, ms, mom and ConTeXt writers. Read
`docs/research/syntax-highlighting-small.md` first.
Phase 25, mermaid diagrams (decisions 48 to 54), is done: `PdMermaid`
runs pomermaid (`~/Repos/Oberon/pomermaid`) for `-F
pandoc-mermaid-selenium-filter` or `-F pomermaid`; its tests are
`tools/runmermaid`, with a stand-in pomermaid in `test/mermaid/bin`.
An Org mode reader, `-f org` (decisions 55 to 59), is planned as
Phases 26 to 28; 26.1 (blocks of text), 26.2 (lists), 26.3 (blocks)
and 26.4 (tables) are done: `PdOrg`, `PdOrgInline` and
`PdOrgMeta`. Read `docs/research/org-mode-reader.md` first.
See PLAN.md's State.

## Reference material

| What | Where |
|---|---|
| pandoc 3.14 source (the installed binary since 2026-11-22) | `/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.14` |
| pandoc 3.10 source | `/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10` |
| pandoc 3.1.11.1 source | `/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.1.11.1` |
| doctemplates source | `/usr/local/sw/src/lang/Haskell/pandoc/doctemplates` |
| The markdown reader | `src/Text/Pandoc/Readers/Markdown.hs`, `Parsing/` |
| The writers | `src/Text/Pandoc/Writers/{HTML,Ms,Roff,ConTeXt,Shared}.hs` |
| PDF engines | `src/Text/Pandoc/PDF.hs` |
| Default templates | `data/templates/` (GPL-2.0-or-later or BSD-3-Clause) |
| Test fixtures | `test/testsuite.txt`, `test/writer.*`, `test/tables.*`, `test/command/*.md` |
| Installed pandoc (the oracle) | `~/.cabal/bin/pandoc`, 3.14 (was 3.10 until 2026-11-22), with Lua 5.4 |
| `pandoc-include` | `~/.local/lib/python3.14/site-packages/pandoc_include/main.py` |
| The user's filters and templates | `~/.pandoc/filters`, `~/.pandoc/templates` |
| Markdown projects using pandoc | `~/Repos/RPG/Lost-Worlds`, `~/Repos/RPG/Galactic-Bounty-Hunters` |
| reStructuredText projects (templates, variables) | `~/Repos/RPG/Red-Planet-Blue-Helmets/2ER`, `~/current/RPG/Campaigns/Alusia/Return/Scenarios/005-merchant/rst-version` |
| The largest reStructuredText files, for tests and benchmarks | `~/current/RPG/Mini-Six/SRD/minimal-opend6-srd.rst` (179 KB: grid and simple tables, `table` with `:widths:`, `raw:: ms` and `raw:: context`, line blocks, comments, `container`, hyperlink references), `~/current/RPG/Campaigns/Alusia/Return/Scenarios/005-merchant/rst-version/return-005-merchant.rst` (47 KB) |

The user's projects and `~/.pandoc` are read only: never change them.
Read the specific files you need; do not list `~/.pandoc` or other
private directories wholesale.

## The compiler

- **Use the installed `poc`**: `/usr/bin/poc`, version 0.15.0 (39d2137)
  as of 2026-11-20. Its libraries are in `/usr/lib/poc`, and libraries
  installed by the user in `~/.local/lib/poc/<triple>/{O2,OC}`. Check
  what the compiler accepts by running it, not by reading its source.
- **`~/Repos/Oberon/Peaseblossom` is reference only.** Read its
  `doc/users-guide.md`, `doc/developer/language-extensions.md`, its
  runtime (`rtl/`) and its `AGENTS.md` for conventions, but never
  modify, build or commit anything there. A poc bug found here is
  reported to the user, who records it in Peaseblossom's `PLAN.md`; do
  not work around it silently.
- **Target:** LLVM, `x86_64-redhat-linux-gnu` by default; Linux and
  the BSDs. Not VAX/VMS (decision 1). Keep the core free of C where
  there is a choice; optional C (libfyaml) goes behind a build option.
- **Size models:** under `-O2`, the default, `INTEGER` and `LONGINT` are
  16 and 32 bits; under `-OC` they are 32 and 64. Every module must
  compile and pass its tests under both. Text lengths and file sizes
  can exceed 32,767, so index text with `LONGINT` where it can.
- **`-trap-heap-exhausted`** is in the GNUmakefile's `POCFLAGS`: a
  `NEW` that finds no memory stops podoc with "heap exhausted"
  (trap 11) instead of leaving NIL. It is compiled into each `NEW`, so
  it covers podoc's modules, not the installed libraries.
- **Functions cannot return records or arrays** in poc; they come back
  through a `VAR` parameter.
- **C**, when an optional feature needs it, is called with
  `PROCEDURE ["C", "name"]` and a module's C part `<Module>.c`; see
  pofltk for callbacks from C into Oberon. No C `longjmp` may cross an
  Oberon frame.
- **C parts:** `src/PdGlob.c` (`opendir`, `readdir`, `stat`; POSIX,
  no library) is podoc's only one.
- **Module names** must not collide with poc's runtime modules or
  other libraries: Oberon has one global module namespace. podoc's
  modules are prefixed `Pd`.

## Libraries

| Library | Use | Notes |
|---|---|---|
| pounicode (`Utf8`, `Unicode`, `Utf8Strings`, `Utf8Files`) | identifiers, delimiter rules | |
| ArgParser | the command line: `--opt=val`, `--opt val`, `-ovalue`, `-o value`, clustered short options | |
| Ropes | AST strings and all output (scope §12.1) | byte-oriented |
| pounix (`UnixProcesses`, `UnixFiles`) | not used: built for `-OC` only; PDF engines run through `Platform.System` | Unix only |
| poDateTime | dates, if needed | |
| polibfyaml | full YAML, a later build option | needs libfyaml; installed for `-OC` only |

ArgParser, Ropes and pounicode must be installed under both models in
`~/.local/lib/poc` (`POCLIBDIR`). A missing one is installed from its
checkout under `~/Repos/Oberon`: `make -f pocGNUmakefile install` in
`ArgParser` and `Ropes`, `make install` in `pounicode`. A library
records the poc that built it, and another poc refuses it: rebuild and
reinstall after upgrading poc.

## Building and testing

- `make` builds `podoc` under `-O2` and `-OC` in `build/O2` and
  `build/OC`.
- `make test` runs the unit tests (`test/<Name>Test.Mod`, printing
  `ok   - ` and `FAIL - ` lines, compared with `<Name>Test.expected`)
  and the case tests (`tools/runcases`: `test/cases/<name>.md` with
  optional `<name>.args`, against each expected `<name>.<format>`
  beside it), the image tests (`tools/runimages`, from
  `test/images` against `test/images-expected`), and the mermaid
  tests (`tools/runmermaid`, from `test/mermaid` against
  `test/mermaid-expected`), under both models.
  It must not need pandoc. Expected JSON
  is pandoc 3.10's (not yet re-checked against 3.14); the writers' expected files start as pandoc's
  `--wrap=none` output and may be replaced by podoc's equivalent
  output, each difference recorded in `docs/user/differences.md`
  (decision 3).
- `make compare` runs pandoc and podoc side by side, where pandoc is
  installed.
- `tools/bench` times podoc, under both models, against pandoc. It
  reports wall and CPU time and peak RSS for conversions, the
  Lost-Worlds builds, PDFs and reStructuredText (`rst`); run it under a `systemd-run` memory
  cap. Its results, the method and the changes made for performance
  are in `docs/developer/performance.md`. The layout writers' memory
  use, its fixes and what is left are in
  `docs/developer/memory-use-problem.md`.
- `make install` installs the `-OC` podoc and `subs2yaml` (`PREFIX`,
  `~/.local` by default; `MODEL`, `DESTDIR`); `make uninstall`.
- Tested on Fedora (atla), FreeBSD (alerik), NetBSD (artos, terhali;
  yishana, i386) and OpenBSD (erekose, i386); on the
  VMs, copy clean checkouts (`git archive`) of podoc and its libraries
  to a scratch directory, `gmake`, and remove it afterwards.
- The reader is checked against `pandoc -f markdown -t json`, byte for
  byte; the writers against `pandoc --wrap=none -t html|ms|context`,
  for equivalence; the markdown writer by the round trip (its output
  read again gives the same JSON).

## Exit statuses and halt codes

Errors the user can cause end podoc with pandoc's exit status for that
error (`Text.Pandoc.Error`), through `PdIO.Fail` or `PdIO.Exit`: 1
input or output, 4 application error (PDF output podoc cannot make),
5 template error, 6 option error, 21 unknown input format, 22 unknown
output format, 23 unsupported extension, 43 PDF error, 47 PDF program
not found, 64 parse error, 83 filter error, 97 data file not found, 98 metadata file not found, 99
resource not found. ArgParser ends
with 2 on a bad option (pandoc: 6).

`HALT` and `ASSERT` are for what should never happen. podoc's codes
for them start at 100; none is assigned yet. The codes poc's traps,
its runtime and the po* libraries use, how `HALT` and `ASSERT` report
them, and podoc's own, are in `docs/developer/halt-codes.md`. List
each new code there.

## Conventions

- **Claim only what has been verified.** Say in PLAN.md's State what
  was run and what passed, with the date.
- **Commit only when asked.** Each phase ends with a commit, made when
  the user asks.
- **Commit on `devel`**, not `main`. Before committing, check the
  branch and bring `devel` up to date with `main`.
- **Temporary files** go under `/usr/local/sw/tmp`, in a directory per
  session, never `/tmp` (a RAM disk on this machine). Delete it when
  done. Large runs (whole-corpus comparisons, ConTeXt) are capped with
  `systemd-run --user --scope -q -p MemoryMax=... -p MemorySwapMax=0`.
- **Portable:** Linux and the BSDs. GNU make is the build tool; shell
  scripts are POSIX `sh`.
- **Match pandoc**, not a reading of its manual: when unsure, run
  the installed pandoc (3.14) and do what it does. Known, deliberate differences are
  listed in the user documentation.
- **Scope:** add a feature when the user's documents or filters need
  it, or the plan schedules it. Everything else goes to PLAN.md's
  "Later".
- **Style:** as the other Oberon projects under `~/Repos/Oberon`: one
  module per file, `src/<Module>.Mod`, exported procedures commented.
