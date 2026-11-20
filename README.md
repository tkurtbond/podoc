# podoc

A proof of concept: the parts of [pandoc](https://pandoc.org) that a
set of writing builds need, as one Oberon-2 program built with the
Peaseblossom Oberon Compiler (`poc`). It is to read pandoc markdown
with YAML metadata and write HTML, groff `ms`, ConTeXt and markdown,
and make PDFs with `pdfroff`, `groff` or `context`, on systems too
small or too unusual for pandoc.

The scope and the reasons for it are in
[docs/research/podoc-scope.md](docs/research/podoc-scope.md); the plan,
phase by phase, and how far it has got, in [PLAN.md](PLAN.md). Known
differences from pandoc are in
[docs/user/differences.md](docs/user/differences.md).

## Building

It needs `poc` and the poc libraries ArgParser, Ropes and pounicode,
installed under both size models in `~/.local/lib/poc` (`POCLIBDIR`).

    make            # build/O2/podoc and build/OC/podoc
    make test       # the unit and case tests, under both
    make clean

## Using

The command line is pandoc's:

    podoc [OPTIONS] [FILES]

podoc reads pandoc markdown with YAML metadata and writes `html`,
`ms`, `context`, `markdown` or `json` (`-t`, or `-o`'s extension, as
pandoc infers it), standalone with `-s` and pandoc's templates. `podoc
--help` lists the options. Not done yet: includes (`-F
pandoc-include`), the built-in filters and PDF output. Where podoc
differs from pandoc is in
[docs/user/differences.md](docs/user/differences.md).

## License

BSD 3-Clause; see [LICENSE](LICENSE).
