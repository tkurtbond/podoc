MODULE PdRunTest;
(* Tests of PdRun: quoting, exit statuses, finding programs, and the
   temporary directory. *)

IMPORT Out, R := PdRun;

VAR
  failures: INTEGER;
  c: R.Command;
  dir: R.Path;
  ok: BOOLEAN;

PROCEDURE Report(good: BOOLEAN; what: ARRAY OF CHAR);
BEGIN
  IF good THEN Out.String("ok   - ") ELSE Out.String("FAIL - "); INC(failures) END;
  Out.String(what); Out.Ln
END Report;

(* Whether the shell reads s, quoted by Add, as one word matching the
   case pattern pat *)
PROCEDURE Word(s, pat: ARRAY OF CHAR): BOOLEAN;
  VAR c: R.Command;
BEGIN
  c := R.New(); R.AddText(c, "case"); R.Add(c, s);
  R.AddText(c, " in "); R.AddText(c, pat);
  R.AddText(c, ") exit 0;; *) exit 1;; esac");
  RETURN R.Run(c) = 0
END Word;

(* Whether the directory d exists *)
PROCEDURE IsDir(d: ARRAY OF CHAR): BOOLEAN;
  VAR c: R.Command;
BEGIN
  c := R.New(); R.AddText(c, "test -d"); R.Add(c, d);
  RETURN R.Run(c) = 0
END IsDir;

BEGIN
  failures := 0;
  Report(Word("a b", "a?b"), "a space stays in the word");
  Report(Word("it's", "it?s"), "a quote stays in the word");
  Report(Word("$HOME", "?HOME"), "a dollar sign is not expanded");
  Report(Word("''", "??"), "two quotes");
  Report(Word("*", "?"), "a star is not a glob");
  c := R.New(); R.AddText(c, "exit 3");
  Report(R.Run(c) = 3, "exit status 3");
  c := R.New(); R.AddText(c, "exit 255");
  Report(R.Run(c) = 255, "exit status 255");
  c := R.New(); R.AddText(c, "kill -9 $$");
  Report(R.Run(c) = 128 + 9, "killed by signal 9");
  Report(R.Found("sh"), "sh is found");
  Report(~R.Found("/no/where/sh"), "/no/where/sh is not found");
  R.MakeTempDir(dir, ok);
  Report(ok & (dir[0] = "/") & IsDir(dir), "the temporary directory is made");
  R.RemoveDir(dir);
  Report(~IsDir(dir), "the temporary directory is removed");
  IF failures > 0 THEN Out.Int(failures, 0); Out.String(" failed"); Out.Ln END
END PdRunTest.
