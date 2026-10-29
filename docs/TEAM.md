# Murzik engineering team — shared rules

Product: **Murzik**, a cute black cat for an iPhone 15 Pro Max (iOS 26) that lives in and around the
Dynamic Island. The user (building it for his wife) wants: a **full-body 3D cat with lots of animations**
that **walks around the Dynamic Island**. Be creative and ambitious, but ship working code.

## Environment facts (read carefully)
- There is **no Swift compiler or Xcode locally** (Linux). The only way to compile/test is CI:
  push your branch → GitHub Actions (macos-26, Xcode 26.6, iOS 26.5 simulator "iPhone 17 Pro Max")
  generates the project with XcodeGen, runs unit + UI tests on the simulator, builds an unsigned device IPA.
- After pushing, run `scripts/ci-wait.sh` from your worktree. It waits for the run of your HEAD commit,
  prints status, compile errors and failed tests, and copies renders/screenshots to `/tmp/ci-<branch>/renders`.
  **Look at the PNGs with the Read tool** — that is how you see your work. A CI round takes ~8–20 min, so
  batch changes, re-read your code carefully before each push, and keep iterating until it is green and good.
- Tests can write images: in unit/UI tests, write PNGs to `ProcessInfo.processInfo.environment["RENDER_DIR"]`
  (subfolders allowed); they appear in `/tmp/ci-<branch>/renders`.
- Project: `project.yml` (XcodeGen). Targets: `Murzik` (App/ + Shared/), `MurzikWidgets` app extension
  (Widgets/ + Shared/, compiled with `WIDGET_EXTENSION` flag and `APPLICATION_EXTENSION_API_ONLY=YES`),
  `MurzikTests` (Tests/, hosted by the app, `@testable import Murzik`), `MurzikUITests` (UITests/).
  New files inside those folders are picked up automatically. Deployment target iOS 17.0, Swift 5 language mode.
- Anything in Shared/ must compile in the widget extension too (no UIApplication.shared, no SceneKit views there,
  keep memory small — Live Activities have a ~30 MB limit and images must be small).
- iOS rules: a Live Activity cannot animate continuously; it changes only when its content is updated
  (animations ≤2 s between states), max 8 h. Only `Text(timerInterval:)`, `ProgressView(timerInterval:)`
  and date-relative text update by themselves. Updates can be sent while the app runs (foreground, a
  background task of ~30 s, or a `LiveActivityIntent` button). No push server exists.
- UI language is Hebrew (`Shared/Model/Strings.swift`); code, comments and commits in English.

## Git rules
- Work **only in your own worktree and branch** (given in your brief). Commit often with clear messages.
  Push with `git push origin <your-branch>`. Never push to `main`, never force-push, never touch other branches.
- **Only edit files you own** (listed in your brief). If you need a change elsewhere, describe it in your
  final report instead. Adding new files in your own folders is always fine.
- End every commit message with these two lines:
  `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`
  `Claude-Session: https://claude.ai/code/session_01K14kV3VfMuf1bLjtcgscGa`
- Use `git -c user.name="Claude" -c user.email="noreply@anthropic.com" commit ...`.
- GitHub CLI: use `env -u GH_TOKEN gh ...` (REST only; GraphQL is blocked).

## Contracts (do not break)
- `Shared/Character/MurzikSprite.swift`: names/conventions of pre-rendered 3D sprites (square transparent PNG,
  64pt × 3, side views face right, feet on the bottom edge). `SpriteImage` falls back to the 2D cat if missing.
- `App/Cat3D/Murzik3DController.swift`: the API the app screen uses to drive the 3D cat.
- `MurzikActions` / `LiveActivityController.reconcile` / `PetStorage` / `PersonalityEngine` public APIs stay
  source-compatible (you may add, not remove/rename).

## Definition of done for your part
Green CI on your branch (all tests pass, IPA builds), screenshots/renders that you have actually looked at and
are proud of, no new warnings you could easily fix, and a final report: what you built, files, how others
integrate it, what you verified (with the render file names), and anything unverified.
