# micguard

Keeps the macOS default input on the built-in microphone, so connecting
AirPods (or any Bluetooth headset) only changes the output.

It listens for CoreAudio default-input changes and switches back to the
built-in mic immediately. The mic is found by transport type, so no device
name is configured. Using the built-in mic also keeps AirPods out of the
low-quality headset profile.

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift build -c release
```

## Install

```bash
.build/release/micguard install
```

This copies the binary to `~/.local/bin/micguard`, writes
`~/Library/LaunchAgents/local.micguard.plist` and loads it with
`launchctl bootstrap`. It runs at login and is restarted if it exits.

## Other commands

```bash
micguard status      # built-in mic, current default input, install state
micguard uninstall   # unload agent, remove plist and binary
micguard run         # run in the foreground (what the agent runs)
```

Log: `~/Library/Logs/micguard.log`
