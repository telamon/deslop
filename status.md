# unslop — status

## Current state

- Zig 0.17.0-dev.2264+230c63650 (upgraded from 0.16.0 mid-project) template project (`zig init`), builds clean: `zig build`.
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

1. [x] CLI parsing: `-n NUMBER`, `-t TAGFILE`, `--json|-j`, `-l`, `[FILE]` / STDIN fallback
2. [x] Harness bridge: spawn `HARNESS_BIN` (stdio pipes), stream source lines as context,
       collect per-line verdict; define line-delimited JSON envelope for fitness score
3. [x] Example 1 — Fitness output: `N | X.XX | <line>` with 2-decimal formatting
4. [x] Example 2 — Categorical mode: load TAGFILE → ladder, map score to label, pad label column
5. [x] `--json` structured output (mirror of text: `{line, score|tag}`)
6. [ ] Tests: arg parser unit tests; end-to-end fixture with a fake `HARNESS_BIN`
       script that emits canned verdicts (no model needed in CI)
7. [ ] Housekeeping: promote draft.md → README.md; license headers; -r help text marked "not implemented"

## On hold

- **LSP mode (`-l`)**: blocked until Examples 1 & 2 work end-to-end.
  Do **not** hand-roll the JSON-RPC loop; keep `lsp_kit` as the transport when unblocked.
  Requires Zig `0.17.0-dev.1397+4331ba0fb` (lsp_kit minimum) — newer than local 0.16.0;
  a 0.17 toolchain will be provided later if this turns out to be a problem.

## Notes / decisions

- libharness stable ABI (harness-rust): not pursued; draft settles on subprocess + `HARNESS_BIN`.
- Toolchain upgraded to 0.17.0-dev.2264+230c63650; lsp_kit stays pinned but unwired (see On hold).
- Milestone gate: two basic examples (fitness + categorical) must pass before any LSP work.
- Envelope: {"line":N,"fitness":F} or {"line":N,"tag":"..."} NDJSON on harness stdout; unparseable lines ignored; missing -> neutral (0.00/mediocre); fitness->tag = linear floor map (draft samples illustrative). Fixtures: tests/fake-harness*.sh; real-harness integration may need a wrapper emitting the envelope.
- 0.17 compat: `b.args` removed from `std.Build` — run-step arg forwarding dropped from build.zig; caches cleared and rebuilt. lsp_kit minimum (0.17.0-dev.1397) now satisfied.

## API (TypeSafe backend)

- OpenAPI fetched to `schema/openapi.json` (TypeSafe 0.2.0, from api.typesafe.ai/docs).
- `POST /v1/systemone` (op `systemone_v1_systemone_post`), Bearer auth (`HTTPBearer`).
  - Request `SystemOneRequest` (all required): `state` (string|object|array — content),
    `model` (name/alias; list via `GET /v1/models`), `questions` (named map, ≥1).
  - `Question` discriminated by `type`:
    - `noul` — yes/no; answer = `NoulAnswer{noul: 0..1}` (≈0.5 uncertain); optional instructions + `NoulCriteria{true,false}`.
    - `choice` — pick from `criteria` map; answer = `ChoiceAnswer{choice, confidence, probabilities}`.
    - `score` — ordered rubric `criteria` array (score = 0-based index); answer = `ScoreAnswer{score (expected value), confidence, probabilities, legend}`.
  - Response `SystemOneResponse` (all required): `model` (resolved name), `answers`
    (same keys as questions; `Answer` type matches question), `usage{input_tokens,output_tokens}`.
  - Errors: 422 `HTTPValidationError`.
- Binary/module/package renamed: `code_xorcery` → `unslop` (build.zig, .zon name+fingerprint `0x4608cf9f88405b9e`, imports, help text).
- TODO: TypesSafe client — auth token via env (suggest `TYPESAFE_API_KEY`), map verdict envelope → noul/score questions per line.
- Initial variant: harness is run as `harness -R -T -r` (raw in / no tools / raw out); the
  NDJSON envelope protocol is replaced by /v1/systemone JSON (schema/openapi.json).
  src/systemone.zig builds `SystemOneRequest` (state = whole source; per-line `line_N`
  questions: `noul` good-vs-bad by default, `choice` over the -t ladder with null
  descriptions; -n restricts questions) and parses `SystemOneResponse.answers` back out
  (noul p -> fitness 2p-1; choice -> tag). Model: $UNSLOP_MODEL, default "jev-latest".
  Fixtures emit canned SystemOneResponse JSON.
