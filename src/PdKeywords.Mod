MODULE PdKeywords;
(* PdKeywords: users' lists of reserved words (PLAN.md Phase 24.8;
   decisions 31, 40 and 47; docs/research/syntax-highlighting-small.md
   §6).

   A list changes the words of one of PdCode's languages. It comes from
   a file, named by --code-keywords=LANG:FILE, or from the metadata
   field code-keywords (PdShared.SetCodeStyle reads the field and
   calls Words). Each word is added to the language's built-in words;
   a word "-word" takes word out of them. A file whose first line is
   "#!replace" replaces the built-in words instead.

   A file is words separated by spaces, tabs and line ends; "#" at the
   start of a word starts a comment that runs to the line's end. A
   language that ignores case compares its words without case.

   The files are read when they are named, so a missing one stops
   podoc at once, with exit status 1 as pandoc's missing files do
   (--abbreviations, --syntax-definition). They are applied after the
   metadata's lists, by Apply. *)

IMPORT PdIO, PdCode;

CONST
  WordLen = 64; (* longer words are cut, and refused by PdCode *)

TYPE
  (* A list from a file: its language, whether it replaces the built-in
     words, its text from start, after the "#!replace" line *)
  List = POINTER TO ListDesc;
  ListDesc = RECORD
    lang: PdCode.Language;
    replace: BOOLEAN;
    text: PdIO.Text;
    start, len: LONGINT;
    next: List
  END;

VAR
  first, last: List;

(* Adds the word w to lang's words, or with a "-" takes the rest out;
   warns about a word too long to be a reserved word *)
PROCEDURE Word*(lang: PdCode.Language; w: ARRAY OF CHAR);
  VAR i: INTEGER; rest: ARRAY WordLen OF CHAR;
BEGIN
  IF (w[0] = "-") & (w[1] # 0X) THEN
    i := 1;
    WHILE (i < LEN(w)) & (w[i] # 0X) & (i - 1 < WordLen - 1) DO rest[i - 1] := w[i]; INC(i) END;
    rest[i - 1] := 0X;
    PdCode.RemoveWord(lang, rest)
  ELSIF ~PdCode.AddWord(lang, w) THEN
    PdIO.Message3("[WARNING] code-keywords: '", w, "' is too long to be a reserved word; ignored")
  END
END Word;

PROCEDURE IsBlank(ch: CHAR): BOOLEAN;
BEGIN RETURN (ch = " ") OR (ch = 09X) OR (ch = 0AX) OR (ch = 0DX)
END IsBlank;

(* Gives each word of t[start .. end-1] to Word; with comments, "#" at
   a word's start runs to the line's end *)
PROCEDURE Words*(lang: PdCode.Language; VAR t: ARRAY OF CHAR; start, end: LONGINT; comments: BOOLEAN);
  VAR i: LONGINT; k: INTEGER; w: ARRAY WordLen + 1 OF CHAR;
BEGIN
  i := start;
  WHILE i < end DO
    WHILE (i < end) & IsBlank(t[i]) DO INC(i) END;
    IF (i < end) & comments & (t[i] = "#") THEN
      WHILE (i < end) & (t[i] # 0AX) DO INC(i) END
    ELSIF i < end THEN
      k := 0;
      WHILE (i < end) & ~IsBlank(t[i]) DO
        IF k < WordLen THEN w[k] := t[i]; INC(k) END;
        INC(i)
      END;
      w[k] := 0X;
      Word(lang, w)
    END
  END
END Words;

(* Reads the list --code-keywords=spec names, spec being LANG:FILE.
   A spec without ":" or with a language podoc does not know is an
   option error; a file that cannot be read stops podoc with exit
   status 1. *)
PROCEDURE AddFile*(spec: ARRAY OF CHAR);
  VAR i, k: INTEGER; name: ARRAY 32 OF CHAR; file: ARRAY 4096 OF CHAR;
    l: List; len, j: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(spec)) & (spec[i] # 0X) & (spec[i] # ":") DO INC(i) END;
  IF (i >= LEN(spec)) OR (spec[i] # ":") OR (i = 0) OR (i >= LEN(name)) THEN
    PdIO.Message("--code-keywords must be LANGUAGE:FILE");
    PdIO.Exit(PdIO.OptionError)
  END;
  FOR k := 0 TO i - 1 DO name[k] := spec[k] END;
  name[i] := 0X;
  k := 0; INC(i);
  WHILE (i < LEN(spec)) & (spec[i] # 0X) & (k < LEN(file) - 1) DO file[k] := spec[i]; INC(k); INC(i) END;
  file[k] := 0X;
  NEW(l); l.lang := PdCode.Find(name); l.next := NIL;
  IF l.lang = NIL THEN
    PdIO.Message3("--code-keywords: unknown language '", name, "'");
    PdIO.Exit(PdIO.OptionError)
  END;
  IF file = "" THEN
    PdIO.Message("--code-keywords must be LANGUAGE:FILE");
    PdIO.Exit(PdIO.OptionError)
  END;
  PdIO.ReadFile(file, l.text, len);
  l.len := len; l.start := 0; l.replace := FALSE;
  (* a first line "#!replace", with trailing blanks *)
  IF (len >= 9) & (l.text[0] = "#") & (l.text[1] = "!") & (l.text[2] = "r")
     & (l.text[3] = "e") & (l.text[4] = "p") & (l.text[5] = "l") & (l.text[6] = "a")
     & (l.text[7] = "c") & (l.text[8] = "e") THEN
    j := 9;
    WHILE (j < len) & (l.text[j] # 0AX) & IsBlank(l.text[j]) DO INC(j) END;
    IF (j = len) OR (l.text[j] = 0AX) THEN l.replace := TRUE; l.start := j END
  END;
  IF first = NIL THEN first := l ELSE last.next := l END;
  last := l
END AddFile;

(* Applies the files' lists, in the order they were named *)
PROCEDURE Apply*;
  VAR l: List;
BEGIN
  l := first;
  WHILE l # NIL DO
    IF l.replace THEN PdCode.Clear(l.lang) END;
    Words(l.lang, l.text^, l.start, l.len, TRUE);
    l := l.next
  END
END Apply;

BEGIN
  first := NIL; last := NIL
END PdKeywords.
