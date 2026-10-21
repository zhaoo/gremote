# Third-party notices

The GR III profile and container codec in `m10v_core/profile.py` and
`m10v_core/codec/` are derived from `gr-custom-tool` (DoYitNow), licensed
under GPL-2.0-only. Source file SHA-256 values at import:

`node/firmware.mjs` ports the read-only GR III profile and decoding checks
from those files; it is also covered by this project's GPL-2.0-only license.

- `profiles/gr3.py`: `b5d90aaeaff45531d7f59904ab5eded33a2b5fc2259030c225faf6970c0a0ca7`
- `codec/container.py`: `7f6f83ac21387dd08002a5a0c20fccac6f212e398079c9694304463b6c163a45`
- `codec/frames.py`: `cd89e80080d7e8f1e940b7c737d9d3966ec75fb04a9961b9a1daeb5d19f9b078`

See `LICENSE`. The user's official firmware is not included in this source tree.

## GR IV official-input compatibility and GR II container research

M10V adds an authored `vendor/gr4/gr4_editor/m10v_official_entries.py` compatibility
module and local patches to the vendored `slots.py` and `registry_resources.py`.
They preserve official 1.11.10.7 entry instructions and read its 34-column color
tables through the verified startup RAM mapping, rather than assuming the older
research image's branch wrappers and 37-column ROM tables. Original import hashes
remain in `vendor/gr4/PROVENANCE.json`; local modifications are recorded separately.
These changes retain GPL-2.0-only licensing.

GR II's UNITY encoding facts were investigated using the public
[gr2-boot research](https://github.com/lc2425150/ricoh-gr2-boot-screen-mod), then
independently validated against the user's official image. Its source code was
not copied. M10V's decoder is authored here, including nested containers and the
independently established 512-byte resource-volume offset. See the model-port
research report for exact input hashes and research checkout provenance.

## GRLife compatibility data and local runtime

`web/gr3/film-catalog.json` contains 32 fitted film entries and camera icon pixels
derived from the [public GRLife film catalog](https://grlife.app/firmware-store/film-catalog.js).
Its film fitting data are attributed upstream to `film/NOTICE.md`, including
CC BY-SA 4.0 material; retain the upstream attribution and share-alike
requirements when redistributing that data.
`web/gr3/community-data.json` contains reference recipe values from the public
GRLife community catalog. The user-supplied modified firmware is used for
byte-level regression evidence; it is not distributed in this repository.

The GRLife Python browser core and three JavaScript fitting modules are
downloaded by `scripts/sync-grlife-runtime.mjs` into the ignored `.runtime/`
directory. Each fetched file is pinned by SHA-256 and verified before use.
GRLife source code is not bundled or relicensed by m10v. Users should review
GRLife's applicable license and terms before redistributing a packaged runtime.

The current GRLife runtime manifest SHA-256 is
`1dff66f9e243329ed4ab95b9b7bb4bef74846848f62ae29172d8f3c74574688b`.
Its film-bay extension and film data stay in the ignored local runtime;
m10v's independently written audit reads their pinned hashes and checks the
generated firmware. GRLife separately issues device-bound `FILMS.GRF` files
through its service. m10v does not call that issuer. Its alternative generator
signs plaintext records with a public project key, and its firmware overlay
replaces only the film-bay module's verification public key. This key grants no
access to GRLife's issuer. The original runtime stays hash-pinned and unmodified.

## GR IV reference core

`vendor/gr4/` contains a deterministic source snapshot of the GPL-2.0-only
`gr-custom-tool` distribution by DoYitNow. It includes the Python/native core,
browser source and Lightroom bridge. Three large calibration DNG samples remain local and are excluded from the Git source distribution; their original names and hashes remain in the provenance manifest for restoration. The precise
source commit, every included file hash and size, and intentional exclusions are
recorded in `vendor/gr4/PROVENANCE.json`. The standalone upstream HTTP server and
runtime data are excluded; m10v supplies its own loopback server and product UI.

## Darkslide GR preset metadata

`vendor/darkslide/gr3_v210.json` is copied from LiorMoment/darkslide-gr,
commit `9913169558d725d44400e297ff0bebe2c252abc7`, GPL-2.0-only.
The corresponding license is preserved at `vendor/darkslide/LICENSE`.
The new JS resource reader/editor is implemented in m10v from the GR III
layout, with Darkslide's slot metadata, name storage rules and findings credited.

RAW noise-reduction layout references `idontknownihil/gr3-film-mods`, commit
`04d5d5dd6e85d80089c6200bd0f0de5fff2d658f`; upstream code/notes are MIT.
The new XMP conversion uses the already pinned GPL gr-custom-tool reference
renderer and its Adobe DNG table format decoder, then fits GR III parameters.
It does not reuse GR IV firmware color tables or include an official BIN.

## Ricoh-GRMod digital soft-focus coefficients

The three Q10 coefficient rows in `scripts/build_gr3_digital_hdf.py` reference
`idontknownihil/Ricoh-GRMod`, commit
`16327dbe7bf9e5fd5e4db99ef47237b2240e5487`,
`core/src/fw/clarity.ts` (GPL-2.0, compatible with this project).
The GR III firmware addresses, recipe ownership adapters, settings integration
and audit are independently implemented from the exact GR III 2.10 firmware.
No GR IV executable patch or camera firmware binary is copied into the source.

## GR III power image resource references

The fixed-size shutdown JPEG replacement and A-drive installation approach were
informed by [Darkslide GR](https://github.com/LiorMoment/darkslide-gr),
`darkslide/shared_shutdown.py` and `darkslide/a_shutdown.py` (GPL-2.0-only).
M10V rechecks paths, descriptors and resource slots against its hash-pinned
GR III 2.10 input and implements its own JS container composition and readback.
The independent StartUp JPEG slot is not a GR II BRP patch. No manufacturer's
firmware or JPEG artwork is added to the source distribution.

## Additional film colour references

The C200, Aerochrome 1443, Aerocolor 2460 and VISION3 5203 models use their
individual digitized characteristic and sensitivity data from Jan Lohse's
[spectral_film_lut](https://github.com/JanLohse/spectral_film_lut) (MIT).
The retained license is `third_party/spectral-film-lut/LICENSE`; exact input
hashes and M10V's separate display adaptation are recorded in
`native/gr3/newstocks-reference.json`.

The T-Max 100 display reference comes from
[YahiaAngelo/Film-Luts](https://github.com/YahiaAngelo/Film-Luts), identified
upstream as a G'MIC film LUT. Its MIT license and original cube header are
retained in `third_party/curated-film-luts/`. ProImage 100 uses M10V's manual
reading of Kodak E-4L curves. These are approximate display interpretations,
not manufacturer-supplied transforms or measured camera/film calibration.
