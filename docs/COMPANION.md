# Kedis Companion — M1 (experimental)

Owner-approved direction: one existing Kedis application, offline-first task management and
optional knowledge retrieval, then on-device RAG and future permission-scoped MCP.
V1 task acknowledgement, stale tasks, reminders and the existing Trash milestone remain
separate commitments. This draft is not an accepted production feature.

## Candidate and limits

- Android binding: Maven Central `org.kiwix:libkiwix:2.6.0` (libkiwix 14.2.1,
  libzim 9.7.0, upstream tag 2.6.0). Upstream build targets API 24+ and
  builds arm, arm64, x86 and x86_64. Actual resolved APK ABI and runtime
  behavior require validation.
- Use the Android document picker and copy one single-file, indexed ZIM into
  no-backup private storage. The 2 GiB preview cap and 128 MiB free-space
  reserve are deliberate provisional limits. Replacement is staged, checked
  and atomically renamed; original external documents are never modified.
- Full-text search uses libzim, not a second database. Up to 20 results and
  text excerpts capped at 40,000 characters. HTML input is rendered as plain
  text only. Native article inputs are capped at 2 MiB.
- Archive UUID, record path, resolved path and available archive metadata are
  displayed for attribution. Complete per-article attribution for release is
  still a compliance task. Archive checksum is checked during import; later
  operations reopen and check index availability rather than rehashing every
  search.
- The dedicated `kedis/knowledge` channel runs archive operations serially
  on a worker; task database and widget channel are not involved. Archive,
  query, searcher, search, result iterator and blob are explicitly disposed.
  Entry and Item wrappers in this binding expose only private disposal,
  so their cleanup is managed by upstream finalizers. Measure memory.
- No model, accounts, network service, vector index, background downloads,
  or task mutations. Native libraries are loaded only on knowledge use.

## Concurrent integration order

PR #12 owns Home, Settings, Trash and the existing product/architecture/backlog
documents. This draft deliberately does not edit those files. The independent
screen has a named route and a debug-only startup preview. Integrate PR #12
first (separate authorization), update this branch from main, add a small
Home or Settings entry and reconcile documentation. Do not merge this draft
before that and full physical acceptance.

## Private physical test

On Ubuntu with Flutter and Java 17, provision a small genuine searchable
Wikipedia ZIM from https://library.kiwix.org/ and copy it to the phone's Downloads.
Build/install directly for private testing only:

    flutter pub get
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze
    flutter test
    flutter build apk --debug
    git diff --check
    flutter run --debug --dart-define=KEDIS_KNOWLEDGE_PREVIEW=true

The preview starts on the reader; Back returns to the normal task home.
Normal launches without the define remain unchanged. Verify import, cancel,
invalid file, empty search, real results, article identity, airplane mode,
restart with archive, failed replacement retaining old archive, removal
without deleting the original, and normal task/widget behavior. Inspect APK
ABIs and native libraries locally; measure memory and import/search latency.

## Licensing

Binding and libkiwix are GPL-3.0-or-later; libzim is GPL-2.0-or-later.
GPL-3.0-or-later is the preferred application candidate, not finalized.
Confirm contribution rights, exact transitive/native licenses, notices,
corresponding source and distribution obligations before releasing or
sharing combined binaries. This PR is source-only; no APK artifacts are
published. Wikipedia content licensing is separate (generally CC BY-SA 4.0,
with exceptions); preserve applicable attribution, credits and terms.
Gemma 4 weights (Apache-2.0) and LiteRT-LM are future experimental candidates,
not M1 dependencies. Do not change the repository license in this milestone.

Upstream: https://github.com/kiwix/java-libkiwix/tree/2.6.0
and https://central.sonatype.com/artifact/org.kiwix/libkiwix/2.6.0.
