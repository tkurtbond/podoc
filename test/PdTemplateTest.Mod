MODULE PdTemplateTest;
(* Tests of PdTemplate: doctemplates' golden tests, in test/templates,
   and its unit tests. *)

IMPORT Out, Ropes, PdIO, PdYaml, L := PdLayout, T := PdTemplate;

VAR
  failures: INTEGER;

PROCEDURE Ok(name: ARRAY OF CHAR);
BEGIN
  Out.String("ok   - "); Out.String(name); Out.Ln
END Ok;

PROCEDURE Bad(name: ARRAY OF CHAR);
BEGIN
  Out.String("FAIL - "); Out.String(name); Out.Ln; INC(failures)
END Bad;

PROCEDURE Append(VAR s: ARRAY OF CHAR; t: ARRAY OF CHAR);
  VAR i, k: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO INC(i) END;
  k := 0; WHILE t[k] # 0X DO s[i] := t[k]; INC(i); INC(k) END;
  s[i] := 0X
END Append;

(* A JSON node as a template value *)
PROCEDURE ToValue(nd: PdYaml.Node): T.Value;
  VAR v: T.Value; p: PdYaml.Pair; b: BOOLEAN; s: PdYaml.Text; n: LONGINT;
BEGIN
  IF nd = NIL THEN RETURN NIL END;
  CASE nd.kind OF
    PdYaml.Scalar:
      IF nd.style # PdYaml.Plain THEN
        RETURN T.NewSimple(L.Chars(nd.text^, 0, nd.len))
      END;
      CASE PdYaml.Resolve(nd, b) OF
        PdYaml.Null: RETURN NIL
      | PdYaml.Bool: RETURN T.NewBool(b)
      | PdYaml.Number: PdYaml.NumberText(nd, s, n); RETURN T.NewSimple(L.Chars(s^, 0, n))
      | PdYaml.String: RETURN T.NewSimple(L.Chars(nd.text^, 0, nd.len))
      END
  | PdYaml.Sequence:
      v := T.NewList(); p := nd.items;
      WHILE p # NIL DO T.Add(v, ToValue(p.value)); p := p.next END;
      RETURN v
  | PdYaml.Mapping:
      v := T.NewMap(); p := nd.items;
      WHILE p # NIL DO
        T.PutRope(v, Ropes.FromSubchars(p.key.text^, 0, p.key.len), ToValue(p.value));
        p := p.next
      END;
      RETURN v
  END;
  RETURN NIL
END ToValue;

(* The index of "\n.\n" in t[from .. len-1], or -1 *)
PROCEDURE FindDot(t: PdIO.Text; from, len: LONGINT): LONGINT;
BEGIN
  WHILE from + 2 < len DO
    IF (t[from] = 0AX) & (t[from + 1] = ".") & (t[from + 2] = 0AX) THEN RETURN from END;
    INC(from)
  END;
  RETURN -1
END FindDot;

(* A copy of t[from .. to-1] with a new line after it *)
PROCEDURE Part(t: PdIO.Text; from, to: LONGINT; VAR p: PdIO.Text; VAR n: LONGINT);
  VAR i: LONGINT;
BEGIN
  n := to - from + 1;
  NEW(p, n + 1);
  FOR i := 0 TO n - 2 DO p[i] := t[from + i] END;
  p[n - 1] := 0AX; p[n] := 0X
END Part;

PROCEDURE ShowRope(r: Ropes.Rope);
  VAR s: POINTER TO ARRAY OF CHAR; n: LONGINT;
BEGIN
  n := Ropes.Length(r); NEW(s, n + 1);
  IF n > 0 THEN Ropes.Blit(r, 0, s^, 0, n) END;
  s[n] := 0X;
  Out.String(s^)
END ShowRope;

(* The golden test test/templates/name.test *)
PROCEDURE Golden(name: ARRAY OF CHAR);
  VAR path, tpath: ARRAY 256 OF CHAR; t, j, tm: PdIO.Text; len, a, b, jn, tn: LONGINT;
    doc: PdYaml.Node; ctx: T.Value; tmpl: T.Template; got, want: Ropes.Rope;
BEGIN
  path := "../../../test/templates/"; tpath := path;
  Append(path, name); Append(path, ".test");
  Append(tpath, name); Append(tpath, ".txt");
  PdIO.ReadFile(path, t, len);
  a := FindDot(t, 0, len); b := FindDot(t, a + 3, len);
  IF (a < 0) OR (b < 0) THEN Bad(name); RETURN END;
  Part(t, 0, a, j, jn); Part(t, a + 3, b, tm, tn);
  want := Ropes.FromSubchars(t^, b + 3, len - b - 3);
  IF ~PdYaml.Parse(j^, jn, doc) THEN
    Bad(name); Out.String(PdYaml.error); Out.Ln; RETURN
  END;
  ctx := ToValue(doc);
  IF ~T.Compile(tpath, tm, tn, tmpl) THEN
    Bad(name); Out.String(T.error); Out.Ln; RETURN
  END;
  got := L.Render(T.Render(tmpl, ctx), 0);
  IF Ropes.Equal(got, want) THEN Ok(name)
  ELSE
    Bad(name);
    Out.String("-- got:"); Out.Ln; ShowRope(got);
    Out.String("-- want:"); Out.Ln; ShowRope(want)
  END
END Golden;

(* The text of s, "$" for a new line *)
PROCEDURE Text(s: ARRAY OF CHAR; VAR t: PdIO.Text; VAR n: LONGINT);
  VAR i: LONGINT;
BEGIN
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  NEW(t, n + 1);
  FOR i := 0 TO n - 1 DO
    IF s[i] = "|" THEN t[i] := 0AX ELSE t[i] := s[i] END
  END;
  t[n] := 0X
END Text;

(* Compiles s ("|" for a new line), which should fail *)
PROCEDURE Fails(name, path, s: ARRAY OF CHAR);
  VAR t: PdIO.Text; n: LONGINT; tmpl: T.Template;
BEGIN
  Text(s, t, n);
  IF T.Compile(path, t, n, tmpl) THEN Bad(name)
  ELSE Ok(name); Out.String("  "); Out.String(T.error); Out.Ln
  END
END Fails;

(* Compiles s, renders it with ctx at width w and compares with want *)
PROCEDURE Renders(name, s: ARRAY OF CHAR; ctx: T.Value; w: LONGINT; want: ARRAY OF CHAR);
  VAR t, wt: PdIO.Text; n, wn: LONGINT; tmpl: T.Template; got: Ropes.Rope;
BEGIN
  Text(s, t, n); Text(want, wt, wn);
  IF ~T.Compile("foo", t, n, tmpl) THEN
    Bad(name); Out.String(T.error); Out.Ln; RETURN
  END;
  got := L.Render(T.Render(tmpl, ctx), w);
  IF Ropes.Equal(got, Ropes.FromSubchars(wt^, 0, wn)) THEN Ok(name)
  ELSE Bad(name); Out.String("-- got:"); Out.Ln; ShowRope(got); Out.Ln
  END
END Renders;

PROCEDURE Words(s: ARRAY OF CHAR): L.Doc;
  VAR d: L.Doc; i, j: LONGINT;
BEGIN
  d := NIL; i := 0;
  WHILE s[i] # 0X DO
    j := i; WHILE (s[j] # 0X) & (s[j] # " ") DO INC(j) END;
    IF d = NIL THEN d := L.Chars(s, i, j - i)
    ELSE d := L.Hsep(d, L.Chars(s, i, j - i))
    END;
    i := j; IF s[i] = " " THEN INC(i) END
  END;
  RETURN d
END Words;

PROCEDURE Units;
  VAR ctx: T.Value;
BEGIN
  Fails("compile failure", "", "$if(x$and$endif$");
  Fails("a keyword as a variable", "foobar.txt", "$sep$");
  Fails("an unknown pipe", "foobar.txt", "$foo/nope$");
  Fails("a block pipe", "foobar.txt", "$foo/left 5 2$");
  Fails("an error in a partial", "../../../test/templates/foobar.txt", "$bad()$");
  Fails("a missing partial", "../../../test/templates/foobar.txt", "$nosuch()$");
  Renders("a comment with no newline", "$-- hi", NIL, 0, "");
  ctx := T.NewMap(); T.Put(ctx, "foo", T.NewString("42"));
  Renders("reflow", "not breakable and$~$ this is breakable|ok? $foo$$~$",
    ctx, 10, "not breakable and|this is|breakable|ok? 42");
  ctx := T.NewMap();
  T.Put(ctx, "foo", T.NewSimple(Words("hello this is a test of the wrapping")));
  Renders("the nowrap pipe", "$foo/nowrap$|$foo$", ctx, 10,
    "hello this is a test of the wrapping|hello this|is a test|of the|wrapping");
  ctx := T.NewMap();
  T.Put(ctx, "one", T.NewString("1")); T.Put(ctx, "twentysix", T.NewString("26"));
  T.Put(ctx, "twentyseven", T.NewString("27")); T.Put(ctx, "zero", T.NewString("0"));
  Renders("the alpha pipe", "$one/alpha$ $twentysix/alpha$ $twentyseven/alpha$ $zero/alpha$",
    ctx, 0, "a z a 0");
  ctx := T.NewMap();
  T.Put(ctx, "big", T.NewString("1234567890123456789"));
  T.Put(ctx, "y", T.NewString("3999")); T.Put(ctx, "z", T.NewString("4000"));
  Renders("alpha and roman on big numbers", "$big/alpha$ $big/roman$ $y/roman$ $z/roman$",
    ctx, 0, "q 1234567890123456789 mmmcmxcix 4000");
  ctx := T.NewMap(); T.Put(ctx, "s", T.NewString("héllo wörld"));
  Renders("uppercase, length and reverse in UTF-8", "$s/uppercase$ $s/length$ $s/reverse$",
    ctx, 0, "HÉLLO WÖRLD 11 dlröw olléh")
END Units;

BEGIN
  failures := 0;
  Golden("basic"); Golden("basic-with-braces"); Golden("basic-with-it");
  Golden("boolean"); Golden("comments"); Golden("conditionals");
  Golden("elseif"); Golden("empty"); Golden("final-newline");
  Golden("forloop"); Golden("indent"); Golden("loop-in-object");
  Golden("loop-in-partial"); Golden("nested-loop"); Golden("nest");
  Golden("numbers"); Golden("partials"); Golden("pipe-and-partial");
  Golden("pipes"); Golden("space-in-loop"); Golden("values");
  Units;
  IF failures = 0 THEN Out.String("all passed") ELSE Out.Int(failures, 0); Out.String(" failed") END;
  Out.Ln
END PdTemplateTest.
