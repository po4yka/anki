// Copyright: Ankitects Pty Ltd and contributors
// License: GNU AGPL, version 3 or later; http://www.gnu.org/licenses/agpl.html

pub mod mac;

use std::path::PathBuf;

use anki_process::CommandExt;
use anyhow::Context;
use anyhow::Result;

pub fn get_exe_and_resources_dirs() -> Result<(PathBuf, PathBuf)> {
    let exe_dir = std::env::current_exe()
        .context("Failed to get current executable path")?
        .parent()
        .context("Failed to get executable directory")?
        .to_owned();

    let resources_dir = exe_dir
        .parent()
        .context("Failed to get parent directory")?
        .join("Resources");

    Ok((exe_dir, resources_dir))
}

pub fn get_uv_binary_name() -> &'static str {
    "uv"
}

pub fn respawn_launcher() -> Result<()> {
    use std::process::Stdio;

    let current_exe =
        std::env::current_exe().context("Failed to get current executable path")?;

    // Navigate from Contents/MacOS/launcher to the .app bundle
    let app_bundle = current_exe
        .parent() // MacOS
        .and_then(|p| p.parent()) // Contents
        .and_then(|p| p.parent()) // .app
        .context("Failed to find .app bundle")?;

    let mut launcher_cmd = std::process::Command::new("open");
    launcher_cmd.arg(app_bundle);

    launcher_cmd
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null());

    let child = launcher_cmd.ensure_spawn()?;
    std::mem::forget(child);

    Ok(())
}

pub fn launch_anki_normally(mut cmd: std::process::Command) -> Result<()> {
    #[cfg(unix)]
    cmd.ensure_exec()?;
    Ok(())
}

pub fn ensure_terminal_shown() -> Result<()> {
    use std::io::IsTerminal;

    let want_terminal = std::env::var("ANKI_LAUNCHER_WANT_TERMINAL").is_ok();
    let stdout_is_terminal = IsTerminal::is_terminal(&std::io::stdout());
    if want_terminal || !stdout_is_terminal {
        mac::relaunch_in_terminal()?;
    }

    // Set terminal title to "Anki Launcher"
    print!("\x1b]2;Anki Launcher\x07");
    Ok(())
}

pub fn ensure_os_supported() -> Result<()> {
    Ok(())
}
