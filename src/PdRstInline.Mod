MODULE PdRstInline;
(* PdRstInline: the reStructuredText reader's inlines
   (Text.Pandoc.Readers.RST, inline and the parsers it chooses among),
   with its tables of reference keys and custom roles.

   It parses PdMdBase's current text, as the markdown reader's inlines
   do, and shares PdMdInline's helpers. Inline parses one inline at
   PdMdBase.pos and appends it to a list, as pandoc's Builder joins
   inlines (PdAst.Append); when a parser fails, the position and the
   state go back as Parsec's try puts them.

   References, notes and substitutions cannot be resolved until the
   whole document has been read: as pandoc does, they are left as
   links whose targets start with ##REF##, ##NOTE## and ##SUBST##, which
   PdRst replaces. *)

IMPORT Ropes, Utf8, Unicode, A := PdAst, B := PdMdBase, MI := PdMdInline,
  W := PdWords;

CONST
  TableSize = 1024; (* buckets in the key table *)
  MaxDepth* = 64; (* the texts deeper than this are not located *)
  OrgUnknown* = 0; OrgOffset* = 1; OrgLines* = 2;

TYPE
  Name* = B.Text;
  (* A reference key: the target src (and title) and attributes of the
     links that name it *)
  Key* = POINTER TO KeyDesc;
  KeyDesc* = RECORD
    key*, src*, title*: A.Rope;
    attr*: A.Attr;
    next: Key
  END;

  (* A custom role, from the role directive *)
  Role = POINTER TO RoleDesc;
  RoleDesc = RECORD
    name, base, fmt: A.Rope;
    attr: A.Attr;
    next: Role
  END;

  (* The parser's state, saved to go back to *)
  Mark = RECORD
    pos, lastStrPos, lastStrText: LONGINT
  END;

VAR
  (* Where each text B.Enter entered, by B.depth, for reporting:
     OrgUnknown, at the start of the block holding it (blockStart of
     the depth above); OrgOffset, at orgA in the text above; OrgLines,
     line orgA, after column orgB, of the file orgName *)
  orgKind*: ARRAY MaxDepth OF INTEGER;
  orgA*, orgB*, blockStart*: ARRAY MaxDepth OF LONGINT;
  orgText*: ARRAY MaxDepth OF B.Text;
  orgName*: ARRAY MaxDepth OF Name;
  (* called for an interpreted text role that is not known, with where
     it starts in B.t *)
  unknownRole*: PROCEDURE (role: A.Rope; pos: LONGINT);
  rolePos: LONGINT;
  keys: ARRAY TableSize OF Key;
  keyCount*: LONGINT; (* M.size stateKeys *)
  roles: Role;
  defaultRole*: A.Rope; (* stateRstDefaultRole *)

PROCEDURE^ Inline*(VAR l: A.Inlines): BOOLEAN;

(* State *)

PROCEDURE Save(VAR m: Mark);
BEGIN
  m.pos := B.pos; m.lastStrPos := B.lastStrPos; m.lastStrText := B.lastStrText
END Save;

PROCEDURE Restore(VAR m: Mark);
BEGIN
  B.pos := m.pos; B.lastStrPos := m.lastStrPos; B.lastStrText := m.lastStrText
END Restore;

PROCEDURE Again(VAR m: Mark): BOOLEAN;
BEGIN
  Restore(m);
  RETURN TRUE
END Again;

PROCEDURE UpdateLastStrPos;
BEGIN
  B.lastStrPos := B.pos; B.lastStrText := B.textId
END UpdateLastStrPos;

(* Keys *)

PROCEDURE Bucket(key: A.Rope): LONGINT;
BEGIN
  RETURN SHORT(Ropes.Hash(key) MOD TableSize)
END Bucket;

(* The key key, or NIL *)
PROCEDURE FindKey*(key: A.Rope): Key;
  VAR k: Key;
BEGIN
  k := keys[Bucket(key)];
  WHILE (k # NIL) & ~Ropes.Equal(k.key, key) DO k := k.next END;
  RETURN k
END FindKey;

(* M.insert key ((src, title), attr) stateKeys *)
PROCEDURE SetKey*(key, src, title: A.Rope; attr: A.Attr);
  VAR k: Key; b: LONGINT;
BEGIN
  k := FindKey(key);
  IF k = NIL THEN
    NEW(k); k.key := key; b := Bucket(key);
    k.next := keys[b]; keys[b] := k; INC(keyCount)
  END;
  k.src := src; k.title := title; k.attr := attr
END SetKey;

(* Removes the key key *)
PROCEDURE DeleteKey*(key: A.Rope);
  VAR k, p: Key; b: LONGINT;
BEGIN
  b := Bucket(key); k := keys[b]; p := NIL;
  WHILE (k # NIL) & ~Ropes.Equal(k.key, key) DO p := k; k := k.next END;
  IF k # NIL THEN
    IF p = NIL THEN keys[b] := k.next ELSE p.next := k.next END;
    DEC(keyCount)
  END
END DeleteKey;

(* The least of the anonymous keys (those that start with _), or NIL *)
PROCEDURE FirstAnonymous*(): A.Rope;
  VAR i: LONGINT; k: Key; best: A.Rope;
BEGIN
  best := NIL;
  FOR i := 0 TO TableSize - 1 DO
    k := keys[i];
    WHILE k # NIL DO
      IF (Ropes.Length(k.key) > 0) & (Ropes.Fetch(k.key, 0) = "_")
          & ((best = NIL) OR (Ropes.Compare(k.key, best) < 0)) THEN
        best := k.key
      END;
      k := k.next
    END
  END;
  RETURN best
END FirstAnonymous;

(* toKey of the rope r *)
PROCEDURE RopeKey*(r: A.Rope): A.Rope;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b); MI.PutRope(b, r);
  IF b.len = 0 THEN B.PutChar(b, 0X) END;
  RETURN MI.Key(b.t^, 0, b.len, TRUE)
END RopeKey;

(* Records where the text B.Enter has just entered came from; see
   orgKind *)
PROCEDURE SetOrigin*(kind: INTEGER; a, b: LONGINT; name: Name);
  VAR d: INTEGER;
BEGIN
  d := B.depth;
  IF (d >= 0) & (d < MaxDepth) THEN
    orgKind[d] := kind; orgA[d] := a; orgB[d] := b; orgName[d] := name;
    orgText[d] := B.t; blockStart[d] := 0
  END
END SetOrigin;

(* Readies the reader for a new document. *)
PROCEDURE Reset*;
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO TableSize - 1 DO keys[i] := NIL END;
  keyCount := 0; roles := NIL;
  defaultRole := A.S("title-reference")
END Reset;

(* Text *)

PROCEDURE IsSp(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
END IsSp;

(* B.text of s[from .. to-1], appended to l: its words as Strs, the
   white space between them as Space, or SoftBreak if it has a new
   line. *)
PROCEDURE AddTextOf*(VAR s: ARRAY OF CHAR; from, to: LONGINT; VAR l: A.Inlines);
  VAR p, q: LONGINT; nl: BOOLEAN;
BEGIN
  p := from;
  WHILE p < to DO
    q := p;
    IF IsSp(s[p]) THEN
      nl := FALSE;
      WHILE (q < to) & IsSp(s[q]) DO
        IF (s[q] = 0AX) OR (s[q] = 0DX) THEN nl := TRUE END;
        INC(q)
      END;
      IF nl THEN A.Append(l, A.NewSimple(A.SoftBreak))
      ELSE A.Append(l, A.NewSimple(A.Space))
      END
    ELSE
      WHILE (q < to) & ~IsSp(s[q]) DO INC(q) END;
      A.Append(l, A.NewStr(Ropes.FromSubchars(s, from + (p - from), q - p)))
    END;
    p := q
  END
END AddTextOf;

(* B.text of the rope r, as inlines *)
PROCEDURE TextOf*(r: A.Rope): A.Inline;
  VAR b: B.Buf; l: A.Inlines;
BEGIN
  A.InitInlines(l);
  IF Ropes.Length(r) > 0 THEN
    B.InitBuf(b); MI.PutRope(b, r);
    AddTextOf(b.t^, 0, b.len, l)
  END;
  RETURN l.first
END TextOf;

(* B.text of the current text's t[from .. to-1] *)
PROCEDURE AddText(VAR l: A.Inlines; from, to: LONGINT);
BEGIN
  AddTextOf(B.t^, from, to, l)
END AddText;

(* Whether c is a space, tab, new line or carriage return (trim) *)
PROCEDURE IsTrim(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c = " ") OR (c = 09X) OR (c = 0AX) OR (c = 0DX)
END IsTrim;

(* trim: b without white space at its ends *)
PROCEDURE TrimBuf*(VAR b: B.Buf);
  VAR s, i: LONGINT;
BEGIN
  WHILE (b.len > 0) & IsTrim(b.t[b.len - 1]) DO DEC(b.len) END;
  s := 0;
  WHILE (s < b.len) & IsTrim(b.t[s]) DO INC(s) END;
  IF s > 0 THEN
    FOR i := s TO b.len - 1 DO b.t[i - s] := b.t[i] END;
    DEC(b.len, s)
  END;
  b.t[b.len] := 0X
END TrimBuf;

(* Characters *)

(* The length of the special character (specialChars) at p, or 0 *)
PROCEDURE SpecialAt*(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  IF p >= B.len THEN RETURN 0 END;
  ch := B.t[p];
  CASE ch OF
  | "\", "`", "|", "*", "_", "<", ">", "$", ":", "/", "[", "]", "{", "}",
    "(", ")", "-", ".", 22X, 27X:
      RETURN 1
  | 0E2X:
      IF (B.C(p + 1) = 80X) & ((B.C(p + 2) = 98X) OR (B.C(p + 2) = 99X)
          OR (B.C(p + 2) = 9CX) OR (B.C(p + 2) = 9DX)) THEN
        RETURN 3
      END
  ELSE
  END;
  RETURN 0
END SpecialAt;

(* canPrecedeOpener *)
PROCEDURE CanPrecedeOpener(r: Utf8.Rune): BOOLEAN;
  VAR c: INTEGER;
BEGIN
  c := Unicode.Category(r);
  RETURN (c = Unicode.Ps) OR (c = Unicode.Pi) OR (c = Unicode.Pf)
    OR (c = Unicode.Pd) OR (c = Unicode.So)
END CanPrecedeOpener;

(* Whether c is one of underlineChars *)
PROCEDURE IsUnderlineChar*(c: CHAR): BOOLEAN;
BEGIN
  RETURN (c > " ") & (c < 7FX) & ~((c >= "0") & (c <= "9")
    OR (c >= "a") & (c <= "z") OR (c >= "A") & (c <= "Z"))
END IsUnderlineChar;

(* hrule at p: where the blank lines after it end, or -1 *)
PROCEDURE Hrule*(p: LONGINT): LONGINT;
  VAR c: CHAR; q: LONGINT;
BEGIN
  c := B.C(p);
  IF ~IsUnderlineChar(c) THEN RETURN -1 END;
  q := p + 1;
  WHILE B.C(q) = c DO INC(q) END;
  IF q - p < 4 THEN RETURN -1 END;
  q := B.BlankLine(q);
  IF q < 0 THEN RETURN -1 END;
  RETURN B.BlankLines(q)
END Hrule;

(* bulletListStart at p: the position after the marker and the spaces
   after it, or -1; width is their length in characters *)
PROCEDURE BulletStart*(p: LONGINT; VAR width: LONGINT): LONGINT;
  VAR q: LONGINT; ch: CHAR;
BEGIN
  IF Hrule(p) >= 0 THEN RETURN -1 END;
  ch := B.C(p);
  IF (ch = "*") OR (ch = "+") OR (ch = "-") THEN q := p + 1
  ELSIF (ch = 0E2X) & (B.C(p + 1) = 80X) & (B.C(p + 2) = 0A2X) (* • *)
      OR (ch = 0E2X) & (B.C(p + 1) = 80X) & (B.C(p + 2) = 0B3X) (* ‣ *)
      OR (ch = 0E2X) & (B.C(p + 1) = 81X) & (B.C(p + 2) = 83X) (* ⁃ *) THEN
    q := p + 3
  ELSE RETURN -1
  END;
  width := 1;
  IF B.IsSpace(B.C(q)) THEN
    WHILE B.IsSpace(B.C(q)) DO INC(q); INC(width) END
  ELSIF B.C(q) # 0AX THEN RETURN -1
  END;
  RETURN q
END BulletStart;

(* simpleReferenceName at p: its end, or -1 *)
PROCEDURE SimpleName*(p: LONGINT): LONGINT;
  VAR ch: CHAR;
BEGIN
  IF ~MI.AlnumAt(p) THEN RETURN -1 END;
  p := MI.RuneEnd(p);
  LOOP
    ch := B.C(p);
    IF MI.AlnumAt(p) THEN p := MI.RuneEnd(p)
    ELSIF ((ch = "-") OR (ch = "_") OR (ch = ":") OR (ch = "+") OR (ch = "."))
        & MI.AlnumAt(p + 1) THEN
      INC(p)
    ELSE EXIT
    END
  END;
  RETURN p
END SimpleName;

(* quotedReferenceName at p: the end; the name is t[p+1 .. end-2] *)
PROCEDURE QuotedName*(p: LONGINT): LONGINT;
BEGIN
  IF (B.C(p) # "`") OR (B.C(p + 1) = "`") THEN RETURN -1 END;
  INC(p);
  WHILE (p < B.len) & (B.t[p] # "`") DO INC(p) END;
  IF p >= B.len THEN RETURN -1 END;
  RETURN p + 1
END QuotedName;

(* noteMarker at p: the end; the reference is t[p+1 .. end-2] *)
PROCEDURE NoteMarker*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF B.C(p) # "[" THEN RETURN -1 END;
  q := p + 1;
  IF B.IsDigit(B.C(q)) THEN
    WHILE B.IsDigit(B.C(q)) DO INC(q) END
  ELSIF B.C(q) = "#" THEN
    q := SimpleName(p + 2);
    IF q < 0 THEN q := p + 2 END
  ELSIF B.C(q) = "*" THEN q := p + 2
  ELSE RETURN -1
  END;
  IF B.C(q) # "]" THEN RETURN -1 END;
  RETURN q + 1
END NoteMarker;

(* citationMarker at p: the end; the name is t[p+1 .. end-2] *)
PROCEDURE CitationMarker*(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF B.C(p) # "[" THEN RETURN -1 END;
  q := SimpleName(p + 1);
  IF (q < 0) OR (B.C(q) # "]") THEN RETURN -1 END;
  RETURN q + 1
END CitationMarker;

(* roleName at p: its end, or -1 *)
PROCEDURE RoleName*(p: LONGINT): LONGINT;
BEGIN
  RETURN SimpleName(p)
END RoleName;

(* roleMarker at p: its end, or -1; the name is t[p+1 .. end-2] *)
PROCEDURE RoleMarker(p: LONGINT): LONGINT;
  VAR q: LONGINT;
BEGIN
  IF B.C(p) # ":" THEN RETURN -1 END;
  q := RoleName(p + 1);
  IF (q < 0) OR (B.C(q) # ":") THEN RETURN -1 END;
  RETURN q + 1
END RoleMarker;

(* isURI: whether b is a URI with a known scheme *)
PROCEDURE IsURI*(VAR b: B.Buf): BOOLEAN;
  VAR n, i: LONGINT; c: CHAR;
BEGIN
  IF b.len = 0 THEN RETURN FALSE END;
  b.t[b.len] := 0X;
  n := W.Scheme(b.t, 0);
  IF (n = 0) OR (b.t[n] # ":") THEN RETURN FALSE END;
  FOR i := 0 TO b.len - 1 DO
    c := b.t[i];
    IF (c <= " ") OR (c = "<") OR (c = ">") OR (c = 22X) OR (c = "{")
        OR (c = "}") OR (c = "|") OR (c = "\") OR (c = "^") OR (c = "`")
        OR (c = 7FX) THEN
      RETURN FALSE
    END;
    IF (c = "%") & ~((i + 2 < b.len) & MI.IsHex(b.t[i + 1])
        & MI.IsHex(b.t[i + 2])) THEN
      RETURN FALSE
    END
  END;
  RETURN TRUE
END IsURI;

(* Prefixed: the rope of the string s followed by b *)
PROCEDURE Prefixed(s: ARRAY OF CHAR; r: A.Rope): A.Rope;
BEGIN
  RETURN Ropes.Cat(A.S(s), r)
END Prefixed;

(* Parsing a text on its own *)

PROCEDURE Parse(VAR s: ARRAY OF CHAR; from, n: LONGINT; here: BOOLEAN): A.Inline;
  VAR f: B.Frame; text: B.Text; i, sp, st: LONGINT; l: A.Inlines;
BEGIN
  IF n < 0 THEN n := 0 END;
  text := B.NewText(n);
  FOR i := 0 TO n - 1 DO text[i] := s[from + i] END;
  sp := B.lastStrPos; st := B.lastStrText; B.lastStrPos := -1;
  B.Enter(f, text, n);
  IF here THEN SetOrigin(OrgOffset, from, 0, NIL)
  ELSE SetOrigin(OrgUnknown, 0, 0, NIL)
  END;
  A.InitInlines(l);
  WHILE Inline(l) DO END;
  B.Leave(f);
  B.lastStrPos := sp; B.lastStrText := st;
  RETURN MI.Trim(l)
END Parse;

(* parseInlineFromText: the inlines of s[from .. from+n-1], trimmed,
   parsed on their own (parseFromString') *)
PROCEDURE ParseInlines*(VAR s: ARRAY OF CHAR; from, n: LONGINT): A.Inline;
BEGIN
  RETURN Parse(s, from, n, FALSE)
END ParseInlines;

(* ParseInlines of B.t[from .. from+n-1], the current text *)
PROCEDURE ParseSpan*(from, n: LONGINT): A.Inline;
BEGIN
  RETURN Parse(B.t^, from, n, TRUE)
END ParseSpan;

(* parseInlineFromText of a rope *)
PROCEDURE ParseRope*(r: A.Rope): A.Inline;
  VAR b: B.Buf;
BEGIN
  B.InitBuf(b); MI.PutRope(b, r);
  RETURN ParseInlines(b.t^, 0, b.len)
END ParseRope;

(* The parsers. Each parses at B.pos; if it succeeds it appends what it
   found to l, moves B.pos past it and returns TRUE. If it fails, the
   caller restores the position and the state. *)

(* whitespace *)
PROCEDURE Whitespace(VAR l: A.Inlines): BOOLEAN;
BEGIN
  IF ~B.IsSpace(B.C(B.pos)) THEN RETURN FALSE END;
  B.pos := B.SkipSpaces(B.pos);
  A.Append(l, A.NewSimple(A.Space));
  RETURN TRUE
END Whitespace;

(* str *)
PROCEDURE Str(VAR l: A.Inlines): BOOLEAN;
  VAR s, p: LONGINT; ch: CHAR;
BEGIN
  s := B.pos; p := s;
  LOOP
    IF p >= B.len THEN EXIT END;
    ch := B.t[p];
    IF (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (SpecialAt(p) > 0) THEN EXIT END;
    IF ORD(ch) < 80H THEN INC(p) ELSE p := MI.RuneEnd(p) END
  END;
  IF p = s THEN RETURN FALSE END;
  B.pos := p; UpdateLastStrPos;
  MI.AddText(l, s, p);
  RETURN TRUE
END Str;

(* Whether a list item starts at p, which ends a line in a list *)
PROCEDURE ListStartAt*(p: LONGINT): BOOLEAN;
  VAR q, num, w: LONGINT; style, delim: INTEGER; save: LONGINT;
BEGIN
  save := B.nextExample;
  q := B.ListMarker(p, TRUE, num, style, delim);
  B.nextExample := save;
  IF (q >= 0) & B.IsSpace(B.C(q)) THEN RETURN TRUE END;
  RETURN BulletStart(p, w) >= 0
END ListStartAt;

(* endline *)
PROCEDURE Endline*(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT;
BEGIN
  IF B.C(B.pos) # 0AX THEN RETURN FALSE END;
  q := B.pos + 1;
  IF B.BlankLine(q) >= 0 THEN RETURN FALSE END;
  IF (B.context = B.ListItemState) & ListStartAt(q) THEN RETURN FALSE END;
  A.Append(l, A.NewSimple(A.SoftBreak)); B.pos := q;
  RETURN TRUE
END Endline;

(* escapedChar *)
PROCEDURE EscapedChar(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; r: Utf8.Rune;
BEGIN
  IF (B.C(B.pos) # "\") OR (B.pos + 1 >= B.len) THEN RETURN FALSE END;
  q := MI.RuneAt(B.pos + 1, r);
  IF (r = ORD(" ")) OR (r = 0AH) OR (r = 0DH) THEN
    B.pos := q
  ELSE
    MI.AddText(l, B.pos + 1, q); B.pos := q;
    IF ~CanPrecedeOpener(r) THEN UpdateLastStrPos END
  END;
  RETURN TRUE
END EscapedChar;

(* symbol *)
PROCEDURE Symbol(VAR l: A.Inlines): BOOLEAN;
  VAR n, q: LONGINT; r: Utf8.Rune;
BEGIN
  n := SpecialAt(B.pos);
  IF n = 0 THEN RETURN FALSE END;
  q := MI.RuneAt(B.pos, r);
  MI.AddText(l, B.pos, B.pos + n); B.pos := B.pos + n;
  IF ~CanPrecedeOpener(r) THEN UpdateLastStrPos END;
  RETURN TRUE
END Symbol;

(* inlineContent *)
PROCEDURE InlineContent(VAR l: A.Inlines): BOOLEAN;
BEGIN
  RETURN Whitespace(l) OR Str(l) OR Endline(l) OR EscapedChar(l) OR Symbol(l)
END InlineContent;

(* code: ``text`` *)
PROCEDURE Code(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; b: B.Buf;
BEGIN
  p := B.pos;
  IF ~B.Looking(p, "``") THEN RETURN FALSE END;
  q := p + 2;
  WHILE (q < B.len) & ~B.Looking(q, "``") DO INC(q) END;
  IF q >= B.len THEN RETURN FALSE END;
  B.InitBuf(b); B.Put(b, p + 2, q);
  FOR p := 0 TO b.len - 1 DO IF b.t[p] = 0AX THEN b.t[p] := " " END END;
  TrimBuf(b);
  A.Append(l, A.NewCode(A.NewAttr(NIL), B.BufRope(b)));
  B.pos := q + 2;
  RETURN TRUE
END Code;

(* enclosed (atStart open) close inlineContent: the trimmed contents
   as kind (Emph or Strong) *)
PROCEDURE Enclosed(open: ARRAY OF CHAR; kind: INTEGER; VAR l: A.Inlines): BOOLEAN;
  VAR c: A.Inlines;
BEGIN
  IF ~B.Looking(B.pos, open) OR ~MI.NotAfterString() THEN RETURN FALSE END;
  B.pos := B.pos + LEN(open) - 1;
  IF B.IsWhite(B.C(B.pos)) THEN RETURN FALSE END;
  A.InitInlines(c);
  IF ~InlineContent(c) THEN RETURN FALSE END;
  LOOP
    IF B.Looking(B.pos, open) THEN
      B.pos := B.pos + LEN(open) - 1; EXIT
    END;
    IF ~InlineContent(c) THEN RETURN FALSE END
  END;
  A.Append(l, A.NewCont(kind, MI.Trim(c)));
  RETURN TRUE
END Enclosed;

(* note: [ref]_, after optional white space, which is dropped *)
PROCEDURE Note(VAR l: A.Inlines): BOOLEAN;
  VAR p, q: LONGINT; ref: A.Rope;
BEGIN
  p := B.SkipSpaces(B.pos);
  q := NoteMarker(p);
  IF (q < 0) OR (B.C(q) # "_") THEN RETURN FALSE END;
  ref := B.Rope(p + 1, q - 1);
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), TextOf(ref),
    Prefixed("##NOTE##", ref), NIL));
  B.pos := q + 1;
  RETURN TRUE
END Note;

(* explicitLink: `text <target>`_ *)
PROCEDURE ExplicitLink(VAR l: A.Inlines): BOOLEAN;
  VAR lab: A.Inlines; label: A.Inline; q: LONGINT; b, s: B.Buf; src, key: A.Rope;
BEGIN
  IF (B.C(B.pos) # "`") OR (B.C(B.pos + 1) = "`") THEN RETURN FALSE END;
  INC(B.pos); A.InitInlines(lab);
  LOOP
    IF B.C(B.pos) = "<" THEN INC(B.pos); EXIT END;
    IF (B.C(B.pos) = "`") OR ~InlineContent(lab) THEN RETURN FALSE END
  END;
  label := MI.Trim(lab);
  q := B.pos; B.InitBuf(b);
  LOOP
    IF q >= B.len THEN RETURN FALSE END;
    IF B.t[q] = ">" THEN EXIT END;
    IF B.t[q] = 0AX THEN
      IF B.BlankLine(q + 1) >= 0 THEN RETURN FALSE END
    ELSE B.PutChar(b, B.t[q])
    END;
    INC(q)
  END;
  q := B.SkipSpaces(q + 1);
  IF ~B.Looking(q, "`_") THEN RETURN FALSE END;
  INC(q, 2);
  IF B.C(q) = "_" THEN INC(q) END;
  TrimBuf(b);
  IF IsURI(b) THEN
    B.InitBuf(s); MI.EscapeURI(b.t^, b.len, s); src := B.BufRope(s)
  ELSIF (b.len > 0) & (b.t[b.len - 1] = "_") THEN
    src := Prefixed("##REF##", Ropes.FromSubchars(b.t^, 0, b.len - 1))
  ELSE src := B.BufRope(b)
  END;
  IF label # NIL THEN
    MI.Stringify(label, s);
    IF s.len = 0 THEN key := NIL ELSE key := MI.Key(s.t^, 0, s.len, TRUE) END;
    IF key # NIL THEN SetKey(key, src, NIL, A.NewAttr(NIL)) END
  ELSE
    label := A.NewStr(B.BufRope(b))
  END;
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), label, src, NIL));
  B.pos := q;
  RETURN TRUE
END ExplicitLink;

(* referenceLink: name_, `name`_, [name]_, and the anonymous name__ *)
PROCEDURE ReferenceLink(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, s, e: LONGINT; ref: A.Rope; c: A.Inlines;
BEGIN
  p := B.pos; q := QuotedName(p);
  IF q >= 0 THEN s := p + 1; e := q - 1
  ELSE
    q := SimpleName(p);
    IF q >= 0 THEN s := p; e := q
    ELSE q := CitationMarker(p); s := p; e := q
    END
  END;
  IF (q < 0) OR (B.C(q) # "_") THEN RETURN FALSE END;
  INC(q);
  IF B.C(q) = "_" THEN INC(q); ref := A.S("_")
  ELSE ref := B.Rope(s, e)
  END;
  IF (q < B.len) & MI.AlnumAt(q) THEN RETURN FALSE END;
  A.InitInlines(c); AddText(c, s, e);
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), c.first,
    Prefixed("##REF##", ref), NIL));
  B.pos := q;
  RETURN TRUE
END ReferenceLink;

(* autoLink: a URI or an e-mail address *)
PROCEDURE AutoLink(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; orig, src: B.Buf;
BEGIN
  B.InitBuf(orig); B.InitBuf(src);
  q := MI.Uri(B.pos, orig, src);
  IF q < 0 THEN
    B.InitBuf(orig); B.InitBuf(src);
    q := MI.Email(B.pos, orig, src)
  END;
  IF q < 0 THEN RETURN FALSE END;
  A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(B.BufRope(orig)),
    B.BufRope(src), NIL));
  B.pos := q;
  RETURN TRUE
END AutoLink;

(* inlineAnchor: _name or _`name` *)
PROCEDURE InlineAnchor(VAR l: A.Inlines): BOOLEAN;
  VAR p, q, s, e: LONGINT; name, ident: A.Rope; c: A.Inlines;
BEGIN
  p := B.pos;
  IF B.C(p) # "_" THEN RETURN FALSE END;
  q := QuotedName(p + 1);
  IF q >= 0 THEN s := p + 2; e := q - 1
  ELSE q := SimpleName(p + 1); s := p + 1; e := q
  END;
  IF q < 0 THEN RETURN FALSE END;
  name := B.Rope(s, e);
  A.InitInlines(c); AddText(c, s, e);
  ident := MI.Identifier(c.first);
  SetKey(RopeKey(name), Prefixed("#", ident), NIL, A.NewAttr(NIL));
  A.Append(l, A.NewSpan(A.NewAttr(ident), c.first));
  B.pos := q;
  RETURN TRUE
END InlineAnchor;

(* subst: |name|, or the link |name|_ *)
PROCEDURE Subst(VAR l: A.Inlines): BOOLEAN;
  VAR s: LONGINT; c: A.Inlines; ref: A.Rope; link: A.Inline;
BEGIN
  s := B.pos;
  IF B.C(s) # "|" THEN RETURN FALSE END;
  INC(B.pos);
  IF B.IsWhite(B.C(B.pos)) THEN RETURN FALSE END;
  A.InitInlines(c);
  IF ~Inline(c) THEN RETURN FALSE END;
  LOOP
    IF B.C(B.pos) = "|" THEN INC(B.pos); EXIT END;
    IF ~Inline(c) THEN RETURN FALSE END
  END;
  ref := B.Rope(s, B.pos);
  A.InitInlines(c); AddText(c, s, B.pos);
  link := A.NewLink(A.Link, A.NewAttr(NIL), c.first,
    Prefixed("##SUBST##", ref), NIL);
  IF B.C(B.pos) = "_" THEN
    INC(B.pos);
    link := A.NewLink(A.Link, A.NewAttr(NIL), link,
      Prefixed("##REF##", B.Rope(s + 1, B.pos - 2)), NIL)
  END;
  A.Append(l, link);
  RETURN TRUE
END Subst;

(* Roles *)

(* unmarkedInterpretedText at B.pos: the text between the backquotes,
   in b *)
PROCEDURE Unmarked(VAR b: B.Buf): BOOLEAN;
  VAR q, n, e: LONGINT; ch: CHAR;
BEGIN
  IF (B.C(B.pos) # "`") OR ~MI.NotAfterString() THEN RETURN FALSE END;
  q := B.pos + 1; n := 0; B.InitBuf(b);
  LOOP
    IF q >= B.len THEN RETURN FALSE END;
    ch := B.t[q];
    IF ch = "`" THEN
      IF (RoleMarker(q + 1) < 0) & MI.AlnumAt(q + 1) THEN
        B.PutChar(b, "`"); INC(q)
      ELSE EXIT
      END
    ELSIF ch = "\" THEN
      IF (q + 1 >= B.len) OR (B.t[q + 1] = 0AX) THEN RETURN FALSE END;
      e := MI.RuneEnd(q + 1); B.Put(b, q, e); q := e
    ELSIF ch = 0AX THEN
      IF B.BlankLine(q + 1) >= 0 THEN RETURN FALSE END;
      B.PutChar(b, 0AX); INC(q)
    ELSE
      B.PutChar(b, ch); INC(q)
    END;
    INC(n)
  END;
  IF n = 0 THEN RETURN FALSE END;
  B.pos := q + 1;
  RETURN TRUE
END Unmarked;

(* treatAsText: B.text of b's text, each backslash removed, and one
   space after it *)
PROCEDURE TreatAsText(VAR b: B.Buf): A.Inline;
  VAR c: B.Buf; i: LONGINT; l: A.Inlines;
BEGIN
  B.InitBuf(c); i := 0;
  WHILE i < b.len DO
    IF b.t[i] = "\" THEN
      INC(i);
      IF (i < b.len) & (b.t[i] = " ") THEN INC(i) END
    ELSE B.PutChar(c, b.t[i]); INC(i)
    END
  END;
  A.InitInlines(l); AddTextOf(c.t^, 0, c.len, l);
  RETURN l.first
END TreatAsText;

PROCEDURE Is(r: A.Rope; s: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN Ropes.EqualString(r, s)
END Is;

(* parseCite: {prefix}id{suffix} *)
PROCEDURE ParseCite(VAR s: ARRAY OF CHAR; from, to: LONGINT): A.Citation;
  CONST Start = 0; Prefix = 1; Id = 2; Suffix = 3;
  VAR st: INTEGER; i: LONGINT; pre, suf, id: B.Buf; c: A.Citation; l: A.Inlines;
BEGIN
  st := Start; B.InitBuf(pre); B.InitBuf(suf); B.InitBuf(id);
  FOR i := from TO to - 1 DO
    CASE st OF
    | Start: IF s[i] = "{" THEN st := Prefix ELSE st := Id; B.PutChar(id, s[i]) END
    | Prefix: IF s[i] = "}" THEN st := Id ELSE B.PutChar(pre, s[i]) END
    | Id: IF s[i] = "{" THEN st := Suffix ELSE B.PutChar(id, s[i]) END
    | Suffix: IF s[i] # "}" THEN B.PutChar(suf, s[i]) END
    END
  END;
  c := A.NewCitation(B.BufRope(id), A.NormalCitation, 0);
  A.InitInlines(l); AddTextOf(pre.t^, 0, pre.len, l); c.prefix := l.first;
  A.InitInlines(l); AddTextOf(suf.t^, 0, suf.len, l); c.suffix := l.first;
  RETURN c
END ParseCite;

(* cite citeType rawcite *)
PROCEDURE Cite(type: A.Rope; VAR b: B.Buf; VAR l: A.Inlines);
  VAR first, last, c: A.Citation; i, s: LONGINT;
BEGIN
  first := NIL; last := NIL; s := 0;
  FOR i := 0 TO b.len DO
    IF (i = b.len) OR (b.t[i] = ",") THEN
      c := ParseCite(b.t^, s, i);
      IF first = NIL THEN first := c ELSE last.next := c END;
      last := c; s := i + 1
    END
  END;
  IF Is(type, ":t") OR Is(type, ":ct") THEN first.mode := A.AuthorInText
  ELSIF Is(type, ":year") OR Is(type, ":yearpar") THEN first.mode := A.SuppressAuthor
  END;
  A.Append(l, A.NewCite(first, A.NewStr(B.BufRope(b))))
END Cite;

(* The number of characters of b's text *)
PROCEDURE Chars(VAR b: B.Buf): LONGINT;
  VAR i, n: LONGINT;
BEGIN
  n := 0;
  FOR i := 0 TO b.len - 1 DO
    IF (ORD(b.t[i]) < 80H) OR (ORD(b.t[i]) >= 0C0H) THEN INC(n) END
  END;
  RETURN n
END Chars;

PROCEDURE FindRole(name: A.Rope): Role;
  VAR r: Role;
BEGIN
  r := roles;
  WHILE (r # NIL) & ~Ropes.Equal(r.name, name) DO r := r.next END;
  RETURN r
END FindRole;

(* The base role (getBaseRole) of a role defined with parent *)
PROCEDURE BaseRole*(parent: A.Rope): A.Rope;
  VAR p: Role;
BEGIN
  IF parent = NIL THEN RETURN A.S("span") END;
  p := FindRole(parent);
  IF p # NIL THEN RETURN p.base END;
  RETURN parent
END BaseRole;

(* renderRole: the interpreted text b in role, appended to l *)
PROCEDURE RenderRole(VAR b: B.Buf; fmt, role: A.Rope; attr: A.Attr;
    VAR l: A.Inlines);
  VAR t: A.Rope; a: A.Attr; r: Role; n: B.Buf; i: LONGINT;
BEGIN
  IF Is(role, "sup") OR Is(role, "superscript") THEN
    A.Append(l, A.NewCont(A.Superscript, TreatAsText(b)))
  ELSIF Is(role, "sub") OR Is(role, "subscript") THEN
    A.Append(l, A.NewCont(A.Subscript, TreatAsText(b)))
  ELSIF Is(role, "mark") THEN
    a := A.NewAttr(NIL); A.AddClass(a, A.S("mark"));
    A.Append(l, A.NewSpan(a, TreatAsText(b)))
  ELSIF Is(role, "emphasis") THEN
    A.Append(l, A.NewCont(A.Emph, TreatAsText(b)))
  ELSIF Is(role, "strong") THEN
    A.Append(l, A.NewCont(A.Strong, TreatAsText(b)))
  ELSIF Is(role, "rfc-reference") OR Is(role, "RFC") THEN
    t := Prefixed("RFC ", B.BufRope(b));
    A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(t),
      Ropes.Cat(Prefixed("http://www.faqs.org/rfcs/rfc", B.BufRope(b)),
        A.S(".html")), t))
  ELSIF Is(role, "pep-reference") OR Is(role, "PEP") THEN
    t := Prefixed("PEP ", B.BufRope(b));
    B.InitBuf(n);
    FOR i := Chars(b) TO 3 DO B.PutChar(n, "0") END;
    MI.PutBuf(n, b);
    A.Append(l, A.NewLink(A.Link, A.NewAttr(NIL), A.NewStr(t),
      Ropes.Cat(Prefixed("http://www.python.org/dev/peps/pep-", B.BufRope(n)),
        A.S("/")), t))
  ELSIF Is(role, "literal") OR Is(role, "code") THEN
    A.Append(l, A.NewCode(attr, B.BufRope(b)))
  ELSIF Is(role, "math") THEN
    A.Append(l, A.NewMath(A.InlineMath, B.BufRope(b)))
  ELSIF Is(role, "title-reference") OR Is(role, "title") OR Is(role, "t") THEN
    a := A.NewAttr(NIL); A.AddClass(a, A.S("title-ref"));
    A.Append(l, A.NewSpan(a, TreatAsText(b)))
  ELSIF Is(role, "span") THEN
    A.Append(l, A.NewSpan(attr, TreatAsText(b)))
  ELSIF Is(role, "raw") THEN
    A.Append(l, A.NewRawInline(fmt, B.BufRope(b)))
  ELSIF (Ropes.Length(role) >= 4) & Is(Ropes.Substring(role, 0, 4), "cite") THEN
    Cite(Ropes.Substring(role, 4, Ropes.Length(role) - 4), b, l)
  ELSE
    r := FindRole(role);
    IF r # NIL THEN
      RenderRole(b, r.fmt, r.base, r.attr, l)
    ELSE
      IF unknownRole # NIL THEN unknownRole(role, rolePos) END;
      a := A.NewAttr(NIL); A.AddClass(a, A.S("interpreted-text"));
      A.AddKeyVal(a, A.S("role"), role);
      A.Append(l, A.NewCode(a, B.BufRope(b)))
    END
  END
END RenderRole;

(* addNewRole: defines role, inheriting from parent (span if NIL), with
   the format, language and class fields (NIL if missing; hasClass
   whether :class: was given) *)
PROCEDURE AddRole*(role, parent, format, language, class: A.Rope;
    hasFormat, hasLanguage, hasClass: BOOLEAN);
  VAR r, p: Role; base, fmt: A.Rope; attr, na: A.Attr; cls: A.StrList;
    w: B.Buf; i, s: LONGINT;

  PROCEDURE Add(c: A.Rope);
    VAR q: A.StrList;
  BEGIN
    q := na.classes;
    WHILE (q # NIL) & ~Ropes.Equal(q.s, c) DO q := q.next END;
    IF q = NIL THEN A.AddClass(na, c) END
  END Add;

BEGIN
  IF parent = NIL THEN parent := A.S("span") END;
  base := parent; fmt := NIL; attr := A.NewAttr(NIL);
  p := FindRole(parent);
  IF p # NIL THEN base := p.base; fmt := p.fmt; attr := p.attr END;
  IF Is(parent, "raw") THEN
    IF hasFormat THEN fmt := format ELSE fmt := NIL END
  END;
  na := A.NewAttr(attr.id); na.attrs := attr.attrs;
  IF hasClass THEN
    B.InitBuf(w); MI.PutRope(w, class); i := 0;
    WHILE i < w.len DO
      WHILE (i < w.len) & IsSp(w.t[i]) DO INC(i) END;
      s := i;
      WHILE (i < w.len) & ~IsSp(w.t[i]) DO INC(i) END;
      IF i > s THEN Add(Ropes.FromSubchars(w.t^, s, i - s)) END
    END
  ELSE Add(role)
  END;
  IF Is(base, "code") & hasLanguage THEN Add(language) END;
  cls := attr.classes;
  WHILE cls # NIL DO Add(cls.s); cls := cls.next END;
  r := FindRole(role);
  IF r = NIL THEN NEW(r); r.name := role; r.next := roles; roles := r END;
  r.base := base; r.fmt := fmt; r.attr := na
END AddRole;

(* interpretedRole: :role:`text` or `text`:role: or `text` *)
PROCEDURE InterpretedRole(VAR l: A.Inlines): BOOLEAN;
  VAR q: LONGINT; role: A.Rope; b: B.Buf; m: Mark;
BEGIN
  Save(m); rolePos := B.pos;
  q := RoleMarker(B.pos);
  IF q >= 0 THEN
    role := B.Rope(B.pos + 1, q - 1); B.pos := q;
    IF ~Unmarked(b) THEN RETURN FALSE END
  ELSE
    IF ~Unmarked(b) THEN RETURN FALSE END;
    IF B.C(B.pos) = ":" THEN
      q := RoleMarker(B.pos);
      IF q < 0 THEN RETURN FALSE END;
      role := B.Rope(B.pos + 1, q - 1); B.pos := q
    ELSE role := defaultRole
    END
  END;
  RenderRole(b, NIL, role, A.NewAttr(NIL), l);
  RETURN TRUE
END InterpretedRole;

(* inline: one inline at B.pos, appended to l; FALSE if there is none *)
PROCEDURE Inline*(VAR l: A.Inlines): BOOLEAN;
  VAR ch: CHAR; m: Mark; ok: BOOLEAN;
BEGIN
  IF B.pos >= B.len THEN RETURN FALSE END;
  ch := B.C(B.pos); Save(m); ok := FALSE;
  IF (ch = " ") OR (ch = 09X) OR (ch = "[") THEN ok := Note(l) END;
  IF ~ok & MI.NotAfterString() THEN
    Restore(m);
    IF ch = "`" THEN
      ok := ExplicitLink(l) OR Again(m) & ReferenceLink(l)
    ELSIF ch = "[" THEN
      ok := ReferenceLink(l)
    ELSIF ch = "_" THEN
      ok := InlineAnchor(l)
    ELSIF ch = "*" THEN
      ok := Enclosed("**", A.Strong, l) OR Again(m) & Enclosed("*", A.Emph, l)
    ELSIF MI.AlnumAt(B.pos) THEN
      ok := ReferenceLink(l) OR Again(m) & AutoLink(l)
    END
  END;
  IF ~ok THEN
    Restore(m);
    IF ch = "`" THEN
      ok := Code(l) OR Again(m) & InterpretedRole(l)
    ELSIF ch = "|" THEN
      ok := Subst(l)
    ELSIF ch = ":" THEN
      ok := InterpretedRole(l)
    END
  END;
  IF ~ok THEN
    Restore(m);
    ok := InlineContent(l);
    IF ~ok THEN Restore(m) END
  END;
  RETURN ok
END Inline;

(* The trimmed inlines of the current text from B.pos while stop says
   go on; many inline *)
PROCEDURE Inlines*(VAR l: A.Inlines);
BEGIN
  WHILE Inline(l) DO END
END Inlines;

(* Parsec's try of one inline, for the block parsers: the inline at
   B.pos, appended to l, with the state restored if there is none *)
PROCEDURE TryInline*(VAR l: A.Inlines): BOOLEAN;
BEGIN
  RETURN Inline(l)
END TryInline;

BEGIN
  Reset
END PdRstInline.
