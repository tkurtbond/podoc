MODULE PdConTeXt;
(* PdConTeXt: the ConTeXt writer, as pandoc 3.10's ConTeXt writer
   (Text.Pandoc.Writers.ConTeXt) writes ConTeXt with its default
   extensions (smart, so dashes and apostrophes become ligatures; no
   tagging; xtables), without syntax highlighting and with --wrap=none.

   The output is built as a PdLayout Doc, as pandoc builds it. The
   writer's state (the next URL reference, the ordered list level, CSL
   references) changes as pandoc's does, in the same order: the
   metadata first, then the body. *)

IMPORT Ropes, A := PdAst, L := PdLayout, T := PdTemplate, C := PdContext,
  Sh := PdShared, PdWords, PdIO;

TYPE
  Rope = Ropes.Rope;
  Buf = PdIO.Text;

VAR
  (* options *)
  numberSections, preserve, wantToc: BOOLEAN;
  tocDepth: INTEGER;

  (* the writer's state *)
  nextRef: LONGINT; (* the number of the next \useURL *)
  listLevel: INTEGER; (* the depth of ordered lists *)
  cslRefs, cslHanging: BOOLEAN;

(* Ropes *)

PROCEDURE R(s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.FromString(s)
END R;

PROCEDURE Cat(a, b: Rope): Rope;
BEGIN
  RETURN Ropes.Cat(a, b)
END Cat;

PROCEDURE CatS(a: Rope; s: ARRAY OF CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(a, Ropes.FromString(s))
END CatS;

PROCEDURE CatC(a: Rope; ch: CHAR): Rope;
BEGIN
  RETURN Ropes.Cat(a, Ropes.FromChar(ch))
END CatC;

PROCEDURE Len(r: Rope): LONGINT;
BEGIN
  RETURN Ropes.Length(r)
END Len;

PROCEDURE Eq(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN Ropes.EqualString(r, s)
END Eq;

(* The text of r in a new buffer, 0X after it *)
PROCEDURE ToBuf(r: Rope): Buf;
  VAR b: Buf; n: LONGINT;
BEGIN
  n := Len(r); NEW(b, n + 1);
  IF n > 0 THEN Ropes.Blit(r, 0, b^, 0, n) END;
  b[n] := 0X;
  RETURN b
END ToBuf;

PROCEDURE HexDigit(v: LONGINT): CHAR;
BEGIN
  IF v < 10 THEN RETURN CHR(ORD("0") + v) END;
  RETURN CHR(ORD("a") + v - 10)
END HexDigit;

PROCEDURE HexValue(ch: CHAR): INTEGER;
BEGIN
  IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch) - ORD("0")
  ELSIF (ch >= "a") & (ch <= "f") THEN RETURN ORD(ch) - ORD("a") + 10
  ELSIF (ch >= "A") & (ch <= "F") THEN RETURN ORD(ch) - ORD("A") + 10
  END;
  RETURN -1
END HexValue;

(* Docs *)

PROCEDURE Lit(s: ARRAY OF CHAR): L.Doc;
BEGIN
  RETURN L.Text(s)
END Lit;

PROCEDURE Above(a, b: L.Doc): L.Doc;
BEGIN
  RETURN L.Above(a, b)
END Above;

PROCEDURE Above3(a, b, c: L.Doc): L.Doc;
BEGIN
  RETURN L.Above(L.Above(a, b), c)
END Above3;

PROCEDURE Braces(d: L.Doc): L.Doc;
BEGIN
  RETURN L.Cat3(L.Char("{"), d, L.Char("}"))
END Braces;

PROCEDURE Brackets(d: L.Doc): L.Doc;
BEGIN
  RETURN L.Cat3(L.Char("["), d, L.Char("]"))
END Brackets;

(* a, then "," and b if a is not empty, or b *)
PROCEDURE Comma(a, b: L.Doc): L.Doc;
BEGIN
  IF L.IsEmpty(b) THEN RETURN a
  ELSIF L.IsEmpty(a) THEN RETURN b
  END;
  RETURN L.Cat3(a, L.Char(","), b)
END Comma;

(* Escapes *)

(* stringToConTeXt, with ligatures *)
PROCEDURE Escape(r: Rope): Rope;
  VAR b: Buf; n, i, start: LONGINT; out: Rope; ch: CHAR; rep: ARRAY 24 OF CHAR; k: INTEGER;
BEGIN
  n := Len(r); b := ToBuf(r); out := NIL; start := 0; i := 0;
  WHILE i < n DO
    ch := b[i]; rep[0] := 0X; k := 1;
    CASE ch OF
      "{": rep := "\{"
    | "}": rep := "\}"
    | "\": rep := "\letterbackslash{}"
    | "$": rep := "\$"
    | "|": rep := "\letterbar{}"
    | "%": rep := "\letterpercent{}"
    | "~": rep := "\lettertilde{}"
    | "#": rep := "\#"
    | "[": rep := "{[}"
    | "]": rep := "{]}"
    | 0C2X: IF b[i + 1] = 0A0X THEN rep := "~"; k := 2 END
    | 0E2X:
      IF b[i + 1] = 80X THEN
        CASE b[i + 2] OF
          94X: rep := "---"; k := 3
        | 93X: rep := "--"; k := 3
        | 99X: rep := "'"; k := 3
        | 0A6X: rep := "\ldots{}"; k := 3
        ELSE
        END
      END
    ELSE
    END;
    IF rep[0] # 0X THEN
      IF i > start THEN out := Cat(out, Ropes.FromSubchars(b^, start, i - start)) END;
      out := CatS(out, rep);
      INC(i, k); start := i
    ELSE INC(i)
    END
  END;
  IF start = 0 THEN RETURN r END;
  IF n > start THEN out := Cat(out, Ropes.FromSubchars(b^, start, n - start)) END;
  RETURN out
END Escape;

(* toLabel *)
PROCEDURE ToLabel(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; out: Rope; ch: CHAR;
BEGIN
  n := Len(r); b := ToBuf(r); out := NIL;
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    CASE ch OF
      "\", "#", "[", "]", 22X, ",", "{", "}", "%", "(", ")", "|", "=":
      out := CatC(CatC(CatS(out, "ux"), HexDigit(ORD(ch) DIV 16)), HexDigit(ORD(ch) MOD 16))
    ELSE out := CatC(out, ch)
    END
  END;
  RETURN out
END ToLabel;

(* A URL with # and % escaped (escConTeXtURL) *)
PROCEDURE EscUrl(r: Rope): Rope;
  VAR n, i: LONGINT; out: Rope; ch: CHAR;
BEGIN
  n := Len(r); out := NIL;
  FOR i := 0 TO n - 1 DO
    ch := Ropes.Fetch(r, i);
    IF (ch = "#") OR (ch = "%") THEN out := CatC(out, "\") END;
    out := CatC(out, ch)
  END;
  RETURN out
END EscUrl;

(* unEscapeString: r with each %XX decoded *)
PROCEDURE UnEscape(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; out: Rope; h1, h2: INTEGER;
BEGIN
  n := Len(r); b := ToBuf(r); out := NIL; i := 0;
  WHILE i < n DO
    IF b[i] = "%" THEN h1 := HexValue(b[i + 1]); IF h1 >= 0 THEN h2 := HexValue(b[i + 2]) END
    ELSE h1 := -1
    END;
    IF (h1 >= 0) & (h2 >= 0) THEN out := CatC(out, CHR(h1 * 16 + h2)); INC(i, 3)
    ELSE out := CatC(out, b[i]); INC(i)
    END
  END;
  RETURN out
END UnEscape;

(* isURI: whether r starts with a known scheme and a colon *)
PROCEDURE IsUri(r: Rope): BOOLEAN;
  VAR b: Buf; n, k: LONGINT;
BEGIN
  n := Len(r); b := ToBuf(r); k := 0;
  WHILE (k < n) & (b[k] # ":") DO INC(k) END;
  RETURN (k > 0) & (k < n) & (PdWords.Scheme(b, 0) = k)
END IsUri;

(* Inlines *)

PROCEDURE^ Inlines(i: A.Inline): L.Doc;
PROCEDURE^ Blocks(b: A.Block): L.Doc;

(* Whether i is a Space or a Str that starts with a no-break space *)
PROCEDURE Spacey(i: A.Inline): BOOLEAN;
  VAR s: Rope;
BEGIN
  IF i = NIL THEN RETURN FALSE
  ELSIF i.kind = A.Space THEN RETURN TRUE
  ELSIF i.kind = A.Str THEN
    s := i(A.StrInl).text;
    RETURN (Len(s) >= 2) & (Ropes.Fetch(s, 0) = 0C2X) & (Ropes.Fetch(s, 1) = 0A0X)
  END;
  RETURN FALSE
END Spacey;

(* typeDelim: the first delimiter character not in s; 0X if none is
   left. "}" in s counts as "{" *)
PROCEDURE TypeDelim(s: Rope): CHAR;
  VAR delims: ARRAY 16 OF CHAR; n, i, k: LONGINT; ch: CHAR;
BEGIN
  delims := "{x'`()-+=%,.:;"; delims[1] := 22X;
  n := Len(s);
  FOR i := 0 TO n - 1 DO
    ch := Ropes.Fetch(s, i);
    IF ch = "}" THEN ch := "{" END;
    k := 0;
    WHILE (delims[k] # 0X) & (delims[k] # ch) DO INC(k) END;
    WHILE delims[k] # 0X DO delims[k] := delims[k + 1]; INC(k) END
  END;
  RETURN delims[0]
END TypeDelim;

PROCEDURE Code(s: Rope): L.Doc;
  VAR ch: CHAR; r: Rope; n, i: LONGINT; c: CHAR;
BEGIN
  ch := TypeDelim(s);
  IF ch = "{" THEN r := CatC(Cat(R("\type{"), s), "}")
  ELSIF ch # 0X THEN r := CatC(Cat(CatC(R("\type"), ch), s), ch)
  ELSE
    r := R("\type[escape=yes]{"); n := Len(s);
    FOR i := 0 TO n - 1 DO
      c := Ropes.Fetch(s, i);
      IF c = "{" THEN r := CatS(r, "/BTEX\letteropenbrace /ETEX")
      ELSIF c = "}" THEN r := CatS(r, "/BTEX\letterclosebrace /ETEX")
      ELSE r := CatC(r, c)
      END
    END;
    r := CatC(r, "}")
  END;
  RETURN L.Literal(r)
END Code;

(* A dimension of an image, as the writer's showDim shows it; NIL if
   the attribute name is not there or is not a dimension *)
PROCEDURE Dim(attr: A.Attr; name: ARRAY OF CHAR): L.Doc;
  VAR found: BOOLEAN; v, int, frac, unit, s: Rope; px, q, rem: LONGINT; n, i: LONGINT;
    digits: ARRAY 8 OF CHAR;
BEGIN
  v := A.GetKeyVal(attr, name, found);
  IF ~found OR ~Sh.NumUnit(v, int, frac, unit) THEN RETURN NIL END;
  IF (Len(unit) = 0) OR Eq(unit, "px") THEN
    (* showInInch: px / 96, to 5 decimals *)
    int := Sh.StripZeros(int);
    IF Len(int) > 9 THEN RETURN NIL END;
    px := 0; n := Len(int);
    FOR i := 0 TO n - 1 DO px := px * 10 + ORD(Ropes.Fetch(int, i)) - ORD("0") END;
    q := px DIV 96; rem := px MOD 96;
    FOR i := 0 TO 5 DO rem := rem * 10; digits[i] := CHR(ORD("0") + rem DIV 96); rem := rem MOD 96 END;
    digits[6] := 0X;
    s := Sh.ShowFl(Sh.IntRope(q), R(digits));
    s := CatS(s, "in")
  ELSIF Eq(unit, "%") THEN
    (* showFl (a / 100) *)
    n := Len(int);
    IF n > 2 THEN s := Ropes.Substring(int, 0, n - 2); frac := Cat(Ropes.Substring(int, n - 2, 2), frac)
    ELSE
      s := R("0");
      IF n = 1 THEN frac := Cat(Cat(R("0"), int), frac) ELSE frac := Cat(int, frac) END
    END;
    s := CatS(Sh.ShowFl(s, frac), "\textwidth")
  ELSIF Eq(unit, "inch") THEN s := CatS(Sh.ShowFl(int, frac), "in")
  ELSIF Eq(unit, "cm") OR Eq(unit, "mm") OR Eq(unit, "in")
     OR Eq(unit, "pt") OR Eq(unit, "pc") OR Eq(unit, "em") THEN
    s := Cat(Sh.ShowFl(int, frac), unit)
  ELSE RETURN NIL
  END;
  RETURN L.Literal(Cat(CatS(R(name), "="), s))
END Dim;

PROCEDURE Image(i: A.LinkInl): L.Doc;
  VAR src: Rope; n, k: LONGINT; b: Buf; d, dims: L.Doc;
BEGIN
  src := i.url;
  IF ~IsUri(src) THEN src := UnEscape(src) END;
  b := ToBuf(src); n := Len(src);
  FOR k := 0 TO n - 1 DO IF b[k] = "\" THEN b[k] := "/" END END;
  src := Ropes.FromSubchars(b^, 0, n);
  d := L.Cat(Lit("\externalfigure"), Brackets(L.Literal(src)));
  IF (i.attr # NIL) & (i.attr.classes # NIL) THEN
    d := L.Cat(d, Brackets(L.Literal(ToLabel(i.attr.classes.s))))
  END;
  dims := Comma(Dim(i.attr, "width"), Dim(i.attr, "height"));
  IF ~L.IsEmpty(dims) THEN d := L.Cat(d, Brackets(dims)) END;
  RETURN Braces(d)
END Image;

PROCEDURE Link(i: A.LinkInl): L.Doc;
  VAR c: A.Inline; ref, src: Rope; contents: L.Doc;
BEGIN
  c := i.content; src := i.url;
  IF (c # NIL) & (c.next = NIL) & (c.kind = A.Str)
     & Ropes.Equal(c(A.StrInl).text, UnEscape(src)) THEN
    ref := Cat(R("url"), Sh.IntRope(nextRef)); INC(nextRef);
    src := Cat(CatS(Cat(R("\useURL["), ref), "]["), EscUrl(src));
    src := CatS(Cat(CatS(src, "]\from["), ref), "]");
    RETURN L.Literal(src)
  END;
  contents := Inlines(c);
  IF (Len(src) > 0) & (Ropes.Fetch(src, 0) = "#") THEN
    ref := ToLabel(Escape(Ropes.Substring(src, 1, Len(src) - 1)))
  ELSE ref := CatC(Cat(R("url("), EscUrl(src)), ")")
  END;
  RETURN L.Cat3(Lit("\goto"), Braces(contents), Brackets(L.Literal(ref)))
END Link;

(* Whether the blocks b hold a block of the kind k, at any depth *)
PROCEDURE HasBlock(b: A.Block; k: INTEGER): BOOLEAN;
  VAR it: A.BlockList; di: A.DefItem; t: A.TableBlk; row: A.Row; c: A.Cell; tb: A.TableBody;
    pass: INTEGER;
BEGIN
  WHILE b # NIL DO
    IF b.kind = k THEN RETURN TRUE END;
    CASE b.kind OF
      A.BlockQuote, A.Div, A.Figure:
      IF HasBlock(b(A.BlocksBlk).blocks, k) THEN RETURN TRUE END
    | A.OrderedList, A.BulletList:
      it := b(A.ListBlk).items;
      WHILE it # NIL DO
        IF HasBlock(it.blocks, k) THEN RETURN TRUE END;
        it := it.next
      END
    | A.DefinitionList:
      di := b(A.DefListBlk).items;
      WHILE di # NIL DO
        it := di.defs;
        WHILE it # NIL DO
          IF HasBlock(it.blocks, k) THEN RETURN TRUE END;
          it := it.next
        END;
        di := di.next
      END
    | A.Table:
      t := b(A.TableBlk); row := t.head.rows; tb := t.bodies; pass := 0;
      LOOP
        WHILE row # NIL DO
          c := row.cells;
          WHILE c # NIL DO
            IF HasBlock(c.blocks, k) THEN RETURN TRUE END;
            c := c.next
          END;
          row := row.next
        END;
        IF pass = 1 THEN row := tb.body; pass := 2; tb := tb.next
        ELSIF tb # NIL THEN row := tb.head; pass := 1
        ELSIF pass # 3 THEN row := t.foot.rows; pass := 3
        ELSE EXIT
        END
      END
    ELSE
    END;
    b := b.next
  END;
  RETURN FALSE
END HasBlock;

PROCEDURE Note(bs: A.Block): L.Doc;
  VAR contents: L.Doc;
BEGIN
  contents := Blocks(bs);
  contents := L.Nest(2, L.Chomp(contents));
  IF HasBlock(bs, A.CodeBlock) THEN
    RETURN L.Cat3(Lit("\startbuffer "), contents, Lit("\stopbuffer\footnote{\getbuffer}"))
  END;
  RETURN L.Cat3(Lit("\footnote{"), contents, L.Char("}"))
END Note;

(* fromBCP47 of the language tag s; NIL if there is none *)
PROCEDURE FromBCP47(s: Rope): Rope;
  VAR b: Buf; n, i, k, start: LONGINT; lang, region, script: Rope; variants: ARRAY 4 OF Rope;
    nv: INTEGER; part: Rope; ch: CHAR;
BEGIN
  n := Len(s);
  IF n = 0 THEN RETURN NIL END;
  b := ToBuf(s); i := 0; k := 0; lang := NIL; region := NIL; script := NIL; nv := 0;
  WHILE i <= n DO
    start := i;
    WHILE (i < n) & (b[i] # "-") & (b[i] # "_") DO INC(i) END;
    part := NIL;
    FOR start := start TO i - 1 DO
      ch := b[start];
      IF (ch >= "A") & (ch <= "Z") THEN ch := CHR(ORD(ch) + 32) END;
      part := CatC(part, ch)
    END;
    IF k = 0 THEN lang := part
    ELSIF (Len(part) = 4) & (script = NIL) & (region = NIL) & (nv = 0) THEN script := part
    ELSIF (Len(part) = 2) & (region = NIL) & (nv = 0) THEN region := part
    ELSIF nv < LEN(variants) THEN variants[nv] := part; INC(nv)
    END;
    INC(k); INC(i)
  END;
  IF Eq(lang, "ar") & (region # NIL) & (Eq(region, "sy") OR Eq(region, "iq") OR Eq(region, "jo")
     OR Eq(region, "lb") OR Eq(region, "dz") OR Eq(region, "ma")) THEN
    RETURN Cat(R("ar-"), region)
  ELSIF Eq(lang, "de") & (nv = 1) & Eq(variants[0], "1901") THEN RETURN R("deo")
  ELSIF Eq(lang, "de") & (region # NIL) & (Eq(region, "de") OR Eq(region, "at") OR Eq(region, "ch")) THEN
    RETURN Cat(R("de-"), region)
  ELSIF Eq(lang, "el") & (nv = 1) & Eq(variants[0], "poly") THEN RETURN R("agr")
  ELSIF Eq(lang, "en") & (region # NIL) & (Eq(region, "us") OR Eq(region, "gb")) THEN
    RETURN Cat(R("en-"), region)
  ELSIF Eq(lang, "grc") THEN RETURN R("agr")
  ELSIF Eq(lang, "el") THEN RETURN R("gr")
  ELSIF Eq(lang, "eu") THEN RETURN R("ba")
  ELSIF Eq(lang, "he") THEN RETURN R("il")
  ELSIF Eq(lang, "uk") THEN RETURN R("ua")
  ELSIF Eq(lang, "vi") THEN RETURN R("vn")
  ELSIF Eq(lang, "zh") THEN RETURN R("cn")
  END;
  RETURN lang
END FromBCP47;

PROCEDURE Span(i: A.SpanInl): L.Doc;
  VAR d: L.Doc; found: BOOLEAN; dir, lng: Rope;
BEGIN
  d := Inlines(i.content);
  dir := A.GetKeyVal(i.attr, "dir", found);
  IF found & Eq(dir, "rtl") THEN d := Braces(L.Cat(Lit("\righttoleft "), d))
  ELSIF found & Eq(dir, "ltr") THEN d := Braces(L.Cat(Lit("\lefttoright "), d))
  END;
  lng := A.GetKeyVal(i.attr, "lang", found);
  IF found THEN lng := FromBCP47(lng) END;
  IF lng # NIL THEN d := Braces(L.Cat3(Lit("\language"), Brackets(L.Literal(lng)), d)) END;
  IF (i.attr # NIL) & (Len(i.attr.id) > 0) THEN
    d := L.Cat(L.Literal(CatS(CatC(Cat(R("\reference["), i.attr.id), "]"), "{}")), d)
  END;
  RETURN d
END Span;

PROCEDURE Inline(i: A.Inline): L.Doc;
  VAR c: L.Doc; s: Rope;
BEGIN
  CASE i.kind OF
    A.Str: RETURN L.Literal(Escape(i(A.StrInl).text))
  | A.Emph: c := Inlines(i(A.ContInl).content); RETURN Braces(L.Cat3(Lit("\em"), L.Space(), c))
  | A.Strong: c := Inlines(i(A.ContInl).content); RETURN Braces(L.Cat3(Lit("\bf"), L.Space(), c))
  | A.SmallCaps:
    c := Inlines(i(A.ContInl).content); RETURN Braces(L.Cat3(Lit("\setsmallcaps"), L.Space(), c))
  | A.Underline: c := Inlines(i(A.ContInl).content); RETURN L.Cat(Lit("\underbar"), Braces(c))
  | A.Strikeout: c := Inlines(i(A.ContInl).content); RETURN L.Cat(Lit("\overstrikes"), Braces(c))
  | A.Superscript: c := Inlines(i(A.ContInl).content); RETURN L.Cat(Lit("\high"), Braces(c))
  | A.Subscript: c := Inlines(i(A.ContInl).content); RETURN L.Cat(Lit("\low"), Braces(c))
  | A.Code: RETURN Code(i(A.CodeInl).text)
  | A.Quoted:
    c := Inlines(i(A.ContInl).content);
    IF i(A.QuotedInl).quote = A.SingleQuote THEN RETURN L.Cat(Lit("\quote"), Braces(c)) END;
    RETURN L.Cat(Lit("\quotation"), Braces(c))
  | A.Cite: RETURN Inlines(i(A.ContInl).content)
  | A.Math:
    s := i(A.MathInl).text;
    IF i(A.MathInl).math = A.InlineMath THEN RETURN L.Cat3(L.Char("$"), L.Literal(s), L.Char("$")) END;
    RETURN L.Cat(L.Cat3(Lit("\startformula "), L.Literal(s), Lit(" \stopformula")), L.Space())
  | A.RawInline:
    s := i(A.RawInl).format;
    IF Eq(s, "tex") OR Eq(s, "context") THEN RETURN L.Literal(i(A.RawInl).text) END;
    RETURN NIL
  | A.LineBreak: RETURN L.Cat(Lit("\crlf"), L.Cr())
  | A.SoftBreak: IF preserve THEN RETURN L.Cr() END; RETURN L.Space()
  | A.Space: RETURN L.Space()
  | A.Link: RETURN Link(i(A.LinkInl))
  | A.Image: RETURN Image(i(A.LinkInl))
  | A.Note: RETURN Note(i(A.NoteInl).blocks)
  | A.Span: RETURN Span(i(A.SpanInl))
  END
END Inline;

(* inlineListToConTeXt: hcat, with a \strut after a line break before
   a space (addStruts) *)
PROCEDURE Inlines(i: A.Inline): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE i # NIL DO
    x := Inline(i); d := L.Cat(d, x);
    IF (i.kind = A.LineBreak) & Spacey(i.next) THEN d := L.Cat(d, Lit("\strut ")) END;
    i := i.next
  END;
  RETURN d
END Inlines;

(* Blocks *)

PROCEDURE^ Block(b: A.Block): L.Doc;

(* sectionLevelToText; NIL for "" *)
PROCEDURE LevelText(attr: A.Attr; level: INTEGER; section: BOOLEAN): L.Doc;
  VAR r: Rope; k: INTEGER;
BEGIN
  IF A.HasClass(attr, "unlisted") THEN
    IF level = 0 THEN RETURN Lit("title") END;
    r := NIL;
    FOR k := 2 TO level DO r := CatS(r, "sub") END;
    RETURN L.Literal(CatS(r, "subject"))
  ELSIF section THEN RETURN Lit("sectionlevel")
  END;
  RETURN NIL
END LevelText;

PROCEDURE SectionHeader(attr: A.Attr; level: INTEGER; title: A.Inline; section: BOOLEAN): L.Doc;
  VAR contents, opts, levelText, d: L.Doc;
BEGIN
  contents := Inlines(title);
  levelText := LevelText(attr, level, section);
  opts := NIL;
  IF ~L.IsEmpty(contents) THEN opts := L.Cat(Lit("title="), Braces(contents)) END;
  IF (attr # NIL) & (Len(attr.id) > 0) THEN
    opts := Comma(opts, L.Cat(Lit("reference="), Braces(L.Literal(ToLabel(attr.id)))))
  END;
  IF A.HasClass(attr, "unnumbered") THEN
    opts := Comma(opts, Lit("number=no")); opts := Comma(opts, Lit("incrementnumber=no"))
  END;
  IF section THEN d := Lit("\start") ELSE d := L.Char("\") END;
  d := L.Cat(d, levelText);
  IF ~L.IsEmpty(opts) & ~L.IsEmpty(levelText) THEN d := L.Cat(d, Brackets(opts)) END;
  RETURN L.Cat(d, L.BlankLine())
END SectionHeader;

PROCEDURE LineBlock(l: A.InlineList): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE l # NIL DO
    x := Inlines(l.inlines);
    IF L.IsEmpty(x) THEN x := L.BlankLine() END;
    d := Above(d, x); l := l.next
  END;
  RETURN Above3(Lit("\startlines"), d, L.Cat(Lit("\stoplines"), L.BlankLine()))
END LineBlock;

PROCEDURE DivDoc(d: A.DivBlk): L.Doc;
  VAR attr: A.Attr; txt: L.Doc; found: BOOLEAN; v, lng: Rope; b: A.Block;
BEGIN
  attr := d.attr; b := d.blocks;
  IF (attr # NIL) & (attr.classes # NIL) & Eq(attr.classes.s, "section")
     & (b # NIL) & (b.kind = A.Header) THEN
    txt := SectionHeader(attr, b(A.HeaderBlk).level, b(A.HeaderBlk).inlines, TRUE);
    txt := Above(txt, Blocks(b.next));
    RETURN Above(txt, L.Cat3(Lit("\stop"), LevelText(attr, b(A.HeaderBlk).level, TRUE), L.BlankLine()))
  END;
  IF (attr # NIL) & Eq(attr.id, "refs") THEN
    cslRefs := TRUE; cslHanging := A.HasClass(attr, "hanging-indent");
    txt := Blocks(b);
    RETURN Above3(Lit("\startcslreferences"), txt, Lit("\stopcslreferences"))
  END;
  txt := Blocks(b);
  IF (attr # NIL) & (Len(attr.id) > 0) THEN
    txt := Above(L.Literal(CatS(CatC(Cat(R("\reference["), ToLabel(attr.id)), "]"), "{}%")), txt)
  END;
  v := A.GetKeyVal(attr, "dir", found);
  IF found & Eq(v, "rtl") THEN txt := Above3(Lit("\startalignment[righttoleft]"), txt, Lit("\stopalignment"))
  ELSIF found & Eq(v, "ltr") THEN txt := Above3(Lit("\startalignment[lefttoright]"), txt, Lit("\stopalignment"))
  END;
  lng := A.GetKeyVal(attr, "lang", found);
  IF found THEN lng := FromBCP47(lng) END;
  IF lng # NIL THEN
    txt := Above3(L.Literal(CatC(Cat(R("\start\language["), lng), "]")), txt, Lit("\stop"))
  END;
  RETURN L.Cat3(L.BlankLine(), txt, L.BlankLine())
END DivDoc;

PROCEDURE Items(it: A.BlockList): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE it # NIL DO
    x := Blocks(it.blocks);
    d := Above(d, Above(Lit("\item"), L.Nest(2, x)));
    it := it.next
  END;
  RETURN d
END Items;

PROCEDURE BulletList(l: A.ListBlk): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  x := Items(l.items);
  d := Lit("\startitemize");
  IF Sh.IsTightList(l.items) THEN d := L.Cat(d, Lit("[packed]")) END;
  RETURN Above3(d, x, L.Cat(Lit("\stopitemize"), L.BlankLine()))
END BulletList;

PROCEDURE OrderedList(l: A.OrderedBlk): L.Doc;
  VAR level: INTEGER; x: L.Doc; s, specs2: Rope; styles: ARRAY 5 OF CHAR;
BEGIN
  level := listLevel; INC(listLevel);
  x := Items(l.items);
  listLevel := level;
  IF l.start # 1 THEN specs2 := Cat(R("start="), Sh.IntRope(l.start)) ELSE specs2 := NIL END;
  s := NIL;
  CASE l.delim OF
    A.Period: s := R("stopper=.")
  | A.OneParen: s := R("stopper=)")
  | A.TwoParens: s := R("left=(,stopper=)")
  ELSE
  END;
  IF (specs2 # NIL) & (s # NIL) THEN specs2 := Cat(CatC(specs2, ","), s)
  ELSIF s # NIL THEN specs2 := s
  END;
  IF specs2 # NIL THEN specs2 := CatC(Cat(R("["), specs2), "]") END;
  styles := "narg";
  CASE l.style OF
    A.DefaultStyle: s := Ropes.FromChar(styles[level MOD 4])
  | A.Decimal, A.Example: s := R("n")
  | A.LowerRoman: s := R("r")
  | A.UpperRoman: s := R("R")
  | A.LowerAlpha: s := R("a")
  | A.UpperAlpha: s := R("A")
  END;
  s := Cat(R("\startenumerate["), s);
  IF Sh.IsTightList(l.items) THEN s := CatS(s, ",packed]") ELSE s := CatS(s, "]") END;
  RETURN Above3(L.Literal(Cat(s, specs2)), x, L.Cat(Lit("\stopenumerate"), L.BlankLine()))
END OrderedList;

PROCEDURE DefList(l: A.DefListBlk): L.Doc;
  VAR it: A.DefItem; def: A.BlockList; term, defs, x, d: L.Doc;
BEGIN
  d := NIL; it := l.items;
  WHILE it # NIL DO
    term := Inlines(it.term);
    defs := NIL; def := it.defs;
    WHILE def # NIL DO x := Blocks(def.blocks); defs := L.AboveBlank(defs, x); def := def.next END;
    x := Above3(L.Cat(Lit("\startdescription"), Braces(term)), L.Nest(2, defs),
      L.Cat(Lit("\stopdescription"), L.BlankLine()));
    d := Above(d, x);
    it := it.next
  END;
  RETURN d
END DefList;

PROCEDURE Figure(f: A.FigureBlk): L.Doc;
  VAR il: A.Inlines; title, list, content, opts, d: L.Doc; sub: BOOLEAN;
BEGIN
  A.InitInlines(il);
  Sh.BlocksToInlines(il, f.caption.blocks);
  title := Inlines(il.first);
  IF f.caption.hasShort THEN list := Inlines(f.caption.short) ELSE list := NIL END;
  content := Blocks(f.blocks);
  opts := NIL;
  IF (f.attr # NIL) & (Len(f.attr.id) > 0) THEN
    opts := L.Literal(Cat(R("reference="), ToLabel(f.attr.id)))
  END;
  IF ~L.IsEmpty(title) THEN opts := Comma(opts, L.Cat(Lit("title="), Braces(title))) END;
  IF ~L.IsEmpty(list) THEN opts := Comma(opts, L.Cat(Lit("list="), Braces(list))) END;
  sub := HasBlock(f.blocks, A.Figure);
  d := L.Cat(Lit("\startplacefigure"), Brackets(opts));
  IF sub THEN d := Above(d, Lit("\startfloatcombination")) END;
  d := Above(d, content);
  IF sub THEN d := Above(d, Lit("\stopfloatcombination")) END;
  RETURN Above3(d, Lit("\stopplacefigure"), L.BlankLine())
END Figure;

(* Tables, as Ann.toTable lays them out *)

PROCEDURE Cell(c: A.Cell; cs: A.ColSpec; w: LONGINT): L.Doc;
  VAR keys, contents: L.Doc; align: INTEGER; k: LONGINT; sum: LONGREAL; any: BOOLEAN;
    s: A.ColSpec;
BEGIN
  align := c.align;
  IF align = A.AlignDefault THEN align := cs.align END;
  CASE align OF
    A.AlignLeft: keys := Lit("align=right")
  | A.AlignRight: keys := Lit("align=left")
  | A.AlignCenter: keys := Lit("align=middle")
  ELSE keys := NIL
  END;
  sum := 0; any := FALSE; s := cs;
  FOR k := 1 TO w DO
    IF s.hasWidth THEN sum := sum + s.width; any := TRUE END;
    s := s.next
  END;
  IF any THEN
    keys := Comma(keys, L.Literal(CatS(Cat(R("width={"), Sh.Fixed(sum, 2)), "\textwidth}")))
  END;
  IF w # 1 THEN keys := Comma(keys, L.Literal(Cat(R("nc="), Sh.IntRope(w)))) END;
  IF c.rowSpan # 1 THEN keys := Comma(keys, L.Literal(Cat(R("nr="), Sh.IntRope(c.rowSpan)))) END;
  IF ~L.IsEmpty(keys) THEN keys := Brackets(keys) END;
  keys := L.Cat(keys, L.Space());
  contents := Blocks(c.blocks);
  RETURN L.Cat3(Lit("\startxcell"), keys, L.Cat(contents, Lit(" \stopxcell")))
END Cell;

(* The rows, one section of a table: each \startxrow ... \stopxrow,
   the last in a row group *)
PROCEDURE Rows(row: A.Row; t: A.TableBlk): L.Doc;
  VAR hang: POINTER TO ARRAY OF LONGINT; specs: POINTER TO ARRAY OF A.ColSpec;
    n, col, w, k, h: LONGINT; cs: A.ColSpec; c, empty: A.Cell; cells, x, d, last: L.Doc;
BEGIN
  n := 0; cs := t.colSpecs;
  WHILE cs # NIL DO INC(n); cs := cs.next END;
  NEW(hang, n + 1); NEW(specs, n + 1);
  cs := t.colSpecs;
  FOR k := 0 TO n - 1 DO hang[k] := 1; specs[k] := cs; cs := cs.next END;
  NEW(empty); empty.attr := NIL; empty.align := A.AlignDefault; empty.rowSpan := 1;
  empty.colSpan := 1; empty.blocks := NIL; empty.next := NIL;
  d := NIL; last := NIL;
  WHILE row # NIL DO
    cells := NIL; c := row.cells; col := 0;
    LOOP
      WHILE (col < n) & (hang[col] > 1) DO DEC(hang[col]); INC(col) END;
      IF col >= n THEN EXIT END;
      IF c = NIL THEN c := empty END;
      w := c.colSpan; IF w < 1 THEN w := 1 END;
      k := 0;
      WHILE (k < w) & (col + k < n) & (hang[col + k] = 1) DO INC(k) END;
      w := k;
      h := c.rowSpan; IF h < 1 THEN h := 1 END;
      FOR k := col TO col + w - 1 DO hang[k] := h END;
      x := Cell(c, specs[col], w);
      cells := Above(cells, x);
      INC(col, w);
      IF c # empty THEN c := c.next END
    END;
    d := Above(d, last);
    last := Above3(Lit("\startxrow"), cells, Lit("\stopxrow"));
    row := row.next
  END;
  IF ~L.IsEmpty(last) THEN
    d := Above(d, Above3(Lit("\startxrowgroup[lastrow]"), last, Lit("\stopxrowgroup")))
  END;
  RETURN d
END Rows;

PROCEDURE Table(t: A.TableBlk): L.Doc;
  VAR caption, head, bodies, foot, x, y, body, opts: L.Doc; tb: A.TableBody;
BEGIN
  IF t.caption.blocks = NIL THEN caption := NIL ELSE caption := Blocks(t.caption.blocks) END;
  x := Rows(t.head.rows, t);
  head := Above3(Lit("\startxtablehead[head]"), x, Lit("\stopxtablehead"));
  bodies := NIL; tb := t.bodies;
  WHILE tb # NIL DO
    x := Rows(tb.head, t); y := Rows(tb.body, t);
    bodies := Above(bodies, L.Cat(x, y));
    tb := tb.next
  END;
  x := Rows(t.foot.rows, t);
  foot := Above3(Lit("\startxtablefoot[foot]"), x, Lit("\stopxtablefoot"));
  body := Above3(Lit("\startxtable"), head, Lit("\startxtablebody[body]"));
  body := Above3(body, bodies, Lit("\stopxtablebody"));
  body := Above3(body, foot, Lit("\stopxtable"));
  IF L.IsEmpty(caption) THEN opts := Lit("location=none")
  ELSE opts := L.Cat(Lit("title="), Braces(caption))
  END;
  IF (t.attr # NIL) & (Len(t.attr.id) > 0) THEN
    opts := Comma(opts, L.Cat(Lit("reference="), Braces(L.Literal(ToLabel(t.attr.id)))))
  END;
  RETURN Above3(L.Cat(Lit("\startplacetable"), Brackets(opts)), body,
    L.Cat(Lit("\stopplacetable"), L.BlankLine()))
END Table;

PROCEDURE Block(b: A.Block): L.Doc;
  VAR d: L.Doc; s: Rope;
BEGIN
  CASE b.kind OF
    A.Plain: RETURN Inlines(b(A.InlinesBlk).inlines)
  | A.Para: d := Inlines(b(A.InlinesBlk).inlines); RETURN L.Cat(d, L.BlankLine())
  | A.LineBlock: RETURN LineBlock(b(A.LineBlk).lines)
  | A.CodeBlock:
    d := Above3(Lit("\starttyping"), L.Literal(b(A.CodeBlk).text), Lit("\stoptyping"));
    RETURN Above(L.Flush(d), L.BlankLine())
  | A.RawBlock:
    s := b(A.RawBlk).format;
    IF Eq(s, "context") OR Eq(s, "tex") THEN RETURN L.Cat(L.Literal(b(A.RawBlk).text), L.BlankLine()) END;
    RETURN NIL
  | A.BlockQuote:
    d := Blocks(b(A.BlocksBlk).blocks);
    RETURN Above3(Lit("\startblockquote"), L.Nest(0, d), L.Cat(Lit("\stopblockquote"), L.BlankLine()))
  | A.OrderedList: RETURN OrderedList(b(A.OrderedBlk))
  | A.BulletList: RETURN BulletList(b(A.ListBlk))
  | A.DefinitionList: RETURN DefList(b(A.DefListBlk))
  | A.Header:
    RETURN SectionHeader(b(A.HeaderBlk).attr, b(A.HeaderBlk).level, b(A.HeaderBlk).inlines, FALSE)
  | A.HorizontalRule: RETURN L.Cat(Lit("\thinrule"), L.BlankLine())
  | A.Table: RETURN Table(b(A.TableBlk))
  | A.Figure: RETURN Figure(b(A.FigureBlk))
  | A.Div: RETURN DivDoc(b(A.DivBlk))
  END
END Block;

(* blockListToConTeXt: vcat *)
PROCEDURE Blocks(b: A.Block): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE b # NIL DO x := Block(b); d := Above(d, x); b := b.next END;
  RETURN d
END Blocks;

(* The writer *)

(* The blocks b as ConTeXt, for the template's metadata *)
PROCEDURE BlockDoc*(b: A.Block): L.Doc;
BEGIN
  RETURN Blocks(b)
END BlockDoc;

(* The inlines i as ConTeXt, for the template's metadata *)
PROCEDURE InlineDoc*(i: A.Inline): L.Doc;
BEGIN
  RETURN L.Chomp(Inlines(i))
END InlineDoc;

(* Sets the writer's options: whether sections are numbered (-N),
   whether soft breaks are kept as new lines (--wrap=preserve), and
   whether there is a table of contents (--toc) and its depth *)
PROCEDURE SetOptions*(number, preserveBreaks, toc: BOOLEAN; depth: INTEGER);
BEGIN
  numberSections := number; preserve := preserveBreaks; wantToc := toc; tocDepth := depth
END SetOptions;

(* The text of the simple value of key in ctx; found FALSE if it is
   not there or not simple *)
PROCEDURE Field(ctx: T.Value; key: ARRAY OF CHAR; VAR found: BOOLEAN): Rope;
  VAR v: T.Value;
BEGIN
  v := T.Get(ctx, key);
  found := (v # NIL) & (v.kind = T.SimpleV);
  IF found THEN RETURN L.Render(v.doc, 0) END;
  RETURN NIL
END Field;

(* The layout from the margins (layoutFromMargins) *)
PROCEDURE Layout(ctx: T.Value): L.Doc;
  VAR d: L.Doc;

  PROCEDURE Add(name, key: ARRAY OF CHAR);
    VAR v: T.Value;
  BEGIN
    v := T.Get(ctx, key);
    IF (v # NIL) & (v.kind = T.SimpleV) THEN
      IF d # NIL THEN d := L.Cat(d, L.Char(",")) END;
      d := L.Cat3(d, Lit(name), L.Cat(L.Char("="), v.doc))
    END
  END Add;

BEGIN
  d := NIL;
  Add("leftmargin", "margin-left"); Add("rightmargin", "margin-right");
  Add("top", "margin-top"); Add("bottom", "margin-bottom");
  RETURN d
END Layout;

(* lookupMetaString key meta *)
PROCEDURE MetaString(meta: A.MetaMapV; key: ARRAY OF CHAR): Rope;
  VAR v: A.MetaValue;
BEGIN
  v := A.GetMeta(meta, key);
  IF v = NIL THEN RETURN NIL END;
  WITH
    v: A.MetaStringV DO RETURN v.s
  | v: A.MetaInlinesV DO RETURN Sh.Stringify(v.inlines)
  | v: A.MetaBlocksV DO RETURN Sh.StringifyBlocks(v.blocks)
  | v: A.MetaBoolV DO IF v.b THEN RETURN R("true") END; RETURN R("false")
  ELSE
  END;
  RETURN NIL
END MetaString;

(* Writes the document doc as ConTeXt: its body, or, if tmpl is not
   NIL, the template filled in *)
PROCEDURE WriteDoc*(doc: A.Doc; tmpl: T.Template);
  VAR ctx: T.Value; main, placelist: L.Doc; meta: A.MetaMapV; s, lang: Rope; found: BOOLEAN;
    k: INTEGER; b: Buf; n, i: LONGINT;
    levels: ARRAY 6, 20 OF CHAR;
BEGIN
  nextRef := 1; listLevel := 0; cslRefs := FALSE; cslHanging := FALSE;
  meta := doc.meta;
  ctx := C.Build(meta, BlockDoc, InlineDoc);
  main := Blocks(Sh.MakeSections(FALSE, -1, doc.blocks));
  IF tmpl = NIL THEN
    L.Write(L.Chomp(main), 0); PdIO.WriteLn;
    RETURN
  END;
  C.DefField(ctx, "toc", T.NewBool(wantToc));
  C.DefField(ctx, "lof", T.NewBool(FALSE));
  C.DefField(ctx, "lot", T.NewBool(FALSE));
  levels[0] := "chapter"; levels[1] := "section"; levels[2] := "subsection";
  levels[3] := "subsubsection"; levels[4] := "subsubsubsection"; levels[5] := "subsubsubsubsection";
  placelist := NIL;
  FOR k := 0 TO tocDepth DO
    IF k < 6 THEN
      IF k > 0 THEN placelist := L.Cat(placelist, L.Char(",")) END;
      placelist := L.Cat(placelist, Lit(levels[k]))
    END
  END;
  C.DefField(ctx, "placelist", T.NewSimple(placelist));
  C.DefField(ctx, "body", T.NewSimple(main));
  C.DefField(ctx, "layout", T.NewSimple(Layout(ctx)));
  C.DefField(ctx, "tagging", T.NewBool(FALSE));
  C.DefField(ctx, "number-sections", T.NewBool(numberSections));
  C.DefField(ctx, "csl-refs", T.NewBool(cslRefs));
  C.DefField(ctx, "csl-hanging-indent", T.NewBool(cslHanging));
  (* getLang: the variable lang, else the metadata's *)
  lang := Field(ctx, "lang", found);
  IF ~found THEN lang := MetaString(meta, "lang") END;
  lang := FromBCP47(lang);
  IF lang # NIL THEN C.DefField(ctx, "context-lang", T.NewSimple(L.Literal(lang))) END;
  s := Field(ctx, "papersize", found);
  IF found & (Len(s) >= 2) & (Ropes.Fetch(s, 0) = "a") THEN
    b := ToBuf(s); n := Len(s); i := 1;
    WHILE (i < n) & (b[i] >= "0") & (b[i] <= "9") DO INC(i) END;
    IF i = n THEN
      b[0] := "A";
      C.ResetField(ctx, "papersize", T.NewSimple(L.Literal(Ropes.FromSubchars(b^, 0, n))))
    END
  END;
  C.DefField(ctx, "emphasis-commands", T.NewSimple(NIL));
  s := MetaString(meta, "pdfa");
  n := Len(s);
  IF n = 4 THEN
    b := ToBuf(s);
    FOR i := 0 TO 3 DO IF (b[i] >= "A") & (b[i] <= "Z") THEN b[i] := CHR(ORD(b[i]) + 32) END END;
    IF b^ = "true" THEN C.ResetField(ctx, "pdfa", T.NewSimple(Lit("1b:2005"))) END
  END;
  s := Field(ctx, "dir", found);
  IF found THEN
    IF Eq(s, "ltr") THEN s := R("l2r") ELSIF Eq(s, "rtl") THEN s := R("r2l") END;
    C.DefField(ctx, "context-dir", T.NewSimple(L.Literal(s)))
  ELSE C.DefField(ctx, "context-dir", T.NewSimple(NIL))
  END;
  L.Write(T.Render(tmpl, ctx), 0)
END WriteDoc;

BEGIN
  numberSections := FALSE; preserve := FALSE; wantToc := FALSE; tocDepth := 3;
  nextRef := 1; listLevel := 0; cslRefs := FALSE; cslHanging := FALSE
END PdConTeXt.
