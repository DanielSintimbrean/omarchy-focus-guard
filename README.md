# Focus Guard for Omarchy

Focus Guard blocks distracting domains across the computer during a weekday
work window. It lives in the Omarchy bar and adds enough friction to stop an
impulsive "just five minutes" detour.

The default schedule is Monday to Friday, 09:00 to 17:00, using the computer's
local timezone. You can change the times and sites from the panel.

## Default sites

These are enabled initially:

- Facebook
- Instagram
- Threads
- X and Twitter
- TikTok
- Reddit
- YouTube
- Twitch

Discord, LinkedIn, Pinterest, and Snapchat are available but off initially.
You can also add custom domains. Selecting `example.com` blocks that domain and
all of its subdomains.

The YouTube preset also blocks its video CDN, image, API, and embed domains so
an already-loaded YouTube page cannot continue fetching media from a separate
hostname.

## Install

Add the plugin and place it in the bar:

```bash
omarchy plugin add https://github.com/DanielSintimbrean/omarchy-focus-guard.git --enable
```

The plugin ID is `io.github.danielsintimbrean.focus-guard`. If needed, add it
to a bar section in `~/.config/omarchy/shell.json`:

```json
{ "id": "io.github.danielsintimbrean.focus-guard" }
```

Open the panel and choose **Install system blocker**. A graphical administrator
prompt appears once. Setup installs the `dnsmasq` package and a small systemd
helper, then briefly reloads DNS.

Omarchy does not run plugin install hooks, so this explicit setup step is
required.

## Use

The shield in the bar shows the current state. Left-click it to open the panel.

- During the work window, blocking starts automatically.
- **Enable now** starts a manual session. It lasts through the end of the next
  scheduled work period.
- **Pause blocking** opens one arithmetic challenge with three operands between
  100 and 999 and two random addition or subtraction operators.
- A wrong answer replaces the entire problem. A correct answer pauses blocking
  until the next work period begins.
- Manual sessions and overrides survive shell restarts and reboots.

The helper checks the schedule every minute. It also reconciles immediately
after the computer wakes from sleep.

Open the panel from a keybinding:

```lua
o.bind("SUPER + CTRL + ALT + F", "Focus Guard", "omarchy-shell shell toggle io.github.danielsintimbrean.focus-guard")
```

## Recovery

The normal disable path is the arithmetic challenge. If the plugin or panel is
broken, this command removes blocking and puts the helper in recovery mode:

```bash
sudo focus-guardctl recover
```

Open the panel and choose **Resume schedule** when the problem is fixed. You can
also run:

```bash
pkexec focus-guardctl resume
```

Recovery exists to prevent an accidental permanent lockout. Focus Guard is an
impulse barrier, not a security boundary. A local administrator can always stop
or alter it.

## Remove

Removing the Omarchy plugin does not remove its root-owned helper. Run the
uninstaller first from the plugin directory:

```bash
sudo bash system/uninstall.sh
```

The uninstaller removes Focus Guard's system files and DNS rules. It leaves the
`dnsmasq` package installed because another program may use it. The user config
at `~/.config/focus-guard/config.json` is also left in place.

## Commands

The panel is the intended control surface. A small IPC interface supports
status checks and manual activation:

```bash
omarchy-shell focus-guard status
omarchy-shell focus-guard enable
omarchy-shell focus-guard refresh
```

There is intentionally no IPC disable command. The privileged helper supports
maintenance and recovery:

```bash
focus-guardctl status
pkexec focus-guardctl enable
pkexec focus-guardctl disable
sudo focus-guardctl recover
```

## How blocking works

Setup adds these system components:

- `/usr/local/bin/focus-guardctl`
- `focus-guard.service` and `focus-guard.timer`
- a system-sleep reconciliation hook
- a narrow PolicyKit action for the controller
- a NetworkManager drop-in that enables its `dnsmasq` DNS plugin

Setup preserves the existing `/etc/resolv.conf` entry, then points it at
NetworkManager's generated resolver file so applications actually use the
filter. On systems with `systemd-resolved`, native applications can otherwise
use the `resolve` NSS module and query the network DNS server directly. Setup
temporarily removes that module from the `hosts` lookup path and restores the
original `/etc/nsswitch.conf` on uninstall if it has not been changed again.

When blocking is active, the helper writes
`/etc/NetworkManager/dnsmasq.d/90-focus-guard.conf`. Each selected domain gets
IPv4 and IPv6 sinkhole responses. Removing the file and reloading NetworkManager's
DNS plugin restores normal resolution. Focus Guard also flushes the system
resolver cache after each DNS reload. Existing browser sockets are not forcibly
killed, so a browser that was already streaming may need to be fully restarted
once after activation.

The helper owns schedule state under `/var/lib/focus-guard`. The panel stores
editable settings in `~/.config/focus-guard/config.json` and sends validated
changes to the helper.

## Limits

- Focus Guard blocks domains, not individual HTTPS pages or URL paths.
- Existing browser connections may continue briefly until they reconnect.
- Custom DNS clients and VPNs may bypass the blocker.
- A user with administrator access can bypass or uninstall it.

Those limits are deliberate. The plugin is designed to interrupt an impulsive
choice without taking control of browsers, VPNs, or administrator access.

## License

MIT
