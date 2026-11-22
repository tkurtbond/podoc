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

IMPORT Ropes, A := PdAst, L := PdLayout, T := PdTemplate, C := PdContext,
  Sh := PdShared, Ro := PdRoff, PdIO, PdCode, PdCodeAlign;

TYPE
  Rope = Ropes.Rope;
  MathFinder = POINTER TO RECORD (A.WalkerDesc) found: BOOLEAN END;

VAR
  (* options *)
  numberSections, preserve, wantToc: BOOLEAN;
  tocDepth: INTEGER;
  width: LONGINT; (* the width lines are wrapped at, 0 for none *)
  hasEngine, groff: BOOLEAN; (* the variable pdf-engine is set; to "groff" *)

  (* the writer's state *)
  firstPara, smallCaps, inHeader, hasInlineMath: BOOLEAN;
  fonts: Ro.Fonts;
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

PROCEDURE StartsWithChar(r: Rope; ch: CHAR): BOOLEAN;
BEGIN
  RETURN (Len(r) > 0) & (Ropes.Fetch(r, 0) = ch)
END StartsWithChar;

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
  Ro.Toggle(fonts, c); begin := Ro.FontChange(fonts, inHeader);
  IF withNotes THEN d := InlinesP(i, bts) ELSE d := Inlines(i, bts) END;
  Ro.Toggle(fonts, c);
  RETURN L.Cat3(begin, d, Ro.FontChange(fonts, inHeader))
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
  IF smallCaps THEN RETURN L.Cat(shim, L.Literal(Ro.ToSmallCaps(s))) END;
  RETURN L.Cat(shim, L.Literal(Ro.EscapeStr(s)))
END StrDoc;

(* The command for a picture with the path src, "" if there is none *)
PROCEDURE PicCmd(src: Rope; VAR cmd: ARRAY OF CHAR);
  VAR ext: Rope;
BEGIN
  ext := Ro.Extension(src);
  IF Eq(ext, ".ps") OR Eq(ext, ".eps") THEN COPY(".PSPIC", cmd)
  ELSIF Eq(ext, ".pdf") THEN COPY(".PDFPIC", cmd)
  ELSE cmd[0] := 0X
  END
END PicCmd;

PROCEDURE PointsDoc(p: LONGREAL): L.Doc;
BEGIN
  RETURN L.Cat(L.Space(), DQ(L.Literal(CatS(Sh.IntRope(ENTIER(p)), "p"))))
END PointsDoc;

(* getSizeAttrs *)
PROCEDURE SizeAttrs(attr: A.Attr): L.Doc;
  VAR w, h: LONGREAL;
BEGIN
  IF ~Ro.Points(attr, "width", w) THEN RETURN NIL END;
  IF ~Ro.Points(attr, "height", h) THEN RETURN PointsDoc(w) END;
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
    RETURN PdfHref(".pdfhref L -D ", Ro.ToAscii(Ropes.Substring(i.url, 1, Len(i.url) - 1)), contents)
  END;
  RETURN PdfHref(".pdfhref W -D ", Ro.EscapeUri(i.url), contents)
END Link;

PROCEDURE Image(i: A.LinkInl): L.Doc;
  VAR cmd: ARRAY 8 OF CHAR; d: L.Doc;
BEGIN
  PicCmd(i.url, cmd);
  IF cmd[0] = 0X THEN
    d := L.Cat3(Lit("[IMAGE: "), L.Literal(Ro.EscapeStr(Sh.Stringify(i.content))), L.Char("]"));
    d := L.Cat3(d, Lit(' \" '), L.Cat(DQ(L.Literal(i.url)), SizeAttrs(i.attr)))
  ELSE
    d := L.Cat(L.Hsep(Lit(cmd), DQ(L.Literal(i.url))), SizeAttrs(i.attr))
  END;
  RETURN L.Cat3(L.Cr(), L.NoWrap(d), L.Cr())
END Image;

PROCEDURE Inline(i: A.Inline; bts: BOOLEAN): L.Doc;
  VAR d: L.Doc; n: A.BlockList; m: A.MathInl;
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
  | A.Code: RETURN Ro.InlineCode(fonts, inHeader, i(A.CodeInl).attr, i(A.CodeInl).text)
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

(* Blocks *)

(* .pdfhref M "id" *)
PROCEDURE Anchor(id: Rope): L.Doc;
BEGIN
  RETURN L.NoWrap(L.Cat(Lit(".pdfhref M "), DQ(L.Literal(Ro.ToAscii(id)))))
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
  WHILE (i < n) & Ro.IsBlank(Ropes.Fetch(v, i)) DO INC(i) END;
  WHILE (i < n) & (Ropes.Fetch(v, i) >= "0") & (Ropes.Fetch(v, i) <= "9") DO
    ch := Ropes.Fetch(v, i); IF ch # "0" THEN pos := TRUE END;
    digits := TRUE; INC(i)
  END;
  WHILE (i < n) & Ro.IsBlank(Ropes.Fetch(v, i)) DO INC(i) END;
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
  plain := Ro.PlainText(h.inlines);
  inHeader := FALSE;
  IF numberSections & ~A.HasClass(h.attr, "unnumbered") THEN
    d := Lit(".NH"); secnum := R("\*[SN]")
  ELSE d := Lit(".SH"); secnum := NIL
  END;
  id := AttrId(h.attr);
  anchor := NIL;
  IF Len(id) > 0 THEN anchor := Anchor(id) END;
  IF secnum # NIL THEN t := CatS(secnum, "  ") ELSE t := NIL END;
  IF groff THEN t := Cat(t, plain) ELSE t := Cat(t, Ro.EscapePDFString(plain)) END;
  bookmark := L.Cat3(Lit(".pdfhref O "), L.Literal(CatS(Sh.IntRope(h.level), " ")),
    L.NoWrap(DQ(L.Literal(t))));
  backlink := L.NoWrap(L.Cat3(Lit(".pdfhref L -D "), DQ(L.Literal(Ro.ToAscii(id))),
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

(* A code block: in the code font, its reserved words in bold and
   comments in italic in the mono style; in the text font, with them in
   bold and italic, in the proportional style (decisions 35 and 36),
   aligned as --code-align says (decision 33) *)
PROCEDURE CodeBlock(c: A.CodeBlk): L.Doc;
  VAR d: L.Doc; lang: PdCode.Language; style: INTEGER;
BEGIN
  firstPara := TRUE;
  style := Sh.CodeStyle(c.attr, lang);
  IF style = Sh.CodeProportional THEN
    IF Sh.codeAlign = PdCodeAlign.None THEN
      d := L.Literal(Ro.Highlight(c.text, lang, TRUE, "\f[B]", "\f[I]", "\f[R]"))
    ELSE d := L.Literal(Ro.AlignedCode(c.text, lang, Sh.codeAlign, "\f[B]", "\f[I]", "\f[R]"))
    END;
    RETURN Above3(Above(Lit(".IP"), Lit(".nf")), d, Lit(".fi"))
  END;
  IF style = Sh.CodeNone THEN lang := NIL END;
  d := L.Literal(Ro.Highlight(c.text, lang, TRUE, "\f[CB]", "\f[CI]", "\f[CR]"));
  RETURN Above3(Above3(Lit(".IP"), Lit(".nf"), Lit("\f[CR]")), d, Above(Lit("\f[]"), Lit(".fi")))
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
  | A.UpperRoman: m := Ro.Roman(l.start + k)
  | A.LowerRoman: m := Ro.MapCase(Ro.Roman(l.start + k), FALSE)
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

(* A table, as pandoc's ms writer writes it, with the parts
   PdRoff.TableParts makes *)
PROCEDURE Table(t: A.TableBlk): L.Doc;
  VAR il: A.Inlines; simple: BOOLEAN; caption, colheadings, body, d, desc: L.Doc;
BEGIN
  A.InitInlines(il);
  Sh.BlocksToInlines(il, t.caption.blocks);
  caption := InlinesP(il.first, FALSE);
  simple := Ro.TableParts(t, Blocks, desc, colheadings, body);
  firstPara := TRUE;
  d := Above3(Lit(".PP"), caption, Lit(".na"));
  IF ~simple THEN d := Above(d, Lit(".nr LLold \n[LL]")) END;
  d := Above3(Above3(d, Lit(".TS"), Lit("delim(@@) tab(	);")), desc, colheadings);
  d := Above3(d, body, Lit(".TE"));
  IF ~simple THEN d := Above(d, Lit(".nr LL \n[LLold]")) END;
  RETURN Above(d, Lit(".ad"))
END Table;

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
    d := Above(d, L.Literal(Cat(R(".ce "), Sh.IntRope(Ro.Height(capt)))));
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
  Ro.ResetFonts(fonts); notes := NIL; Sh.SetCodeStyle(doc.meta);
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
    s := Cat(s, Ro.EscapeStr(Sh.Stringify(authors.inlines)));
    IF authors.next # NIL THEN s := CatS(s, "; ") END;
    authors := authors.next
  END;
  C.DefField(ctx, "author-meta", LitV(s));
  C.DefField(ctx, "title-meta", LitV(Ro.EscapeStr(Sh.Stringify(Sh.DocMeta(meta, "title")))));
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
