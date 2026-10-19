# Fork changelog

Changes maintained in [gabritorres/port-killer](https://github.com/gabritorres/port-killer),
based on the original MIT-licensed PortKiller. These additions apply to macOS.

## 2026-10-19 — Restarting services and resolving port conflicts

- Fix false busy-port errors immediately after stopping a service, including
  IPv4 and IPv6 connections in TIME_WAIT.
- Add **Free :port & Start…** to project services in the main window and menu bar.
  It lists the listening processes for confirmation, then stops them and starts
  the selected service. Ordinary Start and group actions preserve external owners.
- Revalidate process creation time and socket ownership before sending signals;
  abort if the port changes owners during the operation.
- Add executable regression checks for immediate restart, resistant listeners,
  stale identities and ownership changes.

## 2026-10-18 — Saved projects and service groups

- Save foreground start commands, working folders and optional TCP ports.
- Keep favorite projects in the menu bar, including when stopped.
- Group services under a project and start or stop the group or each service.
- Set launch order and exclude optional services from group startup.
- Show starting/listening states and per-project readiness counts.
- Open service URLs and inspect private, per-service logs.
- Recognize matching services started outside PortKiller; group actions leave
  those processes running. Stop them externally before launching them here.
- Generate shared temporary variables in memory for linked services, without
  saving their values in project configurations.
- Import local JSON configurations atomically, preserving unrelated projects
  and compatibility with earlier saved configurations.
- Isolate launched process groups and clean up their workers on stop or app exit.
- Package a locally signed development app with separate preferences and logs,
  and upstream automatic updates disabled for that development build.
- Add automated coverage for project persistence, imports, grouping, lifecycle,
  shared variables and external-service identity.

Validation included the executable group smoke checks and native macOS operation
with a seven-service project and four additional web projects. All eleven services
returned HTTP 200 during their respective checks; the additional web projects
were subsequently stopped through PortKiller. The complete Swift Testing suite
still requires an Xcode toolchain with the `Testing` module.

Machine-specific recipes, paths and settings stay local and are not part of this
repository. Launch at Login uses the app's existing setting; enabling it does not
automatically start saved projects. See [the project guide](PROJECTS.md) for usage
and limitations. This changelog does not represent a packaged public release.
