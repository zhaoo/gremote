# Release delivery implementation plan

> **For agentic workers:** Use superpowers:executing-plans. 用户已授权直接实施，不重复请求阶段确认。

**Goal:** Deliver the approved A website, controlled Baota deployment, Android release signing, and an honest iOS adaptation path.
**Architecture:** Static website and independently deployable version directories. Native platform releases remain separate from website delivery.
**Tech Stack:** HTML/CSS/JavaScript, Python deployment validation, Gradle, Flutter/Swift.
**Spec:** docs/superpowers/specs/2026-10-19-release-website-design.md

## Global Constraints
- Work on develop; preserve unrelated changes and previous release assets.
- Chinese UI; real release data; no unsupported device or performance claims.
- Signing material never enters Git or logs. Missing release signing must fail.
- iOS requires real native bridge implementation and device validation before availability claims.

## Review Focus
- Mobile navigation, keyboard access and reduced motion.
- Release data unavailable: retain a working static release link.
- Malicious deployment archives and concurrent deployments.
- Existing debug installs cannot upgrade with a different key.
- iOS platform behavior differs from Android and must remain explicit.

### Task 1: Static website
Files: website/index.html, style.css, app.js, releases.json, assets/.
- [ ] Build A layout with real assets, accessible navigation and native FAQ.
- [ ] Render releases from local JSON using text nodes with static fallback.
- [ ] Verify desktop/mobile appearance, links, keyboard, menu and reduced motion in browser.

### Task 2: Controlled static deployment
Files: deploy/publish_site.py, deploy/nginx.conf, deploy/README.md, tests/test_site_deploy.py, .github/workflows/deploy-website.yml.
- [ ] Test valid archives, traversal, symlinks, missing assets, version identifiers, rollback and locking; observe failure before implementation.
- [ ] Validate complete archive before extraction; atomic current symlink, explicit previous rollback, fixed deploy root.
- [ ] Run unittest and workflow checks; inspect Baota and DNS live; deploy only with verified access.

### Task 3: Android signing
Files: android/app/build.gradle, scripts/build_android.sh, docs/releases/android-signing.md.
- [ ] Load ignored key.properties, validate required values and file before release tasks; no debug fallback.
- [ ] Verify missing configuration fails, debug still works; use official key if available.
- [ ] Publish a new immutable version only after signing/build verification.

### Task 4: iOS readiness
Files: docs/releases/ios-testflight.md, platform files as verified toolchain permits.
- [ ] Inventory bridge methods, permissions, native imaging and platform assumptions.
- [ ] Verify Xcode and Apple account availability before generating and claiming working native code.
- [ ] Implement verifiable components; report external prerequisites precisely; no fictitious build/test evidence.
