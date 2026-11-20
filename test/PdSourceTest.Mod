MODULE PdSourceTest;
(* Tests of PdSource.Add: the input prepared as pandoc prepares it. *)

IMPORT Out, PdIO, PdSource;

VAR
  failures: INTEGER;

(* Copies the string s, with "~" standing for a tab, "|" for a CR and
   "$" for a new line, into t; n is its length. *)
PROCEDURE Decode(s: ARRAY OF CHAR; VAR t: ARRAY OF CHAR; VAR n: LONGINT);
  VAR i: LONGINT;
BEGIN
  i := 0; n := 0;
  WHILE s[i] # 0X DO
    CASE s[i] OF
      "~": t[n] := 09X
    | "|": t[n] := 0DX
    | "$": t[n] := 0AX
    ELSE t[n] := s[i]
    END;
    INC(i); INC(n)
  END
END Decode;

(* Checks that the inputs a and then b, prepared with the tab stop
   tabStop and joined, give want; b is left out when it is "!". *)
PROCEDURE Check(name, a, b: ARRAY OF CHAR; tabStop: INTEGER; want: ARRAY OF CHAR);
  VAR dst: PdIO.Text; dlen, n, wn, i: LONGINT;
    src, w: ARRAY 256 OF CHAR; ok: BOOLEAN;
BEGIN
  dst := NIL; dlen := 0;
  Decode(a, src, n); PdSource.Add(dst, dlen, src, n, tabStop);
  IF b # "!" THEN Decode(b, src, n); PdSource.Add(dst, dlen, src, n, tabStop) END;
  Decode(want, w, wn);
  ok := dlen = wn;
  i := 0;
  WHILE ok & (i < wn) DO ok := dst[i] = w[i]; INC(i) END;
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name); Out.Ln
END Check;

PROCEDURE CheckBOM;
  VAR dst: PdIO.Text; dlen: LONGINT; src: ARRAY 8 OF CHAR;
BEGIN
  src[0] := 0EFX; src[1] := 0BBX; src[2] := 0BFX; src[3] := "a"; src[4] := 0AX;
  dst := NIL; dlen := 0;
  PdSource.Add(dst, dlen, src, 5, 4);
  IF (dlen = 3) & (dst[0] = "a") & (dst[1] = 0AX) & (dst[2] = 0AX) THEN
    Out.String("ok   - ")
  ELSE
    Out.String("FAIL - "); INC(failures)
  END;
  Out.String("a byte order mark is dropped"); Out.Ln
END CheckBOM;

PROCEDURE CheckUtf8Tab;
  VAR dst: PdIO.Text; dlen: LONGINT; src: ARRAY 8 OF CHAR;
BEGIN
  (* "é" is two bytes but one column: the tab goes to column 4 *)
  src[0] := 0C3X; src[1] := 0A9X; src[2] := 09X; src[3] := "b"; src[4] := 0AX;
  dst := NIL; dlen := 0;
  PdSource.Add(dst, dlen, src, 5, 4);
  IF (dlen = 8) & (dst[2] = " ") & (dst[4] = " ") & (dst[5] = "b") THEN
    Out.String("ok   - ")
  ELSE
    Out.String("FAIL - "); INC(failures)
  END;
  Out.String("tabs count characters, not bytes"); Out.Ln
END CheckUtf8Tab;

BEGIN
  failures := 0;
  Check("a new line is appended", "a$", "!", 4, "a$$");
  Check("a last line gets a new line", "a", "!", 4, "a$$");
  Check("an empty input is a new line", "", "!", 4, "$");
  Check("CRs are removed", "a|$b|$", "!", 4, "a$b$$");
  Check("a lone CR is removed", "a|b", "!", 4, "ab$$");
  Check("tabs go to the next stop", "~a$ab~c$abcd~e$", "!", 4,
    "    a$ab  c$abcd    e$$");
  Check("tab stop 8", "a~b", "!", 8, "a       b$$");
  Check("tabs are kept with tab stop 0", "a~b$", "!", 0, "a~b$$");
  Check("no last new line is added with tab stop 0", "a~b", "!", 0, "a~b$");
  Check("inputs are joined", "a", "b$", 4, "a$$b$$");
  Check("columns restart in each input", "ab", "~c", 4, "ab$$    c$$");
  CheckBOM;
  CheckUtf8Tab;
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdSourceTest.
