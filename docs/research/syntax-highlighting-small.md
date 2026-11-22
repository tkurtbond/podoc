# Small syntax highlighting: reserved words in bold

Research for podoc, 2026-11-22. This study covers highlighting written
from scratch for ms, mom and ConTeXt output. It does not use pandoc's
skylighting, its syntax files or its token styles. The highlighting
does one thing: it sets the reserved words of a language in bold.
docs/research/syntax-highlighting-big.md studied a port of skylighting,
which the user decided against (PLAN.md's decision 29).

Everything below marked *verified* was run on atla, with these
versions:

- groff 1.25.0;
- ConTeXt LMTX;
- pandoc 3.14 (installed on 2026-11-22; AGENTS.md still names 3.10);
- gcc and g++ 16.2.1;
- GNAT 16.2.1;
- gm2 16.2.1;
- poc 0.15.0;
- FreePascal 3.2.3, with its compiler source;
- bash.

## 1. Summary

- **Two styles.**
  - *mono* sets code in the monospaced font, with reserved words in
    bold monospace.
  - *proportional* sets code in the text font, with reserved words in
    bold, and keeps line breaks and indentation.
- **Writers.** All three writers can do both styles with markup they
  already use. Each form below was rendered and checked (§4).
- **Languages.** Seven language families are covered: sh and bash,
  Oberon-2, Modula-2, Ada, Pascal (every FreePascal mode, Object
  Pascal among them), C and C++.
  - Each needs a list of reserved words. The lists were checked
    against the compilers on atla (§5).
  - Each also needs a scanner that knows the language's comments,
    strings and character literals, so that a reserved word inside a
    comment or a string stays plain.
  - The scanners are not hard to write. The awkward cases are sh,
    where a word is reserved only in command position, Ada, where
    `'` is both the attribute tick and a character-literal quote, C++
    raw strings, and Pascal's comment forms, which differ by mode.
- **User lists.** A plain word-list file per language is simple to
  read with what podoc already has (§6).
- **Size.** About 1,500 to 2,300 lines of Oberon, tests included,
  mostly in one new module. There are no external data files, no
  licence questions and no C. The skylighting port would have been
  about 4,000 lines plus megabytes of GPL and LGPL data.
- **Divergence from pandoc.** This is podoc's own feature: pandoc has
  nothing like it. With it on, podoc's output differs from pandoc's,
  so it should be off by default and documented in
  docs/user/differences.md (§3).
- **A bug found on the way, not caused by highlighting.**
  - Under groff 1.25.0, podoc's ms code blocks are set in Times-Roman,
    not Courier. The block starts with `\f[C]`, and groff 1.25 no
    longer has a font `C` (*verified*). pandoc 3.14 writes the same
    `\f[C]`, with the same result.
  - `\f[CR]` is the fix, and highlighting needs it anyway (§4.1).

## 2. What was asked

- Highlighting for ms, mom and ConTeXt, written from scratch.
- Two styles: *mono* and *proportional*. Only reserved words are
  marked, and only in bold.
- Languages: sh, bash, Oberon-2, Modula-2, Ada, Pascal (all the
  FreePascal dialects, Object Pascal among them), C and C++.
- A way for the user to give the list of reserved words for a
  language.

Not asked, and left out of this study:

- colour;
- comments or strings in their own style;
- HTML output (added later, 2026-11-22: PLAN.md decision 46 and
  Phase 24.5);
- line numbers;
- languages beyond these.

§9 notes which of them the design would make cheap later.

## 3. pandoc, and why this is podoc's own

- pandoc 3.14 highlights with skylighting. Its token macros give
  keywords bold and also colour.
  - Since 3.11 or later, `-s -t ms` defines the macros, and
    `-s -t context` compiles (*verified* with 3.14).
  - The two 3.10 regressions recorded in the big study are gone in
    3.14. The token markup in the body is unchanged.
- pandoc knows `ada`, `bash`, `c`, `cpp`, `modula2` and `pascal`
  (`--list-highlight-languages`, *verified*), and `sh` through bash.
  It has no Oberon, so pandoc writes an `oberon` block as plain code.
- No pandoc option asks for "keywords in bold, nothing else", and none
  asks for code in a proportional font. Whatever podoc does here
  differs from pandoc. podoc should therefore keep writing what it
  writes now unless the user asks for highlighting: the case tests
  stay as they are, and `make compare` stays meaningful.
- docs/user/differences.md already says, for HTML, ms and ConTeXt,
  that code is not highlighted. Those entries would say instead that
  podoc highlights only on request, only reserved words, and only in
  bold.

## 4. The output, writer by writer

Each form was written by hand, rendered to PDF, and checked with
`pdffonts`, `pdftotext` and a look at the page (*verified*).

### 4.1 ms

- **Today.**
  - A code block is `.IP` / `.nf` / `\f[C]` ... `\f[]` / `.fi`.
  - Inline code is `\f[CR]` ... `\f[R]`.
- **groff 1.25 and `\f[C]`.** groff 1.25.0 warns "font name 'C' is
  deprecated", then fails "cannot open font description file 'C'".
  The block keeps the current font, Times-Roman.
  - Checked with podoc's own output: a document with only a code
    block has Times-Roman as its only font.
  - pandoc 3.14 does the same, and its highlighted keywords come out
    in Courier-Bold among Times-Roman text.
  - Whether older groffs (1.22, 1.23) accepted `C` was not checked.
  - `\f[CR]` works everywhere the C family exists.
- **mono.** Start the block with `\f[CR]`, and write each reserved
  word as `\f[CB]WORD\f[CR]`. *Verified:* Courier and Courier-Bold
  only.
  - This must be `\f[CR]`, not `\f[C]`. After a failed `\f[C]`, the
    bold carries on to the end of the block (seen in the test).
- **proportional.** Use the same `.IP` / `.nf` with no font change,
  and write each reserved word as `\f[B]WORD\f[R]`. *Verified:*
  Times-Bold and Times-Roman, line breaks and indentation kept.
  - `\f[B]` and `\f[R]` stay within the current family, so a template
    that sets `.fam` keeps working.
- **Inline code** in mono style: `\f[CB]` and `\f[CR]` inside the
  existing `\f[CR]` ... `\f[R]` span (*verified*).
- **Escaping.** `PdRoff.EscapeStr` stays as it is. The highlighter
  only puts font escapes between escaped pieces.
  - A reserved word never holds a character that needs escaping.
  - A line that starts with a keyword starts with `\f[`, so it cannot
    be taken for a request. The existing `\&` rule for a leading `.`
    still applies to the other lines.

### 4.2 mom

- **Today.** A code block is `.QUOTE` / `.CODE` ... `.CODE OFF` /
  `.QUOTE OFF`. Inline code is `Ro.FontChange` with the family `C`.
- **mono.** Inside `.CODE`, write each reserved word as
  `\*[BD]WORD\*[PREV]` (*verified*: Courier and Courier-Bold).
  - `\*[BD]` is `\f[B]` in the current family (om.tmac), so this
    works because `.CODE` sets the family to `C`.
- **proportional.** Drop `.CODE` and keep `.QUOTE`, which already
  keeps the line breaks, with `\*[BD]WORD\*[PREV]`.
  - *Verified, and a problem:* mom's `.QUOTE` is italic by default.
    The code came out in Times-Italic, with keywords in Times-Bold,
    and `\*[PREV]` went back to italic.
  - The block needs a roman font set around it, for example
    `.QUOTE_FONT R` before it and the template's own setting restored
    after. Another choice is a mom no-fill block other than `.QUOTE`.
    This is design work in mom, not yet tried (Q7).
- **Tabs.** In the hand-written test, a line that started with a tab
  vanished inside `.QUOTE`, in both styles.
  - podoc's markdown reader expands tabs to spaces (`--tab-stop`), so
    podoc's normal output has no tabs there. Checked: a tab-indented
    line in a fenced block comes out as four spaces and renders.
  - With `-p` (`--preserve-tabs`) tabs reach the writer. Whether
    podoc's mom output then loses lines was not checked. If it does,
    that is a bug of its own, separate from highlighting.

### 4.3 ConTeXt

- **Today.** A code block is `\starttyping` ... `\stoptyping`. Inline
  code is `\type{...}`, or `\type[escape=yes]{...}` when the code
  holds braces.
- **mono.** Use `\starttyping[escape=yes]`, and write each reserved
  word as `/BTEX\bf WORD/ETEX`. The rest of the code stays verbatim,
  as now. *Verified:* LMMono10-Regular and LMMonoLt10-Bold.
  - Inline code works the same way:
    `\type[escape=yes]{x := /BTEX\bf NIL/ETEX;}` (*verified*). This is
    the escape mechanism `PdConTeXt.Code` already uses for braces.
  - **A weak bold.** ConTeXt's default mono bold is Latin Modern Mono
    *Light* Bold. In the rendered page the keywords are hard to tell
    from the regular weight. The style needs a mono font with a real
    bold, set in the template (for example DejaVu Sans Mono, or TeX
    Gyre Cursor), or the result is barely visible. This is a template
    question, not a code question, but it decides whether *mono* is
    worth having in ConTeXt.
  - The literal text `/BTEX` or `/ETEX` inside code would break the
    block. pandoc's highlighting has the same limit. It is unlikely in
    the user's code, and can be avoided by choosing other escape
    strings with `\setuptyping`.
- **proportional.** Use `\startlines[space=on]` ... `\stoplines`, and
  write each reserved word as `{\bf WORD}`. *Verified:* LMRoman10
  Regular and Bold, line breaks and indentation kept.
  - The code is no longer verbatim, so every special character
    (`# $ % & \ { } ~ ^ _`, and `|`) must go through the writer's
    normal text escaping, as for a paragraph.
  - `space=on` keeps every space at a fixed width, which keeps
    indentation.

### 4.4 Indentation and alignment in the proportional style

- Line breaks and leading indentation survive in all three writers.
- Alignment in the middle of a line does not survive: columns of `:`,
  `:=` or trailing comments. That is the nature of a proportional
  font, and why one would choose it knowingly.
- *Later (2026-11-22):* docs/research/vgrind.md §8 shows both can be
  kept, in ms, mom and ConTeXt, by placing each run of spaces at a
  position for its column. Which form, and the column width, is its
  question V4.
- In groff, a space in `.nf` is an interword space, about a quarter
  of an em, so indentation shrinks to a fraction of the mono width.
  - Writing each leading space as `\0` (digit width) or
    `\h'0.5n'` would keep the indentation closer to its mono shape.
  - Not tried. It would be a choice to make while implementing, and
    the case tests would fix it.
- Wrapping: code blocks are `L.Literal` in `PdLayout` and do not wrap.
  - Inline code wraps with the paragraph. The new font escapes
    lengthen the text that `PdLayout` measures.
  - Whether `PdLayout` counts roff escapes as width must be checked
    first. If it does, a line with highlighted inline code wraps
    earlier than the same line without.

## 5. The languages

Each language needs:

1. a reserved-word list;
2. case sensitivity;
3. comment forms, and whether they nest;
4. string and character-literal forms, with their escape or doubling
   rules;
5. any rule that makes a reserved word not reserved in some position.

The scanner only has to tell "reserved word" from "anything else":
numbers, operators and identifiers need no classes of their own. A
scanner that is wrong in a corner case gets the bolding wrong, never
the text, because the text is copied unchanged (§8).

The counts below were checked by compiling a declaration of each word
as an identifier, and confirming that the compiler rejects it.

### 5.1 Oberon-2

- **Reserved words:** 34.
  - The list: `ARRAY BEGIN BY CASE CONST DIV DO ELSE ELSIF END EXIT
    FOR IF IMPORT IN IS LOOP MOD MODULE NIL OF OR POINTER PROCEDURE
    RECORD REPEAT RETURN THEN TO TYPE UNTIL VAR WHILE WITH`.
  - *Verified* with `poc -check-syntax`: all 34 are rejected as
    variable names, and `x` is accepted.
  - poc adds no reserved words: its extensions are predeclared
    procedures (Peaseblossom's language-extensions.md says so, and
    why).
- **Case:** sensitive. Only upper case is reserved, so `begin` is an
  identifier.
- **Comments:** `(* ... *)`, which nest.
- **Strings:** `"..."` or `'...'`, with no escapes. A character
  constant like `0AX` is a number.
- **Predeclared identifiers** (`INTEGER`, `NEW`, `TRUE`, `ABS`, ...)
  are not reserved (*verified*: poc accepts them as variable names).
  Whether to bold them is Q3.
- **Variants.** The class could also cover Oberon-07 and Component
  Pascal, whose lists differ a little. That is a list question, so
  the user's list option can cover it (Q8).

### 5.2 Modula-2

- **Reserved words.**
  - PIM's 40: `AND ARRAY BEGIN BY CASE CONST DEFINITION DIV DO ELSE
    ELSIF END EXIT EXPORT FOR FROM IF IMPLEMENTATION IMPORT IN LOOP
    MOD MODULE NOT OF OR POINTER PROCEDURE QUALIFIED RECORD REPEAT
    RETURN SET THEN TO TYPE UNTIL VAR WHILE WITH`.
  - ISO 10514 adds `EXCEPT FINALLY FORWARD PACKEDSET REM RETRY`.
  - *Verified* with gm2: all 46 are rejected under both `-fpim` and
    `-fiso`. gm2 reserves the ISO words even in PIM mode, so one list
    of 46 matches the installed compiler.
  - ISO's object-oriented and generic additions (`CLASS`, `GENERIC`,
    `TRACED`, ...) were not checked. They are rare and can go in a
    user list.
- **Case:** sensitive, upper case.
- **Comments:** `(* ... *)`, which nest.
- **Pragmas:** gm2 and ISO pragmas are `<* ... *>`. They could be
  treated as comments.
- **Strings:** `"..."` or `'...'`, with no escapes.

### 5.3 Ada

- **Reserved words:** 74 in Ada 2022.
  - The list: `abort abs abstract accept access aliased all and array
    at begin body case constant declare delay delta digits do else
    elsif end entry exception exit for function generic goto if in
    interface is limited loop mod new not null of or others out
    overriding package parallel pragma private procedure protected
    raise range record rem renames requeue return reverse select
    separate some subtype synchronized tagged task terminate then
    type until use when while with xor`.
  - *Verified* with GNAT 16.2.1, `-gnat2022 -gnats`: 73 are rejected.
    `parallel`, new in Ada 2022, is still accepted as an identifier by
    this GNAT, perhaps because GNAT ties it to its extensions
    (`-gnatX`), which was not tried.
  - Bolding `parallel` follows the standard. A user who disagrees can
    remove it with a list.
- **Case:** insensitive (`BEGIN`, `Begin` and `begin` are all
  reserved).
- **Comments:** `--` to the end of the line.
- **Strings:** `"..."`, with `""` for a quote inside.
- **The tick.** `'` is both the attribute tick (`X'First`,
  `T'(...)`) and the quote of a character literal (`'a'`).
  - The usual rule: after an identifier, a `)` or the word `all`, `'`
    is a tick. Otherwise `'x'` is a character literal.
  - After a tick, a reserved word used as an attribute (`X'Access`,
    `X'Range`, `X'Delta`, `X'Digits`, `X'Mod`) must stay plain.
  - `Character'('a')` needs both rules at once. This is the one place
    where Ada's scanner needs care.
- **Based literals** (`16#FF#`) need no handling: they hold no
  letters that could be taken for a word, apart from hex digits
  inside a number.

### 5.4 Pascal, FreePascal and Object Pascal

FreePascal's own table, `compiler/tokens.pas` in the FPC 3.2.3 source,
gives each word the set of language modes in which it is reserved.
Grouping the table (*verified*):

| Reserved in | Words |
|---|---|
| every mode (fpc, objfpc, delphi, tp, macpas, iso, extendedpascal) | 36: `and array begin case const div do downto else end file for function goto if in label mod nil not of or packed procedure program record repeat set then to type until var while with` |
| every mode but iso and extendedpascal | 18: `asm`, `otherwise` (both also in extendedpascal), `shl shr unit uses object string exports library bitpacked inherited interface threadvar destructor constructor implementation resourcestring` |
| objfpc, delphi (`m_class`) | `as is class dispinterface` |
| objfpc, delphi (`m_except`) | `try raise except finally` |
| fpc, objfpc, delphi (`m_property`) | `property` |
| fpc, objfpc (`m_fpc`) | `cppclass operator` |
| macpas | `univ return` |
| tp | `inline` |
| objectivec1 mode switch | `objcclass objccategory objcprotocol` |
| no mode: "modifiers" | 143 words such as `override virtual cdecl stdcall forward external abstract published private public protected strict sealed helper generic specialize absolute deprecated` |

- **Modes.**
  - The default mode, `fpc`, does not reserve `class` or `try`.
    `objfpc` and `delphi`, the usual Object Pascal modes, do.
  - A Pascal class could take its mode from:
    - the class name (`pascal`, `objfpc`, `delphi`, `tp`, `macpas`,
      `iso`);
    - a `{$mode ...}` directive at the top of the code;
    - or a single superset list.

    The superset gets ISO Pascal slightly wrong (`string`, `unit`,
    `class` are identifiers there) and every Object Pascal program
    right. This is Q4.
- **Modifiers.** The 143 modifiers are not reserved; they have
  meaning only in certain places. A reader of Object Pascal would
  expect `override`, `virtual`, `private`, `public`, `published`,
  `property` and `forward` in bold, as Lazarus's editor shows them.
  This is Q3, and a user list covers it either way.
- **Case:** insensitive.
- **Comments:**
  - `{ ... }` and `(* ... *)`;
  - `// ...` in FPC and Delphi modes;
  - nesting depends on the mode: FPC's documentation says nested
    comments are on in `fpc` and `objfpc` and off elsewhere (not
    checked against the compiler here).
  - `{$...}` directives look like comments and can be scanned as
    comments.
- **Strings:**
  - `'...'`, with `''` for a quote inside;
  - `#13` and `#$0D` character codes are numbers.
- **`&` before a word** (`&begin`) makes it an identifier in FPC and
  Delphi. It is cheap to honour.

### 5.5 C

- **Reserved words:** 59 for C23, with the old underscore spellings.
  - The list: `alignas alignof auto bool break case char const
    constexpr continue default do double else enum extern false float
    for goto if inline int long nullptr register restrict return
    short signed sizeof static static_assert struct switch
    thread_local true typedef typeof typeof_unqual union unsigned void
    volatile while _Alignas _Alignof _Atomic _BitInt _Bool _Complex
    _Decimal128 _Decimal32 _Decimal64 _Generic _Imaginary _Noreturn
    _Static_assert _Thread_local`.
  - *Verified* with `gcc -std=c23`: 45 are rejected as names in
    `int WORD;`. The other 14 are qualifiers and specifiers (`const`,
    `long`, `static`, `typedef`, `_Atomic`, ...), which that
    declaration accepts as part of the type, so the test cannot show
    them. They are keywords by the standard.
- **Case:** sensitive.
- **Comments:** `/* ... */`, which do not nest, and `// ...`.
- **Strings and characters:**
  - `"..."` and `'...'`, with backslash escapes;
  - prefixes `L`, `u`, `U`, `u8`;
  - a backslash-newline continues a line.
- **Preprocessor:** `#include`, `#define`, `#if` and the rest are
  not keywords. Bolding the directive name is a reasonable choice
  (Q3). The rest of the line is scanned as C, so `defined` stays
  plain and `if` in `#if` follows that choice.

### 5.6 C++

- **Reserved words:** 92 in C++23.
  - The list: C's words without the underscore forms and the C-only
    ones (`restrict`, `typeof`, `_Generic`, ...), plus `and and_eq
    asm bitand bitor catch char8_t char16_t char32_t class compl
    concept consteval constinit const_cast co_await co_return
    co_yield decltype delete dynamic_cast explicit export friend
    mutable namespace new noexcept not not_eq operator or or_eq
    private protected public reinterpret_cast requires static_cast
    template this throw try typeid typename using virtual wchar_t xor
    xor_eq`.
  - *Verified* with `g++ -std=c++23`: all 92 are rejected as names.
  - The identifiers with special meaning, `final`, `override`,
    `import` and `module`, are accepted. They are contextual, not
    reserved; Q3 again.
- **Lexing beyond C:**
  - raw strings, `R"delim( ... )delim"`, which can hold `"` and
    newlines;
  - digit separators, `1'000'000`, where `'` is not a character
    literal. A `'` straight after a digit inside a number belongs to
    the number.
- **Future standards.** C++26 adds words. New standards are what the
  user list is for.

### 5.7 sh and bash

- **Reserved words.**
  - POSIX: `! { } case do done elif else esac fi for if in then until
    while`.
  - bash adds `[[ ]] function select time coproc`. *Verified*:
    `compgen -k` in bash prints exactly these 22.
- **Command position.** A word is reserved only:
  - as the first word of a command: after a newline, `;`, `&`, `|`,
    `&&`, `||`, `(`, `{`, `` ` ``, `$(`, or another reserved word
    such as `then` or `do`;
  - or, for `in` (and `do` after `for NAME in WORDS;` with no `;`
    before it), as the third word of `for`, `case` or `select`.

  So in `echo done` or `ls if`, `done` and `if` stay plain. This is
  what keeps sh from being a word list with comments.
- **Comments:** `#` only at the start of a word. In `${#x}` or `a#b`
  it does not start a comment.
- **Quoting:**
  - `'...'`, with no escapes;
  - `"..."`, with `\` escapes, and `$(...)` and `` `...` `` inside;
  - a `\` before any character.
- **Here-documents:** after `<<WORD`, `<<-WORD`, `<<'WORD'` or
  `<<"WORD"`, the lines up to `WORD` are data and stay plain.
  - The scanner must remember the pending delimiters until the end
    of the line, then skip the body.
  - Several on one line are allowed.
- **Case patterns:** in `case x in a|b) ...;; esac`, the patterns are
  words before `)`, not commands. `esac` can still appear in a
  command position, and after `;;` comes a pattern.
- **Builtins** (`echo`, `cd`, `export`, `local`, `return`) are not
  reserved. Whether to bold them is Q3.
- **Other shells.** zsh and ksh share most of this. They are not
  asked for; a class name could map to the bash rules later.

### 5.8 What the languages share

All seven fit one scanner driven by a description of each language,
with a few hooks:

| | Case | Block comments | Line comment | Strings | Hooks |
|---|---|---|---|---|---|
| Oberon-2 | sensitive | `(* *)`, nest | | `" '`, no escapes | |
| Modula-2 | sensitive | `(* *)`, nest; `<* *>` | | `" '`, no escapes | |
| Ada | insensitive | | `--` | `"` doubled | the tick |
| Pascal | insensitive | `{ }`, `(* *)`, nesting by mode | `//` | `'` doubled | `&word`, mode |
| C | sensitive | `/* */` | `//` | `" '`, backslash | prefixes, `#` lines |
| C++ | sensitive | `/* */` | `//` | `" '`, backslash | raw strings, digit separators |
| sh, bash | sensitive | | `#` at word start | `'`, `"` and `\` | command position, here-documents, `case` |

## 6. The user's lists of reserved words

podoc has no data directory: its templates are compiled in by
`tools/mktemplates`. The built-in lists would be compiled in the same
way. The user's lists come from files named on the command line, or
from metadata.

- **A word-list file.**
  - Words separated by spaces or newlines; `#` to the end of the line
    is a comment.
  - It is read with `Files` and split by hand, under 100 lines.
  - For a language that ignores case, the words compare without case.
  - An option names the language and the file, for example
    `--keywords=pascal:mywords.txt`, and may be given once per
    language. A missing file is exit status 98 or 99, as for
    pandoc's other missing files.
- **Replace or add.** Both are useful:
  - *replace* for a dialect (Oberon-07, Component Pascal, K&R C);
  - *add* for a project's own words (Object Pascal's modifiers,
    `final` and `override`, a C project's macros).

  Possible forms:
  - two options;
  - a first line in the file (`#!replace`);
  - `-word` lines that remove a word from the built-in list.

  This is Q5.
- **Metadata.** The same lists could come from YAML metadata, read
  with `PdYaml`:

  ```yaml
  keywords:
    pascal: [override, virtual, private, public, published]
  ```

  This keeps a book's settings in its metadata file, as the user's
  builds already do. It costs a little more than the file option
  (about 50 lines), and both could exist.
- **Defining a language.** A list could name a new class with the
  rules of an existing one (`--keywords=oberon07:like=oberon:file`).
  It was not asked for and goes to "Later" if wanted.

## 7. Choosing the language and the style

- **The language** comes from the code block's classes, the first one
  the highlighter knows. podoc's markdown and rST readers already keep
  classes: `{.pascal}`, ```` ```c ````, `.. code:: ada`.
  - pandoc's names: `sh`, `bash`, `ada`, `c`, `cpp`, `modula2`,
    `pascal`.
  - podoc's additions:
    - `oberon` and `oberon2`, since pandoc has no Oberon;
    - `objfpc`, `delphi`, `fpc`, `tp`, `macpas`, `iso`, as Pascal
      modes (Q4).
  - Code with no class, or an unknown one, is written plain, as now.
  - Inline code with a class (`` `x := NIL`{.oberon} ``) can be
    highlighted the same way (Q2).
- **The style**, `none` (default), `mono` or `proportional`, comes
  from an option and from a metadata variable, so that a document can
  set it.
  - Reusing pandoc's `--syntax-highlighting` with new values would
    confuse: pandoc would try to read `mono` as a theme file and fail.
  - A podoc option of its own is clearer, such as
    `--code-style=none|mono|proportional`.
  - The name is Q1.
  - A per-block override, a class `.proportional` or `.mono`, costs a
    few lines and would let one document mix the two.

## 8. Design and size

One new module, `PdCode`, scans a code rope and returns spans: start,
length, and whether the span is a reserved word.

- **The writers.** Each writer copies the text between spans through
  its existing escaping, and wraps each reserved word in the bold
  markup of §4.
  - This keeps the property that matters most: **the text is never
    changed, only font changes are added**. A scanner mistake can bold
    the wrong word or miss one; it cannot lose or garble code.
  - With the style `none`, the writers take today's path, byte for
    byte.
- **The scanner.** A loop driven by a language record:
  - case sensitivity;
  - comment delimiters, and nesting;
  - line-comment markers;
  - string quotes, and the escape or doubling rule;
  - a hook procedure for the language's special rules (§5.8).
- **Word lookup.** A sorted array or a small hash table per language.
  - About 350 built-in words in all, generated from
    `data/keywords/<lang>.txt` by a tool like `tools/mktemplates`, or
    written in the module.
  - Under `-O2`, word positions are `LONGINT`, as for all text.

| Part | Lines (estimate) |
|---|---|
| `PdCode`: scanner, language records, lookup | 500–700 |
| hooks: sh, Ada tick, C++ raw strings, Pascal modes | 250–400 |
| built-in word lists | 60–120 |
| user lists: file option, metadata, add and replace | 120–200 |
| options and metadata for the style | 60–100 |
| writers: ms, mom, ConTeXt, both styles, block and inline | 150–250 |
| `PdCodeTest`: spans for each language's corner cases | 300–450 |
| case tests: each writer, each style | 60–100 files' worth |
| **total** | **about 1,500–2,300** |

There are no new libraries, no C and no data files at run time. The
built-in lists are the languages' own definitions, which carry no
licence, and the FreePascal grouping is facts from its table, not its
code.

**Phases**, if the user goes ahead:

1. `PdCode` with Oberon-2, Modula-2 and C. These are the simplest
   scanners, and they prove the framework.
2. The writers and the style option. Fix the ms `\f[C]` first, as its
   own change.
3. Pascal with its modes, Ada, C++.
4. sh and bash.
5. User lists.
6. Documentation (podoc.md, differences.md); BSD tests.

Each phase is small enough to finish and commit alone.

## 9. Potential

- **Code becomes easier to read** in the user's PDFs. The user's own
  code is mostly in these languages: the Oberon projects, ova_cg_po,
  ova_cg_ada. The user's built documents have no code with a language
  today, so the benefit is for documents not yet written: notes,
  manuals for the Oberon libraries, podoc's own documentation.
- **The proportional style** is unusual. It suits short fragments in
  running text, and the old typographic habit, from Algol's
  publication language on, of setting programs in a text font with
  bold reserved words.
- **Oberon gets highlighting**, which pandoc does not offer at all.
- **Cheap extensions later.** The scanner already finds comments and
  strings, so italic comments or a different string style would be a
  few lines per writer. Line numbers, colour and HTML output are each
  separate small pieces of work. None is proposed here.

## 10. Risks

- **Divergence from pandoc.** It is a new output form that pandoc
  cannot reproduce.
  - It is off by default, so the existing case tests and
    `make compare` are unaffected.
  - Documents that turn it on build differently under pandoc; the
    user's documents do not depend on pandoc's highlighting today.
- **Scanner mistakes.** The worst cases are an unclosed comment or
  string that leaves the rest of a block unbolded, and sh's command
  position and here-documents.
  - The text is never at risk (§8).
  - Tests should take real code from the user's projects as fixtures,
    copied into `test/`, since the projects themselves are read only.
- **Fonts.**
  - ConTeXt's default mono bold is too light to see (§4.3). *mono* in
    ConTeXt needs a template font with a real bold.
  - groff's Courier-Bold and Times-Bold are fine.
- **mom's `.QUOTE` is italic**, and needs a roman setting for the
  proportional style. A tab-led line vanished in a hand-written
  `.QUOTE` (§4.2).
- **Wrapping** of inline code in ms and mom, if `PdLayout` counts
  font escapes as width (§4.4).
- **Moving standards.** C2y, C++26 and new FreePascal versions add
  words. The user lists answer that without a podoc release, and the
  built-in lists are easy to edit.
- **Scope creep.** Once reserved words are bold, colour, comment
  styles, HTML and more languages are natural requests. Each is
  modest with this design, but each is new work for the plan, not
  part of this one.
- **The ms `\f[C]` bug** exists with or without highlighting. It is
  noted here because highlighting cannot be done right without fixing
  it.

## 11. Questions for the user

- **Q1. The style option.**
  - What is it called (`--code-style`, `--highlight`, ...)?
  - Is it also a metadata variable?
  - Is a per-block class to override it wanted?
  - Default `none`?
  - *Decided in part 2026-11-22* (PLAN.md decision 35):
    `--code-style=none|mono|proportional`, and `code-style` in the
    metadata. The default and the per-block override are open.
  - *Completed 2026-11-22* (decision 35): default `none`; a block
    overrides it with the class `.mono`, `.proportional` or `.plain`.
- **Q2. Inline code.** Highlight inline code that has a language
  class, or only code blocks? In the proportional style, is inline
  code also set in the text font?
  *Decided 2026-11-22* (decision 38): bold, yes; always in the code
  font, as in the text font it would be hard to tell from the
  running text.
- **Q3. Words that are not reserved.** Should any of these be bold
  by default, or left to the user's lists?
  - Oberon's predeclared identifiers;
  - FreePascal's modifiers (`override`, `virtual`, `private`, ...);
  - C++'s contextual `final`, `override`, `import`, `module`;
  - C's preprocessor directives;
  - sh's builtins.
  *Decided 2026-11-22: reserved words only; the rest from users'
  lists* (decision 45).
- **Q4. Pascal modes.** One superset list, a list per mode chosen by
  class name, the `{$mode ...}` directive, or a combination?
  *Decided 2026-11-22* (decision 39): a list per mode, chosen by
  class; plain `pascal` means `fpc`.
- **Q5. User lists.**
  - From files, metadata or both?
  - Replace, add, or both, and in what syntax?
  - *Decided in part 2026-11-22* (decision 40): both files
    (`--keywords=pascal:words.txt`) and metadata. *Completed
    2026-11-22:* both: a list adds, a file's first line `#!replace`
    replaces, a `-word` line removes; in metadata, a list adds and
    `{replace: true, words: [...]}` replaces.
- **Q6. The ms `\f[C]` bug.** Fix it now, as a change of its own,
  writing `\f[CR]` for code blocks? The fix is a difference from
  pandoc, to be listed in differences.md.
  *Decided 2026-11-22: yes, as a change of its own* (decision 36).
- **Q7. mom's proportional style.** `.QUOTE` set to roman, or another
  mom block? *Decided 2026-11-22: `.QUOTE` with `.QUOTE_FONT R`*
  (decision 37).
- **Q8. Oberon variants.** Is `oberon` only Oberon-2, or should the
  built-in lists also know Oberon-07 and Component Pascal?
  *Decided 2026-11-22* (decision 41): original Oberon, Oberon-2,
  Oberon-07 and Component Pascal, each a class; `oberon` means
  Oberon-2. Classes: `oberon`/`oberon2`, `oberon1`/`oberon87`,
  `oberon07`, `cp`/`componentpascal`.

## 12. With vgrind's lessons

Added 2026-11-22, after docs/research/vgrind.md and PLAN.md's
decisions 30 to 34. It changes §7 and §8 where they differ; the rest
of this study stands. The user decided to implement it, as PLAN.md's
Phase 24. Nothing here is code yet. Decision 32's template lines have
not been run.

### 12.1 Three steps

§8 had two steps: scan, then write. The proportional style gets a
third step between them:

1. **Scan** (`PdCode`): the code becomes spans: plain, reserved word,
   or comment. Comments are new: they are needed for italic comments
   (decision 30).
2. **Lay out** (new, `PdCodeAlign`, proportional style only): each
   line is cut into its indentation and its segments; groups of lines
   whose segments share a column are found; positions are chosen as
   `--code-align` says (decision 33).
3. **Write** (`PdMs`, `PdMom`, `PdConTeXt`): the text goes through
   each writer's escaping, with font changes and positions added.

§8's rule still holds: **the text is never changed, only font changes
and positions are added.** A wrong scan or a wrong layout misplaces
bold, italic or a column. It cannot lose or garble code.

### 12.2 The scanner, with comments

- The language records and hooks are as in §5.8. The scanner already
  finds comments, to skip reserved words in them; it now returns them
  as spans as well.
- vgrind.md §6.2's "mistakes to avoid" become cases in `PdCodeTest`:
  - nested comments (Oberon, Modula-2, FreePascal);
  - braces inside strings;
  - C's `//`;
  - Modula-2's case rule;
  - sh's reserved words only in command position.
- Reserved-word lists are in podoc's own format only (decision 31).

### 12.3 Layout

`PdCodeAlign` takes a block's lines, as spans, and gives a list of
lines. Each line holds an indentation column and its segments. Each
segment holds a source column and pieces of text, and each piece has
its kind: plain, reserved or comment.

- **Cutting a line**, as in vgrind.md §8.1:
  - leading spaces give the indentation;
  - a run of two or more spaces ends a segment, and the next segment
    starts at its source column;
  - a single space stays a space;
  - trailing spaces are dropped.
- **A boundary inside a comment** (`(* a  b *)`): the italic is closed
  at the end of the segment and reopened at the start of the next.
  ConTeXt needs this, since each segment is a box (vgrind.md §8.2).
  roff does the same, so that the writers stay alike.
- **Groups**, for `elastic` and `hybrid`: consecutive lines with a
  segment at the same column. Their positions are worked out in
  column order, since a group's prefix refers only to groups to its
  left. This needs the whole block, which `L.Literal` already holds.
- **`--code-align`** (decision 33):
  - `none`: segments are joined again with their spaces (§4.4's
    proportional style, unaligned);
  - `fixed`: each segment at its column, with the guard against
    overlap;
  - `elastic` and `hybrid`: as `fixed`, plus the measured group
    positions.
- **Columns, not lengths:** the writer writes column numbers. The
  template turns them into lengths with `code-column` and `code-gap`
  (decision 32).
- It is plain data in and out, tested without groff or ConTeXt.

### 12.4 The writers

**mono** needs no alignment: a monospaced font keeps the columns. It
stays as §4 has it:

- ms: `\f[CR]`, with `\f[CB]` for bold; this needs the `\f[C]` fix
  first (Q6);
- mom: `.QUOTE`/`.CODE`, with `\*[BD]`;
- ConTeXt: `\starttyping[escape=yes]`, with `/BTEX\bf .../ETEX`.

**proportional**, with vgrind's lessons:

- **ms:**
  - `.nf` in the text font: bold `\f[B]`, comments `\f[I]`, back to
    `\f[R]`;
  - indentation `\h'|N*\n[PdCodeCol]u'`;
  - `fixed`: `\h'(N*\n[PdCodeCol]u-\n[.k]u)>?\n[PdCodeGap]u'`;
  - `hybrid`: measuring lines before the block,
    `.nr PdGn \n[PdGn]>?(\w'prefix'u+\n[PdCodeGap]u)`, then
    `\h'|\n[PdGn]u'` before the segment;
  - the group registers are reset at each block.
- **mom:**
  - the same escapes, inside `.QUOTE` without `.CODE`, at the margin
    by default (`code-indent`, decision 34);
  - `.QUOTE` is italic by default, so the block needs a roman font:
    `.QUOTE_FONT R` before it is the proposed answer to Q7;
  - mom makes `"` into curly quotes, so the writer writes `\[dq]`
    (vgrind.md §8.4).
- **ConTeXt:**
  - `\startlines[space=on]`, each line
    `\PdLine\PdSeg{pos}{text}...`;
  - `hybrid`: `\setvalue{PdGn}{...}` and one `\PdMeasure` per line
    before the block;
  - the text goes through the normal ConTeXt escaping, since it is
    not verbatim;
  - `-` is written `-\kern0pt`, against ligatures;
  - fonts are reopened in each segment;
  - the three macros of vgrind.md §8.2 go in the template.

**Inline code** gets bold and italic only. Alignment means nothing
inside a line of running text (Q2).

### 12.5 Templates unchanged unless used

Decision 32's lines and the ConTeXt macros are needed only when a
document uses the proportional style with alignment. `default.ms`
and `default.context` are pandoc's templates, so the new lines go
inside `$if(...)$`, on a variable the writer sets when it needs them.
With the style `none`, podoc's output stays byte for byte as it is,
and the case tests and `make compare` are unaffected.

### 12.6 Phases and size

§8's phases, with layout added; they are PLAN.md's Phase 24:

1. `PdCode`, with comments as spans, for Oberon-2, Modula-2 and C;
   `PdCodeTest`.
2. The ms `\f[CR]` fix, as a change of its own.
3. The writers in both styles, behind the style option, with
   alignment `none`.
4. `PdCodeAlign` and its tests; `fixed` in the three writers, then
   `elastic` and `hybrid`; the template variables and the ConTeXt
   macros. This first checks decision 32's template lines.
5. Pascal with its modes, Ada, C++.
6. sh and bash.
7. Users' lists of reserved words.
8. Documentation (podoc.md, differences.md) and the BSD tests.

Step 4 adds about 400 to 600 lines to §8's estimate: about 2,000 to
2,900 lines in all.

### 12.7 Questions before coding

Q1 to Q11 are all decided (2026-11-22, PLAN.md decisions 35 to 45). Phases 24.1 to 24.3 need Q1 (the style option), Q6 (the
ms fix) and Q7 (mom's roman), all decided. Integrating
vgrind raises three more:

- **Q9. Proportional code with no known language.** Is it still set
  in the text font, and aligned, without bold? vgrind.md §8.3 found
  that alignment helps with highlighting off.
  *Decided 2026-11-22: yes* (decision 42).
- **Q10. Comments in mono.** Does mono set comments in italic too?
  Decision 30 covers only the proportional style.
  *Decided 2026-11-22: yes* (decision 43).
- **Q11. Runs of spaces in strings.** Does a run of two or more
  spaces inside a string literal start a segment, as it does
  elsewhere?
  *Decided 2026-11-22: no, strings are left whole* (decision 44).
