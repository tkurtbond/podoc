MODULE PdFilters;
(* PdFilters: the user's Lua filters, built in (Phase 13). Each does what
   its filter in ~/.pandoc/filters or the Lost-Worlds project does, run
   as pandoc runs a Lua filter (PdAst.WalkDoc):

   subs            replaces text in every Str, from the metadata map
                   "substitutions" (decision 5)
   strip-comments  removes every paragraph that starts with "%"
   general         the Div, Table and Span rules of general.lua
   toc-columns     a two-column ConTeXt table of contents
   combine-docs    one document from the files of the metadata list
                   "combine"

   What the Lua filters write to standard output or standard error,
   these write to standard error. A filter that fails ends podoc with
   pandoc's status for a failed filter, 83. *)

IMPORT Ropes, PdIO, PdSource, PdMarkdown, A := PdAst, PdShared;

CONST
  TabStop = 4;

TYPE
  Rope = Ropes.Rope;

  (* A substitution: key replaced by value *)
  Sub = POINTER TO SubDesc;
  SubDesc = RECORD
    key, value: Rope;
    next: Sub
  END;

  SubsWalker = POINTER TO SubsWalkerDesc;
  SubsWalkerDesc = RECORD (A.WalkerDesc)
    subs: Sub
  END;

  StripWalker = POINTER TO StripWalkerDesc;
  StripWalkerDesc = RECORD (A.WalkerDesc) END;

  GeneralWalker = POINTER TO GeneralWalkerDesc;
  GeneralWalkerDesc = RECORD (A.WalkerDesc)
    format: ARRAY 32 OF CHAR;
    colorSeen: BOOLEAN
  END;

  (* combine-docs: shifts and renames the headers of one file *)
  HeaderWalker = POINTER TO HeaderWalkerDesc;
  HeaderWalkerDesc = RECORD (A.WalkerDesc)
    shift: INTEGER;
    stem: Rope
  END;

VAR
  filterName: ARRAY 4096 OF CHAR; (* the filter running, for errors *)

(* Errors and messages *)

(* Ends podoc as pandoc ends for a failed filter: a message naming the
   filter, then msg, then status 83. *)
PROCEDURE Fail(a, b, c: ARRAY OF CHAR);
BEGIN
  PdIO.Message3("Error running filter '", filterName, "':");
  PdIO.Message3(a, b, c);
  PdIO.Exit(PdIO.FilterError)
END Fail;

(* The text of the metadata value v, as pandoc.utils.stringify gives
   it *)
PROCEDURE StringifyMeta(v: A.MetaValue): Rope;
  VAR r: Rope; it: A.MetaItem; e: A.MetaEntry;
BEGIN
  r := NIL;
  WITH
    v: A.MetaStringV DO r := v.s
  | v: A.MetaInlinesV DO r := PdShared.Stringify(v.inlines)
  | v: A.MetaBlocksV DO r := PdShared.StringifyBlocks(v.blocks)
  | v: A.MetaBoolV DO
      IF v.b THEN r := A.S("true") ELSE r := A.S("false") END
  | v: A.MetaListV DO
      it := v.items;
      WHILE it # NIL DO r := Ropes.Cat(r, StringifyMeta(it.value)); it := it.next END
  | v: A.MetaMapV DO
      e := v.entries;
      WHILE e # NIL DO r := Ropes.Cat(r, StringifyMeta(e.value)); e := e.next END
  ELSE
  END;
  RETURN r
END StringifyMeta;

(* subs *)

(* Whether key is in text at p *)
PROCEDURE At(text: Rope; p, tlen: LONGINT; key: Rope; klen: LONGINT): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  IF p + klen > tlen THEN RETURN FALSE END;
  i := 0;
  WHILE (i < klen) & (Ropes.Fetch(text, p + i) = Ropes.Fetch(key, i)) DO INC(i) END;
  RETURN i = klen
END At;

(* text with every key in it, left to right, replaced by value *)
PROCEDURE Replace(text, key, value: Rope): Rope;
  VAR r: Rope; p, start, tlen, klen: LONGINT; found: BOOLEAN;
BEGIN
  tlen := Ropes.Length(text); klen := Ropes.Length(key);
  r := NIL; start := 0; p := 0; found := FALSE;
  WHILE p < tlen DO
    IF At(text, p, tlen, key, klen) THEN
      r := Ropes.Cat(r, Ropes.Substring(text, start, p - start));
      r := Ropes.Cat(r, value);
      INC(p, klen); start := p; found := TRUE
    ELSE
      INC(p)
    END
  END;
  IF ~found THEN RETURN text END;
  RETURN Ropes.Cat(r, Ropes.Substring(text, start, tlen - start))
END Replace;

PROCEDURE (w: SubsWalker) Inline*(i: A.Inline): A.Inline;
  VAR s: Sub;
BEGIN
  IF i.kind = A.Str THEN
    s := w.subs;
    WHILE s # NIL DO
      i(A.StrInl).text := Replace(i(A.StrInl).text, s.key, s.value);
      s := s.next
    END
  END;
  RETURN i
END Inline;

(* subs.lua: replaces, in every Str of d, its metadata included, each
   key of the metadata map "substitutions" with its value, stringified,
   the keys taken in turn in the map's order *)
PROCEDURE Subs*(d: A.Doc; name: ARRAY OF CHAR);
  VAR w: SubsWalker; v: A.MetaValue; e: A.MetaEntry; s, last: Sub;
BEGIN
  COPY(name, filterName);
  v := A.GetMeta(d.meta, "substitutions");
  IF (v = NIL) OR ~(v IS A.MetaMapV) THEN
    Fail("no substitutions: give them as the metadata map ",
'"substitutions", usually with --metadata-file=substitutions.yaml', "")
  END;
  NEW(w); w.subs := NIL; last := NIL;
  e := v(A.MetaMapV).entries;
  WHILE e # NIL DO
    IF Ropes.Length(e.key) > 0 THEN
      NEW(s); s.key := e.key; s.value := StringifyMeta(e.value); s.next := NIL;
      IF last = NIL THEN w.subs := s ELSE last.next := s END;
      last := s
    END;
    e := e.next
  END;
  A.WalkDoc(w, d)
END Subs;

(* strip-comments *)

PROCEDURE (w: StripWalker) Block*(b: A.Block): A.Block;
  VAR i: A.Inline;
BEGIN
  IF (b.kind = A.Para) OR (b.kind = A.Plain) THEN
    i := b(A.InlinesBlk).inlines;
    IF (i # NIL) & (i.kind = A.Str) & (Ropes.Length(i(A.StrInl).text) > 0)
       & (Ropes.Fetch(i(A.StrInl).text, 0) = "%") THEN
      RETURN NIL
    END
  END;
  RETURN b
END Block;

(* strip-comments.lua: removes every Para and Plain of d whose first
   inline is a Str that starts with "%" *)
PROCEDURE StripComments*(d: A.Doc);
  VAR w: StripWalker;
BEGIN
  NEW(w); A.WalkDoc(w, d)
END StripComments;

(* general *)

(* A raw block of the format; "|" in text stands for a new line *)
PROCEDURE Raw(format, text: ARRAY OF CHAR): A.Block;
  VAR t: ARRAY 256 OF CHAR; i: INTEGER;
BEGIN
  COPY(text, t); i := 0;
  WHILE t[i] # 0X DO
    IF t[i] = "|" THEN t[i] := 0AX END;
    INC(i)
  END;
  RETURN A.NewRawBlock(A.S(format), A.S(t))
END Raw;

(* Appends s to t *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR);
  VAR i, j: INTEGER;
BEGIN
  i := 0; WHILE t[i] # 0X DO INC(i) END;
  j := 0;
  WHILE (s[j] # 0X) & (i < LEN(t) - 1) DO t[i] := s[j]; INC(i); INC(j) END;
  t[i] := 0X
END Append;

(* The list of the block b between the raw blocks before and after, of
   the writer's format *)
PROCEDURE Around(w: GeneralWalker; before, after: ARRAY OF CHAR; b: A.Block): A.Block;
  VAR first: A.Block;
BEGIN
  first := Raw(w.format, before);
  first.next := b;
  b.next := Raw(w.format, after);
  RETURN first
END Around;

PROCEDURE (w: GeneralWalker) Block*(b: A.Block): A.Block;
  VAR a: A.Attr;
BEGIN
  IF b.kind = A.Div THEN
    a := b(A.DivBlk).attr;
    IF A.HasClass(a, "for-format") THEN
      IF ~A.HasClass(a, w.format) THEN
        PdIO.Note('Something is missing here in format "', w.format, '".');
        RETURN NIL
      ELSE
        PdIO.Note('Has something here in format "', w.format, '".')
      END
    ELSIF A.HasClass(a, "box") THEN
      IF w.format = "ms" THEN
        RETURN Around(w, ".sp 0.2v|.B1", ".sp 0.2v|.B2|.sp 0.2v", b)
      ELSIF w.format = "context" THEN
        RETURN Around(w,
          "\startframedtext[width=broad,rulethickness=0.75pt,offset=3pt,aligned=yes]",
          "\stopframedtext{}", b)
      ELSIF w.format = "html" THEN
        RETURN Around(w, '<div style="border:solid">', "</div>", b)
      END
    ELSIF A.HasClass(a, "keep") THEN
      IF w.format = "ms" THEN RETURN Around(w, ".KS|", ".KE|", b) END
    END
  ELSIF (b.kind = A.Table) & (w.format = "ms") THEN
    RETURN Around(w, ".na|", ".ad|", b)
  END;
  RETURN b
END Block;

(* Puts the raw inlines before and after, of the writer's format, around
   the content of the span s *)
PROCEDURE Wrap(w: GeneralWalker; s: A.SpanInl; before, after: ARRAY OF CHAR);
  VAR first: A.Inline;
BEGIN
  first := A.NewRawInline(A.S(w.format), A.S(before));
  first.next := s.content;
  IF s.content = NIL THEN s.content := first
  ELSE s.content := first; first := A.LastInline(first)
  END;
  first.next := A.NewRawInline(A.S(w.format), A.S(after))
END Wrap;

(* The message general.lua writes for what a format does not do *)
PROCEDURE Unimplemented(w: GeneralWalker; what: ARRAY OF CHAR);
BEGIN
  PdIO.Note('Format "', w.format, what)
END Unimplemented;

(* A colour span: \m[colour] for ms, \color[colour]{ for ConTeXt and a
   span of style "color:Colour;" for HTML *)
PROCEDURE Color(w: GeneralWalker; s: A.SpanInl; ms, cap: ARRAY OF CHAR);
  VAR t: ARRAY 64 OF CHAR;
BEGIN
  IF w.format = "ms" THEN
    IF ~w.colorSeen THEN
      w.colorSeen := TRUE;
      PdIO.Note('Format "', w.format, '" requires .color in a template.')
    END;
    COPY("\m[", t); Append(ms, t); Append("]", t);
    Wrap(w, s, t, "\m[]")
  ELSIF w.format = "context" THEN
    COPY("\color[", t); Append(ms, t); Append("]{", t);
    Wrap(w, s, t, "}")
  ELSIF w.format = "html" THEN
    COPY('<span style="color:', t); Append(cap, t); Append(';">', t);
    Wrap(w, s, t, "</span>")
  ELSE
    COPY('" ', t); Append(ms, t); Append(" unimplemented.", t);
    Unimplemented(w, t)
  END
END Color;

PROCEDURE (w: GeneralWalker) Inline*(i: A.Inline): A.Inline;
  VAR s: A.SpanInl; a: A.Attr;
BEGIN
  IF i.kind # A.Span THEN RETURN i END;
  s := i(A.SpanInl); a := s.attr;
  IF A.HasClass(a, "title-ref") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\fI", "\fP")
    ELSIF w.format = "context" THEN Wrap(w, s, "{\it ", "}")
    ELSIF w.format = "html" THEN Wrap(w, s, "<cite>", "</cite>")
    ELSE Unimplemented(w, '" title-ref unimplemented.')
    END
  ELSIF A.HasClass(a, "skill") OR A.HasClass(a, "att") OR A.HasClass(a, "spell")
     OR A.HasClass(a, "power") OR A.HasClass(a, "edge") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\S'15'", "\S'0'")
    ELSIF w.format = "context" THEN Wrap(w, s, "{\it ", "}")
    ELSIF w.format = "html" THEN Wrap(w, s, "<i>", "</i>")
    ELSE Unimplemented(w, '" skill, att, spell, power, edge unimplemented.')
    END
  ELSIF A.HasClass(a, "name") OR A.HasClass(a, "place") OR A.HasClass(a, "money")
     OR A.HasClass(a, "room") OR A.HasClass(a, "item") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\fB", "\fP")
    ELSIF w.format = "context" THEN Wrap(w, s, "{\bf ", "}")
    ELSIF w.format = "html" THEN Wrap(w, s, "<b>", "</b>")
    ELSE Unimplemented(w, '" name, money, room unimplemented.')
    END
  ELSIF A.HasClass(a, "bi") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\f[BI]", "\fP")
    ELSIF w.format = "context" THEN Wrap(w, s, "{\bi ", "}")
    ELSIF w.format = "html" THEN Wrap(w, s, "<b><i>", "</i></b>")
    ELSE Unimplemented(w, '" bi unimplemented.')
    END
  ELSIF A.HasClass(a, "red") THEN Color(w, s, "red", "Red")
  ELSIF A.HasClass(a, "green") THEN Color(w, s, "green", "Green")
  ELSIF A.HasClass(a, "blue") THEN Color(w, s, "blue", "Blue")
  ELSIF A.HasClass(a, "file") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\F[C]", "\F[]")
    ELSIF w.format = "html" THEN Wrap(w, s, "<code>", "</code>")
    ELSE Unimplemented(w, '" file unimplemented.')
    END
  ELSIF A.HasClass(a, "cmd") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\f[CB]", "\fP")
    ELSIF w.format = "html" THEN Wrap(w, s, "<b><code>", "</code></b>")
    ELSE Unimplemented(w, '" file unimplemented.')
    END
  ELSIF A.HasClass(a, "app") THEN
    IF w.format = "ms" THEN Wrap(w, s, "\f[BI]", "\fP")
    ELSIF w.format = "context" THEN
      PdIO.Note("Hit app in context", "", "");
      Wrap(w, s, "{\bi ", "}")
    ELSIF w.format = "html" THEN Wrap(w, s, "<b><i>", "</i></b>")
    ELSE Unimplemented(w, '" file unimplemented.')
    END
  END;
  RETURN i
END Inline;

(* general.lua, for the writer format, as Lua's FORMAT names it (html,
   html5, ms, context, json, markdown): Divs of class for-format that do not have
   the format as a class are removed, Divs of class box and keep and
   Tables are put between raw blocks, and Spans of the classes
   general.lua knows have their content put between raw inlines, as
   general.lua does for the format. *)
PROCEDURE General*(d: A.Doc; format: ARRAY OF CHAR);
  VAR w: GeneralWalker;
BEGIN
  NEW(w); COPY(format, w.format); w.colorSeen := FALSE;
  A.WalkDoc(w, d)
END General;

(* toc-columns *)

(* toc-columns.lua: puts the raw ConTeXt block of a two-column table of
   contents first in d, or second when d has no title in its metadata
   and starts with a level-1 header *)
PROCEDURE TocColumns*(d: A.Doc);
  VAR b: A.Block; t: A.MetaValue; nl: ARRAY 2 OF CHAR; r: Rope;
BEGIN
  nl[0] := 0AX; nl[1] := 0X;
  r := A.S("\blank[big]");
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\switchtobodyfont[8pt]"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("{\tfc\bf Contents}"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\blank[halfline]"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\startcolumns[n=2]"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\placecontent"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\stopcolumns"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\switchtobodyfont[10pt]"));
  r := Ropes.Cat(r, A.S(nl)); r := Ropes.Cat(r, A.S("\blank[big]"));
  r := Ropes.Cat(r, A.S(nl));
  b := A.NewRawBlock(A.S("context"), r);
  t := A.GetMeta(d.meta, "title");
  IF (t # NIL) & (t IS A.MetaBoolV) & ~t(A.MetaBoolV).b THEN t := NIL END;
  IF (t = NIL) & (d.blocks # NIL) & (d.blocks.kind = A.Header)
     & (d.blocks(A.HeaderBlk).level = 1) THEN
    b.next := d.blocks.next; d.blocks.next := b
  ELSE
    b.next := d.blocks; d.blocks := b
  END
END TocColumns;

(* combine-docs *)

PROCEDURE (w: HeaderWalker) Block*(b: A.Block): A.Block;
  VAR h: A.HeaderBlk;
BEGIN
  IF b.kind = A.Header THEN
    h := b(A.HeaderBlk);
    h.level := h.level + w.shift;
    IF h.level > 6 THEN h.level := 6 END;
    IF (h.attr # NIL) & (Ropes.Length(h.attr.id) > 0) THEN
      h.attr.id := Ropes.Cat(Ropes.Cat(w.stem, A.S("-")), h.attr.id)
    END
  END;
  RETURN b
END Block;

PROCEDURE IsAlnum(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9") OR (ch >= "A") & (ch <= "Z")
    OR (ch >= "a") & (ch <= "z")
END IsAlnum;

(* The stem of the file name path, as combine-docs.lua's pattern
   ([^/]+)%.%w+$ takes it: its last component without a final
   extension of letters and digits; path itself when there is none *)
PROCEDURE Stem(path: Rope): Rope;
  VAR n, e, s: LONGINT;
BEGIN
  n := Ropes.Length(path); e := n;
  WHILE (e > 0) & IsAlnum(Ropes.Fetch(path, e - 1)) DO DEC(e) END;
  IF (e = n) OR (e = 0) OR (Ropes.Fetch(path, e - 1) # ".") THEN RETURN path END;
  DEC(e); s := e;
  WHILE (s > 0) & (Ropes.Fetch(path, s - 1) # "/") DO DEC(s) END;
  IF s = e THEN RETURN path END;
  RETURN Ropes.Substring(path, s, e - s)
END Stem;

(* The title made from the stem: its words, between "-" and "_", each
   with its first byte in upper case, joined by spaces *)
PROCEDURE TitleFromStem(stem: Rope): A.Inline;
  VAR r: Rope; i, n: LONGINT; ch: CHAR; start, inWord: BOOLEAN;
BEGIN
  r := NIL; n := Ropes.Length(stem); inWord := FALSE; start := TRUE;
  FOR i := 0 TO n - 1 DO
    ch := Ropes.Fetch(stem, i);
    IF (ch = "-") OR (ch = "_") THEN inWord := FALSE
    ELSE
      IF ~inWord THEN
        IF ~start THEN r := Ropes.AppendChar(r, " ") END;
        start := FALSE; inWord := TRUE;
        IF (ch >= "a") & (ch <= "z") THEN ch := CHR(ORD(ch) - 32) END
      END;
      r := Ropes.AppendChar(r, ch)
    END
  END;
  RETURN A.NewStr(r)
END TitleFromStem;

(* The blocks of the file path, normalized as combine-docs.lua does:
   one level-1 header, its title, then its other headers shifted below
   it, their identifiers prefixed with the file's stem *)
PROCEDURE Normalize(path: Rope): A.Block;
  VAR name: ARRAY 4096 OF CHAR; text: PdIO.Text; len: LONGINT; d: A.Doc;
    stem: Rope; b, h, prev: A.Block; t: A.MetaValue; title: A.Inline;
    h1, min: INTEGER; w: HeaderWalker;
BEGIN
  Ropes.ToString(path, name);
  IF ~PdIO.Exists(name) THEN Fail(name, ": No such file or directory", "") END;
  text := NIL; len := 0;
  PdSource.AddFile(text, len, name, TabStop);
  d := PdMarkdown.Read(text, len, TabStop);
  stem := Stem(path);
  h1 := 0; b := d.blocks;
  WHILE b # NIL DO
    IF (b.kind = A.Header) & (b(A.HeaderBlk).level = 1) THEN INC(h1) END;
    b := b.next
  END;
  t := A.GetMeta(d.meta, "title");
  IF (t # NIL) & (t IS A.MetaBoolV) & ~t(A.MetaBoolV).b THEN t := NIL END;
  IF t # NIL THEN
    IF t IS A.MetaInlinesV THEN title := t(A.MetaInlinesV).inlines
    ELSE title := A.NewStr(StringifyMeta(t))
    END
  ELSIF (h1 = 1) & (d.blocks.kind = A.Header) & (d.blocks(A.HeaderBlk).level = 1) THEN
    title := d.blocks(A.HeaderBlk).inlines;
    d.blocks := d.blocks.next
  ELSE
    title := TitleFromStem(stem)
  END;
  min := 0; b := d.blocks;
  WHILE b # NIL DO
    IF (b.kind = A.Header) & ((min = 0) OR (b(A.HeaderBlk).level < min)) THEN
      min := b(A.HeaderBlk).level
    END;
    b := b.next
  END;
  NEW(w); w.stem := stem;
  IF min = 0 THEN w.shift := 0 ELSE w.shift := 2 - min END;
  prev := d.blocks;
  b := A.WalkBlocks(w, prev);
  h := A.NewHeader(1, A.NewAttr(stem), title);
  h.next := b;
  RETURN h
END Normalize;

(* combine-docs.lua: replaces the blocks of d with those of the files the
   metadata list "combine" names (a single value names one file), each
   normalized, a raw ConTeXt \page between them; "combine" is removed
   from the metadata *)
PROCEDURE CombineDocs*(d: A.Doc; name: ARRAY OF CHAR);
  VAR v: A.MetaValue; it: A.MetaItem; l: A.Blocks; first: BOOLEAN;

  PROCEDURE Add(v: A.MetaValue);
  BEGIN
    IF ~first THEN A.AddBlock(l, Raw("context", "\page")) END;
    first := FALSE;
    A.AddBlock(l, Normalize(StringifyMeta(v)))
  END Add;

BEGIN
  COPY(name, filterName);
  v := A.GetMeta(d.meta, "combine");
  IF v = NIL THEN
    Fail("combine-docs.lua: no files listed in the ", '"combine" metadata field', "")
  END;
  A.InitBlocks(l); first := TRUE;
  IF v IS A.MetaListV THEN
    it := v(A.MetaListV).items;
    WHILE it # NIL DO Add(it.value); it := it.next END
  ELSE
    Add(v)
  END;
  A.DeleteMeta(d.meta, "combine");
  d.blocks := l.first
END CombineDocs;

END PdFilters.
