MODULE PdDefaults;
(* PdDefaults: pandoc 3.10's default templates and their partials,
   and podoc's own default.mom, from data/templates. Written by
   tools/mktemplates; do not edit. *)

IMPORT PdIO;

VAR
  t: PdIO.Text;
  n: LONGINT;

PROCEDURE S(s: ARRAY OF CHAR);
  VAR i: LONGINT;
BEGIN
  i := 0;
  WHILE s[i] # 0X DO
    PdIO.Reserve(t, n, n + 1); t[n] := s[i]; INC(n); INC(i)
  END
END S;

PROCEDURE C(ch: CHAR);
BEGIN
  PdIO.Reserve(t, n, n + 1); t[n] := ch; INC(n)
END C;

PROCEDURE T0;
BEGIN
  S("<!DOCTYPE html>"); C(0AX); S("<html xmlns="); C(22X);
  S("http://www.w3.org/1999/xhtml"); C(22X); S("$if(lang)$ lang="); C(22X);
  S("$lang$"); C(22X); S(" xml:lang="); C(22X);
  S("$lang$"); C(22X); S("$endif$$if(dir)$ dir="); C(22X);
  S("$dir$"); C(22X); S("$endif$>"); C(0AX);
  S("<head>"); C(0AX); S("  <meta charset="); C(22X);
  S("utf-8"); C(22X); S(" />"); C(0AX);
  S("  <meta name="); C(22X); S("generator"); C(22X);
  S(" content="); C(22X); S("pandoc $pandoc-version$"); C(22X);
  S(" />"); C(0AX); S("  <meta name="); C(22X);
  S("viewport"); C(22X); S(" content="); C(22X);
  S("width=device-width, initial-scale=1.0, user-scalable=yes"); C(22X); S(" />"); C(0AX);
  S("$for(author-meta)$"); C(0AX); S("  <meta name="); C(22X);
  S("author"); C(22X); S(" content="); C(22X);
  S("$author-meta$"); C(22X); S(" />"); C(0AX);
  S("$endfor$"); C(0AX); S("$if(date-meta)$"); C(0AX);
  S("  <meta name="); C(22X); S("dcterms.date"); C(22X);
  S(" content="); C(22X); S("$date-meta$"); C(22X);
  S(" />"); C(0AX); S("$endif$"); C(0AX);
  S("$if(keywords)$"); C(0AX); S("  <meta name="); C(22X);
  S("keywords"); C(22X); S(" content="); C(22X);
  S("$for(keywords)$$keywords$$sep$, $endfor$"); C(22X); S(" />"); C(0AX);
  S("$endif$"); C(0AX); S("$if(description-meta)$"); C(0AX);
  S("  <meta name="); C(22X); S("description"); C(22X);
  S(" content="); C(22X); S("$description-meta$"); C(22X);
  S(" />"); C(0AX); S("$endif$"); C(0AX);
  S("  <title>$if(title-prefix)$$title-prefix$ "); C(0E2X); C(80X); C(93X);
  S(" $endif$$pagetitle$</title>"); C(0AX); S("  <style>"); C(0AX);
  S("    $styles.html()$"); C(0AX); S("  </style>"); C(0AX);
  S("$for(css)$"); C(0AX); S("  <link rel="); C(22X);
  S("stylesheet"); C(22X); S(" href="); C(22X);
  S("$css$"); C(22X); S(" />"); C(0AX);
  S("$endfor$"); C(0AX); S("$for(header-includes)$"); C(0AX);
  S("  $header-includes$"); C(0AX); S("$endfor$"); C(0AX);
  S("$if(math)$"); C(0AX); S("  $math$"); C(0AX);
  S("$endif$"); C(0AX); S("</head>"); C(0AX);
  S("<body>"); C(0AX); S("$for(include-before)$"); C(0AX);
  S("$include-before$"); C(0AX); S("$endfor$"); C(0AX);
  S("$if(title)$"); C(0AX); S("<header id="); C(22X);
  S("title-block-header"); C(22X); S(">"); C(0AX);
  S("<h1 class="); C(22X); S("title"); C(22X);
  S(">$title$</h1>"); C(0AX); S("$if(subtitle)$"); C(0AX);
  S("<p class="); C(22X); S("subtitle"); C(22X);
  S(">$subtitle$</p>"); C(0AX); S("$endif$"); C(0AX);
  S("$for(author)$"); C(0AX); S("<p class="); C(22X);
  S("author"); C(22X); S(">$author$</p>"); C(0AX);
  S("$endfor$"); C(0AX); S("$if(date)$"); C(0AX);
  S("<p class="); C(22X); S("date"); C(22X);
  S(">$date$</p>"); C(0AX); S("$endif$"); C(0AX);
  S("$if(abstract)$"); C(0AX); S("<div class="); C(22X);
  S("abstract"); C(22X); S(">"); C(0AX);
  S("<div class="); C(22X); S("abstract-title"); C(22X);
  S(">$abstract-title$</div>"); C(0AX); S("$abstract$"); C(0AX);
  S("</div>"); C(0AX); S("$endif$"); C(0AX);
  S("</header>"); C(0AX); S("$endif$"); C(0AX);
  S("$if(toc)$"); C(0AX); S("<nav id="); C(22X);
  S("$idprefix$TOC"); C(22X); S(" role="); C(22X);
  S("doc-toc"); C(22X); S(">"); C(0AX);
  S("$if(toc-title)$"); C(0AX); S("<h2 id="); C(22X);
  S("$idprefix$toc-title"); C(22X); S(">$toc-title$</h2>"); C(0AX);
  S("$endif$"); C(0AX); S("$table-of-contents$"); C(0AX);
  S("</nav>"); C(0AX); S("$endif$"); C(0AX);
  S("$body$"); C(0AX); S("$for(include-after)$"); C(0AX);
  S("$include-after$"); C(0AX); S("$endfor$"); C(0AX);
  S("</body>"); C(0AX); S("</html>"); C(0AX)
END T0;

PROCEDURE T1;
BEGIN
  S("/* Default styles provided by pandoc."); C(0AX); S("** See https://pandoc.org/MANUAL.html#variables-for-html for"); S(" config info.");
  C(0AX); S("*/"); C(0AX); S("$if(document-css)$");
  C(0AX); S("html {"); C(0AX); S("$if(mainfont)$");
  C(0AX); S("  font-family: $mainfont$;"); C(0AX); S("$endif$");
  C(0AX); S("$if(fontsize)$"); C(0AX); S("  font-size: $fontsize$;");
  C(0AX); S("$endif$"); C(0AX); S("$if(linestretch)$");
  C(0AX); S("  line-height: $linestretch$;"); C(0AX); S("$endif$");
  C(0AX); S("  color: $if(fontcolor)$$fontcolor$$else$#1a1a1a$endif$;"); C(0AX); S("  background-color: $if(backgroundcolor)$$backgroundcolor$$e");
  S("lse$#fdfdfd$endif$;"); C(0AX); S("}"); C(0AX);
  S("body {"); C(0AX); S("  margin: 0 auto;"); C(0AX);
  S("  max-width: $if(maxwidth)$$maxwidth$$else$36em$endif$;"); C(0AX); S("  padding-left: $if(margin-left)$$margin-left$$else$50px$end"); S("if$;");
  C(0AX); S("  padding-right: $if(margin-right)$$margin-right$$else$50px$"); S("endif$;"); C(0AX);
  S("  padding-top: $if(margin-top)$$margin-top$$else$50px$endif$"); S(";"); C(0AX); S("  padding-bottom: $if(margin-bottom)$$margin-bottom$$else$50");
  S("px$endif$;"); C(0AX); S("  hyphens: auto;"); C(0AX);
  S("  overflow-wrap: break-word;"); C(0AX); S("  text-rendering: optimizeLegibility;"); C(0AX);
  S("  font-kerning: normal;"); C(0AX); S("}"); C(0AX);
  S("@media (max-width: 600px) {"); C(0AX); S("  body {"); C(0AX);
  S("    font-size: 0.9em;"); C(0AX); S("    padding: 12px;"); C(0AX);
  S("  }"); C(0AX); S("  h1 {"); C(0AX);
  S("    font-size: 1.8em;"); C(0AX); S("  }"); C(0AX);
  S("}"); C(0AX); S("@media print {"); C(0AX);
  S("  html {"); C(0AX); S("    background-color: $if(backgroundcolor)$$backgroundcolor$"); S("$else$white$endif$;");
  C(0AX); S("  }"); C(0AX); S("  body {");
  C(0AX); S("    background-color: transparent;"); C(0AX); S("    color: black;");
  C(0AX); S("    font-size: 12pt;"); C(0AX); S("  }");
  C(0AX); S("  p, h2, h3 {"); C(0AX); S("    orphans: 3;");
  C(0AX); S("    widows: 3;"); C(0AX); S("  }");
  C(0AX); S("  h2, h3, h4 {"); C(0AX); S("    page-break-after: avoid;");
  C(0AX); S("  }"); C(0AX); S("}");
  C(0AX); S("p {"); C(0AX); S("  margin: 1em 0;");
  C(0AX); S("}"); C(0AX); S("a {");
  C(0AX); S("  color: $if(linkcolor)$$linkcolor$$else$#1a1a1a$endif$;"); C(0AX); S("}");
  C(0AX); S("a:visited {"); C(0AX); S("  color: $if(linkcolor)$$linkcolor$$else$#1a1a1a$endif$;");
  C(0AX); S("}"); C(0AX); S("img {");
  C(0AX); S("  max-width: 100%;"); C(0AX); S("}");
  C(0AX); S("svg {"); C(0AX); S("  height: auto;");
  C(0AX); S("  max-width: 100%;"); C(0AX); S("}");
  C(0AX); S("h1, h2, h3, h4, h5, h6 {"); C(0AX); S("  margin-top: 1.4em;");
  C(0AX); S("}"); C(0AX); S("h5, h6 {");
  C(0AX); S("  font-size: 1em;"); C(0AX); S("  font-style: italic;");
  C(0AX); S("}"); C(0AX); S("h6 {");
  C(0AX); S("  font-weight: normal;"); C(0AX); S("}");
  C(0AX); S("ol, ul {"); C(0AX); S("  padding-left: 1.7em;");
  C(0AX); S("  margin-top: 1em;"); C(0AX); S("}");
  C(0AX); S("li > ol, li > ul {"); C(0AX); S("  margin-top: 0;");
  C(0AX); S("}"); C(0AX); S("blockquote {");
  C(0AX); S("  margin: 1em 0 1em 1.7em;"); C(0AX); S("  padding-left: 1em;");
  C(0AX); S("  border-left: 2px solid #e6e6e6;"); C(0AX); S("  color: #606060;");
  C(0AX); S("}"); C(0AX); S("$if(abstract)$");
  C(0AX); S("div.abstract {"); C(0AX); S("  margin: 2em 2em 2em 2em;");
  C(0AX); S("  text-align: left;"); C(0AX); S("  font-size: 85%;");
  C(0AX); S("}"); C(0AX); S("div.abstract-title {");
  C(0AX); S("  font-weight: bold;"); C(0AX); S("  text-align: center;");
  C(0AX); S("  padding: 0;"); C(0AX); S("  margin-bottom: 0.5em;");
  C(0AX); S("}"); C(0AX); S("$endif$");
  C(0AX); S("code {"); C(0AX); S("  white-space: pre-wrap;");
  C(0AX); S("  font-family: $if(monofont)$$monofont$$else$Menlo, Monaco, "); S("Consolas, 'Lucida Console', monospace$endif$;"); C(0AX);
  S("$if(monobackgroundcolor)$"); C(0AX); S("  background-color: $monobackgroundcolor$;"); C(0AX);
  S("  padding: .2em .4em;"); C(0AX); S("$endif$"); C(0AX);
  S("  font-size: 85%;"); C(0AX); S("  margin: 0;"); C(0AX);
  S("  hyphens: manual;"); C(0AX); S("}"); C(0AX);
  S("pre {"); C(0AX); S("  margin: 1em 0;"); C(0AX);
  S("$if(monobackgroundcolor)$"); C(0AX); S("  background-color: $monobackgroundcolor$;"); C(0AX);
  S("  padding: 1em;"); C(0AX); S("$endif$"); C(0AX);
  S("  overflow: auto;"); C(0AX); S("}"); C(0AX);
  S("pre code {"); C(0AX); S("  padding: 0;"); C(0AX);
  S("  overflow: visible;"); C(0AX); S("  overflow-wrap: normal;"); C(0AX);
  S("}"); C(0AX); S(".sourceCode {"); C(0AX);
  S(" background-color: transparent;"); C(0AX); S(" overflow: visible;"); C(0AX);
  S("}"); C(0AX); S("hr {"); C(0AX);
  S("  border: none;"); C(0AX); S("  border-top: 1px solid #1a1a1a;"); C(0AX);
  S("  height: 1px;"); C(0AX); S("  margin: 1em 0;"); C(0AX);
  S("}"); C(0AX); S("table {"); C(0AX);
  S("  margin: 1em 0;"); C(0AX); S("  border-collapse: collapse;"); C(0AX);
  S("  width: 100%;"); C(0AX); S("  overflow-x: auto;"); C(0AX);
  S("  display: block;"); C(0AX); S("  font-variant-numeric: lining-nums tabular-nums;"); C(0AX);
  S("}"); C(0AX); S("table caption {"); C(0AX);
  S("$if(table-caption-below)$"); C(0AX); S("  caption-side: bottom;"); C(0AX);
  S("  margin-top: 0.75em;"); C(0AX); S("$else$"); C(0AX);
  S("  margin-bottom: 0.75em;"); C(0AX); S("$endif$"); C(0AX);
  S("}"); C(0AX); S("tbody {"); C(0AX);
  S("  margin-top: 0.5em;"); C(0AX); S("  border-top: 1px solid $if(fontcolor)$$fontcolor$$else$#1a1"); S("a1a$endif$;");
  C(0AX); S("  border-bottom: 1px solid $if(fontcolor)$$fontcolor$$else$#"); S("1a1a1a$endif$;"); C(0AX);
  S("}"); C(0AX); S("th {"); C(0AX);
  S("  border-top: 1px solid $if(fontcolor)$$fontcolor$$else$#1a1"); S("a1a$endif$;"); C(0AX); S("  padding: 0.25em 0.5em 0.25em 0.5em;");
  C(0AX); S("}"); C(0AX); S("td {");
  C(0AX); S("  padding: 0.125em 0.5em 0.25em 0.5em;"); C(0AX); S("}");
  C(0AX); S("header {"); C(0AX); S("  margin-bottom: 4em;");
  C(0AX); S("  text-align: center;"); C(0AX); S("}");
  C(0AX); S("#TOC li {"); C(0AX); S("  list-style: none;");
  C(0AX); S("}"); C(0AX); S("#TOC ul {");
  C(0AX); S("  padding-left: 1.3em;"); C(0AX); S("}");
  C(0AX); S("#TOC > ul {"); C(0AX); S("  padding-left: 0;");
  C(0AX); S("}"); C(0AX); S("#TOC a:not(:hover) {");
  C(0AX); S("  text-decoration: none;"); C(0AX); S("}");
  C(0AX); S("$endif$"); C(0AX); S("span.smallcaps{font-variant: small-caps;}");
  C(0AX); S("div.columns{display: flex; gap: 1.5em;}"); C(0AX); S("div.column{flex: auto;}");
  C(0AX); S("@media screen {"); C(0AX); S("div.columns{gap: min(4vw, 1.5em);}");
  C(0AX); S("div.column{overflow-x: auto;}"); C(0AX); S("}");
  C(0AX); S("div.hanging-indent{margin-left: 1.5em; text-indent: -1.5em;}"); C(0AX); S("/* The extra [class] is a hack that increases specificity en");
  S("ough to"); C(0AX); S("   override a similar rule in reveal.js */"); C(0AX);
  S("ul.task-list[class]{list-style: none;}"); C(0AX); S("ul.task-list li input[type="); C(22X);
  S("checkbox"); C(22X); S("] {"); C(0AX);
  S("  font-size: inherit;"); C(0AX); S("  width: 0.8em;"); C(0AX);
  S("  margin: 0 0.8em 0.2em -1.6em;"); C(0AX); S("  vertical-align: middle;"); C(0AX);
  S("}"); C(0AX); S("$if(quotes)$"); C(0AX);
  S("q { quotes: "); C(22X); C(0E2X); C(80X);
  C(9CX); C(22X); S(" "); C(22X);
  C(0E2X); C(80X); C(9DX); C(22X);
  S(" "); C(22X); C(0E2X); C(80X);
  C(98X); C(22X); S(" "); C(22X);
  C(0E2X); C(80X); C(99X); C(22X);
  S("; }"); C(0AX); S("$endif$"); C(0AX);
  S("$if(displaymath-css)$"); C(0AX); S(".display.math{display: block; text-align: center; margin: 0."); S("5rem auto;}");
  C(0AX); S("$endif$"); C(0AX); S("$if(highlighting-css)$");
  C(0AX); S("/* CSS for syntax highlighting */"); C(0AX); S("$highlighting-css$");
  C(0AX); S("$endif$"); C(0AX); S("$if(csl-css)$");
  C(0AX); S("$styles.citations.html()$"); C(0AX); S("$endif$");
  C(0AX)
END T1;

PROCEDURE T2;
BEGIN
  S("/* CSS for citations */"); C(0AX); S("div.csl-bib-body { }"); C(0AX);
  S("div.csl-entry {"); C(0AX); S("  clear: both;"); C(0AX);
  S("$if(csl-entry-spacing)$"); C(0AX); S("  margin-bottom: $csl-entry-spacing$;"); C(0AX);
  S("$endif$"); C(0AX); S("}"); C(0AX);
  S(".hanging-indent div.csl-entry {"); C(0AX); S("  margin-left:2em;"); C(0AX);
  S("  text-indent:-2em;"); C(0AX); S("}"); C(0AX);
  S("div.csl-left-margin {"); C(0AX); S("  min-width:2em;"); C(0AX);
  S("  float:left;"); C(0AX); S("}"); C(0AX);
  S("div.csl-right-inline {"); C(0AX); S("  margin-left:2em;"); C(0AX);
  S("  padding-left:1em;"); C(0AX); S("}"); C(0AX);
  S("div.csl-indent {"); C(0AX); S("  margin-left: 2em;"); C(0AX);
  S("}"); C(0AX)
END T2;

PROCEDURE T3;
BEGIN
  S("$if(pandoc-version)$"); C(0AX); S(".\"); C(22X);
  S(" Automatically generated by Pandoc $pandoc-version$"); C(0AX); S(".\"); C(22X);
  C(0AX); S("$endif$"); C(0AX); S(".\");
  C(22X); S(" **** Custom macro definitions *****************************"); S("****"); C(0AX);
  S(".\"); C(22X); S(" * Super/subscript"); C(0AX);
  S(".\"); C(22X); S(" (https://lists.gnu.org/archive/html/groff/2012-07/msg00046."); S("html)");
  C(0AX); S(".ds { \v'-0.3m'\\s[\\n[.s]*9u/12u]"); C(0AX); S(".ds } \s0\v'0.3m'");
  C(0AX); S(".ds < \v'0.3m'\s[\\n[.s]*9u/12u]"); C(0AX); S(".ds > \s0\v'-0.3m'");
  C(0AX); S(".\"); C(22X); S(" * Horizontal line");
  C(0AX); S(".de HLINE"); C(0AX); S(".LP");
  C(0AX); S(".ce"); C(0AX); S("\l'20'");
  C(0AX); S(".."); C(0AX); S("$if(highlighting-macros)$");
  C(0AX); S(".\"); C(22X); S(" * Syntax highlighting macros");
  C(0AX); S("$highlighting-macros$"); C(0AX); S("$endif$");
  C(0AX); S(".\"); C(22X); S(" **** Settings *********************************************");
  S("****"); C(0AX); S(".\"); C(22X);
  S(" text width"); C(0AX); S(".nr LL 5.5i"); C(0AX);
  S(".\"); C(22X); S(" left margin"); C(0AX);
  S(".nr PO 1.25i"); C(0AX); S(".\"); C(22X);
  S(" top margin"); C(0AX); S(".nr HM 1.25i"); C(0AX);
  S(".\"); C(22X); S(" bottom margin"); C(0AX);
  S(".nr FM 1.25i"); C(0AX); S(".\"); C(22X);
  S(" header/footer width"); C(0AX); S(".nr LT \n[LL]"); C(0AX);
  S(".\"); C(22X); S(" point size"); C(0AX);
  S(".nr PS $if(pointsize)$$pointsize$$else$10p$endif$"); C(0AX); S(".\"); C(22X);
  S(" line height"); C(0AX); S(".nr VS $if(lineheight)$$lineheight$$else$12p$endif$"); C(0AX);
  S(".\"); C(22X); S(" font family: A, BM, H, HN, N, P, T, ZCM"); C(0AX);
  S(".fam $if(fontfamily)$$fontfamily$$else$T$endif$"); C(0AX); S(".\"); C(22X);
  S(" paragraph indent"); C(0AX); S(".nr PI $if(indent)$$indent$$else$0m$endif$"); C(0AX);
  S(".\"); C(22X); S(" interparagraph space"); C(0AX);
  S(".nr PD 0.4v"); C(0AX); S(".\"); C(22X);
  S(" footnote width"); C(0AX); S(".nr FL \n[LL]"); C(0AX);
  S(".\"); C(22X); S(" footnote point size"); C(0AX);
  S(".nr FPS (\n[PS] - 2000)"); C(0AX); S("$if(papersize)$"); C(0AX);
  S(".\"); C(22X); S(" paper size"); C(0AX);
  S(".ds paper $papersize$"); C(0AX); S("$endif$"); C(0AX);
  S(".\"); C(22X); S(" color used for strikeout"); C(0AX);
  S(".defcolor strikecolor rgb 0.7 0.7 0.7"); C(0AX); S(".\"); C(22X);
  S(" point size difference between heading levels"); C(0AX); S(".nr PSINCR 1p"); C(0AX);
  S(".\"); C(22X); S(" heading level above which point size no longer changes"); C(0AX);
  S(".nr GROWPS 2"); C(0AX); S(".\"); C(22X);
  S(" comment these out if you want a dot after section numbers:"); C(0AX); S(".als SN SN-NO-DOT"); C(0AX);
  S(".als SN-STYLE SN-NO-DOT"); C(0AX); S(".\"); C(22X);
  S(" page numbers in footer, centered"); C(0AX); S(".ds CH"); C(0AX);
  S(".ds CF %"); C(0AX); S("$if(adjusting)$"); C(0AX);
  S(".ad $adjusting$"); C(0AX); S("$endif$"); C(0AX);
  S("$if(hyphenate)$"); C(0AX); S(".hy"); C(0AX);
  S("$else$"); C(0AX); S(".nh"); C(0AX);
  S("$endif$"); C(0AX); S("$if(has-inline-math)$"); C(0AX);
  S(".EQ"); C(0AX); S("delim @@"); C(0AX);
  S(".EN"); C(0AX); S("$endif$"); C(0AX);
  S("$if(pdf-engine)$"); C(0AX); S(".\"); C(22X);
  S(" color for links (rgb)"); C(0AX); S(".ds PDFHREF.COLOUR   0.35 0.00 0.60"); C(0AX);
  S(".\"); C(22X); S(" border for links (default none)"); C(0AX);
  S(".ds PDFHREF.BORDER   0 0 0"); C(0AX); S(".\"); C(22X);
  S(" pdf outline fold level"); C(0AX); S(".nr PDFOUTLINE.FOLDLEVEL 3"); C(0AX);
  S(".\"); C(22X); S(" start out in outline view"); C(0AX);
  S(".pdfview /PageMode /UseOutlines"); C(0AX); S(".\"); C(22X);
  S(" ***********************************************************"); S("****"); C(0AX); S(".\");
  C(22X); S(" PDF metadata"); C(0AX); S(".pdfinfo /Title ");
  C(22X); S("$title-meta$"); C(22X); C(0AX);
  S(".pdfinfo /Author "); C(22X); S("$author-meta$"); C(22X);
  C(0AX); S("$endif$"); C(0AX); S("$for(header-includes)$");
  C(0AX); S("$header-includes$"); C(0AX); S("$endfor$");
  C(0AX); S("$if(title)$"); C(0AX); S(".TL");
  C(0AX); S("$title$"); C(0AX); S("$endif$");
  C(0AX); S("$for(author)$"); C(0AX); S(".AU");
  C(0AX); S("$author$"); C(0AX); S("$endfor$");
  C(0AX); S("$if(date)$"); C(0AX); S(".AU");
  C(0AX); S(".sp 0.5"); C(0AX); S(".ft R");
  C(0AX); S("$date$"); C(0AX); S("$endif$");
  C(0AX); S("$if(abstract)$"); C(0AX); S(".AB");
  C(0AX); S("$abstract$"); C(0AX); S(".AE");
  C(0AX); S("$endif$"); C(0AX); S(".\");
  C(22X); S(" 1 column (use .2C for two column)"); C(0AX); S(".1C");
  C(0AX); S("$for(include-before)$"); C(0AX); S("$include-before$");
  C(0AX); S("$endfor$"); C(0AX); S("$body$");
  C(0AX); S("$if(toc)$"); C(0AX); S(".TC");
  C(0AX); S("$endif$"); C(0AX); S("$for(include-after)$");
  C(0AX); S("$include-after$"); C(0AX); S("$endfor$");
  C(0AX); S(".pdfsync"); C(0AX)
END T3;

PROCEDURE T4;
BEGIN
  S(".\"); C(22X); S(" Written by podoc's default mom template, for groff 1.23 and"); S(" later");
  C(0AX); S("$if(title)$"); C(0AX); S(".TITLE ");
  C(22X); S("$title$"); C(22X); C(0AX);
  S("$endif$"); C(0AX); S("$if(subtitle)$"); C(0AX);
  S(".SUBTITLE "); C(22X); S("$subtitle$"); C(22X);
  C(0AX); S("$endif$"); C(0AX); S("$if(author)$");
  C(0AX); S(".AUTHOR$for(author)$ "); C(22X); S("$author$");
  C(22X); S("$endfor$"); C(0AX); S("$endif$");
  C(0AX); S("$if(date)$"); C(0AX); S(".MISC ");
  C(22X); S("$date$"); C(22X); C(0AX);
  S("$endif$"); C(0AX); S("$if(covers)$"); C(0AX);
  S(".COVER$if(title)$ TITLE$endif$$if(subtitle)$ SUBTITLE$endif$"); S("$if(author)$ AUTHOR$endif$$if(date)$ MISC$endif$"); C(0AX); S("$endif$");
  C(0AX); S("$if(doctype)$"); C(0AX); S(".DOCTYPE $doctype$");
  C(0AX); S("$endif$"); C(0AX); S(".\");
  C(22X); S(" PAPER comes before PRINTSTYLE, which sets the page from it"); C(0AX); S("$if(papersize)$");
  C(0AX); S(".PAPER $papersize/uppercase$"); C(0AX); S("$endif$");
  C(0AX); S(".PRINTSTYLE $if(printstyle)$$printstyle$$else$TYPESET$endif$"); C(0AX); S("$if(margin-left)$");
  C(0AX); S(".L_MARGIN $margin-left$"); C(0AX); S("$endif$");
  C(0AX); S("$if(margin-right)$"); C(0AX); S(".R_MARGIN $margin-right$");
  C(0AX); S("$endif$"); C(0AX); S("$if(margin-top)$");
  C(0AX); S(".T_MARGIN $margin-top$"); C(0AX); S("$endif$");
  C(0AX); S("$if(margin-bottom)$"); C(0AX); S(".B_MARGIN $margin-bottom$");
  C(0AX); S("$endif$"); C(0AX); S("$if(fontfamily)$");
  C(0AX); S(".FAMILY $fontfamily$"); C(0AX); S("$endif$");
  C(0AX); S("$if(pointsize)$"); C(0AX); S(".PT_SIZE $pointsize$");
  C(0AX); S("$endif$"); C(0AX); S("$if(lineheight)$");
  C(0AX); S(".LS $lineheight$"); C(0AX); S("$endif$");
  C(0AX); S("$if(columns)$"); C(0AX); S(".COLUMNS $columns$ $if(column-gutter)$$column-gutter$$else$1");
  S(".5P$endif$"); C(0AX); S("$endif$"); C(0AX);
  S("$if(numbersections)$"); C(0AX); S(".HEADING_STYLE 1 NUMBER"); C(0AX);
  S(".HEADING_STYLE 2 NUMBER"); C(0AX); S(".HEADING_STYLE 3 NUMBER"); C(0AX);
  S(".HEADING_STYLE 4 NUMBER"); C(0AX); S(".HEADING_STYLE 5 NUMBER"); C(0AX);
  S(".HEADING_STYLE 6 NUMBER"); C(0AX); S("$endif$"); C(0AX);
  S("$if(linkcolor)$"); C(0AX); S(".PDF_LINK_COLOR $linkcolor$"); C(0AX);
  S("$endif$"); C(0AX); S(".\"); C(22X);
  S(" code blocks (QUOTE) at the left margin unless code-indent i"); S("s set"); C(0AX); S(".QUOTE_INDENT $if(code-indent)$$code-indent$$else$0$endif$");
  C(0AX); S(".\"); C(22X); S(" the colour for strikeout");
  C(0AX); S(".defcolor strikecolor rgb 0.7 0.7 0.7"); C(0AX); S(".\");
  C(22X); S(" captions below images"); C(0AX); S(".CAPTION_AFTER_LABEL IMG");
  C(0AX); S("$if(title-meta)$"); C(0AX); S(".PDF_TITLE ");
  C(22X); S("$title-meta$"); C(22X); C(0AX);
  S("$endif$"); C(0AX); S("$for(header-includes)$"); C(0AX);
  S("$header-includes$"); C(0AX); S("$endfor$"); C(0AX);
  S("$if(toc)$"); C(0AX); S("$if(toc-title)$"); C(0AX);
  S(".TOC_HEADER_STRING "); C(22X); S("$toc-title$"); C(22X);
  C(0AX); S("$endif$"); C(0AX); S(".AUTO_RELOCATE_TOC$if(covers)$$else$ TOP$endif$");
  C(0AX); S("$endif$"); C(0AX); S(".START");
  C(0AX); S("$if(abstract)$"); C(0AX); S(".BLOCKQUOTE");
  C(0AX); S("$abstract$"); C(0AX); S(".BLOCKQUOTE OFF");
  C(0AX); S("$endif$"); C(0AX); S("$for(include-before)$");
  C(0AX); S("$include-before$"); C(0AX); S("$endfor$");
  C(0AX); S("$body$"); C(0AX); S("$for(include-after)$");
  C(0AX); S("$include-after$"); C(0AX); S("$endfor$");
  C(0AX); S("$if(toc)$"); C(0AX); S(".\");
  C(22X); S(" groff 1.23 leaves vertical traps off after endnotes"); C(0AX); S(".if \n[.vpt]=0 .vpt");
  C(0AX); S(".TOC"); C(0AX); S("$endif$");
  C(0AX)
END T4;

PROCEDURE T5;
BEGIN
  S("$if(tagging)$"); C(0AX); S("\setupbackend[format=pdf/ua-2]"); C(0AX);
  S("\enabledirectives[backend.usetags=mkiv]"); C(0AX); S("\setuptagging[state=start]"); C(0AX);
  S("$endif$"); C(0AX); S("$if(context-lang)$"); C(0AX);
  S("\mainlanguage[$context-lang$]"); C(0AX); S("$endif$"); C(0AX);
  S("$if(context-dir)$"); C(0AX); S("\setupalign[$context-dir$]"); C(0AX);
  S("\setupdirections[bidi=on,method=two]"); C(0AX); S("$endif$"); C(0AX);
  S("% Enable hyperlinks"); C(0AX); S("\setupinteraction"); C(0AX);
  S("  [state=start,"); C(0AX); S("$if(title)$"); C(0AX);
  S("  title={$title$},"); C(0AX); S("$endif$"); C(0AX);
  S("$if(subtitle)$"); C(0AX); S("  subtitle={$subtitle$},"); C(0AX);
  S("$endif$"); C(0AX); S("$if(author)$"); C(0AX);
  S("  author={$for(author)$$author$$sep$; $endfor$},"); C(0AX); S("$endif$"); C(0AX);
  S("$if(keywords)$"); C(0AX); S("  keyword={$for(keywords)$$keywords$$sep$; $endfor$},"); C(0AX);
  S("$endif$"); C(0AX); S("  style=$linkstyle$,"); C(0AX);
  S("  color=$linkcolor$,"); C(0AX); S("  contrastcolor=$linkcontrastcolor$]"); C(0AX);
  S("\setupurl[style=$urlstyle$]"); C(0AX); C(0AX); S("% make chapter, section bookmarks visible when opening docum");
  S("ent"); C(0AX); S("\placebookmarks[chapter, section, subsection, subsubsection,"); S(" subsubsubsection, subsubsubsubsection][chapter, section]");
  C(0AX); S("\setupinteractionscreen[option={bookmark,title}]"); C(0AX); C(0AX);
  S("$if(papersize)$"); C(0AX); S("\setuppapersize[$for(papersize)$$papersize$$sep$,$endfor$]"); C(0AX);
  S("$endif$"); C(0AX); S("$if(layout)$"); C(0AX);
  S("\setuplayout[$for(layout)$$layout$$sep$,$endfor$]"); C(0AX); S("$endif$"); C(0AX);
  S("$if(pagenumbering)$"); C(0AX); S("\setuppagenumbering[$for(pagenumbering)$$pagenumbering$$sep$"); S(",$endfor$]");
  C(0AX); S("$else$"); C(0AX); S("\setuppagenumbering[location={footer,middle}]");
  C(0AX); S("$endif$"); C(0AX); S("$if(pdfa)$");
  C(0AX); S("% attempt to generate PDF/A"); C(0AX); S("\setupbackend");
  C(0AX); S("  [format=PDF/A-$pdfa$,"); C(0AX); S("   profile={$if(pdfaiccprofile)$$for(pdfaiccprofile)$$pdfaic");
  S("cprofile$$sep$,$endfor$$else$sRGB.icc$endif$},"); C(0AX); S("   intent=$if(pdfaintent)$$pdfaintent$$else$sRGB IEC61966-2."); S("1$endif$]");
  C(0AX); S("$endif$"); C(0AX); S("\setupstructure[state=start,method=auto]");
  C(0AX); C(0AX); S("% use microtypography"); C(0AX);
  S("\definefontfeature[default][default][script=latn, protrusion"); S("=quality, expansion=quality, itlc=yes, textitalics=yes, onum"); S("=yes, pnum=yes]"); C(0AX);
  S("\definefontfeature[default:tnum][default][tnum=yes, pnum=no]"); C(0AX); S("\definefontfeature[smallcaps][script=latn, protrusion=qualit"); S("y, expansion=quality, smcp=yes, onum=yes, pnum=yes]");
  C(0AX); S("\setupalign[hz,hanging]"); C(0AX); S("\setupitaliccorrection[global, always]");
  C(0AX); C(0AX); S("\setupbodyfontenvironment[default][em=italic] % use italic a"); S("s em, not slanted");
  C(0AX); C(0AX); S("$-- set up font fallbacks"); C(0AX);
  S("$for(mainfontfallback)$"); C(0AX); S("\definefallbackfamily[mainface][rm][$mainfontfallback/nowrap"); S("$][range=0x0000-0xFFFF, check=yes, force=no]");
  C(0AX); S("$endfor$"); C(0AX); S("$for(sansfontfallback)$");
  C(0AX); S("\definefallbackfamily[mainface][ss][$sansfontfallback/nowrap"); S("$][range=0x0000-0xFFFF, check=yes, force=no]"); C(0AX);
  S("$endfor$"); C(0AX); S("$for(monofontfallback)$"); C(0AX);
  S("\definefallbackfamily[mainface][tt][$monofontfallback/nowrap"); S("$][range=0x0000-0xFFFF, check=yes, force=no]"); C(0AX); S("$endfor$");
  C(0AX); S("\definefallbackfamily[mainface][rm][CMU Serif][preset=range:"); S("greek, force=yes]"); C(0AX);
  S("\definefontfamily[mainface][rm][$if(mainfont)$$mainfont/nowr"); S("ap$$else$Latin Modern Roman$endif$]"); C(0AX); S("\definefontfamily[mainface][mm][$if(mathfont)$$mathfont/nowr");
  S("ap$$else$Latin Modern Math$endif$]"); C(0AX); S("\definefontfamily[mainface][ss][$if(sansfont)$$sansfont/nowr"); S("ap$$else$Latin Modern Sans$endif$]");
  C(0AX); S("\definefontfamily[mainface][tt][$if(monofont)$$monofont/nowr"); S("ap$$else$Latin Modern Typewriter$endif$][features=none]"); C(0AX);
  S("\setupbodyfont[mainface$if(fontsize)$,$fontsize$$endif$]"); C(0AX); C(0AX); S("\setupwhitespace[$if(whitespace)$$whitespace$$else$medium$en");
  S("dif$]"); C(0AX); S("$if(indenting)$"); C(0AX);
  S("\setupindenting[$for(indenting)$$indenting$$sep$,$endfor$]"); C(0AX); S("$endif$"); C(0AX);
  S("$if(interlinespace)$"); C(0AX); S("\setupinterlinespace[$for(interlinespace)$$interlinespace$$s"); S("ep$,$endfor$]");
  C(0AX); S("$endif$"); C(0AX); C(0AX);
  S("\setuphead[chapter]            [style=\tfd\setupinterlinespa"); S("ce,header=empty]"); C(0AX); S("\setuphead[section]            [style=\tfc\setupinterlinespa");
  S("ce]"); C(0AX); S("\setuphead[subsection]         [style=\tfb\setupinterlinespa"); S("ce]");
  C(0AX); S("\setuphead[subsubsection]      [style=\bf]"); C(0AX); S("\setuphead[subsubsubsection]   [style=\sc]");
  C(0AX); S("\setuphead[subsubsubsubsection][style=\it]"); C(0AX); C(0AX);
  S("\definesectionlevels"); C(0AX); S("   [default]"); C(0AX);
  S("   [section, subsection, subsubsection, subsubsubsection, su"); S("bsubsubsubsection]"); C(0AX); C(0AX);
  S("$if(headertext)$"); C(0AX); S("\setupheadertexts$for(headertext)$[$headertext$]$endfor$"); C(0AX);
  S("$endif$"); C(0AX); S("$if(footertext)$"); C(0AX);
  S("\setupfootertexts$for(footertext)$[$footertext$]$endfor$"); C(0AX); S("$endif$"); C(0AX);
  S("$if(number-sections)$"); C(0AX); S("$else$"); C(0AX);
  S("\setuphead[chapter, section, subsection, subsubsection, subs"); S("ubsubsection, subsubsubsubsection][number=no]"); C(0AX); S("$endif$");
  C(0AX); C(0AX); S("\definedescription"); C(0AX);
  S("  [description]"); C(0AX); S("  [headstyle=bold, style=normal, location=hanging, width=bro"); S("ad, margin=1cm, alternative=hanging]");
  C(0AX); C(0AX); S("\setupitemize[autointro]    % prevent orphan list intro"); C(0AX);
  S("\setupitemize[indentnext=no]"); C(0AX); C(0AX); S("\defineitemgroup[enumerate]");
  C(0AX); S("\setupenumerate[each][fit][itemalign=left,distance=.5em,styl"); S("e={\feature[+][default:tnum]}]"); C(0AX);
  C(0AX); S("\setupfloat[figure][default={here,nonumber}]"); C(0AX); S("\setupfloat[table][default={here,nonumber}]");
  C(0AX); C(0AX); S("\setupxtable[frame=off]"); C(0AX);
  S("\setupxtable[head][topframe=on]"); C(0AX); S("\setupxtable[body][]"); C(0AX);
  S("\setupxtable[foot][]"); C(0AX); S("\setupxtable[lastrow][bottomframe=on]"); C(0AX);
  C(0AX); S("$if(emphasis-commands)$"); C(0AX); S("$emphasis-commands$");
  C(0AX); S("$endif$"); C(0AX); S("$if(highlighting-commands)$");
  C(0AX); S("$highlighting-commands$"); C(0AX); S("$endif$");
  C(0AX); S("$if(csl-refs)$"); C(0AX); S("\definemeasure[cslhangindent][1.5em]");
  C(0AX); S("\definenarrower[hangingreferences][left=\measure{cslhanginde"); S("nt}]"); C(0AX);
  S("\definestartstop [cslreferences] ["); C(0AX); C(09X); S("$if(csl-hanging-indent)$");
  C(0AX); C(09X); S("before={%"); C(0AX);
  C(09X); S("  \starthangingreferences[left]"); C(0AX); S("      \setupindenting[-\leftskip,yes,first]");
  C(0AX); S("      \doindentation"); C(0AX); S("  ");
  C(09X); S("},"); C(0AX); S("  ");
  C(09X); S("after=\stophangingreferences,"); C(0AX); C(09X);
  S("$endif$"); C(0AX); S("]"); C(0AX);
  S("$endif$"); C(0AX); S("$if(includesource)$"); C(0AX);
  S("$for(sourcefile)$"); C(0AX); S("\attachment[file=$curdir$/$sourcefile$,method=hidden]"); C(0AX);
  S("$endfor$"); C(0AX); S("$endif$"); C(0AX);
  S("$for(header-includes)$"); C(0AX); S("$header-includes$"); C(0AX);
  S("$endfor$"); C(0AX); C(0AX); S("\starttext");
  C(0AX); S("$if(title)$"); C(0AX); S("\startalignment[middle]");
  C(0AX); S("  {\tfd\setupinterlinespace $title$}"); C(0AX); S("$if(subtitle)$");
  C(0AX); S("  \smallskip"); C(0AX); S("  {\tfa\setupinterlinespace $subtitle$}");
  C(0AX); S("$endif$"); C(0AX); S("$if(author)$");
  C(0AX); S("  \smallskip"); C(0AX); S("  {\tfa\setupinterlinespace $for(author)$$author$$sep$\crlf ");
  S("$endfor$}"); C(0AX); S("$endif$"); C(0AX);
  S("$if(date)$"); C(0AX); S("  \smallskip"); C(0AX);
  S("  {\tfa\setupinterlinespace $date$}"); C(0AX); S("$endif$"); C(0AX);
  S("  \bigskip"); C(0AX); S("\stopalignment"); C(0AX);
  S("$endif$"); C(0AX); S("$if(abstract)$"); C(0AX);
  S("\midaligned{\it Abstract}"); C(0AX); S("\startnarrower[2*middle]"); C(0AX);
  S("$abstract$"); C(0AX); S("\stopnarrower"); C(0AX);
  S("\blank[big]"); C(0AX); S("$endif$"); C(0AX);
  S("$for(include-before)$"); C(0AX); S("$include-before$"); C(0AX);
  S("$endfor$"); C(0AX); S("$if(toc)$"); C(0AX);
  S("\completecontent"); C(0AX); S("$endif$"); C(0AX);
  S("$if(lof)$"); C(0AX); S("\completelistoffigures"); C(0AX);
  S("$endif$"); C(0AX); S("$if(lot)$"); C(0AX);
  S("\completelistoftables"); C(0AX); S("$endif$"); C(0AX);
  C(0AX); S("$body$"); C(0AX); C(0AX);
  S("$for(include-after)$"); C(0AX); S("$include-after$"); C(0AX);
  S("$endfor$"); C(0AX); S("\stoptext"); C(0AX)
END T5;

PROCEDURE T6;
BEGIN
  S("$if(titleblock)$"); C(0AX); S("$titleblock$"); C(0AX);
  C(0AX); S("$endif$"); C(0AX); S("$for(header-includes)$");
  C(0AX); S("$header-includes$"); C(0AX); C(0AX);
  S("$endfor$"); C(0AX); S("$for(include-before)$"); C(0AX);
  S("$include-before$"); C(0AX); C(0AX); S("$endfor$");
  C(0AX); S("$if(toc)$"); C(0AX); S("$table-of-contents$");
  C(0AX); C(0AX); S("$endif$"); C(0AX);
  S("$body$"); C(0AX); S("$for(include-after)$"); C(0AX);
  C(0AX); S("$include-after$"); C(0AX); S("$endfor$");
  C(0AX)
END T6;

PROCEDURE T7;
BEGIN
  S("$if(titleblock)$"); C(0AX); S("$titleblock$"); C(0AX);
  C(0AX); S("$endif$"); C(0AX); S("$for(header-includes)$");
  C(0AX); S("$header-includes$"); C(0AX); C(0AX);
  S("$endfor$"); C(0AX); S("$for(include-before)$"); C(0AX);
  S("$include-before$"); C(0AX); C(0AX); S("$endfor$");
  C(0AX); S("$if(toc)$"); C(0AX); S("$table-of-contents$");
  C(0AX); C(0AX); S("$endif$"); C(0AX);
  S("$body$"); C(0AX); S("$for(include-after)$"); C(0AX);
  C(0AX); S("$include-after$"); C(0AX); S("$endfor$");
  C(0AX)
END T7;

(* Whether there is a default template or partial called name
   ("default.html5", "styles.html", ...); if there is, it is
   text[0 .. len-1] *)
PROCEDURE Get*(name: ARRAY OF CHAR; VAR text: PdIO.Text; VAR len: LONGINT): BOOLEAN;
BEGIN
  t := NIL; n := 0;
  IF name = "default.html5" THEN T0
  ELSIF name = "styles.html" THEN T1
  ELSIF name = "styles.citations.html" THEN T2
  ELSIF name = "default.ms" THEN T3
  ELSIF name = "default.mom" THEN T4
  ELSIF name = "default.context" THEN T5
  ELSIF name = "default.markdown" THEN T6
  ELSIF name = "default.plain" THEN T7
  ELSE RETURN FALSE
  END;
  text := t; len := n; t := NIL;
  RETURN TRUE
END Get;

END PdDefaults.
