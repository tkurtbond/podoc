# podoc and syntax highlighting: scope, possibilities and risks for ms, mom and ConTeXt

Research done 2026-11-22. The question is whether podoc should
highlight code (code blocks and inline code that name a language) in
its ms, mom and ConTeXt output, as pandoc highlights code with
skylighting. It covers what pandoc does, what podoc would need, what
it would give, and what could go wrong. podoc highlights nothing
today, in any writer; docs/user/differences.md lists that for HTML,
ms and ConTeXt.

**Outcome:** on 2026-11-22 the user decided that highlighting through
a port of skylighting, as studied here, is too big, and will not be
done (PLAN.md's decision 29). §10's questions are left as they were
asked; Q1 (c) and (d), and with them Q2 to Q4, are settled by that
decision.

**pandoc 3.14:** the user installed pandoc 3.14 on 2026-11-22, and it
is now the oracle. The 3.10 regressions described in §1 and §3 are
fixed in 3.14. This was checked the same day, after the study (§3.1):

- by default and with a named style, ms and ConTeXt output highlight
  code blocks and inline code, and the PDFs build;
- `--syntax-highlighting=none` writes plain code.

The rest of this document describes 3.10 as it was studied. Its
source is still the one at hand; there is no 3.14 source here.

Sources:

- pandoc 3.10's source (`/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10`):
  - `src/Text/Pandoc/Highlighting.hs`;
  - `src/Text/Pandoc/Writers/Ms.hs`, `ConTeXt.hs` and `Roff.hs`;
  - `src/Text/Pandoc/Options.hs` and `App/OutputSettings.hs`;
  - `data/templates/default.ms` and `default.context`;
  - `changelog.md`.
- pandoc 3.1.11.1's source, for the writers before pandoc 3.8.
- skylighting-core 0.14.7 and skylighting-format-context 0.1.0.2,
  the versions pandoc 3.10 builds with, unpacked from
  `~/.cabal/packages/hackage.haskell.org`.
- The installed pandoc 3.10 (`~/.cabal/bin/pandoc`), run as the
  oracle.
- groff 1.25.0 (`groff -Tpdf`, mom's `om.tmac`) and ConTeXt LMTX
  2026.07.06.
- podoc at 1ea15aa.
- The user's markdown and rST projects, their GNUmakefiles and
  `~/.pandoc/templates`. These were only read.

Experiments ran in `/usr/local/sw/tmp/claude-podoc-hl`, with a small
test file that has a Python code block, inline code marked `{.c}`
and a code block with no language.

## 1. Summary

- **The user's documents have almost no highlightable code.** In the
  markdown and rST projects that the user builds with pandoc, the only
  code blocks with a language are:
  - two `mermaid` blocks, which skylighting does not know;
  - one `sh` block in a `CLAUDE.md` that is not built to ms or
    ConTeXt.

  The 73-file rST corpus has no `code` directive at all. Nothing in
  the user's builds passes a highlighting option.
- **pandoc 3.10's ms and ConTeXt highlighting is broken by default.**
  pandoc 3.8 replaced `--highlight-style` with
  `--syntax-highlighting`, and that change brought two regressions
  (§3):
  - **ms:** with the default setting, code is tokenized, but the
    macros that print the tokens are never defined. groff then prints
    nothing, so code blocks and inline code vanish from the PDF.
  - **ConTeXt:** the test is inverted. Code blocks are highlighted
    only when no style is named, and then the highlighting commands
    are missing, so `context` stops on `Undefined control sequence`.
    With a style named, code blocks are not highlighted.

  pandoc's 3.11 release notes are reported to fix both (#11829). I
  saw that only in a web search's summary; I have not read the notes
  or run 3.11. podoc's plain code is better output than pandoc 3.10's
  default for both formats. (Both are fixed in pandoc 3.14, verified
  2026-11-22; see §3.1.)
- **mom has no oracle**, since pandoc has no mom writer. Highlighting
  for mom would be podoc's own, built the way ms is built.
- **The cost is a port of skylighting.** That means about 3,000 lines
  of Haskell:
  - a KDE regex engine with backtracking, captures, lookbehind,
    possessive and lazy quantifiers, subroutine calls and Unicode
    classes;
  - the KDE context-stack tokenizer;
  - an XML syntax-definition loader;
  - eight styles;
  - 164 syntax files, 5.9 MB of XML (0.8 MB gzipped), covering pandoc's
    163 languages.

  In Oberon this is likely 4,000 to 5,000 lines, about 15% of podoc
  today (30,795 lines). The syntax data, compacted and embedded, would
  probably make the 1.44 MB binary two to three times larger.
- **Risks** (§9):
  - licences: 84 of the 164 syntax files are GPL or LGPL, but podoc is
    BSD;
  - regex compatibility and speed;
  - a moving oracle;
  - very little benefit for the user's own documents.
- **Cheap, useful steps exist without highlighting** (§7.3): accept
  pandoc's highlighting options, so command lines written for pandoc
  do not fail with exit status 2, and list the languages and styles.
- **Recommendation:** do not port skylighting now. If the user wants
  anything, accept the options (with `none` as the only behaviour) and
  leave highlighting in "Later". Revisit if the user starts writing
  documents with code, or if pandoc 3.11 becomes the oracle.

## 2. Highlighting in pandoc 3.10

### 2.1 skylighting and pandoc's options

pandoc highlights with skylighting, a Haskell port of KDE's
KSyntaxHighlighting:

- **Languages:** `highlight` (`Highlighting.hs`) looks up each of a
  block's classes, in order, by syntax name and then by file
  extension. The first match is the language. With no match it
  returns `Left ""`, and the writer writes the code plain. The classes
  `number`, `numberLines` and `number-lines` ask for line numbers, and
  the `startFrom` attribute sets the first number.
- **Tokens:** `tokenize` turns each line into a list of
  `(TokenType, Text)` pairs. There are 31 token types, from
  `KeywordTok` to `NormalTok`.
- **Styles:** a `Style` gives each token type a colour, a background,
  bold, italic and underline, plus a default colour and a background.
  There are eight built-in styles: pygments (the default), tango,
  espresso, zenburn, kate, monochrome, breezedark and haddock. A KDE
  `.theme` file, which is JSON, can also be given.
- **`--syntax-highlighting`** (since 3.8) takes `none`, `default`,
  `idiomatic`, a style name or a `.theme` path. It replaces
  `--no-highlight`, `--highlight-style` and `--listings`, which still
  work with a deprecation warning. Other options:
  - `--syntax-definition=FILE` adds a KDE XML syntax;
  - `--list-highlight-languages` (163 here) and
    `--list-highlight-styles` list what is available.
- **`HighlightMethod`** (`Options.hs`) is one of `Skylighting Style`,
  `IdiomaticHighlighting`, `DefaultHighlighting` and `NoHighlighting`.
  The default is `DefaultHighlighting`, which each writer is meant to
  map to the pygments style. HTML, LaTeX, Docx, Man and ANSI do that.
  Ms and ConTeXt do not (§3).

### 2.2 The ms writer

`Ms.hs`, lines 595 to 657:

- **Code** (`highlightCode`): code blocks and inline code are
  tokenized whenever a class names a language, whatever the method,
  even `none`. Each token becomes a groff string call with an
  argument: `\*[KeywordTok "def"]`. The token text is escaped with
  `escapeStr`.
- **Macros** (`styleToMs`): these go in the template variable
  `highlighting-macros`, but only for `Skylighting sty`:
  - `.defcolor` for each colour the style uses;
  - for each token type, `.ds KeywordTok \&\\m[007020]\\f[CB]\\$1\\f[C]\\m[]`:
    colour, then `C` with `B` and/or `I`, the argument, then reset.

  Backgrounds and underline are left out (commented out in the
  source).
- **The template:** `default.ms`, lines 18 to 21:
  `$if(highlighting-macros)$ ... $endif$`. The user's own
  `statement.ms`, `tkb.ms` and `digest.ms` have the same lines.

Output, `-t ms`, with the default method and with `none` alike:

```
.IP
.nf
\f[C]
\*[KeywordTok "def"]\*[NormalTok " f(x):"]
\*[NormalTok "    "]\*[ControlFlowTok "return"]\*[NormalTok " "]\*[StringTok "\(dqhi\(dq"]\*[NormalTok " "]\*[CommentTok "# c"]
\f[]
.fi
.LP
Inline
\f[CR]\*[NormalTok "x "]\*[OperatorTok "="]\*[NormalTok " "]\*[DecValTok "1"]\f[R]
here.
```

With `--syntax-highlighting=pygments`, `-s` adds 31 `.ds` lines and
their `.defcolor`s. Rendered with `groff -ms -Tpdf`, the text is all
there and in colour (136 distinct non-grey pixel colours on page 1 at
40 dpi).

### 2.3 The ConTeXt writer

`ConTeXt.hs`, lines 219 to 238 and 609 to 630, with
skylighting-format-context:

- **Code blocks:** the code goes between `\starthighlighting` and
  `\stophighlighting`. Each token is
  `/BTEX\KeywordTok{def}/ETEX`, with adjacent escapes merged, ConTeXt's
  special characters spelled `\letterhash{}` and so on, and a second
  space in a group as `{ }`.
- **Inline code:** `\highlight{...}`, in the same form.
- **Commands** (`styleToConTeXt`): these go in
  `highlighting-commands`:
  - `\definecolor[shadecolor]`;
  - a `shaded` framed text;
  - `\definetyping[highlighting]` and `\definetype[highlight]` with
    `escape=yes`;
  - `\define[1]\KeywordTok{\colored[r=..,g=..,b=..]{\bf #1}}` for each
    token type, with `\underbar`, `\bf` and `\em` as needed.
- **The template:** `default.context`, lines 135 to 137. The user's
  ConTeXt templates (`statement.context`, `tkb.context`) do not have
  these lines, so highlighted code would fail in them even when pandoc
  works.

Two small defects in skylighting-format-context, seen in passing:

- The background colour is printed with `printf "%x%x%x"`, without
  zero padding, so a component below 16 gives a wrong colour. The
  styles' backgrounds happen to avoid this.
- In the PDF of `` `x = 1`{.c} ``, the text came out as `x =1`: a
  space is lost.

### 2.4 mom

pandoc has no mom writer. podoc's `PdMom` writes code blocks as
`.QUOTE`/`.CODE` ... `.CODE OFF`/`.QUOTE OFF`, and inline code through
the font state (`\f[CR]`).

mom has what highlighting needs:

- `.NEWCOLOR name RGB #rrggbb`, which runs `.defcolor` and defines the
  string `\*[name]` as `\m[name]`;
- `\*[BD]`, `\*[IT]`, `\*[BDI]` and `\*[PREV]`, which change the style
  within the current family. Inside `.CODE`, that family is `C`.

So the ms scheme carries over:

- the same `\*[KeywordTok "..."]` calls;
- macros defined with `.NEWCOLOR` (or plain `.defcolor`) and
  `\f[B]`/`\f[I]`, styles of the `C` family, rather than ms's absolute
  `\f[CB]`;
- a `highlighting-macros` variable in podoc's own `default.mom`.

`PRINTSTYLE TYPEWRITE` would ignore colour, as mom does.

## 3. pandoc 3.10's regressions

pandoc 3.1.11.1 had `writerHighlightStyle :: Maybe Style`, defaulting
to `Just pygments`:

- the ms writer wrote the macros whenever code was highlighted and a
  style was set;
- the ConTeXt writer highlighted a code block only `if not (null
  classes) && isJust style`.

pandoc 3.8 (2025-09-06) replaced this with `HighlightMethod` (#10525).
In 3.10:

| | ms, default | ms, `none` | ms, a style | ConTeXt, default | ConTeXt, `none` | ConTeXt, a style |
|---|---|---|---|---|---|---|
| code blocks | tokens, no macros | tokens, no macros | highlighted | tokens, no commands | tokens, no commands | plain `\starttyping` |
| inline code | tokens, no macros | tokens, no macros | highlighted | plain `\type` | plain `\type` | highlighted |
| PDF | code missing | code missing | works | `context` fails | `context` fails | works, blocks plain |

What I checked:

- **ms:** `groff -ms -ww` warns `name 'KeywordTok' not defined` for
  each token type. The rendered page reads "Inline here.", and the
  code block is empty.
- **ConTeXt:** with the default method, `context` stopped with `tex
  error on line 69 ... Undefined control sequence`.
- **ConTeXt with `--syntax-highlighting=pygments`:** the PDF was made,
  with plain code blocks and highlighted inline code.

The causes in the source:

- `Ms.hs` maps only `Skylighting sty` to macros, not
  `DefaultHighlighting`.
- `ConTeXt.hs` line 237 reads
  `Skylighting _ | not (null classes) -> pure unhighlighted`, which
  is the old test turned around.
- Inline ConTeXt code is highlighted only for `Skylighting _`.

According to a web search, pandoc 3.11's release notes say that the
ConTeXt writer "fixed a bug in syntax highlighting (#11829), which
was a regression from 3.8", and that the ms writer "fixed the
treatment of DefaultHighlighting (#11829)". I have not seen 3.11's
code or output.

### 3.1 pandoc 3.14

Checked on 2026-11-22 with pandoc 3.14, the same test (inline code
marked `{.c}` and a `c` code block), `-s`, groff 1.25.0 and ConTeXt
LMTX:

| | ms, default | ms, `none` | ms, a style | ConTeXt, default | ConTeXt, `none` | ConTeXt, a style |
|---|---|---|---|---|---|---|
| code blocks | highlighted | plain | highlighted | highlighted | plain `\starttyping` | highlighted |
| inline code | highlighted | plain | highlighted | highlighted (`\highlight{...}`) | plain `\type` | highlighted |
| PDF | works | works | works | works | works | works |

- The ms output defines the token macros (`.ds KeywordTok ...`) by
  default, and groff warns about none of them.
- `context` ends with exit status 0 in all three cases.
- With `none`, both writers now write what podoc writes, so the parts
  of docs/user/differences.md that say pandoc highlights even with
  `none` are out of date for 3.14.
- One problem remains in pandoc's ms output, and in podoc's: code
  blocks start with `\f[C]`, a font groff 1.25.0 no longer has, so
  unhighlighted code is set in Times-Roman. See
  docs/research/syntax-highlighting-small.md, §4.1.

docs/user/differences.md already records part of this: that pandoc
highlights ms and ConTeXt code even with `none`. It does not record
that pandoc's default output is broken.

## 4. The user's code

Sources: `.md` files under `~/Repos/RPG/Lost-Worlds` and
`~/Repos/RPG/Galactic-Bounty-Hunters`; the 73 rST files (memory note
`rst-corpus`); other `~/Repos/RPG` and `~/current/RPG` files.

- **Fenced blocks:**
  - mostly raw `{=context}` blocks, which are not code;
  - unmarked fences, which have no language;
  - two `mermaid` blocks in the Galactic-Bounty-Hunters one-shot.
    skylighting has no mermaid syntax, so pandoc writes them plain.
    The user builds them through a mermaid filter for HTML (decision
    4).
  - one `sh` block, in `Galactic-Bounty-Hunters/CLAUDE.md`. That is a
    project note, not a built document. It is the one file that
    differs from pandoc in the ms and ConTeXt comparisons, and this is
    why.
- **rST:** the 73 files have no `code`, `code-block`, `sourcecode`
  or `highlight` directive and no `:code:` role. Literal blocks
  (`::`) are not highlighted in pandoc either. The only `.. code::`
  blocks under `~/Repos/RPG` are two in the Centauri Knights campaign
  notes, with no language. They are dice-roller scripts.
- **Builds:** no GNUmakefile under `~/Repos/RPG`, `~/current/RPG` or
  `~/Repos` passes `--highlight-style`, `--syntax-highlighting`,
  `--no-highlight` or `--listings`.
- **Templates:** `~/.pandoc/templates/statement.ms`, `tkb.ms` and
  `digest.ms` have pandoc's `highlighting-macros` block, copied from
  `default.ms`. The ConTeXt templates have no `highlighting-commands`.
- **Software projects:** the user's documents with real code
  (`~/Repos/RPG/Tools/ova_cg_*` READMEs and AGENTS.md files, Oberon
  projects) are not built to PDF with pandoc. skylighting has no
  Oberon syntax; Modula-2 and Modula-3 are the nearest.

So highlighting would change nothing in the user's current PDFs.

## 5. podoc today

- **Writers:** `PdMs`, `PdMom` and `PdConTeXt` write code plain:
  - ms: `\f[C]` ... `\f[]`;
  - mom: `.CODE`;
  - ConTeXt: `\starttyping` and `\type`.

  This is what pandoc does for code with no language. differences.md
  lists it for HTML, ms and ConTeXt.
- **Templates:** podoc's `default.ms` and `default.context` keep the
  `highlighting-macros` and `highlighting-commands` blocks, which
  stay empty.
- **Options:** `--syntax-highlighting`, `--highlight-style`,
  `--no-highlight` and `--list-highlight-languages` are unknown.
  ArgParser stops with "Unknown option" and exit status 2, where
  pandoc's option errors give 6. A command line or GNUmakefile written
  for pandoc with one of these options therefore fails in podoc.
- **Tests:** the case tests' expected ms and ConTeXt files are
  pandoc's `--syntax-highlighting=none` output, edited where pandoc
  writes tokens. `inlines.ms` and `tables.ms` are podoc's, because of
  this (PLAN.md, Phase 12).

## 6. What porting skylighting would take

### 6.1 skylighting-core 0.14.7

`src/`, 3,077 lines of Haskell:

| Module | Lines | Contents |
|---|---|---|
| `Regex/KDE/Compile.hs` | 362 | regex parser to an AST |
| `Regex/KDE/Match.hs` | 208 | a backtracking matcher over UTF-8 |
| `Regex/KDE/Regex.hs`, `Regex/KDE.hs`, `Skylighting/Regex.hs` | 205 | AST and glue |
| `Skylighting/Tokenizer.hs` | 734 | the KDE tokenizer |
| `Skylighting/Parser.hs` | 424 | XML syntax definitions to `Syntax` |
| `Skylighting/Types.hs` | 447 | syntax, context, rule, token and style types |
| `Skylighting/Styles.hs` | 548 | the eight styles and KDE `.theme` JSON |
| `Skylighting/Core.hs`, `Loader.hs` | 149 | lookup by name and extension |

The `skylighting` package proper (not core) compiles the 164 XML
files into Haskell. pandoc links that. Some files are patched first
(`haskell`, `isocpp`, `latex`, `markdown`, `php` and `raku` have a
`.xml.patch`).

### 6.2 The regex engine

The KDE regex AST has these constructors:

- `MatchAnyChar`, `MatchChar` (a predicate), `MatchSome`, `MatchAlt`,
  `MatchConcat`, `MatchNull`;
- `MatchCapture`, `MatchCaptured` (backreferences), `MatchDynamic`
  (`%1` from the rule that entered the context);
- `AssertWordBoundary`, `AssertBeginning`, `AssertEnd`;
- `AssertPositive` and `AssertNegative`, forward and backward;
- `Possessive`, `Lazy`, and `Subroutine` (`(?1)`, `(?R)`).

How much of this the syntax files use:

| Feature | Files |
|---|---|
| `<RegExpr>` rules in total | 3,511 |
| possessive (`*+`, `++`, `?+`) or atomic `(?>` | 57 |
| dynamic rules (`dynamic="true"`) | 29 |
| backreferences (`\1`) | 11 |
| lookbehind `(?<=`, `(?<!` | 11 |
| `\p{...}` Unicode classes | 5 |
| subroutine calls `(?1)`, `(?R)` | 5 |

An Oberon engine needs:

- all of these features;
- Unicode character classes, from pounicode's `Unicode` module;
- word characters, which are letters, digits and connector
  punctuation;
- case-insensitive matching.

It must also work on `LONGINT` offsets under `-O2`. None of podoc's
modules has a regex engine today. The rST and markdown readers are
hand-written scanners.

### 6.3 The tokenizer

The rest of the KDE semantics:

- **Contexts:** a context stack with `#pop`, `#pop#pop` and
  `#pop!ctx` switches, and `lineEndContext`, `lineBeginContext`,
  `lineEmptyContext`, `fallthrough` and `fallthroughContext`.
- **Matchers:** `DetectChar`, `Detect2Chars`, `AnyChar`,
  `RangeDetect`, `StringDetect`, `WordDetect`, `RegExpr`, `keyword`
  (word lists with `casesensitive`, `weakDeliminator` and
  `additionalDeliminator`), `Int`, `Float`, `HlCOct`, `HlCHex`,
  `HlCStringChar`, `HlCChar`, `LineContinue`, `IncludeRules` (with
  `includeAttrib`), `DetectSpaces` and `DetectIdentifier`.
- **Rule flags:** `lookAhead`, `firstNonSpace`, `column` and
  `dynamic`.
- **Other syntaxes:** rules can refer to them (`##Doxygen`,
  `##Alerts`), so syntaxes load together.

The XML contains:

| Element | Count |
|---|---|
| `<item>` (keywords) | 81,623 |
| `<context>` | 5,968 |
| `<DetectChar>` | 5,006 |
| `<IncludeRules>` | 3,850 |
| `<RegExpr>` | 3,511 |

### 6.4 The data

The syntax files cannot be read at run time from a data directory,
because podoc has none (no `--data-dir`; templates are embedded by
`tools/mktemplates`). The choices are:

- **(a)** embed every syntax, preparsed by a build-time tool into
  compact tables in a generated module. With keyword lists and regex
  sources kept as strings, this is likely 2 to 3 MB of initialized
  data, against the 1.44 MB binary today. Whether poc compiles a
  generated module of that size, under `-O2` and `-OC`, is untested.
- **(b)** embed a chosen subset, for example the languages the user's
  projects use (`bash`, `c`, `python`, `lua`, `makefile`, `yaml`,
  `json`, `xml`, `html`, `markdown`, `modula-2`). Smaller, but
  `{.rust}` would quietly be plain, and pandoc would highlight it.
- **(c)** add a data directory (`PREFIX/share/podoc/syntax`) and an
  XML reader. This is a new installation concept for podoc and a new
  failure mode: a binary copied without its data.

`--syntax-definition=FILE` needs (c)'s XML reader in any case.

### 6.5 Styles and options

These parts are small:

- the eight styles as constant tables, from `Styles.hs`;
- `--syntax-highlighting` (`none`, `default`, `idiomatic` or a style
  name; a `.theme` path needs JSON reading, which podoc does not
  have, since `PdYaml` is a small YAML reader);
- the deprecated `--highlight-style`, `--no-highlight` and
  `--listings`, with pandoc's warnings;
- `--list-highlight-languages` and `--list-highlight-styles`.

### 6.6 The writers

- **`PdRoff`**, shared by ms and mom:
  - token formatting, `\*[Tok "..."]` with `EscapeStr`;
  - macro generation from a style.

  The ms half follows `styleToMs`. The mom half is new (§2.4), and
  mom's `default.mom` gets a `highlighting-macros` block.
- **`PdConTeXt`:** the block and inline formats and
  `styleToConTeXt`.
- **Wrapping:** `PdLayout` must keep a highlighted inline span whole,
  as pandoc's `nowrap` and `literal` do. differences.md already notes
  that "a line holding highlighted inline code or math can wrap at a
  different place" in ms.
- **The flag:** the writers' state sets `stHighlighting`, so the
  template variable appears only when something was highlighted.

### 6.7 Size

| Part | Oberon lines, estimated |
|---|---|
| regex parser and matcher | 1,200 to 1,500 |
| tokenizer | 1,000 to 1,200 |
| syntax tables and the build-time converter | 600 to 900 |
| styles, options and listing | 400 |
| ms, mom and ConTeXt formatters and macros | 300 to 400 |
| tests | |
| **Total** | **3,500 to 4,400**, plus generated data |

Tests would need a large token oracle. pandoc gives one: `pandoc -t ms
--syntax-highlighting=pygments` writes every token with its type, for
any language. skylighting's own `test/cases` (32 files) and
`test/expected` give 32 more.

## 7. Narrower alternatives

### 7.1 External highlighters

- **`pygmentize`** is installed here and has a groff formatter. Its
  token names and colours are pygments', not skylighting's, so output
  would not match pandoc. It is Python, which small systems lack.
- **GNU `source-highlight`** is installed here, with `groff_mm`,
  `groff_mm_color` and `groff_man` output languages. These are for
  mm, not ms or mom, and its language list differs from skylighting's.

Either breaks "builds wherever poc does", the reason podoc exists.
Either would be an optional runtime dependency that tests would have
to skip.

### 7.2 A few hand-written lexers

Lexers in Oberon for a handful of languages (sh, C, Python, Oberon):

- small, a few hundred lines each;
- they could cover Oberon, which skylighting cannot;
- the tokens would not match pandoc's, so every highlighted block
  would be a listed difference, and testing would have no oracle.

### 7.3 The options only

Accept the options, with plain code as the only behaviour:

- `--syntax-highlighting`, with `none`, `default`, `idiomatic` and
  the eight style names; anything else gives exit status 6, as pandoc
  does;
- `--highlight-style`, `--no-highlight` and `--listings`, with
  pandoc's deprecation warnings;
- `--list-highlight-styles`, giving the eight names.

`--list-highlight-languages` would have to print an empty list or be
left unknown.

This costs perhaps 100 lines. It makes pandoc command lines work in
podoc, and it changes no output. It is consistent with what
differences.md already says.

### 7.4 Working macros for unhighlighted code

Not applicable. Since podoc writes no tokens, it has nothing to
define.

## 8. What highlighting would give

- Colour and bold or italic keywords, comments and strings in code
  blocks in ms, mom and ConTeXt PDFs, for any of 163 languages.
- **ms:** pandoc 3.10's output with a named style, matched.
- **mom:** podoc's own, a first for mom documents made from markdown.
- **ConTeXt:** working highlighting, which pandoc 3.10 cannot give for
  code blocks.
- Fewer listed differences: highlighting is the first entry in
  differences.md's ms and ConTeXt sections. On the user's 54
  markdown documents it is the only ConTeXt difference, and one of
  the ms differences (with eqn math), both in Galactic-Bounty-Hunters'
  `CLAUDE.md`.
- The same engine would also give HTML highlighting (with CSS from
  the style), the fourth writer listed as unhighlighted.

## 9. Risks

1. **Licences.** podoc is BSD 3-clause, and skylighting-core is BSD3.
   But the syntax files carry their own licences:

   | Licence | Files |
   |---|---|
   | LGPL in its forms | 68 |
   | MIT | 43 |
   | GPL in its forms (one dual GPL or BSD) | 16 |
   | empty or none | 31 |
   | other (BSD, WTFPL, LLVM, FDL) | 6 |

   Embedding GPL syntax data in the podoc binary would put the binary
   under the GPL. pandoc is GPL, so pandoc never faces this.
   Choosing only MIT and BSD syntaxes, or keeping the data in separate
   files (§6.4 (c)), avoids it, at the cost of coverage or of a new
   installation concept. This needs the user's decision, and possibly
   a closer reading of each file's terms.
2. **The oracle moves and is wrong.** pandoc 3.10's ms and ConTeXt
   highlighting is broken by default (§3). "Match pandoc" would mean
   matching bugs, so the target has to be pandoc's intent (3.1.11.1's
   or, if the release notes are right, 3.11's), each case listed in
   differences.md. That weakens the byte-for-byte oracle that keeps
   podoc honest everywhere else. Token streams still compare exactly
   through `--syntax-highlighting=pygments`.
3. **Regex compatibility.** KDE regexes follow PCRE, and skylighting's
   engine has its own coverage and quirks. podoc must reproduce
   skylighting's behaviour, not PCRE's, including the Unicode classes
   and the matching of `\b` and `\w` on non-ASCII text. Each syntax
   file is a test.
4. **Speed and memory.** skylighting's matcher backtracks. A
   pathological regex in some syntax can take exponential time on long
   lines. podoc makes the merchant scenario's ms PDF in 1.4 s today,
   and highlighting would add to such times only for documents with
   code. Memory use in the layout writers is already a known
   problem (docs/developer/memory-use-problem.md). Every token is a
   separate rope node.
5. **`-O2`.** The syntax tables are large, and the matcher needs deep
   recursion or an explicit stack. Both must work with 16-bit
   `INTEGER` and poc's limits. A generated module of megabytes may
   find compiler limits; poc bugs found here go to the user.
6. **Maintenance.** skylighting updates its syntax files with KDE's.
   podoc would freeze 0.14.7's set, or need a regeneration tool kept
   in step.
7. **Little benefit to the user.** Nothing the user builds today has
   highlightable code (§4). The work would serve possible future
   documents, and users other than the user.
8. **The user's templates.** The ConTeXt templates have no
   `highlighting-commands`, so highlighted ConTeXt code would fail in
   them until the user adds the block. This is the same as in pandoc,
   but it is a trap.

## 10. Questions for the user

- **Q1. Highlighting at all?**
  - (a) none: leave it in "Later" (recommended);
  - (b) accept the options only (§7.3), with plain code;
  - (c) port skylighting for ms, mom and ConTeXt;
  - (d) (c) plus HTML.

  The user decided on 2026-11-22 against (c) and (d): the port is too
  big (PLAN.md's decision 29). (a) and (b) remain open.
- **Q2. If ported, which pandoc is the target?** pandoc 3.10's output
  where it works (ms with a named style, ConTeXt inline code with a
  named style), and pandoc's evident intent elsewhere, each case
  listed (recommended)? Or 3.10's exact output, broken PDFs included?
  Or wait for 3.11 and make it the oracle?
- **Q3. If ported, which syntaxes?** All 164, a licence-clean subset
  (MIT, BSD and unlicensed), or a list the user names? Embedded, or
  in a data directory?
- **Q4. mom.** If ported, give mom highlighting in podoc's own form
  (§2.4), with `highlighting-macros` in `default.mom` (recommended
  with (c))?
- **Q5. The broken default.** Should docs/user/differences.md say now
  that pandoc 3.10's default ms output drops highlighted code and its
  ConTeXt output fails, and that podoc's plain code is deliberate
  (recommended either way)?
