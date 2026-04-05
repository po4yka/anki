# Stripping Anki to Its Rust Core: Execution Guide

## Overview

This guide removes all non-Rust UI code (PyQt, Svelte/TypeScript, Python bindings), all
platform-specific code targeting Windows and Linux, and all build tooling that depends on
Python or Node. What remains is the Rust workspace: `rslib`, `rslib/i18n`, `rslib/io`,
`rslib/process`, `rslib/proto`, `rslib/sync`, `rslib/linkchecker`, the `ftl` crate, and
the `qt/launcher` crate (macOS platform code only). The `cargo/` directory and root-level
Rust config files are preserved unchanged.

---

## Phase 1: Bulk Directory Removals

Remove these directories in their entirety.

```
REMOVE: qt/aqt/           # PyQt GUI (218 files, ~2.5M Python)
REMOVE: ts/               # Svelte/TypeScript frontend (520 files, ~2.6M)
REMOVE: pylib/            # Python library + PyO3 bridge (97 files, ~1.3M)
REMOVE: python/           # Python utilities (2 files, ~8K)
REMOVE: tools/            # Python dev tools (23 files, ~100K)
REMOVE: build/            # Ninja build system, Python-based (264K)
REMOVE: .github/          # Multi-platform CI workflows (20K)
REMOVE: .buildkite/       # Buildkite CI config (40K)
REMOVE: .idea.dist/       # IntelliJ project template (4K)
REMOVE: .vscode.dist/     # VS Code project template (16K)
REMOVE: .cursor/          # Cursor IDE config (8K)
```

Commands:

```bash
cd /path/to/anki

rm -rf qt/aqt
rm -rf ts
rm -rf pylib
rm -rf python
rm -rf tools
rm -rf build
rm -rf .github
rm -rf .buildkite
rm -rf .idea.dist
rm -rf .vscode.dist
rm -rf .cursor
```

Validation:

```bash
ls qt/           # should show: icons  launcher  mac  release  tests  tools
ls               # pylib/ ts/ python/ tools/ build/ .github/ .buildkite/ should be gone
```

---

## Phase 2: Root File Removals

Remove these files from the repository root.

```
REMOVE: package.json         # Node.js package config
REMOVE: yarn.lock            # Yarn lockfile
REMOVE: .yarnrc.yml          # Yarn config
REMOVE: yarn                 # Yarn wrapper script
REMOVE: yarn.bat             # Yarn wrapper (Windows)
REMOVE: pyproject.toml       # Python project config (uv/ruff/mypy settings)
REMOVE: uv.lock              # Python lock file
REMOVE: .python-version      # Python version pinning
REMOVE: .mypy.ini            # Python type checker config
REMOVE: .ruff.toml           # Python linter config
REMOVE: .eslintrc.cjs        # JavaScript linter config
REMOVE: .prettierrc          # JavaScript formatter config
REMOVE: .dprint.json         # Multi-language formatter config
REMOVE: .readthedocs.yaml    # ReadTheDocs config
REMOVE: .dockerignore        # Docker config
REMOVE: run.bat              # Windows run script
REMOVE: check                # Python-based build entry point (keep if repurposing)
REMOVE: ninja                # Python-based ninja wrapper
```

Note: `run` (the Unix run script) invokes the Python build system. Remove it along with
`ninja` and `check` unless you intend to repurpose those shell scripts for a Swift build.

Commands:

```bash
rm package.json yarn.lock .yarnrc.yml yarn yarn.bat
rm pyproject.toml uv.lock .python-version .mypy.ini .ruff.toml
rm .eslintrc.cjs .prettierrc .dprint.json
rm .readthedocs.yaml .dockerignore
rm run.bat run check ninja
```

Validation:

```bash
ls *.toml        # should show only: Cargo.toml rust-toolchain.toml
ls .*            # python/node config files should be absent
```

---

## Phase 3: Partial Directory Removals

### qt/

The `qt/` directory contains the launcher (keep macOS parts), icons, release scripts,
tests, and macOS packaging. Remove everything except the launcher crate and the macOS
helper.

```
KEEP:   qt/launcher/src/main.rs
KEEP:   qt/launcher/src/platform/mac.rs
KEEP:   qt/launcher/src/platform/mod.rs   # needs editing - see Phase 4
KEEP:   qt/launcher/Cargo.toml            # needs editing - see Phase 4
KEEP:   qt/mac/                           # macOS Entitlements, Info.plist, Xcode helper

REMOVE: qt/launcher/src/platform/windows.rs   # Windows launcher (263 lines)
REMOVE: qt/launcher/src/platform/unix.rs      # Linux launcher (105 lines)
REMOVE: qt/launcher/src/bin/                  # Windows-specific binaries
        qt/launcher/src/bin/anki_console.rs
        qt/launcher/src/bin/build_win.rs
REMOVE: qt/icons/                             # Qt icon assets
REMOVE: qt/release/                           # Release packaging scripts
REMOVE: qt/tests/                             # Qt Python integration tests
REMOVE: qt/tools/                             # Qt build tools (Python)
```

Commands:

```bash
rm qt/launcher/src/platform/windows.rs
rm qt/launcher/src/platform/unix.rs
rm -rf qt/launcher/src/bin
rm -rf qt/icons
rm -rf qt/release
rm -rf qt/tests
rm -rf qt/tools
```

Validation:

```bash
ls qt/launcher/src/platform/   # should show: mac.rs  mod.rs
ls qt/                         # should show: launcher  mac
```

### rslib/

Remove the Python and TypeScript code-generation modules.

```
REMOVE: rslib/proto/python.rs      # Python interface codegen (called from build.rs)
REMOVE: rslib/proto/typescript.rs  # TypeScript interface codegen (called from build.rs)
REMOVE: rslib/i18n/python.rs       # Python string bindings codegen
REMOVE: rslib/i18n/typescript.rs   # TypeScript string bindings codegen

REMOVE: rslib/src/card_rendering/tts/windows.rs   # Windows TTS implementation (110 lines)
REMOVE: rslib/src/error/windows.rs                # Windows error types (33 lines)
```

Commands:

```bash
rm rslib/proto/python.rs rslib/proto/typescript.rs
rm rslib/i18n/python.rs rslib/i18n/typescript.rs
rm rslib/src/card_rendering/tts/windows.rs
rm rslib/src/error/windows.rs
```

### docs/

```
REMOVE: docs/windows.md      # Windows developer setup
REMOVE: docs/linux.md        # Linux developer setup
REMOVE: docs/docker/         # Docker environment docs
REMOVE: docs/ninja.md        # Ninja build system docs (Python-based)

KEEP:   docs/migration/      # This guide and related migration docs
KEEP:   docs/mac.md          # macOS developer setup
KEEP:   docs/api-rust.md     # Rust API docs
KEEP:   docs/architecture.md
KEEP:   docs/protobuf.md
KEEP:   docs/syncserver/
```

Commands:

```bash
rm docs/windows.md docs/linux.md docs/ninja.md
rm -rf docs/docker
```

### ftl/

```
KEEP:   ftl/core/       # Core translation strings (40 .ftl files)
KEEP:   ftl/core-repo/  # Upstream core strings repo

REMOVE: ftl/qt/         # Qt-specific translation strings
REMOVE: ftl/qt-repo/    # Upstream Qt strings repo
REMOVE: ftl/usage/      # Translation usage tracking scripts
REMOVE: ftl/src/        # FTL crate source that generates Python/TS bindings
        (keep ftl/Cargo.toml if the ftl crate is still a workspace member)
```

Note: Inspect `ftl/Cargo.toml` and `ftl/src/` before removing. The `ftl` crate in the
workspace exists to track string usage for the build system. If you are dropping the
build system, assess whether this crate is still needed.

Commands:

```bash
rm -rf ftl/qt ftl/qt-repo ftl/usage
```

---

## Phase 4: File Modifications

### `.cargo/config.toml`

Current file (`/Users/npochaev/GitHub/anki/.cargo/config.toml`):

```toml
[env]
STRINGS_PY = { value = "out/pylib/anki/_fluent.py", relative = true }
STRINGS_TS = { value = "out/ts/lib/generated/ftl.ts", relative = true }
DESCRIPTORS_BIN = { value = "out/rslib/proto/descriptors.bin", relative = true }
# build script will append .exe if necessary
PROTOC = { value = "out/extracted/protoc/bin/protoc", relative = true }
PYO3_NO_PYTHON = "1"
MACOSX_DEPLOYMENT_TARGET = "11"
PYTHONDONTWRITEBYTECODE = "1" # prevent junk files on Windows

[term]
color = "always"

[target.'cfg(all(target_env = "msvc", target_os = "windows"))']
rustflags = ["-C", "target-feature=+crt-static"]
```

Replace with:

```toml
[env]
MACOSX_DEPLOYMENT_TARGET = "13"

[term]
color = "always"
```

Notes:
- `STRINGS_PY`, `STRINGS_TS`: removed because Python/TS codegen is gone.
- `DESCRIPTORS_BIN`: the proto build script writes descriptors to `OUT_DIR` directly when
  not overridden; if `rslib/build.rs` still reads from a fixed path, update it to use
  `OUT_DIR` (see `rslib/build.rs` modification below).
- `PROTOC`: prost-build discovers `protoc` on `PATH` when this env var is absent. Install
  `protoc` via Homebrew: `brew install protobuf`.
- `PYO3_NO_PYTHON`, `PYTHONDONTWRITEBYTECODE`: removed with Python.
- `MACOSX_DEPLOYMENT_TARGET`: bumped from `"11"` to `"13"` for a macOS 13+ SwiftUI target.
- Windows `rustflags` section: removed.

### `Cargo.toml` (root workspace)

File: `/Users/npochaev/GitHub/anki/Cargo.toml`

**Remove these workspace members** (lines 10-24):

```toml
# REMOVE:
"build/configure",
"build/ninja_gen",
"build/runner",
"pylib/rsbridge",
"tools/minilints",
```

**Resulting `[workspace] members` block:**

```toml
[workspace]
members = [
  "ftl",
  "qt/launcher",
  "rslib",
  "rslib/i18n",
  "rslib/io",
  "rslib/linkchecker",
  "rslib/process",
  "rslib/proto",
  "rslib/sync",
]
resolver = "2"
```

Note: Also remove `rslib/linkchecker` if you do not need link checking; it has no
platform-specific dependencies but is unused without the build system.

**Remove these lines from `[workspace.dependencies]`:**

```toml
# REMOVE - Python build tools:
ninja_gen = { "path" = "build/ninja_gen" }
anki_proto_gen = { path = "rslib/proto_gen" }   # if present

# REMOVE - Windows-only:
embed-resource = "3.0.4"
junction = "1.2.0"
libc-stdhandle = "0.1"
widestring = "1.1.0"
winapi = { version = "0.3", features = ["wincon", "winreg"] }
windows = { version = "0.61.3", features = ["Media_SpeechSynthesis", "Media_Core", "Foundation_Collections", "Storage_Streams", "Win32_System_Console", "Win32_System_Registry", "Win32_System_SystemInformation", "Win32_Foundation", "Win32_UI_Shell", "Wdk_System_SystemServices"] }

# REMOVE - Python bindings:
pyo3 = { version = "0.25.1", features = ["extension-module", "abi3", "abi3-py39"] }
```

**Remove the profile override for rsbridge:**

```toml
# REMOVE:
[profile.dev.package.rsbridge]
debug = 0
```

**Remove from `[workspace.dependencies]` local section:**

```toml
# REMOVE:
anki_proto_gen = { path = "rslib/proto_gen" }
ninja_gen = { "path" = "build/ninja_gen" }
```

### `qt/launcher/Cargo.toml`

File: `/Users/npochaev/GitHub/anki/qt/launcher/Cargo.toml`

Remove the Windows and Linux conditional dependency blocks and the Windows binary targets:

```toml
# REMOVE this block:
[target.'cfg(all(unix, not(target_os = "macos")))'.dependencies]
libc.workspace = true

# REMOVE this block:
[target.'cfg(windows)'.dependencies]
windows.workspace = true
widestring.workspace = true
libc.workspace = true
libc-stdhandle.workspace = true

# REMOVE these [[bin]] entries:
[[bin]]
name = "build_win"
path = "src/bin/build_win.rs"

[[bin]]
name = "anki-console"
path = "src/bin/anki_console.rs"

# REMOVE this block:
[target.'cfg(windows)'.build-dependencies]
embed-resource.workspace = true
```

Resulting `Cargo.toml` after removals:

```toml
[package]
name = "launcher"
version = "1.0.0"
authors.workspace = true
edition.workspace = true
license.workspace = true
publish = false
rust-version.workspace = true

[dependencies]
anki_i18n.workspace = true
anki_io.workspace = true
anki_process.workspace = true
anyhow.workspace = true
camino.workspace = true
dirs.workspace = true
locale_config.workspace = true
serde_json.workspace = true
```

### `qt/launcher/src/platform/mod.rs`

File: `/Users/npochaev/GitHub/anki/qt/launcher/src/platform/mod.rs`

The current file uses `#[cfg]` attributes to conditionally include `mac.rs`, `unix.rs`,
and `windows.rs`. Remove the `unix` and `windows` modules so only `mac.rs` is compiled.

Read the current file first (`cat qt/launcher/src/platform/mod.rs`), then remove any
lines of the form:

```rust
// REMOVE:
#[cfg(target_os = "windows")]
mod windows;
#[cfg(all(unix, not(target_os = "macos")))]
mod unix;
```

Keep only:

```rust
#[cfg(target_os = "macos")]
mod mac;
// ... re-exports from mac
```

Since this is now macOS-only, you may also remove the `#[cfg(target_os = "macos")]`
guard and unconditionally include `mac`:

```rust
mod mac;
pub use mac::*;
```

Verify the public API of `mod.rs` matches what `main.rs` calls before simplifying.

### `rslib/proto/build.rs`

File: `/Users/npochaev/GitHub/anki/rslib/proto/build.rs`

Current:

```rust
pub mod python;
pub mod rust;
pub mod typescript;

use anki_proto_gen::descriptors_path;
use anki_proto_gen::get_services;
use anyhow::Result;

fn main() -> Result<()> {
    let descriptors_path = descriptors_path();

    let pool = rust::write_rust_protos(descriptors_path)?;
    let (_, services) = get_services(&pool);
    python::write_python_interface(&services)?;
    typescript::write_ts_interface(&services)?;

    Ok(())
}
```

Replace with:

```rust
pub mod rust;

use anki_proto_gen::descriptors_path;
use anyhow::Result;

fn main() -> Result<()> {
    let descriptors_path = descriptors_path();
    rust::write_rust_protos(descriptors_path)?;
    Ok(())
}
```

Also remove the now-deleted `python.rs` and `typescript.rs` from the module declarations
(already reflected above).

Note: `get_services` and the services variable are no longer needed once Python and
TypeScript codegen are removed.

### `rslib/proto/rust.rs`

File: `/Users/npochaev/GitHub/anki/rslib/proto/rust.rs`

The `set_protoc_path()` function appends `.exe` on Windows and reads the `PROTOC_BINARY`
env var. With the build system gone and `protoc` on `PATH` via Homebrew, this function
is a no-op on macOS. Remove it and remove its call from `write_rust_protos`:

```rust
// REMOVE the entire function:
fn set_protoc_path() {
    if let Ok(custom_protoc) = env::var("PROTOC_BINARY") {
        env::set_var("PROTOC", custom_protoc);
    } else if let Ok(bundled_protoc) = env::var("PROTOC") {
        if cfg!(windows) && !bundled_protoc.ends_with(".exe") {
            env::set_var("PROTOC", format!("{bundled_protoc}.exe"));
        }
    }
}

// REMOVE this call at the top of write_rust_protos:
set_protoc_path();
```

Also remove `use std::env;` if it is no longer referenced after removing `set_protoc_path`.

### `rslib/build.rs`

File: `/Users/npochaev/GitHub/anki/rslib/build.rs`

Current:

```rust
fn main() -> Result<()> {
    println!("cargo:rerun-if-changed=../out/buildhash");
    let buildhash = fs::read_to_string("../out/buildhash").unwrap_or_default();
    println!("cargo:rustc-env=BUILDHASH={buildhash}");

    let descriptors_path = descriptors_path();
    println!("cargo:rerun-if-changed={}", descriptors_path.display());
    let pool = DescriptorPool::decode(std::fs::read(descriptors_path)?.as_ref())?;
    rust_interface::write_rust_interface(&pool)?;
    Ok(())
}
```

Replace the `buildhash` block to derive the hash from git instead of the `out/` directory:

```rust
fn main() -> Result<()> {
    let buildhash = std::process::Command::new("git")
        .args(["rev-parse", "--short", "HEAD"])
        .output()
        .ok()
        .and_then(|o| String::from_utf8(o.stdout).ok())
        .unwrap_or_default();
    println!("cargo:rustc-env=BUILDHASH={}", buildhash.trim());

    let descriptors_path = descriptors_path();
    println!("cargo:rerun-if-changed={}", descriptors_path.display());
    let pool = DescriptorPool::decode(std::fs::read(descriptors_path)?.as_ref())?;
    rust_interface::write_rust_interface(&pool)?;
    Ok(())
}
```

Also remove `use std::fs;` if it is no longer needed (it was only used for
`read_to_string`).

Note: `descriptors_path()` from `anki_proto_gen` reads the `DESCRIPTORS_BIN` env var,
which we removed from `.cargo/config.toml`. You must either:
- Set `DESCRIPTORS_BIN` to the `OUT_DIR` path from the `rslib/proto` build step, or
- Replace the call with a direct path derived from `OUT_DIR`.

The cleanest approach is to add a `build-dependencies` entry that depends on `anki_proto`
(which already has the descriptors compiled in) and read from `OUT_DIR` of that crate.
Alternatively, set `DESCRIPTORS_BIN` in `.cargo/config.toml` to a stable path in the
build output directory. This dependency chain is the main coupling point to resolve.

### `rslib/i18n/build.rs`

File: `/Users/npochaev/GitHub/anki/rslib/i18n/build.rs`

Current `main()` calls `typescript::write_ts_interface` and `python::write_py_interface`.
Remove both calls and their module declarations:

```rust
// REMOVE these module declarations at the top:
mod python;
mod typescript;

// REMOVE these calls from main():
typescript::write_ts_interface(&modules)?;
python::write_py_interface(&modules)?;
```

Resulting `main()`:

```rust
fn main() -> Result<()> {
    let mut map = get_ftl_data();
    check(&map);
    let mut modules = get_modules(&map);
    write_strings(&map, &modules, "strings.rs", "All");

    if let Some(path) = option_env!("STRINGS_JSON") {
        if !path.is_empty() {
            let path = PathBuf::from(path);
            let meta_json = serde_json::to_string_pretty(&modules).unwrap();
            create_dir_all(path.parent().unwrap())?;
            write_file_if_changed(path, meta_json)?;
        }
    }

    map.iter_mut()
        .for_each(|(_, modules)| modules.retain(|module, _| module == "launcher"));
    modules.retain(|module| module.name == "launcher");
    write_strings(&map, &modules, "strings_launcher.rs", "Launcher");

    Ok(())
}
```

### `rslib/src/card_rendering/tts/mod.rs`

File: `/Users/npochaev/GitHub/anki/rslib/src/card_rendering/tts/mod.rs`

Current:

```rust
#[cfg(windows)]
#[path = "windows.rs"]
mod inner;
#[cfg(not(windows))]
#[path = "other.rs"]
mod inner;
```

Replace with (unconditionally use the non-Windows implementation):

```rust
#[path = "other.rs"]
mod inner;
```

The `windows.rs` file was already removed in Phase 3.

### `rslib/src/error/mod.rs`

File: `/Users/npochaev/GitHub/anki/rslib/src/error/mod.rs`

Remove the Windows module declaration and the `WindowsError` enum variant:

```rust
// REMOVE this line near the top:
#[cfg(windows)]
pub mod windows;

// REMOVE this variant from AnkiError:
#[cfg(windows)]
#[snafu(context(false))]
WindowsError {
    source: windows::WindowsError,
},
```

The `windows.rs` file was already removed in Phase 3. After removing the variant, verify
that no match arms in `error/mod.rs` or elsewhere reference `AnkiError::WindowsError`.

Search:

```bash
grep -r "WindowsError\|windows::Windows" rslib/src/ --include="*.rs"
```

All matches should be eliminated after the removal.

---

## Phase 5: Dependency Cleanup

After editing `Cargo.toml`, run `cargo check --workspace` to identify any remaining
references to the removed dependencies. The following packages should no longer appear in
`Cargo.toml` or any crate-level `Cargo.toml` after removal:

```toml
# Root Cargo.toml - remove from [workspace.dependencies]:
embed-resource = "3.0.4"
junction = "1.2.0"
libc-stdhandle = "0.1"
pyo3 = { version = "0.25.1", features = [...] }
widestring = "1.1.0"
winapi = { version = "0.3", features = [...] }
windows = { version = "0.61.3", features = [...] }
```

Note: `libc` itself is a cross-platform dependency used by other crates; keep it.
Only `libc-stdhandle` (Windows stdio handle manipulation) should be removed.

Check each crate's `Cargo.toml` individually:

```
qt/launcher/Cargo.toml     # windows, widestring, libc-stdhandle, embed-resource
pylib/rsbridge/Cargo.toml  # pyo3 - entire crate removed in Phase 1
```

---

## Phase 6: Validation

Run these commands in order after completing all phases.

```bash
# 1. Verify protoc is available
protoc --version

# 2. Check the workspace compiles
cargo check --workspace

# 3. Run the test suite
cargo test --workspace

# 4. Verify no references remain to removed modules
grep -r "pylib\|rsbridge\|pyo3" rslib/src/ --include="*.rs"
grep -r "WindowsError\|windows::Windows" rslib/src/ --include="*.rs"
grep -r "write_python_interface\|write_py_interface" rslib/ --include="*.rs"
grep -r "write_ts_interface" rslib/ --include="*.rs"

# 5. Verify no dangling workspace member references
cargo metadata --no-deps --format-version 1 | python3 -c "
import json, sys
m = json.load(sys.stdin)
for p in m['packages']:
    print(p['name'], p['manifest_path'])
"
```

Expected: all five grep commands return no output. `cargo check` and `cargo test` pass
with zero errors.

---

## Summary Table

| Category | Items Removed | Measured Size |
|---|---|---|
| PyQt GUI | `qt/aqt/` (218 files) | ~2.5M |
| Web Frontend | `ts/` (520 files) | ~2.6M |
| Python library | `pylib/` (97 files) | ~1.3M |
| Python utilities | `python/` (2 files) | ~8K |
| Build system | `build/` | ~264K |
| Dev tools | `tools/` (23 files) | ~100K |
| CI | `.github/`, `.buildkite/` | ~60K |
| IDE configs | `.idea.dist/`, `.vscode.dist/`, `.cursor/` | ~28K |
| Root configs | 15+ files (Node, Python, lint) | ~50K |
| Windows/Linux code | ~6 `.rs` files, ~500 lines | minimal |
| **Total removed** | | **~7M** |
| **Remaining Rust core** | `rslib/`, `ftl/`, `cargo/`, `proto/` | **~3.9M** |
