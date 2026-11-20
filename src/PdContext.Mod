MODULE PdContext;
(* PdContext: a template's context, as pandoc builds it
   (Text.Pandoc.Writers.Shared, Text.Pandoc.App.OutputSettings), and
   finding and compiling the template (Text.Pandoc.Templates).

   The variables (-V, and those podoc sets itself) override the
   metadata, key by key. Metadata goes into the context through the
   writer, as the procedures given to FromMeta write it.

   Templates and partials are looked for as pandoc looks for them: a
   file, then templates/NAME in the user data directory, then podoc's
   built-in templates (PdDefaults). *)

IMPORT Ropes, Platform, PdIO, A := PdAst, L := PdLayout, T := PdTemplate,
  PdDefaults;

CONST
  PathLen = 4096;

TYPE
  (* A writer of blocks and of inlines, for metadata *)
  BlockWriter* = PROCEDURE (b: A.Block): L.Doc;
  InlineWriter* = PROCEDURE (i: A.Inline): L.Doc;

VAR
  variables-: T.Value; (* a map: -V, and what podoc sets *)
  dataDir: ARRAY PathLen OF CHAR; (* "" if there is none *)

(* Variables *)

(* -V KEY[=VALUE] or KEY[:VALUE]: sets the variable KEY to the text
   VALUE, "true" by default. A key given again becomes a list of its
   values. *)
PROCEDURE SetVariable*(arg: ARRAY OF CHAR);
  VAR i, j: LONGINT; key, val: POINTER TO ARRAY OF CHAR; v, old, l: T.Value;
BEGIN
  NEW(key, LEN(arg) + 1); NEW(val, LEN(arg) + 5);
  i := 0;
  WHILE (i < LEN(arg)) & (arg[i] # 0X) & (arg[i] # ":") & (arg[i] # "=") DO
    key[i] := arg[i]; INC(i)
  END;
  key[i] := 0X;
  IF (i >= LEN(arg)) OR (arg[i] = 0X) THEN COPY("true", val^)
  ELSE
    INC(i); j := 0;
    WHILE (i < LEN(arg)) & (arg[i] # 0X) DO val[j] := arg[i]; INC(i); INC(j) END;
    val[j] := 0X
  END;
  v := T.NewString(val^);
  old := T.Get(variables, key^);
  IF old = NIL THEN T.Put(variables, key^, v)
  ELSIF old.kind = T.ListV THEN T.Add(old, v)
  ELSE
    l := T.NewList(); T.Add(l, old); T.Add(l, v); T.Put(variables, key^, l)
  END
END SetVariable;

(* Sets the variable key to the text val, unless it is set
   (setVariableM) *)
PROCEDURE SetVariableIfAbsent*(key, val: ARRAY OF CHAR);
BEGIN
  IF ~T.Has(variables, key) THEN T.Put(variables, key, T.NewString(val)) END
END SetVariableIfAbsent;

(* Adds v to the list variable key (setListVariableM): a variable that
   is not a list becomes the first item of one. *)
PROCEDURE AddListVariable*(key: ARRAY OF CHAR; v: T.Value);
  VAR old, l: T.Value;
BEGIN
  old := T.Get(variables, key);
  IF (old # NIL) & (old.kind = T.ListV) THEN T.Add(old, v)
  ELSE
    l := T.NewList();
    IF old # NIL THEN T.Add(l, old) END;
    T.Add(l, v); T.Put(variables, key, l)
  END
END AddListVariable;

(* Adds the text s to the list variable key *)
PROCEDURE AddListString*(key, s: ARRAY OF CHAR);
BEGIN
  AddListVariable(key, T.NewString(s))
END AddListString;

(* Adds the contents of the file name to the list variable key, as -H,
   -B and -A do. A file that cannot be found or read ends the
   program. *)
PROCEDURE AddFileContents*(key, name: ARRAY OF CHAR);
  VAR t: PdIO.Text; n: LONGINT;
BEGIN
  IF ~PdIO.Exists(name) THEN
    PdIO.Message3("File '", name, "' not found in resource path");
    PdIO.Exit(PdIO.ResourceNotFound)
  END;
  PdIO.ReadFile(name, t, n);
  AddListVariable(key, T.NewSimple(L.Chars(t^, 0, n)))
END AddFileContents;

(* Metadata *)

(* Builder.text s: words, with Space between them, or SoftBreak where
   the space between them has a new line *)
PROCEDURE TextInlines(s: A.Rope): A.Inline;
  VAR l: A.Inlines; t: POINTER TO ARRAY OF CHAR; n, i, j: LONGINT; nl: BOOLEAN;
BEGIN
  n := Ropes.Length(s); NEW(t, n + 1);
  IF n > 0 THEN Ropes.Blit(s, 0, t^, 0, n) END;
  t[n] := 0X;
  A.InitInlines(l); i := 0;
  WHILE i < n DO
    j := i;
    IF (t[i] = " ") OR (t[i] = 9X) OR (t[i] = 0AX) OR (t[i] = 0DX) THEN
      nl := FALSE;
      WHILE (j < n) & ((t[j] = " ") OR (t[j] = 9X) OR (t[j] = 0AX) OR (t[j] = 0DX)) DO
        IF t[j] = 0AX THEN nl := TRUE END;
        INC(j)
      END;
      IF nl THEN A.AddInline(l, A.NewSimple(A.SoftBreak))
      ELSE A.AddInline(l, A.NewSimple(A.Space))
      END
    ELSE
      WHILE (j < n) & ~((t[j] = " ") OR (t[j] = 9X) OR (t[j] = 0AX) OR (t[j] = 0DX)) DO
        INC(j)
      END;
      A.AddInline(l, A.NewStr(Ropes.Substring(s, i, j - i)))
    END;
    i := j
  END;
  RETURN l.first
END TextInlines;

(* metaValueToVal *)
PROCEDURE MetaValue(v: A.MetaValue; bw: BlockWriter; iw: InlineWriter): T.Value;
  VAR r: T.Value; e: A.MetaEntry; it: A.MetaItem;
BEGIN
  IF v = NIL THEN RETURN NIL END;
  WITH v: A.MetaMapV DO
    r := T.NewMap(); e := v.entries;
    WHILE e # NIL DO T.PutRope(r, e.key, MetaValue(e.value, bw, iw)); e := e.next END
  | v: A.MetaListV DO
    r := T.NewList(); it := v.items;
    WHILE it # NIL DO T.Add(r, MetaValue(it.value, bw, iw)); it := it.next END
  | v: A.MetaBoolV DO r := T.NewBool(v.b)
  | v: A.MetaStringV DO r := T.NewSimple(iw(TextInlines(v.s)))
  | v: A.MetaInlinesV DO r := T.NewSimple(iw(v.inlines))
  | v: A.MetaBlocksV DO r := T.NewSimple(bw(v.blocks))
  END;
  RETURN r
END MetaValue;

(* The metadata meta as a context, a map, written with bw and iw *)
PROCEDURE FromMeta*(meta: A.MetaMapV; bw: BlockWriter; iw: InlineWriter): T.Value;
BEGIN
  IF meta = NIL THEN RETURN T.NewMap() END;
  RETURN MetaValue(meta, bw, iw)
END FromMeta;

(* The context for a document with the metadata meta: the variables,
   then the metadata (addVariablesToContext, without meta-json) *)
PROCEDURE Build*(meta: A.MetaMapV; bw: BlockWriter; iw: InlineWriter): T.Value;
  VAR ctx: T.Value; e: T.Entry;
BEGIN
  ctx := FromMeta(meta, bw, iw);
  e := variables.items;
  WHILE e # NIL DO T.PutRope(ctx, e.key, e.value); e := e.next END;
  RETURN ctx
END Build;

(* Sets key in the context ctx to v, unless it is set (defField) *)
PROCEDURE DefField*(ctx: T.Value; key: ARRAY OF CHAR; v: T.Value);
BEGIN
  IF ~T.Has(ctx, key) THEN T.Put(ctx, key, v) END
END DefField;

(* Sets key in the context ctx to v, replacing what was there
   (resetField) *)
PROCEDURE ResetField*(ctx: T.Value; key: ARRAY OF CHAR; v: T.Value);
BEGIN
  T.Put(ctx, key, v)
END ResetField;

(* Finding templates *)

PROCEDURE Length(s: ARRAY OF CHAR): LONGINT;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
  RETURN n
END Length;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
  VAR i, k: LONGINT;
BEGIN
  i := Length(s); k := 0;
  WHILE (k < LEN(t)) & (t[k] # 0X) & (i < LEN(s) - 1) DO s[i] := t[k]; INC(i); INC(k) END;
  s[i] := 0X
END Append;

(* takeFileName: what follows the last "/" of path *)
PROCEDURE BaseName(path: ARRAY OF CHAR; VAR name: ARRAY OF CHAR);
  VAR i, s, k: LONGINT;
BEGIN
  s := 0; i := 0;
  WHILE (i < LEN(path)) & (path[i] # 0X) DO
    IF path[i] = "/" THEN s := i + 1 END;
    INC(i)
  END;
  k := 0;
  WHILE (s < i) & (k < LEN(name) - 1) DO name[k] := path[s]; INC(k); INC(s) END;
  name[k] := 0X
END BaseName;

(* Whether the file name of path has an extension *)
PROCEDURE HasExtension(path: ARRAY OF CHAR): BOOLEAN;
  VAR name: ARRAY PathLen OF CHAR; i: LONGINT;
BEGIN
  BaseName(path, name);
  i := Length(name) - 1;
  WHILE (i > 0) & (name[i] # ".") DO DEC(i) END;
  RETURN (i > 0) & (name[i + 1] # 0X)
END HasExtension;

(* Sets the user data directory; "" for none *)
PROCEDURE SetDataDir*(dir: ARRAY OF CHAR);
BEGIN
  COPY(dir, dataDir)
END SetDataDir;

(* pandoc's defaultUserDataDir: $XDG_DATA_HOME/pandoc, by default
   ~/.local/share/pandoc, unless it does not exist and ~/.pandoc
   does *)
PROCEDURE DefaultDataDir;
  VAR home, xdg, old: ARRAY PathLen OF CHAR;
BEGIN
  Platform.GetEnv("HOME", home);
  IF ~Platform.getEnv("XDG_DATA_HOME", xdg) OR (xdg = "") THEN
    IF home = "" THEN dataDir := ""; RETURN END;
    COPY(home, xdg); Append(xdg, "/.local/share")
  END;
  COPY(xdg, dataDir); Append(dataDir, "/pandoc");
  IF ~PdIO.Exists(dataDir) & (home # "") THEN
    COPY(home, old); Append(old, "/.pandoc");
    IF PdIO.Exists(old) THEN COPY(old, dataDir) END
  END
END DefaultDataDir;

(* readDataFile "templates/" + name: from the user data directory, or
   built in *)
PROCEDURE ReadDataTemplate(name: ARRAY OF CHAR; VAR t: PdIO.Text; VAR len: LONGINT): BOOLEAN;
  VAR path: ARRAY PathLen OF CHAR;
BEGIN
  IF dataDir # "" THEN
    COPY(dataDir, path); Append(path, "/templates/"); Append(path, name);
    IF PdIO.Exists(path) THEN PdIO.ReadFile(path, t, len); RETURN TRUE END
  END;
  RETURN PdDefaults.Get(name, t, len)
END ReadDataTemplate;

(* getTemplate: the file path, or else the data file templates/ and its
   file name *)
PROCEDURE ReadTemplateFile(path: ARRAY OF CHAR; VAR t: PdIO.Text; VAR len: LONGINT): BOOLEAN;
  VAR name: ARRAY PathLen OF CHAR;
BEGIN
  IF PdIO.Exists(path) THEN PdIO.ReadFile(path, t, len); RETURN TRUE END;
  BaseName(path, name);
  RETURN ReadDataTemplate(name, t, len)
END ReadTemplateFile;

(* The partials of a default template (WithDefaultPartials) *)
PROCEDURE ReadDefaultPartial(path: ARRAY OF CHAR; VAR t: PdIO.Text; VAR len: LONGINT): BOOLEAN;
  VAR name: ARRAY PathLen OF CHAR;
BEGIN
  BaseName(path, name);
  RETURN ReadDataTemplate(name, t, len)
END ReadDefaultPartial;

(* Compiles text as the template path into t; a template that does not
   compile ends the program *)
PROCEDURE CompileOrFail(path: ARRAY OF CHAR; text: PdIO.Text; len: LONGINT;
                        VAR t: T.Template);
BEGIN
  IF ~T.Compile(path, text, len, t) THEN
    PdIO.Message3("Error compiling template '", T.error, "'");
    PdIO.Exit(PdIO.TemplateError)
  END
END CompileOrFail;

(* The template given by --template path, for the output format
   format: the file path, or the data file templates/NAME, NAME being
   path's file name, and if neither is found and path has no extension,
   the same with ".format" added. A template that cannot be found or
   compiled ends the program. *)
PROCEDURE Get*(path, format: ARRAY OF CHAR; VAR t: T.Template);
  VAR p, name, msg: ARRAY PathLen OF CHAR; text: PdIO.Text; len: LONGINT; found: BOOLEAN;
BEGIN
  COPY(path, p);
  found := ReadTemplateFile(p, text, len);
  IF ~found & ~HasExtension(path) THEN
    Append(p, "."); Append(p, format);
    found := ReadTemplateFile(p, text, len)
  END;
  IF ~found THEN
    BaseName(p, name);
    msg := "templates/"; Append(msg, name);
    PdIO.Message3("Could not find data file '", msg, "'");
    PdIO.Exit(PdIO.CouldNotFindDataFile)
  END;
  T.readPartial := ReadTemplateFile;
  CompileOrFail(p, text, len, t)
END Get;

(* The default template for the output format format (html5, ms,
   context, markdown), from the user data directory or built in. One
   that cannot be found or compiled ends the program. *)
PROCEDURE GetDefault*(format: ARRAY OF CHAR; VAR t: T.Template);
  VAR name, path: ARRAY PathLen OF CHAR; text: PdIO.Text; len: LONGINT;
BEGIN
  name := "default."; Append(name, format);
  path := "templates/"; Append(path, name);
  IF ~ReadDataTemplate(name, text, len) THEN
    PdIO.Message3("Could not find data file '", path, "'");
    PdIO.Exit(PdIO.CouldNotFindDataFile)
  END;
  T.readPartial := ReadDefaultPartial;
  CompileOrFail(path, text, len, t)
END GetDefault;

BEGIN
  variables := T.NewMap();
  DefaultDataDir
END PdContext.
