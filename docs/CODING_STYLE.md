# Coding Style Guidelines

## Core Rules

- Use Dart/Flutter defaults first; avoid custom style drift.
- Keep line length at `100` characters.
- Prefer single quotes in Dart unless interpolation/escaping is clearer with double quotes.
- Keep imports ordered and grouped (SDK, package, relative).
- Keep feature co-location structure (`features/<feature>/*`) for new code.

## Lint and Analyze

- `analysis_options.yaml` is the source of truth for lints.
- Run `flutter analyze` before commits.
- Strict analyzer options are enabled for safer typing:
  - `strict-casts`
  - `strict-inference`
  - `strict-raw-types`

## Formatting

- Use `dart format` for Dart sources.
- IntelliJ picks project formatting from `.editorconfig` and `.idea/codeStyles`.
- Use provided run configurations:
  - `Format (Dart)`
  - `Format Check (Dart)`
  - `Analyze (Flutter)`
