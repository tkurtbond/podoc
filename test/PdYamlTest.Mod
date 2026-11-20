MODULE PdYamlTest;
(* Tests of PdYaml: the YAML subset, the values of scalars and how
   numbers are shown. *)

IMPORT Out, Y := PdYaml;

VAR
  failures: INTEGER;
  out: ARRAY 1024 OF CHAR;
  olen: LONGINT;

(* Copies s into t, with "$" standing for a new line and "~" for a tab;
   n is its length *)
PROCEDURE Decode(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR; VAR n: LONGINT);
BEGIN
  n := 0;
  WHILE s[n] # 0X DO
    IF s[n] = "$" THEN t[n] := 0AX
    ELSIF s[n] = "~" THEN t[n] := 09X
    ELSE t[n] := s[n]
    END;
    INC(n)
  END;
  t[n] := 0X
END Decode;

PROCEDURE Put(ch: CHAR);
BEGIN
  IF olen < LEN(out) - 1 THEN out[olen] := ch; INC(olen); out[olen] := 0X END
END Put;

PROCEDURE PutS(s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0; WHILE s[i] # 0X DO Put(s[i]); INC(i) END
END PutS;

PROCEDURE PutInt(x: LONGINT);
  VAR d: ARRAY 24 OF CHAR; k: INTEGER;
BEGIN
  k := 0;
  REPEAT d[k] := CHR(ORD("0") + x MOD 10); x := x DIV 10; INC(k) UNTIL x = 0;
  WHILE k > 0 DO DEC(k); Put(d[k]) END
END PutInt;

(* A scalar: its style's letter, then its text in angle brackets, with "$" for a
   new line *)
PROCEDURE PutScalar(nd: Y.Node);
  VAR i: LONGINT; ch: CHAR;
BEGIN
  CASE nd.style OF
    Y.Plain: Put("P")
  | Y.SingleQuoted: Put("S")
  | Y.DoubleQuoted: Put("D")
  | Y.Literal: Put("L")
  | Y.Folded: Put("F")
  END;
  Put("<");
  FOR i := 0 TO nd.len - 1 DO
    ch := nd.text[i];
    IF ch = 0AX THEN Put("$") ELSIF ch = 09X THEN Put("~") ELSE Put(ch) END
  END;
  Put(">")
END PutScalar;

PROCEDURE Dump(nd: Y.Node);
  VAR p: Y.Pair;
BEGIN
  IF nd = NIL THEN PutS("-")
  ELSIF nd.kind = Y.Scalar THEN PutScalar(nd)
  ELSE
    IF nd.kind = Y.Sequence THEN Put("[") ELSE Put("{") END;
    p := nd.items;
    WHILE p # NIL DO
      IF p.key # NIL THEN PutScalar(p.key); Put("=") END;
      Dump(p.value);
      p := p.next;
      IF p # NIL THEN Put(",") END
    END;
    IF nd.kind = Y.Sequence THEN Put("]") ELSE Put("}") END
  END
END Dump;

PROCEDURE Report(ok: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name);
  IF ~ok THEN Out.String(": got "); Out.String(out) END;
  Out.Ln
END Report;

(* Checks that the YAML s reads as want: the tree dumped, then any
   warnings after " !"; or, if it does not read, "E line:col error" *)
PROCEDURE Check(name, s, want: ARRAY OF CHAR);
  VAR t: ARRAY 1024 OF CHAR; n: LONGINT; doc: Y.Node; w: Y.Warning; i: LONGINT;
BEGIN
  Decode(s, t, n);
  olen := 0; out := "";
  IF Y.Parse(t, n, doc) THEN
    Dump(doc);
    w := Y.warnings;
    WHILE w # NIL DO
      PutS(" !"); i := 0; WHILE w.text[i] # 0X DO Put(w.text[i]); INC(i) END;
      w := w.next
    END
  ELSE
    PutS("E "); PutInt(Y.errLine); Put(":"); PutInt(Y.errCol); Put(" ");
    PutS(Y.error)
  END;
  Report(out = want, name)
END Check;

(* Checks what the plain scalar s resolves to: "null", "true", "false",
   the number as pandoc shows it, or "string" *)
PROCEDURE CheckValue(s, want: ARRAY OF CHAR);
  VAR t: ARRAY 256 OF CHAR; n, len, i: LONGINT; doc: Y.Node; b: BOOLEAN;
    txt: Y.Text; name: ARRAY 300 OF CHAR;
BEGIN
  Decode(s, t, n);
  olen := 0; out := "";
  IF ~Y.Parse(t, n, doc) THEN PutS("E ") ; PutS(Y.error)
  ELSE
    IF doc.kind = Y.Mapping THEN doc := doc.items.value END;
    CASE Y.Resolve(doc, b) OF
      Y.Null: PutS("null")
    | Y.Bool: IF b THEN PutS("true") ELSE PutS("false") END
    | Y.Number:
        Y.NumberText(doc, txt, len);
        FOR i := 0 TO len - 1 DO Put(txt[i]) END
    | Y.String: PutS("string")
    END
  END;
  name := "value of "; i := 9; n := 0;
  WHILE s[n] # 0X DO name[i] := s[n]; INC(i); INC(n) END;
  name[i] := 0X;
  Report(out = want, name)
END CheckValue;

BEGIN
  failures := 0;
  (* documents *)
  Check("empty", "", "-");
  Check("comments only", "# a$  # b$", "-");
  Check("markers only", "---$...$", "-");
  Check("a scalar document", "hello", "P<hello>");
  Check("a map", "a: 1$b: two$", "{P<a>=P<1>,P<b>=P<two>}");
  Check("later documents are read and dropped", "a: 1$---$b: 2$", "{P<a>=P<1>}");
  Check("an explicit start", "---$a: 1$...$", "{P<a>=P<1>}");
  Check("an empty value", "a:$b: 2", "{P<a>=P<>,P<b>=P<2>}");
  Check("an indented map", "  a: 1$  b: 2$", "{P<a>=P<1>,P<b>=P<2>}");
  (* block collections *)
  Check("a nested map", "a:$  b: 1$  c: 2$d: 3",
    "{P<a>={P<b>=P<1>,P<c>=P<2>},P<d>=P<3>}");
  Check("a sequence", "- a$- b$", "[P<a>,P<b>]");
  Check("a sequence under a key, indented", "a:$  - x$  - y$b: 1",
    "{P<a>=[P<x>,P<y>],P<b>=P<1>}");
  Check("a sequence under a key, not indented", "a:$- x$- y$b: 1",
    "{P<a>=[P<x>,P<y>],P<b>=P<1>}");
  Check("compact maps in a sequence", "- a: 1$  b: 2$- c: 3$",
    "[{P<a>=P<1>,P<b>=P<2>},{P<c>=P<3>}]");
  Check("a compact sequence", "- - a$  - b$- c$", "[[P<a>,P<b>],P<c>]");
  Check("an empty entry", "-$- a$", "[P<>,P<a>]");
  Check("comments between", "a: 1 # one$# two$b: 2$", "{P<a>=P<1>,P<b>=P<2>}");
  (* plain scalars *)
  Check("a plain scalar over lines", "a: one$  two$$  three$b: x",
    "{P<a>=P<one two$three>,P<b>=P<x>}");
  Check("colons and hashes inside", "a: http://x.org/#y z#w$",
    "{P<a>=P<http://x.org/#y z#w>}");
  Check("a plain scalar in a sequence over lines", "- one$  two$",
    "[P<one two>]");
  Check("trailing spaces", "a: x   $", "{P<a>=P<x>}");
  (* quoted scalars *)
  Check("single quotes", "a: 'it''s # not: a comment'",
    "{P<a>=S<it's # not: a comment>}");
  Check("double quotes and escapes", 'a: "x\ty\n\"q\" \\ \u0041\x42"',
    '{P<a>=D<x~y$"q" \ AB>}');
  Check("quoted folding", "a: 'one  $   two$$  three'",
    "{P<a>=S<one two$three>}");
  Check("an escaped line break", 'a: "one\$   two"', "{P<a>=D<onetwo>}");
  Check("a single-quoted key", "'a b': 1$c: 2", "{S<a b>=P<1>,P<c>=P<2>}");
  Check("a double-quoted key", '"c" : 2', "{D<c>=P<2>}");
  Check("a tab in double quotes", 'a: "x~y"', "{P<a>=D<x~y>}");
  (* block scalars *)
  Check("a literal scalar", "a: |$  one$   two$$  three$b: 1",
    "{P<a>=L<one$ two$$three$>,P<b>=P<1>}");
  Check("a folded scalar", "a: >$  one$  two$$  three$   more$  four$",
    "{P<a>=F<one two$three$ more$four$>}");
  Check("strip chomping", "a: |-$  x$$$b: 1", "{P<a>=L<x>,P<b>=P<1>}");
  Check("keep chomping", "a: |+$  x$$$b: 1", "{P<a>=L<x$$$>,P<b>=P<1>}");
  Check("an indentation indicator", "a: |2$    x$   y$",
    "{P<a>=L<  x$ y$>}");
  Check("an empty block scalar", "a: |$b: 1", "{P<a>=L<>,P<b>=P<1>}");
  Check("a block scalar in a sequence", "- |$  x$- y",
    "[L<x$>,P<y>]");
  Check("a block scalar with a comment", "a: > # c$  x$", "{P<a>=F<x$>}");
  (* flow collections *)
  Check("a flow sequence", "a: [x, 'y', [z], {k: v}]",
    "{P<a>=[P<x>,S<y>,[P<z>],{P<k>=P<v>}]}");
  Check("a flow map", "a: {x: 1, y, z: }",
    "{P<a>={P<x>=P<1>,P<y>=P<>,P<z>=P<>}}");
  Check("a flow sequence over lines", "a: [one,$  two, # c$  three,$]",
    "{P<a>=[P<one>,P<two>,P<three>]}");
  Check("a single pair in a flow sequence", "[a: 1, b]",
    "[{P<a>=P<1>},P<b>]");
  Check("JSON", '{"a":[1,2],"b":"c"}',
    "{D<a>=[P<1>,P<2>],D<b>=D<c>}");
  Check("plain flow scalars with spaces", "[a b, c:d]", "[P<a b>,P<c:d>]");
  (* duplicate keys *)
  Check("duplicate keys", "a: 1$b: {c: 1, c: 2}$a: 3$",
    "{P<a>=P<3>,P<b>={P<c>=P<2>}} !Duplicate key: .a !Duplicate key: .b.c");
  Check("a duplicate key in a sequence", "x:$  - a: 1$    a: 2$",
    "{P<x>=[{P<a>=P<2>}]} !Duplicate key: .x[0].a");
  (* what is not read *)
  Check("an anchor", "a: &x 1", "E 0:3 anchors are not supported");
  Check("an alias", "a: 1$b: *x", "E 1:3 aliases are not supported");
  Check("a tag", "a: !!str 1", "E 0:3 tags are not supported");
  Check("a directive", "%YAML 1.2$---$a: 1", "E 0:0 directives are not supported");
  Check("a complex key", "? a$: b", "E 0:0 complex keys are not supported");
  (* errors *)
  Check("an unclosed flow sequence", "a: [x$", "E 1:0 a flow collection without its end");
  Check("an unclosed quote", "a: 'x$", "E 1:0 a quoted scalar without its closing quote");
  Check("a value after a value", "a: b: c", "E 0:4 a mapping value where none is allowed");
  Check("bad indentation", "a: 1$ b: 2", "E 1:2 a mapping value where none is allowed");
  Check("a deeper key", "a:$  b: 'x'$   c: 2", "E 2:3 bad indentation of a mapping entry");
  Check("a sequence after a key", "a: - b", "E 0:3 a sequence where it is not allowed");
  Check("text after a quoted scalar", "a: 'x' y", "E 0:7 text after a value");
  Check("a tab in indentation", "a:$~b: 1", "E 1:1 a tab in indentation");
  Check("text after the document", "- a$b", "E 1:0 text after the document's end");
  Check("a bad escape", 'a: "\q"', "E 0:5 an unknown escape in a double-quoted scalar");
  (* values *)
  CheckValue("a: ~", "null");
  CheckValue("a: NULL", "null");
  CheckValue("a:", "null");
  CheckValue("a: ''", "string");
  CheckValue("a: Yes", "true");
  CheckValue("a: y", "true");
  CheckValue("a: ON", "true");
  CheckValue("a: tRue", "string");
  CheckValue("a: off", "false");
  CheckValue("a: 'true'", "string");
  CheckValue("a: |-$  true", "true");
  CheckValue("a: >-$  true", "string");
  CheckValue("a: 1", "1");
  CheckValue("a: 1.0", "1");
  CheckValue("a: 1e3", "1000");
  CheckValue("a: 0x1F", "31");
  CheckValue("a: 0X1F", "string");
  CheckValue("a: 0o17", "15");
  CheckValue("a: +5", "5");
  CheckValue("a: -0", "0");
  CheckValue("a: -12", "-12");
  CheckValue("a: 1.", "1");
  CheckValue("a: 1e", "string");
  CheckValue("a: .5", "string");
  CheckValue("a: 1_000", "string");
  CheckValue("a: 1.5e10", "15000000000");
  CheckValue("a: 0.001", "1.0e-3");
  CheckValue("a: 0.1", "0.1");
  CheckValue("a: 1.50", "1.5");
  CheckValue("a: 1.5e-3", "1.5e-3");
  CheckValue("a: 123456789.5", "1.234567895e8");
  CheckValue("a: 12345678.5", "1.23456785e7");
  CheckValue("a: 1234567.5", "1234567.5");
  CheckValue("a: 99999999999999999999", "9.9999999999999999999e19");
  CheckValue("a: 9223372036854775807", "9223372036854775807");
  CheckValue("a: 9223372036854775808", "9.223372036854775808e18");
  CheckValue("a: -9223372036854775808", "-9223372036854775808");
  CheckValue("a: 1e400", "1.0e400");
  CheckValue("a: -1E+2", "-100");
  CheckValue("a: 0xFFFFFFFFFFFFFFFF", "1.8446744073709551615e19");
  IF failures = 0 THEN Out.String("all passed") ELSE Out.Int(failures, 0); Out.String(" failed") END;
  Out.Ln
END PdYamlTest.
