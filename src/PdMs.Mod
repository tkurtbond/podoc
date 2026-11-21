MODULE PdMs;
(* PdMs: the ms writer, as pandoc 3.10's ms writer
   (Text.Pandoc.Writers.Ms, Text.Pandoc.Writers.Roff) writes groff ms
   without syntax highlighting, with --wrap=none, and with TeX math
   written as its TeX (pandoc's fallback; podoc has no eqn writer).

   The output is built as a PdLayout Doc, as pandoc builds it, since
   pandoc's splitSentences, nowrap and afterBreak work on the Doc. The
   writer's state (the first paragraph, the notes waiting to be
   written, the fonts, small caps) changes as pandoc's does, in the
   same order. *)

IMPORT Ropes, Strings, Utf8, Unicode, A := PdAst, L := PdLayout, T := PdTemplate,
  C := PdContext, Sh := PdShared, PdAscii, PdIO;

TYPE
  Rope = Ropes.Rope;
  MathFinder = POINTER TO RECORD (A.WalkerDesc) found: BOOLEAN END;
  Buf = POINTER TO ARRAY OF CHAR;

  (* a list of Docs *)
  Docs = POINTER TO DocsDesc;
  DocsDesc = RECORD
    d: L.Doc;
    next: Docs
  END;

VAR
  (* options *)
  numberSections, preserve, wantToc: BOOLEAN;
  tocDepth: INTEGER;
  width: LONGINT; (* the width lines are wrapped at, 0 for none *)
  hasEngine, groff: BOOLEAN; (* the variable pdf-engine is set; to "groff" *)

  (* the writer's state *)
  firstPara, smallCaps, inHeader, hasInlineMath: BOOLEAN;
  fontI, fontB, fontC, fontV: BOOLEAN;
  notes: A.BlockList; (* the notes waiting to be written, newest first *)

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

PROCEDURE StartsWithChar(r: Rope; ch: CHAR): BOOLEAN;
BEGIN
  RETURN (Len(r) > 0) & (Ropes.Fetch(r, 0) = ch)
END StartsWithChar;

(* The rune ru, encoded *)
PROCEDURE RuneRope(ru: Utf8.Rune): Rope;
  VAR s: ARRAY 8 OF CHAR; k: LONGINT;
BEGIN
  k := 0;
  IF Utf8.Encode(ru, s, k) THEN RETURN Ropes.FromSubchars(s, 0, k) END;
  RETURN NIL
END RuneRope;

(* r with each rune mapped to upper case (up) or lower case *)
PROCEDURE MapCase(r: Rope; up: BOOLEAN): Rope;
  VAR b: Buf; n, i, q: LONGINT; out: Rope; ru: Utf8.Rune;
BEGIN
  n := Len(r); b := ToBuf(r); out := NIL; i := 0;
  WHILE i < n DO
    q := i;
    IF Utf8.Decode(b^, q, ru) & (q > i) THEN
      IF up THEN ru := Unicode.ToUpper(ru) ELSE ru := Unicode.ToLower(ru) END;
      out := Cat(out, RuneRope(ru))
    ELSE out := CatC(out, b[i]); q := i + 1
    END;
    i := q
  END;
  RETURN out
END MapCase;

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

(* doubleQuotes d *)
PROCEDURE DQ(d: L.Doc): L.Doc;
BEGIN
  RETURN L.Cat3(L.Char(22X), d, L.Char(22X))
END DQ;

PROCEDURE AddDoc(VAR first, last: Docs; d: L.Doc);
  VAR n: Docs;
BEGIN
  NEW(n); n.d := d; n.next := NIL;
  IF first = NIL THEN first := n ELSE last.next := n END;
  last := n
END AddDoc;

(* Escapes *)

(* pandoc's escapeString False AllowUTF8: roff's special characters
   as escapes, and \& before a period that starts a line *)
PROCEDURE EscapeStr(r: Rope): Rope;
  VAR b: Buf; n, i, start, k: LONGINT; out: Rope; rep: ARRAY 8 OF CHAR;
BEGIN
  n := Len(r);
  IF n = 0 THEN RETURN NIL END;
  b := ToBuf(r);
  out := NIL; start := 0; i := 0;
  WHILE i < n DO
    rep[0] := 0X; k := 1;
    CASE b[i] OF
      0AX:
      IF (i + 1 < n) & (b[i + 1] = ".") THEN
        rep[0] := 0AX; rep[1] := "\"; rep[2] := "&"; rep[3] := "."; rep[4] := 0X; k := 2
      END
    | "'": rep := "\(aq"
    | 22X: rep := "\(dq"
    | "`": rep := "\(ga"
    | "^": rep := "\(ha"
    | "~": rep := "\(ti"
    | "\": rep := "\(rs"
    | "@": rep := "\(at"
    | 0C2X:
      IF (i + 1 < n) & (b[i + 1] = 0A0X) THEN rep := "\ "; k := 2 END
    | 0E2X:
      IF (i + 2 < n) & (b[i + 1] = 80X) THEN
        CASE b[i + 2] OF
          98X: rep := "\(oq"
        | 99X: rep := "\(cq"
        | 9CX: rep := "\(lq"
        | 9DX: rep := "\(rq"
        | 94X: rep := "\(em"
        | 93X: rep := "\(en"
        | 0A6X: rep := "\&..."
        ELSE
        END;
        IF rep[0] # 0X THEN k := 3 END
      END
    ELSE
    END;
    IF rep[0] # 0X THEN
      IF i > start THEN out := Cat(out, Ropes.Substring(r, start, i - start)) END;
      out := CatS(out, rep); INC(i, k); start := i
    ELSE INC(i)
    END
  END;
  IF start = 0 THEN RETURN r END; (* nothing escaped *)
  IF n > start THEN out := Cat(out, Ropes.Substring(r, start, n - start)) END;
  RETURN out
END EscapeStr;

(* toSmallCaps: each run of lower case letters in upper case and
   smaller, \s-2 ... \s0; everything else escaped *)
PROCEDURE ToSmallCaps(r: Rope): Rope;
  VAR b: Buf; n, i, q: LONGINT; out, run: Rope; ru: Utf8.Rune; lower: BOOLEAN;
BEGIN
  n := Len(r); b := ToBuf(r);
  out := NIL; run := NIL; lower := FALSE; i := 0;
  WHILE i < n DO
    q := i;
    IF ~Utf8.Decode(b^, q, ru) OR (q <= i) THEN ru := -1; q := i + 1 END;
    IF (ru >= 0) & (Unicode.Category(ru) = Unicode.Ll) THEN
      run := Cat(run, RuneRope(Unicode.ToUpper(ru))); lower := TRUE
    ELSE
      IF lower THEN
        out := CatS(Cat(CatS(out, "\s-2"), EscapeStr(run)), "\s0"); run := NIL; lower := FALSE
      END;
      out := Cat(out, EscapeStr(Ropes.Substring(r, i, q - i)))
    END;
    i := q
  END;
  IF lower THEN out := CatS(Cat(CatS(out, "\s-2"), EscapeStr(run)), "\s0") END;
  RETURN out
END ToSmallCaps;

(* toAscii: an identifier for a PDF anchor *)
PROCEDURE ToAscii(r: Rope): Rope;
  VAR b: Buf; n, i, q: LONGINT; out: Rope; ru: Utf8.Rune; ch: CHAR;
BEGIN
  n := Len(r); b := ToBuf(r);
  out := NIL; i := 0;
  WHILE i < n DO
    q := i;
    IF ~Utf8.Decode(b^, q, ru) OR (q <= i) THEN ru := ORD(b[i]); q := i + 1 END;
    IF PdAscii.ToAscii(ru, ch) & (ch # "/") THEN out := CatC(out, ch)
    ELSE out := CatS(Cat(CatS(out, "_u"), Sh.IntRope(ru)), "_")
    END;
    i := q
  END;
  RETURN out
END ToAscii;

PROCEDURE Octal(VAR out: Rope; v: LONGINT);
  VAR s: ARRAY 5 OF CHAR;
BEGIN
  s[0] := "\"; s[1] := CHR(ORD("0") + v DIV 64); s[2] := CHR(ORD("0") + v DIV 8 MOD 8);
  s[3] := CHR(ORD("0") + v MOD 8); s[4] := 0X;
  out := CatS(out, s)
END Octal;

(* escapePDFString: as it is, if it is ASCII without ( ) \ and ";
   otherwise UTF-16BE, each byte in octal, after a byte order mark *)
PROCEDURE EscapePDFString(r: Rope): Rope;
  VAR b: Buf; n, i, q: LONGINT; out: Rope; ru, lo, hi: LONGINT; x: Utf8.Rune;
    plain: BOOLEAN; ch: CHAR;
BEGIN
  n := Len(r); b := ToBuf(r);
  plain := TRUE; i := 0;
  WHILE plain & (i < n) DO
    ch := b[i];
    IF (ORD(ch) >= 80H) OR (ch = "(") OR (ch = ")") OR (ch = "\") OR (ch = 22X) THEN plain := FALSE END;
    INC(i)
  END;
  IF plain THEN RETURN r END;
  out := R("\376\377"); i := 0;
  WHILE i < n DO
    ch := b[i];
    IF (ORD(ch) < 80H) & (ch # "\") & (ch # "(") & (ch # ")") THEN
      out := CatC(CatS(out, "\000"), ch); INC(i)
    ELSE
      q := i;
      IF ~Utf8.Decode(b^, q, x) OR (q <= i) THEN x := 0FFFDH; q := i + 1 END;
      ru := x;
      IF ru >= 10000H THEN
        DEC(ru, 10000H); hi := 0D800H + ru DIV 400H; lo := 0DC00H + ru MOD 400H;
        Octal(out, hi DIV 256); Octal(out, hi MOD 256);
        Octal(out, lo DIV 256); Octal(out, lo MOD 256)
      ELSE
        Octal(out, ru DIV 256); Octal(out, ru MOD 256)
      END;
      i := q
    END
  END;
  RETURN out
END EscapePDFString;

(* Whether ch may stand in a URI as it is (isAllowedInURI), @ apart *)
PROCEDURE UriChar(ch: CHAR): BOOLEAN;
BEGIN
  CASE ch OF
    "0" .. "9", "A" .. "Z", "a" .. "z",
    "-", "_", ".", "~", ":", "/", "?", "#", "[", "]", "!", "$", "&", "'",
    "(", ")", "*", "+", ",", ";", "=", "%": RETURN TRUE
  ELSE RETURN FALSE
  END
END UriChar;

(* escapeUri: what is not allowed in a URI, and @, %-encoded byte by
   byte *)
PROCEDURE EscapeUri(r: Rope): Rope;
  VAR b: Buf; n, i: LONGINT; out: Rope; ch: CHAR; s: ARRAY 4 OF CHAR; hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789ABCDEF";
  n := Len(r); b := ToBuf(r); out := NIL;
  FOR i := 0 TO n - 1 DO
    ch := b[i];
    IF UriChar(ch) THEN out := CatC(out, ch)
    ELSE
      s[0] := "%"; s[1] := hex[ORD(ch) DIV 16]; s[2] := hex[ORD(ch) MOD 16]; s[3] := 0X;
      out := CatS(out, s)
    END
  END;
  RETURN out
END EscapeUri;

(* Fonts *)

PROCEDURE Toggle(c: CHAR);
BEGIN
  CASE c OF
    "I": fontI := ~fontI
  | "B": fontB := ~fontB
  | "C": fontC := ~fontC
  | "V": fontV := ~fontV
  END
END Toggle;

(* fontChange: the font for the features on *)
PROCEDURE FontChange(): L.Doc;
  VAR s: ARRAY 10 OF CHAR; k: INTEGER;
BEGIN
  s := "\f["; k := 3;
  IF fontC THEN s[k] := "C"; INC(k) END;
  IF fontV THEN s[k] := "V"; INC(k) END;
  IF inHeader OR fontB THEN s[k] := "B"; INC(k) END;
  IF fontI THEN s[k] := "I"; INC(k) END;
  IF k = 3 THEN RETURN Lit("\f[R]")
  ELSIF (k = 4) & fontC THEN RETURN Lit("\f[CR]")
  END;
  s[k] := "]"; s[k + 1] := 0X;
  RETURN Lit(s)
END FontChange;

(* Inlines *)

PROCEDURE^ Inlines(i: A.Inline; bts: BOOLEAN): L.Doc;
PROCEDURE^ InlinesP(i: A.Inline; bts: BOOLEAN): L.Doc;
PROCEDURE^ Blocks(b: A.Block): L.Doc;
PROCEDURE^ Block(b: A.Block): L.Doc;

(* withFontFeature c over the inlines i; inlineListToMs' if withNotes,
   else inlineListToMs *)
PROCEDURE WithFont(c: CHAR; i: A.Inline; bts, withNotes: BOOLEAN): L.Doc;
  VAR begin, d: L.Doc;
BEGIN
  Toggle(c); begin := FontChange();
  IF withNotes THEN d := InlinesP(i, bts) ELSE d := Inlines(i, bts) END;
  Toggle(c);
  RETURN L.Cat3(begin, d, FontChange())
END WithFont;

(* blockToMs (Plain i) *)
PROCEDURE PlainDoc(i: A.Inline): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := InlinesP(i, FALSE);
  RETURN L.SplitSentences(d)
END PlainDoc;

(* The notes waiting, written, or fallback if there are none
   (handleNotes) *)
PROCEDURE HandleNotes(fallback: L.Doc): L.Doc;
  VAR l: A.BlockList; d, first, contents: L.Doc; bs: A.Block;
BEGIN
  IF notes = NIL THEN RETURN fallback END;
  l := notes; notes := NIL; d := NIL;
  WHILE l # NIL DO
    bs := l.blocks;
    IF (bs # NIL) & (bs.kind = A.Para) THEN
      first := PlainDoc(bs(A.InlinesBlk).inlines);
      contents := Above(first, Blocks(bs.next))
    ELSE contents := Blocks(bs)
    END;
    d := Above(d, Above3(L.Cat(L.Cr(), Lit(".FS")), contents, L.Cat(Lit(".FE"), L.Cr())));
    l := l.next
  END;
  RETURN d
END HandleNotes;

(* inlineListToMs': the inlines i, then the notes in them; with bts,
   their line breaks as spaces (breakToSpace) *)
PROCEDURE InlinesP(i: A.Inline; bts: BOOLEAN): L.Doc;
  VAR x: L.Doc;
BEGIN
  x := Inlines(i, bts);
  RETURN L.Cat(x, HandleNotes(NIL))
END InlinesP;

(* inlineToMs (Str s) *)
PROCEDURE StrDoc(s: Rope): L.Doc;
  VAR shim: L.Doc;
BEGIN
  shim := NIL;
  IF StartsWithChar(s, ".") THEN shim := L.AfterBreak("\&") END;
  IF smallCaps THEN RETURN L.Cat(shim, L.Literal(ToSmallCaps(s))) END;
  RETURN L.Cat(shim, L.Literal(EscapeStr(s)))
END StrDoc;

(* The extension of the path s, as takeExtension finds it *)
PROCEDURE Extension(s: Rope): Rope;
  VAR n, i: LONGINT; ch: CHAR;
BEGIN
  n := Len(s); i := n;
  WHILE i > 0 DO
    DEC(i); ch := Ropes.Fetch(s, i);
    IF ch = "/" THEN RETURN NIL
    ELSIF ch = "." THEN RETURN Ropes.Substring(s, i, n - i)
    END
  END;
  RETURN NIL
END Extension;

(* The command for a picture with the path src, "" if there is none *)
PROCEDURE PicCmd(src: Rope; VAR cmd: ARRAY OF CHAR);
  VAR ext: Rope;
BEGIN
  ext := Extension(src);
  IF Eq(ext, ".ps") OR Eq(ext, ".eps") THEN COPY(".PSPIC", cmd)
  ELSIF Eq(ext, ".pdf") THEN COPY(".PDFPIC", cmd)
  ELSE cmd[0] := 0X
  END
END PicCmd;

(* The dimension key of attr in points (inPoints), FALSE if it has
   none *)
PROCEDURE Points(attr: A.Attr; key: ARRAY OF CHAR; VAR p: LONGREAL): BOOLEAN;
  VAR v, int, frac, unit, num: Rope; found: BOOLEAN; s: ARRAY 64 OF CHAR; x: LONGREAL;
BEGIN
  IF attr = NIL THEN RETURN FALSE END;
  v := A.GetKeyVal(attr, key, found);
  IF ~found OR ~Sh.NumUnit(v, int, frac, unit) THEN RETURN FALSE END;
  num := int;
  IF frac # NIL THEN num := Cat(CatS(num, "."), frac) END;
  IF Len(num) >= LEN(s) THEN RETURN FALSE END;
  Ropes.ToString(num, s);
  Strings.StrToLongReal(s, x);
  IF Eq(unit, "px") OR (unit = NIL) OR Eq(unit, "") THEN x := ENTIER(x) / 96.0D0
  ELSIF Eq(unit, "cm") THEN x := x * 0.3937007874D0
  ELSIF Eq(unit, "mm") THEN x := x * 0.03937007874D0
  ELSIF Eq(unit, "in") OR Eq(unit, "inch") THEN
  ELSIF Eq(unit, "%") THEN x := 0
  ELSIF Eq(unit, "pt") THEN x := x / 72.0D0
  ELSIF Eq(unit, "pc") THEN x := x / 6.0D0
  ELSIF Eq(unit, "em") THEN x := x * (11.0D0 / 64.0D0)
  ELSE RETURN FALSE
  END;
  p := x * 72.0D0;
  RETURN TRUE
END Points;

PROCEDURE PointsDoc(p: LONGREAL): L.Doc;
BEGIN
  RETURN L.Cat(L.Space(), DQ(L.Literal(CatS(Sh.IntRope(ENTIER(p)), "p"))))
END PointsDoc;

(* getSizeAttrs *)
PROCEDURE SizeAttrs(attr: A.Attr): L.Doc;
  VAR w, h: LONGREAL;
BEGIN
  IF ~Points(attr, "width", w) THEN RETURN NIL END;
  IF ~Points(attr, "height", h) THEN RETURN PointsDoc(w) END;
  RETURN L.Cat(PointsDoc(w), PointsDoc(h))
END SizeAttrs;

(* \c, then a .pdfhref of kind to target with contents *)
PROCEDURE PdfHref(kind: ARRAY OF CHAR; target: Rope; contents: L.Doc): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := L.NoWrap(L.Cat3(Lit(kind), DQ(L.Literal(target)),
    L.Cat3(Lit(" -A "), DQ(Lit("\c")), L.Cat(L.Space(), Lit("\")))));
  d := L.Cat3(Lit("\c"), L.Cr(), d);
  RETURN L.Cat3(d, L.Cat3(L.Cr(), Lit(" -- "), DQ(L.NoWrap(contents))), L.Cat(L.Cr(), Lit("\&")))
END PdfHref;

PROCEDURE Link(i: A.LinkInl): L.Doc;
  VAR contents: L.Doc;
BEGIN
  contents := InlinesP(i.content, TRUE);
  IF ~hasEngine THEN RETURN contents END;
  IF StartsWithChar(i.url, "#") THEN
    RETURN PdfHref(".pdfhref L -D ", ToAscii(Ropes.Substring(i.url, 1, Len(i.url) - 1)), contents)
  END;
  RETURN PdfHref(".pdfhref W -D ", EscapeUri(i.url), contents)
END Link;

PROCEDURE Image(i: A.LinkInl): L.Doc;
  VAR cmd: ARRAY 8 OF CHAR; d: L.Doc;
BEGIN
  PicCmd(i.url, cmd);
  IF cmd[0] = 0X THEN
    d := L.Cat3(Lit("[IMAGE: "), L.Literal(EscapeStr(Sh.Stringify(i.content))), L.Char("]"));
    d := L.Cat3(d, Lit(' \" '), L.Cat(DQ(L.Literal(i.url)), SizeAttrs(i.attr)))
  ELSE
    d := L.Cat(L.Hsep(Lit(cmd), DQ(L.Literal(i.url))), SizeAttrs(i.attr))
  END;
  RETURN L.Cat3(L.Cr(), L.NoWrap(d), L.Cr())
END Image;

PROCEDURE Inline(i: A.Inline; bts: BOOLEAN): L.Doc;
  VAR d, begin: L.Doc; n: A.BlockList; m: A.MathInl;
BEGIN
  CASE i.kind OF
    A.Str: RETURN StrDoc(i(A.StrInl).text)
  | A.Emph, A.Underline: RETURN WithFont("I", i(A.ContInl).content, FALSE, FALSE)
  | A.Strong: RETURN WithFont("B", i(A.ContInl).content, FALSE, FALSE)
  | A.Strikeout:
    d := Inlines(i(A.ContInl).content, FALSE);
    RETURN L.Cat3(Lit("\m[strikecolor]"), d, Lit("\m[]"))
  | A.Superscript:
    d := Inlines(i(A.ContInl).content, FALSE);
    RETURN L.Cat3(Lit("\*{"), d, Lit("\*}"))
  | A.Subscript:
    d := Inlines(i(A.ContInl).content, FALSE);
    RETURN L.Cat3(Lit("\*<"), d, Lit("\*>"))
  | A.SmallCaps:
    smallCaps := ~smallCaps;
    d := Inlines(i(A.ContInl).content, FALSE);
    smallCaps := ~smallCaps;
    RETURN d
  | A.Quoted:
    d := Inlines(i(A.ContInl).content, FALSE);
    IF i(A.QuotedInl).quote = A.SingleQuote THEN RETURN L.Cat3(L.Char("`"), d, L.Char("'")) END;
    RETURN L.Cat3(Lit("\(lq"), d, Lit("\(rq"))
  | A.Cite, A.Span: RETURN Inlines(i(A.ContInl).content, FALSE)
  | A.Code:
    Toggle("C"); begin := FontChange(); Toggle("C");
    RETURN L.Cat3(begin, L.Literal(EscapeStr(i(A.CodeInl).text)), FontChange())
  | A.Space: RETURN HandleNotes(L.Space())
  | A.SoftBreak:
    IF ~bts & preserve THEN RETURN HandleNotes(L.Cr()) END;
    RETURN HandleNotes(L.Space())
  | A.LineBreak:
    IF bts THEN RETURN HandleNotes(L.Space()) END;
    RETURN L.Cat3(L.Cr(), Lit(".br"), L.Cr())
  | A.Math:
    m := i(A.MathInl);
    IF m.math = A.InlineMath THEN
      hasInlineMath := TRUE;
      RETURN StrDoc(CatS(Cat(R("$"), m.text), "$"))
    END;
    d := StrDoc(CatS(Cat(R("$$"), m.text), "$$"));
    RETURN Above3(L.Cat(L.Cr(), Lit(".RS 3")), d, Lit(".RE"))
  | A.RawInline:
    IF Eq(i(A.RawInl).format, "ms") THEN RETURN L.Literal(i(A.RawInl).text) END;
    RETURN NIL
  | A.Link: RETURN Link(i(A.LinkInl))
  | A.Image: RETURN Image(i(A.LinkInl))
  | A.Note:
    NEW(n); n.blocks := i(A.NoteInl).blocks; n.next := notes; notes := n;
    RETURN Lit("\**")
  END
END Inline;

(* inlineListToMs: hcat; with bts, breakToSpace on each *)
PROCEDURE Inlines(i: A.Inline; bts: BOOLEAN): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE i # NIL DO x := Inline(i, bts); d := L.Cat(d, x); i := i.next END;
  RETURN d
END Inlines;

(* The plain text of inlines, for PDF bookmarks: an approximation of
   pandoc's plain writer *)

(* Appends the inlines i to r as Unicode superscripts (sup) or
   subscripts; FALSE if they have characters that have none *)
PROCEDURE Scripts(VAR r: Rope; i: A.Inline; sup: BOOLEAN): BOOLEAN;
  VAR b: Buf; n, k, q: LONGINT; ru, x: Utf8.Rune; out: Rope;
BEGIN
  out := NIL;
  WHILE i # NIL DO
    CASE i.kind OF
      A.Space, A.SoftBreak: out := CatS(out, " ")
    | A.LineBreak: out := CatC(out, 0AX)
    | A.Span: IF ~Scripts(out, i(A.ContInl).content, sup) THEN RETURN FALSE END
    | A.Str:
      b := ToBuf(i(A.StrInl).text); n := Len(i(A.StrInl).text); k := 0;
      WHILE k < n DO
        q := k;
        IF ~Utf8.Decode(b^, q, ru) OR (q <= k) THEN RETURN FALSE END;
        x := -1;
        IF (ru >= ORD("0")) & (ru <= ORD("9")) THEN
          IF ~sup THEN x := 2080H + ru - ORD("0")
          ELSIF ru = ORD("1") THEN x := 0B9H
          ELSIF ru = ORD("2") THEN x := 0B2H
          ELSIF ru = ORD("3") THEN x := 0B3H
          ELSE x := 2070H + ru - ORD("0")
          END
        ELSIF ru = ORD("+") THEN x := 207AH
        ELSIF (ru = ORD("-")) OR (ru = 2212H) THEN x := 207BH
        ELSIF ru = ORD("=") THEN x := 207CH
        ELSIF ru = ORD("(") THEN x := 207DH
        ELSIF ru = ORD(")") THEN x := 207EH
        ELSIF Unicode.IsSpace(ru) THEN x := ru
        END;
        IF x < 0 THEN RETURN FALSE END;
        IF ~sup & (x >= 207AH) & (x <= 207EH) THEN INC(x, 10H) END;
        out := Cat(out, RuneRope(x));
        k := q
      END
    ELSE RETURN FALSE
    END;
    i := i.next
  END;
  r := Cat(r, out);
  RETURN TRUE
END Scripts;

PROCEDURE PlainTo(VAR r, nt: Rope; VAR nn: LONGINT; i: A.Inline);
  VAR c: Rope; t: A.RawInl;
BEGIN
  WHILE i # NIL DO
    CASE i.kind OF
      A.Str: r := Cat(r, i(A.StrInl).text)
    | A.Space, A.SoftBreak: r := CatS(r, " ")
    | A.LineBreak: r := CatC(r, 0AX)
    | A.Code: r := Cat(r, i(A.CodeInl).text)
    | A.Math: r := Cat(r, i(A.MathInl).text)
    | A.RawInline:
      t := i(A.RawInl);
      IF Eq(t.format, "plain") THEN r := Cat(r, t.text) END
    | A.Quoted:
      IF i(A.QuotedInl).quote = A.DoubleQuote THEN
        r := CatS(r, "“"); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "”")
      ELSE
        r := CatS(r, "‘"); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "’")
      END
    | A.Image:
      r := CatS(r, "["); PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, "]")
    | A.SmallCaps:
      c := NIL; PlainTo(c, nt, nn, i(A.ContInl).content); r := Cat(r, MapCase(c, TRUE))
    | A.Superscript, A.Subscript:
      IF ~Scripts(r, i(A.ContInl).content, i.kind = A.Superscript) THEN
        IF i.kind = A.Superscript THEN r := CatS(r, "^(") ELSE r := CatS(r, "_(") END;
        PlainTo(r, nt, nn, i(A.ContInl).content); r := CatS(r, ")")
      END
    | A.Note:
      INC(nn);
      r := CatS(Cat(CatS(r, "["), Sh.IntRope(nn)), "]");
      nt := CatS(Cat(CatS(CatC(CatC(nt, 0AX), 0AX), "["), Sh.IntRope(nn)), "] ");
      nt := Cat(nt, Sh.StringifyBlocks(i(A.NoteInl).blocks))
    ELSE
      IF i IS A.ContInl THEN PlainTo(r, nt, nn, i(A.ContInl).content) END
    END;
    i := i.next
  END
END PlainTo;

PROCEDURE IsBlank(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 9X) OR (ch = 0AX) OR (ch = 0DX)
END IsBlank;

(* inlinesToPlain: the plain text of i, stripped *)
PROCEDURE PlainText(i: A.Inline): Rope;
  VAR r, nt: Rope; nn, s, e: LONGINT;
BEGIN
  r := NIL; nt := NIL; nn := 0;
  PlainTo(r, nt, nn, i);
  r := Cat(r, nt);
  s := 0; e := Len(r);
  WHILE (s < e) & IsBlank(Ropes.Fetch(r, s)) DO INC(s) END;
  WHILE (e > s) & IsBlank(Ropes.Fetch(r, e - 1)) DO DEC(e) END;
  IF e = s THEN RETURN NIL END;
  RETURN Ropes.Substring(r, s, e - s)
END PlainText;

(* Blocks *)

(* .pdfhref M "id" *)
PROCEDURE Anchor(id: Rope): L.Doc;
BEGIN
  RETURN L.NoWrap(L.Cat(Lit(".pdfhref M "), DQ(L.Literal(ToAscii(id)))))
END Anchor;

PROCEDURE AttrId(a: A.Attr): Rope;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN a.id
END AttrId;

(* Whether i is a Span with only the class c *)
PROCEDURE IsCslSpan(i: A.Inline; c: ARRAY OF CHAR): BOOLEAN;
  VAR a: A.Attr;
BEGIN
  IF (i = NIL) OR (i.kind # A.Span) THEN RETURN FALSE END;
  a := i(A.SpanInl).attr;
  RETURN (a # NIL) & (Len(a.id) = 0) & (a.attrs = NIL) & (a.classes # NIL)
    & (a.classes.next = NIL) & Eq(a.classes.s, c)
END IsCslSpan;

(* The content of the Span i, copied, then the inlines rest, copied *)
PROCEDURE SpanThen(i, rest: A.Inline): A.Inline;
  VAR il: A.Inlines;
BEGIN
  A.InitInlines(il);
  A.Append(il, A.CopyInlines(i(A.ContInl).content));
  A.Append(il, A.CopyInlines(rest));
  RETURN il.first
END SpanThen;

(* cslEntryToMs over a Para's inlines i *)
PROCEDURE CslPara(atStart: BOOLEAN; i: A.Inline): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  IF IsCslSpan(i, "csl-left-margin") & IsCslSpan(i.next, "csl-right-inline") THEN
    x := InlinesP(i(A.ContInl).content, FALSE);
    d := L.Cat3(L.Cr(), Lit(".IP "), L.Cat(DQ(L.NoWrap(x)), Lit(" 5")));
    x := CslPara(FALSE, i.next);
    RETURN Above(d, x)
  ELSIF IsCslSpan(i, "csl-block") OR IsCslSpan(i, "csl-left-margin")
    OR IsCslSpan(i, "csl-indented") THEN
    x := CslPara(FALSE, SpanThen(i, i.next));
    RETURN Above(L.Cat(L.Cr(), Lit(".LP")), x)
  ELSIF atStart THEN
    x := CslPara(FALSE, i);
    RETURN Above(Lit(".CSLP"), x)
  END;
  IF i = NIL THEN RETURN NIL END;
  d := Inline(i, FALSE);
  x := CslPara(FALSE, i.next);
  RETURN L.Cat(d, x)
END CslPara;

(* A Div of the class csl-entry *)
PROCEDURE CslEntry(bs: A.Block): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE bs # NIL DO
    IF bs.kind = A.Para THEN x := CslPara(TRUE, bs(A.InlinesBlk).inlines)
    ELSE x := Block(bs)
    END;
    d := Above(d, x); bs := bs.next
  END;
  RETURN Above(Lit(".CSLENTRY"), d)
END CslEntry;

(* Whether the attribute entry-spacing of a reads as a number > 0 *)
PROCEDURE EntrySpacing(a: A.Attr): BOOLEAN;
  VAR v: Rope; found, digits, pos: BOOLEAN; i, n: LONGINT; ch: CHAR;
BEGIN
  v := A.GetKeyVal(a, "entry-spacing", found);
  IF ~found THEN RETURN FALSE END;
  n := Len(v); i := 0; digits := FALSE; pos := FALSE;
  WHILE (i < n) & IsBlank(Ropes.Fetch(v, i)) DO INC(i) END;
  WHILE (i < n) & (Ropes.Fetch(v, i) >= "0") & (Ropes.Fetch(v, i) <= "9") DO
    ch := Ropes.Fetch(v, i); IF ch # "0" THEN pos := TRUE END;
    digits := TRUE; INC(i)
  END;
  WHILE (i < n) & IsBlank(Ropes.Fetch(v, i)) DO INC(i) END;
  RETURN digits & pos & (i = n)
END EntrySpacing;

PROCEDURE DivDoc(attr: A.Attr; bs: A.Block): L.Doc;
  VAR anchor, res, d: L.Doc; id: Rope;
BEGIN
  id := AttrId(attr); anchor := NIL;
  IF hasEngine & (Len(id) > 0) THEN anchor := Anchor(id) END;
  IF A.HasClass(attr, "csl-entry") THEN RETURN CslEntry(bs)
  ELSIF A.HasClass(attr, "csl-bib-body") THEN
    res := Blocks(bs);
    d := Above3(anchor, Lit(".nr PI 3n"), Lit(".de CSLENTRY"));
    IF EntrySpacing(attr) THEN d := Above(d, Lit(".sp")) END;
    d := Above3(d, Lit(".."), Lit(".de CSLP"));
    IF A.HasClass(attr, "hanging-indent") THEN d := Above(d, Lit(".XP"))
    ELSE d := Above(d, Lit(".LP"))
    END;
    RETURN Above3(d, Lit(".."), res)
  END;
  firstPara := TRUE;
  res := Blocks(bs);
  firstPara := TRUE;
  RETURN Above(anchor, res)
END DivDoc;

PROCEDURE Header(h: A.HeaderBlk): L.Doc;
  VAR contents, anchor, bookmark, backlink, toc, d: L.Doc; plain, id, secnum, t: Rope;
    k: INTEGER;
BEGIN
  firstPara := TRUE;
  inHeader := TRUE;
  contents := InlinesP(h.inlines, TRUE);
  plain := PlainText(h.inlines);
  inHeader := FALSE;
  IF numberSections & ~A.HasClass(h.attr, "unnumbered") THEN
    d := Lit(".NH"); secnum := R("\*[SN]")
  ELSE d := Lit(".SH"); secnum := NIL
  END;
  id := AttrId(h.attr);
  anchor := NIL;
  IF Len(id) > 0 THEN anchor := Anchor(id) END;
  IF secnum # NIL THEN t := CatS(secnum, "  ") ELSE t := NIL END;
  IF groff THEN t := Cat(t, plain) ELSE t := Cat(t, EscapePDFString(plain)) END;
  bookmark := L.Cat3(Lit(".pdfhref O "), L.Literal(CatS(Sh.IntRope(h.level), " ")),
    L.NoWrap(DQ(L.Literal(t))));
  backlink := L.NoWrap(L.Cat3(Lit(".pdfhref L -D "), DQ(L.Literal(ToAscii(id))),
    L.Cat(L.Space(), Lit("\"))));
  backlink := L.Cat3(backlink, L.Cr(), Lit(" -- "));
  toc := NIL;
  IF wantToc & (h.level <= tocDepth) THEN
    t := NIL;
    FOR k := 1 TO h.level DO t := CatC(t, 9X) END;
    IF secnum # NIL THEN t := CatS(Cat(t, secnum), "\~\~") END;
    toc := Above3(Lit(".XS"), L.Cat(backlink, DQ(L.NoWrap(L.Cat(L.Literal(t), contents)))),
      Lit(".XE"))
  END;
  firstPara := TRUE;
  d := Above(L.Cat3(d, L.Space(), L.Literal(Sh.IntRope(h.level))), contents);
  (* .br ends the heading's line first: groff 1.25's .SH and .NH box
     the heading until its line is output, and would box (and print)
     the .pdfhref lines too; pandoc writes no .br *)
  IF hasEngine THEN d := Above3(d, Lit(".br"), Above3(bookmark, anchor, toc)) END;
  RETURN d
END Header;

PROCEDURE CodeBlock(c: A.CodeBlk): L.Doc;
  VAR d: L.Doc;
BEGIN
  firstPara := TRUE;
  d := NIL;
  IF StartsWithChar(c.text, ".") THEN d := Lit("\&") END;
  d := L.Cat(d, L.Literal(EscapeStr(c.text)));
  RETURN Above3(Above3(Lit(".IP"), Lit(".nf"), Lit("\f[C]")), d, Above(Lit("\f[]"), Lit(".fi")))
END CodeBlock;

PROCEDURE Para(i: A.Inline): L.Doc;
  VAR fp: BOOLEAN; c: L.Doc;
BEGIN
  fp := firstPara; firstPara := FALSE;
  c := InlinesP(i, FALSE);
  IF fp THEN RETURN Above(Lit(".LP"), L.SplitSentences(c)) END;
  RETURN Above(Lit(".PP"), L.SplitSentences(c))
END Para;

PROCEDURE LineBlock(l: A.InlineList): L.Doc;
  VAR il: A.Inlines;
BEGIN
  firstPara := TRUE;
  A.InitInlines(il);
  Sh.JoinLines(il, l);
  RETURN Para(il.first)
END LineBlock;

(* Lists *)

PROCEDURE BulletItem(bs: A.Block): L.Doc;
  VAR first, rest: L.Doc;
BEGIN
  IF bs = NIL THEN RETURN NIL END;
  IF (bs.kind = A.Para) OR (bs.kind = A.Plain) THEN
    first := PlainDoc(bs(A.InlinesBlk).inlines);
    rest := Blocks(bs.next);
    first := Above(Lit(".IP \(bu 3"), first);
    IF bs.next = NIL THEN RETURN first END;
    RETURN Above(first, Above3(Lit(".RS 3"), rest, Lit(".RE")))
  END;
  first := Block(bs);
  rest := Blocks(bs.next);
  RETURN Above3(Lit("\(bu .RS 3"), first, Above(rest, Lit(".RE")))
END BulletItem;

PROCEDURE BulletList(l: A.ListBlk): L.Doc;
  VAR it: A.BlockList; d, x: L.Doc;
BEGIN
  d := NIL; it := l.items;
  WHILE it # NIL DO x := BulletItem(it.blocks); d := Above(d, x); it := it.next END;
  firstPara := TRUE;
  RETURN d
END BulletList;

(* toRomanNumeral *)
PROCEDURE Roman(n: LONGINT): Rope;
  VAR r: Rope;
BEGIN
  IF (n >= 4000) OR (n < 0) THEN RETURN R("?") END;
  r := NIL;
  WHILE n >= 1000 DO r := CatC(r, "M"); DEC(n, 1000) END;
  IF n >= 900 THEN r := CatS(r, "CM"); DEC(n, 900) END;
  IF n >= 500 THEN r := CatC(r, "D"); DEC(n, 500) END;
  IF n >= 400 THEN r := CatS(r, "CD"); DEC(n, 400) END;
  WHILE n >= 100 DO r := CatC(r, "C"); DEC(n, 100) END;
  IF n >= 90 THEN r := CatS(r, "XC"); DEC(n, 90) END;
  IF n >= 50 THEN r := CatC(r, "L"); DEC(n, 50) END;
  IF n >= 40 THEN r := CatS(r, "XL"); DEC(n, 40) END;
  WHILE n >= 10 DO r := CatC(r, "X"); DEC(n, 10) END;
  IF n = 9 THEN r := CatS(r, "IX"); n := 0 END;
  IF n >= 5 THEN r := CatC(r, "V"); DEC(n, 5) END;
  IF n = 4 THEN r := CatS(r, "IV"); n := 0 END;
  WHILE n >= 1 DO r := CatC(r, "I"); DEC(n) END;
  RETURN r
END Roman;

(* The k-th (from 0) marker of the ordered list l (orderedListMarkers) *)
PROCEDURE Marker(l: A.OrderedBlk; k: LONGINT): Rope;
  VAR m: Rope; s: LONGINT;
BEGIN
  CASE l.style OF
    A.LowerAlpha, A.UpperAlpha:
    s := l.start - 1; IF s < 0 THEN s := 0 END;
    s := (s + k) MOD 26;
    IF l.style = A.LowerAlpha THEN m := Ropes.FromChar(CHR(ORD("a") + s))
    ELSE m := Ropes.FromChar(CHR(ORD("A") + s))
    END
  | A.UpperRoman: m := Roman(l.start + k)
  | A.LowerRoman: m := MapCase(Roman(l.start + k), FALSE)
  ELSE m := Sh.IntRope(l.start + k)
  END;
  CASE l.delim OF
    A.OneParen: m := CatC(m, ")")
  | A.TwoParens: m := CatC(Cat(R("("), m), ")")
  ELSE m := CatC(m, ".")
  END;
  RETURN m
END Marker;

PROCEDURE OrderedList(l: A.OrderedBlk): L.Doc;
  VAR it: A.BlockList; k, indent, w: LONGINT; m, pad, ind: Rope; first, rest, d, x: L.Doc;
    bs: A.Block;
BEGIN
  indent := 0; k := 0; it := l.items;
  WHILE it # NIL DO
    w := Len(Marker(l, k)); IF w > indent THEN indent := w END;
    INC(k); it := it.next
  END;
  INC(indent, 2); ind := Sh.IntRope(indent);
  d := NIL; k := 0; it := l.items;
  WHILE it # NIL DO
    bs := it.blocks;
    IF bs # NIL THEN
      m := Marker(l, k);
      pad := NIL; w := Len(m);
      WHILE w < indent - 1 DO pad := CatC(pad, " "); INC(w) END;
      IF bs.kind = A.Para THEN first := PlainDoc(bs(A.InlinesBlk).inlines)
      ELSE first := Block(bs)
      END;
      rest := Blocks(bs.next);
      x := Above(L.Literal(Cat(CatS(Cat(Cat(R('.IP "'), pad), m), '" '), ind)), first);
      IF bs.next # NIL THEN
        x := Above(x, Above3(L.Literal(Cat(R(".RS "), ind)), rest, Lit(".RE")))
      END;
      d := Above(d, x)
    END;
    INC(k); it := it.next
  END;
  firstPara := TRUE;
  RETURN d
END OrderedList;

PROCEDURE DefList(l: A.DefListBlk): L.Doc;
  VAR it: A.DefItem; def: A.BlockList; label, first, rest, d, defs: L.Doc; bs: A.Block;
BEGIN
  d := NIL; it := l.items;
  WHILE it # NIL DO
    label := WithFont("B", it.term, TRUE, TRUE);
    defs := NIL; def := it.defs;
    WHILE def # NIL DO
      bs := def.blocks;
      IF bs = NIL THEN rest := NIL; first := PlainDoc(NIL)
      ELSE
        rest := Blocks(bs.next);
        IF bs.kind = A.Para THEN first := PlainDoc(bs(A.InlinesBlk).inlines)
        ELSE first := Block(bs)
        END
      END;
      defs := Above(defs, Above(Above3(first, Lit(".RS 3"), rest), Lit(".RE")));
      def := def.next
    END;
    d := Above(d, Above(L.NoWrap(L.Cat3(Lit(".IP "), DQ(label), Lit(" 3"))), defs));
    it := it.next
  END;
  firstPara := TRUE;
  RETURN d
END DefList;

(* Tables *)

(* makeRow: the cells T{ ... T}, a tab between each two *)
PROCEDURE MakeRow(cols: Docs): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE cols # NIL DO
    d := Above(d, cols.d);
    IF cols.next # NIL THEN d := Above(d, Lit("T}	T{")) END;
    cols := cols.next
  END;
  RETURN Above3(Lit("T{"), d, Lit("T}"))
END MakeRow;

(* A table, as toLegacyTable makes it (PdShared.LegacyRows): the first
   row of the head as the header, the other rows as the body, their
   spans cut into empty pieces *)
PROCEDURE Table(t: A.TableBlk): L.Doc;
  VAR il: A.Inlines; simple, allNull: BOOLEAN; caption, colheadings, body, d, desc: L.Doc;
    cs: A.ColSpec; ncols, k: LONGINT; s: Rope; cols, lastCol: Docs;
    widths: POINTER TO ARRAY OF LONGREAL; head, rows: Sh.LegacyRow;
BEGIN
  A.InitInlines(il);
  Sh.BlocksToInlines(il, t.caption.blocks);
  caption := InlinesP(il.first, FALSE);
  ncols := 0; cs := t.colSpecs;
  WHILE cs # NIL DO INC(ncols); cs := cs.next END;
  NEW(widths, ncols + 1);
  simple := TRUE; s := NIL; k := 0; cs := t.colSpecs;
  WHILE cs # NIL DO
    widths[k] := 0;
    IF cs.hasWidth & (cs.width > 0) THEN widths[k] := cs.width; simple := FALSE END;
    IF k > 0 THEN s := CatC(s, " ") END;
    CASE cs.align OF
      A.AlignRight: s := CatC(s, "r")
    | A.AlignCenter: s := CatC(s, "c")
    ELSE s := CatC(s, "l")
    END;
    IF widths[k] # 0 THEN s := CatS(Cat(CatS(s, "w("), Sh.Fixed(70 * widths[k], 1)), "n)") END;
    INC(k); cs := cs.next
  END;
  desc := L.Literal(CatC(s, "."));
  Sh.LegacyRows(t, head, rows);
  (* the header *)
  colheadings := NIL;
  IF head # NIL THEN
    cols := NIL; lastCol := NIL; allNull := TRUE;
    FOR k := 0 TO head.n - 1 DO
      IF head.cells[k] # NIL THEN allNull := FALSE END;
      AddDoc(cols, lastCol, Blocks(head.cells[k]))
    END;
    IF ~allNull THEN colheadings := Above(MakeRow(cols), L.Char("_")) END
  END;
  (* the rows, each zipped with the widths *)
  body := NIL;
  WHILE rows # NIL DO
    cols := NIL; lastCol := NIL; k := 0;
    WHILE (k < rows.n) & (k < ncols) DO
      d := Blocks(rows.cells[k]);
      IF ~simple THEN
        d := Above(L.Literal(CatS(Cat(R(".nr LL "), Sh.Fixed(widths[k] * 70, 1)), "n")), d)
      END;
      AddDoc(cols, lastCol, d); INC(k)
    END;
    body := Above(body, MakeRow(cols));
    rows := rows.next
  END;
  firstPara := TRUE;
  d := Above3(Lit(".PP"), caption, Lit(".na"));
  IF ~simple THEN d := Above(d, Lit(".nr LLold \n[LL]")) END;
  d := Above3(Above3(d, Lit(".TS"), Lit("delim(@@) tab(	);")), desc, colheadings);
  d := Above3(d, body, Lit(".TE"));
  IF ~simple THEN d := Above(d, Lit(".nr LL \n[LLold]")) END;
  RETURN Above(d, Lit(".ad"))
END Table;

(* height: the number of lines of d as rendered *)
PROCEDURE Height(d: L.Doc): LONGINT;
  VAR r: Rope; n, i, len: LONGINT;
BEGIN
  r := L.Render(d, 0); len := Len(r);
  IF len = 0 THEN RETURN 0 END;
  n := 1;
  FOR i := 0 TO len - 2 DO
    IF Ropes.Fetch(r, i) = 0AX THEN INC(n) END
  END;
  RETURN n
END Height;

PROCEDURE Figure(f: A.FigureBlk): L.Doc;
  VAR b: A.Block; i: A.Inline; img: A.LinkInl; capt, d: L.Doc; cmd: ARRAY 16 OF CHAR;
BEGIN
  b := f.blocks; i := NIL;
  IF (b # NIL) & (b.next = NIL) & (b.kind = A.Plain) THEN i := b(A.InlinesBlk).inlines END;
  IF (i # NIL) & (i.next = NIL) & (i.kind = A.Image) THEN
    img := i(A.LinkInl);
    capt := DivDoc(f.attr, f.caption.blocks);
    PicCmd(img.url, cmd);
    IF cmd[0] = 0X THEN COPY('\" .IMAGE', cmd) END;
    d := L.NoWrap(L.Cat(L.Hsep(Lit(cmd), DQ(L.Literal(img.url))), SizeAttrs(img.attr)));
    d := Above(d, L.Literal(Cat(R(".ce "), Sh.IntRope(Height(capt)))));
    RETURN Above3(d, capt, Lit(".sp 1"))
  END;
  RETURN DivDoc(f.attr, b)
END Figure;

PROCEDURE Block(b: A.Block): L.Doc;
  VAR d: L.Doc;
BEGIN
  CASE b.kind OF
    A.Plain: RETURN PlainDoc(b(A.InlinesBlk).inlines)
  | A.Para: RETURN Para(b(A.InlinesBlk).inlines)
  | A.LineBlock: RETURN LineBlock(b(A.LineBlk).lines)
  | A.CodeBlock: RETURN CodeBlock(b(A.CodeBlk))
  | A.RawBlock:
    IF Eq(b(A.RawBlk).format, "ms") THEN RETURN L.Literal(b(A.RawBlk).text) END;
    RETURN NIL
  | A.BlockQuote:
    firstPara := TRUE;
    d := Blocks(b(A.BlocksBlk).blocks);
    firstPara := TRUE;
    RETURN Above3(Lit(".QS"), d, Lit(".QE"))
  | A.OrderedList: RETURN OrderedList(b(A.OrderedBlk))
  | A.BulletList: RETURN BulletList(b(A.ListBlk))
  | A.DefinitionList: RETURN DefList(b(A.DefListBlk))
  | A.Header: RETURN Header(b(A.HeaderBlk))
  | A.HorizontalRule: firstPara := FALSE; RETURN Lit(".HLINE")
  | A.Table: RETURN Table(b(A.TableBlk))
  | A.Figure: RETURN Figure(b(A.FigureBlk))
  | A.Div: RETURN DivDoc(b(A.DivBlk).attr, b(A.DivBlk).blocks)
  END
END Block;

(* blockListToMs: vcat *)
PROCEDURE Blocks(b: A.Block): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE b # NIL DO x := Block(b); d := Above(d, x); b := b.next END;
  RETURN d
END Blocks;

(* The writer *)

(* The blocks b as ms, for the template's metadata *)
PROCEDURE BlockDoc*(b: A.Block): L.Doc;
BEGIN
  RETURN Blocks(b)
END BlockDoc;

(* The inlines i as ms, for the template's metadata *)
PROCEDURE InlineDoc*(i: A.Inline): L.Doc;
BEGIN
  RETURN L.Chomp(InlinesP(i, FALSE))
END InlineDoc;

(* Sets the writer's options: whether sections are numbered (-N),
   whether soft breaks are kept as new lines (--wrap=preserve), and
   whether there is a table of contents (--toc) and its depth *)
PROCEDURE SetOptions*(number, preserveBreaks, toc: BOOLEAN; depth: INTEGER);
BEGIN
  numberSections := number; preserve := preserveBreaks; wantToc := toc; tocDepth := depth
END SetOptions;

(* Sets the width lines are wrapped at (--columns under --wrap=auto),
   0 for none *)
PROCEDURE SetWidth*(w: LONGINT);
BEGIN
  width := w
END SetWidth;

PROCEDURE LitV(r: Rope): T.Value;
BEGIN
  RETURN T.NewSimple(L.Literal(r))
END LitV;

(* Writes the document doc as ms: its body, or, if tmpl is not NIL,
   the template filled in *)
(* Finding inline math, as the writer would *)

PROCEDURE (w: MathFinder) Inline*(i: A.Inline): A.Inline;
BEGIN
  IF (i.kind = A.Math) & (i(A.MathInl).math = A.InlineMath) THEN w.found := TRUE END;
  RETURN i
END Inline;

(* Whether the metadata or the blocks of doc hold inline math: what
   hasInlineMath is likely to be once the document is written. It is
   checked after. *)
PROCEDURE HasMath(doc: A.Doc): BOOLEAN;
  VAR w: MathFinder;
BEGIN
  NEW(w); w.found := FALSE;
  A.WalkMetaValue(w, doc.meta);
  doc.blocks := A.WalkBlocks(w, doc.blocks);
  RETURN w.found
END HasMath;

PROCEDURE Write(doc: A.Doc; tmpl: T.Template; stream: BOOLEAN): BOOLEAN;
  VAR ctx, v: T.Value; title, main: L.Doc; meta: A.MetaMapV; authors: A.InlineList;
    s: Rope; b: A.Block; slot: T.Template; guess, ours: BOOLEAN;
BEGIN
  firstPara := TRUE; smallCaps := FALSE; inHeader := FALSE; hasInlineMath := FALSE;
  fontI := FALSE; fontB := FALSE; fontC := FALSE; fontV := FALSE; notes := NIL;
  v := T.Get(C.variables, "pdf-engine");
  hasEngine := v # NIL;
  groff := (v # NIL) & (v.kind = T.SimpleV) & Eq(L.Render(v.doc, 0), "groff");
  meta := doc.meta;
  title := L.Chomp(InlinesP(Sh.DocMeta(meta, "title"), FALSE));
  ctx := NIL;
  IF tmpl # NIL THEN ctx := C.Build(meta, BlockDoc, InlineDoc) END;
  IF tmpl = NIL THEN
    (* a block at a time, so the whole body is never built *)
    L.Open(width); b := doc.blocks;
    WHILE b # NIL DO L.PutAbove(Block(b)); b := b.next END;
    L.Close; PdIO.WriteLn;
    RETURN TRUE
  END;
  slot := NIL;
  IF stream & ~T.Has(ctx, "body") THEN slot := T.Slot(tmpl, "body") END;
  IF slot = NIL THEN main := Blocks(doc.blocks) END;
  C.ResetField(ctx, "title", T.NewSimple(title));
  s := NIL; authors := Sh.DocAuthors(meta);
  WHILE authors # NIL DO
    s := Cat(s, EscapeStr(Sh.Stringify(authors.inlines)));
    IF authors.next # NIL THEN s := CatS(s, "; ") END;
    authors := authors.next
  END;
  C.DefField(ctx, "author-meta", LitV(s));
  C.DefField(ctx, "title-meta", LitV(EscapeStr(Sh.Stringify(Sh.DocMeta(meta, "title")))));
  C.DefField(ctx, "toc", T.NewBool(wantToc));
  C.DefField(ctx, "hyphenate", T.NewBool(TRUE));
  IF slot = NIL THEN
    C.DefField(ctx, "has-inline-math", T.NewBool(hasInlineMath));
    C.DefField(ctx, "body", T.NewSimple(main));
    L.Write(T.Render(tmpl, ctx), width);
    RETURN TRUE
  END;
  (* the body a block at a time, between the template's parts before
     and after it. has-inline-math, if the template's part before the
     body needs it, is guessed, and the output held until the guess is
     known to be right. *)
  ours := ~T.Has(ctx, "has-inline-math");
  guess := hasInlineMath OR ours & HasMath(doc);
  C.DefField(ctx, "has-inline-math", T.NewBool(guess));
  L.OpenWhole(width, ours);
  L.Put(T.RenderBefore(tmpl, slot, ctx));
  L.BeginSlot; b := doc.blocks;
  WHILE b # NIL DO L.PutAbove(Block(b)); b := b.next END;
  L.EndSlot;
  IF ours & (hasInlineMath # guess) THEN L.Finish(FALSE); RETURN FALSE END;
  L.Put(T.RenderAfter(slot, ctx));
  L.Close;
  RETURN TRUE
END Write;

PROCEDURE WriteDoc*(doc: A.Doc; tmpl: T.Template);
BEGIN
  IF ~Write(doc, tmpl, TRUE) THEN IF Write(doc, tmpl, FALSE) THEN END END
END WriteDoc;

BEGIN
  numberSections := FALSE; preserve := FALSE; wantToc := FALSE; tocDepth := 3;
  width := 0; hasEngine := FALSE; groff := FALSE; notes := NIL
END PdMs.
