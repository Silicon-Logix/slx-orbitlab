<!-- Silicon LogiX / SLX OrbitLab
Copyright (c) 2026 Marco Pezzullo (Silicon LogiX).
Author: Marco Pezzullo
License: Silicon LogiX Evaluation License 1.0. See LICENSE. -->

# Distribution and proprietary-core protection

The mission implementation resides in `private/core/`. Only the Qt-independent C ABI in `core/include/SiliconLogiX/OrbitLab/Core.h` is public. Windows links an approved DLL/import-library pair; Linux links an approved `.so`. Orbital operations require core **0.6.0 or newer, ABI 2**. Additive interfaces preserve existing configuration, measurement and control layouts.

## GitHub source

The public source package excludes the proprietary implementation, core binaries, build/cache directories, operator recordings, raw diagnostics, native Blender sources, editor files and development history. Approved GLBs, branding, adapters, examples, tests and notices remain. Binary SDKs are supplied separately. Users need a matching SDK to build and execute the full mission path.

Prepare a fresh local publication tree with:

```powershell
./scripts/export-public.ps1
```

The exporter copies an allowlist, audits contents and compares file hashes against private sources, including files renamed during copying. Existing output directories are never overwritten. `-InitializeRepository` creates and stages a new local Git repository and audits staged bytes and its history. It creates no remote and performs no upload.

Before committing from the publication tree:

```powershell
python tools/audit-source.py --public --github --git
```

The audit rejects private/generated files, common credential formats, developer paths, internal notes, source implementation signatures and oversized files. Attribution, resource paths, document links and English operator copy are checked. GitHub Actions repeats these checks on pushes and pull requests. These scans are safeguards with defined patterns; they cannot guarantee discovery of every possible secret.

`.gitignore` prevents future accidental additions; it does not remove already tracked files or earlier commits. If publishing an existing repository, inspect its actual history and branches before upload. Do not attach the development repository or old export directories to the new public repository.

## Evaluation binary SDK

For a local source package with an approved SDK, use `-IncludeSdk` and a distinct output directory. SDK copies have debug/static symbols removed and are audited again. Original development libraries remain untouched. The package retains notices and public ABI contracts. A separate backend cache (`SLX_BACKEND_HOME`) is required for an independent checkout because each CMake build directory belongs to one source path.

The Evaluation License restricts permitted use and preserves ownership. Keeping the implementation outside GitHub protects its source from publication. **A distributed binary can still be analyzed or reverse engineered; symbol stripping and license terms do not provide absolute technical protection.** If disclosure of an algorithm is unacceptable, keep its executable on infrastructure controlled by Silicon LogiX and expose an agreed service interface.

Qt, Godot, F Prime, Basilisk and RTEMS retain their own licenses. The source export includes relevant notices and Qt/Godot license texts; bootstrap scripts fetch upstream tools separately. A portable runtime release must also satisfy the corresponding third-party source/relinking requirements. Preserve public interfaces needed to replace or relink LGPL-covered components.
