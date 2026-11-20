MODULE PdGlobTest;
(* Tests of PdGlob: Match against Python's fnmatch.fnmatchcase, and
   Compare against natsort's order. The answers are Python 3.14's. *)

IMPORT Out, PdGlob;

VAR
  failures: INTEGER;

PROCEDURE Report(ok: BOOLEAN; a, b: ARRAY OF CHAR);
BEGIN
  IF ok THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(a); Out.String(" "); Out.String(b); Out.Ln
END Report;

(* Checks that the pattern matches the name when want *)
PROCEDURE M(pattern, name: ARRAY OF CHAR; want: BOOLEAN);
BEGIN
  Report(PdGlob.Match(pattern, name) = want, pattern, name)
END M;

(* Checks that Compare(a, b) is want *)
PROCEDURE C(a, b: ARRAY OF CHAR; want: INTEGER);
BEGIN
  Report(PdGlob.Compare(a, b) = want, a, b)
END C;

BEGIN
  failures := 0;
  M("*.md", "a.md", TRUE);
  M("*.md", ".md", TRUE);
  M("a?c", "abc", TRUE);
  M("a?c", "ac", FALSE);
  M("[abc]x", "bx", TRUE);
  M("[!abc]x", "bx", FALSE);
  M("[!abc]x", "dx", TRUE);
  M("[a-c]", "b", TRUE);
  M("[c-a]", "b", FALSE);
  M("[]]", "]", TRUE);
  M("[!]]", "]", FALSE);
  M("[a-]", "-", TRUE);
  M("[", "[", TRUE);
  M("[ab", "[ab", TRUE);
  M("a*b*c", "aXbYc", TRUE);
  M("a*b*c", "aXbY", FALSE);
  M("*", "é", TRUE);
  M("?", "é", TRUE);
  M("[é]", "é", TRUE);
  M("a/b", "a/b", TRUE);
  M("**", "x/y", TRUE);
  M("[--0]", ".", TRUE);
  M("[z-a-c]", "b", FALSE);
  C("part2.md", "part10.md", -1);
  C("part10.md", "part2.md", 1);
  C("part1.md", "part1.md", 0);
  C("B.md", "a.md", -1);
  C("x01", "x1", 0);
  C("x1.5", "x1a", -1);
  C("x1", "x1a", -1);
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdGlobTest.
