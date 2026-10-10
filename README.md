# smart-work

Menu bar app that holds the Mac awake only while agent work is running, and pings your phone
when it finishes or goes quiet. Like `caffeinate -i`, but the work reports itself.

- Awake = a `PreventUserIdleSystemSleep` assertion, held while at least one session is alive.
  The display is not held: macOS still dims/sleeps it on idle. No sessions = the Mac sleeps normally.
- Lid close still sleeps the Mac (as with `caffeinate -i`).

## Use

```sh
swift build -c release
.build/release/SmartWork &          # menu bar app (moon = idle, bolt = holding awake)

smart-work begin omp-1 --timeout 30m   # start; timeout = max silence before "stuck"
smart-work beat  omp-1                 # heartbeat, resets the timeout
smart-work done  omp-1                 # finish -> ntfy ping, release
smart-work run   build -- make all     # wrap a command: begin, auto-heartbeat, done
smart-work list
```

A session that stays silent past its timeout is released and you get a "timed out" ping.
The menu's "Keep awake" toggle is a manual session that never expires.

## Phone pings (ntfy)

`~/.smart-work/config.json`:

```json
{ "ntfyTopic": "pick-a-long-random-string", "ntfyServer": "https://ntfy.sh" }
```

Env `SMART_WORK_NTFY_TOPIC` / `SMART_WORK_NTFY_SERVER` override. Subscribe to the topic in the
ntfy iOS app. No topic = pings are logged to stderr only. Topics on ntfy.sh are public by name:
use an unguessable one.

## Protocol

JSON line per request over `~/.smart-work/daemon.sock` (0600):
`{"cmd":"begin|beat|done|list","name":"…","timeout":secs}`.

## Lid-closed mode

Off by default; menu toggle "Stay awake with lid closed". macOS only allows this with root
(`pmset disablesleep`), so a small privileged helper does it:

- Installed on first enable through `SMAppService` (a LaunchDaemon inside the app bundle). macOS asks you to
  approve it once in System Settings > Login Items; the menu shows the state and a button.
- The helper exposes one XPC call: a lease of at most 120 s that the app renews every 30 s, only while a
  session is alive. Only a client signed with the helper's own Team ID and identifier
  `com.hamardikan.smart-work` is accepted.
- It restores normal sleep on: lease expiry (app quit/crash/hang), last session done, battery <= 10% on
  battery power, thermal state serious/critical, or helper restart after a crash (marker file in `/var/db`).
  Those safety stops send an ntfy ping.
- Heat is the real risk of a closed-lid laptop in a bag; prefer AC power.

## Build, sign, release

The helper only runs from the signed `.app`, not from `swift run`.

```sh
SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" scripts/bundle.sh   # dist/SmartWork.app
xcrun notarytool store-credentials smart-work --apple-id <id> --team-id <TEAMID> --password <app-specific>
SIGN_IDENTITY=... scripts/notarize.sh                                             # dist/smart-work-<v>.dmg
```

Distribution is Developer ID + notarized DMG. The Mac App Store is not possible: the sandbox forbids
the privileged helper. `bundle.sh` also works with an `Apple Development` identity for local testing.
Put `smart-work` on PATH: `ln -s /Applications/SmartWork.app/Contents/MacOS/smart-work /usr/local/bin/`.

## Later

iOS companion app (APNs/CloudKit) replacing ntfy; herdr agent-state hook calling the CLI.
