# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

**面试智练 (MianShi ZhiLian)** — a local-first technical interview active-recall learning workbench. Users learn structured knowledge routes, practice active recall, get AI evaluation, and track mastery. Supports Flutter Web, Android, macOS, Windows clients plus a Cloudflare Workers API.

## Repository Structure

```
mianshi-zhilian-app/
├── apps/client/         # Flutter client (primary codebase)
├── workers/api/         # Cloudflare Pages Functions (TypeScript)
├── scripts/             # Build, release, and pre-commit check scripts
└── .github/workflows/   # CI/CD (ci.yml, deploy workflows)
```

## Commands

### Flutter Client (`apps/client/`)

```bash
flutter pub get                          # Install dependencies
bash tool/generate_version.sh           # Generate lib/generated/app_version.g.dart and web/version.json
flutter run -d chrome                   # Run in browser
flutter analyze --no-fatal-infos        # Static analysis
python3 lib/l10n/check_l10n_keys.py     # l10n key consistency check
flutter test                            # Run all tests
flutter test test/integration/          # Business-layer end-to-end (real content pipeline)
flutter test test/path/to_test.dart     # Run a single test
flutter build web --release             # Build web
```

**Testing strategy** (see [docs/testing.md](docs/testing.md)): prioritize business/data-layer end-to-end tests driven by realistic 3-domain content fixtures (`test/fixtures/content_full/` + `FakeContentClient`, which exercise the real `ContentApiService`/`ContentProvider` — not mocks). Keep full-page widget tests minimal (they're layout-fragile under the test viewport); cover only small key controls in `test/widget/`. Content (domains/topics/learningPaths/ids) is the single source of truth — tests must use content-shaped data.

### Cloudflare Worker (`workers/api/`)

```bash
npm install                 # Install dependencies
npx wrangler pages dev src/ # Local dev server
npm run typecheck           # TypeScript type check (npx tsc --noEmit)
```

### Pre-commit (from repo root)

```bash
./scripts/pre-commit-check.sh   # Runs all 7 checks: deps, version gen, l10n, analyze, test, web build, worker typecheck
```

## Flutter Client Architecture (`apps/client/lib/`)

The app uses **Provider** for state management with a layered architecture:

**Providers** (state/business logic layer):
- `auth_provider.dart` — authentication state, login/logout
- `content_provider.dart` — knowledge routes and topic content (lazy-loaded by domain)
- `progress_provider.dart` — learning progress, mastery scores, practice records
- `ai_provider.dart` — AI model configurations (multi-model, OpenAI-compatible API)
- `settings_provider.dart` — app settings, sync targets, preferences
- `connectivity_provider.dart` — network state

**Services** (infrastructure layer):
- `storage_service.dart` — local storage via `shared_preferences` for app/business data (sqflite is not used and was removed as a dependency). **Exception: sensitive credentials are NOT stored in plain SharedPreferences** — AI API keys and remembered login passwords go to the OS secure store (Keychain/Keystore/DPAPI) via `flutter_secure_storage` on native platforms; see `credential_store.dart` and the secure-storage paths in `storage_service.dart`. Never move secrets back into plain SharedPreferences
- `ai_service.dart` — AI API calls (streaming, evaluation)
- `data_sync_service.dart` — file/WebDAV/GitHub/Gitee sync with whitelist snapshot
- `content_api_service.dart` — fetches knowledge content from CDN (dual-source fallback)
- `endpoint_fallback_client.dart` — HTTP client with primary/backup URL fallback
- `update_service.dart` — in-app update check with SHA256 verification

**Pages** organized by feature:
- `learning/` — dashboard, knowledge catalog, topic detail
- `practice/` — 8 practice modes: today review, recall, follow-up, weakness training, high-frequency sprint, project dig, system design, mock interview
- `mastery/` — mastery dashboard
- `prep/` — interview prep workbench (JD analysis, project library, answer versions)
- `profile/` — AI config, sync/backup, appearance, on-device models
- `auth/` — login, change password

**Routing**: `go_router` with a shell route (`learning_shell.dart`) for bottom nav.

**Localization**: ARB files in `lib/l10n/`. After adding/modifying keys, run `check_l10n_keys.py` to validate consistency.

**Generated files**: `lib/generated/app_version.g.dart` is generated from `pubspec.yaml` — never edit manually, always run `bash tool/generate_version.sh`.

## Cloudflare Worker Architecture (`workers/api/`)

Deployed as **Cloudflare Pages Functions** (not a standalone Worker). Entry: `src/_worker.js` / `src/index.ts`.

Bindings:
- `DB` — Cloudflare D1 (SQLite) for user data
- `KV` — Cloudflare KV for session/cache
- `JWT_SECRET` — set via Cloudflare Pages Dashboard (not in wrangler.toml)

The `wrangler.toml` uses `PLACEHOLDER_KV_NAMESPACE_ID` and `PLACEHOLDER_DATABASE_ID` — these are substituted by CI (`sed`) from GitHub Secrets before deployment. Do not put real IDs in this file.

Content is served from two CDN origins (primary + backup) configured in `[vars]`.

## Commit Message Format

Follow `.gitmessage` convention — Chinese descriptions, type prefix required:
```
feat: 功能描述
fix: 问题描述
chore: 构建号 N→N+1
```

## Version Bumping

The build number is tracked in `apps/client/pubspec.yaml` as `version: x.y.z+BUILD`. After incrementing, run `bash tool/generate_version.sh` to regenerate version files. The `scripts/auto-release.sh` handles release automation.

## Data Privacy Constraints

The sync snapshot uses a **whitelist** approach — only explicitly allowed fields are exported. When adding new data fields, consciously decide whether they belong in the sync snapshot. API keys must never appear in exports, sync payloads, or logs.
