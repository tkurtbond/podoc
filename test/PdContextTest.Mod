MODULE PdContextTest;
(* Tests of PdContext: variables, metadata in the context, and finding
   templates. Metadata is written by a plain writer: a Str is its text,
   a Space " ", a SoftBreak "|", and blocks are their inlines, each
   followed by "/". *)

IMPORT Out, Ropes, PdIO, A := PdAst, L := PdLayout, T := PdTemplate,
  C := PdContext;

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

PROCEDURE ShowRope(r: Ropes.Rope);
  VAR s: POINTER TO ARRAY OF CHAR; n: LONGINT;
BEGIN
  n := Ropes.Length(r); NEW(s, n + 1);
  IF n > 0 THEN Ropes.Blit(r, 0, s^, 0, n) END;
  s[n] := 0X;
  Out.String(s^)
END ShowRope;

(* The plain writer *)

PROCEDURE Inlines(i: A.Inline): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE i # NIL DO
    IF i IS A.StrInl THEN d := L.Cat(d, L.Literal(i(A.StrInl).text))
    ELSIF i.kind = A.Space THEN d := L.Cat(d, L.Text(" "))
    ELSIF i.kind = A.SoftBreak THEN d := L.Cat(d, L.Text("|"))
    END;
    i := i.next
  END;
  RETURN d
END Inlines;

PROCEDURE Blocks(b: A.Block): L.Doc;
  VAR d: L.Doc;
BEGIN
  d := NIL;
  WHILE b # NIL DO
    IF b IS A.InlinesBlk THEN d := L.Cat(d, Inlines(b(A.InlinesBlk).inlines)) END;
    d := L.Cat(d, L.Text("/"));
    b := b.next
  END;
  RETURN d
END Blocks;

(* Renders the template s ("|" for a new line, compiled as foo.txt)
   with ctx and compares with want *)
PROCEDURE Renders(name, s: ARRAY OF CHAR; ctx: T.Value; want: ARRAY OF CHAR);
  VAR t: PdIO.Text; n, i: LONGINT; tmpl: T.Template; got: Ropes.Rope;
BEGIN
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  NEW(t, n + 1);
  FOR i := 0 TO n - 1 DO
    IF s[i] = "|" THEN t[i] := 0AX ELSE t[i] := s[i] END
  END;
  t[n] := 0X;
  IF ~T.Compile("foo.txt", t, n, tmpl) THEN
    Bad(name); Out.String(T.error); Out.Ln; RETURN
  END;
  got := L.Render(T.Render(tmpl, ctx), 0);
  IF Ropes.Equal(got, Ropes.FromString(want)) THEN Ok(name)
  ELSE Bad(name); Out.String("-- got:"); Out.Ln; ShowRope(got); Out.Ln
  END
END Renders;

(* Renders tmpl with ctx and compares with want, "|" in it for a new
   line *)
PROCEDURE RendersT(name: ARRAY OF CHAR; tmpl: T.Template; ctx: T.Value; want: ARRAY OF CHAR);
  VAR got: Ropes.Rope; i: LONGINT;
BEGIN
  i := 0;
  WHILE want[i] # 0X DO IF want[i] = "|" THEN want[i] := 0AX END; INC(i) END;
  got := L.Render(T.Render(tmpl, ctx), 0);
  IF Ropes.Equal(got, Ropes.FromString(want)) THEN Ok(name)
  ELSE Bad(name); Out.String("-- got:"); Out.Ln; ShowRope(got); Out.Ln
  END
END RendersT;

(* Whether the text of r has s at from *)
PROCEDURE HasAt(r: Ropes.Rope; from: LONGINT; s: ARRAY OF CHAR): BOOLEAN;
  VAR n: LONGINT;
BEGIN
  n := 0; WHILE s[n] # 0X DO INC(n) END;
  RETURN (from + n <= Ropes.Length(r))
    & Ropes.Equal(Ropes.Substring(r, from, n), Ropes.FromString(s))
END HasAt;

(* Whether r contains s *)
PROCEDURE Contains(r: Ropes.Rope; s: ARRAY OF CHAR): BOOLEAN;
  VAR i: LONGINT;
BEGIN
  FOR i := 0 TO Ropes.Length(r) - 1 DO
    IF HasAt(r, i, s) THEN RETURN TRUE END
  END;
  RETURN FALSE
END Contains;

PROCEDURE Meta(): A.MetaMapV;
  VAR m, sub: A.MetaMapV; l: A.MetaListV; il: A.Inlines; b: A.Blocks;
    str: ARRAY 16 OF CHAR;
BEGIN
  m := A.NewMetaMap();
  str := " a  b| c"; str[5] := 0AX;
  A.SetMeta(m, A.S("s"), A.NewMetaString(A.S(str)));
  A.SetMeta(m, A.S("t"), A.NewMetaBool(TRUE));
  A.SetMeta(m, A.S("f"), A.NewMetaBool(FALSE));
  A.InitInlines(il);
  A.AddInline(il, A.NewStr(A.S("in"))); A.AddInline(il, A.NewSimple(A.Space));
  A.AddInline(il, A.NewStr(A.S("lines")));
  A.SetMeta(m, A.S("i"), A.NewMetaInlines(il.first));
  A.InitBlocks(b);
  A.AddBlock(b, A.NewInlinesBlock(A.Para, A.NewStr(A.S("one"))));
  A.AddBlock(b, A.NewInlinesBlock(A.Plain, A.NewStr(A.S("two"))));
  A.SetMeta(m, A.S("b"), A.NewMetaBlocks(b.first));
  l := A.NewMetaList();
  A.AddMetaItem(l, A.NewMetaString(A.S("x"))); A.AddMetaItem(l, A.NewMetaString(A.S("y")));
  A.SetMeta(m, A.S("l"), l);
  sub := A.NewMetaMap();
  A.SetMeta(sub, A.S("k"), A.NewMetaString(A.S("v")));
  A.SetMeta(m, A.S("m"), sub);
  A.SetMeta(m, A.S("over"), A.NewMetaString(A.S("meta")));
  RETURN m
END Meta;

PROCEDURE Run;
  VAR ctx: T.Value; tmpl: T.Template; got: Ropes.Rope;
BEGIN
  ctx := C.FromMeta(Meta(), Blocks, Inlines);
  Renders("a metadata string, through the inline writer", "[$s$]", ctx, "[ a b|c]");
  Renders("booleans", "$if(t)$T$endif$$if(f)$F$else$notF$endif$", ctx, "TnotF");
  Renders("inlines and blocks", "$i$ $b$", ctx, "in lines one/two/");
  Renders("a list and a map", "$for(l)$<$l$>$endfor$ $m.k$", ctx, "<x><y> v");

  C.SetVariable("x=1"); C.SetVariable("x:2"); C.SetVariable("b");
  C.SetVariable("over=var"); C.SetVariable("e=");
  C.SetVariable("header-includes=V"); C.AddListString("header-includes", "H");
  C.SetVariableIfAbsent("x", "no"); C.SetVariableIfAbsent("outputfile", "-");
  ctx := C.Build(Meta(), Blocks, Inlines);
  Renders("-V given twice", "$x$ $for(x)$<$x$>$endfor$", ctx, "12 <1><2>");
  Renders("-V with no value", "$b$", ctx, "true");
  Renders("-V with an empty value", "[$e$]$if(e)$yes$else$no$endif$", ctx, "[]no");
  Renders("variables override metadata", "$over$ $s$", ctx, "var  a b|c");
  Renders("list variables", "$for(header-includes)$<$header-includes$>$endfor$",
    ctx, "<V><H>");
  Renders("variables set if absent", "$outputfile$", ctx, "-");
  C.DefField(ctx, "over", T.NewString("def")); C.DefField(ctx, "new", T.NewString("def"));
  Renders("defField", "$over$ $new$", ctx, "var def");
  C.ResetField(ctx, "over", T.NewString("reset"));
  Renders("resetField", "$over$", ctx, "reset");

  ctx := T.NewMap(); T.Put(ctx, "x", T.NewString("X")); T.Put(ctx, "body", T.NewString("B"));
  C.SetDataDir("../../../test/templates/data");
  C.Get("../../../test/templates/ctx.html", "html", tmpl);
  RendersT("a template file, its partial in the data directory", tmpl, ctx, "[X](part X)|");
  C.Get("../../../test/templates/ctx", "html", tmpl);
  RendersT("a template with the format's extension added", tmpl, ctx, "[X](part X)|");
  C.Get("somewhere/indata.html", "html", tmpl);
  RendersT("a template in the data directory", tmpl, ctx, "in data: X|");
  C.GetDefault("ms", tmpl);
  RendersT("a default template in the data directory", tmpl, ctx, "my ms: B|");
  C.GetDefault("html5", tmpl);
  T.Put(ctx, "pagetitle", T.NewString("PT"));
  got := L.Render(T.Render(tmpl, ctx), 0);
  IF HasAt(got, 0, "<!DOCTYPE html>") & Contains(got, "<title>PT</title>")
     & Contains(got, "<style>") & Contains(got, "<body>") THEN
    Ok("the built-in html5 template and its partial")
  ELSE Bad("the built-in html5 template and its partial"); ShowRope(got)
  END;
  C.SetDataDir("");
  C.Get("default.markdown", "markdown", tmpl);
  RendersT("a built-in template by name", tmpl, ctx, "B|")
END Run;

BEGIN
  failures := 0;
  Run;
  IF failures = 0 THEN Out.String("all passed") ELSE Out.Int(failures, 0); Out.String(" failed") END;
  Out.Ln
END PdContextTest.
