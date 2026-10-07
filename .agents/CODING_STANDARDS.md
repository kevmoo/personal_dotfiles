# Coding Standards

## Published Package `-wip` Bumps (`pubspec.yaml` & `CHANGELOG.md`)

1. Whenever modifying _any_ file (`lib/`, `bin/`, `test/`, `tool/`) in a package
   at a released version (`0.15.7`), **unconditionally** bump to `-wip`
   (`0.15.8-wip`) and add `## 0.15.8-wip` in `CHANGELOG.md`.
2. **New Feature / Public API -> Minor `-wip` (`X.(Y+1).0-wip` for `X >= 1`,
   `0.Y.(Z+1)-wip` for `0.Y.Z`)**: Whenever a change adds a new non-breaking
   public feature or API, bump to the next **minor** `-wip` version (`3.1.2` or
   `3.1.3-wip` -> `3.2.0-wip`; for `0.Y.Z` pre-v1 packages where `^0.Y.Z` caps
   at `<0.(Y+1).0`, use `0.Y.(Z+1)-wip`) in both `pubspec.yaml` and
   `CHANGELOG.md` (promoting any unreleased patch `-wip` heading).
3. **Breaking Change / Removed Public API -> Major `-wip` (`(X+1).0.0-wip` for
   `X >= 1`, `0.(Y+1).0-wip` for `0.Y.Z`)**: Whenever a change removes or
   incompatibly alters a public API (`api.txt` removal/signature change), CLI
   flag, or config key, bump to the next **major** `-wip` version (`6.3.0` or
   `6.3.1-wip` -> `7.0.0-wip`; for `0.Y.Z` pre-v1 packages, `0.3.1` ->
   `0.4.0-wip`) in both `pubspec.yaml` and `CHANGELOG.md` (promoting any
   unreleased patch/minor `-wip` heading).
4. Add changelog bullets only for user-visible feature/API/behavior changes;
   leave `## <ver>-wip` empty (header only) for `test/`/`tool/`/internal-only
   edits. Copy the repo's BSD license header into any newly created `.dart`
   file.

## Architecture: "Deep Externally, Pure Internally"

- **Public Package / Subsystem Boundary (`lib/<pkg>.dart` & `api.txt`)**: Must
  be **Deep**. Export only top-level orchestrators, immutable configuration
  value objects, and result records. Hide AST walkers, SQL builders, and parser
  helpers inside `lib/src/` (never re-exported in `lib/<pkg>.dart`). Use
  explicit `export 'src/...' show ...;` when splitting files to prevent API
  leaks.
- **Public API Surface Verification (`dart run api_summary@^1.1.0`)**: After any
  file split or refactoring in a Dart package (Dart 3.12+ remote package
  runner—zero `pubspec.yaml` edits or global install required):
  - If `api.txt` is tracked: run `dart run api_summary@^1.1.0 --check` and
    require exit code `0`.
  - If `api.txt` is not tracked: capture
    `dart run api_summary@^1.1.0 -o /tmp/api_before.txt` before refactoring and
    `diff -u /tmp/api_before.txt /tmp/api_after.txt` after, requiring zero diff
    unless a public API change was requested.
- **Internal Decomposition & Shallow-Helper Guardrail (`lib/src/`)**: When
  decomposing functions to satisfy `cognitive_complexity <= 15`, forbid stateful
  `_Populator` / `_Runner` helper classes that mutate caller maps/sets in-place;
  require **file-private pure functions (`_computeX(input) -> output`)** inside
  the same library or narrow internal modules with zero out-parameters. Stop
  decomposing once a function reaches the **Target Zone (`8–15`, not `0`)**, cap
  extracted helpers at `<= 4` parameters (`<= 3` preferred,
  `sliceScoreAtRoot >= 3`), and run
  `dart run cognitive_complexity:shallow@^0.4.0 lib/` to detect and re-inline
  single-caller `SAFE_INLINE` helpers (`CallerCCAfter <= 15`).
- **Load-Bearing Library Boundary Rule (`part` / `part of` vs. Separate
  Libraries)**:
  - **Core Principle**: Prefer the boundary the language compiler enforces
    (library privacy + class modifiers) over one an annotation suggests
    (`@internal`, which is only an analyzer lint and still leaks into `api.txt`
    when attached to a member of an exported `PublicClass`).
  - **Tier 1 — Standalone `lib/src/` Library (Default When Boundary Is Not
    Load-Bearing)**: Extract declarations into a separate library under
    `lib/src/` with explicit `import` / `show` **only** when the cut requires
    **zero** visibility widening (`0` cross-cut `_private` member accesses) and
    crosses **zero** library-scoped class modifier boundaries (`sealed`,
    `final`, `interface`, `base`, or private generative constructors `._()`).
  - **Tier 2 — `part` / `part of` (Preferred When the Library Boundary Is
    Load-Bearing)**: Whenever multiple types require privileged library-level
    access to each other—such as subtyping a `sealed`, `final`, `interface`, or
    `base` class/mixin, calling a private constructor `._()` for subtype
    capability, or accessing `_private` members on a public or shared
    class—**keep them in the same library using `part` / `part of`**. Never
    force tightly privileged types into a single giant file just to avoid
    `part`, and never widen `PublicClass._member` to `@internal` just to split
    libraries.

## Testing & Verification

- **Test Seam Discipline (Package Integration vs. `lib/src/` Unit Tests)**:
  - **Package-Level & Integration Tests**: Import `package:<pkg>/<pkg>.dart`
    (the public entrypoint seam) and keep `lib/<pkg>.dart` exports strictly
    scoped to public consumers.
  - **Subsystem Unit Tests (`lib/src/`)**: Import internal **deep modules**
    (`package:<pkg>/src/<subsystem>.dart`)—such as unexported parsers, state
    machines, data models, or algorithms with simple interfaces and rich
    internal behavior—to unit-test edge cases directly; test thin single-caller
    helpers through their owning module's entrypoint.
- **Behavioral & Boundary Assertions**: Assert observable outputs, state
  transitions, and boundary conditions of the code that _consumes_ constants and
  models (e.g., passing 280 vs. 281 characters into a validator) against
  concrete expected values.
- **Direct Execution & Rendering Verification**: Verify runtime behavior,
  control flow, and UI/CLI output by invoking functions, running CLI commands,
  or rendering components directly. Use raw file-text reads
  (`readAsStringSync()`) specifically for static documentation drift
  (`README.md` `--help` blocks), build/package metadata sync (`BUILD`,
  `pubspec.yaml`), and code-generator input/output fixtures.
- **Real Implementations & First-Party Fakes ("Tests That Can Fail")**: Exercise
  real dependencies and first-party fakes so tests fail when production
  contracts break—use `package:test_descriptor` (`d.sandbox`, `d.dir`, `d.file`)
  or `Directory.systemTemp.createTempSync()` for filesystem I/O, in-memory
  databases or loopback `HttpServer` instances for services,
  `package:http/testing.dart` (`MockClient`) for HTTP, hand-written fakes/stubs
  for custom interfaces, and `@TestOn('browser')` for DOM and JS/Wasm interop.

## Dart & CLI Design Defaults

- **Zero-Alias CLI Design**: Never add `package:args` `aliases`; register
  non-canonical verbs in `CommonMistakes` (`FuzzyCommandRunner`) to fail fast
  with a prescriptive hint.
- **Dart Getters**: Prefer `@override String get name => '...';` over
  `@override final String name = '...';`.
- **Dependency Bounds**: Widen upper bounds (`'>=0.5.0 <0.7.0'`) rather than
  bumping `^min`.
- **Package `README.md` Hygiene**: Omit top-level `# <package>` H1 headers
  (redundant with `pub.dev`/GitHub header rendering) and never insert `---`
  horizontal rules; start directly with the introductory description followed by
  `##` sections.
- **Dart & `sem` CLI (`~/github/...`)**:
  - Use `dart_oss` MCP (`lsp` before `grep_search`; `analyze_files` with
    `applyFixes: true` / `dart fix --apply`;
    `read_package_uris`/`rip_grep_packages` for deps; `dtd`/`hot_reload` for
    live apps).
  - Exclusively use `dart install` (`dart install --source path <dir>` or
    `upkeep update dart_install`)—never `dart pub global`.
  - Use `sem entities <file> --only class --only method` before reading files
    `>300 lines`, and `sem entities <dir> --text "<str>"` for AST-scoped string
    search. In `>10k-file` monorepos (`dart-sdk`), restrict `sem` to
    `sem find|callers|refs|grep` or path-scoped `sem entities <subpath>`.
