# Install PortKiller Projects

PortKiller Projects is a macOS fork of [PortKiller](https://github.com/productdevbook/port-killer)
with saved projects, service groups and explicit port-conflict recovery.

## Download

Get the DMG or ZIP from [the public releases](https://github.com/gabritorres/port-killer/releases).
Version 0.1.0 is a beta for **macOS 15 or later**, with a universal executable for
Apple Silicon and Intel Macs. Runtime checks were performed on Apple Silicon;
the Intel executable is cross-compiled and has not been tested on Intel hardware.

1. Download the `.dmg`, open it and drag **PortKiller Projects.app** to Applications.
   Alternatively, unzip the `.zip` and move the app to Applications.
2. Open the app from Applications. Its icon stays in the menu bar.
3. Open **Projects**, add a service folder and foreground start command, and enter
   its TCP port. Give related services the same project/group name.
4. Use **Start Group**, **Stop Group**, or the individual service controls.

The archive includes the app, its runtime frameworks and open-source licenses.
Your development runtimes (Node, Python, etc.) and project dependencies remain
your responsibility. No sample projects, private configuration, credentials or
user preferences are bundled. New installations start with an empty project list.

## macOS security notice

This beta has an **ad-hoc local signature**. It is **not signed with an Apple
Developer ID and is not notarized by Apple**, so Gatekeeper may block its first
launch. Review the source and checksums before deciding whether to open it.
Apple documents the per-app option in [Safely open apps on your Mac](https://support.apple.com/en-us/102445).
There is no need to disable Gatekeeper globally or run a quarantine-removal command.

## Verify a download

Download `SHA256SUMS.txt` alongside the matching archive. In the download folder:

```sh
shasum -a 256 -c SHA256SUMS.txt --ignore-missing
```

The checksum identifies the published bytes; it does not replace Developer ID
signing or Apple notarization.

## Preferences, updates and login

- Public app identifier: `com.gabritorres.portkiller.projects`.
- Preferences are separate from both upstream PortKiller and the development app.
- Project logs: `~/Library/Application Support/PortKiller Projects/ProjectLogs/`.
- Updates are manual through this fork's Releases page. This beta has no automatic
  updater and cannot download upstream PortKiller over your fork.
- **Settings → General → Launch at Login** starts the app when you sign in; saved
  projects only start when requested. Keep the installed app in Applications.
- Closing the main window leaves the menu bar app running. Quitting the app stops
  the services it started. Group actions preserve externally started services.
- **Free :port & Start…** explicitly asks before stopping competing listeners.

For shell setup, imports, shared variables and lifecycle behavior, see [PROJECTS.md](PROJECTS.md).
