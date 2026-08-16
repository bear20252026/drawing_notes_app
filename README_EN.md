# Drawing Notes App

A cross-platform **drawing and note-taking** application for **Windows desktop + Android**, built with **Flutter (Dart)**.
100% local & offline — **no cloud sync, no accounts, no AI features, no network requests**.

![CI](https://img.shields.io/github/actions/workflow/status/bear20252026/drawing_notes_app/ci.yml)
![License](https://img.shields.io/github/license/bear20252026/drawing_notes_app)

> **Security posture**: government-grade security — encrypted notebooks (per-note K_note keys),
> policy engine (default-deny), session guard (auto-lock), VFS encrypted object vault
> (versioned / atomic commits), tamper-evident audit (SHA-256 hash chain), import isolation
> (SVG/PDF preflight).

---

## Features

| Phase | Content | Status |
| --- | --- | --- |
| 1 | Minimal canvas: draw lines, undo, clear | ✅ |
| 2 | Drawing tools: pen width, color palette, eraser (transparent), eyedropper | ✅ |
| 3 | Layers: create/delete/visibility/opacity/order/merge | ✅ |
| 4 | Selection & transform: rect/lasso, move/scale/rotate, copy/paste/delete | ✅ |
| 5 | Notebooks: notebook/page management, text input, image embedding | ✅ |
| 6 | Persistence: auto-save, thumbnail list, PNG export, delete confirmation | ✅ |
| 7 | Polish: dark mode, pinch gestures, fullscreen, onboarding | ✅ |
| Security | Expert-audit closure: P0-P2 fixes + military-grade audit chain + encryption system | ✅ |

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

## Tests & Static Analysis

```bash
dart analyze   # zero issues (project uses dart analyze due to Chinese path LSP compatibility)
flutter test   # 391+ tests (Phase 1-7 + security audit regressions)
flutter test test/architecture_test.dart   # +5 architecture rules
bash tools/check_boundaries.sh             # boundary checks
python tools/code_guard.py --dir lib --force-native --json   # line-count gate
```

## Security Features (expert-audit closure)

| Component | Description |
| --- | --- |
| Encrypted notebooks | AES-256-GCM + AAD context binding (NIST SP 800-38D) — content/media/trash encrypted |
| Per-note K_note keys | Independent data key + AAD bound to notebook ID — one leaked note key never affects others |
| Policy engine | Operation allowlist with **default-deny** (fail-closed) + audit — import/delete gated |
| Session guard | Immediate lock on focus loss (memory keys zeroed) + file-picker exemption + re-auth |
| VFS encrypted vault | Object manifest + version rollback + AAD binding + atomic commits (crash-safe) — media objects onboarded |
| Tamper-evident audit | SHA-256 hash chain (prevHash linkage — tamper breaks chain) + verifyIntegrity |
| Import isolation | SVG preflight (XXE/Billion Laughs/script injection/bomb) + PDF page/size quotas |
| Release gates | SBOM generation (CycloneDX) + secret scanning (Gitleaks pattern) + CI integration |

## Data Storage

All data lives under the app documents directory:

```
<documents>/
├── documents/        standalone drawing project files (JSON — layers & strokes)
├── thumbnails/       drawing thumbnails (PNG)
├── notebooks/        notebook project files (JSON — all pages)
└── notebook_images/  embedded page images (new media via VFS encrypted objects)
```

## Technical Highlights

- Canvas: Flutter `CustomPainter` + `Canvas` API (no third-party drawing engine)
- Stroke model: vector point sequences (undo/redo, layer merge, lossless export at any resolution)
- Layer cache: offscreen bitmap (`PictureRecorder → toImage`) for smooth drawing
- Auto-save: 800ms debounce + exit-time backup save
- Architecture: God Class split (8 pure-computation services — official incremental approach) + five-domain notifiers

Design docs: [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md), [`docs/AUDIT_REPORT_2026-08-15.md`](docs/AUDIT_REPORT_2026-08-15.md), [`docs/PHASES.md`](docs/PHASES.md).

## Open Source

- 📄 License: [MIT](LICENSE)
- 🤝 Contributing: [CONTRIBUTING.md](CONTRIBUTING.md)
- 🔒 Security policy: [SECURITY.md](SECURITY.md)
- 📜 Code of conduct: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- 📝 Changelog: [CHANGELOG.md](CHANGELOG.md)
