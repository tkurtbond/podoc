MODULE PdGlob;
(* PdGlob: the file names a pattern names, as Python's
   glob.glob(pattern, recursive=True) finds them, for PdInclude.

   In a part of the pattern (between "/"s), "*", "?" and "[...]" are
   read as Python's fnmatch reads them, matching a whole name, character
   by character (UTF-8 is decoded); a part that is "**" matches any
   number of directories, none too. A name starting with "." is matched
   only by a part that starts with "." (and never by "**"). A part with
   none of "*?[" is taken as it is.

   The names found are sorted as natsort's natsorted sorts them: a run
   of digits compares as its number, the text between as code points.
   Names natsorted takes as equal ("a1", "a01") are in byte order;
   natsorted keeps the order the directory lists them in, and compares
   names after Unicode's NFD normalization, which podoc does not do.

   The directories are read by the module's part in C, PdGlob.c, with
   POSIX opendir and readdir. *)

IMPORT SYSTEM;

CONST
  PathLen = 4096;
  Missing = 0; Directory = 2; (* what pdglob_kind says *)
  Sep = -1; (* the hyphen of a range, in a set *)
  MaxDepth = 256; (* how deep "**" goes *)

TYPE
  Path = ARRAY PathLen OF CHAR;
  Chars = ARRAY PathLen OF LONGINT; (* code points *)

  Name* = POINTER TO ARRAY OF CHAR;
  List* = POINTER TO ListDesc;
  ListDesc* = RECORD
    name*: Name;
    next*: List
  END;

PROCEDURE ["C", "pdglob_open"] COpen(name: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
PROCEDURE ["C", "pdglob_next"] CNext(d, buf: SYSTEM.ADDRESS; len: SYSTEM.INT32): SYSTEM.INT32;
PROCEDURE ["C", "pdglob_close"] CClose(d: SYSTEM.ADDRESS);
PROCEDURE ["C", "pdglob_kind"] CKind(name: SYSTEM.ADDRESS; follow: SYSTEM.INT32): SYSTEM.INT32;

(* Strings *)

PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0;
  WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Length;

(* Adds s to the front of the list l *)
PROCEDURE Add(VAR l: List; VAR s: ARRAY OF CHAR);
  VAR e: List;
BEGIN
  NEW(e); NEW(e.name, Length(s) + 1); COPY(s, e.name^);
  e.next := l; l := e
END Add;

(* r becomes Python's os.path.join(a, b) *)
PROCEDURE Join(VAR a, b: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
  VAR n, i, k: LONGINT;
BEGIN
  IF (b[0] = "/") OR (a[0] = 0X) THEN COPY(b, r)
  ELSE
    COPY(a, r); n := Length(r);
    IF (r[n - 1] # "/") & (n < LEN(r) - 1) THEN r[n] := "/"; INC(n) END;
    i := 0; k := n;
    WHILE (b[i] # 0X) & (k < LEN(r) - 1) DO r[k] := b[i]; INC(i); INC(k) END;
    r[k] := 0X
  END
END Join;

(* r becomes glob's _join(a, b): a or b when the other is empty *)
PROCEDURE GJoin(VAR a, b: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
BEGIN
  IF b[0] = 0X THEN COPY(a, r) ELSE Join(a, b, r) END
END GJoin;

(* dir and base become Python's os.path.split(p) *)
PROCEDURE Split(VAR p: ARRAY OF CHAR; VAR dir, base: ARRAY OF CHAR);
  VAR i, n, j, k: LONGINT;
BEGIN
  n := Length(p); i := n;
  WHILE (i > 0) & (p[i - 1] # "/") DO DEC(i) END;
  k := 0; j := i;
  WHILE j < n DO base[k] := p[j]; INC(k); INC(j) END;
  base[k] := 0X;
  j := i;
  WHILE (j > 0) & (p[j - 1] = "/") DO DEC(j) END;
  IF j = 0 THEN j := i END; (* all slashes *)
  k := 0;
  WHILE k < j DO dir[k] := p[k]; INC(k) END;
  dir[k] := 0X
END Split;

PROCEDURE HasMagic(VAR s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    IF (s[i] = "*") OR (s[i] = "?") OR (s[i] = "[") THEN RETURN TRUE END;
    INC(i)
  END;
  RETURN FALSE
END HasMagic;

(* Files *)

(* Whether the file name exists, a broken symbolic link too *)
PROCEDURE Exists(VAR name: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN CKind(SYSTEM.ADR(name), 0) # Missing
END Exists;

PROCEDURE IsDir(VAR name: ARRAY OF CHAR): BOOLEAN;
BEGIN
  RETURN CKind(SYSTEM.ADR(name), 1) = Directory
END IsDir;

(* The entries of the directory dir ("" is the working directory) in l;
   only the directories if dironly *)
PROCEDURE ListDir(VAR dir: ARRAY OF CHAR; dironly: BOOLEAN; VAR l: List);
  VAR d: SYSTEM.ADDRESS; buf, t: Path;
BEGIN
  l := NIL;
  IF dir[0] = 0X THEN t := "." ELSE COPY(dir, t) END;
  d := COpen(SYSTEM.ADR(t));
  IF d # 0 THEN
    WHILE CNext(d, SYSTEM.ADR(buf), PathLen) >= 0 DO
      IF dironly THEN
        GJoin(dir, buf, t);
        IF IsDir(t) THEN Add(l, buf) END
      ELSE Add(l, buf)
      END
    END;
    CClose(d)
  END
END ListDir;

(* Matching *)

(* c[0 .. n-1] becomes the code points of the UTF-8 s; a byte that
   starts no character stands for itself *)
PROCEDURE Decode(VAR s: ARRAY OF CHAR; VAR c: Chars; VAR n: LONGINT);
  VAR i, b, k, cp: LONGINT;
BEGIN
  i := 0; n := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (n < LEN(c)) DO
    b := ORD(s[i]); INC(i);
    IF b < 80H THEN cp := b; k := 0
    ELSIF b DIV 20H = 6 THEN cp := b MOD 20H; k := 1
    ELSIF b DIV 10H = 0EH THEN cp := b MOD 10H; k := 2
    ELSIF b DIV 8 = 1EH THEN cp := b MOD 8; k := 3
    ELSE cp := b; k := 0
    END;
    WHILE (k > 0) & (i < LEN(s)) & (ORD(s[i]) DIV 40H = 2) DO
      cp := cp * 40H + ORD(s[i]) MOD 40H; INC(i); DEC(k)
    END;
    c[n] := cp; INC(n)
  END
END Decode;

(* Whether c is in the set p[i .. j-1], between "[" and "]", as
   fnmatch's translate makes it a regular expression's set: chunks
   split at hyphens, ranges whose ends are reversed removed *)
PROCEDURE InSet(VAR p: Chars; i, j, c: LONGINT): BOOLEAN;
  VAR t: Chars; m, s, k, q, x: LONGINT;
BEGIN
  m := 0; s := i;
  IF p[i] = ORD("!") THEN k := i + 2 ELSE k := i + 1 END;
  LOOP
    WHILE (k < j) & (p[k] # ORD("-")) DO INC(k) END;
    IF k >= j THEN EXIT END;
    WHILE s < k DO t[m] := p[s]; INC(m); INC(s) END;
    t[m] := Sep; INC(m);
    s := k + 1; k := k + 3
  END;
  IF s < j THEN
    WHILE s < j DO t[m] := p[s]; INC(m); INC(s) END
  ELSE t[m - 1] := ORD("-") (* a hyphen at the end is itself *)
  END;
  q := m - 1;
  WHILE q > 0 DO
    IF (t[q] = Sep) & (t[q - 1] > t[q + 1]) THEN
      x := q - 1;
      WHILE x + 3 < m DO t[x] := t[x + 3]; INC(x) END;
      DEC(m, 3); DEC(q, 2)
    ELSE DEC(q)
    END
  END;
  IF m = 0 THEN RETURN FALSE
  ELSIF (m = 1) & (t[0] = ORD("!")) THEN RETURN TRUE
  END;
  IF t[0] = ORD("!") THEN q := 1 ELSE q := 0 END;
  WHILE q < m DO
    IF (q + 2 < m) & (t[q + 1] = Sep) THEN
      IF (c >= t[q]) & (c <= t[q + 2]) THEN RETURN t[0] # ORD("!") END;
      INC(q, 3)
    ELSE
      IF c = t[q] THEN RETURN t[0] # ORD("!") END;
      INC(q)
    END
  END;
  RETURN t[0] = ORD("!")
END InSet;

(* Whether the pattern p[pi .. pn-1] matches s[si .. sn-1] *)
PROCEDURE Matches(VAR p: Chars; pi, pn: LONGINT; VAR s: Chars; si, sn: LONGINT): BOOLEAN;
  VAR j: LONGINT;
BEGIN
  WHILE pi < pn DO
    IF p[pi] = ORD("*") THEN
      WHILE (pi < pn) & (p[pi] = ORD("*")) DO INC(pi) END;
      IF pi = pn THEN RETURN TRUE END;
      LOOP
        IF Matches(p, pi, pn, s, si, sn) THEN RETURN TRUE END;
        IF si = sn THEN RETURN FALSE END;
        INC(si)
      END
    ELSIF si = sn THEN RETURN FALSE
    ELSIF p[pi] = ORD("?") THEN INC(pi); INC(si)
    ELSE
      j := pi + 1;
      IF p[pi] = ORD("[") THEN
        IF (j < pn) & (p[j] = ORD("!")) THEN INC(j) END;
        IF (j < pn) & (p[j] = ORD("]")) THEN INC(j) END;
        WHILE (j < pn) & (p[j] # ORD("]")) DO INC(j) END
      END;
      IF (p[pi] = ORD("[")) & (j < pn) THEN
        IF ~InSet(p, pi + 1, j, s[si]) THEN RETURN FALSE END;
        pi := j + 1; INC(si)
      ELSIF p[pi] = s[si] THEN INC(pi); INC(si)
      ELSE RETURN FALSE
      END
    END
  END;
  RETURN si = sn
END Matches;

(* Whether the pattern matches the whole of the name, as Python's
   fnmatch.fnmatchcase *)
PROCEDURE Match*(pattern, name: ARRAY OF CHAR): BOOLEAN;
  VAR p, s: Chars; pn, sn: LONGINT;
BEGIN
  Decode(pattern, p, pn); Decode(name, s, sn);
  RETURN Matches(p, 0, pn, s, 0, sn)
END Match;

(* Globbing *)

PROCEDURE^ IGlob(VAR root, pathname: ARRAY OF CHAR; dironly: BOOLEAN; VAR l: List);

(* The names in the directory dir that the pattern matches, added to l *)
PROCEDURE Glob1(VAR dir, pattern: ARRAY OF CHAR; dironly: BOOLEAN; VAR l: List);
  VAR names: List; p, s: Chars; pn, sn: LONGINT;
BEGIN
  ListDir(dir, dironly, names);
  Decode(pattern, p, pn);
  WHILE names # NIL DO
    IF (names.name[0] # ".") OR (pattern[0] = ".") THEN
      Decode(names.name^, s, sn);
      IF Matches(p, 0, pn, s, 0, sn) THEN Add(l, names.name^) END
    END;
    names := names.next
  END
END Glob1;

(* The name base in the directory dir, if it exists, added to l *)
PROCEDURE Glob0(VAR dir, base: ARRAY OF CHAR; VAR l: List);
  VAR t: Path;
BEGIN
  IF base[0] # 0X THEN
    GJoin(dir, base, t);
    IF Exists(t) THEN Add(l, base) END
  ELSIF IsDir(dir) THEN Add(l, base)
  END
END Glob0;

(* What the directory dir holds, below it too, each spelled after
   prefix, added to l *)
PROCEDURE RListDir(VAR dir, prefix: ARRAY OF CHAR; dironly: BOOLEAN; depth: INTEGER;
                   VAR l: List);
  VAR names: List; rel, path: Path;
BEGIN
  IF depth < MaxDepth THEN
    ListDir(dir, dironly, names);
    WHILE names # NIL DO
      IF names.name[0] # "." THEN
        GJoin(prefix, names.name^, rel); Add(l, rel);
        GJoin(dir, names.name^, path);
        RListDir(path, rel, dironly, depth + 1, l)
      END;
      names := names.next
    END
  END
END RListDir;

(* What "**" matches in the directory dir, added to l *)
PROCEDURE Glob2(VAR dir: ARRAY OF CHAR; dironly: BOOLEAN; VAR l: List);
  VAR empty: ARRAY 1 OF CHAR;
BEGIN
  empty[0] := 0X;
  IF (dir[0] = 0X) OR IsDir(dir) THEN Add(l, empty) END;
  RListDir(dir, empty, dironly, 0, l)
END Glob2;

(* glob's _iglob: the names pathname names, relative to the directory
   root ("" is the working directory) and spelled as pathname spells
   them, added to l; only directories if dironly *)
PROCEDURE IGlob(VAR root, pathname: ARRAY OF CHAR; dironly: BOOLEAN; VAR l: List);
  VAR dir, base, real, t: Path; dirs, names: List;
BEGIN
  Split(pathname, dir, base);
  IF ~HasMagic(pathname) THEN
    IF base[0] # 0X THEN
      GJoin(root, pathname, t);
      IF Exists(t) THEN Add(l, pathname) END
    ELSE
      GJoin(root, dir, t);
      IF IsDir(t) THEN Add(l, pathname) END
    END
  ELSIF dir[0] = 0X THEN
    IF base = "**" THEN Glob2(root, dironly, l) ELSE Glob1(root, base, dironly, l) END
  ELSE
    dirs := NIL;
    IF (dir # pathname) & HasMagic(dir) THEN IGlob(root, dir, TRUE, dirs)
    ELSE Add(dirs, dir)
    END;
    WHILE dirs # NIL DO
      GJoin(root, dirs.name^, real); names := NIL;
      IF base = "**" THEN Glob2(real, dironly, names)
      ELSIF HasMagic(base) THEN Glob1(real, base, dironly, names)
      ELSE Glob0(real, base, names)
      END;
      WHILE names # NIL DO
        Join(dirs.name^, names.name^, t); Add(l, t);
        names := names.next
      END;
      dirs := dirs.next
    END
  END
END IGlob;

(* Sorting *)

PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "0") & (ch <= "9")
END IsDigit;

(* Compares a and b as natsort's keys: -1, 0 or 1 *)
PROCEDURE Compare*(VAR a, b: ARRAY OF CHAR): INTEGER;
  VAR i, j, si, sj, ni, nj, k: LONGINT;
BEGIN
  i := 0; j := 0;
  LOOP
    (* the text before the next number *)
    WHILE (a[i] # 0X) & ~IsDigit(a[i]) & (a[i] = b[j]) DO INC(i); INC(j) END;
    IF (a[i] # 0X) & ~IsDigit(a[i]) THEN
      IF (b[j] = 0X) OR IsDigit(b[j]) OR (a[i] > b[j]) THEN RETURN 1 ELSE RETURN -1 END
    ELSIF (b[j] # 0X) & ~IsDigit(b[j]) THEN RETURN -1
    ELSIF a[i] = 0X THEN
      IF b[j] = 0X THEN RETURN 0 ELSE RETURN -1 END
    ELSIF b[j] = 0X THEN RETURN 1
    END;
    (* both at a number: leading zeros skipped, the longer the larger *)
    WHILE a[i] = "0" DO INC(i) END;
    WHILE b[j] = "0" DO INC(j) END;
    si := i; sj := j;
    WHILE IsDigit(a[i]) DO INC(i) END;
    WHILE IsDigit(b[j]) DO INC(j) END;
    ni := i - si; nj := j - sj;
    IF ni # nj THEN
      IF ni > nj THEN RETURN 1 ELSE RETURN -1 END
    END;
    k := 0;
    WHILE k < ni DO
      IF a[si + k] # b[sj + k] THEN
        IF a[si + k] > b[sj + k] THEN RETURN 1 ELSE RETURN -1 END
      END;
      INC(k)
    END
  END
END Compare;

(* Whether a comes before b: natsort's order, then the bytes *)
PROCEDURE Before(VAR a, b: ARRAY OF CHAR): BOOLEAN;
  VAR c: INTEGER;
BEGIN
  c := Compare(a, b);
  RETURN (c < 0) OR (c = 0) & (a < b)
END Before;

(* l sorted, by insertion *)
PROCEDURE Sort(VAR l: List);
  VAR r, e, p: List;
BEGIN
  r := NIL;
  WHILE l # NIL DO
    e := l; l := l.next;
    IF (r = NIL) OR Before(e.name^, r.name^) THEN e.next := r; r := e
    ELSE
      p := r;
      WHILE (p.next # NIL) & ~Before(e.name^, p.next.name^) DO p := p.next END;
      e.next := p.next; p.next := e
    END
  END;
  l := r
END Sort;

(* The names the pattern names, in l, sorted; a relative pattern is
   relative to the directory root ("" for the working directory), and
   the names are spelled as the pattern spells them *)
PROCEDURE Glob*(root, pattern: ARRAY OF CHAR; VAR l: List);
  VAR p: List;
BEGIN
  l := NIL;
  IGlob(root, pattern, FALSE, l);
  IF (pattern[0] = 0X) OR (pattern[0] = "*") & (pattern[1] = "*") THEN
    (* glob.iglob skips the empty name "**" or "**/" names first *)
    IF (l # NIL) & (l.name[0] = 0X) THEN l := l.next
    ELSIF l # NIL THEN
      p := l;
      WHILE (p.next # NIL) & (p.next.name[0] # 0X) DO p := p.next END;
      IF p.next # NIL THEN p.next := p.next.next END
    END
  END;
  Sort(l)
END Glob;

END PdGlob.
