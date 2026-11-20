MODULE PdLayout;
(* PdLayout: documents laid out as pandoc's doclayout library (0.5)
   lays them out. The writers and the templates build their output as
   a Doc, and Render or Write turns it into text.

   A Doc is text, line breaks of three kinds (a new line; a carriage
   return, a new line unless at the start of one; blank lines, as many
   as are asked for unless there are already that many), breaking
   spaces (a space, or a new line where a line would be too long),
   prefixed and flush parts, and parts printed only before something
   that is not blank or only at the start of a line, joined by
   concatenation. NIL is the empty Doc. Runs of breaks and spaces
   collapse as doclayout's normalize collapses them, so that, say, a
   blank line after a carriage return gives one blank line.

   Not yet: doclayout's blocks (lblock, cblock, rblock, vfill), styles
   and links. Widths count East Asian wide and full-width characters as
   two and combining marks as none, as doclayout's realLength does. *)

IMPORT Ropes, Utf8, Unicode, PdIO;

CONST
  text = 0; prefixed = 1; beforeNonBlank = 2; flush = 3;
  breakingSpace = 4; afterBreak = 5; carriageReturn = 6; newLine = 7;
  blankLines = 8; concat = 9;

TYPE
  Doc* = POINTER TO DocDesc;
  DocDesc = RECORD
    kind: INTEGER;
    n: LONGINT; (* text: width; blankLines: how many *)
    s: Ropes.Rope; (* text; prefixed: the prefix; afterBreak: the text *)
    a, b: Doc (* concat: a then b; prefixed, beforeNonBlank, flush: a *)
  END;

  (* doclayout's FlatDoc: a Doc flattened into a list *)
  Flat = POINTER TO FlatDesc;
  FlatDesc = RECORD
    kind: INTEGER;
    n: LONGINT;
    s: Ropes.Rope;
    sub: Flat; (* prefixed, beforeNonBlank, flush, afterBreak *)
    next: Flat
  END;

  Stack = POINTER TO ARRAY OF Doc;

VAR
  (* the render state *)
  out: PdIO.Text; outLen: LONGINT;
  prefix, prefixTrimmed: Ropes.Rope; prefixLen: LONGINT;
  usePrefix: BOOLEAN;
  lineLength: LONGINT; (* 0: no wrapping *)
  column, newlines: LONGINT;

  buf: PdIO.Text; (* for Width *)

(* Widths *)

(* The width of s[i .. n-1] *)
PROCEDURE CharsWidth(VAR s: ARRAY OF CHAR; i, n: LONGINT): LONGINT;
  VAR w, q: LONGINT; r: Utf8.Rune; eaw, c: INTEGER;
BEGIN
  w := 0;
  WHILE i < n DO
    IF ORD(s[i]) < 80H THEN INC(w); INC(i)
    ELSE
      q := i;
      IF ~Utf8.Decode(s, q, r) OR (q <= i) OR (q > n) THEN
        r := 0FFFDH; q := i + 1
      END;
      i := q;
      IF r < 300H THEN INC(w)
      ELSE
        eaw := Unicode.EastAsianWidth(r);
        IF (eaw = Unicode.widthW) OR (eaw = Unicode.widthF) THEN INC(w, 2)
        ELSE
          c := Unicode.Category(r);
          IF (c # Unicode.Mn) & (c # Unicode.Me) THEN INC(w) END
        END
      END
    END
  END;
  RETURN w
END CharsWidth;

(* doclayout's realLength: the width of r in columns *)
PROCEDURE Width*(r: Ropes.Rope): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := Ropes.Length(r);
  IF n = 0 THEN RETURN 0 END;
  PdIO.Reserve(buf, 0, n);
  Ropes.Blit(r, 0, buf^, 0, n);
  RETURN CharsWidth(buf^, 0, n)
END Width;

(* Making Docs *)

PROCEDURE New(kind: INTEGER): Doc;
  VAR d: Doc;
BEGIN
  NEW(d); d.kind := kind; d.n := 0; d.s := NIL; d.a := NIL; d.b := NIL;
  RETURN d
END New;

(* a <> b *)
PROCEDURE Cat*(a, b: Doc): Doc;
  VAR d: Doc;
BEGIN
  IF b = NIL THEN RETURN a
  ELSIF a = NIL THEN RETURN b
  END;
  d := New(concat); d.a := a; d.b := b;
  RETURN d
END Cat;

(* a <> b <> c, as Haskell's infixr <> groups it *)
PROCEDURE Cat3*(a, b, c: Doc): Doc;
BEGIN
  RETURN Cat(a, Cat(b, c))
END Cat3;

(* Whether d is empty *)
PROCEDURE IsEmpty*(d: Doc): BOOLEAN;
BEGIN
  RETURN d = NIL
END IsEmpty;

(* One line of text, s, which holds no new line *)
PROCEDURE Line(s: Ropes.Rope): Doc;
  VAR d: Doc;
BEGIN
  IF Ropes.Length(s) = 0 THEN RETURN NIL END;
  d := New(text); d.s := s; d.n := Width(s);
  RETURN d
END Line;

(* The parts of d that are not concatenations, left to right, in
   parts[0 .. np-1] *)
PROCEDURE Unfold(d: Doc; VAR parts: Stack; VAR np: LONGINT);
  VAR stack, t: Stack; sp, i: LONGINT;

  PROCEDURE Push(x: Doc);
  BEGIN
    IF sp = LEN(stack^) THEN
      NEW(t, 2 * sp);
      FOR i := 0 TO sp - 1 DO t[i] := stack[i] END;
      stack := t
    END;
    stack[sp] := x; INC(sp)
  END Push;

BEGIN
  NEW(stack, 64); sp := 0; np := 0;
  IF parts = NIL THEN NEW(parts, 64) END;
  Push(d);
  WHILE sp > 0 DO
    DEC(sp); d := stack[sp];
    WHILE (d # NIL) & (d.kind = concat) DO Push(d.b); d := d.a END;
    IF d # NIL THEN
      IF np = LEN(parts^) THEN
        NEW(t, 2 * np);
        FOR i := 0 TO np - 1 DO t[i] := parts[i] END;
        parts := t
      END;
      parts[np] := d; INC(np)
    END
  END
END Unfold;

(* The parts parts[from .. to-1] joined, right to left *)
PROCEDURE Join(parts: Stack; from, to: LONGINT): Doc;
  VAR d: Doc;
BEGIN
  d := NIL;
  WHILE to > from DO DEC(to); d := Cat(parts[to], d) END;
  RETURN d
END Join;

(* doclayout's literal: the text r, each new line in it a NewLine *)
PROCEDURE Literal*(r: Ropes.Rope): Doc;
  VAR parts, t: Stack; np, i, j, n, k: LONGINT;

  PROCEDURE Add(x: Doc);
  BEGIN
    IF x # NIL THEN
      IF np = LEN(parts^) THEN
        NEW(t, 2 * np);
        FOR k := 0 TO np - 1 DO t[k] := parts[k] END;
        parts := t
      END;
      parts[np] := x; INC(np)
    END
  END Add;

BEGIN
  NEW(parts, 8); np := 0;
  n := Ropes.Length(r); i := 0;
  LOOP
    j := Ropes.IndexChar(r, 0AX, i);
    IF j < 0 THEN
      IF n > i THEN Add(Line(Ropes.Substring(r, i, n - i))) END;
      EXIT
    END;
    IF j > i THEN Add(Line(Ropes.Substring(r, i, j - i))) END;
    Add(New(newLine));
    i := j + 1
  END;
  RETURN Join(parts, 0, np)
END Literal;

(* Literal for a string *)
PROCEDURE Text*(s: ARRAY OF CHAR): Doc;
BEGIN
  RETURN Literal(Ropes.FromString(s))
END Text;

(* Literal for s[start .. start+len-1] *)
PROCEDURE Chars*(VAR s: ARRAY OF CHAR; start, len: LONGINT): Doc;
BEGIN
  RETURN Literal(Ropes.FromSubchars(s, start, len))
END Chars;

(* A character *)
PROCEDURE Char*(ch: CHAR): Doc;
BEGIN
  RETURN Literal(Ropes.FromChar(ch))
END Char;

(* A breaking space: a space, or a new line where a line would be too
   long *)
PROCEDURE Space*(): Doc;
BEGIN
  RETURN New(breakingSpace)
END Space;

(* A carriage return: a new line unless at the start of a line *)
PROCEDURE Cr*(): Doc;
BEGIN
  RETURN New(carriageReturn)
END Cr;

(* A new line *)
PROCEDURE NewLine*(): Doc;
BEGIN
  RETURN New(newLine)
END NewLine;

(* n blank lines, unless there are that many already *)
PROCEDURE BlankLines*(n: LONGINT): Doc;
  VAR d: Doc;
BEGIN
  d := New(blankLines); d.n := n;
  RETURN d
END BlankLines;

(* A blank line, unless there is one already *)
PROCEDURE BlankLine*(): Doc;
BEGIN
  RETURN BlankLines(1)
END BlankLine;

(* a <+> b: a and b with a breaking space between, unless one is empty *)
PROCEDURE Hsep*(a, b: Doc): Doc;
BEGIN
  IF a = NIL THEN RETURN b ELSIF b = NIL THEN RETURN a END;
  RETURN Cat(a, Cat(Space(), b))
END Hsep;

(* a $$ b: a above b *)
PROCEDURE Above*(a, b: Doc): Doc;
BEGIN
  IF a = NIL THEN RETURN b ELSIF b = NIL THEN RETURN a END;
  RETURN Cat(a, Cat(Cr(), b))
END Above;

(* a $+$ b: a above b, with a blank line between *)
PROCEDURE AboveBlank*(a, b: Doc): Doc;
BEGIN
  IF a = NIL THEN RETURN b ELSIF b = NIL THEN RETURN a END;
  RETURN Cat(a, Cat(BlankLine(), b))
END AboveBlank;

(* d with each line prefixed with pref (but the first, if d does not
   start a line); a blank line gets pref without its trailing spaces *)
PROCEDURE PrefixedRope*(pref: Ropes.Rope; d: Doc): Doc;
  VAR p: Doc;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  p := New(prefixed); p.s := pref; p.a := d;
  RETURN p
END PrefixedRope;

(* PrefixedRope for a string *)
PROCEDURE Prefixed*(pref: ARRAY OF CHAR; d: Doc): Doc;
BEGIN
  RETURN PrefixedRope(Ropes.FromString(pref), d)
END Prefixed;

(* d indented by n spaces *)
PROCEDURE Nest*(n: LONGINT; d: Doc): Doc;
BEGIN
  IF n <= 0 THEN RETURN PrefixedRope(NIL, d) END;
  RETURN PrefixedRope(Ropes.Make(n, " "), d)
END Nest;

(* start, then d with every line but the first indented by n *)
PROCEDURE Hang*(n: LONGINT; start, d: Doc): Doc;
BEGIN
  RETURN Cat(start, Nest(n, d))
END Hang;

(* d flush against the left margin, without the prefixes around it *)
PROCEDURE Flush*(d: Doc): Doc;
  VAR f: Doc;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  f := New(flush); f.a := d;
  RETURN f
END Flush;

(* d, unless what follows it is blank *)
PROCEDURE BeforeNonBlank*(d: Doc): Doc;
  VAR f: Doc;
BEGIN
  f := New(beforeNonBlank); f.a := d;
  RETURN f
END BeforeNonBlank;

(* s, printed only at the start of a line *)
PROCEDURE AfterBreak*(s: ARRAY OF CHAR): Doc;
  VAR f: Doc;
BEGIN
  f := New(afterBreak); f.s := Ropes.FromString(s);
  RETURN f
END AfterBreak;

(* d with its breaking spaces made plain spaces, so that it is not
   wrapped (outside its prefixed and flush parts) *)
PROCEDURE NoWrap*(d: Doc): Doc;
  VAR parts: Stack; np, i: LONGINT;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  FOR i := 0 TO np - 1 DO
    IF parts[i].kind = breakingSpace THEN parts[i] := Line(Ropes.FromChar(" ")) END
  END;
  RETURN Join(parts, 0, np)
END NoWrap;

(* d without the blank lines, new lines, carriage returns and breaking
   spaces at its end *)
PROCEDURE Chomp*(d: Doc): Doc;
  VAR c: Doc;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  CASE d.kind OF
    blankLines, newLine, carriageReturn, breakingSpace: RETURN NIL
  | prefixed: c := New(prefixed); c.s := d.s; c.a := Chomp(d.a); RETURN c
  | concat:
      IF (d.a # NIL) & (d.a.kind = concat) THEN
        RETURN Chomp(Cat(d.a.a, Cat(d.a.b, d.b)))
      END;
      c := Chomp(d.b);
      IF c = NIL THEN RETURN Chomp(d.a) END;
      RETURN Cat(d.a, c)
  ELSE RETURN d
  END
END Chomp;

(* d without the blank lines and new lines at its start *)
PROCEDURE Nestle*(d: Doc): Doc;
BEGIN
  LOOP
    IF d = NIL THEN RETURN NIL END;
    CASE d.kind OF
      blankLines, newLine: RETURN NIL
    | concat:
        IF (d.a # NIL) & (d.a.kind = concat) THEN
          d := Cat(d.a.a, Cat(d.a.b, d.b))
        ELSIF (d.a # NIL) & ((d.a.kind = blankLines) OR (d.a.kind = newLine)
                             OR (d.a.kind = carriageReturn)) THEN
          d := d.b
        ELSE RETURN d
        END
    ELSE RETURN d
    END
  END
END Nestle;

(* doclayout's removeFinalNl, as doctemplates uses it: d without a new
   line or carriage return at the end of its right spine *)
PROCEDURE RemoveFinalNl*(d: Doc): Doc;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  IF (d.kind = newLine) OR (d.kind = carriageReturn) THEN RETURN NIL
  ELSIF d.kind = concat THEN RETURN Cat(d.a, RemoveFinalNl(d.b))
  END;
  RETURN d
END RemoveFinalNl;

(* d with f applied to the text of each of its text parts; their widths
   are kept, as Haskell's fmap keeps them *)
PROCEDURE MapText*(d: Doc; f: PROCEDURE (r: Ropes.Rope): Ropes.Rope): Doc;
  VAR c: Doc;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  c := New(d.kind); c.n := d.n; c.s := d.s;
  CASE d.kind OF
    text: c.s := f(d.s)
  | concat: c.a := MapText(d.a, f); c.b := MapText(d.b, f)
  | prefixed, beforeNonBlank, flush: c.a := MapText(d.a, f)
  ELSE
  END;
  RETURN c
END MapText;

(* Whether the text r ends a sentence, as pandoc's splitSentences
   sees it: it ends in . ! or ? and is not a single upper case letter
   before that; or it ends in ) ] " or U+201D after . or ! or after a ?
   that does not follow a single upper case letter (Haskell's
   precedence, kept) *)
PROCEDURE SentenceEnd(r: Ropes.Rope): BOOLEAN;
  VAR n, i: LONGINT; ch, d: CHAR; rune: Utf8.Rune;

  (* Whether buf[0 .. e-1] is one upper case letter *)
  PROCEDURE Initial(e: LONGINT): BOOLEAN;
    VAR j: LONGINT; c: INTEGER;
  BEGIN
    IF e <= 0 THEN RETURN FALSE END;
    j := 0;
    IF ~Utf8.Decode(buf^, j, rune) OR (j # e) THEN RETURN FALSE END;
    c := Unicode.Category(rune);
    RETURN (c = Unicode.Lu) OR (c = Unicode.Lt)
  END Initial;

BEGIN
  n := Ropes.Length(r);
  IF n = 0 THEN RETURN FALSE END;
  PdIO.Reserve(buf, 0, n + 1);
  Ropes.Blit(r, 0, buf^, 0, n); buf[n] := 0X;
  ch := buf[n - 1]; i := n - 1;
  IF (ch = ".") OR (ch = "!") OR (ch = "?") THEN RETURN ~Initial(i)
  ELSIF (ch = ")") OR (ch = "]") OR (ch = 22X) OR (ch = 9DX) & (n >= 3)
        & (buf[n - 2] = 80X) & (buf[n - 3] = 0E2X) THEN
    IF ch = 9DX THEN i := n - 3 END;
    IF i = 0 THEN RETURN FALSE END;
    d := buf[i - 1];
    RETURN (d = ".") OR (d = "!") OR (d = "?") & ~Initial(i - 1)
  END;
  RETURN FALSE
END SentenceEnd;

(* pandoc's splitSentences (Text.Pandoc.Writers.Shared): d with the
   breaking space after each text that ends a sentence (and an
   after-break part between them) made a new line, so that roff sees
   one sentence a line. Only the top-level concatenation of d is
   looked at. *)
PROCEDURE SplitSentences*(d: Doc): Doc;
  VAR parts: Stack; np, i, j: LONGINT;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  i := 0; j := 0;
  WHILE i < np DO
    IF (parts[i].kind = text) & (i + 2 < np) & (parts[i + 1].kind = afterBreak)
       & (parts[i + 2].kind = breakingSpace) & SentenceEnd(parts[i].s) THEN
      parts[j] := parts[i]; parts[j + 1] := New(newLine); INC(j, 2); INC(i, 3)
    ELSIF (parts[i].kind = text) & (i + 1 < np) & (parts[i + 1].kind = breakingSpace)
          & SentenceEnd(parts[i].s) THEN
      parts[j] := parts[i]; parts[j + 1] := New(newLine); INC(j, 2); INC(i, 2)
    ELSE parts[j] := parts[i]; INC(j); INC(i)
    END
  END;
  RETURN Join(parts, 0, j)
END SplitSentences;

(* Columns *)

(* Whether d starts with text (doclayout's isNonBlank) *)
PROCEDURE IsNonBlank(d: Doc): BOOLEAN;
BEGIN
  WHILE (d # NIL) & ((d.kind = beforeNonBlank) OR (d.kind = flush)
                     OR (d.kind = concat)) DO
    d := d.a
  END;
  RETURN (d # NIL) & (d.kind = text)
END IsNonBlank;

(* doclayout's updateColumn: the column after d, laid out from column
   k without wrapping *)
PROCEDURE UpdateColumn*(d: Doc; k: LONGINT): LONGINT;
  VAR stack, t: Stack; sp, i, c: LONGINT; rest: Doc;

  PROCEDURE Push(x: Doc);
  BEGIN
    IF sp = LEN(stack^) THEN
      NEW(t, 2 * sp);
      FOR i := 0 TO sp - 1 DO t[i] := stack[i] END;
      stack := t
    END;
    stack[sp] := x; INC(sp)
  END Push;

BEGIN
  NEW(stack, 64); sp := 0; c := k;
  Push(d);
  WHILE sp > 0 DO
    DEC(sp); d := stack[sp];
    WHILE (d # NIL) & (d.kind = concat) DO Push(d.b); d := d.a END;
    IF d # NIL THEN
      CASE d.kind OF
        text: INC(c, d.n)
      | carriageReturn, newLine, blankLines: c := 0
      | prefixed: c := UpdateColumn(d.a, 0) + Width(d.s)
      | beforeNonBlank:
          (* what follows, up to the end of the enclosing Doc *)
          IF sp > 0 THEN rest := stack[sp - 1] ELSE rest := NIL END;
          IF IsNonBlank(rest) THEN Push(d.a) END
      | flush: Push(d.a)
      | breakingSpace: INC(c)
      | afterBreak: IF c = 0 THEN INC(c, Width(d.s)) END
      END
    END
  END;
  RETURN c
END UpdateColumn;

(* Flattening *)

PROCEDURE NewFlat(kind: INTEGER; n: LONGINT; s: Ropes.Rope; sub: Flat): Flat;
  VAR f: Flat;
BEGIN
  NEW(f); f.kind := kind; f.n := n; f.s := s; f.sub := sub; f.next := NIL;
  RETURN f
END NewFlat;

(* doclayout's flatten: d as a list *)
PROCEDURE Flatten(d: Doc): Flat;
  VAR parts: Stack; np, i: LONGINT; head, tail, f, sub: Flat; x: Doc;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  head := NIL; tail := NIL;
  FOR i := 0 TO np - 1 DO
    x := parts[i]; f := NIL;
    CASE x.kind OF
      text: f := NewFlat(text, x.n, x.s, NIL)
    | prefixed, beforeNonBlank, flush:
        sub := Flatten(x.a);
        IF sub # NIL THEN f := NewFlat(x.kind, 0, x.s, sub) END
    | afterBreak:
        sub := Flatten(Literal(x.s));
        IF sub # NIL THEN f := NewFlat(afterBreak, 0, NIL, sub) END
    | breakingSpace, carriageReturn, newLine, blankLines:
        f := NewFlat(x.kind, x.n, NIL, NIL)
    END;
    IF f # NIL THEN
      IF head = NIL THEN head := f ELSE tail.next := f END;
      tail := f
    END
  END;
  RETURN head
END Flatten;

(* Whether the pair p, x collapses, as doclayout's normalize collapses
   it; if so, p becomes what it collapses to *)
PROCEDURE Collapse(VAR p: Flat; x: Flat): BOOLEAN;
BEGIN
  CASE p.kind OF
    blankLines:
      IF x.kind = blankLines THEN
        IF x.n > p.n THEN p.n := x.n END;
        RETURN TRUE
      END;
      RETURN (x.kind = breakingSpace) OR (x.kind = carriageReturn)
             OR (x.kind = newLine)
  | newLine:
      IF x.kind = blankLines THEN p := x; RETURN TRUE END;
      RETURN (x.kind = breakingSpace) OR (x.kind = carriageReturn)
  | carriageReturn:
      IF x.kind = blankLines THEN p := x; RETURN TRUE END;
      RETURN (x.kind = carriageReturn) OR (x.kind = breakingSpace)
  | breakingSpace:
      IF (x.kind = carriageReturn) OR (x.kind = newLine)
         OR (x.kind = blankLines) OR (x.kind = breakingSpace) THEN
        p := x; RETURN TRUE
      END;
      RETURN FALSE
  ELSE RETURN FALSE
  END
END Collapse;

(* doclayout's normalize: the list l with its runs of breaks and spaces
   collapsed; a new line or blank lines at the end become a carriage
   return, and a breaking space there is dropped *)
PROCEDURE Normalize(l: Flat): Flat;
  VAR head, tail, p, x, next: Flat;
BEGIN
  head := NIL; tail := NIL; p := NIL;
  WHILE l # NIL DO
    next := l.next; x := l; x.next := NIL;
    IF p = NIL THEN p := x
    ELSIF ~Collapse(p, x) THEN
      IF head = NIL THEN head := p ELSE tail.next := p END;
      tail := p; p := x
    END;
    l := next
  END;
  IF p # NIL THEN
    IF (p.kind = newLine) OR (p.kind = blankLines) THEN
      p := NewFlat(carriageReturn, 0, NIL, NIL)
    ELSIF p.kind = breakingSpace THEN p := NIL
    END;
    IF p # NIL THEN
      IF head = NIL THEN head := p ELSE tail.next := p END
    END
  END;
  RETURN head
END Normalize;

(* Rendering *)

PROCEDURE Emit(r: Ropes.Rope);
  VAR n: LONGINT;
BEGIN
  n := Ropes.Length(r);
  IF n > 0 THEN
    PdIO.Reserve(out, outLen, outLen + n);
    Ropes.Blit(r, 0, out^, outLen, n);
    INC(outLen, n)
  END
END Emit;

PROCEDURE SetPrefix(p: Ropes.Rope);
BEGIN
  prefix := p;
  prefixTrimmed := Ropes.TrimRight(p);
  prefixLen := Width(p)
END SetPrefix;

PROCEDURE Newline;
BEGIN
  IF (column = 0) & usePrefix & (Ropes.Length(prefix) > 0) THEN
    Emit(prefixTrimmed)
  END;
  PdIO.Reserve(out, outLen, outLen + 1);
  out[outLen] := 0AX; INC(outLen);
  column := 0; INC(newlines)
END Newline;

PROCEDURE Outp(off: LONGINT; s: Ropes.Rope);
BEGIN
  IF (column = 0) & usePrefix & (Ropes.Length(prefix) > 0) THEN
    Emit(prefix); Emit(s);
    column := prefixLen + off
  ELSE
    Emit(s); INC(column, off)
  END;
  newlines := 0
END Outp;

PROCEDURE IsSpaceChar(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch >= 09X) & (ch <= 0DX)
END IsSpaceChar;

(* doclayout's startsBlank *)
PROCEDURE StartsBlank(f: Flat): BOOLEAN;
  VAR r: Utf8.Rune; s: ARRAY 8 OF CHAR; i, n: LONGINT;
BEGIN
  CASE f.kind OF
    text:
      n := Ropes.Length(f.s);
      IF n > 4 THEN n := 4 END;
      Ropes.Blit(f.s, 0, s, 0, n);
      IF ORD(s[0]) < 80H THEN RETURN IsSpaceChar(s[0]) END;
      i := 0;
      IF ~Utf8.Decode(s, i, r) THEN RETURN FALSE END;
      RETURN Unicode.IsSpace(r)
  | prefixed, beforeNonBlank, flush, afterBreak: RETURN StartsBlank(f.sub)
  ELSE RETURN TRUE
  END
END StartsBlank;

PROCEDURE^ RenderList(f: Flat);

PROCEDURE RenderOne(VAR f: Flat);
  VAR p, pt: Ropes.Rope; pl, off, i, k: LONGINT; up: BOOLEAN; g: Flat;
BEGIN
  CASE f.kind OF
    text: Outp(f.n, f.s)
  | prefixed:
      p := prefix; pt := prefixTrimmed; pl := prefixLen;
      SetPrefix(Ropes.Cat(prefix, f.s));
      RenderList(Normalize(f.sub));
      prefix := p; prefixTrimmed := pt; prefixLen := pl
  | flush:
      up := usePrefix; usePrefix := FALSE;
      RenderList(Normalize(f.sub));
      usePrefix := up
  | beforeNonBlank:
      IF (f.next # NIL) & ~StartsBlank(f.next) THEN
        RenderList(Normalize(f.sub))
      END
  | blankLines:
      IF newlines <= f.n THEN
        k := 1 + f.n - newlines;
        FOR i := 1 TO k DO Newline END
      END
  | carriageReturn: IF newlines = 0 THEN Newline END
  | newLine: Newline
  | breakingSpace:
      WHILE (f.next # NIL) & (f.next.kind = breakingSpace) DO f := f.next END;
      off := 0; g := f.next;
      WHILE (g # NIL) & (g.kind # breakingSpace) & (g.kind # carriageReturn)
            & (g.kind # newLine) & (g.kind # blankLines) DO
        IF g.kind = text THEN INC(off, g.n) END;
        g := g.next
      END;
      IF (lineLength > 0) & (column + 1 + off > lineLength) THEN Newline
      ELSIF column > 0 THEN Outp(1, Ropes.FromChar(" "))
      END
  | afterBreak: IF newlines > 0 THEN RenderList(f.sub) END
  END
END RenderOne;

PROCEDURE RenderList(f: Flat);
BEGIN
  WHILE f # NIL DO RenderOne(f); f := f.next END
END RenderList;

(* Lays d out into out[0 .. outLen-1] *)
PROCEDURE Lay(d: Doc; width: LONGINT);
BEGIN
  outLen := 0;
  prefix := NIL; prefixTrimmed := NIL; prefixLen := 0;
  usePrefix := TRUE; lineLength := width;
  column := 0; newlines := 2;
  RenderList(Normalize(Flatten(d)))
END Lay;

(* d laid out as text, wrapped at width columns, or not wrapped if
   width is 0 *)
PROCEDURE Render*(d: Doc; width: LONGINT): Ropes.Rope;
  VAR r: Ropes.Rope;
BEGIN
  Lay(d, width);
  IF outLen = 0 THEN r := NIL ELSE r := Ropes.FromSubchars(out^, 0, outLen) END;
  RETURN r
END Render;

(* Render, written to PdIO's output *)
PROCEDURE Write*(d: Doc; width: LONGINT);
BEGIN
  Lay(d, width);
  IF outLen > 0 THEN PdIO.WriteChars(out^, 0, outLen) END
END Write;

BEGIN
  out := NIL; outLen := 0; buf := NIL
END PdLayout.
