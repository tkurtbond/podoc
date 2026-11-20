MODULE PdJson;
(* PdJson: a document written as pandoc's JSON (pandoc -t json), byte
   for byte as pandoc 3.10 writes it: compact, with the map of metadata
   in key order, and a new line at the end.

   Strings are written as aeson writes them: '"', '\' and the control
   characters escaped (\n, \t, \r, \b, \f by name and the rest as
   \u00xx), and everything else, UTF-8 included, as it is. Numbers are
   written as Haskell's show writes a Double. *)

IMPORT Ropes, RealDigits, Strings, PdIO, A := PdAst;

CONST
  ApiVersion = "[1,23,1,2]";

(* Strings *)

(* Writes the characters of chunk, escaped. *)
PROCEDURE EscapeChunk(VAR chunk: ARRAY OF CHAR): BOOLEAN;
  VAR i, start, n: LONGINT; ch: CHAR;
    hex: ARRAY 17 OF CHAR;
BEGIN
  hex := "0123456789abcdef";
  n := LEN(chunk); start := 0; i := 0;
  WHILE i < n DO
    ch := chunk[i];
    IF (ch < " ") OR (ch = 22X) OR (ch = "\") THEN
      IF i > start THEN PdIO.WriteChars(chunk, start, i - start) END;
      CASE ch OF
        22X: PdIO.WriteString('\"')
      | "\": PdIO.WriteString("\\")
      | 0AX: PdIO.WriteString("\n")
      | 09X: PdIO.WriteString("\t")
      | 0DX: PdIO.WriteString("\r")
      | 08X: PdIO.WriteString("\b")
      | 0CX: PdIO.WriteString("\f")
      ELSE
        PdIO.WriteString("\u00");
        PdIO.WriteChar(hex[ORD(ch) DIV 16]); PdIO.WriteChar(hex[ORD(ch) MOD 16])
      END;
      start := i + 1
    END;
    INC(i)
  END;
  IF n > start THEN PdIO.WriteChars(chunk, start, n - start) END;
  RETURN TRUE
END EscapeChunk;

(* Writes r as a JSON string. *)
PROCEDURE String(r: A.Rope);
BEGIN
  PdIO.WriteChar(22X);
  Ropes.IterateChunks(r, EscapeChunk);
  PdIO.WriteChar(22X)
END String;

(* Numbers *)

(* Writes n in decimal. *)
PROCEDURE Int(n: LONGINT);
  VAR d: ARRAY 24 OF CHAR; i: INTEGER;
BEGIN
  IF n < 0 THEN
    PdIO.WriteChar("-");
    IF n = MIN(LONGINT) THEN (* -n does not fit *)
      Int(-(n DIV 10)); PdIO.WriteChar(CHR(ORD("0") + (-(n MOD 10)) MOD 10));
      RETURN
    END;
    n := -n
  END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  WHILE i > 0 DO DEC(i); PdIO.WriteChar(d[i]) END
END Int;

(* The shortest digits that read back give x > 0, in digits (with no
   trailing zeros) and n of them; x is 0.d1d2... * 10^e. *)
PROCEDURE ShortestDigits(x: LONGREAL; VAR digits: ARRAY OF CHAR; VAR n, e: INTEGER);
  VAR p, e10, i, k: INTEGER; s: ARRAY 48 OF CHAR; y: LONGREAL;
BEGIN
  p := 0;
  REPEAT
    INC(p);
    RealDigits.Digits(x, p, digits, e10);
    (* "0.ddd" "E" e10 + 1 *)
    s[0] := "0"; s[1] := "."; i := 0;
    WHILE i < p DO s[2 + i] := digits[i]; INC(i) END;
    k := 2 + p; s[k] := "E"; INC(k);
    e := e10 + 1;
    IF e < 0 THEN s[k] := "-"; INC(k); i := -e ELSE i := e END;
    IF i >= 100 THEN s[k] := CHR(ORD("0") + i DIV 100); INC(k) END;
    IF i >= 10 THEN s[k] := CHR(ORD("0") + i DIV 10 MOD 10); INC(k) END;
    s[k] := CHR(ORD("0") + i MOD 10); s[k + 1] := 0X;
    Strings.StrToLongReal(s, y)
  UNTIL (y = x) OR (p = 17);
  n := p;
  WHILE (n > 1) & (digits[n - 1] = "0") DO DEC(n) END
END ShortestDigits;

(* Writes x as Haskell's show writes a Double: the shortest digits that
   give x, in fixed notation when 0.1 <= |x| < 10^7 and otherwise as
   d.ddde-n. *)
PROCEDURE Real*(x: LONGREAL);
  VAR digits: ARRAY 24 OF CHAR; n, e, i: INTEGER;
BEGIN
  IF x < 0 THEN PdIO.WriteChar("-"); x := -x END;
  IF x = 0 THEN PdIO.WriteString("0.0"); RETURN END;
  ShortestDigits(x, digits, n, e);
  IF (e >= 0) & (e <= 7) THEN (* 0.1 <= x < 10^7 *)
    IF e = 0 THEN
      PdIO.WriteString("0.");
      i := 0; WHILE i < n DO PdIO.WriteChar(digits[i]); INC(i) END
    ELSE
      i := 0;
      WHILE i < e DO
        IF i < n THEN PdIO.WriteChar(digits[i]) ELSE PdIO.WriteChar("0") END;
        INC(i)
      END;
      PdIO.WriteChar(".");
      IF n <= e THEN PdIO.WriteChar("0")
      ELSE WHILE i < n DO PdIO.WriteChar(digits[i]); INC(i) END
      END
    END
  ELSE
    PdIO.WriteChar(digits[0]); PdIO.WriteChar(".");
    IF n = 1 THEN PdIO.WriteChar("0")
    ELSE i := 1; WHILE i < n DO PdIO.WriteChar(digits[i]); INC(i) END
    END;
    PdIO.WriteChar("e"); Int(e - 1)
  END
END Real;

(* Constructors *)

(* Writes {"t":"name"}. *)
PROCEDURE Tag(name: ARRAY OF CHAR);
BEGIN
  PdIO.WriteString('{"t":"'); PdIO.WriteString(name); PdIO.WriteString('"}')
END Tag;

(* Writes {"t":"name","c": and the caller the contents and "}". *)
PROCEDURE Open(name: ARRAY OF CHAR);
BEGIN
  PdIO.WriteString('{"t":"'); PdIO.WriteString(name); PdIO.WriteString('","c":')
END Open;

PROCEDURE Close;
BEGIN
  PdIO.WriteChar("}")
END Close;

PROCEDURE Comma;
BEGIN
  PdIO.WriteChar(",")
END Comma;

PROCEDURE Attr(a: A.Attr);
  VAR c: A.StrList; kv: A.KeyVal;
BEGIN
  IF a = NIL THEN PdIO.WriteString('["",[],[]]'); RETURN END;
  PdIO.WriteChar("["); String(a.id); PdIO.WriteString(",[");
  c := a.classes;
  WHILE c # NIL DO
    String(c.s);
    c := c.next;
    IF c # NIL THEN Comma END
  END;
  PdIO.WriteString("],[");
  kv := a.attrs;
  WHILE kv # NIL DO
    PdIO.WriteChar("["); String(kv.key); Comma; String(kv.value);
    PdIO.WriteChar("]");
    kv := kv.next;
    IF kv # NIL THEN Comma END
  END;
  PdIO.WriteString("]]")
END Attr;

PROCEDURE^ Inlines(i: A.Inline);
PROCEDURE^ Blocks(b: A.Block);

PROCEDURE BlockList(l: A.BlockList);
BEGIN
  PdIO.WriteChar("[");
  WHILE l # NIL DO
    Blocks(l.blocks);
    l := l.next;
    IF l # NIL THEN Comma END
  END;
  PdIO.WriteChar("]")
END BlockList;

PROCEDURE Citations(c: A.Citation);
BEGIN
  PdIO.WriteChar("[");
  WHILE c # NIL DO
    PdIO.WriteString('{"citationId":'); String(c.id);
    PdIO.WriteString(',"citationPrefix":'); Inlines(c.prefix);
    PdIO.WriteString(',"citationSuffix":'); Inlines(c.suffix);
    PdIO.WriteString(',"citationMode":');
    CASE c.mode OF
      A.AuthorInText: Tag("AuthorInText")
    | A.SuppressAuthor: Tag("SuppressAuthor")
    | A.NormalCitation: Tag("NormalCitation")
    END;
    PdIO.WriteString(',"citationNoteNum":'); Int(c.noteNum);
    PdIO.WriteString(',"citationHash":'); Int(c.hash);
    PdIO.WriteChar("}");
    c := c.next;
    IF c # NIL THEN Comma END
  END;
  PdIO.WriteChar("]")
END Citations;

PROCEDURE Inline(i: A.Inline);
BEGIN
  CASE i.kind OF
    A.Str: Open("Str"); String(i(A.StrInl).text); Close
  | A.Emph: Open("Emph"); Inlines(i(A.ContInl).content); Close
  | A.Underline: Open("Underline"); Inlines(i(A.ContInl).content); Close
  | A.Strong: Open("Strong"); Inlines(i(A.ContInl).content); Close
  | A.Strikeout: Open("Strikeout"); Inlines(i(A.ContInl).content); Close
  | A.Superscript: Open("Superscript"); Inlines(i(A.ContInl).content); Close
  | A.Subscript: Open("Subscript"); Inlines(i(A.ContInl).content); Close
  | A.SmallCaps: Open("SmallCaps"); Inlines(i(A.ContInl).content); Close
  | A.Quoted:
      Open("Quoted"); PdIO.WriteChar("[");
      IF i(A.QuotedInl).quote = A.SingleQuote THEN Tag("SingleQuote")
      ELSE Tag("DoubleQuote")
      END;
      Comma; Inlines(i(A.QuotedInl).content); PdIO.WriteChar("]"); Close
  | A.Cite:
      Open("Cite"); PdIO.WriteChar("[");
      Citations(i(A.CiteInl).citations); Comma;
      Inlines(i(A.CiteInl).content); PdIO.WriteChar("]"); Close
  | A.Code:
      Open("Code"); PdIO.WriteChar("[");
      Attr(i(A.CodeInl).attr); Comma; String(i(A.CodeInl).text);
      PdIO.WriteChar("]"); Close
  | A.Space: Tag("Space")
  | A.SoftBreak: Tag("SoftBreak")
  | A.LineBreak: Tag("LineBreak")
  | A.Math:
      Open("Math"); PdIO.WriteChar("[");
      IF i(A.MathInl).math = A.InlineMath THEN Tag("InlineMath")
      ELSE Tag("DisplayMath")
      END;
      Comma; String(i(A.MathInl).text); PdIO.WriteChar("]"); Close
  | A.RawInline:
      Open("RawInline"); PdIO.WriteChar("[");
      String(i(A.RawInl).format); Comma; String(i(A.RawInl).text);
      PdIO.WriteChar("]"); Close
  | A.Link, A.Image:
      IF i.kind = A.Link THEN Open("Link") ELSE Open("Image") END;
      PdIO.WriteChar("[");
      Attr(i(A.LinkInl).attr); Comma; Inlines(i(A.LinkInl).content);
      PdIO.WriteString(",["); String(i(A.LinkInl).url); Comma;
      String(i(A.LinkInl).title); PdIO.WriteString("]]"); Close
  | A.Note: Open("Note"); Blocks(i(A.NoteInl).blocks); Close
  | A.Span:
      Open("Span"); PdIO.WriteChar("[");
      Attr(i(A.SpanInl).attr); Comma; Inlines(i(A.SpanInl).content);
      PdIO.WriteChar("]"); Close
  END
END Inline;

PROCEDURE Inlines(i: A.Inline);
BEGIN
  PdIO.WriteChar("[");
  WHILE i # NIL DO
    Inline(i);
    i := i.next;
    IF i # NIL THEN Comma END
  END;
  PdIO.WriteChar("]")
END Inlines;

PROCEDURE Caption(VAR c: A.Caption);
BEGIN
  PdIO.WriteChar("[");
  IF c.hasShort THEN Inlines(c.short) ELSE PdIO.WriteString("null") END;
  Comma; Blocks(c.blocks); PdIO.WriteChar("]")
END Caption;

PROCEDURE Alignment(a: INTEGER);
BEGIN
  CASE a OF
    A.AlignLeft: Tag("AlignLeft")
  | A.AlignRight: Tag("AlignRight")
  | A.AlignCenter: Tag("AlignCenter")
  | A.AlignDefault: Tag("AlignDefault")
  END
END Alignment;

PROCEDURE Rows(r: A.Row);
  VAR c: A.Cell;
BEGIN
  PdIO.WriteChar("[");
  WHILE r # NIL DO
    PdIO.WriteChar("["); Attr(r.attr); PdIO.WriteString(",[");
    c := r.cells;
    WHILE c # NIL DO
      PdIO.WriteChar("["); Attr(c.attr); Comma; Alignment(c.align); Comma;
      Int(c.rowSpan); Comma; Int(c.colSpan); Comma; Blocks(c.blocks);
      PdIO.WriteChar("]");
      c := c.next;
      IF c # NIL THEN Comma END
    END;
    PdIO.WriteString("]]");
    r := r.next;
    IF r # NIL THEN Comma END
  END;
  PdIO.WriteChar("]")
END Rows;

PROCEDURE Table(t: A.TableBlk);
  VAR cs: A.ColSpec; tb: A.TableBody;
BEGIN
  Open("Table"); PdIO.WriteChar("[");
  Attr(t.attr); Comma; Caption(t.caption); PdIO.WriteString(",[");
  cs := t.colSpecs;
  WHILE cs # NIL DO
    PdIO.WriteChar("["); Alignment(cs.align); Comma;
    IF cs.hasWidth THEN Open("ColWidth"); Real(cs.width); Close
    ELSE Tag("ColWidthDefault")
    END;
    PdIO.WriteChar("]");
    cs := cs.next;
    IF cs # NIL THEN Comma END
  END;
  PdIO.WriteString("],[");
  Attr(t.head.attr); Comma; Rows(t.head.rows); PdIO.WriteString("],[");
  tb := t.bodies;
  WHILE tb # NIL DO
    PdIO.WriteChar("["); Attr(tb.attr); Comma; Int(tb.rowHeadColumns);
    Comma; Rows(tb.head); Comma; Rows(tb.body); PdIO.WriteChar("]");
    tb := tb.next;
    IF tb # NIL THEN Comma END
  END;
  PdIO.WriteString("],[");
  Attr(t.foot.attr); Comma; Rows(t.foot.rows); PdIO.WriteString("]]");
  Close
END Table;

PROCEDURE Block(b: A.Block);
  VAR il: A.InlineList; d: A.DefItem; o: A.OrderedBlk;
BEGIN
  CASE b.kind OF
    A.Plain: Open("Plain"); Inlines(b(A.InlinesBlk).inlines); Close
  | A.Para: Open("Para"); Inlines(b(A.InlinesBlk).inlines); Close
  | A.LineBlock:
      Open("LineBlock"); PdIO.WriteChar("[");
      il := b(A.LineBlk).lines;
      WHILE il # NIL DO
        Inlines(il.inlines);
        il := il.next;
        IF il # NIL THEN Comma END
      END;
      PdIO.WriteChar("]"); Close
  | A.CodeBlock:
      Open("CodeBlock"); PdIO.WriteChar("[");
      Attr(b(A.CodeBlk).attr); Comma; String(b(A.CodeBlk).text);
      PdIO.WriteChar("]"); Close
  | A.RawBlock:
      Open("RawBlock"); PdIO.WriteChar("[");
      String(b(A.RawBlk).format); Comma; String(b(A.RawBlk).text);
      PdIO.WriteChar("]"); Close
  | A.BlockQuote: Open("BlockQuote"); Blocks(b(A.BlocksBlk).blocks); Close
  | A.OrderedList:
      o := b(A.OrderedBlk);
      Open("OrderedList"); PdIO.WriteString("[["); Int(o.start); Comma;
      CASE o.style OF
        A.DefaultStyle: Tag("DefaultStyle")
      | A.Example: Tag("Example")
      | A.Decimal: Tag("Decimal")
      | A.LowerRoman: Tag("LowerRoman")
      | A.UpperRoman: Tag("UpperRoman")
      | A.LowerAlpha: Tag("LowerAlpha")
      | A.UpperAlpha: Tag("UpperAlpha")
      END;
      Comma;
      CASE o.delim OF
        A.DefaultDelim: Tag("DefaultDelim")
      | A.Period: Tag("Period")
      | A.OneParen: Tag("OneParen")
      | A.TwoParens: Tag("TwoParens")
      END;
      PdIO.WriteString("],"); BlockList(o.items); PdIO.WriteChar("]"); Close
  | A.BulletList: Open("BulletList"); BlockList(b(A.ListBlk).items); Close
  | A.DefinitionList:
      Open("DefinitionList"); PdIO.WriteChar("[");
      d := b(A.DefListBlk).items;
      WHILE d # NIL DO
        PdIO.WriteChar("["); Inlines(d.term); Comma; BlockList(d.defs);
        PdIO.WriteChar("]");
        d := d.next;
        IF d # NIL THEN Comma END
      END;
      PdIO.WriteChar("]"); Close
  | A.Header:
      Open("Header"); PdIO.WriteChar("[");
      Int(b(A.HeaderBlk).level); Comma; Attr(b(A.HeaderBlk).attr); Comma;
      Inlines(b(A.HeaderBlk).inlines); PdIO.WriteChar("]"); Close
  | A.HorizontalRule: Tag("HorizontalRule")
  | A.Table: Table(b(A.TableBlk))
  | A.Figure:
      Open("Figure"); PdIO.WriteChar("[");
      Attr(b(A.FigureBlk).attr); Comma; Caption(b(A.FigureBlk).caption);
      Comma; Blocks(b(A.FigureBlk).blocks); PdIO.WriteChar("]"); Close
  | A.Div:
      Open("Div"); PdIO.WriteChar("[");
      Attr(b(A.DivBlk).attr); Comma; Blocks(b(A.DivBlk).blocks);
      PdIO.WriteChar("]"); Close
  END
END Block;

PROCEDURE Blocks(b: A.Block);
BEGIN
  PdIO.WriteChar("[");
  WHILE b # NIL DO
    Block(b);
    b := b.next;
    IF b # NIL THEN Comma END
  END;
  PdIO.WriteChar("]")
END Blocks;

PROCEDURE^ MetaValue(v: A.MetaValue);

PROCEDURE MetaEntries(e: A.MetaEntry);
BEGIN
  PdIO.WriteChar("{");
  WHILE e # NIL DO
    String(e.key); PdIO.WriteChar(":"); MetaValue(e.value);
    e := e.next;
    IF e # NIL THEN Comma END
  END;
  PdIO.WriteChar("}")
END MetaEntries;

PROCEDURE MetaValue(v: A.MetaValue);
  VAR it: A.MetaItem;
BEGIN
  WITH
    v: A.MetaMapV DO Open("MetaMap"); MetaEntries(v.entries); Close
  | v: A.MetaListV DO
      Open("MetaList"); PdIO.WriteChar("[");
      it := v.items;
      WHILE it # NIL DO
        MetaValue(it.value);
        it := it.next;
        IF it # NIL THEN Comma END
      END;
      PdIO.WriteChar("]"); Close
  | v: A.MetaBoolV DO
      Open("MetaBool");
      IF v.b THEN PdIO.WriteString("true") ELSE PdIO.WriteString("false") END;
      Close
  | v: A.MetaStringV DO Open("MetaString"); String(v.s); Close
  | v: A.MetaInlinesV DO Open("MetaInlines"); Inlines(v.inlines); Close
  | v: A.MetaBlocksV DO Open("MetaBlocks"); Blocks(v.blocks); Close
  END
END MetaValue;

(* Writes the document d, as pandoc -t json does, to PdIO's output. *)
PROCEDURE WriteDoc*(d: A.Doc);
BEGIN
  PdIO.WriteString('{"pandoc-api-version":'); PdIO.WriteString(ApiVersion);
  PdIO.WriteString(',"meta":'); MetaEntries(d.meta.entries);
  PdIO.WriteString(',"blocks":'); Blocks(d.blocks);
  PdIO.WriteChar("}"); PdIO.WriteLn
END WriteDoc;

END PdJson.
