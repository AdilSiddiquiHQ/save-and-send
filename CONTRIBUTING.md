# Contributing

Save & Send is a personal app, but bug reports and focused pull requests are
welcome.

## Before you start

- Search existing issues and discussions first.
- For a security issue, follow [`SECURITY.md`](SECURITY.md) instead of opening
  a public issue.
- Keep changes small and explain the user-visible problem they solve.

## Development setup

Requirements are listed in the README. In short, you need Flutter 3.44.4 or
newer, JDK 17, and an Android SDK with API 36.

```bash
flutter pub get
flutter analyze
flutter test
```

The native download path cannot run in a widget test. To exercise it, install
the app on an arm64 Android device and try a public link from each supported
source.

## Pull requests

1. Branch from `main`.
2. Keep the existing architecture and visual language unless the change is
   specifically about them.
3. Run `flutter analyze` and `flutter test`.
4. Update documentation and tests when behavior changes.
5. Do not commit generated build output, keystores, `local.properties`, or
   cookies.

Golden tests in `test/visual_test.dart` are platform-sensitive. Regenerate them
only when a visual change is intentional:

```bash
flutter test test/visual_test.dart --update-goldens
```

## Commit style

Use short, imperative subjects, for example:

```text
fix: keep audio when the source is silent
docs: explain first-run extraction
```

## License

By contributing, you agree that your contribution is licensed under
GPL-3.0, the same license as the project.
