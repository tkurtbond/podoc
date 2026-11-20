---
title: The *Plain* Writer
author:
- One Author
- Two Author
date: 2026-11-20
---

# A Header with *emphasis* {#hdr .cls}

## Second level

### Third level

Some [small caps with a note^[A note in *caps*.]]{.smallcaps} and
H~2~O, x^2^, ^a\ b^, ^*x*^, ~*x*~, ~q~, ^Q^, ~a\ q~, x~1\ 2~ and ~~gone~~.

[Span]{.foo} and `code`{.haskell} and <http://example.com> and
[a link](http://example.com "title") and ![an image](img.png){width=50%}
and <me@example.com> and "quotes" and 'single'.

| line one
|    line two indented
|
| after blank

> A block quote
> with two lines.
>
> > Nested.

Term
:   Definition one.

Term two

:   Loose definition.

    Second paragraph.

- a list

```haskell
code after list
```

1. one
2. two

<!-- -->

1. three

```{=plain}
raw plain
```

```{=html}
<p>raw html</p>
```

`inline raw`{=plain} and `dropped`{=html}.

::: {.note}
A div.
:::

![A figure caption](fig.png)

![Figure with id](fig2.png){#fig:x}

    indented code

* * *

Text with a second note.[^2]

[^2]: Second note.

    With a code block.

Final.
