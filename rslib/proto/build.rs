// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

pub mod rust;

use anki_proto_gen::descriptors_path;
use anyhow::Result;

fn main() -> Result<()> {
    let descriptors_path = descriptors_path();
    rust::write_rust_protos(descriptors_path)?;
    Ok(())
}
