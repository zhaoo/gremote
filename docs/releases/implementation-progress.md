# Release delivery progress

Plan: docs/superpowers/plans/2026-10-19-release-delivery.md

Ruling: Work in existing develop checkout as user explicitly requires; no alternate feature branch.
Ruling: User explicitly authorizes continuous implementation after design approval; no repeated plan review gate.
Initial state: clean develop, base e6600cc. Website and deployment share website/ archive schema; platform releases do not depend on website availability.

Task 1: A website implemented. Browser 360px menu open/close and FAQ verified; headline adjusted after visual check.
Task 2: 7 deployment tests observed failing without implementation, then passing with archive validation, locking and rollback. DNS/server now confirmed.
Task 3: Dedicated key generated with user authorization; local ignored key.properties and keystore permissions restricted.

Task 3: complete — Android 1.0.1+4 dedicated signing verified and published at https://github.com/zhaoo/gremote/releases/tag/v1.0.1. Existing v1.0.0 retained. Missing signing rejected by actual Flutter release command. Local keystore must be backed up by owner.
Task 4: code preparation delivered, not iOS validated. Native Swift bridge implementations, generated Pigeon protocols, iOS project, permissions, PhotoKit, local network/stream/download, location, FFI build pipeline added. Full Flutter 330 tests and analyze passed. Xcode/iOS SDK/Apple membership absent; no TestFlight build exists.
Final review: independent read-only review found 5 Important issues, all code paths corrected: native lost event, JPEG input scope, cloud-only EXIF skip, real WebSocket open/closed events, bounded archive decompression. Only archive fix has executable regression RED→GREEN here; Apple API fixes require SDK/device validation.
Ruling: Reviewer timestamp item promoted from minor to correctness fix because dateModified is seconds in the existing Dart/SQLite contract; iOS now uses seconds. Cost if wrong: photo ordering regression, covered in pending Swift policy test.
Final verification: deployment 8 tests pass, C++ host CTest pass, Swift parse-stdlib/plist/pbxproj/Podfile/shell syntax checks pass. Pure Swift executable policy tests are not passing evidence: system kills execution with exit 137; Foundation test is blocked by CLT SwiftBridging duplication.
Task 2 remaining external action: SSH previously verified on 47.96.158.25 is now banner-timeout; HTTPS previously verified now times out after corporate domain restriction was lifted by user. Dedicated GitHub deploy secret/host/known-host vars were set, but server dedicated public-key installation and latest hardened publisher/site sync are still pending. Do not trigger CI before the public key is installed.
