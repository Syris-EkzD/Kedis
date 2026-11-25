# Kedis Companion — M1 (experimental)

Owner-approved direction: one existing Kedis application, offline-first task management and
optional knowledge retrieval, then on-device RAG and future permission-scoped MCP.
V1 task acknowledgement, stale tasks and reminders remain separate commitments.
Recoverable category and grouped Trash behavior is inherited from merged PR #12.
This draft is not an accepted production feature.

## Candidate and limits

- Android binding: Maven Central `org.kiwix:libkiwix:2.6.0` (libkiwix 14.2.1,
  libzim 9.7.0, upstream tag 2.6.0). Upstream build targets API 24+ and
  builds arm, arm64, x86 and x86_64. Actual resolved APK ABI and runtime
  behavior require validation.
- Use the Android document picker and copy one single-file, indexed ZIM into
  no-backup private storage. The 2 GiB import cap and 128 MiB free-space
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

## Integration and navigation

PR #12 and the Flutter 3.47.5 pin from PR #14 are integrated into this
branch without rewriting history. Home remains task-first and exposes an
Offline knowledge book icon. Back returns to the existing Home route.
The debug startup flag and named preview route have been removed.
Do not merge before independent review and genuine physical acceptance.

## Private physical test

Use Flutter 3.47.5 and Java 17 on Ubuntu. A candidate genuine archive is
Simple English Wikipedia Mini, September 2026 (about 506 MiB):
https://lb.download.kiwix.org/zim/wikipedia/wikipedia_en-simple_all_mini_2026-09.zim
Verify the actual checksum and full-text index on the downloaded file before
using it as a test fixture; the listing alone does not establish index support.
If not indexed, select a searchable archive under 2 GiB from
https://library.kiwix.org/ (e.g. Simple English Wikipedia Nopic).
Copy the file to the phone's Downloads.

    flutter --version
    flutter pub get
    dart format --output=none --set-exit-if-changed lib test
    flutter analyze
    flutter test
    flutter build apk --debug
    git diff --check
    flutter run --debug

Open the Home book icon. Verify import, cancel, invalid file, empty search,
real results, article identity, airplane mode, restart with archive, failed
replacement retaining old archive, removal without deleting the original,
and normal task/widget behavior. Record actual archive UUID/edition, SHA256,
index/checksum status, tested commit, device/OS, APK ABIs/native libraries,
memory and import/search latency. Use disposable task data and preserve
existing user data; do not clear or uninstall without explicit approval.
No APK distribution is authorized.

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
