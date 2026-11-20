MODULE PdInclude;
(* PdInclude: the filter pandoc-include (version 1.4), built in.

   A paragraph that, written as markdown_strict, reads

     !include path
     !include`incrementSection=n` path

   ($include is the same) is replaced by the blocks of the file path,
   read as pandoc markdown with the tab stop 4, as pandoc-include
   reads it with a pandoc of its own. The included file's own includes
   are expanded first, relative to its directory; its metadata keys
   that the including document lacks are added to it; and
   incrementSection adds n to the level of the headers at the top of
   what it includes. A path in quotes ("...", '...' or `...`) may hold
   quote characters.

   The path is looked for relative to the including file's directory,
   then relative to the working directory. It may hold wildcards, as
   Python's glob reads them (PdGlob): the files it names are included
   one after the other, in natsort's order. A path that names no file
   is warned about and the paragraph kept; a directory, a file podoc
   cannot read, a file that includes itself, directly or not, and a
   file whose name says it is not markdown are errors, as are a malformed include line, !include-header and the
   other options of pandoc-include (startLine, endLine, snippetStart,
   snippetEnd, includeSnippetDelimiters, dedent, xslt, format, raw).
   An unknown option is warned about and ignored.

   Every relative image path in the document, the including one too,
   is made relative to the first input's directory, as pandoc-include
   does with pathlib: "." and empty parts dropped. A URL with a scheme
   and an absolute path are kept. *)

IMPORT Platform, Ropes, PdIO, PdSource, A := PdAst, PdMarkdown, PdGlob;

CONST
  PathLen = 4096;
  LineLen = 4096;
  MsgLen = 8192;
  TabStop = 4; (* pandoc's default: pandoc-include's pandoc has no --tab-stop *)
  MaxIncrement = 1000;

TYPE
  Path = ARRAY PathLen OF CHAR;

  (* An input, or a file being included *)
  File = POINTER TO FileDesc;
  FileDesc = RECORD
    id: Platform.FileIdentity;
    next: File
  END;

  Walker = POINTER TO WalkerDesc;
  WalkerDesc = RECORD (A.WalkerDesc)
    doc: A.Doc; (* the document walked *)
    cur: Path (* its directory, relative to the working directory *)
  END;

VAR
  filter: Path; (* the filter's name, as given *)
  open: File; (* the inputs and the files being included, the innermost first *)

(* Strings *)

PROCEDURE Length(VAR s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0;
  WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Length;

(* Appends s to d, cutting it if it does not fit *)
PROCEDURE Append(s: ARRAY OF CHAR; VAR d: ARRAY OF CHAR);
  VAR i, j: LONGINT;
BEGIN
  j := Length(d); i := 0;
  WHILE (i < LEN(s)) & (s[i] # 0X) & (j < LEN(d) - 1) DO
    d[j] := s[i]; INC(i); INC(j)
  END;
  d[j] := 0X
END Append;

PROCEDURE AppendChar(ch: CHAR; VAR d: ARRAY OF CHAR);
  VAR j: LONGINT;
BEGIN
  j := Length(d);
  IF j < LEN(d) - 1 THEN d[j] := ch; d[j + 1] := 0X END
END AppendChar;

(* d becomes s[start .. end-1] *)
PROCEDURE Sub(VAR s: ARRAY OF CHAR; start, end: LONGINT; VAR d: ARRAY OF CHAR);
  VAR j: LONGINT;
BEGIN
  j := 0;
  WHILE (start < end) & (j < LEN(d) - 1) DO d[j] := s[start]; INC(j); INC(start) END;
  d[j] := 0X
END Sub;

(* Ends podoc as a failing filter does, with the message a and b *)
PROCEDURE Fail(a, b: ARRAY OF CHAR);
  VAR m: ARRAY MsgLen OF CHAR;
BEGIN
  m := "Error running filter '"; Append(filter, m); Append("':", m);
  PdIO.Message(m);
  COPY(a, m); Append(b, m);
  PdIO.Message(m);
  PdIO.Exit(PdIO.FilterError)
END Fail;

(* Paths *)

(* r becomes Python's os.path.join(a, b) *)
PROCEDURE Join(VAR a, b: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
  VAR n: LONGINT;
BEGIN
  IF (b[0] = "/") OR (a[0] = 0X) THEN COPY(b, r)
  ELSE
    COPY(a, r); n := Length(r);
    IF r[n - 1] # "/" THEN AppendChar("/", r) END;
    Append(b, r)
  END
END Join;

(* r becomes Python's os.path.dirname(p) *)
PROCEDURE DirName(VAR p: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
  VAR i, n: LONGINT;
BEGIN
  n := Length(p); i := n;
  WHILE (i > 0) & (p[i - 1] # "/") DO DEC(i) END;
  (* p[0 .. i-1] is the head, with its slashes *)
  n := i;
  WHILE (n > 0) & (p[n - 1] = "/") DO DEC(n) END;
  IF n = 0 THEN n := i END; (* all slashes *)
  Sub(p, 0, n, r)
END DirName;

(* Appends the parts of p, split at "/", to r[0 .. k-1], which holds a
   root of rootLen slashes and then parts parts joined with "/": empty
   parts and "." are dropped. When norm, ".." takes away the part before
   it if there is one that is not "..", and is dropped after a root. *)
PROCEDURE AddParts(VAR p: ARRAY OF CHAR; norm: BOOLEAN; rootLen: LONGINT;
                   VAR r: ARRAY OF CHAR; VAR k, parts: LONGINT);
  VAR i, j, s, n: LONGINT; last: ARRAY 3 OF CHAR;
BEGIN
  n := Length(p); i := 0;
  WHILE i < n DO
    s := i;
    WHILE (i < n) & (p[i] # "/") DO INC(i) END;
    (* p[s .. i-1] is a part *)
    j := k;
    WHILE (j > rootLen) & (r[j - 1] # "/") DO DEC(j) END;
    Sub(r, j, k, last); (* the last part, if parts > 0 *)
    IF (i = s) OR (i - s = 1) & (p[s] = ".") THEN
      (* dropped *)
    ELSIF norm & (i - s = 2) & (p[s] = ".") & (p[s + 1] = ".")
          & ((parts > 0) & (last # "..") OR (parts = 0) & (rootLen > 0)) THEN
      IF parts > 0 THEN
        k := j;
        IF k > rootLen THEN DEC(k) END; (* the "/" before it *)
        DEC(parts)
      END
    ELSE
      IF (parts > 0) & (k < LEN(r) - 1) THEN r[k] := "/"; INC(k) END;
      WHILE (s < i) & (k < LEN(r) - 1) DO r[k] := p[s]; INC(k); INC(s) END;
      INC(parts)
    END;
    IF i < n THEN INC(i) END
  END;
  r[k] := 0X
END AddParts;

(* r becomes Python's os.path.normpath(p) *)
PROCEDURE NormPath(VAR p: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
  VAR k, parts, root: LONGINT;
BEGIN
  k := 0; parts := 0;
  IF p[0] = "/" THEN
    r[0] := "/"; k := 1;
    IF (p[1] = "/") & (p[2] # "/") THEN r[1] := "/"; k := 2 END (* POSIX keeps two *)
  END;
  root := k;
  AddParts(p, TRUE, root, r, k, parts);
  IF k = 0 THEN COPY(".", r) END
END NormPath;

(* r becomes str(Path(a) / b), with pathlib's normalization: empty
   parts and "." dropped, ".." kept *)
PROCEDURE PathJoin(VAR a, b: ARRAY OF CHAR; VAR r: ARRAY OF CHAR);
  VAR k, parts, root: LONGINT;
BEGIN
  k := 0; parts := 0;
  IF a[0] = "/" THEN r[0] := "/"; k := 1 END;
  root := k;
  AddParts(a, FALSE, root, r, k, parts);
  AddParts(b, FALSE, root, r, k, parts);
  IF k = 0 THEN COPY(".", r) END
END PathJoin;

(* Whether url has a scheme, as Python's urlparse sees it *)
PROCEDURE HasScheme(VAR url: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT; ch: CHAR;
BEGIN
  ch := CAP(url[0]);
  IF (ch < "A") OR (ch > "Z") THEN RETURN FALSE END;
  i := 1;
  LOOP
    ch := CAP(url[i]);
    IF ch = ":" THEN RETURN TRUE
    ELSIF ~(((ch >= "A") & (ch <= "Z")) OR ((ch >= "0") & (ch <= "9"))
            OR (ch = "+") OR (ch = "-") OR (ch = ".")) THEN
      RETURN FALSE
    END;
    INC(i)
  END
END HasScheme;

(* Whether pandoc-include reads the file name as some format other than
   markdown (its extension table) *)
PROCEDURE NotMarkdown(VAR name: ARRAY OF CHAR; VAR ext: ARRAY OF CHAR): BOOLEAN;
  VAR i, n, b: LONGINT;
BEGIN
  n := Length(name); i := n; b := n;
  WHILE (b > 0) & (name[b - 1] # "/") DO DEC(b) END;
  WHILE (i > b) & (name[i - 1] # ".") DO DEC(i) END;
  (* Python's splitext: leading dots of the base name start no extension *)
  ext[0] := 0X;
  IF i > b THEN
    WHILE (b < i - 1) & (name[b] = ".") DO INC(b) END;
    IF b < i - 1 THEN Sub(name, i - 1, n, ext) END
  END;
  RETURN (ext = ".adoc") OR (ext = ".asciidoc") OR (ext = ".context")
    OR (ext = ".ctx") OR (ext = ".db") OR (ext = ".doc") OR (ext = ".docx")
    OR (ext = ".dokuwiki") OR (ext = ".epub") OR (ext = ".fb2")
    OR (ext = ".htm") OR (ext = ".html") OR (ext = ".icml")
    OR (ext = ".json") OR (ext = ".latex") OR (ext = ".lhs")
    OR (ext = ".ltx") OR (ext = ".ms") OR (ext = ".muse")
    OR (ext = ".native") OR (ext = ".odt") OR (ext = ".opml")
    OR (ext = ".org") OR (ext = ".pdf") OR (ext = ".pptx")
    OR (ext = ".roff") OR (ext = ".rst") OR (ext = ".rtf") OR (ext = ".s5")
    OR (ext = ".t2t") OR (ext = ".tei") OR (ext = ".tex")
    OR (ext = ".texi") OR (ext = ".texinfo") OR (ext = ".textile")
    OR (ext = ".wiki") OR (ext = ".xhtml") OR (ext = ".ipynb")
    OR (ext = ".csv") OR (ext = ".bib") OR (ext = ".xml") OR (ext = ".xslt")
END NotMarkdown;

(* Whether the file name is one podoc can read: not a directory *)
PROCEDURE Readable(VAR name: ARRAY OF CHAR): BOOLEAN;
  VAR h: Platform.FileHandle; e: Platform.ErrorCode; n: LONGINT;
    b: ARRAY 1 OF CHAR;
BEGIN
  IF Platform.OldRO(name, h) # 0 THEN RETURN FALSE END;
  e := Platform.ReadBuf(h, b, n);
  IF Platform.Close(h) # 0 THEN END;
  RETURN e = 0
END Readable;

(* The include line *)

PROCEDURE Put(VAR s: ARRAY OF CHAR; VAR k: LONGINT; ch: CHAR; VAR ok: BOOLEAN);
BEGIN
  IF k < LEN(s) - 1 THEN s[k] := ch; INC(k) ELSE ok := FALSE END
END Put;

PROCEDURE PutString(VAR s: ARRAY OF CHAR; VAR k: LONGINT; t: ARRAY OF CHAR;
                    VAR ok: BOOLEAN);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE (i < LEN(t)) & (t[i] # 0X) DO Put(s, k, t[i], ok); INC(i) END
END PutString;

(* Puts the curly quote U+20xx, UTF-8 E2 80 last *)
PROCEDURE PutQuote(VAR s: ARRAY OF CHAR; VAR k: LONGINT; last: CHAR; VAR ok: BOOLEAN);
BEGIN
  Put(s, k, 0E2X, ok); Put(s, k, 80X, ok); Put(s, k, last, ok)
END PutQuote;

PROCEDURE PutRope(VAR s: ARRAY OF CHAR; VAR k: LONGINT; r: Ropes.Rope;
                  VAR ok: BOOLEAN);
  VAR i, n: LONGINT;
BEGIN
  n := Ropes.Length(r); i := 0;
  WHILE ok & (i < n) DO Put(s, k, Ropes.Fetch(r, i), ok); INC(i) END
END PutRope;

(* Appends the text of a Str, r, to s[0 .. k-1], with the brackets
   escaped as markdown_strict escapes them (so that a glob's set never
   matches, as in pandoc-include) *)
PROCEDURE PutText(VAR s: ARRAY OF CHAR; VAR k: LONGINT; r: Ropes.Rope;
                  VAR ok: BOOLEAN);
  VAR i, n: LONGINT; ch: CHAR;
BEGIN
  n := Ropes.Length(r); i := 0;
  WHILE ok & (i < n) DO
    ch := Ropes.Fetch(r, i);
    IF (ch = "[") OR (ch = "]") THEN Put(s, k, "\", ok) END;
    Put(s, k, ch, ok); INC(i)
  END
END PutText;

(* Appends the inlines from i on to s[0 .. k-1] as markdown_strict
   writes them, with \* and \_ unescaped and new lines made spaces, as
   pandoc-include sees them; ok becomes FALSE for an inline an include
   line does not hold *)
PROCEDURE Render(i: A.Inline; VAR s: ARRAY OF CHAR; VAR k: LONGINT; VAR ok: BOOLEAN);
BEGIN
  WHILE ok & (i # NIL) DO
    IF i.kind = A.Str THEN PutText(s, k, i(A.StrInl).text, ok)
    ELSIF (i.kind = A.Space) OR (i.kind = A.SoftBreak) THEN Put(s, k, " ", ok)
    ELSIF i.kind = A.Code THEN
      IF Ropes.Contains(i(A.CodeInl).text, "`", 0) THEN ok := FALSE END;
      Put(s, k, "`", ok); PutRope(s, k, i(A.CodeInl).text, ok); Put(s, k, "`", ok)
    ELSIF i.kind = A.Emph THEN
      Put(s, k, "*", ok); Render(i(A.ContInl).content, s, k, ok); Put(s, k, "*", ok)
    ELSIF i.kind = A.Strong THEN
      PutString(s, k, "**", ok); Render(i(A.ContInl).content, s, k, ok);
      PutString(s, k, "**", ok)
    ELSIF i.kind = A.Quoted THEN
      IF i(A.QuotedInl).quote = A.SingleQuote THEN
        PutQuote(s, k, 98X, ok); Render(i(A.ContInl).content, s, k, ok);
        PutQuote(s, k, 99X, ok)
      ELSE
        PutQuote(s, k, 9CX, ok); Render(i(A.ContInl).content, s, k, ok);
        PutQuote(s, k, 9DX, ok)
      END
    ELSE ok := FALSE
    END;
    i := i.next
  END
END Render;

(* Whether the rope starts with !include or $include *)
PROCEDURE StartsInclude(r: Ropes.Rope): BOOLEAN;
  VAR s: ARRAY 9 OF CHAR;
BEGIN
  IF Ropes.Length(r) < 8 THEN RETURN FALSE END;
  Ropes.ToString(Ropes.Substring(r, 0, 8), s);
  RETURN (s = "!include") OR (s = "$include")
END StartsInclude;

PROCEDURE IsQuote(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch = "`") OR (ch = "'") OR (ch = 22X)
END IsQuote;

(* Reads the include line s[0 .. n-1] as pandoc-include's
   RE_INCLUDE_PATTERN does: the file name, the options between
   backquotes and whether it is !include-header. FALSE if it does not
   fit. *)
PROCEDURE ParseLine(VAR s: ARRAY OF CHAR; n: LONGINT; VAR name, args: ARRAY OF CHAR;
                    VAR header: BOOLEAN): BOOLEAN;
  VAR p, q: LONGINT; quoted: BOOLEAN;
BEGIN
  p := 8; header := FALSE; args[0] := 0X;
  IF (n - p >= 7) & (s[p] = "-") & (s[p + 1] = "h") & (s[p + 2] = "e") & (s[p + 3] = "a")
     & (s[p + 4] = "d") & (s[p + 5] = "e") & (s[p + 6] = "r") THEN
    header := TRUE; INC(p, 7)
  END;
  IF (p < n) & (s[p] = "`") THEN
    q := p + 1;
    WHILE (q < n) & (s[q] # "`") DO INC(q) END;
    IF (q = n) OR (q = p + 1) THEN RETURN FALSE END;
    Sub(s, p + 1, q, args); p := q + 1
  END;
  IF (p >= n) OR (s[p] # " ") THEN RETURN FALSE END;
  WHILE (p < n) & (s[p] = " ") DO INC(p) END;
  IF p = n THEN RETURN FALSE END;
  quoted := FALSE; q := p;
  WHILE q < n DO
    IF IsQuote(s[q]) THEN quoted := TRUE END;
    INC(q)
  END;
  IF ~quoted THEN Sub(s, p, n, name)
  ELSIF IsQuote(s[p]) & (n - p >= 3) & (s[n - 1] = s[p]) THEN Sub(s, p + 1, n - 1, name)
  ELSE RETURN FALSE
  END;
  RETURN TRUE
END ParseLine;

PROCEDURE IsWord(ch: CHAR): BOOLEAN;
BEGIN
  RETURN (ch >= "a") & (ch <= "z") OR (ch >= "A") & (ch <= "Z")
    OR (ch >= "0") & (ch <= "9") OR (ch = "_") OR (ORD(ch) >= 80H)
END IsWord;

(* The option key=raw; inc becomes incrementSection's value *)
PROCEDURE Option(VAR key, raw: ARRAY OF CHAR; VAR inc: LONGINT);
  VAR i, n, v: LONGINT; neg: BOOLEAN; m: ARRAY MsgLen OF CHAR;
BEGIN
  IF key = "incrementSection" THEN
    (* an integer, as Python's literal_eval reads it here *)
    i := 0; n := Length(raw); neg := FALSE; v := 0;
    IF (i < n) & ((raw[i] = "-") OR (raw[i] = "+")) THEN neg := raw[i] = "-"; INC(i) END;
    IF (i = n) OR (raw[i] < "0") OR (raw[i] > "9") THEN v := -1 END;
    WHILE (v >= 0) & (i < n) & (raw[i] >= "0") & (raw[i] <= "9") DO
      v := v * 10 + ORD(raw[i]) - ORD("0");
      IF v > MaxIncrement THEN v := -1 END;
      INC(i)
    END;
    WHILE (i < n) & (raw[i] = " ") DO INC(i) END;
    IF (v < 0) OR (i < n) THEN
      m := "Invalid config: "; Append(key, m); AppendChar("=", m);
      Fail(m, raw)
    END;
    IF neg THEN inc := -v ELSE inc := v END
  ELSIF (key = "startLine") OR (key = "endLine") OR (key = "snippetStart")
     OR (key = "snippetEnd") OR (key = "xslt") OR (key = "includeSnippetDelimiters")
     OR (key = "dedent") OR (key = "format") OR (key = "raw") THEN
    Fail("podoc does not support the !include option ", key)
  ELSE
    m := "[Warn] Invalid config key: "; Append(key, m);
    PdIO.Message(m)
  END
END Option;

(* Reads the options a as pandoc-include's parseConfig does: key=value,
   separated by commas, the value perhaps in quotes *)
PROCEDURE ParseOptions(VAR a: ARRAY OF CHAR; VAR inc: LONGINT);
  VAR i, j, v, e, n: LONGINT; found: BOOLEAN; key, raw: Path;
BEGIN
  i := 0; n := Length(a);
  WHILE i < n DO
    IF IsWord(a[i]) THEN
      j := i;
      WHILE (j < n) & IsWord(a[j]) DO INC(j) END;
      IF (j < n) & (a[j] = "=") THEN
        Sub(a, i, j, key); v := j + 1; found := FALSE;
        IF (v < n) & ((a[v] = 22X) OR (a[v] = "'")) THEN
          e := v + 1;
          WHILE (e < n) & ~found DO
            IF (a[e] = a[v]) & ((e + 1 = n) OR (a[e + 1] = ",")) THEN found := TRUE
            ELSE INC(e)
            END
          END;
          IF found THEN Sub(a, v, e + 1, raw); i := e + 2 END
        END;
        IF ~found THEN
          e := v;
          WHILE (e < n) & (a[e] # ",") DO INC(e) END;
          Sub(a, v, e, raw); i := e + 1
        END;
        Option(key, raw, inc)
      ELSE i := j
      END
    ELSE INC(i)
    END
  END
END ParseOptions;

(* Expanding *)

PROCEDURE^ ExpandDoc(d: A.Doc; VAR cur: ARRAY OF CHAR);

(* Adds the keys of from that to lacks to to *)
PROCEDURE MergeMeta(to, from: A.MetaMapV);
  VAR e, p: A.MetaEntry;
BEGIN
  e := from.entries;
  WHILE e # NIL DO
    p := to.entries;
    WHILE (p # NIL) & ~Ropes.Equal(p.key, e.key) DO p := p.next END;
    IF p = NIL THEN A.SetMeta(to, e.key, e.value) END;
    e := e.next
  END
END MergeMeta;

(* The blocks of the file fn, as pandoc-include finds it relative to
   w.cur, with their headers shifted by inc; its metadata goes to w's
   document *)
PROCEDURE IncludeFile(w: Walker; VAR fn: ARRAY OF CHAR; inc: LONGINT): A.Block;
  VAR path, dir, cur, ext: Path; f, p: File; d: A.Doc; text: PdIO.Text;
    len: LONGINT; h: A.Block; m: ARRAY MsgLen OF CHAR;
BEGIN
  Join(w.cur, fn, path); (* relative to the working directory *)
  IF NotMarkdown(fn, ext) THEN
    m := "podoc includes only markdown, not a "; Append(ext, m); Append(" file: ", m);
    Fail(m, fn)
  END;
  IF ~Readable(path) THEN Fail("Included file not found: ", fn) END;
  NEW(f);
  IF Platform.IdentifyByName(path, f.id) # 0 THEN Fail("Included file not found: ", fn) END;
  p := open;
  WHILE p # NIL DO
    IF Platform.SameFile(f.id, p.id) THEN
      Fail("Included file includes itself, directly or not: ", fn)
    END;
    p := p.next
  END;
  f.next := open; open := f;
  text := NIL; len := 0;
  PdSource.AddFile(text, len, path, TabStop);
  d := PdMarkdown.Read(text, len, TabStop);
  DirName(fn, dir); Join(w.cur, dir, path); NormPath(path, cur);
  ExpandDoc(d, cur);
  open := f.next;
  MergeMeta(w.doc.meta, d.meta);
  IF inc # 0 THEN
    h := d.blocks;
    WHILE h # NIL DO
      IF h.kind = A.Header THEN
        h(A.HeaderBlk).level := SHORT(h(A.HeaderBlk).level + inc)
      END;
      h := h.next
    END
  END;
  RETURN d.blocks
END IncludeFile;

(* What takes the place of the paragraph b in the document of w: the
   blocks of the files it includes, or b *)
PROCEDURE Include(w: Walker; b: A.Block): A.Block;
  VAR line: ARRAY LineLen OF CHAR; k, inc: LONGINT; ok, header: BOOLEAN;
    name, args, fn, dir: Path; files: PdGlob.List; first, last, h: A.Block;
    m: ARRAY MsgLen OF CHAR;
BEGIN
  IF (b.kind # A.Para) OR (b(A.InlinesBlk).inlines = NIL)
     OR (b(A.InlinesBlk).inlines.kind # A.Str)
     OR ~StartsInclude(b(A.InlinesBlk).inlines(A.StrInl).text) THEN
    RETURN b
  END;
  k := 0; ok := TRUE;
  Render(b(A.InlinesBlk).inlines, line, k, ok);
  line[k] := 0X;
  IF ~ok OR ~ParseLine(line, k, name, args, header) THEN
    Fail("Unable to extract info from include line ", line)
  END;
  IF header THEN Fail("podoc does not support !include-header: ", line) END;
  inc := 0;
  ParseOptions(args, inc);
  (* relative to w.cur, else to the working directory *)
  PdGlob.Glob(w.cur, name, files);
  IF files = NIL THEN
    COPY(Platform.CWD, dir); Append("/./", dir); Append(name, dir);
    NormPath(dir, fn);
    PdGlob.Glob("", fn, files)
  END;
  IF files = NIL THEN
    m := "Included file not found: "; Append(name, m);
    PdIO.Warn(m);
    RETURN b
  END;
  first := NIL; last := NIL;
  WHILE files # NIL DO
    COPY(files.name^, fn);
    h := IncludeFile(w, fn, inc);
    IF h # NIL THEN
      IF first = NIL THEN first := h ELSE last.next := h END;
      last := h;
      WHILE last.next # NIL DO last := last.next END
    END;
    files := files.next
  END;
  RETURN first
END Include;

(* Rewrites the path of an image *)
PROCEDURE (w: Walker) Inline*(i: A.Inline): A.Inline;
  VAR url, r: Path; l: A.LinkInl;
BEGIN
  IF i.kind = A.Image THEN
    l := i(A.LinkInl);
    IF Ropes.Length(l.url) < PathLen THEN
      Ropes.ToString(l.url, url);
      IF ~HasScheme(url) & (url[0] # "/") THEN
        PathJoin(w.cur, url, r);
        l.url := Ropes.FromString(r)
      END
    END
  END;
  RETURN i
END Inline;

(* Expands an include paragraph *)
PROCEDURE (w: Walker) Block*(b: A.Block): A.Block;
BEGIN
  RETURN Include(w, b)
END Block;

(* Expands the includes of d, whose directory is cur *)
PROCEDURE ExpandDoc(d: A.Doc; VAR cur: ARRAY OF CHAR);
  VAR w: Walker;
BEGIN
  NEW(w); w.doc := d; COPY(cur, w.cur);
  A.WalkMetaValue(w, d.meta);
  d.blocks := A.WalkBlocks(w, d.blocks)
END ExpandDoc;

(* Notes that the file name is an input, so that a file that includes
   it is an error. Standard input ("-") is not noted. *)
PROCEDURE AddInput*(name: ARRAY OF CHAR);
  VAR f: File;
BEGIN
  IF name # "-" THEN
    NEW(f);
    IF Platform.IdentifyByName(name, f.id) = 0 THEN f.next := open; open := f END
  END
END AddInput;

(* Runs the filter pandoc-include, named name on the command line, on
   the document d, read from the working directory *)
PROCEDURE Expand*(d: A.Doc; name: ARRAY OF CHAR);
  VAR cur: Path;
BEGIN
  COPY(name, filter);
  cur := ".";
  ExpandDoc(d, cur)
END Expand;

BEGIN
  open := NIL; filter := ""
END PdInclude.
