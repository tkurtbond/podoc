# Intro {#pre-intro .special key="val"}

Text with a note[^pre-1] and another.[^pre-2]

## Sub [link](http://x.com) here

- [ ] todo
- [x] done

1.  one
2.  two

<!-- -->

(1) ex one
(2) ex two

<!-- -->

1.  hash

<!-- -->

iv. roman
v.  roman2

<!-- -->

A)  alpha
B)  beta

### Deep {#pre-deep .unnumbered}

#### Unlisted {#pre-unlisted .unlisted}

::::: columns
::: {.column width="40%"}
left
:::

::: {.column width="60%"}
right
:::
:::::

::: {#pre-d1 .warning data-x="1" foo="bar" label="l"}
Inside div.
:::

![A figure caption](fig.png "Title"){#pre-fig1 width="300px" height="2.5cm"}

![](inline.svg){width="50%"} inline ![alt *x*](a.jpg){alt="given"} and ![](s.mp3) and ![](doc.pdf)

[span]{.smallcaps} [k]{#pre-s1 .kbd .x} [m]{.mark} [u]{.underline} [p]{.csl-no-emph} [plain]{.foo style="color:red"} `x`{.sample} `y`{.variable .z}

::: raw
raw html
:::

\dropped

| Line one
|   Line two

> quote
>
> > nested

Term
: Definition one
  more

Term 2
: Def 2a
: Def 2b

------------------------------------------------------------------------

    Right Left    Center  Default
  ------- ------ -------- ---------
       12 12        12    12
      123 123      123    123

  : Simple table

  ------------------------------------------------------------------
   Centered Header  Default Aligned     Right Aligned Left Aligned
  ----------------- ----------------- --------------- --------------
        First       row                          12.0 Example long

       Second       row                           5.0 Here
  ------------------------------------------------------------------

  : Multiline {#pre-tbl .c}

# Second

Back link <a@b.com> and [mail](mailto:x@y.z "t") and [int](#intro "go").

[Cite]{.citation} H~2~O ~~s~~ ^sup^

Last para with ↩ arrow and ↔.

Para[^pre-3]

## Empty header {#pre-empty-header .unnumbered}

####### Not header

[^pre-1]: First note.

    Second para of note.

[^pre-2]: Inline *note* here.

[^pre-3]:
        code note
