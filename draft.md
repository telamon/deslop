# code-xorcery

A fast single line of code evaluator

## How it Works

```bash
$ xorcery source.c
1 | X | #include <stdio.h>
2 | X |
3 | X | int main(void)
4 | X | {
5 | X |     printf("hello, world\n");
6 | X |     return 0;
7 | X | }
```


## Manual
```bash
xorcery -h

  usage: xorcery [options] [FILE]
  when no FILE is provided, context is read from STDIN

  -n NUMBER             Single line run
  -g                    1-dimension discrimination: Good vs. Bad
  --json                Output structured json
  -l                    Start LSP server mode (-n and FILE ignored)

  Code Xorcery uses libharness, refer to harness documentation
  for inference backend configuration.
```


## Initial Gradient

### Mode: Noul

Each LOC get's a simple good or bad grading in range of -1 to 1.

### Mode: Categories

Initial naïve tags listed in order from `good` to `bad`

- `godmode`
- `awesomesauce`
- `typesafe`
- `mediocre`
- `noob`
- `workaround`
- `slop`
- `malicious`

## License

AGPL-version-3-or-later

All wrongs reversed - 2026 - Decent Labs

