## Unreleased

- `micro_apps`: a micro-app with its own `assets/translations/<id>/` files gets
  its own generated class, `context.T` getter and key prefix. Its keys join
  the overlap check.
- `key_prefix`: prepends a prefix to every key the generated code looks up.
- `overlap` (`error`, `warning`, `ignore`) and `allow_overlap` (key globs)
  control how a key defined in two sources is reported.
- `example/`: a package that ships translations, and an app that consumes it.

## 0.1.0

- Initial release: parser, cross-locale validator, typed generator, CLI
  (`generate`, `check`), build_runner builder, package namespaces with
  manifests and fingerprints.
