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
.build/release/micguard devices        # numbered input devices
.build/release/micguard prefer 3 1     # set the priority list and install
```

`prefer` takes numbers from `devices`, device names, or `built-in` for the
built-in mic, e.g. `micguard prefer "Shure MV7" built-in`. A device that is
not connected can still be listed by name. Run `micguard install` instead
to install with no list (built-in mic only).

Either copies the binary to `~/.local/bin/micguard`, writes
`~/Library/LaunchAgents/local.micguard.plist` and loads it with
`launchctl bootstrap`. It runs at login and is restarted if it exits.
The priority list is stored in the plist. Run `prefer` again to change it;
`install` updates the binary and keeps the list. `uninstall` removes it
along with everything else.

## Other commands

```bash
micguard status      # default input, install state, target, priority list
micguard uninstall   # unload agent, remove plist and binary
micguard run         # run in the foreground (what the agent runs)
micguard run --prefer "Jabra SPEAK 510 USB" --prefer built-in
```

Log: `~/Library/Logs/micguard.log`
