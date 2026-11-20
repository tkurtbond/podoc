MODULE PdJsonTest;
(* Tests of PdAst and PdJson: documents built by hand and written as
   JSON, each line of the output to be what pandoc 3.10 writes for the
   markdown in the comment above it; then numbers, as Haskell's show
   writes a Double; then a walk. *)

IMPORT Ropes, PdIO, A := PdAst, PdJson;

VAR
  doc: A.Doc;
  body: A.Blocks;

PROCEDURE S(s: ARRAY OF CHAR): A.Rope;
BEGIN
  RETURN A.S(s)
END S;

PROCEDURE Str(s: ARRAY OF CHAR): A.Inline;
BEGIN
  RETURN A.NewStr(S(s))
END Str;

PROCEDURE Sp(): A.Inline;
BEGIN
  RETURN A.NewSimple(A.Space)
END Sp;

(* The list of up to six inlines; NIL ends it early. *)
PROCEDURE L(a, b, c, d, e, f: A.Inline): A.Inline;
  VAR l: A.Inlines;
BEGIN
  A.InitInlines(l);
  A.AddInline(l, a); A.AddInline(l, b); A.AddInline(l, c);
  A.AddInline(l, d); A.AddInline(l, e); A.AddInline(l, f);
  RETURN l.first
END L;

PROCEDURE Plain(i: A.Inline): A.Block;
BEGIN
  RETURN A.NewInlinesBlock(A.Plain, i)
END Plain;

PROCEDURE Para(i: A.Inline): A.Block;
BEGIN
  RETURN A.NewInlinesBlock(A.Para, i)
END Para;

PROCEDURE Item(b: A.Block; next: A.BlockList): A.BlockList;
  VAR l: A.BlockList;
BEGIN
  NEW(l); l.blocks := b; l.next := next;
  RETURN l
END Item;

PROCEDURE Start;
BEGIN
  doc := A.NewDoc(); A.InitBlocks(body)
END Start;

PROCEDURE Add(b: A.Block);
BEGIN
  A.AddBlock(body, b)
END Add;

PROCEDURE Finish;
BEGIN
  doc.blocks := body.first;
  PdJson.WriteDoc(doc)
END Finish;

PROCEDURE Attr(id, class, key, value: ARRAY OF CHAR): A.Attr;
  VAR a: A.Attr;
BEGIN
  a := A.NewAttr(S(id));
  IF class # "" THEN A.AddClass(a, S(class)) END;
  IF key # "" THEN A.AddKeyVal(a, S(key), S(value)) END;
  RETURN a
END Attr;

(* "" *)
PROCEDURE Empty;
BEGIN
  Start; Finish
END Empty;

(* a *b* **c** ~~d~~ ^e^ ~f~ [g]{.smallcaps} [h]{#i .j k=l}
   m\
   n *)
PROCEDURE Inlines1;
  VAR l: A.Inlines;
BEGIN
  Start; A.InitInlines(l);
  A.AddInline(l, L(Str("a"), Sp(), A.NewCont(A.Emph, Str("b")), Sp(),
    A.NewCont(A.Strong, Str("c")), Sp()));
  A.AddInline(l, L(A.NewCont(A.Strikeout, Str("d")), Sp(),
    A.NewCont(A.Superscript, Str("e")), Sp(),
    A.NewCont(A.Subscript, Str("f")), Sp()));
  A.AddInline(l, L(A.NewCont(A.SmallCaps, Str("g")), Sp(),
    A.NewSpan(Attr("i", "j", "k", "l"), Str("h")),
    A.NewSimple(A.SoftBreak), Str("m"), A.NewSimple(A.LineBreak)));
  A.AddInline(l, Str("n"));
  Add(Para(l.first)); Finish
END Inlines1;

(* "q" 'x' $m$ $$d$$ `c`{#i .k a=b} <b> *)
PROCEDURE Inlines2;
  VAR l: A.Inlines;
BEGIN
  Start; A.InitInlines(l);
  A.AddInline(l, L(A.NewQuoted(A.DoubleQuote, Str("q")), Sp(),
    A.NewQuoted(A.SingleQuote, Str("x")), Sp(),
    A.NewMath(A.InlineMath, S("m")), Sp()));
  A.AddInline(l, L(A.NewMath(A.DisplayMath, S("d")), Sp(),
    A.NewCode(Attr("i", "k", "a", "b"), S("c")), Sp(),
    A.NewRawInline(S("html"), S("<b>")), NIL));
  Add(Para(l.first)); Finish
END Inlines2;

(* [l](u "t") ![i](p)^[A note.] [@doe] *)
PROCEDURE Inlines3;
  VAR c: A.Citation;
BEGIN
  Start;
  c := A.NewCitation(S("doe"), A.NormalCitation, 2); (* the note is 1 *)
  Add(Para(L(A.NewLink(A.Link, NIL, Str("l"), S("u"), S("t")), Sp(),
    A.NewLink(A.Image, NIL, Str("i"), S("p"), NIL),
    A.NewNote(Para(L(Str("A"), Sp(), Str("note."), NIL, NIL, NIL))), Sp(),
    A.NewCite(c, Str("[@doe]")))));
  Finish
END Inlines3;

(* @doe [see @doe, p. 3; -@roe]: the citations only *)
PROCEDURE Citations;
  VAR c, d, e: A.Citation; s: ARRAY 8 OF CHAR;
BEGIN
  Start;
  c := A.NewCitation(S("doe"), A.AuthorInText, 1);
  d := A.NewCitation(S("doe"), A.NormalCitation, 1);
  d.prefix := Str("see");
  s := "p.__3"; s[2] := 0C2X; s[3] := 0A0X; (* pandoc's no-break space *)
  d.suffix := L(Str(","), Sp(), Str(s), NIL, NIL, NIL);
  e := A.NewCitation(S("roe"), A.SuppressAuthor, 1);
  c.next := d; d.next := e;
  Add(Para(A.NewCite(c, Str("x")))); Finish
END Citations;

(* ```{.c #x}
   "a\b"<tab>c
   ```
   with --preserve-tabs; then x^Ay^Kz *)
PROCEDURE Escapes;
  VAR s: ARRAY 16 OF CHAR;
BEGIN
  Start;
  s := '"a\b"_c'; s[5] := 09X;
  Add(A.NewCodeBlock(Attr("x", "c", "", ""), S(s)));
  s := "x_y_z"; s[1] := 01X; s[3] := 0BX;
  Add(Para(Str(s)));
  Finish
END Escapes;

(* title: A *T*, b: true, l: [x, y], m: {k: v}, e: (nothing) *)
PROCEDURE Meta;
  VAR l: A.MetaListV; m: A.MetaMapV;
BEGIN
  Start;
  A.SetMeta(doc.meta, S("title"),
    A.NewMetaInlines(L(Str("A"), Sp(), A.NewCont(A.Emph, Str("T")), NIL, NIL, NIL)));
  A.SetMeta(doc.meta, S("e"), A.NewMetaString(NIL));
  l := A.NewMetaList();
  A.AddMetaItem(l, A.NewMetaInlines(Str("x")));
  A.AddMetaItem(l, A.NewMetaBool(TRUE));
  A.SetMeta(doc.meta, S("l"), l);
  m := A.NewMetaMap();
  A.SetMeta(m, S("k"), A.NewMetaInlines(Str("v")));
  A.SetMeta(doc.meta, S("m"), m);
  A.SetMeta(doc.meta, S("b"), A.NewMetaBool(FALSE));
  A.SetMeta(doc.meta, S("b"), A.NewMetaBool(TRUE)); (* replaces *)
  Finish
END Meta;

(* # H {#h .c}, > q, * a * b, 3) x, (ii) y, T : d, ---, ::: {.w} p :::,
   | a |  b, ```{=html} <hr> ``` *)
PROCEDURE Blocks;
  VAR d: A.DefItem; lines, l2: A.InlineList; s: ARRAY 8 OF CHAR;
BEGIN
  Start;
  Add(A.NewHeader(1, Attr("h", "c", "", ""), Str("H")));
  Add(A.NewBlockQuote(Para(Str("q"))));
  Add(A.NewBulletList(Item(Plain(Str("a")), Item(Plain(Str("b")), NIL))));
  Add(A.NewOrderedList(3, A.Decimal, A.OneParen, Item(Plain(Str("x")), NIL)));
  Add(A.NewOrderedList(2, A.LowerRoman, A.TwoParens, Item(Plain(Str("y")), NIL)));
  NEW(d); d.term := Str("T"); d.defs := Item(Plain(Str("d")), NIL); d.next := NIL;
  Add(A.NewDefinitionList(d));
  Add(A.NewHorizontalRule());
  Add(A.NewDiv(Attr("", "w", "", ""), Para(Str("p"))));
  NEW(lines); NEW(l2);
  lines.inlines := Str("a"); lines.next := l2;
  s := "__b"; s[0] := 0C2X; s[1] := 0A0X; (* a no-break space *)
  l2.inlines := Str(s); l2.next := NIL;
  Add(A.NewLineBlock(lines));
  Add(A.NewRawBlock(S("html"), S("<hr>")));
  Finish
END Blocks;

PROCEDURE Cell(s: ARRAY OF CHAR; next: A.Cell): A.Cell;
  VAR c: A.Cell;
BEGIN
  NEW(c); c.attr := NIL; c.align := A.AlignDefault; c.rowSpan := 1;
  c.colSpan := 1; c.blocks := Plain(Str(s)); c.next := next;
  RETURN c
END Cell;

PROCEDURE Row(cells: A.Cell): A.Row;
  VAR r: A.Row;
BEGIN
  NEW(r); r.attr := NIL; r.cells := cells; r.next := NIL;
  RETURN r
END Row;

PROCEDURE Col(align: INTEGER; hasWidth: BOOLEAN; width: LONGREAL; next: A.ColSpec): A.ColSpec;
  VAR c: A.ColSpec;
BEGIN
  NEW(c); c.align := align; c.hasWidth := hasWidth; c.width := width;
  c.next := next;
  RETURN c
END Col;

(* | a | b |
   |:--|--:|
   | 1 | 2 |

   : Cap

   ![f](i.png) *)
PROCEDURE Tables;
  VAR t: A.TableBlk; tb: A.TableBody;
BEGIN
  Start;
  t := A.NewTable(NIL);
  t.caption.blocks := Plain(Str("Cap"));
  t.colSpecs := Col(A.AlignLeft, FALSE, 0, Col(A.AlignRight, FALSE, 0, NIL));
  t.head.rows := Row(Cell("a", Cell("b", NIL)));
  NEW(tb); tb.attr := NIL; tb.rowHeadColumns := 0; tb.head := NIL;
  tb.body := Row(Cell("1", Cell("2", NIL))); tb.next := NIL;
  t.bodies := tb;
  Add(t);
  Add(A.NewFigure(NIL, Plain(Str("f")),
    Plain(A.NewLink(A.Image, NIL, Str("f"), S("i.png"), NIL))));
  Finish
END Tables;

(* | a | b |, a separator of 71 and 44 dashes, | 1 | 2 |: the widths *)
PROCEDURE Widths;
  VAR t: A.TableBlk; tb: A.TableBody;
BEGIN
  Start;
  t := A.NewTable(NIL);
  t.colSpecs := Col(A.AlignDefault, TRUE, 71.0D0 / 115.0D0,
    Col(A.AlignDefault, TRUE, 44.0D0 / 115.0D0, NIL));
  t.head.rows := Row(Cell("a", Cell("b", NIL)));
  NEW(tb); tb.attr := NIL; tb.rowHeadColumns := 0; tb.head := NIL;
  tb.body := Row(Cell("1", Cell("2", NIL))); tb.next := NIL;
  t.bodies := tb;
  Add(t);
  Finish
END Widths;

PROCEDURE Real(x: LONGREAL);
BEGIN
  PdJson.Real(x); PdIO.WriteLn
END Real;

PROCEDURE Reals;
BEGIN
  Real(0.1D0); Real(1.0D0); Real(1.0D7); Real(1234567.0D0);
  Real(9999999.0D0); Real(0.05D0); Real(1.0D0 / 3.0D0); Real(100.0D0);
  Real(123.456D0); Real(8.771929824561403D-3); Real(1.0D-300);
  Real(5.0D-324); Real(1.7976931348623157D308); Real(-2.5D0); Real(0.0D0);
  Real(71.0D0 / 115.0D0); Real(2.0D0 / 7.0D0); Real(1.0D22); Real(0.3D0)
END Reals;

(* A walk: every Str "x" becomes Emph [Str "y"], every Space is
   deleted, and every Para becomes the Plain of its inlines and a
   HorizontalRule after it. *)

TYPE
  TestWalker = POINTER TO TestWalkerDesc;
  TestWalkerDesc = RECORD (A.WalkerDesc) END;

PROCEDURE (w: TestWalker) Inline*(i: A.Inline): A.Inline;
BEGIN
  IF (i.kind = A.Str) & Ropes.EqualString(i(A.StrInl).text, "x") THEN
    RETURN A.NewCont(A.Emph, Str("y"))
  ELSIF i.kind = A.Space THEN
    RETURN NIL
  END;
  RETURN i
END Inline;

PROCEDURE (w: TestWalker) Block*(b: A.Block): A.Block;
  VAR p: A.Block;
BEGIN
  IF b.kind = A.Para THEN
    p := Plain(b(A.InlinesBlk).inlines);
    p.next := A.NewHorizontalRule();
    RETURN p
  END;
  RETURN b
END Block;

(* x a x, in a note too, and a title of x *)
PROCEDURE Walk;
  VAR w: TestWalker;
BEGIN
  Start;
  A.SetMeta(doc.meta, S("title"), A.NewMetaInlines(Str("x")));
  Add(Para(L(Str("x"), Sp(), Str("a"), Sp(),
    A.NewNote(Para(L(Str("x"), Sp(), Str("x"), NIL, NIL, NIL))), NIL)));
  Add(A.NewBlockQuote(Para(Str("b"))));
  doc.blocks := body.first;
  NEW(w);
  A.WalkDoc(w, doc);
  PdJson.WriteDoc(doc)
END Walk;

BEGIN
  Empty; Inlines1; Inlines2; Inlines3; Citations; Escapes; Meta; Blocks;
  Tables; Widths; Reals; Walk;
  PdIO.CloseOutput
END PdJsonTest.
