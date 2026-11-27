# Halt and assert codes

`HALT` and `ASSERT` are for what should never happen. Errors the user
can cause end podoc with pandoc's exit statuses instead (AGENTS.md,
"Exit statuses and halt codes").

In poc the two report differently:

- **`HALT(n)`** ends the program with exit status `n` and prints
  nothing.
- **`ASSERT(x, n)`** always ends it with exit status 10 and prints
  `assertion failed (n)`. Its code is in the message, not the exit
  status.

## Codes in use

Checked 2026-11-21 against poc 0.15.0 and the libraries' sources
under `~/Repos/Oberon`.

| Who | Codes | Kind |
|---|---|---|
| poc's traps | 2–14; 15 planned (Peaseblossom's enhancement 15, a full table of out-of-memory hooks) | exit status, with a message (the reference guide's table of traps) |
| poc's runtime (`Files`, `Texts`) | 99 | `HALT`, exit status |
| pounicode | 20–22 | `ASSERT` |
| poDateTime | 20–24; and 20 for a method with no body (`TimeZones`) | `ASSERT`; `HALT` |
| polibfyaml | 61–65 (`Fyaml.Assert...`) | `ASSERT` |
| pofltk | 70–78 (its PLAN.md, "Halt codes") | `ASSERT` |
| polibtls | 90–99 | `ASSERT` |
| Ropes | 1, for misuse: an index out of range, a length that overflows (checked 2026-11-26) | `HALT`, exit status, no message |
| ArgParser | none (it ends a bad command line with status 2, through `Platform.Exit`) | |
| **podoc** | from 100; none assigned yet | `HALT` and `ASSERT` |

podoc uses Ropes, pounicode and ArgParser. The others are listed so
that podoc's codes stay clear of every po* library's.

podoc's pandoc exit statuses (1, 4, 5, 6, 21–23, 43, 47, 64, 83,
97–99) share numbers with poc's traps (4 is also a NIL dereference,
5 a failed type guard, 6 a `WITH` with no match). Only the message
tells them apart. Ropes' `HALT(1)` prints nothing, so it looks like
pandoc's IOError with its message missing: a status of 1 with nothing
on standard error is a bug in podoc's use of Ropes.

## podoc's codes

List each code here when it is assigned: the code, `HALT` or
`ASSERT`, the module and what it means.

| Code | Kind | Module | Meaning |
|---|---|---|---|

## Checking again

After upgrading poc or a library:

```sh
cd ~/Repos/Oberon
grep -rnE --include='*.Mod' 'HALT\( *[0-9]+ *\)|ASSERT\(.*, *[A-Za-z0-9.]+ *\)' \
    pounicode/src poDateTime/src polibfyaml/src pofltk/src polibtls/src Ropes ArgParser
```

Named codes (polibfyaml's `AssertInvalid` and the like) are defined as
constants in the library's main module. poc's trap statuses are in
Peaseblossom's doc/reference-guide.md, "Traps and exit statuses".
