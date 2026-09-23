# unslop — status

## Current state

- Zig 0.17.0-dev.2264+230c63650, builds clean: `zig build`; tests green.
- One-shot HTTP client (no agent lifecycle): `src/systemone.zig:postJson` POSTs a
  `SystemOneRequest` to $SYSTEMONE_URL (default `http://localhost:8080/v1/systemone`);
  optional `$TYPESAFE_API_KEY` -> `Authorization: Bearer`; `$UNSLOP_MODEL` for the model field.
- lsp_kit pinned in `build.zig.zon` (commit d148676, same as zls) — **not yet wired in build.zig**.

## Contract (from draft.md)

- Output format: `N | X | <line>`; X = float `1.00 … -1.00` (2 decimals) or tag label,
  column-aligned. Blank lines → `0.00` / `mediocre` (neutral).
- Default mode: per-line fitness −1.0 … 1.0. Categorical: `-t TAGFILE` (whitespace-delimited,
  ordered good→bad ladder); answers pick the tag directly.
- Grading is delegated to a /v1/systemone endpoint over HTTP.
- `-r PATH` recursive grade: **out of scope for now** (per draft note).

## TODO

1. [x] CLI parsing: `-n NUMBER`, `-t TAGFILE`, `--json|-j`, `-X`, `-l`, `[FILE]` / STDIN fallback
2. [x] HTTP bridge: POST the request JSON to $SYSTEMONE_URL and parse `SystemOneResponse.answers`
3. [x] Example 1 — Fitness output: `N | X.XX | <line>` with 2-decimal formatting
4. [x] Example 2 — Categorical mode: load TAGFILE → ladder, map answer to label, pad label column
5. [x] `--json` structured output (mirror of text: `{line, score|tag}`)
6. [x] Tests: arg parser unit tests; end-to-end fixture with a fake /v1/systemone HTTP
       endpoint serving a canned SystemOneResponse (no model needed in CI)
7. [ ] Housekeeping: promote draft.md → README.md; license headers; -r help text marked "not implemented"

## On hold

- **LSP mode (`-l`)**: Examples 1 & 2 now pass end-to-end; unblocked, not started.
  Do **not** hand-roll the JSON-RPC loop; keep `lsp_kit` as the transport when unblocked.

## Notes / decisions

- The final draft settles on a one-shot HTTP backend; an earlier subprocess transport
  (spawn + stdio pipes + env override, raw -R -T -r mode) was removed with it.
- Toolchain 0.17.0-dev.2264+230c63650; lsp_kit minimum (0.17.0-dev.1397) satisfied; stays pinned but unwired.
- Milestone gate: two basic examples (fitness + categorical) pass over HTTP before any LSP work.
- Verdict extraction: per-line answers keyed `line_N` in `SystemOneResponse.answers` (plain `N`
  also accepted); non-line keys and empty answers skipped; missing → neutral (0.00/mediocre);
  noul p → fitness 2p−1; choice → tag. Fixtures: tests/fake-systemone.sh (canned HTTP server).
- 0.17 compat: `b.args` removed from `std.Build` — run-step arg forwarding dropped from build.zig;
  caches cleared and rebuilt.
- 0.17 `std.json.ObjectMap` is allocator-passing (`= .empty` + `.put(arena, k, v)`); requests are
  built as a `std.json.Value` tree and serialized with `std.json.Stringify.valueAlloc` — the
  library owns all JSON syntax; no hand-rolled escaping.

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
- Auth token via env (`$TYPESAFE_API_KEY`), per-line questions map to noul/choice.
- Package name is `unslop` everywhere (build.zig, build.zig.zon name+fingerprint `0x4608cf9f88405b9e`,
  imports, help text).
- Instructions template wraps the source line in backticks instead of escaped quotes.
