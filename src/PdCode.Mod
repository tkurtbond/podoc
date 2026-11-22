MODULE PdCode;
(* PdCode: the scanner of podoc's small syntax highlighting (PLAN.md
   Phase 24; docs/research/syntax-highlighting-small.md, §5, §8 and
   §12).

   Scan cuts a piece of code into spans: plain text, reserved words,
   comments and strings. The spans cover the text, in order, and are
   positions in it: the text itself is never changed, so a scanner
   mistake can misplace bold or italic but cannot lose or garble code.
   Strings are a kind of their own so that alignment (Phase 24.4) can
   leave them whole (decision 44); the writers set them as plain text.

   A language is a record: its reserved words (decision 45: the words
   the language reserves, nothing else), whether case matters, its
   block comments and whether they nest, its line comment, its quotes
   and their escape rule, and a few flags for rules of its own. Find
   gives the language a class names. The built-in languages:

     oberon, oberon2           Oberon-2 (34 words)
     oberon1, oberon87         Oberon, the 1990 report (32)
     oberon07                  Oberon-07, the 2016 revision (33)
     cp, componentpascal       Component Pascal, the 2006 report (40)
     modula2                   Modula-2, PIM and ISO (46)
     c                         C23 (59)

   Identifiers are letters, digits, "_" and any byte from 80X up, so
   a word joined to UTF-8 text is not taken for a reserved word. A
   number is a digit followed by letters, digits and "_" (0FFH, 0x1Fu,
   1E10), and a "." followed by a digit; in C, a "'" between digits
   (1'000). A string ends at its closing quote or at the end of the
   line; a comment that is not closed runs to the end of the text. *)

IMPORT Ropes;

CONST
  (* kinds of span *)
  Plain* = 0; Reserved* = 1; Comment* = 2; String* = 3;

  WordLen = 32; (* reserved words are shorter than this *)
  DelimLen = 4;
  MaxComments = 2;

  (* escape rules in strings *)
  NoEscape = 0; Backslash = 1;

  LF = 0AX; CR = 0DX; TAB = 09X;

TYPE
  Rope = Ropes.Rope;
  Text = POINTER TO ARRAY OF CHAR;
  Word = ARRAY WordLen OF CHAR;
  Words = POINTER TO ARRAY OF Word;
  Delim = ARRAY DelimLen OF CHAR;

  (* A span: len bytes of the text from start, of the given kind *)
  Span* = POINTER TO SpanDesc;
  SpanDesc* = RECORD
    start*, len*: LONGINT;
    kind*: INTEGER;
    next*: Span
  END;

  Language* = POINTER TO LanguageDesc;
  LanguageDesc* = RECORD
    ignoreCase: BOOLEAN;      (* words compare without case *)
    nComments: INTEGER;       (* block comments: open[i] ... close[i] *)
    open, close: ARRAY MaxComments OF Delim;
    nest: ARRAY MaxComments OF BOOLEAN;
    line: Delim;              (* a line comment's marker, or "" *)
    lineContinues: BOOLEAN;   (* backslash-newline continues it (C) *)
    quotes: ARRAY 4 OF CHAR;  (* the quote characters *)
    escape: INTEGER;          (* NoEscape or Backslash *)
    digitSep: BOOLEAN;        (* "'" between digits (C23) *)
    directives: BOOLEAN;      (* "#" lines: the directive's name plain (C) *)
    words: Words;             (* sorted; lower case if ignoreCase *)
    nWords: LONGINT
  END;

  Name = POINTER TO NameDesc;
  NameDesc = RECORD
    name: ARRAY 24 OF CHAR;
    lang: Language;
    next: Name
  END;

  Scanner = RECORD
    lang: Language;
    t: Text;
    n: LONGINT;           (* the text's length *)
    plain: LONGINT;       (* where the plain text not yet given starts *)
    first, last: Span
  END;

VAR
  names: Name;

(* --- Languages --- *)

PROCEDURE IsIdent(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")
    OR (ch >= "0") & (ch <= "9") OR (ch = "_") OR (ch >= 80X)
END IsIdent;

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

PROCEDURE Less(VAR a, b: Word): BOOLEAN;
  VAR i: INTEGER;
BEGIN
  i := 0;
  WHILE (a[i] # 0X) & (a[i] = b[i]) DO INC(i) END;
  RETURN a[i] < b[i]
END Less;

(* Add the words of list, separated by spaces, to lang's words, and
   keep them sorted. Words as long as WordLen or longer are left out. *)
PROCEDURE AddWords(lang: Language; list: ARRAY OF CHAR);
  VAR i, k: INTEGER; j, m: LONGINT; w: Word; ws: Words;
BEGIN
  i := 0;
  WHILE (i < LEN(list)) & (list[i] # 0X) DO
    WHILE list[i] = " " DO INC(i) END;
    k := 0;
    WHILE (list[i] # " ") & (list[i] # 0X) DO
      IF k < WordLen - 1 THEN
        IF lang.ignoreCase THEN w[k] := Ropes.LowerChar(list[i]) ELSE w[k] := list[i] END
      END;
      INC(k); INC(i)
    END;
    IF (k > 0) & (k < WordLen) THEN
      w[k] := 0X;
      IF (lang.words = NIL) OR (lang.nWords = LEN(lang.words^)) THEN
        IF lang.words = NIL THEN NEW(ws, 64) ELSE NEW(ws, 2 * LEN(lang.words^)) END;
        FOR m := 0 TO lang.nWords - 1 DO ws[m] := lang.words[m] END;
        lang.words := ws
      END;
      (* insertion *)
      j := lang.nWords;
      WHILE (j > 0) & Less(w, lang.words[j - 1]) DO
        lang.words[j] := lang.words[j - 1]; DEC(j)
      END;
      lang.words[j] := w; INC(lang.nWords)
    END
  END
END AddWords;

PROCEDURE NewLanguage(ignoreCase: BOOLEAN): Language;
  VAR l: Language;
BEGIN
  NEW(l); l.ignoreCase := ignoreCase; l.nComments := 0; l.line := "";
  l.lineContinues := FALSE; l.quotes := ""; l.escape := NoEscape;
  l.digitSep := FALSE; l.directives := FALSE; l.words := NIL; l.nWords := 0;
  RETURN l
END NewLanguage;

(* Strings in " and in ' *)
PROCEDURE Quotes(l: Language);
BEGIN l.quotes[0] := 22X; l.quotes[1] := "'"; l.quotes[2] := 0X
END Quotes;

PROCEDURE AddComment(l: Language; open, close: ARRAY OF CHAR; nest: BOOLEAN);
BEGIN
  ASSERT(l.nComments < MaxComments);
  COPY(open, l.open[l.nComments]); COPY(close, l.close[l.nComments]);
  l.nest[l.nComments] := nest; INC(l.nComments)
END AddComment;

PROCEDURE AddName(name: ARRAY OF CHAR; l: Language);
  VAR n: Name;
BEGIN
  NEW(n); COPY(name, n.name); n.lang := l; n.next := names; names := n
END AddName;

(* The language a class names, or NIL if podoc knows none by that name *)
PROCEDURE Find*(name: ARRAY OF CHAR): Language;
  VAR n: Name;
BEGIN
  n := names;
  WHILE (n # NIL) & (n.name # name) DO n := n.next END;
  IF n = NIL THEN RETURN NIL ELSE RETURN n.lang END
END Find;

(* An Oberon: case matters, comments (* *) nest, strings in " or ' *)
PROCEDURE Oberon(): Language;
  VAR l: Language;
BEGIN
  l := NewLanguage(FALSE); AddComment(l, "(*", "*)", TRUE); Quotes(l);
  AddWords(l, "ARRAY BEGIN CASE CONST DIV DO ELSE ELSIF END IF IMPORT IN IS");
  AddWords(l, "MOD MODULE NIL OF OR POINTER PROCEDURE RECORD REPEAT RETURN");
  AddWords(l, "THEN TO TYPE UNTIL VAR WHILE");
  RETURN l
END Oberon;

PROCEDURE InitLanguages;
  VAR l: Language;
BEGIN
  names := NIL;

  (* Oberon, the 1990 report: 32 words *)
  l := Oberon(); AddWords(l, "EXIT LOOP WITH");
  AddName("oberon1", l); AddName("oberon87", l);

  (* Oberon-2: 34 words, verified with poc (study §5.1) *)
  l := Oberon(); AddWords(l, "BY EXIT FOR LOOP WITH");
  AddName("oberon", l); AddName("oberon2", l);

  (* Oberon-07, the 2016 revision: 33 words *)
  l := Oberon(); AddWords(l, "BY FALSE FOR TRUE");
  AddName("oberon07", l);

  (* Component Pascal, the 2006 report: 40 words *)
  l := Oberon();
  AddWords(l, "ABSTRACT BY CLOSE EMPTY EXIT EXTENSIBLE FOR LIMITED LOOP OUT WITH");
  AddName("cp", l); AddName("componentpascal", l);

  (* Modula-2, PIM's 40 and ISO's 6, verified with gm2 (study §5.2);
     ISO's pragmas <* *> as comments *)
  l := NewLanguage(FALSE); AddComment(l, "(*", "*)", TRUE);
  AddComment(l, "<*", "*>", FALSE); Quotes(l);
  AddWords(l, "AND ARRAY BEGIN BY CASE CONST DEFINITION DIV DO ELSE ELSIF END");
  AddWords(l, "EXIT EXPORT FOR FROM IF IMPLEMENTATION IMPORT IN LOOP MOD MODULE");
  AddWords(l, "NOT OF OR POINTER PROCEDURE QUALIFIED RECORD REPEAT RETURN SET");
  AddWords(l, "THEN TO TYPE UNTIL VAR WHILE WITH");
  AddWords(l, "EXCEPT FINALLY FORWARD PACKEDSET REM RETRY");
  AddName("modula2", l);

  (* C23: 59 words (study §5.5) *)
  l := NewLanguage(FALSE); AddComment(l, "/*", "*/", FALSE);
  l.line := "//"; l.lineContinues := TRUE; Quotes(l);
  l.escape := Backslash; l.digitSep := TRUE; l.directives := TRUE;
  AddWords(l, "alignas alignof auto bool break case char const constexpr");
  AddWords(l, "continue default do double else enum extern false float for");
  AddWords(l, "goto if inline int long nullptr register restrict return short");
  AddWords(l, "signed sizeof static static_assert struct switch thread_local");
  AddWords(l, "true typedef typeof typeof_unqual union unsigned void volatile");
  AddWords(l, "while _Alignas _Alignof _Atomic _BitInt _Bool _Complex");
  AddWords(l, "_Decimal128 _Decimal32 _Decimal64 _Generic _Imaginary");
  AddWords(l, "_Noreturn _Static_assert _Thread_local");
  AddName("c", l)
END InitLanguages;

(* The number of lang's reserved words *)
PROCEDURE Count*(lang: Language): LONGINT;
BEGIN RETURN lang.nWords
END Count;

(* --- The scanner --- *)

(* Give the span [start, end) of the kind, after the plain text before it *)
PROCEDURE Emit(VAR s: Scanner; kind: INTEGER; start, end: LONGINT);
  PROCEDURE Add(kind: INTEGER; start, end: LONGINT);
    VAR sp: Span;
  BEGIN
    NEW(sp); sp.start := start; sp.len := end - start; sp.kind := kind; sp.next := NIL;
    IF s.first = NIL THEN s.first := sp ELSE s.last.next := sp END;
    s.last := sp
  END Add;
BEGIN
  IF s.plain < start THEN Add(Plain, s.plain, start) END;
  IF start < end THEN Add(kind, start, end) END;
  s.plain := end
END Emit;

(* Whether the delimiter d is at position i *)
PROCEDURE At(VAR s: Scanner; i: LONGINT; VAR d: Delim): BOOLEAN;
  VAR k: INTEGER;
BEGIN
  k := 0;
  WHILE (d[k] # 0X) & (i + k < s.n) & (s.t[i + k] = d[k]) DO INC(k) END;
  RETURN (k > 0) & (d[k] = 0X)
END At;

PROCEDURE Length(VAR d: Delim): INTEGER;
  VAR k: INTEGER;
BEGIN
  k := 0; WHILE d[k] # 0X DO INC(k) END;
  RETURN k
END Length;

(* The end of the block comment c that opens at i *)
PROCEDURE CommentEnd(VAR s: Scanner; c: INTEGER; i: LONGINT): LONGINT;
  VAR depth: LONGINT; l: Language;
BEGIN
  l := s.lang; depth := 1; INC(i, Length(l.open[c]));
  WHILE (depth > 0) & (i < s.n) DO
    IF At(s, i, l.close[c]) THEN DEC(depth); INC(i, Length(l.close[c]))
    ELSIF l.nest[c] & At(s, i, l.open[c]) THEN INC(depth); INC(i, Length(l.open[c]))
    ELSE INC(i)
    END
  END;
  RETURN i
END CommentEnd;

(* The end of the line comment at i: the line's end, not the newline *)
PROCEDURE LineEnd(VAR s: Scanner; i: LONGINT): LONGINT;
BEGIN
  WHILE (i < s.n) & ~((s.t[i] = LF) & ~(s.lang.lineContinues & (s.t[i - 1] = "\")))
    & ~((s.t[i] = CR) & ~(s.lang.lineContinues & (s.t[i - 1] = "\"))) DO
    INC(i)
  END;
  RETURN i
END LineEnd;

(* The end of the string that opens at i, after its closing quote, or at
   the end of its line if it is not closed *)
PROCEDURE StringEnd(VAR s: Scanner; i: LONGINT): LONGINT;
  VAR q: CHAR; done: BOOLEAN;
BEGIN
  q := s.t[i]; INC(i); done := FALSE;
  WHILE ~done & (i < s.n) DO
    IF s.t[i] = q THEN INC(i); done := TRUE
    ELSIF (s.t[i] = LF) OR (s.t[i] = CR) THEN done := TRUE
    ELSIF (s.lang.escape = Backslash) & (s.t[i] = "\") & (i + 1 < s.n) THEN
      INC(i, 2);
      IF (s.t[i - 1] = CR) & (i < s.n) & (s.t[i] = LF) THEN INC(i) END
    ELSE INC(i)
    END
  END;
  RETURN i
END StringEnd;

PROCEDURE IsQuote(l: Language; ch: CHAR): BOOLEAN;
  VAR k: INTEGER;
BEGIN
  k := 0;
  WHILE (l.quotes[k] # 0X) & (l.quotes[k] # ch) DO INC(k) END;
  RETURN (ch # 0X) & (l.quotes[k] = ch)
END IsQuote;

(* Whether the identifier [start, end) is a reserved word *)
PROCEDURE IsReserved(VAR s: Scanner; start, end: LONGINT): BOOLEAN;
  VAR w: Word; k: INTEGER; lo, hi, mid: LONGINT; l: Language;
BEGIN
  l := s.lang;
  IF (end - start >= WordLen) OR (l.nWords = 0) THEN RETURN FALSE END;
  k := 0;
  WHILE start < end DO
    IF l.ignoreCase THEN w[k] := Ropes.LowerChar(s.t[start]) ELSE w[k] := s.t[start] END;
    INC(k); INC(start)
  END;
  w[k] := 0X;
  lo := 0; hi := l.nWords;  (* the word, if there, is in [lo, hi) *)
  WHILE lo < hi DO
    mid := (lo + hi) DIV 2;
    IF Less(l.words[mid], w) THEN lo := mid + 1 ELSE hi := mid END
  END;
  RETURN (lo < l.nWords) & (l.words[lo] = w)
END IsReserved;

(* The spans of text, in lang. NIL if text is empty. *)
PROCEDURE Scan*(lang: Language; text: Rope): Span;
  VAR s: Scanner; i, j: LONGINT; c: INTEGER; lineStart, found: BOOLEAN; ch: CHAR;
BEGIN
  s.lang := lang; s.n := Ropes.Length(text); s.plain := 0;
  s.first := NIL; s.last := NIL;
  IF s.n = 0 THEN RETURN NIL END;
  NEW(s.t, s.n + 1); Ropes.Blit(text, 0, s.t^, 0, s.n); s.t[s.n] := 0X;
  i := 0; lineStart := TRUE;
  WHILE i < s.n DO
    ch := s.t[i];
    found := FALSE; c := 0;
    WHILE ~found & (c < lang.nComments) DO
      IF At(s, i, lang.open[c]) THEN found := TRUE ELSE INC(c) END
    END;
    IF found THEN
      j := CommentEnd(s, c, i); Emit(s, Comment, i, j); i := j; lineStart := FALSE
    ELSIF (lang.line[0] # 0X) & At(s, i, lang.line) THEN
      j := LineEnd(s, i); Emit(s, Comment, i, j); i := j
    ELSIF IsQuote(lang, ch) THEN
      j := StringEnd(s, i); Emit(s, String, i, j); i := j; lineStart := FALSE
    ELSIF lang.directives & lineStart & (ch = "#") THEN
      (* the directive's name is not a keyword: #if, #else *)
      INC(i);
      WHILE (i < s.n) & ((s.t[i] = " ") OR (s.t[i] = TAB)) DO INC(i) END;
      WHILE (i < s.n) & IsIdent(s.t[i]) DO INC(i) END;
      lineStart := FALSE
    ELSIF IsDigit(ch) THEN
      INC(i);
      WHILE (i < s.n) & (IsIdent(s.t[i])
          OR (s.t[i] = ".") & (i + 1 < s.n) & IsDigit(s.t[i + 1])
          OR lang.digitSep & (s.t[i] = "'") & (i + 1 < s.n) & IsIdent(s.t[i + 1])) DO
        INC(i)
      END;
      lineStart := FALSE
    ELSIF IsIdent(ch) THEN
      j := i + 1;
      WHILE (j < s.n) & IsIdent(s.t[j]) DO INC(j) END;
      IF IsReserved(s, i, j) THEN Emit(s, Reserved, i, j) END;
      i := j; lineStart := FALSE
    ELSE
      IF (ch = LF) OR (ch = CR) THEN lineStart := TRUE
      ELSIF (ch # " ") & (ch # TAB) THEN lineStart := FALSE
      END;
      INC(i)
    END
  END;
  Emit(s, Plain, s.n, s.n);
  RETURN s.first
END Scan;

BEGIN
  InitLanguages
END PdCode.
