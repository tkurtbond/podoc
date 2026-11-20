# podoc

A proof of concept: the parts of [pandoc](https://pandoc.org) that a
set of writing builds need, as one Oberon-2 program built with the
Peaseblossom Oberon Compiler (`poc`). It reads pandoc markdown
with YAML metadata, writes HTML, groff `ms`, ConTeXt and markdown,
and makes PDFs with `pdfroff`, `groff` or `context`, on systems too
small or too unusual for pandoc.

How to build, install and use it is in
[docs/user/podoc.md](docs/user/podoc.md); known differences from
pandoc are in [docs/user/differences.md](docs/user/differences.md).
The scope and the reasons for it are in
[docs/research/podoc-scope.md](docs/research/podoc-scope.md), and the
plan, phase by phase, in [PLAN.md](PLAN.md).

## Building

It needs `poc` and the poc libraries ArgParser, Ropes and pounicode,
installed under both size models in `~/.local/lib/poc` (`POCLIBDIR`),
and GNU make. It builds and passes its tests on Linux, FreeBSD and
NetBSD.

    make            # build/O2/podoc and build/OC/podoc
    make test       # the unit and case tests, under both
    make install    # podoc and subs2yaml in ~/.local/bin (PREFIX)
    make clean

## Using

The command line is pandoc's:

    podoc [OPTIONS] [FILES]

podoc reads pandoc markdown with YAML metadata. It writes `html`, `ms`,
`context`, `markdown` or `json` (chosen by `-t`, or by `-o`'s extension
as pandoc infers it), standalone with `-s` and pandoc's templates. It
makes PDF with `pdfroff`, `groff` or `context`, and it runs built-in
code for `pandoc-include` and the Lua filters the writing builds use.
`podoc --help` lists the options.

## License

BSD 3-Clause; see [LICENSE](LICENSE). The default templates are
pandoc's, used under their BSD 3-Clause licence; see
[data/templates/README](data/templates/README).
