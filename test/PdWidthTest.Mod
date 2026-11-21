MODULE PdWidthTest;
(* Tests of PdWidth: string widths, as doclayout 0.5.0.3's realLength
   gives them, emoji sequences joined. Each string is given as its
   characters, ended by -1. The expected widths are doclayout's, checked
   against pandoc 3.10 through tables and wrapping. *)

IMPORT Out, Utf8, W := PdWidth;

VAR failures: INTEGER;

PROCEDURE Report(ok: BOOLEAN; name: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(name); Out.Ln
END Report;

(* The width of a, b, c, d and e, up to the first -1, is want *)
PROCEDURE T(name: ARRAY OF CHAR; want: LONGINT; a, b, c, d, e: Utf8.Rune);
  VAR s: W.State; r: ARRAY 5 OF Utf8.Rune; i: INTEGER;
BEGIN
  r[0] := a; r[1] := b; r[2] := c; r[3] := d; r[4] := e;
  W.Start(s); i := 0;
  WHILE (i < 5) & (r[i] # -1) DO W.Add(s, r[i]); INC(i) END;
  Report(W.Total(s) = want, name)
END T;

BEGIN
  failures := 0;
  T("empty", 0, -1, -1, -1, -1, -1);
  T("ascii", 2, ORD("a"), ORD("b"), -1, -1, -1);
  T("wide", 4, 65E5H, 672CH, -1, -1, -1);
  T("combining first", 2, 301H, ORD("a"), -1, -1, -1);
  T("combining after a letter", 1, ORD("e"), 301H, -1, -1, -1);
  T("emoji with U+FE0F", 2, 1F3DBH, 0FE0FH, -1, -1, -1);
  T("U+FE0F after a letter", 1, ORD("x"), 0FE0FH, -1, -1, -1);
  T("U+FE0F alone", 0, 0FE0FH, -1, -1, -1, -1);
  T("emoji with a skin tone", 2, 1F44DH, 1F3FDH, -1, -1, -1);
  T("skin tone after a letter", 3, ORD("a"), 1F3FDH, -1, -1, -1);
  T("skin tone alone", 2, 1F3FBH, -1, -1, -1, -1);
  T("emoji ZWJ sequence", 2, 1F468H, 200DH, 1F469H, 200DH, 1F467H);
  T("ZWJ after a letter", 3, ORD("a"), 200DH, 1F44DH, -1, -1);
  T("ZWJ alone", 0, 200DH, -1, -1, -1, -1);
  T("emoji then ZWJ", 0, 1F44DH, 200DH, -1, -1, -1);
  T("keycap", 2, ORD("1"), 0FE0FH, 20E3H, -1, -1);
  T("skin tone then ZWJ", 2, 1F469H, 1F3FDH, 200DH, 1F4BBH, -1);
  T("U+FE0F then ZWJ", 2, 2764H, 0FE0FH, 200DH, 1F525H, -1);
  T("emoji then a letter", 3, 1F3DBH, 0FE0FH, ORD("x"), -1, -1);
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdWidthTest.
