# Differences from pandoc

Where podoc deliberately, or for now, does not do what pandoc 3.10
does. Output that differs from pandoc's but is equivalent (decision 3
in PLAN.md) is listed by the writer.

## The command line

- An unknown option, or an option missing its argument, ends podoc
  with exit status 2 (ArgParser's), where pandoc's is 6. Every other
  error uses pandoc's exit status: 1 for a file that cannot be read or
  written, 22 for an unknown output format.
- `--help` lists podoc's options in ArgParser's form, and error
  messages are podoc's own wording.
- `-t source` writes the input as the reader would see it (joined,
  CRs removed, tabs expanded); pandoc has no such format.

## Input

- Input that is not valid UTF-8 is read as it is; pandoc reads it as
  Latin-1, with a warning.
- Input file names are not URLs: pandoc fetches `http:` and `https:`
  inputs.

## The markdown reader

podoc reads the markdown the user's documents use. It does not yet
read:

- grid tables, or table cells that hold blank lines;
- the `%` title block;
- raw TeX blocks, LaTeX environments and macros, and the commands
  pandoc's LaTeX reader reads specially (podoc keeps every `\command`
  with its options and arguments as a raw TeX inline);
- citations, example references (`@label`), wikilinks and base64
  data URIs.

A table's column widths count East Asian wide and full-width
characters as two and combining marks as none, which approximates
pandoc's character widths.
