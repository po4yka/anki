// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

mod check;
mod extract;
mod gather;
mod write_strings;

use anyhow::Result;
use check::check;
use extract::get_modules;
use gather::get_ftl_data;
use write_strings::write_strings;

// fixme: check all variables are present in translations as well?

fn main() -> Result<()> {
    // generate our own requirements
    let mut map = get_ftl_data();
    check(&map);
    let mut modules = get_modules(&map);
    write_strings(&map, &modules, "strings.rs", "All");

    // generate strings for the launcher
    map.iter_mut()
        .for_each(|(_, modules)| modules.retain(|module, _| module == "launcher"));
    modules.retain(|module| module.name == "launcher");
    write_strings(&map, &modules, "strings_launcher.rs", "Launcher");

    Ok(())
}
