# micguard

Keeps the macOS default input on the built-in microphone, so connecting
AirPods (or any Bluetooth headset) only changes the output.

It listens for CoreAudio default-input changes and switches back to the
built-in mic immediately. The mic is found by transport type, so no device
name is configured. Using the built-in mic also keeps AirPods out of the
low-quality headset profile.

On a Mac without a built-in mic (e.g. a Mac mini), or to prefer another
input, pick a preferred device at install time. micguard then keeps that
device as the default input whenever it is connected, switches to it when
it is plugged in, and leaves the input alone while it is absent.

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift build -c release
```

## Install

```bash
.build/release/micguard install
```

In a terminal this lists the input devices and asks which one to keep as
default; press Enter to keep the built-in mic. To choose without the
prompt:

```bash
.build/release/micguard install --prefer "Jabra SPEAK 510 USB"
```

This copies the binary to `~/.local/bin/micguard`, writes
`~/Library/LaunchAgents/local.micguard.plist` and loads it with
`launchctl bootstrap`. It runs at login and is restarted if it exits.
The chosen device is stored in the plist, so run `install` again to pick
a different one; `uninstall` removes it along with everything else.

## Other commands

```bash
micguard status      # built-in mic, current default input, install state, target
micguard uninstall   # unload agent, remove plist and binary
micguard run         # run in the foreground (what the agent runs)
micguard run --prefer "Jabra SPEAK 510 USB"
```

Log: `~/Library/Logs/micguard.log`
