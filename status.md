# code-xorcery — status

## Current state

- Zig 0.16.0 template project (`zig init`), builds clean: `zig build`.
- `HARNESS_BIN` env override implemented (`src/root.zig:harnessBin`, `src/main.zig` wiring):
  explicitly set non-empty value wins, else `"harness"` resolved via PATH.
- `lsp_kit` pinned in `build.zig.zon` (commit d148676, same as zls) — **not yet wired in build.zig**.
- No CLI parsing, no harness invocation, no grading pipeline yet.

## Contract (from draft.md)

- Output format: `N | X | <line>`; X = float `1.00 … -1.00` (2 decimals) or tag label,
  column-aligned. Blank lines → `0.00` / `mediocre` (neutral).
- Default mode: per-line fitness −1.0 … 1.0. Categorical: `-t TAGFILE` (whitespace-delimited,
  ordered good→bad ladder); scores map to adjacent labels.
- Grading is delegated to harness over stdio; binary overridable via `HARNESS_BIN`.
- `-r PATH` recursive grade: **out of scope for now** (per draft note).

## TODO

1. [ ] CLI parsing: `-n NUMBER`, `-t TAGFILE`, `--json|-j`, `-l`, `[FILE]` / STDIN fallback
2. [ ] Harness bridge: spawn `HARNESS_BIN` (stdio pipes), stream source lines as context,
       collect per-line verdict; define line-delimited JSON envelope for fitness score
3. [ ] Example 1 — Fitness output: `N | X.XX | <line>` with 2-decimal formatting
4. [ ] Example 2 — Categorical mode: load TAGFILE → ladder, map score to label, pad label column
5. [ ] `--json` structured output (mirror of text: `{line, score|tag}`)
6. [ ] Tests: arg parser unit tests; end-to-end fixture with a fake `HARNESS_BIN`
       script that emits canned verdicts (no model needed in CI)
7. [ ] Housekeeping: promote draft.md → README.md; license headers; `-r` help text marked "not implemented"

## On hold

- **LSP mode (`-l`)**: blocked until Examples 1 & 2 work end-to-end.
  Do **not** hand-roll the JSON-RPC loop; keep `lsp_kit` as the transport when unblocked.
  Requires Zig `0.17.0-dev.1397+4331ba0fb` (lsp_kit minimum) — newer than local 0.16.0;
  a 0.17 toolchain will be provided later if this turns out to be a problem.

## Notes / decisions

- libharness stable ABI (harness-rust): not pursued; draft settles on subprocess + `HARNESS_BIN`.
- Toolchain pinned at 0.16.0 for now; lsp_kit stays pinned but unwired (see On hold).
- Milestone gate: two basic examples (fitness + categorical) must pass before any LSP work.
