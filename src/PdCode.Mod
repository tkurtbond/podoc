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
     pascal, fpc               FreePascal's mode fpc (59)
     objfpc                    FreePascal's mode objfpc (67)
     delphi                    FreePascal's mode delphi (65)
     tp                        FreePascal's mode tp (54)
     macpas                    FreePascal's mode macpas (56)
     iso                       ISO 7185 Pascal, FreePascal's mode iso (36)
     ada                       Ada 2022 (74)
     c                         C23 (59)
     cpp                       C++23 (92)
     sh                        the POSIX shell (16)
     bash                      bash (22)

   The Pascal lists are FreePascal's, a list per mode (decision 39),
   from the table in its compiler/tokens.pas, each word checked with
   fpc 3.2.3, which rejects every one as a variable name in its mode
   and accepts the others; in tp, fpc accepts "inline", which its
   table gives to tp, so it is left out.

   The rules of their own:

   - Pascal: comments in { } and (* *), nested in fpc and objfpc,
     where each kind nests in itself, as fpc does; in iso, { and (*
     are one comment, closed by } or *), as ISO 7185 says; "//" to the
     line's end in every mode; strings in ' with '' for a quote; a word
     after "&" is a name (&begin).
   - Ada: "--" to the line's end; strings in " with "" for a quote;
     "'" after a name, a ")" or "all" is the attribute tick, and the
     word after a tick is an attribute, never reserved (X'Range);
     otherwise 'x' is a character literal.
   - C and C++: a "#" directive's name is plain (#if), and after
     #include a header name <...> is a string (<new>).
   - C++: C's rules, with raw strings, R"d( ... )d" with the prefixes
     R, LR, uR, UR and u8R, kept whole across lines.
   - sh and bash: a shell scanner of its own, Commands. A word is
     reserved only where the shell takes it for one: as the first word
     of a command (after a newline, ";", "&", "|", "(", "$(", "`" or a
     reserved word such as "then"), and "in" and "do" after "for NAME"
     or "case WORD"; a word after another word, an assignment or a
     redirection is plain (echo done). "#" starts a comment only at
     the start of a word (a#b, ${#x}). Strings: '...', "..." with "\"
     escapes, $'...' and $"..."; they may span lines. Command
     substitutions, $(...) and `...` outside double quotes, are
     scanned as commands. A here-document's body, after <<WORD,
     <<-WORD or a quoted WORD, several to a line, stays plain. In
     "case WORD in", the patterns before ")" are plain, and "esac"
     at a pattern's start is reserved (not in a|esac or (esac); ";;", ";&" and ";;&" start the next pattern.
     bash: words in [[ ... ]] are plain up to "]]"; ((...)), $((...)),
     a=(...) and extended patterns @(...) are plain.

   Identifiers are letters, digits, "_" and any byte from 80X up, so
   a word joined to UTF-8 text is not taken for a reserved word. A
   number is a digit followed by letters, digits and "_" (0FFH, 0x1Fu,
   1E10), and a "." followed by a digit; in C, a "'" between digits
   (1'000). A string ends at its closing quote or at the end of the
   line (in sh and bash, at its closing quote or the end of the text);
   a comment that is not closed runs to the end of the text.

   Users' lists (Phase 24.8, decisions 40 and 47) change a language's
   words with AddWord, RemoveWord and Clear; Reset gives every language
   its built-in words again. A change to a language holds for all its
   names (pascal and fpc). In sh and bash, a word a user's list takes
   out is no longer reserved for the scanner either: without "case",
   "case x in" is a command and its arguments. *)

IMPORT Ropes;

CONST
  (* kinds of span *)
  Plain* = 0; Reserved* = 1; Comment* = 2; String* = 3;

  WordLen = 32; (* reserved words are shorter than this *)
  DelimLen = 4;
  MaxComments = 2;

  (* escape rules in strings *)
  NoEscape = 0; Backslash = 1; Doubled = 2;

  (* what came before, for Ada's tick *)
  PrevOther = 0; PrevName = 1; PrevTick = 2;

  MaxRawDelim = 16; (* a C++ raw string's delimiter is at most this long *)

  (* shells *)
  NoShell = 0; Sh = 1; Bash = 2;

  (* what the shell expects the next word to be *)
  ExNone = 0; ExForName = 1; ExForIn = 2; ExCaseWord = 3; ExCaseIn = 4;
  ExFuncName = 5; ExFuncBody = 6;

  MaxDocs = 8;  (* here-documents pending on one line *)
  DocLen = 64;  (* a here-document's delimiter is shorter than this *)

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
    escape: INTEGER;          (* NoEscape, Backslash or Doubled *)
    digitSep: BOOLEAN;        (* "'" between digits (C23) *)
    directives: BOOLEAN;      (* "#" lines: the directive's name plain (C) *)
    crossClose: BOOLEAN;      (* each block comment closes the others' (ISO Pascal) *)
    amp: BOOLEAN;             (* "&" makes a word a name (Pascal) *)
    tick: BOOLEAN;            (* Ada's tick and character literals *)
    raw: BOOLEAN;             (* C++'s raw strings *)
    shell: INTEGER;           (* NoShell, Sh or Bash: Commands scans it *)
    words: Words;             (* sorted; lower case if ignoreCase *)
    nWords: LONGINT;
    builtin: Words;           (* the built-in words, for Reset *)
    nBuiltin: LONGINT
  END;

  Name = POINTER TO NameDesc;
  NameDesc = RECORD
    name: ARRAY 24 OF CHAR;
    lang: Language;
    next: Name
  END;

  (* A here-document waiting for the end of its line *)
  Doc = RECORD
    word: ARRAY DocLen OF CHAR;  (* its delimiter, unquoted *)
    len: LONGINT;                (* its length, DocLen or more if too long *)
    tabs: BOOLEAN                (* <<-: leading tabs are stripped *)
  END;

  Scanner = RECORD
    lang: Language;
    t: Text;
    n: LONGINT;           (* the text's length *)
    plain: LONGINT;       (* where the plain text not yet given starts *)
    first, last: Span;
    nDocs: INTEGER;       (* the shell's pending here-documents *)
    docs: ARRAY MaxDocs OF Doc
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

(* Copies w into word, lower case if lang ignores case; FALSE if w is
   too long or empty *)
PROCEDURE ToWord(lang: Language; w: ARRAY OF CHAR; VAR word: Word): BOOLEAN;
  VAR k: INTEGER;
BEGIN
  k := 0;
  WHILE (k < LEN(w)) & (w[k] # 0X) DO
    IF k >= WordLen - 1 THEN RETURN FALSE END;
    IF lang.ignoreCase THEN word[k] := Ropes.LowerChar(w[k]) ELSE word[k] := w[k] END;
    INC(k)
  END;
  word[k] := 0X;
  RETURN k > 0
END ToWord;

(* The place of w in lang's words: the first word not less than it *)
PROCEDURE Place(lang: Language; VAR w: Word): LONGINT;
  VAR lo, hi, mid: LONGINT;
BEGIN
  lo := 0; hi := lang.nWords;
  WHILE lo < hi DO
    mid := (lo + hi) DIV 2;
    IF Less(lang.words[mid], w) THEN lo := mid + 1 ELSE hi := mid END
  END;
  RETURN lo
END Place;

(* Inserts w in lang's words, kept sorted, unless it is there *)
PROCEDURE Insert(lang: Language; VAR w: Word);
  VAR j, m: LONGINT; ws: Words;
BEGIN
  IF lang.words # NIL THEN j := Place(lang, w) ELSE j := 0 END;
  IF (j < lang.nWords) & (lang.words[j] = w) THEN RETURN END;
  IF (lang.words = NIL) OR (lang.nWords = LEN(lang.words^)) THEN
    IF lang.words = NIL THEN NEW(ws, 64) ELSE NEW(ws, 2 * LEN(lang.words^)) END;
    FOR m := 0 TO lang.nWords - 1 DO ws[m] := lang.words[m] END;
    lang.words := ws
  END;
  m := lang.nWords;
  WHILE m > j DO lang.words[m] := lang.words[m - 1]; DEC(m) END;
  lang.words[j] := w; INC(lang.nWords)
END Insert;

(* Add the words of list, separated by spaces, to lang's words *)
PROCEDURE AddWords(lang: Language; list: ARRAY OF CHAR);
  VAR i, k: INTEGER; w: ARRAY 64 OF CHAR; word: Word;
BEGIN
  i := 0;
  WHILE (i < LEN(list)) & (list[i] # 0X) DO
    WHILE list[i] = " " DO INC(i) END;
    k := 0;
    WHILE (list[i] # " ") & (list[i] # 0X) DO w[k] := list[i]; INC(k); INC(i) END;
    w[k] := 0X;
    IF ToWord(lang, w, word) THEN Insert(lang, word) END
  END
END AddWords;

PROCEDURE NewLanguage(ignoreCase: BOOLEAN): Language;
  VAR l: Language;
BEGIN
  NEW(l); l.ignoreCase := ignoreCase; l.nComments := 0; l.line := "";
  l.lineContinues := FALSE; l.quotes := ""; l.escape := NoEscape;
  l.digitSep := FALSE; l.directives := FALSE; l.crossClose := FALSE;
  l.amp := FALSE; l.tick := FALSE; l.raw := FALSE; l.shell := NoShell;
  l.words := NIL; l.nWords := 0; l.builtin := NIL; l.nBuiltin := 0;
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

(* C's words, without its underscore spellings and its words C++ does
   not have *)
PROCEDURE CWords(l: Language);
BEGIN
  AddWords(l, "alignas alignof auto bool break case char const constexpr");
  AddWords(l, "continue default do double else enum extern false float for");
  AddWords(l, "goto if inline int long nullptr register return short");
  AddWords(l, "signed sizeof static static_assert struct switch thread_local");
  AddWords(l, "true typedef union unsigned void volatile while")
END CWords;

(* C or C++: comments /* */ and //, strings with backslash escapes *)
PROCEDURE CLike(): Language;
  VAR l: Language;
BEGIN
  l := NewLanguage(FALSE); AddComment(l, "/*", "*/", FALSE);
  l.line := "//"; l.lineContinues := TRUE; Quotes(l);
  l.escape := Backslash; l.digitSep := TRUE; l.directives := TRUE;
  CWords(l);
  RETURN l
END CLike;

(* A FreePascal mode: the 36 words of every mode; comments that nest or
   not *)
PROCEDURE Pascal(nest: BOOLEAN): Language;
  VAR l: Language;
BEGIN
  l := NewLanguage(TRUE); AddComment(l, "{", "}", nest); AddComment(l, "(*", "*)", nest);
  l.line := "//"; l.quotes := "'"; l.escape := Doubled; l.amp := TRUE;
  AddWords(l, "and array begin case const div do downto else end file for function");
  AddWords(l, "goto if in label mod nil not of or packed procedure program record");
  AddWords(l, "repeat set then to type until var while with xor");
  RETURN l
END Pascal;

(* The words of every FreePascal mode but iso, 18 *)
PROCEDURE PascalWords(l: Language);
BEGIN
  AddWords(l, "asm bitpacked constructor destructor exports implementation inherited");
  AddWords(l, "interface library object otherwise resourcestring shl shr string");
  AddWords(l, "threadvar unit uses")
END PascalWords;

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

  (* FreePascal's modes, a list each (decision 39), checked with fpc
     3.2.3 (study §5.4) *)
  l := Pascal(TRUE); PascalWords(l);
  AddWords(l, "cppclass finalization initialization operator property");
  AddName("pascal", l); AddName("fpc", l);

  l := Pascal(TRUE); PascalWords(l);
  AddWords(l, "as class cppclass dispinterface except finalization finally");
  AddWords(l, "initialization is operator property raise try");
  AddName("objfpc", l);

  l := Pascal(FALSE); PascalWords(l);
  AddWords(l, "as class dispinterface except finalization finally");
  AddWords(l, "initialization is property raise try");
  AddName("delphi", l);

  l := Pascal(FALSE); PascalWords(l);
  AddName("tp", l);

  l := Pascal(FALSE); PascalWords(l); AddWords(l, "return univ");
  AddName("macpas", l);

  l := Pascal(FALSE); l.crossClose := TRUE;
  AddName("iso", l);

  (* Ada 2022: 74 words, checked with GNAT (study §5.3) *)
  l := NewLanguage(TRUE); l.line := "--"; l.quotes[0] := 22X; l.quotes[1] := 0X;
  l.escape := Doubled; l.tick := TRUE;
  AddWords(l, "abort abs abstract accept access aliased all and array at begin");
  AddWords(l, "body case constant declare delay delta digits do else elsif end");
  AddWords(l, "entry exception exit for function generic goto if in interface is");
  AddWords(l, "limited loop mod new not null of or others out overriding package");
  AddWords(l, "parallel pragma private procedure protected raise range record rem");
  AddWords(l, "renames requeue return reverse select separate some subtype");
  AddWords(l, "synchronized tagged task terminate then type until use when while");
  AddWords(l, "with xor");
  AddName("ada", l);

  (* C23: 59 words (study §5.5) *)
  l := CLike();
  AddWords(l, "restrict typeof typeof_unqual");
  AddWords(l, "_Alignas _Alignof _Atomic _BitInt _Bool _Complex");
  AddWords(l, "_Decimal128 _Decimal32 _Decimal64 _Generic _Imaginary");
  AddWords(l, "_Noreturn _Static_assert _Thread_local");
  AddName("c", l);

  (* C++23: 92 words, checked with g++ (study §5.6) *)
  l := CLike(); l.raw := TRUE;
  AddWords(l, "and and_eq asm bitand bitor catch char8_t char16_t char32_t class");
  AddWords(l, "compl concept consteval constinit const_cast co_await co_return");
  AddWords(l, "co_yield decltype delete dynamic_cast explicit export friend mutable");
  AddWords(l, "namespace new noexcept not not_eq operator or or_eq private");
  AddWords(l, "protected public reinterpret_cast requires static_cast template");
  AddWords(l, "this throw try typeid typename using virtual wchar_t xor xor_eq");
  AddName("cpp", l);

  (* The POSIX shell: 16 words (study §5.7) *)
  l := NewLanguage(FALSE); l.shell := Sh;
  AddWords(l, "! { } case do done elif else esac fi for if in then until while");
  AddName("sh", l);

  (* bash: 22 words, those compgen -k prints *)
  l := NewLanguage(FALSE); l.shell := Bash;
  AddWords(l, "! { } case do done elif else esac fi for if in then until while");
  AddWords(l, "[[ ]] coproc function select time");
  AddName("bash", l)
END InitLanguages;

(* Copies the words ws, n of them *)
PROCEDURE CopyWords(ws: Words; n: LONGINT): Words;
  VAR c: Words; m: LONGINT;
BEGIN
  IF ws = NIL THEN RETURN NIL END;
  NEW(c, LEN(ws^));
  FOR m := 0 TO n - 1 DO c[m] := ws[m] END;
  RETURN c
END CopyWords;

(* Keeps every language's words as its built-in ones *)
PROCEDURE KeepBuiltins;
  VAR n: Name;
BEGIN
  n := names;
  WHILE n # NIL DO
    IF n.lang.builtin = NIL THEN
      n.lang.builtin := CopyWords(n.lang.words, n.lang.nWords);
      n.lang.nBuiltin := n.lang.nWords
    END;
    n := n.next
  END
END KeepBuiltins;

(* Gives every language its built-in words again, undoing AddWord,
   RemoveWord and Clear *)
PROCEDURE Reset*;
  VAR n: Name;
BEGIN
  n := names;
  WHILE n # NIL DO
    n.lang.words := CopyWords(n.lang.builtin, n.lang.nBuiltin);
    n.lang.nWords := n.lang.nBuiltin;
    n := n.next
  END
END Reset;

(* Adds the word w to lang's reserved words (without case if lang
   ignores case); FALSE, and nothing added, if w is empty or as long as
   32 bytes or longer *)
PROCEDURE AddWord*(lang: Language; w: ARRAY OF CHAR): BOOLEAN;
  VAR word: Word;
BEGIN
  IF ~ToWord(lang, w, word) THEN RETURN FALSE END;
  Insert(lang, word);
  RETURN TRUE
END AddWord;

(* Takes the word w out of lang's reserved words, if it is there *)
PROCEDURE RemoveWord*(lang: Language; w: ARRAY OF CHAR);
  VAR word: Word; j: LONGINT;
BEGIN
  IF ToWord(lang, w, word) & (lang.nWords > 0) THEN
    j := Place(lang, word);
    IF (j < lang.nWords) & (lang.words[j] = word) THEN
      WHILE j < lang.nWords - 1 DO lang.words[j] := lang.words[j + 1]; INC(j) END;
      DEC(lang.nWords)
    END
  END
END RemoveWord;

(* Takes out all of lang's reserved words *)
PROCEDURE Clear*(lang: Language);
BEGIN lang.nWords := 0
END Clear;

(* The number of lang's reserved words *)
PROCEDURE Count*(lang: Language): LONGINT;
BEGIN RETURN lang.nWords
END Count;

(* Whether w is one of lang's reserved words *)
PROCEDURE HasWord*(lang: Language; w: ARRAY OF CHAR): BOOLEAN;
  VAR word: Word; j: LONGINT;
BEGIN
  IF ~ToWord(lang, w, word) OR (lang.nWords = 0) THEN RETURN FALSE END;
  j := Place(lang, word);
  RETURN (j < lang.nWords) & (lang.words[j] = word)
END HasWord;

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
    ELSIF l.crossClose & At(s, i, l.close[1 - c]) THEN DEC(depth); INC(i, Length(l.close[1 - c]))
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
    IF (s.t[i] = q) & (s.lang.escape = Doubled) & (i + 1 < s.n) & (s.t[i + 1] = q) THEN
      INC(i, 2)
    ELSIF s.t[i] = q THEN INC(i); done := TRUE
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

(* The end of Ada's character literal at i, a quote, one character
   (UTF-8: its bytes) and a quote; i if there is none *)
PROCEDURE CharEnd(VAR s: Scanner; i: LONGINT): LONGINT;
  VAR j: LONGINT;
BEGIN
  j := i + 1;
  IF (j < s.n) & (s.t[j] # LF) & (s.t[j] # CR) THEN
    INC(j);
    WHILE (j < s.n) & (s.t[j] >= 80X) & (s.t[j] < 0C0X) DO INC(j) END;
    IF (j < s.n) & (s.t[j] = "'") THEN RETURN j + 1 END
  END;
  RETURN i
END CharEnd;

(* The end of C++'s raw string whose prefix is [start, i), the quote at
   i: after its )delim", or the end of the text if not closed; start if
   [start, i) is not a raw string's prefix or the delimiter is bad *)
PROCEDURE RawEnd(VAR s: Scanner; start, i: LONGINT): LONGINT;
  VAR d: ARRAY MaxRawDelim + 1 OF CHAR; k, m: INTEGER; p: ARRAY 4 OF CHAR; ok: BOOLEAN;
BEGIN
  IF (i - start > 3) OR (i >= s.n) OR (s.t[i] # 22X) THEN RETURN start END;
  m := 0; WHILE start + m < i DO p[m] := s.t[start + m]; INC(m) END; p[m] := 0X;
  IF ~((p = "R") OR (p = "LR") OR (p = "uR") OR (p = "UR") OR (p = "u8R")) THEN RETURN start END;
  INC(i); k := 0;
  WHILE (i < s.n) & (k <= MaxRawDelim) & (s.t[i] # "(")
      & (s.t[i] # ")") & (s.t[i] # "\") & (s.t[i] > " ") & (s.t[i] # 22X) DO
    IF k < MaxRawDelim THEN d[k] := s.t[i] END;
    INC(k); INC(i)
  END;
  IF (k > MaxRawDelim) OR (i >= s.n) OR (s.t[i] # "(") THEN RETURN start END;
  d[k] := 0X; INC(i);
  LOOP
    IF i >= s.n THEN RETURN s.n END;
    IF s.t[i] = ")" THEN
      m := 0; ok := TRUE;
      WHILE ok & (m < k) DO
        IF (i + 1 + m < s.n) & (s.t[i + 1 + m] = d[m]) THEN INC(m) ELSE ok := FALSE END
      END;
      IF ok & (i + 1 + k < s.n) & (s.t[i + 1 + k] = 22X) THEN RETURN i + k + 2 END
    END;
    INC(i)
  END
END RawEnd;

(* Whether [start, end) is "include", "include_next" or "import", the
   directives that take a header name *)
PROCEDURE IsInclude(VAR s: Scanner; start, end: LONGINT): BOOLEAN;
  VAR w: ARRAY 16 OF CHAR; k: INTEGER;
BEGIN
  IF end - start >= LEN(w) THEN RETURN FALSE END;
  k := 0; WHILE start < end DO w[k] := s.t[start]; INC(k); INC(start) END;
  w[k] := 0X;
  RETURN (w = "include") OR (w = "include_next") OR (w = "import")
END IsInclude;

(* Whether the identifier [start, end) is a reserved word *)
PROCEDURE IsReserved(VAR s: Scanner; start, end: LONGINT): BOOLEAN;
  VAR w: Word; k: INTEGER; lo: LONGINT; l: Language;
BEGIN
  l := s.lang;
  IF (end - start >= WordLen) OR (l.nWords = 0) THEN RETURN FALSE END;
  k := 0;
  WHILE start < end DO
    IF l.ignoreCase THEN w[k] := Ropes.LowerChar(s.t[start]) ELSE w[k] := s.t[start] END;
    INC(k); INC(start)
  END;
  w[k] := 0X;
  lo := Place(l, w);
  RETURN (lo < l.nWords) & (l.words[lo] = w)
END IsReserved;

(* --- The shell --- *)

(* The character at k, or 0X past the end *)
PROCEDURE Ch(VAR s: Scanner; k: LONGINT): CHAR;
BEGIN
  IF k < s.n THEN RETURN s.t[k] ELSE RETURN 0X END
END Ch;

(* Whether ch ends a shell word: a blank, a newline or an operator *)
PROCEDURE IsMeta(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = " ") OR (ch = TAB) OR (ch = CR) OR (ch = LF) OR (ch = ";") OR (ch = "&")
    OR (ch = "|") OR (ch = "(") OR (ch = ")") OR (ch = "<") OR (ch = ">")
END IsMeta;

(* Whether [start, end) is w *)
PROCEDURE Is(VAR s: Scanner; start, end: LONGINT; w: ARRAY OF CHAR): BOOLEAN;
  VAR k: LONGINT;
BEGIN
  k := 0;
  WHILE (start + k < end) & (k < LEN(w)) & (w[k] # 0X) & (s.t[start + k] = w[k]) DO INC(k) END;
  RETURN (start + k = end) & ((k = LEN(w)) OR (w[k] = 0X))
END Is;

(* After the '...' at i, or the end of the text *)
PROCEDURE SingleEnd(VAR s: Scanner; i: LONGINT): LONGINT;
BEGIN
  INC(i);
  WHILE (i < s.n) & (s.t[i] # "'") DO INC(i) END;
  IF i < s.n THEN INC(i) END;
  RETURN i
END SingleEnd;

(* After the text quoted by q at i, with backslash escapes: $'...' or
   `...`; or the end of the text *)
PROCEDURE EscapedEnd(VAR s: Scanner; i: LONGINT; q: CHAR): LONGINT;
BEGIN
  INC(i);
  WHILE (i < s.n) & (s.t[i] # q) DO
    IF s.t[i] = "\" THEN INC(i) END;
    INC(i)
  END;
  IF i < s.n THEN INC(i) ELSIF i > s.n THEN i := s.n END;
  RETURN i
END EscapedEnd;

PROCEDURE ^ DoubleEnd(VAR s: Scanner; i: LONGINT): LONGINT;

(* After the brackets that open with open at i, skipped: nested
   brackets, quotes and backslashes; or the end of the text *)
PROCEDURE Balanced(VAR s: Scanner; i: LONGINT; open, close: CHAR): LONGINT;
  VAR depth: LONGINT; ch: CHAR;
BEGIN
  depth := 0;
  REPEAT
    ch := s.t[i];
    IF ch = open THEN INC(depth); INC(i)
    ELSIF ch = close THEN DEC(depth); INC(i)
    ELSIF ch = "\" THEN INC(i, 2)
    ELSIF ch = "'" THEN i := SingleEnd(s, i)
    ELSIF ch = 22X THEN i := DoubleEnd(s, i)
    ELSIF ch = "`" THEN i := EscapedEnd(s, i, "`")
    ELSE INC(i)
    END
  UNTIL (depth = 0) OR (i >= s.n);
  IF i > s.n THEN i := s.n END;
  RETURN i
END Balanced;

(* After the "..." at i, or the end of the text: backslash escapes,
   and $(...), ${...} and `...` in it skipped *)
PROCEDURE DoubleEnd(VAR s: Scanner; i: LONGINT): LONGINT;
BEGIN
  INC(i);
  WHILE (i < s.n) & (s.t[i] # 22X) DO
    IF s.t[i] = "\" THEN INC(i, 2)
    ELSIF (s.t[i] = "$") & (Ch(s, i + 1) = "(") THEN i := Balanced(s, i + 1, "(", ")")
    ELSIF (s.t[i] = "$") & (Ch(s, i + 1) = "{") THEN i := Balanced(s, i + 1, "{", "}")
    ELSIF s.t[i] = "`" THEN i := EscapedEnd(s, i, "`")
    ELSE INC(i)
    END
  END;
  IF i < s.n THEN INC(i) ELSIF i > s.n THEN i := s.n END;
  RETURN i
END DoubleEnd;

(* Reads the delimiter of the here-document whose "<<" ends at i, and
   leaves it pending for the end of the line; its quoted parts are
   strings *)
PROCEDURE HereDoc(VAR s: Scanner; VAR i: LONGINT);
  VAR d: Doc; k, m, last: LONGINT; ch: CHAR; start: LONGINT;

  PROCEDURE Put(ch: CHAR);
  BEGIN
    IF d.len < DocLen - 1 THEN d.word[d.len] := ch END;
    INC(d.len)
  END Put;

BEGIN
  d.tabs := Ch(s, i) = "-"; d.len := 0;
  IF d.tabs THEN INC(i) END;
  WHILE (Ch(s, i) = " ") OR (Ch(s, i) = TAB) DO INC(i) END;
  start := i;
  WHILE (i < s.n) & ~IsMeta(s.t[i]) DO
    ch := s.t[i];
    IF (ch = "'") OR (ch = 22X) THEN
      IF ch = "'" THEN k := SingleEnd(s, i) ELSE k := DoubleEnd(s, i) END;
      last := k;
      IF (k - 1 > i) & (s.t[k - 1] = ch) THEN last := k - 1 END;
      FOR m := i + 1 TO last - 1 DO Put(s.t[m]) END;
      Emit(s, String, i, k); i := k
    ELSIF ch = "\" THEN
      IF i + 1 < s.n THEN Put(s.t[i + 1]) END;
      INC(i, 2); IF i > s.n THEN i := s.n END
    ELSE Put(ch); INC(i)
    END
  END;
  IF (i > start) & (s.nDocs < MaxDocs) THEN
    IF d.len < DocLen THEN d.word[d.len] := 0X END;
    s.docs[s.nDocs] := d; INC(s.nDocs)
  END
END HereDoc;

(* Skips the bodies of the pending here-documents, which start at i,
   each up to the line that is its delimiter; they stay plain *)
PROCEDURE HereBodies(VAR s: Scanner; VAR i: LONGINT);
  VAR d: INTEGER; b, e, k, m: LONGINT; found: BOOLEAN;
BEGIN
  FOR d := 0 TO s.nDocs - 1 DO
    found := FALSE;
    WHILE ~found & (i < s.n) DO
      e := i; WHILE (e < s.n) & (s.t[e] # LF) DO INC(e) END;
      b := i;
      IF s.docs[d].tabs THEN WHILE (b < e) & (s.t[b] = TAB) DO INC(b) END END;
      k := e; IF (k > b) & (s.t[k - 1] = CR) THEN DEC(k) END;
      IF (k - b = s.docs[d].len) & (s.docs[d].len < DocLen) THEN
        m := 0; WHILE (b + m < k) & (s.t[b + m] = s.docs[d].word[m]) DO INC(m) END;
        found := b + m = k
      END;
      i := e; IF i < s.n THEN INC(i) END
    END
  END;
  s.nDocs := 0
END HereBodies;

PROCEDURE ^ Commands(VAR s: Scanner; VAR i: LONGINT; term: CHAR);

(* Scans the shell word at i to its end, giving its strings as spans
   and scanning its command substitutions as commands; literal: it has
   no quotes, escapes or expansions, so it may be a reserved word *)
PROCEDURE ShellWord(VAR s: Scanner; VAR i: LONGINT; term: CHAR; VAR literal: BOOLEAN);
  VAR ch, prev: CHAR; start, k: LONGINT; done: BOOLEAN;
BEGIN
  literal := TRUE; done := FALSE; start := i;
  WHILE ~done & (i < s.n) DO
    ch := s.t[i];
    IF i > start THEN prev := s.t[i - 1] ELSE prev := 0X END;
    IF (ch = "(") & ((prev = "=") OR (s.lang.shell = Bash) & ((prev = "?") OR (prev = "*")
        OR (prev = "+") OR (prev = "@") OR (prev = "!"))) THEN
      (* an array, a=(1 2), or bash's extended pattern, @(a|b) *)
      i := Balanced(s, i, "(", ")"); literal := FALSE
    ELSIF IsMeta(ch) OR (ch = term) THEN done := TRUE
    ELSIF ch = "'" THEN
      k := SingleEnd(s, i); Emit(s, String, i, k); i := k; literal := FALSE
    ELSIF ch = 22X THEN
      k := DoubleEnd(s, i); Emit(s, String, i, k); i := k; literal := FALSE
    ELSIF ch = "\" THEN
      INC(i, 2); IF i > s.n THEN i := s.n END; literal := FALSE
    ELSIF ch = "$" THEN
      literal := FALSE;
      CASE Ch(s, i + 1) OF
        "'": k := EscapedEnd(s, i + 1, "'"); Emit(s, String, i, k); i := k
      | 22X: k := DoubleEnd(s, i + 1); Emit(s, String, i, k); i := k
      | "(":
        IF Ch(s, i + 2) = "(" THEN i := Balanced(s, i + 1, "(", ")")  (* $((...)) *)
        ELSE INC(i, 2); Commands(s, i, ")")
        END
      | "{": i := Balanced(s, i + 1, "{", "}")
      ELSE INC(i)
      END
    ELSIF ch = "`" THEN
      INC(i); Commands(s, i, "`"); literal := FALSE
    ELSE INC(i)
    END
  END
END ShellWord;

(* Scans shell commands from i up to term, after it (")" for $(...), a
   subshell or <(...); "`" for `...`; 0X: to the end of the text) *)
PROCEDURE Commands(VAR s: Scanner; VAR i: LONGINT; term: CHAR);
  VAR ch: CHAR; start, j: LONGINT; expect, depth: INTEGER;
    cmd, pattern, patStart, test, def, wasDef, literal, done: BOOLEAN;

  PROCEDURE EndCase;
  BEGIN
    IF depth > 0 THEN DEC(depth) END;
    pattern := FALSE; cmd := FALSE
  END EndCase;

BEGIN
  cmd := TRUE;        (* the next word is a command's first *)
  pattern := FALSE;   (* the next words are a case pattern *)
  patStart := FALSE;  (* and nothing of it is read yet *)
  test := FALSE;      (* inside bash's [[ ]] *)
  def := FALSE;       (* the last word was a command's first: name () *)
  expect := ExNone; depth := 0; done := FALSE;
  WHILE ~done & (i < s.n) DO
    ch := s.t[i];
    IF (ch = " ") OR (ch = TAB) OR (ch = CR) THEN INC(i)
    ELSIF (ch = "\") & (Ch(s, i + 1) = LF) THEN INC(i, 2)
    ELSE
      wasDef := def; def := FALSE;
      IF ch = LF THEN
        INC(i); HereBodies(s, i);
        IF ~pattern & ~test THEN cmd := TRUE END
      ELSIF ch = "#" THEN
        j := i; WHILE (j < s.n) & (s.t[j] # LF) & (s.t[j] # CR) DO INC(j) END;
        Emit(s, Comment, i, j); i := j
      ELSIF test & IsMeta(ch) THEN INC(i)
      ELSIF (ch = term) & ~(pattern & (ch = ")")) THEN INC(i); done := TRUE
      ELSIF ch = ";" THEN
        IF (Ch(s, i + 1) = ";") OR (Ch(s, i + 1) = "&") THEN
          (* ;; ;& ;;& end a case item *)
          INC(i, 2); IF Ch(s, i) = "&" THEN INC(i) END;
          IF depth > 0 THEN pattern := TRUE; patStart := TRUE; cmd := FALSE ELSE cmd := TRUE END
        ELSE INC(i); cmd := TRUE
        END;
        expect := ExNone
      ELSIF (ch = "&") & (Ch(s, i + 1) = ">") THEN
        (* &> &>> *)
        INC(i); WHILE Ch(s, i) = ">" DO INC(i) END;
        cmd := FALSE
      ELSIF ch = "&" THEN
        INC(i); IF Ch(s, i) = "&" THEN INC(i) END;
        cmd := TRUE
      ELSIF ch = "|" THEN
        INC(i);
        IF pattern THEN patStart := FALSE
        ELSE
          IF (Ch(s, i) = "|") OR (Ch(s, i) = "&") THEN INC(i) END;
          cmd := TRUE
        END
      ELSIF ch = "(" THEN
        j := i + 1; WHILE (Ch(s, j) = " ") OR (Ch(s, j) = TAB) DO INC(j) END;
        IF pattern THEN INC(i); patStart := FALSE
        ELSIF (wasDef OR (expect = ExFuncBody)) & (Ch(s, j) = ")") THEN
          (* name (): a function, its body next *)
          i := j + 1; cmd := TRUE; expect := ExNone
        ELSIF (s.lang.shell = Bash) & (Ch(s, i + 1) = "(") & (cmd OR (expect = ExForName)) THEN
          (* ((...)), for ((...)) *)
          i := Balanced(s, i, "(", ")"); cmd := FALSE; expect := ExNone
        ELSE
          INC(i); Commands(s, i, ")"); cmd := FALSE; expect := ExNone
        END
      ELSIF ch = ")" THEN
        INC(i);
        IF pattern THEN pattern := FALSE; cmd := TRUE ELSE cmd := FALSE END
      ELSIF (ch = "<") OR (ch = ">") THEN
        IF Ch(s, i + 1) = "(" THEN INC(i, 2); Commands(s, i, ")")  (* <(...) *)
        ELSIF (ch = "<") & (Ch(s, i + 1) = "<") & (Ch(s, i + 2) # "<") THEN
          INC(i, 2); HereDoc(s, i)
        ELSE
          WHILE (Ch(s, i) = "<") OR (Ch(s, i) = ">") DO INC(i) END;
          IF (Ch(s, i) = "&") OR (Ch(s, i) = "|") THEN INC(i) END
        END;
        cmd := FALSE
      ELSE
        start := i; ShellWord(s, i, term, literal);
        IF i = start THEN INC(i) END;
        IF test THEN
          IF literal & Is(s, start, i, "]]") & IsReserved(s, start, i) THEN
            Emit(s, Reserved, start, i); test := FALSE; cmd := FALSE
          END
        ELSIF pattern THEN
          (* esac, not a|esac or (esac *)
          IF patStart & literal & Is(s, start, i, "esac") & IsReserved(s, start, i) THEN Emit(s, Reserved, start, i); EndCase
          ELSE patStart := FALSE
          END
        ELSIF expect = ExForName THEN expect := ExForIn; cmd := FALSE
        ELSIF (expect = ExForIn) & literal & Is(s, start, i, "in") & IsReserved(s, start, i) THEN
          Emit(s, Reserved, start, i); expect := ExNone; cmd := FALSE
        ELSIF (expect = ExForIn) & literal & Is(s, start, i, "do") & IsReserved(s, start, i) THEN
          Emit(s, Reserved, start, i); expect := ExNone; cmd := TRUE
        ELSIF expect = ExCaseWord THEN expect := ExCaseIn; cmd := FALSE
        ELSIF (expect = ExCaseIn) & literal & Is(s, start, i, "in") & IsReserved(s, start, i) THEN
          Emit(s, Reserved, start, i); expect := ExNone; INC(depth);
          pattern := TRUE; patStart := TRUE; cmd := FALSE
        ELSIF expect = ExFuncName THEN expect := ExFuncBody; cmd := TRUE
        ELSIF cmd & literal & IsReserved(s, start, i) THEN
          Emit(s, Reserved, start, i); expect := ExNone; cmd := TRUE;
          IF Is(s, start, i, "case") THEN expect := ExCaseWord; cmd := FALSE
          ELSIF Is(s, start, i, "for") OR Is(s, start, i, "select") THEN
            expect := ExForName; cmd := FALSE
          ELSIF Is(s, start, i, "function") THEN expect := ExFuncName; cmd := FALSE
          ELSIF Is(s, start, i, "[[") THEN test := TRUE; cmd := FALSE
          ELSIF Is(s, start, i, "esac") THEN EndCase
          ELSIF Is(s, start, i, "fi") OR Is(s, start, i, "done") OR Is(s, start, i, "}")
              OR Is(s, start, i, "in") OR Is(s, start, i, "]]") THEN
            cmd := FALSE
          END
        ELSE
          def := cmd; cmd := FALSE; expect := ExNone
        END
      END
    END
  END
END Commands;

(* The spans of text, in lang. NIL if text is empty. *)
PROCEDURE Scan*(lang: Language; text: Rope): Span;
  VAR s: Scanner; i, j: LONGINT; c, prev: INTEGER; lineStart, found: BOOLEAN; ch: CHAR;
BEGIN
  s.lang := lang; s.n := Ropes.Length(text); s.plain := 0;
  s.first := NIL; s.last := NIL;
  IF s.n = 0 THEN RETURN NIL END;
  NEW(s.t, s.n + 1); Ropes.Blit(text, 0, s.t^, 0, s.n); s.t[s.n] := 0X;
  s.nDocs := 0; i := 0;
  IF lang.shell # NoShell THEN
    WHILE i < s.n DO Commands(s, i, 0X) END;
    Emit(s, Plain, s.n, s.n);
    RETURN s.first
  END;
  lineStart := TRUE; prev := PrevOther;
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
    ELSIF lang.tick & (ch = "'") THEN
      (* Ada: the tick after a name, else a character literal *)
      IF prev = PrevName THEN prev := PrevTick; INC(i)
      ELSE
        j := CharEnd(s, i);
        IF j > i THEN Emit(s, String, i, j); i := j ELSE INC(i) END;
        prev := PrevOther
      END;
      lineStart := FALSE
    ELSIF IsQuote(lang, ch) THEN
      j := StringEnd(s, i); Emit(s, String, i, j); i := j; lineStart := FALSE;
      prev := PrevOther
    ELSIF lang.amp & (ch = "&") & (i + 1 < s.n) & IsIdent(s.t[i + 1]) & ~IsDigit(s.t[i + 1]) THEN
      (* Pascal: &begin is a name *)
      INC(i); WHILE (i < s.n) & IsIdent(s.t[i]) DO INC(i) END;
      lineStart := FALSE
    ELSIF lang.directives & lineStart & (ch = "#") THEN
      (* the directive's name is not a keyword: #if, #else; after
         #include, a header name <...> is a string: <new> *)
      INC(i);
      WHILE (i < s.n) & ((s.t[i] = " ") OR (s.t[i] = TAB)) DO INC(i) END;
      j := i;
      WHILE (i < s.n) & IsIdent(s.t[i]) DO INC(i) END;
      IF IsInclude(s, j, i) THEN
        WHILE (i < s.n) & ((s.t[i] = " ") OR (s.t[i] = TAB)) DO INC(i) END;
        IF (i < s.n) & (s.t[i] = "<") THEN
          j := i + 1;
          WHILE (j < s.n) & (s.t[j] # ">") & (s.t[j] # LF) & (s.t[j] # CR) DO INC(j) END;
          IF (j < s.n) & (s.t[j] = ">") THEN INC(j) END;
          Emit(s, String, i, j); i := j
        END
      END;
      lineStart := FALSE
    ELSIF IsDigit(ch) THEN
      INC(i);
      WHILE (i < s.n) & (IsIdent(s.t[i])
          OR (s.t[i] = ".") & (i + 1 < s.n) & IsDigit(s.t[i + 1])
          OR lang.digitSep & (s.t[i] = "'") & (i + 1 < s.n) & IsIdent(s.t[i + 1])) DO
        INC(i)
      END;
      lineStart := FALSE; prev := PrevOther
    ELSIF IsIdent(ch) THEN
      j := i + 1;
      WHILE (j < s.n) & IsIdent(s.t[j]) DO INC(j) END;
      IF lang.raw & (RawEnd(s, i, j) > i) THEN
        (* C++: R"d( ... )d" *)
        Emit(s, String, i, RawEnd(s, i, j)); j := s.plain; prev := PrevOther
      ELSIF prev = PrevTick THEN prev := PrevName  (* an attribute: X'Range *)
      ELSIF IsReserved(s, i, j) THEN
        Emit(s, Reserved, i, j);
        IF (j - i = 3) & (Ropes.LowerChar(s.t[i]) = "a") & (Ropes.LowerChar(s.t[i + 1]) = "l")
            & (Ropes.LowerChar(s.t[i + 2]) = "l") THEN
          prev := PrevName  (* Ada: X.all'Access *)
        ELSE prev := PrevOther
        END
      ELSE prev := PrevName
      END;
      i := j; lineStart := FALSE
    ELSE
      IF (ch = LF) OR (ch = CR) THEN lineStart := TRUE
      ELSIF (ch # " ") & (ch # TAB) THEN lineStart := FALSE
      END;
      IF ch = ")" THEN prev := PrevName
      ELSIF (ch # " ") & (ch # TAB) & (ch # LF) & (ch # CR) THEN prev := PrevOther
      END;
      INC(i)
    END
  END;
  Emit(s, Plain, s.n, s.n);
  RETURN s.first
END Scan;

BEGIN
  InitLanguages; KeepBuiltins
END PdCode.
