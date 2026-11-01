# Camera extensions implementation

Spec: ../specs/2026-11-01-camera-extensions-design.md. Execution authorized by user's 继续完成扩展部分功能. Known UI already approved. Independent backend/runtime investigations completed and stable interfaces frozen before parallel implementation.

1. Portable protocol/backend: new extensions.h/.c + contract; authenticated isolated caps/state/one-field operations/poll routes; fixed <1024-byte wire; strict CAS/dedup/readback/uncertainty; preserve old responses. TDD portable/http/Linux tests and ARM service stack budget.
2. AppMain runtime adapter: read truthful live/journal state; reuse existing setters/full-struct journals, narrow private A/B/aspect wrappers; shared owner/pending/mutation gates; source fingerprints/build closure; full feature candidate. TDD owner/ARM/ISP regression; final manifest/BIN checks.
3. GRemote: typed protocol/client using same serial session; route allowlists; durable pending coordinator; foreground/transfer/film safety gates; fresh readback; UI grouped actual settings and one-field confirmation; no arbitrary power-image upload. TDD signed legacy404, parse/ranges, CAS/unknown/no replay, failed persistence, lifecycle/UI.
4. Integrate and validate: complete relevant Flutter/analyze/Android tests; native portable/ARM/ISP checks; actual firmware and SD package/app artifacts hashes; install App on authorized USB device. Candidate installation and camera acceptance remain explicit physical step; never claim host proof as camera proof.
5. Fresh whole-change review, fix Important/Critical once with regressions; deliver test package and clear setup/recovery steps.

Review focus: shared session/pending isolation; journal partial write versus false success; old firmware compatibility; changed owner/boot during writes; memory/relocation/ISP and disabled-module truthfulness.
