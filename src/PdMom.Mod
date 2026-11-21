MODULE PdMom;
(* PdMom: the mom writer (decision 27). pandoc has none; this one
   writes groff mom for groff 1.23 (mom 2.5_d) and later, with what it
   shares with the ms writer in PdRoff: escaping, the font state and
   the tbl tables.

   Macros start lines. Where one comes in the middle of text (a link,
   a note, a target), the text before it ends with \c, so no space is
   put before it, and the text after a link is its SUFFIX, so none is
   put after it. Inside a macro's argument (a heading, a link's text)
   links are written as their text, and notes are dropped with a
   warning. *)

IMPORT Ropes, A := PdAst, L := PdLayout, T := PdTemplate, C := PdContext,
  Sh := PdShared, Ro := PdRoff, PdIO;

TYPE
  Rope = Ropes.Rope;

VAR
  (* options *)
  preserve, wantToc, endnotes: BOOLEAN;
  width: LONGINT; (* the width lines are wrapped at, 0 for none *)

  (* the writer's state *)
  smallCaps, inHeader, inArg, hadEndnote: BOOLEAN;
  quoteDepth: INTEGER; (* how many quotes the block being written is in *)
  fonts: Ro.Fonts;

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

PROCEDURE DQ(d: L.Doc): L.Doc;
BEGIN
  RETURN L.Cat3(L.Char(22X), d, L.Char(22X))
END DQ;

(* A macro's line: its name, then the argument arg, quoted, on one line *)
PROCEDURE Macro(name: ARRAY OF CHAR; arg: L.Doc): L.Doc;
BEGIN
  RETURN L.NoWrap(L.Cat3(Lit(name), L.Space(), DQ(arg)))
END Macro;

(* An identifier as a PDF name *)
PROCEDURE Name(id: Rope): L.Doc;
BEGIN
  RETURN L.Literal(Ro.ToAscii(id))
END Name;

PROCEDURE AttrId(a: A.Attr): Rope;
BEGIN
  IF a = NIL THEN RETURN NIL END;
  RETURN a.id
END AttrId;

(* Inlines *)

PROCEDURE^ Inlines(i: A.Inline): L.Doc;
PROCEDURE^ Blocks(b: A.Block): L.Doc;
PROCEDURE^ Block(b: A.Block): L.Doc;

PROCEDURE WithFont(c: CHAR; i: A.Inline): L.Doc;
  VAR begin, d: L.Doc;
BEGIN
  Ro.Toggle(fonts, c); begin := Ro.FontChange(fonts, inHeader);
  d := Inlines(i);
  Ro.Toggle(fonts, c);
  RETURN L.Cat3(begin, d, Ro.FontChange(fonts, inHeader))
END WithFont;

(* The inlines i as an argument of a macro *)
PROCEDURE Arg(i: A.Inline): L.Doc;
  VAR was: BOOLEAN; d: L.Doc;
BEGIN
  was := inArg; inArg := TRUE;
  d := Inlines(i);
  inArg := was;
  RETURN d
END Arg;

PROCEDURE StrDoc(s: Rope): L.Doc;
  VAR shim: L.Doc;
BEGIN
  shim := NIL;
  IF StartsWithChar(s, ".") THEN shim := L.AfterBreak("\&") END;
  IF smallCaps THEN RETURN L.Cat(shim, L.Literal(Ro.ToSmallCaps(s))) END;
  RETURN L.Cat(shim, L.Literal(Ro.EscapeStr(s)))
END StrDoc;

(* What ends the text before a macro that comes after the inline prev
   (NIL at the start): a new line, after \c unless prev is a space or
   a break *)
PROCEDURE BeforeMacro(prev: A.Inline): L.Doc;
BEGIN
  IF (prev # NIL) & ((prev.kind = A.Space) OR (prev.kind = A.SoftBreak)
     OR (prev.kind = A.LineBreak)) THEN
    RETURN L.Cr()
  END;
  RETURN L.Cat(Lit("\c"), L.Cr())
END BeforeMacro;

(* A link, after the inline prev; with next, a Str that follows it with
   no space between, as its SUFFIX *)
PROCEDURE Link(i: A.LinkInl; prev, next: A.Inline): L.Doc;
  VAR contents, d: L.Doc;
BEGIN
  contents := Arg(i.content);
  IF inArg THEN RETURN contents END;
  IF StartsWithChar(i.url, "#") THEN
    d := L.Cat(Lit(".PDF_LINK "), Name(Ropes.Substring(i.url, 1, Len(i.url) - 1)))
  ELSE
    d := L.Cat(Lit(".PDF_WWW_LINK "), L.Literal(Ro.EscapeUri(i.url)))
  END;
  IF next # NIL THEN
    d := L.Cat3(d, Lit(" SUFFIX "), DQ(L.Literal(Ro.EscapeStr(next(A.StrInl).text))))
  END;
  d := L.NoWrap(L.Cat3(d, L.Space(), DQ(contents)));
  RETURN L.Cat3(BeforeMacro(prev), d, L.Cr())
END Link;

(* A note, after the inline prev: a footnote, or an endnote *)
PROCEDURE Note(n: A.NoteInl; prev: A.Inline): L.Doc;
  VAR bs: A.Block; contents: L.Doc; name: ARRAY 12 OF CHAR;
BEGIN
  IF inArg THEN
    PdIO.Warn("mom: a note in a heading or a link's text is left out");
    RETURN NIL
  END;
  bs := n.blocks;
  IF (bs # NIL) & ((bs.kind = A.Para) OR (bs.kind = A.Plain)) THEN
    contents := Above(L.SplitSentences(Inlines(bs(A.InlinesBlk).inlines)), Blocks(bs.next))
  ELSE contents := Blocks(bs)
  END;
  IF endnotes THEN name := ".ENDNOTE"; hadEndnote := TRUE ELSE name := ".FOOTNOTE" END;
  contents := Above3(Lit(name), contents, L.Cat(Lit(name), Lit(" OFF")));
  RETURN L.Cat3(L.Cat(Lit("\c"), L.Cr()), contents, L.Cat(L.Cr(), Lit("\&")))
END Note;

(* A span: its content, after a .PDF_TARGET for its id *)
PROCEDURE Span(s: A.SpanInl; prev: A.Inline): L.Doc;
  VAR id: Rope; d: L.Doc;
BEGIN
  d := Inlines(s.content);
  id := AttrId(s.attr);
  IF inArg OR (Len(id) = 0) THEN RETURN d END;
  RETURN L.Cat3(BeforeMacro(prev), L.Cat3(Lit(".PDF_TARGET "), Name(id), L.Cr()), d)
END Span;

PROCEDURE Image(i: A.LinkInl): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := L.Cat3(Lit("[IMAGE: "), L.Literal(Ro.EscapeStr(Sh.Stringify(i.content))), L.Char("]"));
  RETURN d
END Image;

PROCEDURE Inline(i, prev: A.Inline): L.Doc;
  VAR d, begin: L.Doc; m: A.MathInl;
BEGIN
  CASE i.kind OF
    A.Str: RETURN StrDoc(i(A.StrInl).text)
  | A.Emph, A.Underline: RETURN WithFont("I", i(A.ContInl).content)
  | A.Strong: RETURN WithFont("B", i(A.ContInl).content)
  | A.Strikeout:
    d := Inlines(i(A.ContInl).content);
    RETURN L.Cat3(Lit("\m[strikecolor]"), d, Lit("\m[]"))
  | A.Superscript:
    d := Inlines(i(A.ContInl).content);
    RETURN L.Cat3(Lit("\*[SUP]"), d, Lit("\*[SUPX]"))
  | A.Subscript:
    d := Inlines(i(A.ContInl).content);
    RETURN L.Cat3(Lit("\v'.3m'\s[-2]"), d, Lit("\s[+2]\v'-.3m'"))
  | A.SmallCaps:
    smallCaps := ~smallCaps;
    d := Inlines(i(A.ContInl).content);
    smallCaps := ~smallCaps;
    RETURN d
  | A.Quoted:
    d := Inlines(i(A.ContInl).content);
    IF i(A.QuotedInl).quote = A.SingleQuote THEN RETURN L.Cat3(Lit("\(oq"), d, Lit("\(cq")) END;
    RETURN L.Cat3(Lit("\(lq"), d, Lit("\(rq"))
  | A.Cite: RETURN Inlines(i(A.ContInl).content)
  | A.Span: RETURN Span(i(A.SpanInl), prev)
  | A.Code:
    Ro.Toggle(fonts, "C"); begin := Ro.FontChange(fonts, inHeader); Ro.Toggle(fonts, "C");
    RETURN L.Cat3(begin, L.Literal(Ro.EscapeStr(i(A.CodeInl).text)), Ro.FontChange(fonts, inHeader))
  | A.Space: RETURN L.Space()
  | A.SoftBreak:
    IF ~inArg & preserve THEN RETURN L.Cr() END;
    RETURN L.Space()
  | A.LineBreak:
    IF inArg THEN RETURN L.Space() END;
    RETURN L.Cat3(L.Cr(), Lit(".BR"), L.Cr())
  | A.Math:
    m := i(A.MathInl);
    IF m.math = A.InlineMath THEN RETURN StrDoc(CatS(Cat(R("$"), m.text), "$")) END;
    d := StrDoc(CatS(Cat(R("$$"), m.text), "$$"));
    IF inArg THEN RETURN d END;
    RETURN Above3(L.Cat(L.Cr(), Lit(".BR")), d, Lit(".BR"))
  | A.RawInline:
    IF Eq(i(A.RawInl).format, "mom") THEN RETURN L.Literal(i(A.RawInl).text) END;
    RETURN NIL
  | A.Link: RETURN NIL (* in Inlines *)
  | A.Image: RETURN Image(i(A.LinkInl))
  | A.Note: RETURN Note(i(A.NoteInl), prev)
  END
END Inline;

PROCEDURE Inlines(i: A.Inline): L.Doc;
  VAR d, x: L.Doc; prev, next: A.Inline;
BEGIN
  d := NIL; prev := NIL;
  WHILE i # NIL DO
    IF i.kind = A.Link THEN
      next := i.next;
      IF (next # NIL) & (next.kind # A.Str) THEN next := NIL END;
      x := Link(i(A.LinkInl), prev, next);
      IF (next # NIL) & ~inArg THEN prev := i; i := next END
    ELSE x := Inline(i, prev)
    END;
    d := L.Cat(d, x); prev := i; i := i.next
  END;
  RETURN d
END Inlines;

(* Blocks *)

PROCEDURE Target(id: Rope): L.Doc;
BEGIN
  IF Len(id) = 0 THEN RETURN NIL END;
  RETURN L.Cat(Lit(".PDF_TARGET "), Name(id))
END Target;

PROCEDURE Header(h: A.HeaderBlk): L.Doc;
  VAR contents, d: L.Doc; id: Rope;
BEGIN
  inHeader := TRUE;
  contents := Arg(h.inlines);
  inHeader := FALSE;
  d := L.Cat(Lit(".HEADING "), L.Literal(Sh.IntRope(h.level)));
  id := AttrId(h.attr);
  IF Len(id) > 0 THEN d := L.Cat3(d, Lit(" NAMED "), Name(id)) END;
  RETURN L.NoWrap(L.Cat3(d, L.Space(), DQ(contents)))
END Header;

PROCEDURE CodeBlock(c: A.CodeBlk): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  IF StartsWithChar(c.text, ".") THEN d := Lit("\&") END;
  d := L.Cat(d, L.Literal(Ro.EscapeStr(c.text)));
  RETURN Above3(Above(Lit(".QUOTE"), Lit(".CODE")), d, Above(Lit(".CODE OFF"), Lit(".QUOTE OFF")))
END CodeBlock;

PROCEDURE Para(i: A.Inline): L.Doc;
BEGIN
  RETURN Above(Lit(".PP"), L.SplitSentences(Inlines(i)))
END Para;

PROCEDURE LineBlock(l: A.InlineList): L.Doc;
  VAR il: A.Inlines;
BEGIN
  A.InitInlines(il);
  Sh.JoinLines(il, l);
  RETURN Para(il.first)
END LineBlock;

(* Lists *)

(* An item's blocks after .ITEM: the first paragraph's text, then the
   rest *)
PROCEDURE Item(bs: A.Block): L.Doc;
  VAR first: L.Doc;
BEGIN
  IF bs = NIL THEN RETURN Lit(".ITEM") END;
  IF (bs.kind = A.Para) OR (bs.kind = A.Plain) THEN
    first := L.SplitSentences(Inlines(bs(A.InlinesBlk).inlines))
  ELSE first := Block(bs)
  END;
  RETURN Above3(Lit(".ITEM"), first, Blocks(bs.next))
END Item;

PROCEDURE Items(it: A.BlockList): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE it # NIL DO d := Above(d, Item(it.blocks)); it := it.next END;
  RETURN Above(d, Lit(".LIST OFF"))
END Items;

PROCEDURE BulletList(l: A.ListBlk): L.Doc;
BEGIN
  RETURN Above(Lit(".LIST BULLET"), Items(l.items))
END BulletList;

(* .LIST with the ordered list's style, separator and prefix, then
   .RESET_LIST for a start other than 1 *)
PROCEDURE OrderedList(l: A.OrderedBlk): L.Doc;
  VAR it: A.BlockList; n: LONGINT; s: Rope; d: L.Doc;
BEGIN
  n := 0; it := l.items;
  WHILE it # NIL DO INC(n); it := it.next END;
  CASE l.style OF
    A.LowerAlpha: s := R("alpha")
  | A.UpperAlpha: s := R("ALPHA")
  | A.LowerRoman: s := Cat(R("roman"), Sh.IntRope(l.start + n - 1))
  | A.UpperRoman: s := Cat(R("ROMAN"), Sh.IntRope(l.start + n - 1))
  ELSE s := R("DIGIT")
  END;
  CASE l.delim OF
    A.OneParen: s := CatS(s, " )")
  | A.TwoParens: s := CatS(s, " ) (")
  ELSE s := CatS(s, " .")
  END;
  d := L.Literal(Cat(R(".LIST "), s));
  IF l.start # 1 THEN d := Above(d, L.Literal(Cat(R(".RESET_LIST "), Sh.IntRope(l.start)))) END;
  RETURN Above(d, Items(l.items))
END OrderedList;

(* Each term in bold, as a paragraph, then its definitions indented by
   2m, their paragraphs (tight ones too) with no first-line indent. mom's paragraph
   indent is kept in the register pd:pi meanwhile. *)
PROCEDURE DefList(l: A.DefListBlk): L.Doc;
  VAR it: A.DefItem; def: A.BlockList; d, x: L.Doc; bs: A.Block;
BEGIN
  d := Above(Lit(".nr pd:pi \n[#PP_INDENT]"), Lit(".PARA_INDENT 0"));
  it := l.items;
  WHILE it # NIL DO
    d := Above3(d, Lit(".PP"), WithFont("B", it.term));
    d := Above(d, Lit(".IL 2m"));
    def := it.defs;
    WHILE def # NIL DO
      bs := def.blocks;
      WHILE bs # NIL DO
        IF bs.kind = A.Plain THEN x := Para(bs(A.InlinesBlk).inlines) ELSE x := Block(bs) END;
        d := Above(d, x); bs := bs.next
      END;
      def := def.next
    END;
    d := Above(d, Lit(".IL -2m"));
    it := it.next
  END;
  RETURN Above(d, Lit(".PARA_INDENT \n[pd:pi]u"))
END DefList;

(* Tables: tbl, through PdRoff (the caption, and mom's .TS arguments,
   are Phase 23.3's). groff 1.23's tbl restores the hyphenation margin
   and space in ems that it saved in basic units, so they grow with
   each table until groff reports a numeric overflow; mom sets them
   (ms does not), so they are kept in pd:hym and pd:hys meanwhile. *)
PROCEDURE Table(t: A.TableBlk): L.Doc;
  VAR il: A.Inlines; simple: BOOLEAN; caption, colheadings, body, d, desc: L.Doc;
BEGIN
  A.InitInlines(il);
  Sh.BlocksToInlines(il, t.caption.blocks);
  caption := NIL;
  IF il.first # NIL THEN caption := Para(il.first) END;
  simple := Ro.TableParts(t, Blocks, desc, colheadings, body);
  d := Above3(caption, Above(Lit(".nr pd:hym \n[.hym]"), Lit(".nr pd:hys \n[.hys]")), Lit(".TS"));
  d := Above3(Above(d, Lit("delim(@@) tab(	);")), desc, colheadings);
  RETURN Above3(Above(d, body), Lit(".TE"), Above(Lit(".hym \n[pd:hym]u"), Lit(".hys \n[pd:hys]u")))
END Table;

PROCEDURE DivDoc(attr: A.Attr; bs: A.Block): L.Doc;
BEGIN
  RETURN Above(Target(AttrId(attr)), Blocks(bs))
END DivDoc;

PROCEDURE Figure(f: A.FigureBlk): L.Doc;
BEGIN
  RETURN Above(DivDoc(f.attr, f.blocks), Blocks(f.caption.blocks))
END Figure;

(* A block quote with the blocks bs. mom's quotes do not nest: one
   directly inside another ends it, is written as a quote of its own,
   and the outer one goes on after it, if anything follows. One further
   in (in a list in a quote) is written as its blocks. *)
PROCEDURE Quote(bs: A.Block): L.Doc;
  VAR d: L.Doc; open: BOOLEAN;
BEGIN
  d := NIL; open := FALSE;
  WHILE bs # NIL DO
    IF bs.kind = A.BlockQuote THEN
      IF open THEN d := Above(d, Lit(".BLOCKQUOTE OFF")); open := FALSE END;
      d := Above(d, Quote(bs(A.BlocksBlk).blocks))
    ELSE
      IF ~open THEN d := Above(d, Lit(".BLOCKQUOTE")); open := TRUE END;
      INC(quoteDepth); d := Above(d, Block(bs)); DEC(quoteDepth)
    END;
    bs := bs.next
  END;
  IF open THEN d := Above(d, Lit(".BLOCKQUOTE OFF")) END;
  RETURN d
END Quote;

PROCEDURE Block(b: A.Block): L.Doc;
BEGIN
  CASE b.kind OF
    A.Plain: RETURN L.SplitSentences(Inlines(b(A.InlinesBlk).inlines))
  | A.Para: RETURN Para(b(A.InlinesBlk).inlines)
  | A.LineBlock: RETURN LineBlock(b(A.LineBlk).lines)
  | A.CodeBlock: RETURN CodeBlock(b(A.CodeBlk))
  | A.RawBlock:
    IF Eq(b(A.RawBlk).format, "mom") THEN RETURN L.Literal(b(A.RawBlk).text) END;
    RETURN NIL
  | A.BlockQuote:
    IF quoteDepth > 0 THEN RETURN Blocks(b(A.BlocksBlk).blocks) END;
    RETURN Quote(b(A.BlocksBlk).blocks)
  | A.OrderedList: RETURN OrderedList(b(A.OrderedBlk))
  | A.BulletList: RETURN BulletList(b(A.ListBlk))
  | A.DefinitionList: RETURN DefList(b(A.DefListBlk))
  | A.Header: RETURN Header(b(A.HeaderBlk))
  | A.HorizontalRule: (* the rule is drawn at the next baseline *)
    RETURN Above(Lit(".DRH"), Lit(".SP 1v"))
  | A.Table: RETURN Table(b(A.TableBlk))
  | A.Figure: RETURN Figure(b(A.FigureBlk))
  | A.Div: RETURN DivDoc(b(A.DivBlk).attr, b(A.DivBlk).blocks)
  END
END Block;

PROCEDURE Blocks(b: A.Block): L.Doc;
  VAR d, x: L.Doc;
BEGIN
  d := NIL;
  WHILE b # NIL DO x := Block(b); d := Above(d, x); b := b.next END;
  RETURN d
END Blocks;

(* The writer *)

(* The blocks b as mom, for the template's metadata *)
PROCEDURE BlockDoc*(b: A.Block): L.Doc;
BEGIN
  RETURN Blocks(b)
END BlockDoc;

(* The inlines i as mom, for the template's metadata: as a macro's
   argument *)
PROCEDURE InlineDoc*(i: A.Inline): L.Doc;
BEGIN
  RETURN L.Chomp(Arg(i))
END InlineDoc;

(* Sets the writer's options: whether soft breaks are kept as new lines
   (--wrap=preserve), whether there is a table of contents (--toc), and
   whether notes are endnotes (--reference-location=document) *)
PROCEDURE SetOptions*(preserveBreaks, toc, endnotesOn: BOOLEAN);
BEGIN
  preserve := preserveBreaks; wantToc := toc; endnotes := endnotesOn
END SetOptions;

(* Sets the width lines are wrapped at (--columns under --wrap=auto),
   0 for none *)
PROCEDURE SetWidth*(w: LONGINT);
BEGIN
  width := w
END SetWidth;

(* .ENDNOTES, if there were endnotes *)
PROCEDURE EndnotesDoc(): L.Doc;
BEGIN
  IF hadEndnote THEN RETURN Lit(".ENDNOTES") END;
  RETURN NIL
END EndnotesDoc;

(* Writes the document doc as mom: its body, or, if tmpl is not NIL,
   the template filled in. The body is written a block at a time,
   unless the template uses it more than once. *)
PROCEDURE WriteDoc*(doc: A.Doc; tmpl: T.Template);
  VAR ctx: T.Value; main: L.Doc; meta: A.MetaMapV; b: A.Block; slot: T.Template;
BEGIN
  smallCaps := FALSE; inHeader := FALSE; inArg := FALSE; hadEndnote := FALSE;
  quoteDepth := 0;
  Ro.ResetFonts(fonts);
  meta := doc.meta;
  IF tmpl = NIL THEN
    L.Open(width); b := doc.blocks;
    WHILE b # NIL DO L.PutAbove(Block(b)); b := b.next END;
    L.PutAbove(EndnotesDoc());
    L.Close; PdIO.WriteLn;
    RETURN
  END;
  ctx := C.Build(meta, BlockDoc, InlineDoc);
  C.DefField(ctx, "toc", T.NewBool(wantToc));
  slot := NIL;
  IF ~T.Has(ctx, "body") THEN slot := T.Slot(tmpl, "body") END;
  IF slot = NIL THEN
    main := Above(Blocks(doc.blocks), EndnotesDoc());
    C.DefField(ctx, "body", T.NewSimple(main));
    L.Write(T.Render(tmpl, ctx), width);
    RETURN
  END;
  L.OpenWhole(width, FALSE);
  L.Put(T.RenderBefore(tmpl, slot, ctx));
  L.BeginSlot; b := doc.blocks;
  WHILE b # NIL DO L.PutAbove(Block(b)); b := b.next END;
  L.PutAbove(EndnotesDoc());
  L.EndSlot;
  L.Put(T.RenderAfter(slot, ctx));
  L.Close
END WriteDoc;

BEGIN
  preserve := FALSE; wantToc := FALSE; endnotes := FALSE; width := 0
END PdMom.
