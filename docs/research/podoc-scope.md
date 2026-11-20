# podoc: scope, possibilities and risks

Research done 2026-11-19 for a proof of concept: an Oberon-2 program,
built with the Peaseblossom Oberon Compiler (`poc`), that replaces the
parts of pandoc and of the Lua filters that the user's writing builds
use. Input is pandoc markdown, with YAML metadata blocks. Output is
HTML, groff `ms` (to PDF through `pdfroff` or `groff -Tpdf`), and
ConTeXt (to PDF through `context`).

pandoc is big: the installed 3.10 binary (`~/.cabal/bin/pandoc`, with
Lua 5.4) is 292 MB, and it needs a working GHC to build. On small or
less common systems it is hard or impossible to install. groff and,
less often, ConTeXt are easier to find.

## 1. Summary

- **It is feasible.** The user's documents use a small part of pandoc
  markdown, and the three writers, the template language, the filters
  and `pandoc-include` are all small enough to write in Oberon. The
  estimate is 11,000 to 14,500 lines of Oberon, with the markdown
  writer (§13).
- **The largest risk is the markdown reader.** pandoc markdown is not
  CommonMark. It has its own rules for list indentation, laziness,
  setext headers, smart punctuation and more. The reader must be
  checked against pandoc's own JSON output, on the user's documents
  and on pandoc's test fixtures, not against a reading of a manual.
- **Recommendation: native filters first, Lua later and optional.** The
  user's five Lua filters and `pandoc-include` are short. Built-in
  Oberon versions, chosen by the same command-line options the
  GNUmakefiles pass today, keep podoc pure Oberon and free of a C
  dependency. Lua support, when it comes, should be a build option
  (§8).
- **Keep pandoc's command line.** If podoc accepts the options the
  builds pass to pandoc, a GNUmakefile can use it with `PANDOC=podoc`
  and the two programs can be compared on the same input.
- **Recommendation: YAML by a native subset parser**, not polibfyaml,
  so podoc needs no C library (§9).

## 2. How the user uses pandoc

Four places were examined. The two markdown projects drive the scope;
the two reStructuredText projects show the templates, variables and
filters the user also relies on, but reStructuredText input is out of
scope.

### 2.1. `~/Repos/RPG/Lost-Worlds`

The GNUmakefile builds each document three ways:

```
# HTML
pandoc -s -F pandoc-include $(PANDOC_OPTS) $< \
       --lua-filter=subs.lua --lua-filter=strip-comments.lua -o $@

# ConTeXt PDF (the digest variant adds -H cstyle-digest.tex)
pandoc -s -F pandoc-include --pdf-engine=context -H cstyle.tex \
       --include-in-header=header-includes.context \
       --lua-filter=subs.lua --lua-filter=strip-comments.lua \
       --lua-filter=toc-columns.lua $< -o $@

# ms PDF
pandoc -s -F pandoc-include --pdf-engine=pdfroff \
       --pdf-engine-opt="-Kutf-8" \
       --lua-filter=subs.lua --lua-filter=strip-comments.lua $< -o $@

# one markdown file with the includes expanded
pandoc -r markdown -w markdown -F pandoc-include $< -o $@-whole.md

# a combined digest of several documents
pandoc -s -f markdown --pdf-engine=context ... \
       -M title="Lost Worlds Digest" -M combine=a.md -M combine=b.md ... \
       --lua-filter=combine-docs.lua ... /dev/null -o $@
```

Some markdown is generated first (`build/*.gen.md`, by `ova_fmt_po`),
and the PDFs are post-processed with `pdfbook2` and `qpdf`. Those
steps stay outside podoc.

Its filters, kept in the project:

- `subs.lua` loads `substitutions.lua` with `dofile` and, in every
  `Str`, replaces each key of the table `substitutions` with its value,
  by `string.gsub`. The keys are tokens such as `|SCA|`; the values are
  names such as `Seltroti`. The keys are used as Lua patterns, but none
  of the current keys has a pattern character other than `|`, which is
  literal in Lua patterns.
- `toc-columns.lua` inserts a raw ConTeXt block (a two-column
  `\placecontent` under a "Contents" heading, in 8 pt type) at the
  start of the body, or after the first block when there is no title
  in the metadata and the first block is a level-1 header.
- `combine-docs.lua` (114 lines) reads each file named in the metadata
  list `combine` with `pandoc.read`. It takes a title from that file's
  `title` metadata, else from a lone level-1 header at the top (which
  it removes), else from the file name, title-cased. It shifts the
  file's remaining headers so the smallest level is 2 (at most 6),
  prefixes each identifier with the file's stem, inserts
  `Header(1, title, {id = stem})`, puts a raw ConTeXt `\page` between
  files, and deletes `combine` from the metadata.

And, from `~/.pandoc/filters`, `strip-comments.lua`: it removes a
`Para` or `Plain` whose first inline is a `Str` beginning with `%`.

The project also has `cstyle.tex` (page layout, Symbola fallback
fonts, a "Page X of Y" footer) and `header-includes.context`
(`\setupitemize`, `\setupenumerate`, `\setuplines`, list margins,
`\setupcombinedlist[content][alternative=c]`).

### 2.2. `~/Repos/RPG/Galactic-Bounty-Hunters`

The same pattern: `pandoc -s -F pandoc-include`, with
`--filter pandoc-mermaid-selenium-filter`, to make `-gen.html`,
`-ctx.pdf` (with `-H cstyle.tex`), `-ms.pdf` (pdfroff) and
`-whole.md`. The documents use raw ```` ```{=context} ```` blocks
(`\page[break]`, `\blank`, a `\placecontent` setup), headers that
start with emoji, `Includes/*.md` files for stat blocks (nested bullet
lists, `|` inside text), pipe tables (`core-rules-cheat-sheet.md`),
and images, among them SVG maps. Two ```` ```mermaid ```` blocks are
rendered by `pandoc-mermaid-selenium-filter`, a Python program that
drives a browser through Selenium.

### 2.3. `~/Repos/RPG/Red-Planet-Blue-Helmets/2ER` and `005-merchant`

reStructuredText only, so their input is out of scope, but they show
the rest of the user's setup:

- Templates of their own: `--template=tkb` and `--template=statement`,
  found in `~/.pandoc/templates` (`tkb.ms`, `statement.ms`,
  `tkb.context`, `statement.context`).
- Variables those templates read: `usegrowps`, `fontfamily`,
  `twocolumns`, `pointsize`, `lineheight`, `interpara`, `indent`,
  `widemargins`, `verywidemargins` (ms); `mainfont`, `sansfont`,
  `monofont`, `mathfont`, `fontsize`, `papersize`, `pagenumbering`,
  `whitespace`, `setupitemize`, `setupenumerate`, `indenting`,
  `interlinespace`, `layout`, `linkcolor`, `twocol` (ConTeXt).
- `--lua-filter=general.lua` (§4.3).
- `--pdf-engine-opt=-P-p8.5i,5.5i` for the paper size under pdfroff.
- Plain groff too: `groff -k -Tpdf -ms -P-p4i,6i 4x6-setup.ms $<`.
- 005's YAML metadata has `author`, `rights`, `lang`, a `tags` list,
  an `abstract` block scalar, and comments.

### 2.4. What the markdown actually uses

A census of the 48 markdown files of Lost-Worlds and
Galactic-Bounty-Hunters (4,594 lines, `Includes/` too):

| Feature | Count |
|---|---|
| `\|XXX\|` substitution tokens | 240 |
| block-quote lines | 98 |
| `---` lines (YAML fences or rules) | 74 |
| pipe-table rows | 45 |
| `!include` paragraphs | 35 |
| of those, with `incrementSection=1` | 14 |
| ordered-list items | 33 |
| code fences | 24 |
| raw ConTeXt blocks | 9 |
| images | 8 |
| images with attributes (`{width=100%}`) | 1 |
| `%` comment paragraphs | 3 |
| mermaid blocks | 2 |

Also used: ATX headers, emphasis and strong emphasis, inline code,
links, bullet lists nested several deep, smart quotes and dashes, and
non-ASCII text throughout.

Not found: footnotes, fenced divs, bracketed spans, definition lists,
header attributes, math, citations, strikeout, superscript and
subscript. Fenced divs and bracketed spans still belong in scope,
because `general.lua`'s whole purpose is to style them, and the user
writes new documents.

## 3. The feature subset

### 3.1. Input: pandoc markdown

In scope, in order of need:

1. Paragraphs, ATX and setext headers, block quotes, bullet and
   ordered lists (with pandoc's four-space rule and laziness), fenced
   and indented code blocks, horizontal rules, hard line breaks,
   backslash escapes, HTML entities.
2. Emphasis, strong emphasis, inline code, links (inline and
   reference), images (with `{width=...}` attributes), autolinks.
3. YAML metadata blocks, anywhere in the document as pandoc allows,
   with markdown in their string values.
4. Smart punctuation (`smart`): curly quotes, `--`, `---`, `...`.
5. Pipe tables, with alignment and captions.
6. Raw blocks and inlines: ```` ```{=context} ````, `` `x`{=ms} ``,
   and raw HTML, passed through to the matching writer only.
7. Automatic header identifiers (`auto_identifiers`), with pandoc's
   Unicode rules, and implicit header references.
8. Fenced divs (`:::`) and bracketed spans (`[text]{.class}`), with
   attributes, for `general.lua`.
9. Footnotes (inline and reference), line blocks (`|`), strikeout,
   superscript, subscript, definition lists: cheap once the parser
   exists, and used by the user's older documents.

Out of scope for the proof of concept: grid, simple and multiline
tables; citations; TeX math beyond passing `$...$` through as math;
raw TeX; `markdown_in_html_blocks` beyond keeping HTML blocks raw;
example lists; abbreviations; emoji shortcodes; and every input format
but markdown. These are recorded under "Later" in the plan.

### 3.2. Output

- **HTML5** (`-t html`, `-s` with the default template). Section `div`s
  are not on by default and are not needed.
- **ms** (`-t ms`), for `pdfroff` and `groff -Tpdf`.
- **ConTeXt** (`-t context`).
- **JSON** (`-t json`), pandoc's AST format, as the test oracle for the
  reader. Writing it is short; reading it is optional.
- **markdown** (`-w markdown`) only to produce `-whole.md`. A faithful
  markdown writer is a large job; §11 suggests a cheaper route.

### 3.3. What each writer must do (observed with pandoc 3.10)

**ms:**

- Smart quotes `\(lq` `\(rq` `\(cq`; dashes `\(en` `\(em`. UTF-8
  passes through unescaped.
- Headers `.SH 1` (`.NH` with `--number-sections`).
- Footnotes `\**` with `.FS`/`.FE`.
- Pipe tables become `tbl` (`.TS delim(@@) tab(	); l r.`, cells in
  `T{`/`T}`).
- Lists `.IP " 1." 4`, `.IP \(bu 3`, nesting by `.RS 4`/`.RE`.
- Block quotes `.QS`/`.LP`/`.QE`; rules `.HLINE`; line blocks with
  `.br` and `\ \ `.
- Superscript `\*{`/`\*}`; strikeout `\m[strikecolor]`. Links show only
  their text.
- Title block `.TL`, `.AU` per author, `.AB`/`.AE` for the abstract.
- A line that starts with `.` or `'` must be escaped (`\&`), whatever
  the wrapping.
- Images: `.PSPIC` for `.ps`/`.eps`, `.PDFPIC` for `.pdf` (and then
  pdfroff needs `-U`). Any other image becomes a comment
  (`\" .IMAGE "m.svg"`), so the SVG maps do not appear in ms output
  at all; an image alone in a paragraph is a figure, and its caption
  follows as `.ce 1` / caption / `.sp 1` either way. podoc should do
  the same.

**ConTeXt:**

- Headers `\startsectionlevel[title={...},reference={id}]` ...
  `\stopsectionlevel`.
- `{\em ...}`, `{\bf ...}`, `\type{...}`, `\goto{...}[url(...)]`,
  `\quotation{...}`, `\ldots{}`, `\high{}`, `\low{}`, `\overstrikes{}`.
- `|` becomes `\letterbar{}`; the TeX special characters are escaped.
- Tables use the `xtable` structure. A right-aligned column gets
  `[align=left]`, which is ConTeXt's name for flush right.
- Lists `\startenumerate[n,packed][stopper=.]` and
  `\startitemize[packed]`.
- `\startblockquote`, `\thinrule`, `\startlines` with `~~` for leading
  spaces, `\crlf`.
- Images `\externalfigure[src]`, with the width as a fraction of
  `\textwidth`.

**HTML:**

- Footnotes in `<section id="footnotes" class="footnotes
  footnotes-end-of-document" role="doc-endnotes">` with a `↩︎` back
  link.
- `<ol type="1">`, `<div class="line-block">`, `<del>`, `<sup>`,
  `<sub>`, `<figure>` for an image alone in a paragraph.
- Identifiers keep Unicode letters, are lower-cased, and drop emoji and
  punctuation: `## Café Ünïcode OK! 🎲 Header` gets
  `café-ünïcode-ok-header`.

### 3.4. Wrapping

pandoc wraps at 72 columns by default, using its `doclayout` library,
and the result has quirks: a paragraph line that would start with `.`
is moved and escaped (`\&.` on a line of its own, in ms). Wrapping
does not change the PDF or the rendered HTML. The proof of concept
should write unwrapped output (pandoc's `--wrap=none`) and be compared
with pandoc run with `--wrap=none`. `--wrap=auto` and `--columns` are
"Later".

## 4. The filters, and native equivalents

podoc should recognise the filter options the builds pass, by the
file's base name, and run built-in Oberon code in their place:

| Option | Native equivalent |
|---|---|
| `--lua-filter=subs.lua` | `Str` substitution from the table in the `substitutions.lua` beside it |
| `--lua-filter=strip-comments.lua` | drop `%` paragraphs |
| `--lua-filter=general.lua` | the Div and Span styles below |
| `--lua-filter=toc-columns.lua` | insert the two-column contents block |
| `--lua-filter=combine-docs.lua` | the combined digest |
| `-F pandoc-include` | the include pass (§5) |
| `--filter pandoc-mermaid-selenium-filter` | out of scope, or an external `mmdc` (§4.5) |

Any other filter is an error, unless Lua support is built in (§8).

### 4.1. `subs.lua` and `substitutions.lua`

The table is a Lua table literal of string pairs. podoc should read
that file directly: a small reader for `name = { ["k"] = "v", ... }`
with Lua's string escapes and `--` comments. The project does not then
change. The keys are taken literally, which matches every current key;
a key with a Lua pattern character would warn. If keys are ever
allowed to be patterns, Lua's pattern matcher (about 400 lines of C in
`lstrlib.c`) is small enough to port.

### 4.2. `strip-comments.lua`

Ten lines of Oberon over the block list, recursively.

### 4.3. `general.lua` (`~/.pandoc/filters`, 308 lines)

- **Div `for-format`:** kept only if its classes include the output
  format; otherwise dropped, with a warning on standard error.
- **Div `box`:**
  - ms: `.sp 0.2v` `.B1` ... `.sp 0.2v` `.B2` `.sp 0.2v`
  - ConTeXt: `\startframedtext[width=broad,rulethickness=0.75pt,offset=3pt,aligned=yes]`
    ... `\stopframedtext{}`
  - HTML: `<div style="border:solid">` ... `</div>`
- **Div `keep`:** ms `.KS` ... `.KE`.
- **Tables in ms:** wrapped in `.na` ... `.ad`.
- **Span classes:**

  | Class(es) | ms | ConTeXt | HTML |
  |---|---|---|---|
  | `title-ref` | `\fI`...`\fP` | `{\it ...}` | `<cite>` |
  | `skill`, `att`, `spell`, `power`, `edge` | `\S'15'`...`\S'0'` | `{\it ...}` | `<i>` |
  | `name`, `place`, `money`, `room`, `item` | `\fB`...`\fP` | `{\bf ...}` | `<b>` |
  | `bi`, `app` | `\f[BI]`...`\fP` | `{\bi ...}` | `<b><i>` |
  | `red`, `green`, `blue` | `\m[red]`...`\m[]` | `\color[red]{...}` | `<span style="color:Red;">` |
  | `file` | `\F[C]`...`\F[]` | (message: unimplemented) | `<code>` |
  | `cmd` | `\f[CB]`...`\fP` | (message: unimplemented) | `<b><code>` |

  The ms colour spans print a note that the template needs `.color`.
  The LaTeX and EPUB branches are out of scope.

The natural Oberon form is a pass over the AST that replaces these
Divs and Spans by raw blocks and inlines for the current format, so
the writers need not know about them. That is also how the Lua filter
works, and it keeps the output identical.

### 4.4. `toc-columns.lua` and `combine-docs.lua`

Both are direct AST manipulations: insert a raw block; read files,
shift header levels, rename identifiers, join. `combine-docs.lua`
needs the reader as a library call (its `pandoc.read`), which the
Oberon design gives for free.

### 4.5. Mermaid

`pandoc-mermaid-selenium-filter` needs Python, Selenium and a browser,
which is the opposite of podoc's purpose. Options: leave mermaid
blocks as code (the default); or, if `mmdc` (mermaid-cli) is on the
path, run it to make an SVG or PDF and replace the block with an
image. Recommendation: out of scope for the proof of concept.

## 5. `pandoc-include`

The user's builds use only two forms, each a paragraph of its own:

```
!include path/to/file.md
!include`incrementSection=1` path/to/file.md
```

What the Python filter
(`~/.local/lib/python3.14/site-packages/pandoc_include/main.py`) does,
and podoc should match:

- The path may be a glob; matches are included in sorted order.
- Each file is parsed on its own as a whole document, recursively, with
  relative paths resolved from the including file's directory.
- The included metadata is merged into the outer document's, the outer
  keys winning.
- `incrementSection=n` adds n to each header level of the included
  blocks.
- Relative image paths in the included file are rewritten to be
  relative to the top-level file.
- Cycles are an error.

It also has `startLine`, `endLine`, `snippetStart`, `snippetEnd`,
`dedent`, `format`, `raw`, `xslt`, `!include-header` and code-block
includes. None is used; podoc should reject them with a clear message.

Because includes expand into the AST, the `-whole.md` target needs a
markdown writer. A cheaper route, since only `!include` lines change,
is a textual expansion that copies the included files' text in place,
shifting ATX header markers by `incrementSection`. That is not what
pandoc produces (pandoc re-renders the whole document), but it is a
valid flattened document. Which is wanted is an open question (§15).

## 6. Templates

pandoc's templates use the `doctemplates` language. podoc needs:

- `$var$` and dotted fields (`$author.name$`); `${var}` too.
- `$if(var)$` / `$elseif(var)$` / `$else$` / `$endif$`.
- `$for(var)$` / `$sep$` / `$endfor$`, with `$it$`.
- `$--` comments and `$$` for a dollar.
- Partials, such as `$styles.html()$`, and applied partials
  (`$for(author)$$author:name()$$endfor$`) if a template uses them.
- The pipes `/nowrap` (used by the user's ConTeXt templates) and, as
  needed, `/uppercase`, `/lowercase`, `/length`.
- Nesting by column: a multi-line value inserted at column n is
  indented to n. This matters for HTML and does not for ms and
  ConTeXt.

The default templates are small (`default.html5` 70 lines,
`styles.html` 216, `default.ms` 124, `default.context` 205). They are
dual licensed, GPL-2.0-or-later or BSD-3-Clause, so podoc can carry
copies under the BSD licence. `--template=name` searches the working
directory and then `~/.pandoc/templates`, adding the format's
extension, as pandoc does.

Variables come from the metadata (rendered by the writer), from `-V`,
and from the writer itself (`body`, `toc`, `header-includes`,
`include-before`, `include-after`, `title-prefix`, `pagetitle`,
`date`, `lang`, `numbersections`, `css`). The doctemplates sources
cloned under `/usr/local/sw/src/lang/Haskell/pandoc/doctemplates` are
the reference.

## 7. PDF output

From pandoc 3.10's `Text/Pandoc/PDF.hs`:

- **pdfroff:** `pdfroff -ms -mpdfmark -mspdf -e -t -k -KUTF-8 -i`, plus
  `-U` when the source has `.PDFPIC`, plus `-P-p<papersize>` when
  `papersize` is set, plus each `--pdf-engine-opt`. The ms text goes to
  standard input; the PDF comes from standard output.
- **groff:** `groff -ms -Tpdf -e -t -k -KUTF-8`, with the same additions.
- **context:** writes `input.tex` into a temporary directory and runs
  `context --batchmode input.tex` there, then reads `input.pdf`. Before
  that, images are copied or extracted into that directory, and,
  because ConTeXt counts as a TeX engine, SVG images are converted to
  PDF there by `rsvg-convert -f pdf -a --dpi-x 96 --dpi-y 96` (96 is the default
  `--dpi`). Other
  formats that are not PNG, JPEG or PDF are converted to PNG by a
  Haskell library; podoc cannot do that without help, and should pass
  them through and let ConTeXt fail or cope.

On this machine (2026-11-19): `context` is ConTeXt LMTX in
`/usr/local/sw/versions/context/lmtx`, `pdfroff` and `groff` are groff
1.23.0 in `/usr/local/sw/versions/groff/1.23.0`, and `rsvg-convert` is
`/usr/bin/rsvg-convert`.

podoc needs: making a temporary directory (in `TMPDIR`, which on this
machine must not be `/tmp` for large runs), running a program with
arguments and standard input and output redirected, copying files, and
cleaning up. `Platform.System` runs a shell command line, which needs
careful quoting; pounix's `UnixProcesses` gives fork and exec without a
shell, but only on Unix. A small module of podoc's own should hide the
difference.

## 8. Lua: embed it or not

The question is whether podoc should run Lua filters, so that the
user's filters (and new ones) work unchanged.

### 8.1. What pandoc's Lua API is

`pandoc-lua-engine` is 5,813 lines of Haskell, on top of
`pandoc-lua-marshal`, which turns every AST element into Lua userdata
with methods, lazy lists and `walk`. The filters see `pandoc.Str`,
`pandoc.Para`, `pandoc.RawBlock`, `pandoc.List` (with `:map`,
`:filter`, `:insert`, `:includes`), `pandoc.read`, `pandoc.utils`
(`stringify` above all), `FORMAT`, `PANDOC_SCRIPT_FILE`, and the
traversal rules (typewise or topdown, return `nil` to keep, a list to
splice, `{}` to delete).

### 8.2. Ways to run Lua

- **(a) Embed Lua 5.4.** Lua is MIT licensed, about 30,000 lines of
  ANSI C, and builds anywhere a C compiler exists. It would be a C part
  of a podoc module (an amalgamation in the style of `onelua.c`), so
  podoc does not depend on an installed Lua. Fedora here has
  `lua-libs` but no `lua-devel`, so the headers would come from the
  vendored copy anyway.
- **(b) Run an external `lua`.** podoc writes the document as a Lua
  table literal and a prelude, runs `lua`, and reads the result back.
  No C at all, but each filter costs a process, and `pandoc.read`
  (which `combine-docs.lua` needs) has to call back into podoc as yet
  another process.

Under either, the `pandoc` module itself is best written in Lua, as
pandoc 2.0 to 2.16 did with its `data/pandoc.lua`: constructors that
make plain tables with a `t` field, `pandoc.List`, `walk_block` and
`walk_inline`, and `utils.stringify`. Oberon serialises the AST as Lua
table text, Lua deserialises it with `load`, the filter runs, and the
result comes back as text in the same format (or as JSON), which
Oberon parses. That keeps the C interface down to a handful of calls:
`luaL_newstate`, `luaL_openlibs`, `luaL_loadbuffer`, `lua_pcall` and
reading a string result.

`pandoc.read` under (a) is a C function, registered in Lua, that calls
an Oberon procedure value (poc can pass procedure values to C, as
pofltk's callbacks do) and returns the serialised AST of the parsed
text.

### 8.3. Hazards

- A Lua error longjmps. It must never cross an Oberon frame, so every
  call into Lua goes through `lua_pcall`, and the C callback for
  `pandoc.read` must catch Oberon failures itself and turn them into a
  Lua error only after Oberon has returned.
- Compatibility is a moving target: filters written for pandoc 3 may
  use `elem:walk`, `pandoc.Inlines`, `pandoc.Blocks`,
  `pandoc.structure`, `pandoc.path` and more. The proof of concept
  would support what the user's filters use and say so.
- C is not available on every system podoc is for. The VAX/VMS backend
  of poc compiles Oberon; a C part needs a VMS C compiler as well.

### 8.4. Recommendation

1. Native Oberon equivalents of the user's filters first (§4). They
   are a few hundred lines in all and run without Lua.
2. Lua as an optional, later phase, behind `make LUA=yes`, embedding
   vendored Lua 5.4 (option a), with the `pandoc` module in Lua. The
   core stays pure Oberon.
3. Possibly also pandoc's JSON filter protocol (`--filter prog`, AST as
   JSON on standard input and output), since podoc will already write
   JSON and could read it. That runs filters in any language without
   linking anything.

## 9. YAML

The metadata the user writes is simple: scalars, plain and quoted
strings, block scalars (`|`, `>`), lists of scalars, small maps, and
comments. pandoc parses each string value as markdown (so `title:
"*Lost* Worlds"` is emphasised) unless it is a boolean or number.

- **polibfyaml** (`~/Repos/Oberon/polibfyaml`) wraps the C library
  libfyaml through pkg-config. It is complete and tested, but it is
  installed here for `-OC` only, it has not been tried on the BSDs, and
  libfyaml is one more C library to find on a small system, which is
  the problem podoc exists to avoid.
- **A native subset parser**, about 800 lines: block maps and
  sequences, flow sequences and maps of scalars, plain, single- and
  double-quoted scalars, block scalars with chomping, comments, and the
  `---`/`...` fences. Anchors, aliases, tags and multi-document streams
  are rejected with a message.

Recommendation: the native parser, with polibfyaml as a later option
for full YAML. The same parser reads `--metadata-file`.

## 10. Unicode

podoc's text is UTF-8 throughout and mostly passes through untouched.
Two places need character properties:

- Automatic identifiers keep letters and numbers (Unicode categories L
  and N) and lower-case them, and drop other characters.
- Smart punctuation and emphasis rules look at whether the neighbours
  of a delimiter are spaces, punctuation or alphanumerics.

pounicode (`Utf8`, `Unicode`, `Utf8Strings`, `Utf8Files`) does all of
this, under both size models. It has no VAX build; if VMS is a target,
an ASCII-only fallback for identifiers would be needed there.

## 11. Testing

Oracles, all from the installed pandoc 3.10:

- **The reader:** `pandoc -f markdown -t json` gives the AST as compact
  JSON. podoc writes the same JSON, so a byte-for-byte comparison
  checks the reader with no writer in the way. (Field order and number
  formatting must match pandoc's; `"pandoc-api-version":[1,23,1]`.)
- **The writers:** `pandoc --wrap=none -t html|ms|context`, standalone
  and not, compared as text.
- **Inputs:**
  - pandoc's own fixtures in the cloned source's `test/`:
    `testsuite.txt` with `writer.html5`, `writer.ms`, `writer.context`
    (made with default wrapping, so regenerate with `--wrap=none`);
    `tables.txt`, `pipe-tables.txt`, `markdown-reader-more.txt`; and
    the 1,158 `test/command/*.md` cases, of which `smart.md`,
    `yaml-metadata-blocks.md`, `setext-fenced-div.md`,
    `section-divs.md` and `figures-context.md` matter here. Many use
    extensions out of scope, so the harness needs a list of the cases
    expected to pass.
  - the user's documents: every markdown file of Lost-Worlds and
    Galactic-Bounty-Hunters, and the full builds (`make PANDOC=podoc`)
    whose PDFs are compared by eye and by `pdftotext`.
- **Tests in the repository** follow the other Oberon projects:
  `test/<Name>.Mod` printing `ok   - ` and `FAIL - ` lines, and
  file-based cases (`test/cases/<name>.md` with `.json`, `.html`,
  `.ms`, `.context`) whose expected files were made by pandoc and are
  committed, so `make test` does not need pandoc. A separate
  `make compare` runs against the installed pandoc where there is one.

## 12. Foundations available in Oberon

- **poc 0.14.0** (`/usr/bin/poc`, a410135), size models `-O2` (16/32)
  and `-OC` (32/64). A library is tied to the poc that built it. poc
  has no exceptions and no threads; `HALT` codes report failures.
  Functions cannot return records or arrays.
- **Runtime:** `Files`, `Strings`, `OutStr`/`InStr`,
  `Platform.System`, `Directories`, `Args`.
- **ArgParser** for the command line (it builds with poc and is
  installed). pandoc's options include forms (`-V key=val`,
  `--pdf-engine-opt=...` repeated, `-o file`, `-sF x`) that must be
  checked against it.
- **pounicode** for UTF-8 and character properties.
- **Ropes**, for text and output (§12.1).
- **pounix** (`UnixProcesses`, `UnixFiles`) for running the PDF
  engines without a shell.
- **poDateTime** for `$date$` defaults, if wanted.
- **polibfyaml** for full YAML, optionally.

### 12.1. Ropes

Checked 2026-11-20 at the user's request. `~/Repos/Oberon/Ropes`
(`Ropes.Mod`, 1,930 lines) is an immutable rope after Boehm, Atkinson
and Plass: a balanced tree of flat leaves, NIL as the empty rope,
short leaves merged on concatenation, Fibonacci rebalancing. It
exports concatenation, substring, insert, remove and replace;
iterators; searches (`Find`, `IndexChar`, `IndexSet`, `FindToken`);
comparison and hashing (with case-folding variants for ASCII);
`Split`; ASCII case mapping and `Translate`; trimming; and file input
and output that work leaf by leaf (`ReadFile`, `ReadLine`, `WriteFile`,
`WriteRider`), so a rope never has to be flattened into one
`ARRAY OF CHAR`. Positions are `LONGINT`.

It is installed for poc under both size models
(`~/.local/lib/poc/<triple>/{O2,OC}`: `libropes.a`, `Ropes.sym`). A
test program built on it under `-O2` and `-OC` appended 200,000
three-character ropes, found a string at the end, and wrote the
600,003 characters with `WriteFile`; the tree's depth was 34, and each
run took 0.04 s and 12 MB. (The comment at the end of the module's
header, "voc-only for now: it is not built by pocGNUmakefile", is out
of date: `pocGNUmakefile` builds and installs it.)

Where it fits podoc:

- **Output, yes.** Every writer builds its text by concatenation,
  nested: a list item's text is built, then indented, then joined into
  the list, then into the body, which a template splices into the
  page. Ropes make each of those steps cheap, where a flat buffer
  would copy the text again at each level, and `WriteFile` writes the
  result without flattening it. Template indentation of multi-line
  values (§6) is `Split` and `Cat`.
- **AST strings, probably.** `Str` text, attributes, URLs and code are
  mostly short. Holding them as Ropes gives one string type
  throughout, NIL for the empty string, `Equal` and `Hash` for
  reference and identifier tables, and no fixed-size arrays to
  overflow. The cost is a heap object per string; Phase 2.1 measures
  it on the largest Lost-Worlds build.
- **The reader, no.** Parsing looks at characters one by one, back and
  forth; an `ARRAY OF CHAR` holding the whole input, indexed directly,
  is simpler and faster than a rope iterator. The reader makes Ropes
  only for the text it keeps.
- **Not for Unicode.** Ropes is byte-oriented, which suits UTF-8 text
  that is mostly passed through; character properties come from
  pounicode, run over the bytes.

## 13. Size

A rough estimate, in Oberon lines:

| Part | Lines |
|---|---|
| AST and its JSON writer | about 600 |
| Markdown reader, blocks | 1,500–2,500 |
| Markdown reader, inlines and extensions | 1,500–2,500 |
| YAML subset | about 800 |
| Templates | about 800 |
| HTML writer | about 900 |
| ms writer | about 1,000 |
| ConTeXt writer | about 1,000 |
| Markdown writer (added 2026-11-20) | 1,200–1,500 |
| Includes and native filters | about 500 |
| Command line | about 400 |
| PDF driving | about 300 |
| **Total** | **11,000–14,500** |

For comparison, pandoc's Haskell: `Readers/Markdown.hs` 2,326 lines
and `Parsing/*` about 2,000 more; `Writers/HTML.hs` 1,755;
`Writers/Ms.hs` 658 with `Writers/Roff.hs` 129; `Writers/ConTeXt.hs`
837; `Writers/Shared.hs` 628; `Writers/Markdown.hs` and
`Writers/Markdown/` 1,928. Haskell is denser than Oberon by a factor
of two or three.

## 14. Risks

1. **Reader fidelity.** pandoc markdown has many rules that differ
   from CommonMark and from each other's intuitions: the four-space
   rule for list continuation, lazy continuation lines, setext headers
   against rules against YAML fences, the smart-quote heuristics,
   intraword underscores, YAML blocks anywhere, implicit header
   references, and link references and footnotes defined anywhere
   (which needs two passes). Mitigation: the JSON oracle from the
   start, and the user's own documents as the first acceptance tests.
2. **Writer and template quirks.** Small differences (spacing, `\&`
   escapes, the order of attributes) make diffs noisy. Mitigation:
   `--wrap=none`, and a decision on exact versus equivalent output
   (§15).
3. **YAML.** A subset parser may meet a construct the user writes
   later. Mitigation: clear errors naming the construct, and
   polibfyaml as a fallback.
4. **Unicode on VMS.** pounicode has no VAX build.
5. **poc is young.** Bugs found in poc are reported to the user, not
   worked around silently.
6. **Running programs.** Temporary directories, relative image paths
   for ConTeXt, quoting through `Platform.System`, and portability to
   the BSDs and to systems without pounix.
7. **Lua compatibility.** If Lua is added, the surface of pandoc's Lua
   API is large and grows; supporting it all is out of reach.
8. **Scope creep.** Every extension pandoc has is a few hundred lines
   away. The plan keeps a "Later" list rather than adding features
   ahead of need.

## 15. Open questions for the user

The user decided these on 2026-11-20: no VAX/VMS; the Oberon YAML
subset first, with polibfyaml acceptable later; equivalent output; no
mermaid; a new substitutions format; no Lua for now; a full markdown
writer; and the name and command line as proposed. `PLAN.md`'s
"Decisions" records them and what follows from each. The questions
are kept below as they were asked.

1. **Is VAX/VMS a target for podoc?** It decides whether C (Lua,
   libfyaml) is acceptable in the core and whether pounicode is.
   Recommendation: not for the proof of concept, but keep the core
   free of C so it stays possible.
2. **YAML:** a native subset (recommended) or polibfyaml?
3. **Fidelity:** must podoc's output match pandoc's byte for byte (at
   `--wrap=none`), or is equivalent output (the same PDF and rendered
   HTML) enough? Recommendation: byte for byte for the JSON AST;
   equivalent but diffable for the writers, with known differences
   listed.
4. **Mermaid:** out of scope, or `mmdc` when present?
5. **`substitutions.lua`:** read the Lua table directly (recommended),
   or move to a new format?
6. **Lua:** later and embedded (recommended), external `lua`, or not
   at all?
7. **`-whole.md`:** a real markdown writer, or a textual include
   expansion (recommended for the proof of concept)?
8. **Name and command line:** `podoc`, with pandoc's options, so that
   `PANDOC=podoc` works in the GNUmakefiles?

## 16. Sources consulted

- pandoc 3.10 source, cloned at tag 3.10 (commit 9376458) under
  `/usr/local/sw/src/lang/Haskell/pandoc/pandoc-3.10`, and
  `doctemplates` beside it. pandoc 3.1.11.1 was already there.
- The installed pandoc 3.10, run on small test documents.
- `pandoc-include`'s Python source, as installed.
- The GNUmakefiles, filters, templates and markdown of the four
  projects in §2, and `~/.pandoc/filters` and `~/.pandoc/templates`.
- The Oberon libraries under `~/Repos/Oberon` and Peaseblossom's
  documentation.
