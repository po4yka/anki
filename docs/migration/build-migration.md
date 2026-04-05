# Replacing the Custom Ninja Build System with Plain Cargo

This document explains how to replace Anki's custom ninja build system with
standard `cargo build` for the macOS-only Rust core. The scope is intentionally
narrow: proto compilation, Rust struct generation, and service trait generation.
The TypeScript bundler, Python wheel builder, and cross-platform download
orchestration are not covered.

---

## 1. Current Build Pipeline

```
.proto files (24 files in proto/anki/)
    |
    v  [rslib/proto/build.rs -> rust::write_rust_protos()]
prost_build::Config::compile_protos()
    |
    +-- OUT_DIR/anki.*.rs        (Rust message structs)
    +-- OUT_DIR/descriptors.tmp  (raw binary proto descriptors)
    |       |
    |       v  [written to descriptors_path()]
    |   out/rslib/proto/descriptors.bin   <-- ninja sets DESCRIPTORS_BIN here
    |
    +-- python::write_python_interface()  (REMOVE)
    +-- typescript::write_ts_interface()  (REMOVE)

descriptors.bin
    |
    v  [rslib/build.rs -> rust_interface::write_rust_interface()]
descriptors_path() -> DescriptorPool::decode()
    |
    +-- OUT_DIR/backend.rs       (service traits + RPC dispatch)

rslib/proto/src/lib.rs:   include!(concat!(env!("OUT_DIR"), "/anki.*.rs"))
rslib/src/services.rs:    include!(concat!(env!("OUT_DIR"), "/backend.rs"))
```

The ninja build also reads `out/buildhash` (a file it generates) and passes it
to `rslib/build.rs` as the `BUILDHASH` env var. This needs a replacement under
plain Cargo.

---

## 2. Why It Already Works With Cargo

Two mechanisms make plain `cargo build` sufficient for the Rust core.

**Descriptor path fallback.** `rslib/proto_gen/src/lib.rs` line 278:

```rust
pub fn descriptors_path() -> PathBuf {
    if let Ok(path) = env::var("DESCRIPTORS_BIN") {
        PathBuf::from(path)          // ninja build sets this
    } else {
        PathBuf::from(env::var("OUT_DIR").unwrap())
            .join("../../anki_descriptors.bin")  // cargo fallback
    }
}
```

When `DESCRIPTORS_BIN` is not set, both `rslib/proto` and `rslib` resolve the
descriptor file relative to their own `OUT_DIR`. Because `rslib` depends on
`anki_proto` in `Cargo.toml`, Cargo guarantees `anki_proto`'s build script runs
first, writing `descriptors.bin` into its `OUT_DIR`. When `rslib`'s build script
runs next, it walks two directories up from its own `OUT_DIR` and finds the file
written by `anki_proto`.

**Automatic crate ordering.** The dependency edge in the workspace
(`rslib/Cargo.toml` depends on `anki_proto`) is all Cargo needs to sequence the
two build scripts correctly. No manual orchestration is required.

---

## 3. Prerequisites

Install the system `protoc` binary so `prost-build` can find it on `PATH`:

```bash
brew install protobuf

# Verify:
protoc --version   # should print: libprotoc 3.x or 4.x
```

`prost-build` searches `PATH` for `protoc` automatically when the `PROTOC`
environment variable is not set.

---

## 4. Step-by-Step Migration

### Step 1: Clean `.cargo/config.toml`

Remove the four environment variables that reference ninja-managed paths.
`MACOSX_DEPLOYMENT_TARGET` and the `[term]` / `[target]` sections are
unrelated to the build system and should be kept.

**Before (`/.cargo/config.toml`):**

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

**After:**

```toml
[env]
MACOSX_DEPLOYMENT_TARGET = "11"

[term]
color = "always"

[target.'cfg(all(target_env = "msvc", target_os = "windows"))']
rustflags = ["-C", "target-feature=+crt-static"]
```

Removed: `STRINGS_PY`, `STRINGS_TS`, `DESCRIPTORS_BIN`, `PROTOC`,
`PYO3_NO_PYTHON`, `PYTHONDONTWRITEBYTECODE`.

### Step 2: Remove Python/TypeScript codegen from `rslib/proto/build.rs`

The Python and TypeScript interface generation requires output paths
(`STRINGS_PY`, `STRINGS_TS`) that only exist in the ninja build. Remove the
module declarations and their call sites.

**Before (`rslib/proto/build.rs`):**

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

**After:**

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

The `python` and `typescript` submodules can remain on disk if removing them
causes unrelated compilation errors elsewhere in the workspace; simply removing
their `pub mod` declarations and call sites is sufficient to stop them from
being compiled as part of the `rslib/proto` build.

### Step 3: Simplify `rslib/proto/rust.rs`

The `set_protoc_path()` function reads `PROTOC` from the environment and
forwards it. Without that variable set, `prost-build` falls back to searching
`PATH`, which is the desired behavior after Step 1. Remove the call and the
function.

**Before (excerpt from `rslib/proto/rust.rs`):**

```rust
pub fn write_rust_protos(descriptors_path: PathBuf) -> Result<DescriptorPool> {
    set_protoc_path();
    let proto_dir = PathBuf::from("../../proto");
    // ...
}

/// Set PROTOC to the custom path provided by PROTOC_BINARY, or add .exe to
/// the standard path if on Windows.
fn set_protoc_path() {
    if let Ok(custom_protoc) = env::var("PROTOC_BINARY") {
        env::set_var("PROTOC", custom_protoc);
    } else if let Ok(bundled_protoc) = env::var("PROTOC") {
        if cfg!(windows) && !bundled_protoc.ends_with(".exe") {
            env::set_var("PROTOC", format!("{bundled_protoc}.exe"));
        }
    }
}
```

**After:**

```rust
pub fn write_rust_protos(descriptors_path: PathBuf) -> Result<DescriptorPool> {
    let proto_dir = PathBuf::from("../../proto");
    // ... rest unchanged
}
```

Remove the `set_protoc_path()` call at the top of `write_rust_protos` and the
entire `set_protoc_path` function definition. Also remove the now-unused
`use std::env;` import if no other code in the file references `env`.

### Step 4: Fix buildhash in `rslib/build.rs`

The current code reads `out/buildhash`, a file written by the ninja runner:

```rust
println!("cargo:rerun-if-changed=../out/buildhash");
let buildhash = fs::read_to_string("../out/buildhash").unwrap_or_default();
println!("cargo:rustc-env=BUILDHASH={buildhash}");
```

When `out/buildhash` does not exist, `unwrap_or_default()` produces an empty
string. To produce a meaningful value under plain Cargo, replace the file read
with a `git rev-parse` call:

**Before:**

```rust
println!("cargo:rerun-if-changed=../out/buildhash");
let buildhash = fs::read_to_string("../out/buildhash").unwrap_or_default();
println!("cargo:rustc-env=BUILDHASH={buildhash}");
```

**After:**

```rust
let buildhash = std::process::Command::new("git")
    .args(["rev-parse", "--short", "HEAD"])
    .output()
    .ok()
    .and_then(|o| String::from_utf8(o.stdout).ok())
    .unwrap_or_default();
let buildhash = buildhash.trim();
println!("cargo:rustc-env=BUILDHASH={buildhash}");
println!("cargo:rerun-if-changed=../.git/HEAD");
```

The `rerun-if-changed` directive on `.git/HEAD` ensures Cargo re-runs the
build script after each commit, matching the previous behavior of watching the
ninja-generated file.

Remove the `use std::fs;` import if it is no longer used after this change.

### Step 5: Update workspace `Cargo.toml`

Remove the non-Rust workspace members that have build-time dependencies on
ninja or Python tooling. These crates will not compile without the full
ninja environment.

**Before (the `[workspace]` members list):**

```toml
[workspace]
members = [
  "build/configure",
  "build/ninja_gen",
  "build/runner",
  "ftl",
  "pylib/rsbridge",
  "qt/launcher",
  "rslib",
  "rslib/i18n",
  "rslib/io",
  "rslib/linkchecker",
  "rslib/process",
  "rslib/proto",
  "rslib/sync",
  "tools/minilints",
]
```

**After:**

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
```

Removed: `build/configure`, `build/ninja_gen`, `build/runner`,
`pylib/rsbridge`, `tools/minilints`.

- `build/*` crates require the ninja environment to function.
- `pylib/rsbridge` depends on `pyo3` with `extension-module`, which requires a
  Python interpreter; `PYO3_NO_PYTHON` suppressed this in the ninja build but
  the crate still fails `cargo check` without proper Python headers.
- `tools/minilints` is a development utility unrelated to the Rust core.

Also remove the `ninja_gen` workspace dependency declaration:

```toml
# Remove this line from [workspace.dependencies]:
ninja_gen = { "path" = "build/ninja_gen" }
```

---

## 5. Verification

After completing all steps, verify with:

```bash
# Type-check the entire workspace (fast, no linking):
cargo check --workspace

# Compile and run tests:
cargo test --workspace
```

A successful `cargo check --workspace` with zero errors confirms the proto
codegen pipeline is working end-to-end under plain Cargo.

---

## 6. Troubleshooting

| Error | Cause | Fix |
|-------|-------|-----|
| `Could not find protoc` | `protoc` not on `PATH` | `brew install protobuf` |
| `No such file or directory: descriptors.bin` | Stale build cache with old paths | `cargo clean && cargo build` |
| `environment variable STRINGS_PY not defined` | Old `.cargo/config.toml` still present | Ensure `STRINGS_PY` and `STRINGS_TS` are removed from `[env]` |
| `can't find crate for 'pyo3'` | `pylib/rsbridge` still listed in workspace members | Remove it from `Cargo.toml` members |
| `can't find crate for 'ninja_gen'` | `build/*` crates still in workspace | Remove `build/configure`, `build/ninja_gen`, `build/runner` from members |
| Build script panics reading `out/buildhash` | File absent outside ninja build | Apply the `git rev-parse` replacement in Step 4 |
| `OUT_DIR`-relative descriptor path resolves incorrectly | Non-standard Cargo target directory layout | Set `DESCRIPTORS_BIN` explicitly: `export DESCRIPTORS_BIN=$(cargo build ... 2>&1 \| grep OUT_DIR ...)` |
