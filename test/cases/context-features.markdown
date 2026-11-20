# Escapes {#esc-1}

Braces {} backslash \\ dollar \$ bar \| percent % tilde \~ hash \# \[brackets\]. Dashes -- and --- and ... and it's "quoted" and 'single'. Non-breaking space.

## Unnumbered {#unnumbered .unnumbered}

## Unlisted {#unlisted .unlisted}

### Both {#both .unnumbered .unlisted}

# Inlines

*em* **bf** [sc]{.smallcaps} [ul]{.underline} ~~strike~~ x^2^ H~2~O `plain` `a{b}` `{"'\`()-+=%,.:;}``x}y`$a+b$ and $$\int x$$ and``\raw`{=tex}`{=context}``\tex`{=tex}`{=tex}``<b>`{=html}\`{=html}

Line\
after\
break.

A <https://example.com/a%20b#frag> autolink and <me@example.com>. [Text](https://example.com/x%y#z "t") and [internal](#esc-1) and [odd](#a=b).

![Alt](img/a%20b.png){.cls width="50%" height="3cm"} ![Inline](c:\path\x.png){width="100px"} ![](pic.jpg){width="2.5in" height="12pt"}

[Span]{#sp lang="fr" dir="ltr"} [rtl]{dir="rtl"}.

Note.[^1] Code note.[^2]

# Blocks

> Quote
>
> > nested

| line one
|   indented
| 
| after empty

::: {#d1 lang="el" dir="rtl"}
Div text.
:::

::: {lang="en-GB"}
English.
:::

::: {#refs .hanging-indent}
Ref.
:::

1.  one

2.  two

    a.  alpha

    b.  beta

        i.  roman

            A)  Upper

                (I) Roman

<!-- -->

3)  paren

<!-- -->

(7) two parens

<!-- -->

1.  default
2.  default

Term
: Definition *one*.
: Definition two.

Term 2
: Loose
  paragraphs

- tight

- list

- loose

- list

------------------------------------------------------------------------

``` {#code}
main = print 1
```

    { braces }

```{=context}
\raw block
```
\latex block

![Figure *caption*](fig.png){#fig:one}

  Left     Right  Center  Default
  ------ ------- -------- ---------
  a            b    c     d
  e            f    g     h

  : Table caption {#tbl:one}

  -----------------
   short   long
  -------- --------
     x     y

  -----------------

  -----------------------------------------------------------------------
               Wide              Narrow
  ------------------------------ ----------------------------------------
   A multiline cell that wraps.  B

                C                D
  -----------------------------------------------------------------------

  : Multiline with widths

[^1]: A *note*.

    Second paragraph.

[^2]: With code:

        code
