# Saved projects (macOS)

This extension adds saved launch configurations to PortKiller. The original
project and its MIT license remain intact. Windows and Linux are unchanged.

## Usage

1. Open **Projects** in the main window, or **Projects → Manage…** in the menu bar.
2. Choose **Add Service** and enter a name, folder and foreground start command
   (for example, `pnpm dev`, `npm run dev` or `uv run python app.py`).
3. Optionally enter the expected TCP port. It is checked for conflicts before
   launch and used by the Open button; it does not change your server's port.
4. Mark the project as a favorite to keep it in the menu bar while stopped.
5. Press **Start** or **Stop**. Running non-favorites also remain in the menu bar.

### Multiple services in one project

Give related services the same **Project / group** name. The main window groups
them together, and the menu bar offers a collapsible project with **Start Group**
and **Stop Group** controls plus individual start/stop, browser and log actions.
An ungrouped service keeps working as before; old saved configurations migrate
without losing their IDs, favorites or commands.

Use **Start order** to launch lower numbers first. This orders process launches;
it does not wait for dependency health. Turn off **Include in Start Group** for
shared runtimes or optional services you prefer to start manually. Stop Group
stops owned services in reverse order, including manually started group members.
Unrelated groups and ungrouped services are unaffected.

If a port is already occupied by a process from the configured folder, the service
shows **Running externally**. Group start skips it and group stop leaves it alone.
Stop that service in its original terminal before starting it under PortKiller.
An optional `externalProcessName` field can identify a shared runtime by exact
process name and port instead of folder. No external process is adopted or killed.
An unrelated process on the expected port produces a conflict instead.

For linked services needing the same ephemeral credential, enter comma-separated
**Shared temporary variables** names. PortKiller generates random values scoped to
the project, keeps them only in memory for this application session, and injects
only the variables requested by each service. Restarting one service keeps the
value while the app runs. A linked external service cannot receive that value;
PortKiller asks you to start linked services together rather than silently mixing
incompatible sessions. Do not copy actual secret values into saved commands.

**Import…** loads a local JSON array of saved service configurations. All entries
are validated before saving. Matching IDs update in place; other saved services
are retained. An invalid entry or a replacement for an owned running service
rejects the whole import. Imports do not start anything. Keep machine-specific
paths and commands outside public repositories.

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

**Starting** means the command is alive but its configured port has not been seen.
**Listening** and the group's ready count mean a TCP listener with a matching
folder/process identity was detected, not that an HTTP health check passed.
Services without an expected port are ready while their command is alive.
Expected ports are optional. Port checks cannot prevent another application
from taking a port between checking it and starting the server.

Projects must be stopped before editing or removal. Removal deletes only the
saved configuration. Logs are private to the user and are overwritten at each
start, under `~/Library/Application Support/PortKiller/ProjectLogs/`.

### Login and menu bar

Enable **Settings → General → Launch at Login** to open the app when signing in
to macOS. This existing setting starts PortKiller, not saved projects; use
**Start Group** when needed. Closing the main window leaves the menu bar app
running. Quitting the app stops the services it launched.

Some frameworks can detach their development server automatically. Use their
foreground mode so PortKiller retains ownership of the server process. Also avoid
passing the same host flag both in a package script and in its saved arguments.
Choose distinct ports for projects that may run together, and select the required
runtime explicitly if it is unavailable in a non-interactive login shell.

A recently closed socket can temporarily make the port conflict probe report a
busy port even after its listener has stopped. Wait for macOS to release the
socket and retry; the launcher does not stop another process to resolve conflicts.

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

The group extension was verified against a local seven-service project. Five
existing servers were recognized as external; Start Group launched the two
remaining services and both returned HTTP 200. Stop Group closed those two
listeners while leaving all five external listeners active.

The five external services were later stopped and relaunched through PortKiller.
All seven then appeared ready, responded with HTTP 200 and had process ancestry
under the app. Four additional web projects were imported as favorites, started
through the UI, checked over HTTP and stopped. Their configurations remain local;
no project-specific paths or credentials are shipped with this fork.

`SmokeTests/ProjectGroupsSmoke.swift` additionally exercises old configuration
decoding, atomic/idempotent imports, saved groups, start ordering, group isolation,
manual-only services, temporary shared variables and external identity checks.
After building once, run it without Xcode's Testing module:

```sh
PRODUCTS=$(swift build --show-bin-path)
swiftc -parse-as-library -swift-version 6 -I "$PRODUCTS/Modules" \
  Sources/Models/ProjectConfiguration.swift Sources/Services/ProjectProcess.swift \
  Sources/State/ProjectsState.swift SmokeTests/ProjectGroupsSmoke.swift \
  "$PRODUCTS"/Defaults.build/*.o -o .build/project-groups-smoke
.build/project-groups-smoke
```

## Publishing a fork

Keep `LICENSE` and the original copyright notice when publishing. A GitHub fork
can use your repository as `origin` and the original repository as `upstream`.
The project launcher is maintained on `main` in the
[`gabritorres/port-killer` fork](https://github.com/gabritorres/port-killer),
with the original repository configured as `upstream`. Its initial implementation
was developed on `codex/project-launcher`; see the [fork changelog](CHANGELOG.md).

Before distributing a separately branded app, give it its own bundle identifier
and update configuration. The original packaging script still uses the original
application identity and Sparkle feed; a distributed fork needs its own release
channel rather than replacing local changes with upstream binaries.
