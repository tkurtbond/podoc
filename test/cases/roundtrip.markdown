# A header {#hdr .cls key="v"}

A paragraph with *emphasis*, **strong**, ~~strike~~, ^sup^, ~sub~, [small caps]{.smallcaps}, `code`{.x}, $x^2$ and $$y$$, a [link](http://example.com "title"), <http://example.com/auto>, an ![image](img.png){width="50%"}, a footnote[^1] and an inline note[^2], "quotes" and 'single', a hard\
break, and special characters: \* \_ \` \# \< \> \[ \] \\ \$ \| \~ \^.

## Second level

> A block quote
>
> > nested.

``` {#code1 .haskell startFrom="3"}
main = print 1
```

    indented code

:::: {#div1 .note}
Inside a div.

::: inner
Nested div.
:::
::::

- bullet one
- bullet two
  - nested
  - [ ] a task
  - [x] done

Between lists.

3.  third

4.  fourth

    with a second paragraph

Then.

(a) alpha
(b) beta

Term

: Definition one.

  More.

Other term
: Two.

| line one
|    line two indented

------------------------------------------------------------------------

  Right   Left    Center
  ------- ------ --------
  1       a         x
  22      bb        yy

  : A caption

![A figure caption](fig.png){#fig1}

Final paragraph with a [span]{#s1 .c key="v"}.

[^1]: The footnote,

    in two paragraphs.

[^2]: Inline *note*.
