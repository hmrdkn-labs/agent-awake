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

## Later

iOS companion app (APNs/CloudKit) replacing ntfy; herdr agent-state hook calling the CLI.
