# micguard

Keeps the macOS default input on the built-in microphone, so connecting
AirPods (or any Bluetooth headset) only changes the output.

It listens for CoreAudio default-input changes and switches back to the
built-in mic immediately. The mic is found by transport type, so no device
name is configured. Using the built-in mic also keeps AirPods out of the
low-quality headset profile.

On a Mac without a built-in mic (e.g. a Mac mini), or to prefer other
inputs, set a priority list of devices. micguard keeps the first connected
device on the list as the default input, switches to a higher-priority
device when it is plugged in, and leaves the input alone while none of
them is connected.

## Build

Requires the Xcode Command Line Tools (`xcode-select --install`).

```bash
swift build -c release
```

## Install

```bash
.build/release/micguard install
```

In a terminal this lists the input devices and asks for device numbers
in priority order (e.g. `2 1`); press Enter to keep the built-in mic. To
choose without the prompt:

```bash
.build/release/micguard install --prefer "Jabra SPEAK 510 USB" --prefer built-in
```

This copies the binary to `~/.local/bin/micguard`, writes
`~/Library/LaunchAgents/local.micguard.plist` and loads it with
`launchctl bootstrap`. It runs at login and is restarted if it exits.
The priority list is stored in the plist; `uninstall` removes it along
with everything else.

## Change the priority list

```bash
micguard devices          # numbered input devices, with default/priority tags
micguard list             # current priority list and which entry is active
micguard prefer 3 1       # set a new order by number from `devices`...
micguard prefer "Shure MV7" built-in   # ...or by name; `built-in` means the built-in mic
```

`prefer` rewrites the plist and restarts the agent. A device that is not
connected can still be listed by name.

## Other commands

```bash
micguard status      # built-in mic, current default input, install state, priority, target
micguard uninstall   # unload agent, remove plist and binary
micguard run         # run in the foreground (what the agent runs)
micguard run --prefer "Jabra SPEAK 510 USB" --prefer built-in
```

Log: `~/Library/Logs/micguard.log`
