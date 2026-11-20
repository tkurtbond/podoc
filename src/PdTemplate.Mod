MODULE PdTemplate;
(* PdTemplate: pandoc's templates, as the doctemplates library (0.11)
   reads and renders them.

   Compile reads a template: literal text; $var$ and ${var}, a variable
   with its parts joined by "." and pipes after "/"; $if(var)$ ...
   $elseif(var)$ ... $else$ ... $endif$; $for(var)$ ... $sep$ ...
   $endfor$; $var[sep]$, $var:partial()$ and $partial()$; $^$, which
   nests what follows at its column; $~$, which turns reflowing on and
   off; $$ for a dollar sign; and comments from $-- to the end of the
   line. A variable alone on its line, with a value of several lines,
   has them all indented to its column. Directives alone on their
   lines take their lines with them.

   Render renders a compiled template with a context, a map of values,
   into a PdLayout.Doc. A value is text (a Doc), a list, a map or a
   boolean; NIL is null.

   The pipes are uppercase, lowercase, pairs, length, alpha, roman,
   reverse, first, rest, last, allbutlast, chomp and nowrap. left, right
   and center are read but not supported: Compile fails on them.

   A template that cannot be read gives Compile's error message, which
   names its place as doctemplates does, "name" (line l, column c), but
   says only what was unexpected there. *)

IMPORT Ropes, Utf8, Unicode, Utf8Strings, PdIO, L := PdLayout;

CONST
  (* value kinds *)
  SimpleV* = 0; ListV* = 1; MapV* = 2; BoolV* = 3;

  (* template node kinds *)
  literal = 0; interpolate = 1; conditional = 2; iterate = 3; nested = 4;
  partial = 5;

  (* pipes *)
  toPairs = 0; toUpper = 1; toLower = 2; toLength = 3; reverse = 4;
  firstItem = 5; lastItem = 6; rest = 7; allButLast = 8; chomp = 9;
  toAlpha = 10; toRoman = 11; noWrap = 12; block = 13;

  MaxNesting = 50;

TYPE
  Value* = POINTER TO ValueDesc;
  Entry* = POINTER TO EntryDesc;
  ValueDesc* = RECORD
    kind-: INTEGER;
    doc-: L.Doc; (* SimpleV *)
    b-: BOOLEAN; (* BoolV *)
    items-, last: Entry (* ListV, MapV: maps in order of their keys *)
  END;
  EntryDesc* = RECORD
    key-: Ropes.Rope; (* MapV *)
    value-: Value;
    next-: Entry
  END;

  Pipe = POINTER TO PipeDesc;
  PipeDesc = RECORD
    kind: INTEGER;
    next: Pipe
  END;

  Part = POINTER TO PartDesc;
  PartDesc = RECORD
    name: Ropes.Rope;
    next: Part
  END;

  Variable = RECORD
    parts: Part;
    pipes: Pipe
  END;

  Template* = POINTER TO NodeDesc;
  NodeDesc = RECORD
    kind: INTEGER;
    doc: L.Doc; (* literal *)
    var: Variable; (* interpolate, conditional, iterate *)
    pipes: Pipe; (* partial *)
    a, b: Template; (* then and else; body and separator; contents *)
    next: Template
  END;

  (* Reads the partial named path into t[0 .. len-1]; FALSE if it cannot *)
  PartialReader* = PROCEDURE (path: ARRAY OF CHAR; VAR t: PdIO.Text;
                              VAR len: LONGINT): BOOLEAN;

  Name = POINTER TO ARRAY OF CHAR;

  Pos = RECORD
    file, line, col: LONGINT
  END;

  (* The parser's state, as Parsec's: where it is, and doctemplates'
     PState *)
  State = RECORD
    i: LONGINT; (* in src *)
    p: Pos;
    first: Pos; (* firstNonspace *)
    nestedCol: LONGINT; (* 0: Nothing *)
    inside, breaking: BOOLEAN
  END;

VAR
  readPartial*: PartialReader;

  (* the input *)
  src: PdIO.Text; len: LONGINT;
  srcName: Name; (* the template path *)
  files: LONGINT; (* file numbers given out *)
  st: State;
  nesting: INTEGER; (* partialNesting *)

  (* the furthest failure *)
  errSet: BOOLEAN;
  errFile, errI, errLine, errCol: LONGINT;
  errName: Name;
  errMsg: ARRAY 256 OF CHAR;
  error-: ARRAY 1024 OF CHAR; (* what went wrong, when Compile fails *)

  column: LONGINT; (* the render state *)
  buf, buf2: PdIO.Text;

(* Values *)

PROCEDURE NewValue(kind: INTEGER): Value;
  VAR v: Value;
BEGIN
  NEW(v); v.kind := kind; v.doc := NIL; v.b := FALSE; v.items := NIL; v.last := NIL;
  RETURN v
END NewValue;

(* Text, the Doc d *)
PROCEDURE NewSimple*(d: L.Doc): Value;
  VAR v: Value;
BEGIN
  v := NewValue(SimpleV); v.doc := d;
  RETURN v
END NewSimple;

(* Text, the string s *)
PROCEDURE NewString*(s: ARRAY OF CHAR): Value;
BEGIN
  RETURN NewSimple(L.Text(s))
END NewString;

(* A boolean *)
PROCEDURE NewBool*(b: BOOLEAN): Value;
  VAR v: Value;
BEGIN
  v := NewValue(BoolV); v.b := b;
  RETURN v
END NewBool;

(* An empty list *)
PROCEDURE NewList*(): Value;
BEGIN
  RETURN NewValue(ListV)
END NewList;

(* An empty map *)
PROCEDURE NewMap*(): Value;
BEGIN
  RETURN NewValue(MapV)
END NewMap;

PROCEDURE NewEntry(key: Ropes.Rope; v: Value): Entry;
  VAR e: Entry;
BEGIN
  NEW(e); e.key := key; e.value := v; e.next := NIL;
  RETURN e
END NewEntry;

(* Adds v to the end of the list l *)
PROCEDURE Add*(l: Value; v: Value);
  VAR e: Entry;
BEGIN
  ASSERT(l.kind = ListV);
  e := NewEntry(NIL, v);
  IF l.items = NIL THEN l.items := e ELSE l.last.next := e END;
  l.last := e
END Add;

(* Sets key to v in the map m *)
PROCEDURE PutRope*(m: Value; key: Ropes.Rope; v: Value);
  VAR e, p, n: Entry; c: INTEGER;
BEGIN
  ASSERT(m.kind = MapV);
  p := NIL; e := m.items; c := -1;
  WHILE (e # NIL) & (c < 0) DO
    c := Ropes.Compare(e.key, key);
    IF c < 0 THEN p := e; e := e.next END
  END;
  IF (e # NIL) & (c = 0) THEN e.value := v
  ELSE
    n := NewEntry(key, v); n.next := e;
    IF p = NIL THEN m.items := n ELSE p.next := n END
  END
END PutRope;

(* PutRope for a string key *)
PROCEDURE Put*(m: Value; key: ARRAY OF CHAR; v: Value);
BEGIN
  PutRope(m, Ropes.FromString(key), v)
END Put;

(* The value of key in the map m, NIL if it has none *)
PROCEDURE GetRope*(m: Value; key: Ropes.Rope): Value;
  VAR e: Entry;
BEGIN
  IF (m = NIL) OR (m.kind # MapV) THEN RETURN NIL END;
  e := m.items;
  WHILE (e # NIL) & ~Ropes.Equal(e.key, key) DO e := e.next END;
  IF e = NIL THEN RETURN NIL END;
  RETURN e.value
END GetRope;

(* GetRope for a string key *)
PROCEDURE Get*(m: Value; key: ARRAY OF CHAR): Value;
BEGIN
  RETURN GetRope(m, Ropes.FromString(key))
END Get;

(* Whether the map m has key *)
PROCEDURE Has*(m: Value; key: ARRAY OF CHAR): BOOLEAN;
  VAR e: Entry; k: Ropes.Rope;
BEGIN
  IF (m = NIL) OR (m.kind # MapV) THEN RETURN FALSE END;
  k := Ropes.FromString(key); e := m.items;
  WHILE (e # NIL) & ~Ropes.Equal(e.key, k) DO e := e.next END;
  RETURN e # NIL
END Has;

(* A copy of the map m, sharing its values *)
PROCEDURE CopyMap(m: Value): Value;
  VAR c: Value; e, n, t: Entry;
BEGIN
  c := NewMap(); e := m.items; t := NIL;
  WHILE e # NIL DO
    n := NewEntry(e.key, e.value);
    IF t = NIL THEN c.items := n ELSE t.next := n END;
    t := n; e := e.next
  END;
  RETURN c
END CopyMap;

(* Parsing *)

PROCEDURE NewName(s: ARRAY OF CHAR): Name;
  VAR n: Name; k: LONGINT;
BEGIN
  k := 0; WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
  NEW(n, k + 1); COPY(s, n^);
  RETURN n
END NewName;

PROCEDURE AtEnd(): BOOLEAN;
BEGIN
  RETURN st.i >= len
END AtEnd;

(* The character k after the current one, 0X past the end *)
PROCEDURE Peek(k: LONGINT): CHAR;
BEGIN
  IF st.i + k >= len THEN RETURN 0X END;
  RETURN src[st.i + k]
END Peek;

(* Moves past the current character, keeping the position as Parsec
   keeps it: a tab moves to the column after the next multiple of 8 *)
PROCEDURE Next;
  VAR ch: CHAR;
BEGIN
  ch := src[st.i]; INC(st.i);
  IF ch = 0AX THEN INC(st.p.line); st.p.col := 1
  ELSIF ch = 09X THEN st.p.col := st.p.col + 8 - (st.p.col - 1) MOD 8
  ELSIF (ORD(ch) < 80H) OR (ORD(ch) >= 0C0H) THEN INC(st.p.col)
  END
END Next;

(* Notes a failure at the current place, if it is the furthest yet *)
PROCEDURE Fail(msg: ARRAY OF CHAR);
BEGIN
  IF ~errSet OR (st.p.file # errFile) OR (st.i > errI) THEN
    errSet := TRUE; errFile := st.p.file; errI := st.i;
    errLine := st.p.line; errCol := st.p.col; errName := srcName;
    COPY(msg, errMsg)
  END
END Fail;

(* Fails with what is unexpected at the current place *)
PROCEDURE Unexpected;
  VAR m: ARRAY 16 OF CHAR; ch: CHAR; k: INTEGER;
BEGIN
  IF AtEnd() THEN Fail("unexpected end of input")
  ELSE
    ch := Peek(0);
    m := 'unexpected "';
    k := 12;
    IF ch = 0AX THEN m[k] := "\"; m[k + 1] := "n"; INC(k, 2)
    ELSIF ch = 09X THEN m[k] := "\"; m[k + 1] := "t"; INC(k, 2)
    ELSIF ch = 0DX THEN m[k] := "\"; m[k + 1] := "r"; INC(k, 2)
    ELSE m[k] := ch; INC(k)
    END;
    m[k] := '"'; m[k + 1] := 0X;
    Fail(m)
  END
END Unexpected;

(* Matches ch, or fails without moving *)
PROCEDURE Char(ch: CHAR): BOOLEAN;
BEGIN
  IF ~AtEnd() & (Peek(0) = ch) THEN Next; RETURN TRUE END;
  Unexpected;
  RETURN FALSE
END Char;

(* Matches s, as Parsec's string: moving as far as it matches *)
PROCEDURE String(s: ARRAY OF CHAR): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  k := 0;
  WHILE s[k] # 0X DO
    IF ~Char(s[k]) THEN RETURN FALSE END;
    INC(k)
  END;
  RETURN TRUE
END String;

PROCEDURE IsSpaceOrTab(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X)
END IsSpaceOrTab;

PROCEDURE SkipSpacesAndTabs;
BEGIN
  WHILE ~AtEnd() & IsSpaceOrTab(Peek(0)) DO Next END
END SkipSpacesAndTabs;

(* The rune at the current place; n is its length in bytes *)
PROCEDURE CurRune(VAR n: LONGINT): Utf8.Rune;
  VAR q: LONGINT; r: Utf8.Rune;
BEGIN
  q := st.i;
  IF ORD(src[q]) < 80H THEN n := 1; RETURN ORD(src[q]) END;
  IF ~Utf8.Decode(src^, q, r) OR (q <= st.i) OR (q > len) THEN
    n := 1; RETURN 0FFFDH
  END;
  n := q - st.i;
  RETURN r
END CurRune;

(* Whether the current character is a letter (Haskell's isAlpha) *)
PROCEDURE AtLetter(): BOOLEAN;
  VAR n: LONGINT; ch: CHAR;
BEGIN
  IF AtEnd() THEN RETURN FALSE END;
  ch := Peek(0);
  IF ORD(ch) < 80H THEN RETURN (CAP(ch) >= "A") & (CAP(ch) <= "Z") END;
  RETURN Unicode.IsLetter(CurRune(n))
END AtLetter;

(* Whether it is a letter or a number (isAlphaNum) *)
PROCEDURE AtAlphaNum(): BOOLEAN;
  VAR n: LONGINT; ch: CHAR; r: Utf8.Rune;
BEGIN
  IF AtEnd() THEN RETURN FALSE END;
  ch := Peek(0);
  IF ORD(ch) < 80H THEN
    RETURN (CAP(ch) >= "A") & (CAP(ch) <= "Z") OR (ch >= "0") & (ch <= "9")
  END;
  r := CurRune(n);
  RETURN Unicode.IsLetter(r) OR Unicode.IsNumber(r)
END AtAlphaNum;

(* Moves past the current rune *)
PROCEDURE NextRune;
  VAR n: LONGINT; r: Utf8.Rune;
BEGIN
  r := CurRune(n);
  WHILE n > 0 DO Next; DEC(n) END
END NextRune;

(* Templates *)

PROCEDURE NewNode(kind: INTEGER): Template;
  VAR t: Template;
BEGIN
  NEW(t); t.kind := kind; t.doc := NIL; t.var.parts := NIL; t.var.pipes := NIL;
  t.pipes := NIL; t.a := NIL; t.b := NIL; t.next := NIL;
  RETURN t
END NewNode;

PROCEDURE Lit(d: L.Doc): Template;
  VAR t: Template;
BEGIN
  IF d = NIL THEN RETURN NIL END;
  t := NewNode(literal); t.doc := d;
  RETURN t
END Lit;

(* Appends the template t to the template head .. tail *)
PROCEDURE Append(VAR head, tail: Template; t: Template);
BEGIN
  IF t # NIL THEN
    IF head = NIL THEN head := t ELSE tail.next := t END;
    tail := t;
    WHILE tail.next # NIL DO tail := tail.next END
  END
END Append;

(* The text src[from .. to-1] as a Doc *)
PROCEDURE Source(from, to: LONGINT): L.Doc;
BEGIN
  IF to <= from THEN RETURN NIL END;
  RETURN L.Chars(src^, from, to - from)
END Source;

PROCEDURE^ AppendStr(VAR s: ARRAY OF CHAR; VAR n: LONGINT; t: ARRAY OF CHAR);
PROCEDURE^ Template0(VAR t: Template): BOOLEAN;
PROCEDURE^ Partial(var: Variable; isVar: BOOLEAN; fp: ARRAY OF CHAR;
                   VAR t: Template): BOOLEAN;

(* pLineEnding *)
PROCEDURE LineEnding(): BOOLEAN;
BEGIN
  IF Peek(0) = 0AX THEN Next; RETURN TRUE
  ELSIF Peek(0) = 0DX THEN
    Next;
    IF Peek(0) = 0AX THEN Next END;
    RETURN TRUE
  END;
  Unexpected;
  RETURN FALSE
END LineEnding;

(* Whether a line ending or the end follows (pNewlineOrEof, looked
   ahead) *)
PROCEDURE AtNewlineOrEof(): BOOLEAN;
BEGIN
  RETURN AtEnd() OR (Peek(0) = 0AX) OR (Peek(0) = 0DX)
END AtNewlineOrEof;

(* pEndline: a line ending; inside $^$, the indentation up to its
   column is skipped, and must be there outside a directive *)
PROCEDURE Endline(): BOOLEAN;
  VAR save: State;
BEGIN
  save := st;
  IF ~LineEnding() THEN st := save; RETURN FALSE END;
  IF st.nestedCol > 0 THEN
    WHILE (st.p.col < st.nestedCol) & ~AtEnd() & IsSpaceOrTab(Peek(0)) DO Next END;
    IF ~st.inside & (st.p.col < st.nestedCol) THEN
      Unexpected; st := save; RETURN FALSE
    END
  END;
  RETURN TRUE
END Endline;

(* skipEndline: a line ending, after which the first character that is
   not a space or tab starts the line *)
PROCEDURE SkipEndline(): BOOLEAN;
  VAR save: State;
BEGIN
  IF ~Endline() THEN RETURN FALSE END;
  save := st;
  SkipSpacesAndTabs;
  save.first := st.p;
  st := save;
  RETURN TRUE
END SkipEndline;

(* pNewline *)
PROCEDURE Newline(VAR t: Template): BOOLEAN;
  VAR start, nlEnd, sps: LONGINT; save: State;
BEGIN
  start := st.i; save := st;
  IF ~LineEnding() THEN RETURN FALSE END;
  nlEnd := st.i; st := save;
  IF ~Endline() THEN RETURN FALSE END;
  sps := st.i;
  SkipSpacesAndTabs;
  st.first := st.p;
  IF st.breaking THEN t := Lit(L.Space())
  ELSE t := Lit(L.Cat(Source(start, nlEnd), Source(sps, st.i)))
  END;
  RETURN TRUE
END Newline;

(* pBlankLine *)
PROCEDURE BlankLine(VAR t: Template): BOOLEAN;
  VAR save: State; start: LONGINT;
BEGIN
  save := st; start := st.i;
  IF LineEnding() & AtNewlineOrEof() THEN
    t := Lit(Source(start, st.i));
    RETURN TRUE
  END;
  st := save;
  RETURN FALSE
END BlankLine;

(* pLit *)
PROCEDURE Lit0(VAR t: Template): BOOLEAN;
  VAR start, i, j: LONGINT; blank: BOOLEAN; ch: CHAR; head, tail: Template;
BEGIN
  start := st.i; blank := TRUE;
  WHILE ~AtEnd() & (Peek(0) # "$") & (Peek(0) # 0AX) & (Peek(0) # 0DX) DO
    IF ~IsSpaceOrTab(Peek(0)) THEN blank := FALSE END;
    Next
  END;
  IF st.i = start THEN Unexpected; RETURN FALSE END;
  IF blank & (st.p.line = 1) THEN st.first := st.p END;
  IF st.breaking THEN
    (* toBreakable *)
    head := NIL; tail := NIL; i := start;
    WHILE i < st.i DO
      ch := src[i];
      IF IsSpaceOrTab(ch) THEN
        Append(head, tail, Lit(L.Space()));
        WHILE (i < st.i) & IsSpaceOrTab(src[i]) DO INC(i) END
      ELSE
        j := i;
        WHILE (j < st.i) & ~IsSpaceOrTab(src[j]) DO INC(j) END;
        Append(head, tail, Lit(Source(i, j)));
        i := j
      END
    END;
    t := head
  ELSE
    t := Lit(Source(start, st.i))
  END;
  RETURN TRUE
END Lit0;

(* pEscape *)
PROCEDURE Escape(VAR t: Template): BOOLEAN;
BEGIN
  IF (Peek(0) = "$") & (Peek(1) = "$") THEN
    Next; Next; DEC(st.p.col);
    t := Lit(L.Text("$"));
    RETURN TRUE
  END;
  Unexpected;
  RETURN FALSE
END Escape;

(* pComment *)
PROCEDURE Comment(): BOOLEAN;
  VAR col: LONGINT;
BEGIN
  IF (Peek(0) = "$") & (Peek(1) = "-") & (Peek(2) = "-") THEN
    col := st.p.col;
    WHILE ~AtEnd() & (Peek(0) # 0AX) DO Next END;
    IF (col = 1) & ~AtEnd() THEN IF LineEnding() THEN END END;
    RETURN TRUE
  END;
  RETURN FALSE
END Comment;

PROCEDURE SkipComments;
BEGIN
  WHILE Comment() DO END
END SkipComments;

(* pOpen: "$" or "${"; closer becomes "$" or "}" *)
PROCEDURE Open(VAR closer: CHAR): BOOLEAN;
BEGIN
  IF Peek(0) = "$" THEN
    IF (Peek(1) # "$") & (Peek(1) # "{") THEN Next; closer := "$"; RETURN TRUE END;
    IF (Peek(1) = "{") & (Peek(2) # "}") THEN Next; Next; closer := "}"; RETURN TRUE END
  END;
  Unexpected;
  RETURN FALSE
END Open;

(* pIdentPart *)
PROCEDURE IdentPart(VAR name: Ropes.Rope): BOOLEAN;
  VAR save: State; start: LONGINT;
BEGIN
  save := st; start := st.i;
  IF ~AtLetter() THEN Unexpected; RETURN FALSE END;
  NextRune;
  WHILE AtAlphaNum() OR (Peek(0) = "_") OR (Peek(0) = "-") DO NextRune END;
  name := Ropes.FromSubchars(src^, start, st.i - start);
  IF Ropes.EqualString(name, "if") OR Ropes.EqualString(name, "else")
     OR Ropes.EqualString(name, "endif") OR Ropes.EqualString(name, "elseif")
     OR Ropes.EqualString(name, "for") OR Ropes.EqualString(name, "endfor")
     OR Ropes.EqualString(name, "sep") OR Ropes.EqualString(name, "it") THEN
    Unexpected; st := save; RETURN FALSE
  END;
  RETURN TRUE
END IdentPart;

(* pPipe *)
PROCEDURE Pipe0(VAR p: Pipe): BOOLEAN;
  VAR start, k: LONGINT; name: ARRAY 16 OF CHAR;
BEGIN
  IF ~Char("/") THEN RETURN FALSE END;
  start := st.i;
  IF ~AtLetter() THEN Unexpected; RETURN FALSE END;
  WHILE AtLetter() DO NextRune END;
  NEW(p); p.next := NIL;
  IF st.i - start < LEN(name) THEN
    k := 0;
    WHILE start + k < st.i DO name[k] := src[start + k]; INC(k) END;
    name[k] := 0X
  ELSE name := ""
  END;
  IF name = "uppercase" THEN p.kind := toUpper
  ELSIF name = "lowercase" THEN p.kind := toLower
  ELSIF name = "pairs" THEN p.kind := toPairs
  ELSIF name = "length" THEN p.kind := toLength
  ELSIF name = "alpha" THEN p.kind := toAlpha
  ELSIF name = "roman" THEN p.kind := toRoman
  ELSIF name = "reverse" THEN p.kind := reverse
  ELSIF name = "first" THEN p.kind := firstItem
  ELSIF name = "rest" THEN p.kind := rest
  ELSIF name = "last" THEN p.kind := lastItem
  ELSIF name = "allbutlast" THEN p.kind := allButLast
  ELSIF name = "chomp" THEN p.kind := chomp
  ELSIF name = "nowrap" THEN p.kind := noWrap
  ELSIF (name = "left") OR (name = "right") OR (name = "center") THEN
    Fail("the pipes left, right and center are not supported");
    RETURN FALSE
  ELSE
    Fail("unknown pipe");
    RETURN FALSE
  END;
  RETURN TRUE
END Pipe0;

(* many pPipe *)
PROCEDURE Pipes(VAR first: Pipe): BOOLEAN;
  VAR p, last: Pipe; start: LONGINT;
BEGIN
  first := NIL; last := NIL;
  LOOP
    start := st.i;
    IF ~Pipe0(p) THEN RETURN st.i = start END;
    IF first = NIL THEN first := p ELSE last.next := p END;
    last := p
  END
END Pipes;

(* pVar *)
PROCEDURE Var(VAR v: Variable): BOOLEAN;
  VAR name: Ropes.Rope; p, last: Part;
BEGIN
  IF ~IdentPart(name) THEN
    IF (Peek(0) = "i") & (Peek(1) = "t") THEN
      Next; Next; name := Ropes.FromString("it")
    ELSE Unexpected; RETURN FALSE
    END
  END;
  NEW(p); p.name := name; p.next := NIL; v.parts := p; last := p;
  WHILE Peek(0) = "." DO
    Next;
    IF ~IdentPart(name) THEN RETURN FALSE END;
    NEW(p); p.name := name; p.next := NIL; last.next := p; last := p
  END;
  RETURN Pipes(v.pipes)
END Var;

(* pSep *)
PROCEDURE Sep(VAR t: Template): BOOLEAN;
  VAR start: LONGINT;
BEGIN
  IF ~Char("[") THEN RETURN FALSE END;
  start := st.i;
  WHILE ~AtEnd() & (Peek(0) # "]") DO Next END;
  t := Lit(Source(start, st.i));
  RETURN Char("]")
END Sep;

(* pEnclosed (string kw): $kw$ or ${kw}, with spaces inside, or fails
   without moving *)
PROCEDURE Keyword(kw: ARRAY OF CHAR): BOOLEAN;
  VAR save: State; closer: CHAR;
BEGIN
  save := st;
  IF Open(closer) THEN
    SkipSpacesAndTabs;
    IF String(kw) THEN
      SkipSpacesAndTabs;
      IF Char(closer) THEN RETURN TRUE END
    END
  END;
  st := save;
  RETURN FALSE
END Keyword;

(* pEnclosed (try (string kw *> pParens pVar)): $kw(var)$, or fails
   without moving *)
PROCEDURE KeywordVar(kw: ARRAY OF CHAR; VAR v: Variable): BOOLEAN;
  VAR save: State; closer: CHAR;
BEGIN
  save := st;
  IF Open(closer) THEN
    SkipSpacesAndTabs;
    IF String(kw) & Char("(") & Var(v) & Char(")") THEN
      SkipSpacesAndTabs;
      IF Char(closer) THEN RETURN TRUE END
    END
  END;
  st := save;
  RETURN FALSE
END KeywordVar;

(* pElse multiline <|> pElseIf, optionally *)
PROCEDURE ElsePart(multiline: BOOLEAN; VAR t: Template): BOOLEAN;
  VAR v: Variable; ml: BOOLEAN; c: Template;
BEGIN
  t := NIL;
  IF Keyword("else") THEN
    IF multiline THEN IF SkipEndline() THEN END END;
    RETURN Template0(t)
  ELSIF KeywordVar("elseif", v) THEN
    ml := SkipEndline();
    c := NewNode(conditional); c.var := v; t := c;
    RETURN Template0(c.a) & ElsePart(ml, c.b)
  END;
  RETURN TRUE
END ElsePart;

(* pConditional *)
PROCEDURE Conditional(VAR t: Template): BOOLEAN;
  VAR v: Variable; inside, multiline, ok: BOOLEAN; c: Template;
BEGIN
  IF ~KeywordVar("if", v) THEN RETURN FALSE END;
  inside := st.inside; st.inside := TRUE;
  multiline := SkipEndline();
  c := NewNode(conditional); c.var := v;
  ok := Template0(c.a) & ElsePart(multiline, c.b);
  IF ok THEN
    IF Keyword("endif") THEN
      IF multiline THEN IF SkipEndline() THEN END END
    ELSE Unexpected; ok := FALSE
    END
  END;
  st.inside := inside;
  t := c;
  RETURN ok
END Conditional;

(* pForLoop *)
PROCEDURE ForLoop(VAR t: Template): BOOLEAN;
  VAR v: Variable; inside, multiline, ok: BOOLEAN; c: Template;
BEGIN
  IF ~KeywordVar("for", v) THEN RETURN FALSE END;
  inside := st.inside; st.inside := TRUE;
  multiline := SkipEndline();
  c := NewNode(iterate); c.var := v;
  ok := Template0(c.a);
  IF ok & Keyword("sep") THEN
    IF multiline THEN IF SkipEndline() THEN END END;
    ok := Template0(c.b)
  END;
  IF ok THEN
    IF Keyword("endfor") THEN
      IF multiline THEN IF SkipEndline() THEN END END
    ELSE Unexpected; ok := FALSE
    END
  END;
  st.inside := inside;
  t := c;
  RETURN ok
END ForLoop;

(* pReflowToggle *)
PROCEDURE ReflowToggle(VAR t: Template): BOOLEAN;
BEGIN
  IF Keyword("~") THEN st.breaking := ~st.breaking; t := NIL; RETURN TRUE END;
  RETURN FALSE
END ReflowToggle;

(* pNested *)
PROCEDURE Nested(VAR t: Template): BOOLEAN;
  VAR col, old: LONGINT; head, tail, h2, t2, x, y: Template; save: State;
    ok: BOOLEAN;
BEGIN
  col := st.p.col;
  IF ~Keyword("^") THEN RETURN FALSE END;
  old := st.nestedCol; st.nestedCol := col;
  head := NIL; tail := NIL;
  IF ~Template0(x) THEN RETURN FALSE END;
  Append(head, tail, x);
  LOOP
    (* try (many1 pBlankLine ++ pTemplate) *)
    save := st; h2 := NIL; t2 := NIL;
    IF ~BlankLine(y) THEN EXIT END;
    Append(h2, t2, y);
    WHILE BlankLine(y) DO Append(h2, t2, y) END;
    ok := Template0(x);
    IF ~ok THEN st := save; EXIT END;
    Append(h2, t2, x);
    Append(head, tail, h2)
  END;
  st.nestedCol := old;
  t := NewNode(nested); t.a := head;
  RETURN TRUE
END Nested;

(* handleNesting *)
PROCEDURE HandleNesting(eat: BOOLEAN; pos: Pos; VAR t: Template);
  VAR beginline, endofline: BOOLEAN; n: Template;
BEGIN
  beginline := (st.first.file = pos.file) & (st.first.line = pos.line)
               & (st.first.col = pos.col);
  endofline := AtNewlineOrEof();
  IF eat & beginline THEN IF SkipEndline() THEN END END;
  IF beginline & endofline & (t # NIL) THEN
    IF ((t.kind = nested) & (t.next = NIL)) OR (pos.col = 1)
       OR (pos.col = st.nestedCol) THEN
      (* as it is *)
    ELSE
      n := NewNode(nested); n.a := t; t := n
    END
  END
END HandleNesting;

(* pPartialName, or fails without moving *)
PROCEDURE PartialName(VAR fp: ARRAY OF CHAR): BOOLEAN;
  VAR save: State; start, k: LONGINT; ch: CHAR;
BEGIN
  save := st; start := st.i;
  LOOP
    ch := Peek(0);
    IF AtAlphaNum() THEN NextRune
    ELSIF (ch = "_") OR (ch = "-") OR (ch = ".") OR (ch = "/") OR (ch = "\") THEN Next
    ELSE EXIT
    END
  END;
  IF (st.i > start) & (st.i - start < LEN(fp)) & String("()") THEN
    k := 0;
    WHILE k < st.i - 2 - start DO fp[k] := src[start + k]; INC(k) END;
    fp[k] := 0X;
    RETURN TRUE
  END;
  IF st.i = start THEN Unexpected END;
  st := save;
  RETURN FALSE
END PartialName;

(* pInterpolate *)
PROCEDURE Interpolate(VAR t: Template): BOOLEAN;
  VAR pos: Pos; save: State; closer: CHAR; v, it: Variable; sep: Template;
    fp: ARRAY 1024 OF CHAR; c: Template;
BEGIN
  pos := st.p; save := st;
  IF ~Open(closer) THEN RETURN FALSE END;
  SkipSpacesAndTabs;
  IF ~Var(v) OR (Peek(0) = "(") THEN
    IF Peek(0) = "(" THEN Unexpected END;
    st := save; RETURN FALSE
  END;
  IF Peek(0) = ":" THEN
    Next;
    IF ~PartialName(fp) THEN RETURN FALSE END;
    IF ~Partial(v, TRUE, fp, t) THEN RETURN FALSE END
  ELSIF Peek(0) = "[" THEN
    IF ~Sep(sep) THEN RETURN FALSE END;
    NEW(it.parts); it.parts.name := Ropes.FromString("it"); it.parts.next := NIL;
    it.pipes := NIL;
    c := NewNode(interpolate); c.var := it;
    t := NewNode(iterate); t.var := v; t.a := c; t.b := sep
  ELSE
    t := NewNode(interpolate); t.var := v
  END;
  SkipSpacesAndTabs;
  IF ~Char(closer) THEN RETURN FALSE END;
  HandleNesting(FALSE, pos, t);
  RETURN TRUE
END Interpolate;

(* pBarePartial *)
PROCEDURE BarePartial(VAR t: Template): BOOLEAN;
  VAR pos: Pos; save: State; closer: CHAR; fp: ARRAY 1024 OF CHAR;
    none: Variable;
BEGIN
  pos := st.p; save := st;
  IF ~Open(closer) THEN RETURN FALSE END;
  SkipSpacesAndTabs;
  IF ~PartialName(fp) THEN st := save; RETURN FALSE END;
  none.parts := NIL; none.pipes := NIL;
  IF ~Partial(none, FALSE, fp, t) THEN RETURN FALSE END;
  SkipSpacesAndTabs;
  IF ~Char(closer) THEN RETURN FALSE END;
  HandleNesting(TRUE, pos, t);
  RETURN TRUE
END BarePartial;

(* The path of the partial fp of the template path tp: in tp's
   directory, with tp's extension if fp has none *)
PROCEDURE PartialPath(tp, fp: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
  VAR i, slash, dot, n, k: LONGINT; hasExt: BOOLEAN;
BEGIN
  slash := -1; dot := -1; i := 0;
  WHILE (i < LEN(tp)) & (tp[i] # 0X) DO
    IF tp[i] = "/" THEN slash := i; dot := -1
    ELSIF tp[i] = "." THEN dot := i
    END;
    INC(i)
  END;
  hasExt := FALSE; i := 0;
  WHILE fp[i] # 0X DO
    IF fp[i] = "/" THEN hasExt := FALSE
    ELSIF (fp[i] = ".") & (i > 0) & (fp[i - 1] # "/") THEN hasExt := TRUE
    END;
    INC(i)
  END;
  n := 0;
  FOR k := 0 TO slash DO path[n] := tp[k]; INC(n) END;
  i := 0; WHILE fp[i] # 0X DO path[n] := fp[i]; INC(n); INC(i) END;
  IF ~hasExt & (dot > slash + 1) THEN
    k := dot;
    WHILE (k < LEN(tp)) & (tp[k] # 0X) DO path[n] := tp[k]; INC(n); INC(k) END
  END;
  path[n] := 0X
END PartialPath;

(* Reads a partial from a file *)
PROCEDURE ReadPartialFile(path: ARRAY OF CHAR; VAR t: PdIO.Text;
                          VAR len: LONGINT): BOOLEAN;
BEGIN
  IF ~PdIO.Exists(path) THEN RETURN FALSE END;
  PdIO.ReadFile(path, t, len);
  RETURN TRUE
END ReadPartialFile;

(* pPartial: the partial fp, after a variable v if isVar *)
PROCEDURE Partial(var: Variable; isVar: BOOLEAN; fp: ARRAY OF CHAR;
                  VAR t: Template): BOOLEAN;
  VAR old: State; separ, body, p: Template; path: ARRAY 2048 OF CHAR;
    ptext, oldSrc: PdIO.Text; plen, oldLen, n: LONGINT; oldName: Name;
    ok: BOOLEAN; pipes: Pipe; msg: ARRAY 256 OF CHAR;
BEGIN
  old := st;
  separ := NIL;
  IF Peek(0) = "[" THEN
    IF ~Sep(separ) THEN RETURN FALSE END
  END;
  PartialPath(srcName^, fp, path);
  IF ~readPartial(path, ptext, plen) THEN
    msg := "could not read the partial "; n := 27;
    AppendStr(msg, n, path);
    Fail(msg);
    RETURN FALSE
  END;
  IF (plen > 0) & (ptext[plen - 1] = 0AX) THEN DEC(plen) END;
  IF nesting > MaxNesting THEN
    body := Lit(L.Text("(loop)"))
  ELSE
    oldSrc := src; oldLen := len; oldName := srcName; old := st;
    PdIO.Reserve(ptext, plen, plen + 1);
    src := ptext; len := plen; srcName := NewName(path);
    INC(files);
    st.i := 0; st.p.file := files; st.p.line := 1; st.p.col := 1;
    st.nestedCol := 0;
    INC(nesting);
    ok := Template0(body);
    IF ok & ~AtEnd() THEN Unexpected; ok := FALSE END;
    IF ~ok THEN RETURN FALSE END;
    DEC(nesting);
    src := oldSrc; len := oldLen; srcName := oldName;
    st.i := old.i; st.p := old.p
  END;
  (* putState oldst *)
  st.first := old.first; st.nestedCol := old.nestedCol;
  st.inside := old.inside; st.breaking := old.breaking;
  IF ~Pipes(pipes) THEN RETURN FALSE END;
  p := NewNode(partial); p.pipes := pipes; p.a := body;
  IF isVar THEN
    t := NewNode(iterate); t.var := var; t.a := p; t.b := separ
  ELSE t := p
  END;
  RETURN TRUE
END Partial;

(* pDirective *)
PROCEDURE Directive(VAR t: Template): BOOLEAN;
  VAR start: LONGINT;
BEGIN
  start := st.i;
  IF Conditional(t) THEN RETURN TRUE ELSIF st.i # start THEN RETURN FALSE END;
  IF ForLoop(t) THEN RETURN TRUE ELSIF st.i # start THEN RETURN FALSE END;
  IF ReflowToggle(t) THEN RETURN TRUE ELSIF st.i # start THEN RETURN FALSE END;
  IF Nested(t) THEN RETURN TRUE ELSIF st.i # start THEN RETURN FALSE END;
  IF Interpolate(t) THEN RETURN TRUE ELSIF st.i # start THEN RETURN FALSE END;
  RETURN BarePartial(t)
END Directive;

(* pTemplate *)
PROCEDURE Template0(VAR t: Template): BOOLEAN;
  VAR head, tail, x: Template; start: LONGINT;
BEGIN
  head := NIL; tail := NIL;
  SkipComments;
  LOOP
    start := st.i; x := NIL;
    IF ~AtEnd() & (Peek(0) # "$") & (Peek(0) # 0AX) & (Peek(0) # 0DX) THEN
      IF ~Lit0(x) THEN EXIT END
    ELSIF Newline(x) THEN
    ELSIF st.i # start THEN RETURN FALSE
    ELSIF Directive(x) THEN
    ELSIF st.i # start THEN RETURN FALSE
    ELSIF Escape(x) THEN
    ELSE EXIT
    END;
    Append(head, tail, x);
    SkipComments
  END;
  t := head;
  RETURN TRUE
END Template0;

PROCEDURE AppendStr(VAR s: ARRAY OF CHAR; VAR n: LONGINT; t: ARRAY OF CHAR);
  VAR k: LONGINT;
BEGIN
  k := 0;
  WHILE (k < LEN(t)) & (t[k] # 0X) & (n < LEN(s) - 1) DO s[n] := t[k]; INC(n); INC(k) END;
  s[n] := 0X
END AppendStr;

PROCEDURE AppendInt(VAR s: ARRAY OF CHAR; VAR n: LONGINT; x: LONGINT);
  VAR d: ARRAY 24 OF CHAR; k: INTEGER; one: ARRAY 2 OF CHAR;
BEGIN
  k := 0;
  REPEAT d[k] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(k) UNTIL x = 0;
  one[1] := 0X;
  WHILE k > 0 DO DEC(k); one[0] := d[k]; AppendStr(s, n, one) END
END AppendInt;

(* Reads the template text[0 .. len-1], whose path, for its partials and
   messages, is path, into t. FALSE, with error set, if it cannot be
   read. *)
PROCEDURE Compile*(path: ARRAY OF CHAR; text: PdIO.Text; textLen: LONGINT;
                   VAR t: Template): BOOLEAN;
  VAR ok: BOOLEAN; n: LONGINT;
BEGIN
  src := text; len := textLen;
  IF src = NIL THEN PdIO.Reserve(src, 0, 1) END;
  srcName := NewName(path); files := 0;
  st.i := 0; st.p.file := 0; st.p.line := 1; st.p.col := 1;
  st.first := st.p; st.nestedCol := 0; st.inside := FALSE; st.breaking := FALSE;
  nesting := 1;
  errSet := FALSE; error := "";
  ok := Template0(t);
  IF ok & ~AtEnd() THEN Unexpected; ok := FALSE END;
  IF ~ok THEN
    n := 0;
    IF errName^ # "" THEN
      AppendStr(error, n, '"'); AppendStr(error, n, errName^); AppendStr(error, n, '" ')
    END;
    AppendStr(error, n, "(line "); AppendInt(error, n, errLine);
    AppendStr(error, n, ", column "); AppendInt(error, n, errCol);
    AppendStr(error, n, "):"); AppendStr(error, n, 0AX);
    AppendStr(error, n, errMsg);
    t := NIL
  END;
  src := NIL;
  RETURN ok
END Compile;

(* Rendering *)

(* The text of d, rendered without wrapping, in buf[0 .. n-1] *)
PROCEDURE Rendered(d: L.Doc; VAR n: LONGINT);
  VAR r: Ropes.Rope;
BEGIN
  r := L.Render(d, 0); n := Ropes.Length(r);
  PdIO.Reserve(buf, 0, n + 1);
  IF n > 0 THEN Ropes.Blit(r, 0, buf^, 0, n) END;
  buf[n] := 0X
END Rendered;

(* The decimal number x as text *)
PROCEDURE Number(x: LONGINT): L.Doc;
  VAR s: ARRAY 24 OF CHAR; n: LONGINT;
BEGIN
  n := 0; s[0] := 0X; AppendInt(s, n, x);
  RETURN L.Text(s)
END Number;

PROCEDURE Upper(r: Ropes.Rope): Ropes.Rope;
  VAR n, m: LONGINT;
BEGIN
  n := Ropes.Length(r);
  PdIO.Reserve(buf, 0, n + 1);
  Ropes.Blit(r, 0, buf^, 0, n); buf[n] := 0X;
  m := Utf8Strings.UpperLength(buf^, Unicode.noLanguage);
  PdIO.Reserve(buf2, 0, m + 1);
  IF Utf8Strings.ToUpper(buf^, buf2^, Unicode.noLanguage) THEN END;
  RETURN Ropes.FromSubchars(buf2^, 0, m)
END Upper;

PROCEDURE Lower(r: Ropes.Rope): Ropes.Rope;
  VAR n, m: LONGINT;
BEGIN
  n := Ropes.Length(r);
  PdIO.Reserve(buf, 0, n + 1);
  Ropes.Blit(r, 0, buf^, 0, n); buf[n] := 0X;
  m := Utf8Strings.LowerLength(buf^, Unicode.noLanguage);
  PdIO.Reserve(buf2, 0, m + 1);
  IF Utf8Strings.ToLower(buf^, buf2^, Unicode.noLanguage) THEN END;
  RETURN Ropes.FromSubchars(buf2^, 0, m)
END Lower;

(* v with f applied to its text, in its lists and maps too (mapText) *)
PROCEDURE MapText(v: Value; f: PROCEDURE (r: Ropes.Rope): Ropes.Rope): Value;
  VAR c: Value; e: Entry;
BEGIN
  IF v = NIL THEN RETURN NIL END;
  CASE v.kind OF
    SimpleV: RETURN NewSimple(L.MapText(v.doc, f))
  | ListV:
      c := NewList(); e := v.items;
      WHILE e # NIL DO Add(c, MapText(e.value, f)); e := e.next END;
      RETURN c
  | MapV:
      c := CopyMap(v); e := c.items;
      WHILE e # NIL DO e.value := MapText(e.value, f); e := e.next END;
      RETURN c
  | BoolV: RETURN v
  END
END MapText;

(* The roman numeral for x, 0 <= x < 4000, in lower case *)
PROCEDURE Roman(x: LONGINT; VAR s: ARRAY OF CHAR);
  VAR n: LONGINT;

  PROCEDURE Digit(VAR x: LONGINT; v: LONGINT; d: ARRAY OF CHAR);
  BEGIN
    WHILE x >= v DO AppendStr(s, n, d); DEC(x, v) END
  END Digit;

BEGIN
  n := 0; s[0] := 0X;
  Digit(x, 1000, "m"); Digit(x, 900, "cm"); Digit(x, 500, "d");
  Digit(x, 400, "cd"); Digit(x, 100, "c"); Digit(x, 90, "xc");
  Digit(x, 50, "l"); Digit(x, 40, "xl"); Digit(x, 10, "x");
  Digit(x, 9, "ix"); Digit(x, 5, "v"); Digit(x, 4, "iv"); Digit(x, 1, "i")
END Roman;

(* alpha or roman, on a Doc: if its text is a decimal number, kind's
   form of it, else d *)
PROCEDURE NumberDoc(kind: INTEGER; d: L.Doc): L.Doc;
  VAR n, i, x, m26: LONGINT; big, zero: BOOLEAN; s: ARRAY 64 OF CHAR;
BEGIN
  Rendered(d, n);
  IF n = 0 THEN RETURN d END;
  x := 0; m26 := 0; big := FALSE; zero := TRUE;
  FOR i := 0 TO n - 1 DO
    IF (buf[i] < "0") OR (buf[i] > "9") THEN RETURN d END;
    IF buf[i] # "0" THEN zero := FALSE END;
    m26 := (m26 * 10 + ORD(buf[i]) - ORD("0")) MOD 26;
    IF ~big THEN
      x := x * 10 + ORD(buf[i]) - ORD("0");
      IF x >= 4000 THEN big := TRUE END
    END
  END;
  IF kind = toAlpha THEN
    IF zero THEN RETURN d END;
    s[0] := CHR(ORD("a") + (m26 + 25) MOD 26); s[1] := 0X;
    RETURN L.Text(s)
  END;
  IF big THEN RETURN d END;
  Roman(x, s);
  RETURN L.Text(s)
END NumberDoc;

(* v with its Docs changed as the pipe kind changes them (mapDoc) *)
PROCEDURE MapDoc(v: Value; kind: INTEGER): Value;
  VAR c: Value; e: Entry; d: L.Doc;
BEGIN
  IF v = NIL THEN RETURN NIL END;
  CASE v.kind OF
    SimpleV:
      d := v.doc;
      CASE kind OF
        chomp: d := L.Chomp(d)
      | noWrap: d := L.NoWrap(d)
      | toAlpha, toRoman: d := NumberDoc(kind, d)
      END;
      RETURN NewSimple(d)
  | ListV:
      c := NewList(); e := v.items;
      WHILE e # NIL DO Add(c, MapDoc(e.value, kind)); e := e.next END;
      RETURN c
  | MapV:
      c := CopyMap(v); e := c.items;
      WHILE e # NIL DO e.value := MapDoc(e.value, kind); e := e.next END;
      RETURN c
  | BoolV: RETURN v
  END
END MapDoc;

(* The number of runes in buf[0 .. n-1] *)
PROCEDURE Runes(n: LONGINT): LONGINT;
  VAR i, k: LONGINT;
BEGIN
  k := 0;
  FOR i := 0 TO n - 1 DO
    IF (ORD(buf[i]) < 80H) OR (ORD(buf[i]) >= 0C0H) THEN INC(k) END
  END;
  RETURN k
END Runes;

PROCEDURE Count(e: Entry): LONGINT;
  VAR k: LONGINT;
BEGIN
  k := 0; WHILE e # NIL DO INC(k); e := e.next END;
  RETURN k
END Count;

(* A map of key and value *)
PROCEDURE Pair(key: L.Doc; v: Value): Value;
  VAR m: Value;
BEGIN
  m := NewMap();
  Put(m, "key", NewSimple(key));
  IF v # NIL THEN Put(m, "value", v) ELSE Put(m, "value", NIL) END;
  RETURN m
END Pair;

(* applyPipe *)
PROCEDURE ApplyPipe(p: Pipe; v: Value): Value;
  VAR c: Value; e: Entry; n, i, j, k: LONGINT; r: Utf8.Rune; q: LONGINT;
BEGIN
  CASE p.kind OF
    toLength:
      IF v = NIL THEN n := 0
      ELSE
        CASE v.kind OF
          SimpleV: Rendered(v.doc, n); n := Runes(n)
        | MapV, ListV: n := Count(v.items)
        | BoolV: n := 0
        END
      END;
      RETURN NewSimple(Number(n))
  | toUpper: RETURN MapText(v, Upper)
  | toLower: RETURN MapText(v, Lower)
  | toPairs:
      IF (v # NIL) & (v.kind = MapV) THEN
        c := NewList(); e := v.items;
        WHILE e # NIL DO Add(c, Pair(L.Literal(e.key), e.value)); e := e.next END;
        RETURN c
      ELSIF (v # NIL) & (v.kind = ListV) THEN
        c := NewList(); e := v.items; i := 1;
        WHILE e # NIL DO Add(c, Pair(Number(i), e.value)); INC(i); e := e.next END;
        RETURN c
      END;
      RETURN v
  | firstItem:
      IF (v # NIL) & (v.kind = ListV) & (v.items # NIL) THEN RETURN v.items.value END;
      RETURN v
  | lastItem:
      IF (v # NIL) & (v.kind = ListV) & (v.items # NIL) THEN RETURN v.last.value END;
      RETURN v
  | rest:
      IF (v # NIL) & (v.kind = ListV) & (v.items # NIL) THEN
        c := NewList(); e := v.items.next;
        WHILE e # NIL DO Add(c, e.value); e := e.next END;
        RETURN c
      END;
      RETURN v
  | allButLast:
      IF (v # NIL) & (v.kind = ListV) & (v.items # NIL) THEN
        c := NewList(); e := v.items;
        WHILE e.next # NIL DO Add(c, e.value); e := e.next END;
        RETURN c
      END;
      RETURN v
  | reverse:
      IF (v # NIL) & (v.kind = ListV) THEN
        c := NewList(); n := Count(v.items);
        FOR i := n - 1 TO 0 BY -1 DO
          e := v.items; FOR j := 1 TO i DO e := e.next END;
          Add(c, e.value)
        END;
        RETURN c
      ELSIF (v # NIL) & (v.kind = SimpleV) THEN
        Rendered(v.doc, n);
        PdIO.Reserve(buf2, 0, n + 1);
        (* the runes in reverse order *)
        i := 0; k := n;
        WHILE i < n DO
          q := i;
          IF (ORD(buf[i]) < 80H) OR ~Utf8.Decode(buf^, q, r) OR (q <= i) THEN q := i + 1 END;
          DEC(k, q - i);
          FOR j := i TO q - 1 DO buf2[k + j - i] := buf[j] END;
          i := q
        END;
        RETURN NewSimple(L.Chars(buf2^, 0, n))
      END;
      RETURN v
  | chomp, toAlpha, toRoman, noWrap: RETURN MapDoc(v, p.kind)
  END
END ApplyPipe;

PROCEDURE ApplyPipes(p: Pipe; v: Value): Value;
BEGIN
  WHILE p # NIL DO v := ApplyPipe(p, v); p := p.next END;
  RETURN v
END ApplyPipes;

(* multiLookup *)
PROCEDURE Lookup(parts: Part; v: Value): Value;
BEGIN
  WHILE parts # NIL DO
    IF (v = NIL) OR (v.kind # MapV) THEN RETURN NIL END;
    v := GetRope(v, parts.name);
    IF v = NIL THEN RETURN NIL END;
    parts := parts.next
  END;
  RETURN v
END Lookup;

(* resolveVariable' with no parts or pipes: whether v is true, and its
   text appended to d *)
PROCEDURE Resolve(v: Value; VAR d: L.Doc): BOOLEAN;
  VAR e: Entry; b: BOOLEAN;
BEGIN
  IF v = NIL THEN RETURN FALSE END;
  CASE v.kind OF
    ListV:
      b := FALSE; e := v.items;
      WHILE e # NIL DO
        IF Resolve(e.value, d) THEN b := TRUE END;
        e := e.next
      END;
      RETURN b
  | SimpleV:
      IF L.IsEmpty(v.doc) THEN RETURN FALSE END;
      d := L.Cat(d, L.RemoveFinalNl(v.doc));
      RETURN TRUE
  | MapV: d := L.Cat(d, L.Text("true")); RETURN TRUE
  | BoolV:
      IF v.b THEN d := L.Cat(d, L.Text("true")); RETURN TRUE END;
      d := L.Cat(d, L.Text("false")); RETURN FALSE
  END
END Resolve;

(* resolveVariable *)
PROCEDURE ResolveVar(VAR var: Variable; ctx: Value; VAR d: L.Doc): BOOLEAN;
BEGIN
  d := NIL;
  RETURN Resolve(ApplyPipes(var.pipes, Lookup(var.parts, ctx)), d)
END ResolveVar;

(* addToContext: ctx with the value at parts, if there is one, x *)
PROCEDURE AddToContext(parts: Part; x, ctx: Value): Value;
  VAR e: Entry; c: Value;
BEGIN
  IF parts = NIL THEN RETURN ctx END;
  c := CopyMap(ctx); e := c.items;
  WHILE (e # NIL) & ~Ropes.Equal(e.key, parts.name) DO e := e.next END;
  IF e # NIL THEN
    IF parts.next = NIL THEN e.value := x
    ELSIF (e.value # NIL) & (e.value.kind = MapV) THEN
      e.value := AddToContext(parts.next, x, e.value)
    END
  END;
  RETURN c
END AddToContext;

PROCEDURE^ RenderT(t: Template; ctx: Value): L.Doc;

(* withVariable, then the separator, interspersed *)
PROCEDURE RenderIterate(t: Template; ctx: Value): L.Doc;
  VAR v, c: Value; e: Entry; docs: POINTER TO ARRAY OF L.Doc;
    n, i: LONGINT; sep, d: L.Doc;
BEGIN
  v := ApplyPipes(t.var.pipes, Lookup(t.var.parts, ctx));
  IF v = NIL THEN n := 0
  ELSIF v.kind = ListV THEN n := Count(v.items)
  ELSE n := 1
  END;
  IF n > 0 THEN NEW(docs, n) END;
  IF (v # NIL) & (v.kind = ListV) THEN
    e := v.items; i := 0;
    WHILE e # NIL DO
      c := CopyMap(ctx); Put(c, "it", e.value);
      docs[i] := RenderT(t.a, AddToContext(t.var.parts, e.value, c));
      INC(i); e := e.next
    END
  ELSIF v # NIL THEN
    c := CopyMap(ctx); Put(c, "it", v);
    docs[0] := RenderT(t.a, AddToContext(t.var.parts, v, c))
  END;
  sep := RenderT(t.b, ctx);
  d := NIL;
  i := n;
  WHILE i > 0 DO
    DEC(i);
    IF i < n - 1 THEN d := L.Cat(sep, d) END;
    d := L.Cat(docs[i], d)
  END;
  RETURN d
END RenderIterate;

(* renderTemp of one node *)
PROCEDURE RenderNode(t: Template; ctx: Value): L.Doc;
  VAR d: L.Doc; n: LONGINT; v: Value;
BEGIN
  d := NIL;
  CASE t.kind OF
    literal: d := t.doc; column := L.UpdateColumn(d, column)
  | interpolate:
      IF ResolveVar(t.var, ctx, d) THEN END;
      column := L.UpdateColumn(d, column)
  | conditional:
      IF ResolveVar(t.var, ctx, d) THEN d := RenderT(t.a, ctx)
      ELSE d := RenderT(t.b, ctx)
      END
  | iterate: d := RenderIterate(t, ctx)
  | nested: n := column; d := L.Nest(n, RenderT(t.a, ctx))
  | partial:
      v := ApplyPipes(t.pipes, NewSimple(RenderT(t.a, ctx)));
      IF (v # NIL) & (v.kind = SimpleV) THEN d := v.doc ELSE d := NIL END
  END;
  RETURN d
END RenderNode;

PROCEDURE RenderT(t: Template; ctx: Value): L.Doc;
  VAR d, x: L.Doc; docs: POINTER TO ARRAY OF L.Doc; n, i: LONGINT; u: Template;
BEGIN
  IF t = NIL THEN RETURN NIL END;
  IF t.next = NIL THEN RETURN RenderNode(t, ctx) END;
  n := 0; u := t; WHILE u # NIL DO INC(n); u := u.next END;
  NEW(docs, n); i := 0;
  WHILE t # NIL DO docs[i] := RenderNode(t, ctx); INC(i); t := t.next END;
  (* Concat t1 t2 is t1 <> t2, nested to the right *)
  d := NIL; i := n;
  WHILE i > 0 DO DEC(i); x := docs[i]; d := L.Cat(x, d) END;
  RETURN d
END RenderT;

(* The template t rendered with the context ctx, a map *)
PROCEDURE Render*(t: Template; ctx: Value): L.Doc;
BEGIN
  column := 0;
  IF ctx = NIL THEN ctx := NewMap() END;
  RETURN RenderT(t, ctx)
END Render;

BEGIN
  readPartial := ReadPartialFile;
  buf := NIL; buf2 := NIL
END PdTemplate.
