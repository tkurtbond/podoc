---
title: "Feature *test* & more"
author:
  - Jane Doe
  - name: X
date: 2024-03-05
description: A "test" doc
lang: en
---

# Intro {#intro .special key=val}

Text with a note[^1] and another.^[Inline *note* here.]

[^1]: First note.

    Second para of note.

## Sub [link](http://x.com) here

- [ ] todo
- [x] done

1. one
2. two

(@) ex one
(@) ex two

#. hash

iv. roman
v. roman2

A) alpha
B) beta

### Deep {.unnumbered}

#### Unlisted {.unlisted}

::: {.columns}
::: {.column width="40%"}
left
:::
::: {.column width="60%"}
right
:::
:::

::: {#d1 .warning data-x=1 foo=bar label=l}
Inside div.
:::

![A figure caption](fig.png "Title"){#fig1 width=300px height=2.5cm}

![](inline.svg){width=50%} inline ![alt *x*](a.jpg){alt="given"} and ![](s.mp3) and ![](doc.pdf)

[span]{.smallcaps} [k]{.kbd .x #s1} [m]{.mark} [u]{.underline} [p]{.csl-no-emph}
[plain]{.foo style="color:red"} `x`{.sample} `y`{.variable .z}

<div class="raw">raw html</div>

```{=latex}
\dropped
```

| Line one
|   Line two

> quote
>
> > nested

Term
:   Definition one

    more

Term 2
:   Def 2a

:   Def 2b

-----

  Right     Left     Center     Default
-------     ------ ----------   -------
     12     12        12            12
    123     123      123           123

Table: Simple table

--------------------------------------------
Centered   Default           Right Left
 Header    Aligned         Aligned Aligned
---------- ------------ ---------- ---------
   First   row                12.0 Example
                                   long

  Second   row                 5.0 Here
--------------------------------------------

: Multiline {#tbl .c}

# Second

Back link <a@b.com> and [mail](mailto:x@y.z "t") and [int](#intro "go").

[Cite]{.citation} H~2~O ~~s~~ ^sup^

Last para with ↩ arrow and ↔.

Para[^2]

[^2]: ```
    code note
    ```

## Empty header {-}

####### Not header
