# Saved projects (macOS)

This extension adds saved launch configurations to PortKiller. The original
project and its MIT license remain intact. Windows and Linux are unchanged.

## Usage

1. Open **Projects** in the main window, or **Projects → Manage…** in the menu bar.
2. Choose **Add Project** and enter a name, folder and foreground start command
   (for example, `pnpm dev`, `npm run dev` or `uv run python app.py`).
3. Optionally enter the expected TCP port. It is checked for conflicts before
   launch and used by the Open button; it does not change your server's port.
4. Mark the project as a favorite to keep it in the menu bar while stopped.
5. Press **Start** or **Stop**. Running non-favorites also remain in the menu bar.

Commands run in a non-interactive login zsh shell. The folder is passed as a
separate argument and selected after shell initialization. If your runtime is
configured exclusively in an interactive `.zshrc`, configure it for login shells
or explicitly initialize it in the saved command. No commands run automatically
when you save a project or open PortKiller.

Keep commands in the foreground: do not add `&`, `nohup`, or a daemon flag.
Each launch owns a separate process group. Stop sends SIGTERM and escalates to
SIGKILL after three seconds; remaining workers are cleaned up when the leader
exits. Closing PortKiller stops the projects it launched. It does not adopt or
stop externally started services through the project controls. The existing
port-management actions retain their original behavior.

**Running** means the command is alive, not that an HTTP health check passed.
Expected ports are optional. Port checks cannot prevent another application
from taking a port between checking it and starting the server.

Projects must be stopped before editing or removal. Removal deletes only the
saved configuration. Logs are private to the user and are overwritten at each
start, under `~/Library/Application Support/PortKiller/ProjectLogs/`.

## Development and verification

### Open the local development app

From `platforms/macos`:

```sh
./scripts/build-dev-app.sh
open ".build/development/PortKiller Projects Dev.app"
```

Quit the development app before rebuilding. This script builds for the current
Mac, packages the resources and Sparkle framework, and signs the app locally.
It also works with Command Line Tools by temporarily omitting dependency previews.
It adjusts ignored SwiftPM resource accessors for the standard app bundle layout.

The development app has its own identifier (`com.gabritorres.portkiller.projects.dev`),
separate preferences and project logs under
`~/Library/Application Support/PortKiller Projects Dev/ProjectLogs/`.
The original project's Sparkle feed is removed and updates are disabled in code
for this build, so they cannot replace the experimental app.

### Compiler and automated checks

From `platforms/macos`:

```sh
swift build
swift test
```

The existing app and its dependencies expect the full Xcode toolchain. On a Mac
with only Command Line Tools, KeyboardShortcuts' `#Preview` declarations can fail
to compile and the `Testing` module can be missing. For local verification in
that environment, only the previews in the ignored dependency checkout were
temporarily omitted; no vendored dependency change is included in this branch.
The app's shortcut preview uses PreviewProvider, which works without that macro.

The app build passed. Separate executable smoke checks of the actual project
model, state and process launcher passed for persistence, literal folder paths,
stdout/stderr logs, exit errors, duplicate starts, process-group cleanup,
SIGTERM/SIGKILL shutdown and occupied IPv4 ports. The full Swift Testing suite
still needs to run with Xcode; the new suite additionally covers invalid recipes
and IPv6 port conflicts.

The packaged development app has also been checked in the native macOS UI:
adding a favorite, finding it in the menu bar, starting an HTTP demo, receiving
its page, and pressing Stop in the main window. Stop returned the project to
Stopped and closed its HTTP listener. App signature verification also passed.

## Publishing a fork

Keep `LICENSE` and the original copyright notice when publishing. A GitHub fork
can use your repository as `origin` and the original repository as `upstream`.
Development takes place on `codex/project-launcher` in the
[`gabritorres/port-killer` fork](https://github.com/gabritorres/port-killer),
with the original repository configured as `upstream`.

Before distributing a separately branded app, give it its own bundle identifier
and update configuration. The original packaging script still uses the original
application identity and Sparkle feed; a distributed fork needs its own release
channel rather than replacing local changes with upstream binaries.
