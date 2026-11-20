MODULE PdYaml;
(* PdYaml: the subset of YAML that metadata blocks and metadata files
   use, read into a tree of nodes.

   Read: block mappings and sequences (a sequence may sit at its key's
   indentation, and an entry may hold a compact mapping or sequence);
   flow sequences and mappings, nested and over several lines; plain,
   single-quoted and double-quoted scalars, over several lines, with
   YAML's escapes and line folding; literal and folded block scalars,
   with chomping and indentation indicators; comments; and the document
   markers "---" and "...". Of several documents, the first is kept.

   Not read: anchors, aliases, tags, directives and complex ("? ")
   keys. Each, like any syntax error, ends Parse with a message naming
   the construct, and its line and column.

   A mapping keeps its keys in order. A key given twice keeps the later
   value, with a warning naming its path, as Data.Yaml's are named:
   ".a", ".b.c", ".x[0].a".

   Data.Yaml's reading of a scalar's value (null, a boolean, a number or
   a string) is Resolve; NumberText shows a number as pandoc does. *)

CONST
  (* node kinds *)
  Scalar* = 1; Sequence* = 2; Mapping* = 3;

  (* scalar styles *)
  Plain* = 0; SingleQuoted* = 1; DoubleQuoted* = 2; Literal* = 3; Folded* = 4;

  (* what Resolve finds a scalar to be *)
  Null* = 0; Bool* = 1; Number* = 2; String* = 3;

  (* block scalar chomping *)
  Clip = 0; Strip = 1; Keep = 2;

TYPE
  Text* = POINTER TO ARRAY OF CHAR;

  Node* = POINTER TO NodeDesc;
  Pair* = POINTER TO PairDesc;

  (* A scalar's text is text[0 .. len-1], with 0X after it. A sequence's
     items are pairs without keys; a mapping's are pairs with them. *)
  NodeDesc* = RECORD
    kind*, style*: INTEGER;
    text*: Text;
    len*: LONGINT;
    items*: Pair
  END;

  PairDesc* = RECORD
    key*: Node; (* a scalar; NIL in a sequence *)
    value*: Node;
    next*: Pair
  END;

  Warning* = POINTER TO WarningDesc;
  WarningDesc* = RECORD
    text*: Text;
    next*: Warning
  END;

  Buf = RECORD
    t: Text;
    len: LONGINT
  END;

VAR
  error*: ARRAY 256 OF CHAR; (* what went wrong, when Parse fails *)
  errLine*, errCol*: LONGINT; (* where, counted from 0 as libyaml does *)
  warnings*: Warning; (* the duplicate keys, the last found first *)

  t: Text; (* the text being read, with 0X after it *)
  n: LONGINT; (* its length *)
  pos: LONGINT;
  failed: BOOLEAN;
  path: Buf; (* the path to the node being read, for warnings *)

(* Buffers *)

PROCEDURE InitBuf(VAR b: Buf);
BEGIN
  NEW(b.t, 64); b.t[0] := 0X; b.len := 0
END InitBuf;

PROCEDURE PutChar(VAR b: Buf; ch: CHAR);
  VAR nt: Text; i: LONGINT;
BEGIN
  IF b.len + 1 >= LEN(b.t^) THEN
    NEW(nt, LEN(b.t^) * 2);
    FOR i := 0 TO b.len - 1 DO nt[i] := b.t[i] END;
    b.t := nt
  END;
  b.t[b.len] := ch; INC(b.len); b.t[b.len] := 0X
END PutChar;

PROCEDURE PutString(VAR b: Buf; s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) DO PutChar(b, s[i]); INC(i) END
END PutString;

PROCEDURE PutText(VAR b: Buf; s: Text; len: LONGINT);
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO len - 1 DO PutChar(b, s[i]) END
END PutText;

PROCEDURE PutBreaks(VAR b: Buf; k: LONGINT);
BEGIN
  WHILE k > 0 DO PutChar(b, 0AX); DEC(k) END
END PutBreaks;

PROCEDURE PutUtf8(VAR b: Buf; c: LONGINT);
BEGIN
  IF c < 80H THEN PutChar(b, CHR(c))
  ELSIF c < 800H THEN
    PutChar(b, CHR(0C0H + c DIV 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  ELSIF c < 10000H THEN
    PutChar(b, CHR(0E0H + c DIV 1000H));
    PutChar(b, CHR(80H + c DIV 40H MOD 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  ELSE
    PutChar(b, CHR(0F0H + c DIV 40000H));
    PutChar(b, CHR(80H + c DIV 1000H MOD 40H));
    PutChar(b, CHR(80H + c DIV 40H MOD 40H));
    PutChar(b, CHR(80H + c MOD 40H))
  END
END PutUtf8;

(* The text of b, copied *)
PROCEDURE Copy(VAR b: Buf): Text;
  VAR r: Text; i: LONGINT;
BEGIN
  NEW(r, b.len + 1);
  FOR i := 0 TO b.len - 1 DO r[i] := b.t[i] END;
  r[b.len] := 0X;
  RETURN r
END Copy;

(* Characters and positions *)

PROCEDURE C(p: LONGINT): CHAR;
BEGIN
  IF (p >= 0) & (p < n) THEN RETURN t[p] ELSE RETURN 0X END
END C;

PROCEDURE IsWhite(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X)
END IsWhite;

(* A space, tab, new line or the end of the text at p *)
PROCEDURE BlankAt(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (p >= n) OR IsWhite(t[p]) OR (t[p] = 0AX)
END BlankAt;

PROCEDURE IsFlowIndicator(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = ",") OR (ch = "[") OR (ch = "]") OR (ch = "{") OR (ch = "}")
END IsFlowIndicator;

PROCEDURE LineStart(p: LONGINT): LONGINT;
BEGIN
  WHILE (p > 0) & (t[p - 1] # 0AX) DO DEC(p) END;
  RETURN p
END LineStart;

PROCEDURE Col(p: LONGINT): LONGINT;
BEGIN
  RETURN p - LineStart(p)
END Col;

PROCEDURE Looking(p: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (C(p + i) = s[i]) DO INC(i) END;
  RETURN (i >= LEN(s)) OR (s[i] = 0X)
END Looking;

(* A document marker, "---" or "...", at p, at the start of a line *)
PROCEDURE Marker(p: LONGINT): BOOLEAN;
BEGIN
  RETURN (Col(p) = 0) & (Looking(p, "---") OR Looking(p, "..."))
    & BlankAt(p + 3)
END Marker;

PROCEDURE Fail(p: LONGINT; msg: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  IF ~failed THEN
    failed := TRUE; COPY(msg, error);
    IF p > n THEN p := n END;
    errLine := 0;
    FOR i := 0 TO p - 1 DO IF t[i] = 0AX THEN INC(errLine) END END;
    errCol := Col(p)
  END
END Fail;

(* Skips spaces, tabs, comments and new lines from p: the next content,
   or n *)
PROCEDURE SkipToContent(p: LONGINT): LONGINT;
BEGIN
  LOOP
    WHILE (p < n) & IsWhite(t[p]) DO INC(p) END;
    IF p >= n THEN EXIT END;
    IF t[p] = "#" THEN
      WHILE (p < n) & (t[p] # 0AX) DO INC(p) END
    END;
    IF (p < n) & (t[p] = 0AX) THEN INC(p) ELSE EXIT END
  END;
  RETURN p
END SkipToContent;

(* Fails if a line's first content, at p, is indented with a tab *)
PROCEDURE CheckIndent(p: LONGINT);
  VAR q: LONGINT;
BEGIN
  q := LineStart(p);
  WHILE (q < p) & (t[q] = " ") DO INC(q) END;
  IF (q < p) & (t[q] = 09X) THEN
    q := p;
    WHILE (q > 0) & IsWhite(t[q - 1]) DO DEC(q) END;
    IF (q = 0) OR (t[q - 1] = 0AX) THEN
      Fail(p, "a tab in indentation")
    END
  END
END CheckIndent;

(* Fails unless only spaces, tabs and a comment are left on the line at
   pos *)
PROCEDURE EndOfLine;
  VAR p: LONGINT;
BEGIN
  p := pos;
  WHILE (p < n) & IsWhite(t[p]) DO INC(p) END;
  IF (p < n) & (t[p] = "#") & ((p > pos) OR (p > 0) & IsWhite(t[p - 1])) THEN
    WHILE (p < n) & (t[p] # 0AX) DO INC(p) END
  END;
  IF (p < n) & (t[p] # 0AX) THEN
    IF (t[p] = ":") & (BlankAt(p + 1) OR (p = pos)) THEN
      Fail(p, "a mapping value where none is allowed")
    ELSE
      Fail(p, "text after a value")
    END
  END;
  pos := p
END EndOfLine;

(* Nodes *)

PROCEDURE NewNode(kind: INTEGER): Node;
  VAR r: Node;
BEGIN
  NEW(r); r.kind := kind; r.style := Plain; r.text := NIL; r.len := 0;
  r.items := NIL;
  RETURN r
END NewNode;

PROCEDURE NewScalar(style: INTEGER; VAR b: Buf): Node;
  VAR r: Node;
BEGIN
  r := NewNode(Scalar); r.style := style; r.text := Copy(b); r.len := b.len;
  RETURN r
END NewScalar;

PROCEDURE EmptyScalar(): Node;
  VAR b: Buf;
BEGIN
  InitBuf(b);
  RETURN NewScalar(Plain, b)
END EmptyScalar;

PROCEDURE SameText(a, b: Node): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  IF a.len # b.len THEN RETURN FALSE END;
  i := 0;
  WHILE (i < a.len) & (a.text[i] = b.text[i]) DO INC(i) END;
  RETURN i = a.len
END SameText;

(* Appends value to the sequence s; last is its last item *)
PROCEDURE AddItem(s: Node; VAR last: Pair; value: Node);
  VAR p: Pair;
BEGIN
  NEW(p); p.key := NIL; p.value := value; p.next := NIL;
  IF last = NIL THEN s.items := p ELSE last.next := p END;
  last := p
END AddItem;

(* Adds key and value to the mapping m (path is m's); last is its last
   pair. A key already there takes the new value, with a warning. *)
PROCEDURE AddPair(m: Node; VAR last: Pair; key, value: Node);
  VAR p: Pair; w: Warning; b: Buf;
BEGIN
  p := m.items;
  WHILE (p # NIL) & ~SameText(p.key, key) DO p := p.next END;
  IF p # NIL THEN
    p.value := value;
    InitBuf(b); PutString(b, "Duplicate key: ");
    PutText(b, path.t, path.len); PutChar(b, ".");
    PutText(b, key.text, key.len);
    NEW(w); w.text := Copy(b); w.next := warnings; warnings := w
  ELSE
    NEW(p); p.key := key; p.value := value; p.next := NIL;
    IF last = NIL THEN m.items := p ELSE last.next := p END;
    last := p
  END
END AddPair;

PROCEDURE PathKey(key: Node);
BEGIN
  PutChar(path, "."); PutText(path, key.text, key.len)
END PathKey;

PROCEDURE PathIndex(i: LONGINT);
  VAR d: ARRAY 24 OF CHAR; k: INTEGER;
BEGIN
  PutChar(path, "[");
  k := 0;
  REPEAT d[k] := CHR(ORD("0") + i MOD 10); i := i DIV 10; INC(k) UNTIL i = 0;
  WHILE k > 0 DO DEC(k); PutChar(path, d[k]) END;
  PutChar(path, "]")
END PathIndex;

PROCEDURE PathTo(len: LONGINT);
BEGIN
  path.len := len; path.t[len] := 0X
END PathTo;

(* Constructs not read *)

(* Fails if what starts at p is something podoc does not read *)
PROCEDURE Unsupported(p: LONGINT): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  ch := C(p);
  IF ch = "&" THEN Fail(p, "anchors are not supported")
  ELSIF ch = "*" THEN Fail(p, "aliases are not supported")
  ELSIF ch = "!" THEN Fail(p, "tags are not supported")
  ELSIF (ch = "%") & (Col(p) = 0) THEN Fail(p, "directives are not supported")
  ELSIF (ch = "?") & BlankAt(p + 1) THEN
    Fail(p, "complex keys are not supported")
  ELSIF (ch = "@") OR (ch = "`") THEN
    Fail(p, "a reserved character cannot start a plain scalar")
  END;
  RETURN failed
END Unsupported;

(* Scalars *)

(* A plain scalar starts at p *)
PROCEDURE PlainStart(p: LONGINT; flow: BOOLEAN): BOOLEAN;
  VAR ch: CHAR;
BEGIN
  ch := C(p);
  IF (ch = "-") OR (ch = "?") OR (ch = ":") THEN
    RETURN ~BlankAt(p + 1) & ~(flow & IsFlowIndicator(C(p + 1)))
  END;
  RETURN (p < n) & ~BlankAt(p) & ~IsFlowIndicator(ch)
    & (ch # "#") & (ch # "&") & (ch # "*") & (ch # "!") & (ch # "|")
    & (ch # ">") & (ch # "'") & (ch # 22X) & (ch # "%") & (ch # "@")
    & (ch # "`")
END PlainStart;

(* A plain scalar at pos, into b. In block context its later lines are
   indented more than parent; in flow context it stops at flow
   indicators. multi is FALSE for a key, which has one line. *)
PROCEDURE ScanPlain(VAR b: Buf; parent: LONGINT; flow, multi: BOOLEAN);
  VAR ch: CHAR; keep, q, breaks: LONGINT; more: BOOLEAN;
BEGIN
  keep := b.len;
  LOOP
    LOOP
      ch := C(pos);
      IF (pos >= n) OR (ch = 0AX) THEN EXIT END;
      IF (ch = ":") & (BlankAt(pos + 1)
          OR flow & IsFlowIndicator(C(pos + 1))) THEN EXIT END;
      IF flow & IsFlowIndicator(ch) THEN EXIT END;
      IF (ch = "#") & (pos > 0) & IsWhite(t[pos - 1]) THEN EXIT END;
      PutChar(b, ch);
      IF ~IsWhite(ch) THEN keep := b.len END;
      INC(pos)
    END;
    b.len := keep; b.t[keep] := 0X;
    IF ~multi OR (pos >= n) OR (t[pos] # 0AX) THEN EXIT END;
    (* the next line, past any blank ones *)
    q := pos; breaks := 0;
    LOOP
      INC(q);
      WHILE (q < n) & IsWhite(t[q]) DO INC(q) END;
      IF (q < n) & (t[q] = 0AX) THEN INC(breaks) ELSE EXIT END
    END;
    more := (q < n) & (t[q] # "#") & ~Marker(q);
    IF more & flow THEN
      ch := t[q];
      more := ~IsFlowIndicator(ch) & ~((ch = ":") & (BlankAt(q + 1)
        OR IsFlowIndicator(C(q + 1))))
    ELSIF more THEN
      more := Col(q) > parent
    END;
    IF ~more THEN EXIT END;
    IF breaks = 0 THEN PutChar(b, " ") ELSE PutBreaks(b, breaks) END;
    keep := b.len; pos := q
  END
END ScanPlain;

PROCEDURE HexValue(ch: CHAR): INTEGER;
BEGIN
  IF (ch >= "0") & (ch <= "9") THEN RETURN ORD(ch) - ORD("0")
  ELSIF (ch >= "a") & (ch <= "f") THEN RETURN ORD(ch) - ORD("a") + 10
  ELSIF (ch >= "A") & (ch <= "F") THEN RETURN ORD(ch) - ORD("A") + 10
  END;
  RETURN -1
END HexValue;

(* A double-quoted escape at pos, after its backslash, into b *)
PROCEDURE Escape(VAR b: Buf);
  VAR ch: CHAR; k, i, v, c: LONGINT;
BEGIN
  ch := C(pos); INC(pos); k := 0;
  CASE ch OF
    "0": PutChar(b, 0X)
  | "a": PutChar(b, 07X)
  | "b": PutChar(b, 08X)
  | "t", 09X: PutChar(b, 09X)
  | "n": PutChar(b, 0AX)
  | "v": PutChar(b, 0BX)
  | "f": PutChar(b, 0CX)
  | "r": PutChar(b, 0DX)
  | "e": PutChar(b, 1BX)
  | " ", 22X, "/", "\": PutChar(b, ch)
  | "N": PutUtf8(b, 85H)
  | "_": PutUtf8(b, 0A0H)
  | "L": PutUtf8(b, 2028H)
  | "P": PutUtf8(b, 2029H)
  | "x": k := 2
  | "u": k := 4
  | "U": k := 8
  ELSE
    Fail(pos - 1, "an unknown escape in a double-quoted scalar")
  END;
  IF k > 0 THEN
    c := 0;
    FOR i := 1 TO k DO
      v := HexValue(C(pos));
      IF v < 0 THEN
        Fail(pos, "a bad hexadecimal escape"); RETURN
      END;
      c := c * 16 + v; INC(pos)
    END;
    IF (c > 10FFFFH) OR (c >= 0D800H) & (c <= 0DFFFH) THEN
      Fail(pos, "an escape that is not a Unicode character")
    ELSE
      PutUtf8(b, c)
    END
  END
END Escape;

(* A quoted scalar at pos, its opening quote q, into b *)
PROCEDURE ScanQuoted(VAR b: Buf; q: CHAR);
  VAR ch: CHAR; keep, breaks: LONGINT;
BEGIN
  INC(pos); keep := b.len;
  LOOP
    IF pos >= n THEN Fail(pos, "a quoted scalar without its closing quote") END;
    IF failed THEN EXIT END;
    ch := t[pos];
    IF ch = q THEN
      IF (q = "'") & (C(pos + 1) = "'") THEN
        PutChar(b, "'"); keep := b.len; INC(pos, 2)
      ELSE
        INC(pos); EXIT
      END
    ELSIF ch = 0AX THEN
      (* line folding: spaces before the break are dropped *)
      b.len := keep; b.t[keep] := 0X; breaks := 0;
      LOOP
        INC(pos);
        WHILE (pos < n) & IsWhite(t[pos]) DO INC(pos) END;
        IF (pos < n) & (t[pos] = 0AX) THEN INC(breaks) ELSE EXIT END
      END;
      IF Marker(pos) THEN Fail(pos, "a document marker in a quoted scalar") END;
      IF breaks = 0 THEN PutChar(b, " ") ELSE PutBreaks(b, breaks) END;
      keep := b.len
    ELSIF (ch = "\") & (q = 22X) THEN
      INC(pos);
      IF C(pos) = 0AX THEN
        (* an escaped line break: the lines are joined *)
        breaks := 0;
        LOOP
          INC(pos);
          WHILE (pos < n) & IsWhite(t[pos]) DO INC(pos) END;
          IF (pos < n) & (t[pos] = 0AX) THEN INC(breaks) ELSE EXIT END
        END;
        PutBreaks(b, breaks)
      ELSE
        Escape(b)
      END;
      keep := b.len
    ELSE
      PutChar(b, ch); INC(pos);
      IF ~IsWhite(ch) THEN keep := b.len END
    END
  END
END ScanQuoted;

(* At pos, a block scalar's empty lines and the indentation of the next
   line; indent is found from them when it is 0. Returns how many new
   lines there were. *)
PROCEDURE Breaks(VAR indent: LONGINT; parent: LONGINT): LONGINT;
  VAR k, max: LONGINT;
BEGIN
  k := 0; max := 0;
  LOOP
    WHILE (pos < n) & (t[pos] = " ") & ((indent = 0) OR (Col(pos) < indent)) DO
      INC(pos)
    END;
    IF Col(pos) > max THEN max := Col(pos) END;
    IF (pos < n) & (t[pos] = 09X) & ((indent = 0) OR (Col(pos) < indent)) THEN
      (* a tab before the indentation: a line of white space is fine *)
      WHILE (pos < n) & IsWhite(t[pos]) DO INC(pos) END;
      IF (pos < n) & (t[pos] # 0AX) THEN
        Fail(pos, "a tab in a block scalar's indentation"); RETURN k
      END
    END;
    IF (pos < n) & (t[pos] = 0AX) THEN INC(k); INC(pos) ELSE EXIT END
  END;
  IF indent = 0 THEN
    indent := max;
    IF indent < parent + 1 THEN indent := parent + 1 END;
    IF indent < 1 THEN indent := 1 END
  END;
  RETURN k
END Breaks;

(* A block scalar at pos, "|" or ">", into b. parent is the indentation
   of the collection it is in, -1 for none. *)
PROCEDURE ScanBlockScalar(VAR b: Buf; parent: LONGINT; VAR style: INTEGER);
  VAR folded, leadingBlank, trailingBlank: BOOLEAN; ch: CHAR;
    chomp, i: INTEGER; indent, leading, trailing: LONGINT;
BEGIN
  folded := t[pos] = ">"; INC(pos);
  IF folded THEN style := Folded ELSE style := Literal END;
  chomp := Clip; indent := 0;
  FOR i := 1 TO 2 DO
    ch := C(pos);
    IF (ch = "+") & (chomp = Clip) THEN chomp := Keep; INC(pos)
    ELSIF (ch = "-") & (chomp = Clip) THEN chomp := Strip; INC(pos)
    ELSIF (ch >= "1") & (ch <= "9") & (indent = 0) THEN
      indent := ORD(ch) - ORD("0"); INC(pos);
      IF parent >= 0 THEN INC(indent, parent) END
    ELSIF ch = "0" THEN
      Fail(pos, "a block scalar's indentation indicator of 0"); RETURN
    END
  END;
  EndOfLine;
  IF failed THEN RETURN END;
  IF pos < n THEN INC(pos) END;
  trailing := Breaks(indent, parent);
  leading := 0; leadingBlank := FALSE;
  WHILE ~failed & (pos < n) & (Col(pos) = indent) DO
    trailingBlank := IsWhite(t[pos]);
    IF folded & (leading = 1) & ~leadingBlank & ~trailingBlank THEN
      IF trailing = 0 THEN PutChar(b, " ") END
    ELSE
      PutBreaks(b, leading)
    END;
    leading := 0;
    PutBreaks(b, trailing); trailing := 0;
    leadingBlank := IsWhite(t[pos]);
    WHILE (pos < n) & (t[pos] # 0AX) DO PutChar(b, t[pos]); INC(pos) END;
    IF pos < n THEN
      leading := 1; INC(pos);
      trailing := Breaks(indent, parent)
    END
  END;
  IF chomp # Strip THEN PutBreaks(b, leading) END;
  IF chomp = Keep THEN PutBreaks(b, trailing) END
END ScanBlockScalar;

(* Collections *)

PROCEDURE^ BlockNode(col, parent: LONGINT): Node;
PROCEDURE^ FlowNode(): Node;

(* Skips white space, new lines and comments in a flow collection *)
PROCEDURE SkipFlow;
BEGIN
  pos := SkipToContent(pos);
  IF Marker(pos) THEN Fail(pos, "a document marker in a flow collection") END
END SkipFlow;

(* A ":" that makes what is before it a key in a flow collection;
   adjacent is TRUE after a quoted scalar or a collection, where the ":"
   need not be followed by a space *)
PROCEDURE FlowColon(adjacent: BOOLEAN): BOOLEAN;
BEGIN
  RETURN (C(pos) = ":") & (adjacent OR BlankAt(pos + 1)
    OR IsFlowIndicator(C(pos + 1)))
END FlowColon;

(* A scalar or collection in a flow collection, at pos; adjacent says
   whether a ":" may follow it directly *)
PROCEDURE FlowEntry(VAR adjacent: BOOLEAN): Node;
  VAR b: Buf; ch: CHAR; r: Node;
BEGIN
  SkipFlow;
  IF failed OR Unsupported(pos) THEN RETURN NIL END;
  ch := C(pos); adjacent := TRUE;
  IF (ch = "[") OR (ch = "{") THEN RETURN FlowNode() END;
  InitBuf(b);
  IF ch = "'" THEN ScanQuoted(b, ch); r := NewScalar(SingleQuoted, b)
  ELSIF ch = 22X THEN ScanQuoted(b, ch); r := NewScalar(DoubleQuoted, b)
  ELSIF PlainStart(pos, TRUE) THEN
    adjacent := FALSE;
    ScanPlain(b, -1, TRUE, TRUE); r := NewScalar(Plain, b)
  ELSIF pos >= n THEN
    Fail(pos, "a flow collection without its end"); r := NIL
  ELSE
    Fail(pos, "no value where one was expected"); r := NIL
  END;
  RETURN r
END FlowEntry;

(* After an entry: "," or the closing character close *)
PROCEDURE FlowNext(close: CHAR): BOOLEAN;
BEGIN
  SkipFlow;
  IF failed THEN RETURN FALSE END;
  IF C(pos) = "," THEN INC(pos); RETURN TRUE
  ELSIF C(pos) = close THEN RETURN TRUE
  ELSIF pos >= n THEN Fail(pos, "a flow collection without its end")
  ELSE Fail(pos, "no ',' between flow entries")
  END;
  RETURN FALSE
END FlowNext;

(* A key's value in a flow collection, after its ":" *)
PROCEDURE FlowValue(close: CHAR): Node;
  VAR adjacent: BOOLEAN;
BEGIN
  INC(pos); SkipFlow;
  IF (C(pos) = ",") OR (C(pos) = close) THEN RETURN EmptyScalar() END;
  RETURN FlowEntry(adjacent)
END FlowValue;

(* A flow sequence or mapping at pos *)
PROCEDURE FlowNode(): Node;
  VAR r, key, value, m: Node; last, ml: Pair; close: CHAR;
    adjacent: BOOLEAN; plen, i: LONGINT;
BEGIN
  plen := path.len;
  IF t[pos] = "[" THEN r := NewNode(Sequence); close := "]"
  ELSE r := NewNode(Mapping); close := "}"
  END;
  INC(pos); last := NIL; i := 0;
  LOOP
    SkipFlow;
    IF failed THEN EXIT END;
    IF C(pos) = close THEN INC(pos); EXIT END;
    IF r.kind = Sequence THEN PathIndex(i) END;
    key := FlowEntry(adjacent);
    IF failed THEN EXIT END;
    SkipFlow;
    IF (r.kind = Mapping) OR FlowColon(adjacent) THEN
      IF key.kind # Scalar THEN Fail(pos, "complex keys are not supported"); EXIT END;
      PathKey(key);
      IF FlowColon(adjacent) THEN value := FlowValue(close)
      ELSE value := EmptyScalar()
      END;
      IF failed THEN EXIT END;
      IF r.kind = Mapping THEN
        PathTo(plen); AddPair(r, last, key, value)
      ELSE
        (* a single pair mapping *)
        m := NewNode(Mapping); ml := NIL;
        PathTo(path.len - key.len - 1);
        AddPair(m, ml, key, value);
        AddItem(r, last, m)
      END
    ELSE
      AddItem(r, last, key)
    END;
    PathTo(plen); INC(i);
    IF ~FlowNext(close) THEN EXIT END
  END;
  PathTo(plen);
  RETURN r
END FlowNode;

(* A scalar or flow collection at pos, which ends its line; parent is
   the indentation of the collection it is in *)
PROCEDURE InlineNode(parent: LONGINT): Node;
  VAR b: Buf; ch: CHAR; r: Node; style: INTEGER;
BEGIN
  IF Unsupported(pos) THEN RETURN NIL END;
  ch := t[pos]; InitBuf(b);
  IF (ch = "[") OR (ch = "{") THEN r := FlowNode(); EndOfLine
  ELSIF ch = "'" THEN ScanQuoted(b, ch); r := NewScalar(SingleQuoted, b); EndOfLine
  ELSIF ch = 22X THEN ScanQuoted(b, ch); r := NewScalar(DoubleQuoted, b); EndOfLine
  ELSIF (ch = "|") OR (ch = ">") THEN
    ScanBlockScalar(b, parent, style); r := NewScalar(style, b)
  ELSIF (ch = "-") & BlankAt(pos + 1) THEN
    Fail(pos, "a sequence where it is not allowed"); r := NIL
  ELSIF PlainStart(pos, FALSE) THEN
    ScanPlain(b, parent, FALSE, TRUE); r := NewScalar(Plain, b); EndOfLine
  ELSE
    Fail(pos, "a character that cannot start a value"); r := NIL
  END;
  RETURN r
END InlineNode;

(* Whether the line at p starts with a key and its ":" *)
PROCEDURE IsKey(p: LONGINT): BOOLEAN;
  VAR ch, q: CHAR;
BEGIN
  q := C(p);
  IF (q = "'") OR (q = 22X) THEN
    INC(p);
    LOOP
      ch := C(p);
      IF (p >= n) OR (ch = 0AX) THEN RETURN FALSE END;
      IF (ch = "\") & (q = 22X) THEN INC(p, 2)
      ELSIF (ch = q) & (q = "'") & (C(p + 1) = "'") THEN INC(p, 2)
      ELSIF ch = q THEN INC(p); EXIT
      ELSE INC(p)
      END
    END;
    WHILE IsWhite(C(p)) DO INC(p) END;
    RETURN (C(p) = ":") & BlankAt(p + 1)
  ELSIF PlainStart(p, FALSE) THEN
    LOOP
      ch := C(p);
      IF (p >= n) OR (ch = 0AX) THEN RETURN FALSE END;
      IF (ch = ":") & BlankAt(p + 1) THEN RETURN TRUE END;
      IF (ch = "#") & IsWhite(t[p - 1]) THEN RETURN FALSE END;
      INC(p)
    END
  END;
  RETURN FALSE
END IsKey;

(* A value after a key's ":" (inMap) or a sequence entry's "-", at
   pos; parent is the column of the key or the "-" *)
PROCEDURE Value(parent: LONGINT; inMap: BOOLEAN): Node;
  VAR q, c: LONGINT;
BEGIN
  WHILE (pos < n) & IsWhite(t[pos]) DO INC(pos) END;
  IF (pos >= n) OR (t[pos] = 0AX) OR (t[pos] = "#") THEN
    q := SkipToContent(pos);
    IF (q >= n) OR Marker(q) THEN RETURN EmptyScalar() END;
    c := Col(q);
    IF (c > parent) OR inMap & (c = parent) & (t[q] = "-") & BlankAt(q + 1) THEN
      CheckIndent(q);
      pos := q;
      RETURN BlockNode(c, parent)
    END;
    RETURN EmptyScalar()
  ELSIF inMap THEN
    RETURN InlineNode(parent)
  ELSE
    RETURN BlockNode(Col(pos), parent)
  END
END Value;

(* The next line's content, after a collection's entry: TRUE if it is
   at column col *)
PROCEDURE NextEntry(col: LONGINT; what: ARRAY OF CHAR): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  IF failed THEN RETURN FALSE END;
  q := SkipToContent(pos);
  IF (q >= n) OR Marker(q) OR (Col(q) < col) THEN RETURN FALSE END;
  CheckIndent(q);
  IF Col(q) > col THEN Fail(q, what); RETURN FALSE END;
  pos := q;
  RETURN ~failed
END NextEntry;

(* A block sequence at pos, at column col *)
PROCEDURE BlockSeq(col: LONGINT): Node;
  VAR r, v: Node; last: Pair; plen, i: LONGINT;
BEGIN
  r := NewNode(Sequence); last := NIL; plen := path.len; i := 0;
  LOOP
    IF (t[pos] # "-") OR ~BlankAt(pos + 1) THEN
      Fail(pos, "a sequence entry was expected"); EXIT
    END;
    INC(pos);
    PathIndex(i);
    v := Value(col, FALSE);
    PathTo(plen);
    IF failed THEN EXIT END;
    AddItem(r, last, v); INC(i);
    IF ~NextEntry(col, "bad indentation of a sequence entry") THEN EXIT END;
    IF t[pos] # "-" THEN EXIT END (* a key after a sequence under a key *)
  END;
  RETURN r
END BlockSeq;

(* A block mapping at pos, at column col *)
PROCEDURE BlockMap(col: LONGINT): Node;
  VAR r, key, v: Node; last: Pair; b: Buf; plen: LONGINT; ch: CHAR;
BEGIN
  r := NewNode(Mapping); last := NIL; plen := path.len;
  LOOP
    IF Unsupported(pos) THEN EXIT END;
    ch := t[pos]; InitBuf(b);
    IF ~IsKey(pos) THEN
      IF (ch = "[") OR (ch = "{") THEN Fail(pos, "complex keys are not supported")
      ELSE Fail(pos, "no key where one was expected")
      END;
      EXIT
    ELSIF ch = "'" THEN ScanQuoted(b, ch); key := NewScalar(SingleQuoted, b)
    ELSIF ch = 22X THEN ScanQuoted(b, ch); key := NewScalar(DoubleQuoted, b)
    ELSE ScanPlain(b, col, FALSE, FALSE); key := NewScalar(Plain, b)
    END;
    WHILE IsWhite(C(pos)) DO INC(pos) END;
    INC(pos); (* the ":" IsKey found *)
    PathKey(key);
    v := Value(col, TRUE);
    PathTo(plen);
    IF failed THEN EXIT END;
    AddPair(r, last, key, v);
    IF ~NextEntry(col, "bad indentation of a mapping entry") THEN EXIT END
  END;
  RETURN r
END BlockMap;

(* A node at pos, at column col; parent is the indentation of the
   collection it is in, -1 for none *)
PROCEDURE BlockNode(col, parent: LONGINT): Node;
BEGIN
  IF (t[pos] = "-") & BlankAt(pos + 1) THEN RETURN BlockSeq(col)
  ELSIF IsKey(pos) THEN RETURN BlockMap(col)
  ELSE RETURN InlineNode(parent)
  END
END BlockNode;

(* Documents *)

(* A document at pos: NIL if it is empty *)
PROCEDURE Document(): Node;
  VAR r: Node; q: LONGINT;
BEGIN
  r := NIL;
  q := SkipToContent(pos);
  IF Unsupported(q) THEN RETURN NIL END;
  IF (q < n) & Looking(q, "---") & Marker(q) THEN
    pos := q + 3;
    WHILE (pos < n) & IsWhite(t[pos]) DO INC(pos) END;
    IF (pos < n) & (t[pos] # 0AX) & (t[pos] # "#") THEN
      RETURN InlineNode(-1)
    END;
    q := SkipToContent(pos)
  END;
  IF (q < n) & ~Marker(q) THEN
    CheckIndent(q);
    pos := q;
    IF ~failed THEN r := BlockNode(Col(q), -1) END
  ELSE
    pos := q
  END;
  RETURN r
END Document;

(* Reads the YAML text s[0 .. len-1] into doc, the first document, NIL
   if there is none or it is empty. CRs are ignored. FALSE, with error,
   errLine and errCol set, if it is not read. *)
PROCEDURE Parse*(VAR s: ARRAY OF CHAR; len: LONGINT; VAR doc: Node): BOOLEAN;
  VAR i, q: LONGINT; d: Node; first: BOOLEAN;
BEGIN
  NEW(t, len + 1); n := 0;
  FOR i := 0 TO len - 1 DO
    IF s[i] # 0DX THEN t[n] := s[i]; INC(n) END
  END;
  t[n] := 0X;
  pos := 0; failed := FALSE; error := ""; errLine := 0; errCol := 0;
  warnings := NIL; InitBuf(path);
  doc := NIL; first := TRUE;
  LOOP
    d := Document();
    IF failed THEN EXIT END;
    IF first THEN doc := d; first := FALSE END;
    q := SkipToContent(pos);
    IF q >= n THEN EXIT END;
    IF Looking(q, "...") & Marker(q) THEN
      pos := q + 3; EndOfLine;
      q := SkipToContent(pos);
      IF q >= n THEN EXIT END
    END;
    IF ~failed & ~(Looking(q, "---") & Marker(q)) THEN
      Fail(q, "text after the document's end")
    END;
    IF failed THEN EXIT END;
    pos := q
  END;
  t := NIL;
  IF failed THEN doc := NIL END;
  RETURN ~failed
END Parse;

(* Values *)

PROCEDURE Is(nd: Node; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < nd.len) & (i < LEN(s)) & (s[i] # 0X) & (nd.text[i] = s[i]) DO
    INC(i)
  END;
  RETURN (i = nd.len) & ((i >= LEN(s)) OR (s[i] = 0X))
END Is;

(* s, its upper case or its title case *)
PROCEDURE IsLike(nd: Node; s: ARRAY OF CHAR): BOOLEAN;
  VAR u, ti: ARRAY 8 OF CHAR; i: INTEGER;
BEGIN
  COPY(s, u); COPY(s, ti);
  i := 0;
  WHILE u[i] # 0X DO u[i] := CAP(u[i]); INC(i) END;
  ti[0] := CAP(ti[0]);
  RETURN Is(nd, s) OR Is(nd, u) OR Is(nd, ti)
END IsLike;

(* Decimal digits: the number 0.d[0]d[1]..d[k-1] times 10^e, with no
   leading or trailing zeros (k = 0 for zero) *)
PROCEDURE Scientific(nd: Node; VAR d: Buf; VAR e: LONGINT;
                     VAR neg: BOOLEAN): BOOLEAN;
  VAR p, base, v, i, carry, x, ex, exs, digits: LONGINT; s: Text; frac: BOOLEAN;
BEGIN
  s := nd.text; InitBuf(d); e := 0; neg := FALSE; p := 0;
  IF (nd.len > 2) & (s[0] = "0") & ((s[1] = "x") OR (s[1] = "o")) THEN
    IF s[1] = "x" THEN base := 16 ELSE base := 8 END;
    p := 2;
    (* d holds the value's decimal digits, least significant first *)
    WHILE p < nd.len DO
      v := HexValue(s[p]);
      IF (v < 0) OR (v >= base) THEN RETURN FALSE END;
      carry := v;
      FOR i := 0 TO d.len - 1 DO
        x := (ORD(d.t[i]) - ORD("0")) * base + carry;
        d.t[i] := CHR(ORD("0") + x MOD 10); carry := x DIV 10
      END;
      WHILE carry > 0 DO PutChar(d, CHR(ORD("0") + carry MOD 10)); carry := carry DIV 10 END;
      INC(p)
    END;
    (* reversed, without leading zeros *)
    WHILE (d.len > 0) & (d.t[d.len - 1] = "0") DO DEC(d.len) END;
    FOR i := 0 TO d.len DIV 2 - 1 DO
      x := ORD(d.t[i]); d.t[i] := d.t[d.len - 1 - i]; d.t[d.len - 1 - i] := CHR(x)
    END;
    e := d.len
  ELSE
    IF (p < nd.len) & ((s[p] = "+") OR (s[p] = "-")) THEN
      neg := s[p] = "-"; INC(p)
    END;
    IF ~((p < nd.len) & (s[p] >= "0") & (s[p] <= "9")) THEN RETURN FALSE END;
    frac := FALSE; digits := 0;
    WHILE p < nd.len DO
      IF (s[p] >= "0") & (s[p] <= "9") THEN
        IF (d.len > 0) OR (s[p] # "0") THEN PutChar(d, s[p]);
          IF ~frac THEN INC(e) END
        ELSIF frac THEN DEC(e)
        END;
        INC(p)
      ELSIF (s[p] = ".") & ~frac THEN frac := TRUE; INC(p)
      ELSE
        IF (s[p] # "e") & (s[p] # "E") THEN RETURN FALSE END;
        INC(p); exs := 1;
        IF (p < nd.len) & ((s[p] = "+") OR (s[p] = "-")) THEN
          IF s[p] = "-" THEN exs := -1 END; INC(p)
        END;
        IF p >= nd.len THEN RETURN FALSE END;
        ex := 0;
        WHILE p < nd.len DO
          IF (s[p] < "0") OR (s[p] > "9") THEN RETURN FALSE END;
          IF ex < 100000000 THEN ex := ex * 10 + ORD(s[p]) - ORD("0") END;
          INC(p)
        END;
        e := e + exs * ex
      END
    END;
    WHILE (d.len > 0) & (d.t[d.len - 1] = "0") DO DEC(d.len) END;
    d.t[d.len] := 0X
  END;
  IF d.len = 0 THEN e := 0; neg := FALSE END;
  RETURN TRUE
END Scientific;

(* What the scalar nd is to Data.Yaml: Null, Bool (b says which),
   Number or String *)
PROCEDURE Resolve*(nd: Node; VAR b: BOOLEAN): INTEGER;
  VAR d: Buf; e: LONGINT; neg: BOOLEAN;
BEGIN
  b := FALSE;
  IF (nd.style # Plain) & (nd.style # Literal) THEN RETURN String END;
  IF Is(nd, "null") OR Is(nd, "Null") OR Is(nd, "NULL") OR Is(nd, "~")
      OR (nd.len = 0) THEN
    RETURN Null
  END;
  IF IsLike(nd, "y") OR IsLike(nd, "yes") OR IsLike(nd, "on")
      OR IsLike(nd, "true") THEN
    b := TRUE; RETURN Bool
  END;
  IF IsLike(nd, "n") OR IsLike(nd, "no") OR IsLike(nd, "off")
      OR IsLike(nd, "false") THEN
    RETURN Bool
  END;
  IF Scientific(nd, d, e, neg) THEN RETURN Number END;
  RETURN String
END Resolve;

PROCEDURE PutNumber(VAR b: Buf; x: LONGINT);
  VAR d: ARRAY 24 OF CHAR; k: INTEGER;
BEGIN
  IF x < 0 THEN PutChar(b, "-"); x := -x END;
  k := 0;
  REPEAT d[k] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(k) UNTIL x = 0;
  WHILE k > 0 DO DEC(k); PutChar(b, d[k]) END
END PutNumber;

(* The number nd, which Resolve found to be one, as pandoc shows it: as
   an integer if it is one that fits in 64 bits, otherwise as Haskell's
   Scientific shows it *)
PROCEDURE NumberText*(nd: Node; VAR s: Text; VAR len: LONGINT);
  VAR d, b: Buf; e, i: LONGINT; neg, int: BOOLEAN; lim: ARRAY 20 OF CHAR;
BEGIN
  IF ~Scientific(nd, d, e, neg) THEN s := nd.text; len := nd.len; RETURN END;
  InitBuf(b);
  int := e >= d.len;
  IF int & (e > 19) THEN
    int := FALSE
  ELSIF int & (e = 19) THEN
    (* the 19 digits against the limit *)
    IF neg THEN COPY("9223372036854775808", lim)
    ELSE COPY("9223372036854775807", lim)
    END;
    FOR i := d.len TO 18 DO PutChar(d, "0") END;
    i := 0;
    WHILE (i < 19) & (d.t[i] = lim[i]) DO INC(i) END;
    int := (i = 19) OR (d.t[i] < lim[i]);
    WHILE (d.len > 0) & (d.t[d.len - 1] = "0") DO DEC(d.len) END
  END;
  IF neg THEN PutChar(b, "-") END;
  IF d.len = 0 THEN
    PutChar(b, "0")
  ELSIF int THEN
    PutText(b, d.t, d.len);
    FOR i := d.len TO e - 1 DO PutChar(b, "0") END
  ELSIF (e < 0) OR (e > 7) THEN
    PutChar(b, d.t[0]); PutChar(b, ".");
    IF d.len = 1 THEN PutChar(b, "0")
    ELSE FOR i := 1 TO d.len - 1 DO PutChar(b, d.t[i]) END
    END;
    PutChar(b, "e"); PutNumber(b, e - 1)
  ELSIF e = 0 THEN
    PutString(b, "0."); PutText(b, d.t, d.len)
  ELSE
    FOR i := 0 TO e - 1 DO
      IF i < d.len THEN PutChar(b, d.t[i]) ELSE PutChar(b, "0") END
    END;
    PutChar(b, ".");
    IF e >= d.len THEN PutChar(b, "0")
    ELSE FOR i := e TO d.len - 1 DO PutChar(b, d.t[i]) END
    END
  END;
  s := Copy(b); len := b.len
END NumberText;

END PdYaml.
