# Head `IF x (* c *) END`{.oberon}

Inline `IF x THEN (* c *) END`{.oberon}, `int x; // c {}`{.c},
`IF x`{.haskell} and `plain`.

```oberon
MODULE M; (* a {comment}
  over two lines *)
  VAR s: ARRAY 8 OF CHAR; (* it's -- 50% *)
BEGIN s := "(* a\b *)"; t := 'END'
END M.
```

```c
.dot at start
static int f(void) { return '\''; } // x--y ``z''
```

``` modula2
FROM InOut IMPORT WriteString; (* end END *)
```

```
no language # $ { } -- x
```

```{.oberon .plain}
MODULE Plain;
```
