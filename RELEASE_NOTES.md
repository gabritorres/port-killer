# PortKiller Projects 0.1.0 — first public beta

A macOS fork of PortKiller for starting and stopping your development projects
from the menu bar.

- Favorite launch recipes with folders, commands and optional TCP ports.
- Project groups with whole-project and individual service controls.
- Launch ordering, optional services, readiness indicators and private logs.
- JSON import and temporary shared environment variables kept in memory.
- External-service detection: ordinary group actions leave those services running.
- Immediate restart after TCP TIME_WAIT and a confirmed **Free :port & Start…**
  action for real conflicts, with process-identity revalidation.
- Separate app identity and preferences; upstream automatic updates disabled.

## Downloads

**macOS 15+ · Apple Silicon + Intel universal binary.** Install the DMG by dragging
the app to Applications, or extract the ZIP. `SHA256SUMS.txt` covers both archives.
The Intel binary is cross-compiled; runtime verification was on Apple Silicon.

**Signing:** ad-hoc signed, **not Developer ID signed or Apple notarized**.
macOS may block the first launch. Read [the installation guide](https://github.com/gabritorres/port-killer/blob/main/INSTALL.md)
and [Apple's guidance](https://support.apple.com/en-us/102445) before deciding whether to open it.

New installations have no saved projects. No personal project recipes, paths,
logs, credentials or preferences are included. Development runtimes and project
dependencies must already be installed on your machine.

## Verification

The app build and executable group/port-conflict checks passed locally, including
IPv4/IPv6 TIME_WAIT, cancellation, signal escalation and changed process ownership.
Native UI checks covered start/stop, takeover cancellation and confirmation, and
restarting a real backend. See the project guide for the full scope and limitations.
