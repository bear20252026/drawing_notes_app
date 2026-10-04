# Drawing Notes App（绘图笔记）

A cross-platform **drawing and note-taking** application for **Windows desktop + Android**, built with **Flutter (Dart)**.
**Local-first**: fully offline by default — **no accounts, no AI features**; sync is **optional user-configured WebDAV end-to-end encrypted sync** (no vendor cloud, zero network requests unless enabled).
中文说明见 [README.md](README.md)。

![CI](https://img.shields.io/github/actions/workflow/status/bear20252026/drawing_notes_app/ci.yml)
![License](https://img.shields.io/github/license/bear20252026/drawing_notes_app)

> **Security posture**: government-grade security — encrypted notes (per-note keys),
> policy engine (default-deny), session guard (auto-lock), VFS encrypted object vault
> (versioned / atomic commits), tamper-evident audit (SHA-256 hash chain), import isolation
> (SVG/PDF preflight).

---

## Product Shapes: Three Note Carriers

| Carrier | Description |
|---------|-------------|
| **Typed notes (block docs)** | AFFiNE-style block model: headings / lists / todos / code / quotes / dividers / database blocks, slash menu, block drag handles, bidirectional Markdown, block-level undo, outline rail, document templates — **the flagship carrier** |
| **Paged canvas (notebooks)** | Multi-page sketchbooks: each page is an independent vector canvas with text/image/shape mixing, whole-book & multi-page PDF export (footers, embedded CJK font), password protection with USB reset disk |
| **Infinite canvas (Edgeless)** | Pan-zoom camera + hand-drawn (rough) shapes, diagrams & connectors, object eraser, laser pointer, alignment guides, mini-map, command palette (Ctrl+K) |

All three are managed in the **All Docs workspace**: grouped timeline, favorites, tags, trash (soft delete + 30-day expiry), global search, presentation mode.

## Features

| Area | Content | Status |
|------|---------|--------|
| Drawing engine | Pressure-sensitive strokes (perfect_freehand), pencil grain shader (FragmentShader), layer system (visibility/opacity/order/merge/offscreen cache), selection transforms, blended ink rendering (marker darken compositing) | ✅ |
| Block docs | Database blocks (table/kanban/list views), attachment & embed blocks, slash commands, block-level undo/redo, HTML/Markdown export | ✅ |
| Interop | PDF import as page backgrounds (page/size/output caps); export to PDF (vector+raster hybrid, tiled pages, footers), PNG, SVG, Word (RTF), HTML, JSON, PPTX | ✅ |
| Workspace | All Docs three-layer architecture (domain/query/UI), desktop two-pane + mobile single-column responsive (900dp), quick search, presentation mode | ✅ |
| Sync | Optional WebDAV: AES end-to-end encryption, https enforced (loopback exception), conflict visibility, path-traversal protection, operation timeouts end-to-end | ✅ |
| Security | See table below (expert & military-grade audit closures) | ✅ |
| Accessibility | Touch/mouse/keyboard parity, 44px touch targets, semantic canvas handles, Esc closes dialogs, reduced-motion (3 signals) | ✅ |

## Requirements

- Flutter 3.47.0 (Dart 3.12.2) or later stable
- Windows build: Visual Studio 2022+ (C++ desktop development workload)
- Android build: Android SDK (compileSdk 36) + JDK 17+

## Quick Start

```bash
flutter pub get
flutter run -d windows     # Windows desktop
flutter run -d android     # Android device/emulator
flutter build windows --debug
flutter build apk --debug
```

## Tests & Quality Gates

```bash
flutter analyze   # must report "No issues found" (commit gate)
flutter test      # 1851 tests (canvas / block docs / security audit regressions /
                  # WebDAV sync / export pipelines + 2026-09 full audit regressions;
                  # real-KDF cases split into a serial tagged suite)
flutter test test/architecture_test.dart   # 9 architecture rules (layer direction incl.
                                           # rendering layer, zero cycles, feature isolation,
                                           # onion rules, Martin coupling baseline)
bash tools/check_boundaries.sh             # boundary checks
python tools/code_guard.py --dir lib --force-native --json   # line-count gate
```

All five CI workflows (CI / quality gate / Code Guard / SBOM / Secret Scan) must be green before merge.

## Security Features (expert-audit closure)

| Component | Description |
| --- | --- |
| Encrypted notes | AES-256-GCM + AAD context binding (NIST SP 800-38D) — content/media/trash encrypted, per-encryption random nonce |
| Per-note keys | Independent data key + AAD bound to note ID — one leaked note key never affects others (Knovya pattern) |
| App-lock PIN / vault | Argon2id derivation + constant-time comparison + persistent exponential backoff; versioned envelope encryption + atomic commits |
| Quick unlock | Windows Hello / Android BiometricPrompt (local_auth), DPAPI/Keystore-bound |
| USB reset disk | "Forgot password" reset for notebook/file passwords (LUKS-style: disk key unwraps DEK → re-wrap password slot with new salt) |
| Policy engine | Operation allowlist with **default-deny** (fail-closed) + audit — import/delete gated |
| Session guard | Immediate lock on backgrounding / minimize (memory keys zeroed) + file-picker exemption + re-auth. Note: on desktop, plain window focus loss (still visible) and Win+L do **not** currently trigger the boot lock — the gate only reacts to hidden/paused; tracked as a known gap |
| VFS encrypted vault | Object manifest + version rollback + AAD binding + atomic commits (crash-safe) |
| Tamper-evident audit | SHA-256 hash chain (prevHash linkage — tamper breaks chain) + verifyIntegrity; user-facing errors always sanitized |
| Import isolation | SVG preflight (XXE/Billion Laughs/script injection/bomb) + PDF page/size quotas + hyperlink scheme allowlist |
| Release gates | SBOM generation (CycloneDX) + secret scanning (Gitleaks pattern) + CI integration |

## Data Storage

All business data lives under a single data root in the system **Application Support** directory: `绘图笔记数据/` (Windows typically `%APPDATA%\<app>\绘图笔记数据\` — **S-02 option B**: not under the Documents Known Folder, so it is not cloud-synced by default). First access migrates any legacy scattered paths / old Documents root into the new root without overwriting existing data.
(legacy scattered locations are migrated in on first access — never overwriting):

```
<ApplicationSupport>/绘图笔记数据/
├── documents/            standalone drawing project files (JSON — layers & strokes)
├── documents_trash/      drawing trash
├── thumbnails/           drawing thumbnails
├── document_images/      imported image copies
├── notebooks/            notebook (paged canvas) project files
├── notebook_images/      notebook image copies (sealed per encryption tier)
├── blockdocs/            typed notes (block docs)
├── blockdocs_trash/      block-doc trash
├── security/             vault keys + app-lock guard keys
└── *.json                favorites / tags / schedule configs
```

## Technical Highlights

- Canvas: Flutter `CustomPainter` + `Canvas` API (no third-party drawing engine);
  viewport culling + per-layer render-plan cache + incremental dirty-rect rebuild
- Stroke model: vector point sequences (undo/redo, layer merge, lossless export at
  any resolution); hot paths (inking/erasing) driven by frameTick, decoupled from
  panel rebuilds
- Off-main-thread: large JSON codecs, encryption envelopes, JPEG compression, ZIP
  packaging and PDF composition all run in background `Isolate.run`
- Design system: Apple HIG static tokens (`apple_design.dart`) + Emil motion tokens
  (`apple_motion.dart`) + liquid-glass floating layers (blur σ=12 + saturate 1.4,
  floating layers only)
- Architecture guardrails: Feature-First layering (presentation/application/
  infrastructure/rendering/domain) + core contract injection (zero cross-feature
  direct imports) + 9-rule dart_arch_test gate
- Auto-save: debounced persistence + exit-time backup; critical writes always
  tmp + rename atomic (crash-safe)

Design docs: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/PHASES.md`](docs/PHASES.md).
Changelog: [`CHANGELOG.md`](CHANGELOG.md).

## Open Source

- 📄 License: [MIT](LICENSE)
- 🤝 Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- 🔒 Security policy: [SECURITY.md](SECURITY.md)
- 📜 Code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 📝 Changelog: [CHANGELOG.md](CHANGELOG.md)
