# deslop

A fast single line of code evaluator

## Use

Fitness:

```bash
$ deslop hello.c
1 | 1.00 | #include <stdio.h>
2 | 0.00 |
3 | 0.89 | int main(void)
4 | 0.12 | {
5 | 1.00 |     printf("hello, world\n");
6 | 1.00 |     return 0;
7 | 1.00 | }
```

Categories:

```
$ deslop -t tags.txt hello.c
1 | awesomesauce | #include <stdio.h>
2 | mediocre     |
3 | typesafe     | int main(void)
4 | mediocre     | {
5 | awesomesauce |     printf("hello, world\n");
6 | typesafe     |     return 0;
7 | typesafe     | }
```

## Real Time Editor Feedback

Besides the obvious use-case to grade generated code;
The LSP interface can provide visual feedback in real time

[Demo Video#1](./demo/xorcery-nvim.webm)
[Demo Video#2](./demo/xorcery-vscodium.webm)

(The demos shows a screen capture of editors; code being edited in real time,
each line has it's own background color, and a tag next to the left line-number gutter)

## Manual

```bash
deslop -h

  usage: deslop [options] [FILE]
  when no FILE is provided, context is read from STDIN

  Default mode:
    Good vs. Bad: 1.0 ... -1.0

  Categorical Mode:
    Takes an additional list of categories as input,
    see tag option "-t"

  -n NUMBER             Single line run
  -t TAGFILE            Read whitespace delimited tags from TAGFILE
  -r PATH               Recursive grade path (STDIN & FILE is ignored)
  -s                    Show only a summarize -r output
  --json|-j             Output structured json
  -l                    Start LSP server mode (-n and FILE ignored)
  -X                    dumps Json request to stdout and exits

  Deslop is compatible with `/v1/systemone` spec

  SYSTEMONE_URL=http://localhost:8080/v1/systemone
```


Note: `-r` and `-l` will not be implemented yet.

## Modes

### Quality

Each LOC get's a simple good or bad grading in range of -1 to 1.

### Labels

Initial naïve tags listed in order from `good` to `bad`

- `godmode`
- `memorysafe`
- `awesomesauce`
- `typesafe`
- `mediocre`
- `noob`
- `workaround`
- `syntax_error`
- `slop`
- `malicious`

## License

AGPL-version-3-or-later

All wrongs reversed - 2026 - Decent Labs

