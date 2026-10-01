# Coding Standards

## Published Package `-wip` Bumps (`pubspec.yaml` & `CHANGELOG.md`)

1. Whenever modifying *any* file (`lib/`, `bin/`, `test/`, `tool/`) in a package at a released version (`0.15.7`), **unconditionally** bump to `-wip` (`0.15.8-wip`) and add `## 0.15.8-wip` in `CHANGELOG.md`.
2. **New Feature / Public API -> Minor `-wip` (`X.(Y+1).0-wip` for `X >= 1`, `0.Y.(Z+1)-wip` for `0.Y.Z`)**: Whenever a change adds a new non-breaking public feature or API, bump to the next **minor** `-wip` version (`3.1.2` or `3.1.3-wip` -> `3.2.0-wip`; for `0.Y.Z` pre-v1 packages where `^0.Y.Z` caps at `<0.(Y+1).0`, use `0.Y.(Z+1)-wip`) in both `pubspec.yaml` and `CHANGELOG.md` (promoting any unreleased patch `-wip` heading).
3. **Breaking Change / Removed Public API -> Major `-wip` (`(X+1).0.0-wip` for `X >= 1`, `0.(Y+1).0-wip` for `0.Y.Z`)**: Whenever a change removes or incompatibly alters a public API (`api.txt` removal/signature change), CLI flag, or config key, bump to the next **major** `-wip` version (`6.3.0` or `6.3.1-wip` -> `7.0.0-wip`; for `0.Y.Z` pre-v1 packages, `0.3.1` -> `0.4.0-wip`) in both `pubspec.yaml` and `CHANGELOG.md` (promoting any unreleased patch/minor `-wip` heading).
4. Add changelog bullets only for user-visible feature/API/behavior changes; leave `## <ver>-wip` empty (header only) for `test/`/`tool/`/internal-only edits. Copy the repo's BSD license header into any newly created `.dart` file.

## Architecture: "Deep Externally, Pure Internally"

- **Public Package / Subsystem Boundary (`lib/<pkg>.dart` & `api.txt`)**: Must be **Deep**. Export only top-level orchestrators, immutable configuration value objects, and result records. Hide AST walkers, SQL builders, and parser helpers inside `lib/src/` (never re-exported in `lib/<pkg>.dart`). Ensure explicit `export 'src/...' show ...;` to avoid API leaks.
- **Internal Decomposition (`lib/src/`)**: When decomposing functions to satisfy `cognitive_complexity <= 15`, forbid stateful `_Populator` / `_Runner` helper classes that mutate caller maps/sets in-place; require **file-private pure functions (`_computeX(input) -> output`)** inside the same library or narrow internal modules with zero out-parameters.
- **Load-Bearing Library Boundary Rule (`part` / `part of` vs. Separate Libraries)**: Prefer compiler-enforced boundaries over `@internal` widening. Tier 1: 0-widening standalone `lib/src/` library. Tier 2: `part` / `part of` when `sealed` / `final` / `interface` / `base` / `._()` or `_private` class members cross the cut.
- **Test Seam Discipline**: Default unit/integration tests to importing `package:<pkg>/<pkg>.dart` (the public entrypoint seam). Allow direct `package:<pkg>/src/...` imports only for complex pure algorithms (e.g., parser state machines) that are explicitly marked `@visibleForTesting`.

## Dart & CLI Design Defaults

- **Zero-Alias CLI Design**: Never add `package:args` `aliases`; register non-canonical verbs in `CommonMistakes` (`FuzzyCommandRunner`) to fail fast with a prescriptive hint.
- **Dart Getters**: Prefer `@override String get name => '...';` over `@override final String name = '...';`.
- **Dependency Bounds**: Widen upper bounds (`'>=0.5.0 <0.7.0'`) rather than bumping `^min`.
- **Package `README.md` Hygiene**: Omit top-level `# <package>` H1 headers (redundant with `pub.dev`/GitHub header rendering) and never insert `---` horizontal rules; start directly with the introductory description followed by `##` sections.

- **Dart & `sem` CLI (`~/github/...`)**: Use `dart_oss` MCP (`lsp` before `grep_search`; `analyze_files` with `applyFixes: true` / `dart fix --apply`; `read_package_uris`/`rip_grep_packages` for deps; `dtd`/`hot_reload` for live apps). Exclusively use `dart install` (`dart install --source path <dir>` or `upkeep update dart_install`)—never `dart pub global`. Use `sem entities <file> --only class --only method` before reading files `>300 lines`, and `sem entities <dir> --text "<str>"` for AST-scoped string search. In `>10k-file` monorepos (`dart-sdk`), restrict `sem` to `sem find|callers|refs|grep` or path-scoped `sem entities <subpath>`.
