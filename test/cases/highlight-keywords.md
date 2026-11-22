---
title: Users' lists
code-keywords:
  c: [widget, gadget, -int]
  ada:
    replace: true
    words: [procedure, begin]
  sh: -case
  bash: "select -time"
  cobol: [move]
---

Pascal, with a file that adds and removes:

```pascal
procedure P; override; VIRTUAL; goto 1; begin end
```

The same list in fpc, another name for the same language:

```fpc
OVERRIDE goto
```

Oberon, with a file that replaces:

```oberon
MODULE M; PROCEDURE P; BEGIN END P; END M.
```

Oberon-2 is the same language, so it is changed too:

```oberon2
MODULE M; BEGIN END M.
```

Oberon-07 is not:

```oberon07
MODULE M; BEGIN END M.
```

C, from the metadata, with `widget` taken out again by a file:

```c
int widget; gadget x; long y;
```

Ada, replaced by the metadata:

```ada
procedure P is begin null; end P;
```

sh without `case`:

```sh
case x in a) echo; esac
if true; then :; fi
```

bash with `select` and without `time`:

```bash
time ls
select x in a b; do :; done
```

Inline: `begin override end`{.pascal}.
