---
code-style: proportional
---

The metadata's style, `BEGIN END`{.oberon}:

```oberon
BEGIN x := 1 END
```

A block's class wins:

```{.oberon .mono}
BEGIN x := 2 END
```

```{.c .plain}
int x = 3;
```

`int x`{.c .mono} and `int y`{.c .plain}.
