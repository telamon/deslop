# deslop

A fast "system-one" single line of code evaluator

## Use

Fitness:

```bash
$ deslop hello.c
1 | 0.96 | #include <stdio.h>
2 | 0.49 |
3 | 0.95 | int main(void)
4 | 0.88 | {
5 | 0.89 |     printf("hello, world\n");
6 | 0.57 |
7 | 0.96 |     return 0;
8 | 0.92 | }
```

Categories:

```bash
$ deslop -t tags.txt hello.c
1 | awesomesauce | #include <stdio.h>
2 | mediocre     |
3 | typesafe     | int main(void)
4 | mediocre     | {
5 | awesomesauce |     printf("hello, world\n");
6 | typesafe     |     return 0;
7 | typesafe     | }
```

Summary `-s`:

```bash
$ deslop -t tags.txt -s hello.c
LOC: 8
Score: 0.85 ( 5 / 3 )

Tag          Count  Confidence
mediocre         3     0.51
typesafe         3     0.10
...
```

When `-s` is used in conjunction with `-t` then the source input is first
questioned for the tags, and then one more time questioned for the good/bad score.


## Real Time Editor Feedback

Besides the obvious use-case to grade generated code;
The LSP interface can provide visual feedback in real time

![Demo Video#1](./demo/xorcery-nvim.webm)
![Demo Video#2](./demo/xorcery-vscodium.webm)

(The demos shows a screen capture of editors; code being edited in real time,
each line has it's own background color, and a tag next to the left line-number gutter)

## Manual

`TODO: rework`

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
  -s                    Output a summary
  --json|-j             Output structured json
  -l                    Start LSP server mode (-n and FILE ignored)
  -X                    dumps Json request to stdout and exits

  Deslop is compatible with `/v1/systemone` spec

  SYSTEMONE_URL=http://localhost:8080/v1/systemone
```


Note: `-r` and `-l` will not be implemented yet.

## Modes

### Flair

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

