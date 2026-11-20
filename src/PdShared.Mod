MODULE PdShared;
(* PdShared: what pandoc's writers share (Text.Pandoc.Shared,
   Text.Pandoc.Writers.Shared): the text of inlines and blocks
   (stringify), and the division of a document into sections
   (makeSections). *)

IMPORT Ropes, A := PdAst;

CONST
  MaxLevels = 100; (* the most levels a section number has *)

TYPE
  Rope = Ropes.Rope;
  (* A walker that finds the lowest header level *)
  LevelWalker = POINTER TO LevelWalkerDesc;
  LevelWalkerDesc = RECORD (A.WalkerDesc)
    min: INTEGER
  END;

VAR
  numbering: BOOLEAN; (* MakeSections: whether sections are numbered *)
  baseLevel: INTEGER; (* MakeSections: the level of the top sections; < 0 if they keep theirs *)
  minLevel: INTEGER; (* the lowest header level in the document *)
  lastNum: ARRAY MaxLevels OF LONGINT; (* the last section number *)
  lastLen: INTEGER; (* its components *)

(* stringify *)

PROCEDURE^ StringifyBlocksTo(VAR r: Rope; b: A.Block);

PROCEDURE Add(VAR r: Rope; s: ARRAY OF CHAR);
BEGIN
  r := Ropes.Cat(r, Ropes.FromString(s))
END Add;

(* Whether the rope r starts with s *)
PROCEDURE StartsWith*(r: Rope; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO
    IF (i >= Ropes.Length(r)) OR (Ropes.Fetch(r, i) # s[i]) THEN RETURN FALSE END;
    INC(i)
  END;
  RETURN TRUE
END StartsWith;

PROCEDURE StringifyTo(VAR r: Rope; i: A.Inline);
BEGIN
  WHILE i # NIL DO
    CASE i.kind OF
      A.Str: r := Ropes.Cat(r, i(A.StrInl).text)
    | A.Space, A.SoftBreak, A.LineBreak: Add(r, " ")
    | A.Code: r := Ropes.Cat(r, i(A.CodeInl).text)
    | A.Math: r := Ropes.Cat(r, i(A.MathInl).text)
    | A.RawInline:
      IF Ropes.EqualString(i(A.RawInl).format, "html")
         & StartsWith(i(A.RawInl).text, "<br") THEN
        Add(r, " ")
      END
    | A.Quoted:
      IF i(A.QuotedInl).quote = A.DoubleQuote THEN
        Add(r, "“"); StringifyTo(r, i(A.ContInl).content); Add(r, "”")
      ELSE
        Add(r, "‘"); StringifyTo(r, i(A.ContInl).content); Add(r, "’")
      END
    | A.Note:
    ELSE
      IF i IS A.ContInl THEN StringifyTo(r, i(A.ContInl).content) END
    END;
    i := i.next
  END
END StringifyTo;

(* The text of the inlines i, without their formatting (stringify) *)
PROCEDURE Stringify*(i: A.Inline): Rope;
  VAR r: Rope;
BEGIN
  r := NIL; StringifyTo(r, i);
  RETURN r
END Stringify;

PROCEDURE StringifyRows(VAR r: Rope; row: A.Row);
  VAR c: A.Cell;
BEGIN
  WHILE row # NIL DO
    c := row.cells;
    WHILE c # NIL DO StringifyBlocksTo(r, c.blocks); c := c.next END;
    row := row.next
  END
END StringifyRows;

PROCEDURE StringifyBlocksTo(VAR r: Rope; b: A.Block);
  VAR l: A.InlineList; bl: A.BlockList; d: A.DefItem; t: A.TableBlk;
    tb: A.TableBody;
BEGIN
  WHILE b # NIL DO
    WITH b: A.InlinesBlk DO StringifyTo(r, b.inlines)
    | b: A.LineBlk DO
      l := b.lines;
      WHILE l # NIL DO StringifyTo(r, l.inlines); l := l.next END
    | b: A.FigureBlk DO
      StringifyTo(r, b.caption.short); StringifyBlocksTo(r, b.caption.blocks);
      StringifyBlocksTo(r, b.blocks)
    | b: A.BlocksBlk DO StringifyBlocksTo(r, b.blocks)
    | b: A.ListBlk DO
      bl := b.items;
      WHILE bl # NIL DO StringifyBlocksTo(r, bl.blocks); bl := bl.next END
    | b: A.DefListBlk DO
      d := b.items;
      WHILE d # NIL DO
        StringifyTo(r, d.term);
        bl := d.defs;
        WHILE bl # NIL DO StringifyBlocksTo(r, bl.blocks); bl := bl.next END;
        d := d.next
      END
    | b: A.TableBlk DO
      t := b;
      StringifyTo(r, t.caption.short); StringifyBlocksTo(r, t.caption.blocks);
      StringifyRows(r, t.head.rows);
      tb := t.bodies;
      WHILE tb # NIL DO StringifyRows(r, tb.head); StringifyRows(r, tb.body); tb := tb.next END;
      StringifyRows(r, t.foot.rows)
    ELSE
    END;
    b := b.next
  END
END StringifyBlocksTo;

(* The text of the blocks b, without their formatting, joined with
   nothing between them (stringify) *)
PROCEDURE StringifyBlocks*(b: A.Block): Rope;
  VAR r: Rope;
BEGIN
  r := NIL; StringifyBlocksTo(r, b);
  RETURN r
END StringifyBlocks;

(* makeSections *)

PROCEDURE (w: LevelWalker) Block*(b: A.Block): A.Block;
BEGIN
  IF (b IS A.HeaderBlk) & (b(A.HeaderBlk).level < w.min) THEN
    w.min := b(A.HeaderBlk).level
  END;
  RETURN b
END Block;

(* Whether b is a header of level at most level, or a Div that starts
   with one (headerLtEq) *)
PROCEDURE HeaderLtEq(level: INTEGER; b: A.Block): BOOLEAN;
BEGIN
  WHILE (b # NIL) & (b IS A.DivBlk) DO b := b(A.DivBlk).blocks END;
  RETURN (b # NIL) & (b IS A.HeaderBlk) & (b(A.HeaderBlk).level <= level)
END HeaderLtEq;

(* Whether the list of strings l has s *)
PROCEDURE HasString(l: A.StrList; s: Rope): BOOLEAN;
BEGIN
  WHILE l # NIL DO
    IF Ropes.Equal(l.s, s) THEN RETURN TRUE END;
    l := l.next
  END;
  RETURN FALSE
END HasString;

(* Whether the key-value list l has key *)
PROCEDURE HasKey(l: A.KeyVal; key: Rope): BOOLEAN;
BEGIN
  WHILE l # NIL DO
    IF Ropes.Equal(l.key, key) THEN RETURN TRUE END;
    l := l.next
  END;
  RETURN FALSE
END HasKey;

(* The decimal digits of n *)
PROCEDURE IntRope*(n: LONGINT): Rope;
  VAR s: ARRAY 24 OF CHAR; d: ARRAY 24 OF CHAR; i, k: INTEGER; neg: BOOLEAN;
BEGIN
  neg := n < 0; IF neg THEN n := -n END;
  i := 0;
  REPEAT d[i] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(i) UNTIL n = 0;
  k := 0; IF neg THEN s[0] := "-"; k := 1 END;
  WHILE i > 0 DO DEC(i); s[k] := d[i]; INC(k) END;
  s[k] := 0X;
  RETURN Ropes.FromString(s)
END IntRope;

(* combineAttr a b: a's id unless it is empty; the classes of a, then
   those of b, each once; the key-values of b, after those of a whose
   keys b does not have *)
PROCEDURE CombineAttr(a, b: A.Attr): A.Attr;
  VAR r: A.Attr; l: A.StrList; kv: A.KeyVal;
BEGIN
  r := A.NewAttr(NIL);
  IF (a # NIL) & (Ropes.Length(a.id) > 0) THEN r.id := a.id
  ELSIF b # NIL THEN r.id := b.id
  END;
  IF a # NIL THEN
    l := a.classes;
    WHILE l # NIL DO IF ~HasString(r.classes, l.s) THEN A.AddClass(r, l.s) END; l := l.next END
  END;
  IF b # NIL THEN
    l := b.classes;
    WHILE l # NIL DO IF ~HasString(r.classes, l.s) THEN A.AddClass(r, l.s) END; l := l.next END
  END;
  IF a # NIL THEN
    kv := a.attrs;
    WHILE kv # NIL DO
      IF (b = NIL) OR ~HasKey(b.attrs, kv.key) THEN A.AddKeyVal(r, kv.key, kv.value) END;
      kv := kv.next
    END
  END;
  IF b # NIL THEN
    kv := b.attrs;
    WHILE kv # NIL DO A.AddKeyVal(r, kv.key, kv.value); kv := kv.next END
  END;
  RETURN r
END CombineAttr;

PROCEDURE^ Go(b: A.Block): A.Block;

(* Whether the Div d may become a section: it starts with a header,
   none of its other blocks is a header of the same or a lower level,
   and it is not a column or a fragment *)
PROCEDURE SectionDiv(d: A.DivBlk): BOOLEAN;
  VAR h: A.HeaderBlk; b: A.Block;
BEGIN
  IF (d.blocks = NIL) OR ~(d.blocks IS A.HeaderBlk)
     OR A.HasClass(d.attr, "column") OR A.HasClass(d.attr, "columns")
     OR A.HasClass(d.attr, "fragment") THEN
    RETURN FALSE
  END;
  h := d.blocks(A.HeaderBlk); b := h.next;
  WHILE b # NIL DO
    IF (b IS A.HeaderBlk) & (b(A.HeaderBlk).level <= h.level) THEN RETURN FALSE END;
    b := b.next
  END;
  RETURN TRUE
END SectionDiv;

(* The section that starts with the header h, its contents those of
   the list contents *)
PROCEDURE Section(h: A.HeaderBlk; contents: A.Block): A.Block;
  VAR level, i, n: INTEGER; newNum: ARRAY MaxLevels OF LONGINT;
    unnumbered, found: BOOLEAN; num, role: Rope; dattr, hattr: A.Attr;
    kv: A.KeyVal; l: A.StrList; nh: A.HeaderBlk; d: A.DivBlk;
BEGIN
  level := h.level;
  unnumbered := A.HasClass(h.attr, "unnumbered");
  n := 0;
  FOR i := minLevel TO level DO
    IF n < MaxLevels THEN
      IF n < lastLen THEN newNum[n] := lastNum[n] ELSE newNum[n] := 0 END;
      IF i = level THEN INC(newNum[n]) ELSIF i > level THEN newNum[n] := 0 END;
      INC(n)
    END
  END;
  IF (n > 0) & ~unnumbered THEN
    FOR i := 0 TO n - 1 DO lastNum[i] := newNum[i] END;
    lastLen := n
  END;
  contents := Go(contents);
  dattr := A.NewAttr(NIL); hattr := A.NewAttr(NIL);
  IF h.attr # NIL THEN dattr.id := h.attr.id END;
  A.AddClass(dattr, A.S("section"));
  IF h.attr # NIL THEN
    l := h.attr.classes;
    WHILE l # NIL DO A.AddClass(dattr, l.s); A.AddClass(hattr, l.s); l := l.next END
  END;
  num := A.GetKeyVal(h.attr, "number", found);
  IF ~found & numbering & ~unnumbered THEN
    num := NIL;
    FOR i := 0 TO n - 1 DO
      IF i > 0 THEN num := Ropes.Cat(num, Ropes.FromString(".")) END;
      num := Ropes.Cat(num, IntRope(newNum[i]))
    END;
    A.AddKeyVal(dattr, A.S("number"), num);
    A.AddKeyVal(hattr, A.S("number"), num)
  END;
  IF h.attr # NIL THEN
    kv := h.attr.attrs;
    WHILE kv # NIL DO
      A.AddKeyVal(dattr, kv.key, kv.value);
      IF Ropes.EqualString(kv.key, "epub:type") THEN
      ELSIF Ropes.EqualString(kv.key, "role") THEN
        role := kv.value;
        IF Ropes.EqualString(role, "tab") OR Ropes.EqualString(role, "presentation")
           OR Ropes.EqualString(role, "none") OR Ropes.EqualString(role, "treeitem")
           OR Ropes.EqualString(role, "menuitem") OR Ropes.EqualString(role, "button")
           OR Ropes.EqualString(role, "heading") THEN
          A.AddKeyVal(hattr, kv.key, kv.value)
        END
      ELSE A.AddKeyVal(hattr, kv.key, kv.value)
      END;
      kv := kv.next
    END
  END;
  NEW(nh); nh^ := h^;
  IF baseLevel >= 0 THEN nh.level := baseLevel + level - minLevel END;
  nh.attr := hattr; nh.next := contents;
  NEW(d); d.kind := A.Div; d.attr := dattr; d.blocks := nh; d.next := NIL;
  RETURN d
END Section;

(* The blocks of the list b, divided into sections (makeSections' go) *)
PROCEDURE Go(b: A.Block): A.Block;
  VAR out: A.Blocks; next, x, inner, contents, last: A.Block; h: A.HeaderBlk;
    d, nd, id: A.DivBlk;
BEGIN
  A.InitBlocks(out);
  WHILE b # NIL DO
    IF b IS A.HeaderBlk THEN
      h := b(A.HeaderBlk);
      (* the section's contents: up to a header of the same or a lower level *)
      contents := h.next; last := NIL; x := contents;
      WHILE (x # NIL) & ~HeaderLtEq(h.level, x) DO last := x; x := x.next END;
      next := x;
      IF last = NIL THEN contents := NIL ELSE last.next := NIL END;
      A.AddBlock(out, Section(h, contents));
      b := next
    ELSIF b IS A.DivBlk THEN
      d := b(A.DivBlk); next := b.next;
      NEW(nd); nd^ := d^; nd.next := NIL;
      IF SectionDiv(d) THEN
        inner := Go(d.blocks);
        IF (inner # NIL) & (inner.next = NIL) & (inner IS A.DivBlk) THEN
          id := inner(A.DivBlk);
          IF (d.attr = NIL) OR (Ropes.Length(d.attr.id) = 0)
             OR (id.attr = NIL) OR (Ropes.Length(id.attr.id) = 0)
             OR Ropes.Equal(d.attr.id, id.attr.id) THEN
            nd.attr := CombineAttr(id.attr, d.attr); nd.blocks := id.blocks
          ELSE nd.blocks := inner
          END
        ELSE nd.blocks := inner
        END
      ELSE nd.blocks := Go(d.blocks)
      END;
      A.AddBlock(out, nd);
      b := next
    ELSE
      next := b.next; b.next := NIL;
      A.AddBlock(out, b);
      b := next
    END
  END;
  RETURN out.first
END Go;

(* The blocks b divided into sections, as pandoc's makeSections divides
   them: each header, with the blocks after it up to the next header of
   the same or a lower level, becomes a Div with the class "section"
   and the header's id, classes and attributes; with numbering, an
   attribute "number" holds its section number. If base >= 0, the top
   sections' headers get level base, and those below them follow. The
   list b is used up. *)
PROCEDURE MakeSections*(number: BOOLEAN; base: INTEGER; b: A.Block): A.Block;
  VAR w: LevelWalker;
BEGIN
  NEW(w); w.min := 99;
  b := A.WalkBlocks(w, b);
  minLevel := w.min;
  numbering := number; baseLevel := base; lastLen := 0;
  RETURN Go(b)
END MakeSections;

END PdShared.
