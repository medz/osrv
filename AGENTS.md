# Agent Guidelines

## Project Layout

`osrv` is a unified server runtime for Dart applications. It is a runtime layer, not an HTTP framework and not an adapter registry.

Key repository areas:

- `lib/osrv.dart`: public core entrypoint.
- `lib/runtime/*.dart`: public runtime-family entrypoints.
- `lib/src/core/`: shared server contract, lifecycle model, capabilities, errors, and runtime metadata.
- `doc/`: source-of-truth design docs, including architecture, config, capabilities, terms, API docs, and runtime guides.
- `test/`: unit, bridge, capability, and compile-mode verification.
- `integration_test/`: black-box runtime behavior tests, including runtime-specific app fixtures under `integration_test/<runtime>/app/`.
- `example/`: runnable runtime examples and deployment shims.

Keep edits scoped. Avoid touching generated or installed artifacts unless the task explicitly requires it, especially:

- `.dart_tool/`
- `example/node_modules/`
- `example/api/*.js`
- `example/api/*.js.map`
- `example/api/*.js.deps`
- `.vercel/`

## Product Direction

Treat the released public API and runtime behavior as the contract to protect.

`osrv` should provide:

- one portable `Server` contract;
- explicit runtime selection;
- honest capability reporting;
- typed runtime-specific extension access;
- runtime-family-specific entrypoints and configuration.

`osrv` should not become:

- an HTTP application framework;
- a routing DSL;
- a middleware composition layer;
- an adapter registry;
- an auto-detecting platform abstraction.

Release-state constraints:

- preserve source compatibility for public entrypoints unless the task explicitly calls for a breaking change;
- prefer additive changes over reshaping released APIs;
- runtime selection must stay explicit;
- one deployment targets one runtime family;
- platform differences should be exposed through capabilities, not flattened away;
- do not invent fake platform support such as a fake filesystem or fake long-lived server state.

## Frozen Terms

Use the repository terminology consistently:

- `Server`: the portable request-handling object exposing `fetch` and lifecycle hooks.
- `RuntimeConfig`: the runtime-specific configuration input for a selected runtime family.
- `Runtime`: the running handle returned by `serve(...)` for listener-style runtimes.
- `Capabilities`: runtime truth about supported features; not a promise of parity.
- `RuntimeExtension`: the typed escape hatch for host-specific access.

Current entry-model split matters:

- listener-style runtimes: `dart`, `node`, `bun`
- fetch-export runtimes: `cloudflare`, `vercel`

Do not collapse these models into one fake universal runtime shape.

## Runtime Design Expectations

When adding or changing a runtime family:

- update runtime documentation in the same change;
- define what the runtime is, what it is not, and where its boundaries are;
- document capabilities, limitations, config shape, lifecycle differences, and deployment constraints;
- provide a minimal example and a counterexample;
- expose differences through `Capabilities` or `RuntimeExtension`, not through hidden branching.

Do not introduce structures such as:

- `Adapter`
- `AdapterRegistry`
- `detectPlatform()`
- one giant config object that tries to cover every host

Any new abstraction should justify all three of these:

1. It serves at least two runtime families with a stable shared need.
2. It does not hide real platform differences.
3. It cannot be replaced by a smaller contract.

## Build, Test, and Verification Commands

Run commands from the repository root.

Baseline:

- `dart pub get`
- `dart format .`
- `dart analyze`
- `dart test`

CI-aligned verification:

- Prefer `./tool/ci_local.sh --native` to run the full local CI-equivalent bundle.
- Prefer `./tool/ci_local.sh --job <job>` when you need a single GitHub Actions job through `act`.
- `dart format --output=none --set-exit-if-changed .`
- `dart test test`
- `dart test -p vm integration_test/dart integration_test/compile integration_test/node/runtime_process_test.dart integration_test/bun/runtime_process_test.dart integration_test/deno/runtime_process_test.dart integration_test/cloudflare/runtime_process_test.dart`
- `dart test -p node integration_test/bun/preflight_test.dart integration_test/deno/preflight_test.dart integration_test/node/host_runtime_test.dart integration_test/cloudflare/worker_host_test.dart integration_test/vercel/fetch_export_test.dart integration_test/netlify/fetch_export_test.dart integration_test/web/request_bridge_test.dart`

Fast targeted checks:

- `dart test test/websocket_public_surface_test.dart`
- `dart test -p node integration_test/bun/preflight_test.dart integration_test/deno/preflight_test.dart`
- `dart test -p vm integration_test/dart/runtime_test.dart integration_test/dart/request_bridge_test.dart`
- `dart test -p node integration_test/node/host_runtime_test.dart integration_test/web/request_bridge_test.dart`
- `dart test -p node integration_test/cloudflare/worker_host_test.dart integration_test/vercel/fetch_export_test.dart`
- `dart test integration_test/bun/runtime_process_test.dart`
- `dart test -p vm integration_test/compile/fetch_export_compile_test.dart`

Environment notes:

- `test/` is reserved for portable tests and should not depend on `@TestOn(...)` or host-specific globals.
- Node-host integration tests require a Node test environment.
- `integration_test/bun/runtime_process_test.dart` requires `bun` to be installed and available on `PATH`.
- Example and deployment files under `example/` are part of the runtime contract when they document bootstrap or host-shim behavior.

Use the smallest verification set that matches the change, but do not skip runtime-specific tests when touching a runtime bridge, capability claim, or example bootstrap.

## Change Workflow

Choose the workflow by change type.

Default workflow for API, runtime, or behavior changes:

1. Read the relevant docs first (`doc/architecture.md`, `doc/config.md`, `doc/capabilities.md`, `doc/terms.md`, and the affected runtime doc).
2. Identify whether the change touches released public surface in `package:osrv/osrv.dart` or `package:osrv/runtime/*.dart`.
3. Add or update the focused regression tests.
4. Implement the smallest change that closes the loop.
5. Run the targeted verification for the affected runtime families.
6. Run `dart format .`.
7. Run `dart analyze` if code changed.
8. Update docs/examples so they match the real behavior.
9. Call out any breaking change explicitly in the commit, PR, and docs.

Lightweight workflow for docs-only changes:

- no red-to-green requirement by default;
- if the doc changes commands, examples, or behavior claims, run the smallest relevant verification;
- keep terminology aligned with the frozen terms above.

Lightweight workflow for comment-only or formatting-only changes:

- no test-first requirement;
- run `dart format .` if Dart or doc-comment formatting changed;
- keep formatting-only changes separate from behavior changes when practical.

## Editing Rules

Follow standard Dart style:

- 2-space indentation;
- `PascalCase` for types;
- `camelCase` for members;
- `snake_case.dart` for file names.

Repository-specific rules:

- prefer public imports from `package:osrv/osrv.dart` and `package:osrv/runtime/*.dart`;
- avoid adding new imports from `package:osrv/src/...` unless the file is internal implementation;
- do not broaden the public API casually;
- do not turn runtime-specific behavior into hidden shared magic;
- do not edit compiled example outputs just to mirror source changes unless the task explicitly needs checked-in generated artifacts updated.

Public API changes need extra care. If a change alters what `osrv` is, what it is not, how a runtime family is configured, or what a public entrypoint exports, update docs and examples in the same change and treat compatibility as a first-class concern.

## Testing Rules

Every behavior change needs a focused test near the affected area.

Common expectations:

- core contract or lifecycle behavior: update the relevant `test/*` runtime or bridge test;
- listener runtimes (`dart`, `node`, `bun`): verify request bridging and lifecycle behavior;
- fetch-export runtimes (`cloudflare`, `vercel`): verify export setup, request bridging, and `waitUntil` behavior;
- compile-target expectations: update or run `integration_test/compile/fetch_export_compile_test.dart`;
- docs or examples that change runtime behavior claims: verify the related example or targeted runtime test.

If a change claims cross-runtime behavior, verify more than one runtime family.

## Commit and PR Guidelines

Use Conventional Commits, for example:

- `feat(runtime): add ...`
- `fix(node): correct ...`
- `docs(runtime): clarify ...`
- `test(cloudflare): cover ...`

Keep commits narrowly scoped. Separate formatting-only changes when that improves review clarity.

Pull requests should:

- stay focused on one change set;
- explain the behavior or contract change;
- list the verification commands actually run;
- call out breaking changes explicitly when present;
- use `Resolves #<id>` in the PR body when the PR closes an issue.
