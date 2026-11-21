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
   and links; Chop breaks a rendered line as a block does. Widths count East Asian wide and full-width characters as
   two and combining marks as none, as doclayout's realLength does. *)

IMPORT SYSTEM, Ropes, Utf8, Unicode, W := PdWidth, PdIO;

CONST
  text = 0; prefixed = 1; beforeNonBlank = 2; flush = 3;
  breakingSpace = 4; afterBreak = 5; carriageReturn = 6; newLine = 7;
  blankLines = 8; concat = 9;

TYPE
  Doc* = POINTER TO DocDesc;
  DocDesc = RECORD
    kind: SYSTEM.INT8;
    n: SYSTEM.INT32; (* text: width; blankLines: how many *)
    s: Ropes.Rope; (* text; prefixed: the prefix; afterBreak: the text *)
    a, b: Doc (* concat: a then b; prefixed, beforeNonBlank, flush: a *)
  END;

  Stack = POINTER TO ARRAY OF Doc;

  (* Whether a text is an ordered list marker, for AvoidBadWraps *)
  Marker* = PROCEDURE (t: Ropes.Rope): BOOLEAN;

VAR
  (* the render state *)
  out: PdIO.Text; outLen: LONGINT;
  prefix, prefixTrimmed: Ropes.Rope; prefixLen: LONGINT;
  usePrefix: BOOLEAN;
  lineLength: LONGINT; (* 0: no wrapping *)
  column, newlines: LONGINT;

  buf: PdIO.Text; (* for Width *)

  (* the breaks, shared, as a Doc is never changed once made *)
  space, cr, nl, blank1: Doc;

TYPE
  (* the render state, saved by Render *)
  State = RECORD
    out: PdIO.Text; outLen: LONGINT;
    prefix, prefixTrimmed: Ropes.Rope; prefixLen: LONGINT;
    usePrefix: BOOLEAN; lineLength, column, newlines: LONGINT
  END;

PROCEDURE Save(VAR st: State);
BEGIN
  st.out := out; st.outLen := outLen;
  st.prefix := prefix; st.prefixTrimmed := prefixTrimmed; st.prefixLen := prefixLen;
  st.usePrefix := usePrefix; st.lineLength := lineLength;
  st.column := column; st.newlines := newlines
END Save;

PROCEDURE Restore(VAR st: State);
BEGIN
  out := st.out; outLen := st.outLen;
  prefix := st.prefix; prefixTrimmed := st.prefixTrimmed; prefixLen := st.prefixLen;
  usePrefix := st.usePrefix; lineLength := st.lineLength;
  column := st.column; newlines := st.newlines
END Restore;

(* Widths *)

(* The width of s[i .. n-1], as doclayout's realLength *)
PROCEDURE CharsWidth(VAR s: ARRAY OF CHAR; i, n: LONGINT): LONGINT;
  VAR q: LONGINT; r: Utf8.Rune; st: W.State;
BEGIN
  W.Start(st);
  WHILE i < n DO
    IF ORD(s[i]) < 80H THEN r := ORD(s[i]); INC(i)
    ELSE
      q := i;
      IF ~Utf8.Decode(s, q, r) OR (q <= i) OR (q > n) THEN
        r := 0FFFDH; q := i + 1
      END;
      i := q
    END;
    W.Add(st, r)
  END;
  RETURN W.Total(st)
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

(* The width of one character, r, as doclayout's charWidth *)
PROCEDURE RuneWidth(r: Utf8.Rune): LONGINT;
BEGIN
  IF r < 80H THEN
    IF (r >= 20H) & (r # 7FH) THEN RETURN 1 ELSE RETURN 0 END
  END;
  RETURN W.Width(r)
END RuneWidth;

(* The lines of r, rendered text, as doclayout's chop gives them to a
   block of width n: a final empty line dropped, and each line wider
   than n broken into pieces of at most n columns, counted from the
   line's end, so that the first piece is the shortest *)
PROCEDURE Chop*(r: Ropes.Rope; n: LONGINT): Ropes.Rope;
  VAR s: PdIO.Text; len, i, j, start, q, w, k, np: LONGINT; res: Ropes.Rope;
    starts, widths, cuts: POINTER TO ARRAY OF LONGINT; ru: Utf8.Rune;

  PROCEDURE Add(a, b: LONGINT; first: BOOLEAN);
  BEGIN
    IF ~first THEN res := Ropes.Cat(res, Ropes.FromChar(0AX)) END;
    IF b > a THEN res := Ropes.Cat(res, Ropes.FromSubchars(s^, a, b - a)) END
  END Add;

BEGIN
  len := Ropes.Length(r);
  IF len = 0 THEN RETURN NIL END;
  NEW(s, len + 1); Ropes.Blit(r, 0, s^, 0, len); s[len] := 0X;
  IF s[len - 1] = 0AX THEN DEC(len) END; (* the final empty line *)
  res := NIL; start := 0; i := 0;
  WHILE start <= len DO
    j := start; WHILE (j < len) & (s[j] # 0AX) DO INC(j) END;
    IF CharsWidth(s^, start, j) <= n THEN Add(start, j, start = 0)
    ELSE
      (* the characters' offsets and widths *)
      NEW(starts, j - start + 1); NEW(widths, j - start + 1); NEW(cuts, j - start + 1);
      k := 0; q := start;
      WHILE q < j DO
        starts[k] := q;
        IF ORD(s[q]) < 80H THEN ru := ORD(s[q]); INC(q)
        ELSE
          i := q;
          IF ~Utf8.Decode(s^, i, ru) OR (i <= q) OR (i > j) THEN ru := 0FFFDH; i := q + 1 END;
          q := i
        END;
        widths[k] := RuneWidth(ru); INC(k)
      END;
      (* from the end: a piece starts where adding a character would
         make it wider than n *)
      np := 0; w := 0; i := k - 1;
      WHILE i >= 0 DO
        IF (i < k - 1) & (w + widths[i] > n) THEN cuts[np] := i + 1; INC(np); w := 0 END;
        INC(w, widths[i]); DEC(i)
      END;
      (* the pieces, left to right *)
      q := start;
      WHILE np > 0 DO
        DEC(np); Add(q, starts[cuts[np]], (q = start) & (start = 0)); q := starts[cuts[np]]
      END;
      Add(q, j, (q = start) & (start = 0))
    END;
    start := j + 1
  END;
  RETURN res
END Chop;

(* Making Docs *)

PROCEDURE New(kind: INTEGER): Doc;
  VAR d: Doc;
BEGIN
  NEW(d); d.kind := SYSTEM.VAL(SYSTEM.INT8, kind); d.n := 0; d.s := NIL; d.a := NIL; d.b := NIL;
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
  d := New(text); d.s := s; d.n := SYSTEM.VAL(SYSTEM.INT32, Width(s));
  RETURN d
END Line;

(* x pushed on stack[0 .. sp-1], which grows as needed *)
PROCEDURE Push(VAR stack: Stack; VAR sp: LONGINT; x: Doc);
  VAR t: Stack; i: LONGINT;
BEGIN
  IF sp = LEN(stack^) THEN
    NEW(t, 2 * sp);
    FOR i := 0 TO sp - 1 DO t[i] := stack[i] END;
    stack := t
  END;
  stack[sp] := x; INC(sp)
END Push;

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
  IF Ropes.IndexChar(r, 0AX, 0) < 0 THEN RETURN Line(r) END;
  NEW(parts, 8); np := 0;
  n := Ropes.Length(r); i := 0;
  LOOP
    j := Ropes.IndexChar(r, 0AX, i);
    IF j < 0 THEN
      IF n > i THEN Add(Line(Ropes.Substring(r, i, n - i))) END;
      EXIT
    END;
    IF j > i THEN Add(Line(Ropes.Substring(r, i, j - i))) END;
    Add(nl);
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
  RETURN space
END Space;

(* A carriage return: a new line unless at the start of a line *)
PROCEDURE Cr*(): Doc;
BEGIN
  RETURN cr
END Cr;

(* A new line *)
PROCEDURE NewLine*(): Doc;
BEGIN
  RETURN nl
END NewLine;

(* n blank lines, unless there are that many already *)
PROCEDURE BlankLines*(n: LONGINT): Doc;
  VAR d: Doc;
BEGIN
  IF n = 1 THEN RETURN blank1 END;
  d := New(blankLines); d.n := SYSTEM.VAL(SYSTEM.INT32, n);
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

(* pandoc's avoidBadWraps: in d, a breaking space before a text that
   would start a block if it began a line (">...", a lone "-", "*" or
   "+", "1." or "1)", or, if marker is not NIL, a text for which marker
   is TRUE) becomes part of that text, so that the text cannot begin a
   line. *)
PROCEDURE AvoidBadWraps*(d: Doc; marker: Marker): Doc;
  VAR parts: Stack; np, i: LONGINT; t: Ropes.Rope; n: LONGINT; c: CHAR;
    bad: BOOLEAN; x: Doc;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  FOR i := 0 TO np - 3 DO
    IF (parts[i] # NIL) & (parts[i].kind = breakingSpace) & (parts[i + 1].kind = text)
       & (parts[i + 2].kind = breakingSpace) THEN
      t := parts[i + 1].s; n := Ropes.Length(t);
      c := Ropes.Fetch(t, 0);
      bad := (c = ">")
        OR ((c = "-") OR (c = "*") OR (c = "+")) & (n = 1)
        OR (n = 2) & (c = "1") & ((Ropes.Fetch(t, 1) = ".") OR (Ropes.Fetch(t, 1) = ")"))
        OR (marker # NIL) & marker(t);
      IF bad THEN
        x := New(text); x.s := Ropes.Cat(Ropes.FromChar(" "), t);
        x.n := parts[i + 1].n + 1;
        parts[i] := NIL; parts[i + 1] := x
      END
    END
  END;
  d := NIL;
  i := np;
  WHILE i > 0 DO DEC(i); d := Cat(parts[i], d) END;
  RETURN d
END AvoidBadWraps;

(* d without the blank lines, new lines, carriage returns and breaking
   spaces at its end *)
PROCEDURE Chomp*(d: Doc): Doc;
  VAR stack: Stack; sp: LONGINT; c: Doc;

  (* x, not a concatenation, chomped *)
  PROCEDURE One(x: Doc): Doc;
    VAR y, z: Doc;
  BEGIN
    IF x = NIL THEN RETURN NIL END;
    CASE x.kind OF
      blankLines, newLine, carriageReturn, breakingSpace: RETURN NIL
    | prefixed:
        y := Chomp(x.a);
        IF y = x.a THEN RETURN x END;
        z := New(prefixed); z.s := x.s; z.a := y; RETURN z
    ELSE RETURN x
    END
  END One;

BEGIN
  (* Iterative, as the right spine of a document can be very long: the
     concatenations down to the last part on stack; while the part
     chomps to nothing, the one before it; then the nodes on the path
     rebuilt, those whose right part is unchanged kept *)
  NEW(stack, 64); sp := 0;
  WHILE (d # NIL) & (d.kind = concat) DO Push(stack, sp, d); d := d.b END;
  c := One(d);
  WHILE (c = NIL) & (sp > 0) DO
    DEC(sp); d := stack[sp].a;
    WHILE (d # NIL) & (d.kind = concat) DO Push(stack, sp, d); d := d.b END;
    c := One(d)
  END;
  WHILE sp > 0 DO
    DEC(sp);
    IF c = stack[sp].b THEN c := stack[sp] ELSE c := Cat(stack[sp].a, c) END
  END;
  RETURN c
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
  VAR stack: Stack; sp: LONGINT; c: Doc;
BEGIN
  NEW(stack, 64); sp := 0;
  WHILE (d # NIL) & (d.kind = concat) DO Push(stack, sp, d); d := d.b END;
  IF (d # NIL) & ((d.kind = newLine) OR (d.kind = carriageReturn)) THEN c := NIL ELSE c := d END;
  WHILE sp > 0 DO
    DEC(sp);
    IF c = stack[sp].b THEN c := stack[sp] ELSE c := Cat(stack[sp].a, c) END
  END;
  RETURN c
END RemoveFinalNl;

(* Whether d holds a new line, a carriage return or blank lines outside
   its prefixed, flush and conditional parts (doctemplates' hasNewlines,
   as pandoc's markdown writer uses it) *)
PROCEDURE HasNewlines*(d: Doc): BOOLEAN;
  VAR parts: Stack; np, i: LONGINT;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  FOR i := 0 TO np - 1 DO
    d := parts[i];
    IF (d.kind = newLine) OR (d.kind = carriageReturn) OR (d.kind = blankLines) THEN
      RETURN TRUE
    END
  END;
  RETURN FALSE
END HasNewlines;

(* pandoc's delimited: open, d, close, with the new lines, carriage
   returns, breaking spaces and blank lines at d's start put before open
   and those at its end after close *)
PROCEDURE Delimited*(open, close, d: Doc): Doc;
  VAR parts: Stack; np, i, j: LONGINT;

  PROCEDURE IsWS(x: Doc): BOOLEAN;
  BEGIN
    RETURN (x.kind = newLine) OR (x.kind = carriageReturn)
      OR (x.kind = breakingSpace) OR (x.kind = blankLines)
  END IsWS;

BEGIN
  parts := NIL; Unfold(d, parts, np);
  i := 0; WHILE (i < np) & IsWS(parts[i]) DO INC(i) END;
  j := np; WHILE (j > i) & IsWS(parts[j - 1]) DO DEC(j) END;
  RETURN Cat(Join(parts, 0, i),
    Cat(open, Cat(Join(parts, i, j), Cat(close, Join(parts, j, np)))))
END Delimited;

(* d with f applied to the text of each of its text parts; their widths
   are kept, as Haskell's fmap keeps them *)
PROCEDURE MapText*(d: Doc; f: PROCEDURE (r: Ropes.Rope): Ropes.Rope): Doc;
  VAR parts: Stack; np, i: LONGINT; x, c: Doc;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  FOR i := 0 TO np - 1 DO
    x := parts[i];
    c := New(x.kind); c.n := x.n; c.s := x.s;
    CASE x.kind OF
      text: c.s := f(x.s)
    | prefixed, beforeNonBlank, flush: c.a := MapText(x.a, f)
    ELSE
    END;
    parts[i] := c
  END;
  RETURN Join(parts, 0, np)
END MapText;

(* Whether d is one text part, s its text *)
PROCEDURE SingleText*(d: Doc; VAR s: Ropes.Rope): BOOLEAN;
BEGIN
  s := NIL;
  IF (d # NIL) & (d.kind = text) THEN s := d.s; RETURN TRUE END;
  RETURN FALSE
END SingleText;

(* The text of d's text parts, in order, including those in its
   prefixed, flush and conditional parts (a fold over d's text) *)
PROCEDURE AllText*(d: Doc): Ropes.Rope;
  VAR parts: Stack; np, i: LONGINT; r: Ropes.Rope; x: Doc;
BEGIN
  parts := NIL; Unfold(d, parts, np);
  r := NIL;
  FOR i := 0 TO np - 1 DO
    x := parts[i];
    CASE x.kind OF
      text: r := Ropes.Cat(r, x.s)
    | prefixed, beforeNonBlank, flush: r := Ropes.Cat(r, AllText(x.a))
    ELSE
    END
  END;
  RETURN r
END AllText;

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

(* doclayout's getOffset: l, the longest line so far, and c, the
   current column, after d, laid out without wrapping or, if minimal,
   breaking at every breaking space not at the start of a line *)
PROCEDURE GetOffset(d: Doc; minimal: BOOLEAN; VAR l, c: LONGINT);
  VAR stack, t: Stack; sp, i, l1, c1: LONGINT; rest: Doc;

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
  NEW(stack, 64); sp := 0;
  Push(d);
  WHILE sp > 0 DO
    DEC(sp); d := stack[sp];
    WHILE (d # NIL) & (d.kind = concat) DO Push(d.b); d := d.a END;
    IF d # NIL THEN
      CASE d.kind OF
        text: INC(c, d.n)
      | carriageReturn, newLine, blankLines: IF c > l THEN l := c END; c := 0
      | prefixed:
          l1 := 0; c1 := 0; GetOffset(d.a, minimal, l1, c1);
          IF l1 + Width(d.s) > l THEN l := l1 + Width(d.s) END;
          c := c1 + Width(d.s)
      | beforeNonBlank:
          IF sp > 0 THEN rest := stack[sp - 1] ELSE rest := NIL END;
          IF IsNonBlank(rest) THEN Push(d.a) END
      | flush: Push(d.a)
      | breakingSpace:
          IF minimal & (c > 0) THEN IF c > l THEN l := c END; c := 0
          ELSE INC(c)
          END
      | afterBreak: IF c = 0 THEN INC(c, Width(d.s)) END
      END
    END
  END
END GetOffset;

(* doclayout's offset: the width of d's widest line, unwrapped *)
PROCEDURE Offset*(d: Doc): LONGINT;
  VAR l, c: LONGINT;
BEGIN
  l := 0; c := 0; GetOffset(d, FALSE, l, c);
  IF c > l THEN l := c END;
  RETURN l
END Offset;

(* doclayout's minOffset: the width of d's widest line, broken at every
   breaking space *)
PROCEDURE MinOffset*(d: Doc): LONGINT;
  VAR l, c: LONGINT;
BEGIN
  l := 0; c := 0; GetOffset(d, TRUE, l, c);
  IF c > l THEN l := c END;
  RETURN l
END MinOffset;

(* Rendering

   doclayout flattens a Doc into a list, normalizes the list and renders
   it. Here the parts of a Doc are rendered as they are reached, through
   a Level, which keeps only the parts whose rendering depends on what
   comes after them: the last part, which may yet collapse with the next
   (doclayout's normalize), a breaking space until the next break, and a
   part printed only before something not blank until that something. *)

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

TYPE
  Item = RECORD
    kind: INTEGER;
    n: LONGINT;
    d: Doc (* the part *)
  END;
  Items = POINTER TO ARRAY OF Item;

  (* The parts of one list, a Doc's or a prefixed, flush, beforeNonBlank
     or afterBreak part's, being rendered *)
  Level = RECORD
    stack: Stack; sp: LONGINT; (* the parts still to come *)
    q: Items; qh, qt: LONGINT; (* the parts kept, q[qh .. qt-1] *)
    p: Item; hasP: BOOLEAN; (* the last part, not yet in q *)
    norm: BOOLEAN (* whether the list is normalized *)
  END;

VAR
  (* Levels' arrays, kept for reuse at each depth *)
  stacks: ARRAY 32 OF Stack;
  queues: ARRAY 32 OF Items;
  depth: LONGINT;

  (* the document being written a part at a time *)
  open: Level; isOpen, putAny: BOOLEAN; pending: Doc;
  chompEnd: BOOLEAN; (* Close chomps the end *)
  keep: BOOLEAN; (* the output is held until Finish *)
  inSlot: BOOLEAN; held: Doc; (* between BeginSlot and EndSlot: the last part put *)
  rout: PdIO.Text; (* Render's buffer *)

PROCEDURE IsBreak(kind: INTEGER): BOOLEAN;
BEGIN
  RETURN (kind = breakingSpace) OR (kind = carriageReturn)
    OR (kind = newLine) OR (kind = blankLines)
END IsBreak;

PROCEDURE^ IsVoid(d: Doc): BOOLEAN;

(* Whether the part x, not a concatenation, is left out of a list, as
   doclayout's flatten leaves out an empty prefixed, flush,
   beforeNonBlank or afterBreak part *)
PROCEDURE VoidPart(x: Doc): BOOLEAN;
BEGIN
  CASE x.kind OF
    prefixed, beforeNonBlank, flush: RETURN IsVoid(x.a)
  | afterBreak: RETURN Ropes.Length(x.s) = 0
  ELSE RETURN FALSE
  END
END VoidPart;

(* The first part of d not left out of its list, or NIL *)
PROCEDURE FirstPart(d: Doc): Doc;
  VAR stack: Stack; sp: LONGINT;
BEGIN
  stack := NIL; sp := 0;
  LOOP
    WHILE (d # NIL) & (d.kind = concat) DO
      IF stack = NIL THEN NEW(stack, 16) END;
      Push(stack, sp, d.b); d := d.a
    END;
    IF (d # NIL) & ~VoidPart(d) THEN RETURN d END;
    IF sp = 0 THEN RETURN NIL END;
    DEC(sp); d := stack[sp]
  END
END FirstPart;

(* Whether d flattens to nothing *)
PROCEDURE IsVoid(d: Doc): BOOLEAN;
BEGIN
  RETURN FirstPart(d) = NIL
END IsVoid;

(* doclayout's startsBlank, of a part *)
PROCEDURE StartsBlank(x: Doc): BOOLEAN;
  VAR r: Utf8.Rune; s: ARRAY 8 OF CHAR; i, n: LONGINT;
BEGIN
  CASE x.kind OF
    text:
      n := Ropes.Length(x.s);
      IF n = 0 THEN RETURN FALSE END;
      IF n > 4 THEN n := 4 END;
      Ropes.Blit(x.s, 0, s, 0, n);
      IF ORD(s[0]) < 80H THEN RETURN IsSpaceChar(s[0]) END;
      i := 0;
      IF ~Utf8.Decode(s, i, r) THEN RETURN FALSE END;
      RETURN Unicode.IsSpace(r)
  | prefixed, beforeNonBlank, flush: RETURN StartsBlank(FirstPart(x.a))
  | afterBreak: RETURN StartsBlank(FirstPart(Literal(x.s)))
  ELSE RETURN TRUE
  END
END StartsBlank;

PROCEDURE StartLevel(VAR l: Level; d: Doc; norm: BOOLEAN);
BEGIN
  IF depth < LEN(stacks) THEN
    IF stacks[depth] = NIL THEN NEW(stacks[depth], 64); NEW(queues[depth], 16) END;
    l.stack := stacks[depth]; l.q := queues[depth]
  ELSE NEW(l.stack, 64); NEW(l.q, 16)
  END;
  INC(depth);
  l.sp := 0; l.qh := 0; l.qt := 0; l.hasP := FALSE; l.norm := norm;
  IF d # NIL THEN Push(l.stack, l.sp, d) END
END StartLevel;

PROCEDURE EndLevel(VAR l: Level);
  VAR i: LONGINT;
BEGIN
  DEC(depth);
  IF depth < LEN(stacks) THEN
    (* kept for reuse, but holding no parts *)
    stacks[depth] := l.stack; queues[depth] := l.q;
    FOR i := 0 TO LEN(l.q^) - 1 DO l.q[i].d := NIL END;
    FOR i := 0 TO l.sp - 1 DO l.stack[i] := NIL END
  END
END EndLevel;

(* The next part of l's list, or FALSE at its end *)
PROCEDURE NextPart(VAR l: Level; VAR x: Item): BOOLEAN;
  VAR d: Doc;
BEGIN
  LOOP
    IF l.sp = 0 THEN RETURN FALSE END;
    DEC(l.sp); d := l.stack[l.sp]; l.stack[l.sp] := NIL;
    WHILE d.kind = concat DO Push(l.stack, l.sp, d.b); d := d.a END;
    IF ~VoidPart(d) THEN
      x.kind := d.kind; x.n := d.n; x.d := d;
      RETURN TRUE
    END
  END
END NextPart;

(* x appended to l's queue *)
PROCEDURE Keep(VAR l: Level; VAR x: Item);
  VAR t: Items; i: LONGINT;
BEGIN
  IF l.qt = LEN(l.q^) THEN
    IF l.qh > 0 THEN
      FOR i := l.qh TO l.qt - 1 DO l.q[i - l.qh] := l.q[i]; l.q[i].d := NIL END;
      DEC(l.qt, l.qh); l.qh := 0
    ELSE
      NEW(t, 2 * l.qt);
      FOR i := 0 TO l.qt - 1 DO t[i] := l.q[i] END;
      l.q := t
    END
  END;
  l.q[l.qt] := x; INC(l.qt)
END Keep;

(* Whether the pair p, x collapses, as doclayout's normalize collapses
   it; if so, p becomes what it collapses to *)
PROCEDURE Collapse(VAR p: Item; VAR x: Item): BOOLEAN;
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

PROCEDURE^ RenderDoc(d: Doc; norm: BOOLEAN);

(* Renders the parts at the front of l's queue that can be rendered: all
   of them at the end of the list *)
PROCEDURE Drain(VAR l: Level; atEnd: BOOLEAN);
  VAR i, j, off, k: LONGINT; p, pt: Ropes.Rope; pl: LONGINT; up: BOOLEAN;
    x: Item;
BEGIN
  WHILE l.qh < l.qt DO
    x := l.q[l.qh];
    CASE x.kind OF
      breakingSpace:
        (* the width of the text up to the next break *)
        i := l.qh; WHILE (i + 1 < l.qt) & (l.q[i + 1].kind = breakingSpace) DO INC(i) END;
        j := i + 1; off := 0;
        WHILE (j < l.qt) & ~IsBreak(l.q[j].kind) DO
          IF l.q[j].kind = text THEN INC(off, l.q[j].n) END;
          INC(j)
        END;
        IF (j = l.qt) & ~atEnd THEN RETURN END;
        l.qh := i;
        IF (lineLength > 0) & (column + 1 + off > lineLength) THEN Newline
        ELSIF column > 0 THEN Outp(1, Ropes.FromChar(" "))
        END
    | beforeNonBlank:
        IF (l.qh + 1 = l.qt) & ~atEnd THEN RETURN END;
        IF (l.qh + 1 < l.qt) & ~StartsBlank(l.q[l.qh + 1].d) THEN
          RenderDoc(x.d.a, TRUE)
        END
    | text: Outp(x.n, x.d.s)
    | prefixed:
        p := prefix; pt := prefixTrimmed; pl := prefixLen;
        SetPrefix(Ropes.Cat(prefix, x.d.s));
        RenderDoc(x.d.a, TRUE);
        prefix := p; prefixTrimmed := pt; prefixLen := pl
    | flush:
        up := usePrefix; usePrefix := FALSE;
        RenderDoc(x.d.a, TRUE);
        usePrefix := up
    | blankLines:
        IF newlines <= x.n THEN
          k := 1 + x.n - newlines;
          FOR i := 1 TO k DO Newline END
        END
    | carriageReturn: IF newlines = 0 THEN Newline END
    | newLine: Newline
    | afterBreak: IF newlines > 0 THEN RenderDoc(Literal(x.d.s), FALSE) END
    END;
    l.q[l.qh].d := NIL; INC(l.qh)
  END;
  l.qh := 0; l.qt := 0
END Drain;

(* Renders d's list, normalized if norm *)
PROCEDURE RenderDoc(d: Doc; norm: BOOLEAN);
  VAR l: Level; x: Item;
BEGIN
  StartLevel(l, d, norm);
  WHILE NextPart(l, x) DO
    IF ~norm THEN Keep(l, x)
    ELSIF ~l.hasP THEN l.p := x; l.hasP := TRUE
    ELSIF ~Collapse(l.p, x) THEN Keep(l, l.p); l.p := x
    END;
    Drain(l, FALSE)
  END;
  IF l.hasP THEN
    (* normalize's end: new lines or blank lines become a carriage
       return, and a breaking space is dropped *)
    IF (l.p.kind = newLine) OR (l.p.kind = blankLines) THEN
      l.p.kind := carriageReturn; l.p.n := 0; Keep(l, l.p)
    ELSIF l.p.kind # breakingSpace THEN Keep(l, l.p)
    END;
    l.p.d := NIL
  END;
  Drain(l, TRUE);
  EndLevel(l)
END RenderDoc;

(* Lays d out into out[0 .. outLen-1] *)
PROCEDURE Lay(d: Doc; width: LONGINT);
BEGIN
  outLen := 0;
  prefix := NIL; prefixTrimmed := NIL; prefixLen := 0;
  usePrefix := TRUE; lineLength := width;
  column := 0; newlines := 2;
  RenderDoc(d, TRUE)
END Lay;

(* d laid out as text, wrapped at width columns, or not wrapped if
   width is 0. It may be called between Open and Close. *)
PROCEDURE Render*(d: Doc; width: LONGINT): Ropes.Rope;
  VAR r: Ropes.Rope; st: State;
BEGIN
  Save(st); out := rout;
  Lay(d, width);
  IF outLen = 0 THEN r := NIL ELSE r := Ropes.FromSubchars(out^, 0, outLen) END;
  rout := out; Restore(st);
  RETURN r
END Render;

(* Render, written to PdIO's output *)
PROCEDURE Write*(d: Doc; width: LONGINT);
BEGIN
  Lay(d, width);
  IF outLen > 0 THEN PdIO.WriteChars(out^, 0, outLen) END
END Write;

(* Writing a document a part at a time

   Open, then Put or PutAbove for each part in turn, then Close, writes
   what Write(Chomp(d), width) writes, d being the parts joined with Cat
   or Above, but without the whole of d ever being built. Each part is
   laid out when the next one, not chomped to nothing, is put; the last
   such part, with any after it, is chomped and laid out by Close.

   OpenWhole, the parts, then Close or Finish, writes what Write(d,
   width) writes, unchomped: a template rendered with a variable's value
   given a part at a time, between BeginSlot and EndSlot. *)

(* d's parts laid out through the open level *)
PROCEDURE Feed(d: Doc);
  VAR x: Item;
BEGIN
  IF d = NIL THEN RETURN END;
  Push(open.stack, open.sp, d);
  WHILE NextPart(open, x) DO
    IF ~open.hasP THEN open.p := x; open.hasP := TRUE
    ELSIF ~Collapse(open.p, x) THEN Keep(open, open.p); open.p := x
    END;
    Drain(open, FALSE)
  END;
  IF ~keep & (outLen >= 10000H) THEN PdIO.WriteChars(out^, 0, outLen); outLen := 0 END
END Feed;

PROCEDURE Start(width: LONGINT);
BEGIN
  ASSERT(~isOpen);
  outLen := 0;
  prefix := NIL; prefixTrimmed := NIL; prefixLen := 0;
  usePrefix := TRUE; lineLength := width;
  column := 0; newlines := 2;
  StartLevel(open, NIL, TRUE);
  pending := NIL; putAny := FALSE; inSlot := FALSE; held := NIL; isOpen := TRUE
END Start;

(* Starts writing a document laid out at width columns, or not wrapped
   if width is 0 *)
PROCEDURE Open*(width: LONGINT);
BEGIN
  Start(width); chompEnd := TRUE; keep := FALSE
END Open;

(* Starts writing a document, as Open does, but not chomped at the
   end. If hold, nothing is written until Finish. *)
PROCEDURE OpenWhole*(width: LONGINT; hold: BOOLEAN);
BEGIN
  Start(width); chompEnd := FALSE; keep := hold
END OpenWhole;

PROCEDURE Put1(x: Doc);
BEGIN
  IF Chomp(x) = NIL THEN pending := Cat(pending, x)
  ELSE Feed(pending); pending := x
  END
END Put1;

(* x, the next part of the document Open started, as Cat joins it *)
PROCEDURE Put*(x: Doc);
BEGIN
  ASSERT(isOpen);
  IF x = NIL THEN RETURN END;
  IF inSlot THEN
    IF held # NIL THEN Put1(held) END;
    held := x
  ELSE Put1(x)
  END
END Put;

(* x, the next part of the document Open started, as Above joins it to
   the parts put by PutAbove before it *)
PROCEDURE PutAbove*(x: Doc);
BEGIN
  IF x = NIL THEN RETURN END;
  IF putAny THEN Put(cr) END;
  Put(x); putAny := TRUE
END PutAbove;

(* Starts a variable's value, as a template interpolates it: the parts
   put until EndSlot, joined as Put and PutAbove join them, as one
   value, its final new line removed (RemoveFinalNl) *)
PROCEDURE BeginSlot*;
BEGIN
  ASSERT(isOpen & ~inSlot);
  inSlot := TRUE; held := NIL; putAny := FALSE
END BeginSlot;

(* Ends the value BeginSlot started *)
PROCEDURE EndSlot*;
BEGIN
  ASSERT(inSlot);
  inSlot := FALSE;
  IF held # NIL THEN Put1(RemoveFinalNl(held)); held := NIL END;
  putAny := FALSE
END EndSlot;

(* Ends the document Open or OpenWhole started, written to PdIO's
   output if write, else, if OpenWhole held it, discarded *)
PROCEDURE Finish*(write: BOOLEAN);
BEGIN
  ASSERT(isOpen & ~inSlot);
  IF chompEnd THEN Feed(Chomp(pending)) ELSE Feed(pending) END;
  pending := NIL;
  IF open.hasP THEN
    IF (open.p.kind = newLine) OR (open.p.kind = blankLines) THEN
      open.p.kind := carriageReturn; open.p.n := 0; Keep(open, open.p)
    ELSIF open.p.kind # breakingSpace THEN Keep(open, open.p)
    END;
    open.p.d := NIL
  END;
  Drain(open, TRUE);
  EndLevel(open); isOpen := FALSE;
  IF write & (outLen > 0) THEN PdIO.WriteChars(out^, 0, outLen) END;
  outLen := 0; keep := FALSE
END Finish;

(* Ends the document Open started, written to PdIO's output *)
PROCEDURE Close*;
BEGIN
  Finish(TRUE)
END Close;

BEGIN
  out := NIL; outLen := 0; buf := NIL; rout := NIL;
  isOpen := FALSE; pending := NIL; depth := 0;
  chompEnd := TRUE; keep := FALSE; inSlot := FALSE; held := NIL;
  space := New(breakingSpace); cr := New(carriageReturn); nl := New(newLine);
  blank1 := New(blankLines); blank1.n := 1
END PdLayout.
