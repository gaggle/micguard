// micguard: keeps the default input on the Mac's built-in microphone, or on
// the highest-priority connected device from a preferred list.
// Output devices are left alone, so AirPods still play audio.
import CoreAudio
import Foundation

let label = "local.micguard"
let system = AudioObjectID(kAudioObjectSystemObject)
let home = FileManager.default.homeDirectoryForCurrentUser
let binPath = home.appendingPathComponent(".local/bin/micguard")
let plistPath = home.appendingPathComponent("Library/LaunchAgents/\(label).plist")
let logPath = home.appendingPathComponent("Library/Logs/micguard.log")
let domain = "gui/\(getuid())"

func log(_ msg: String) { fputs("\(Date()) \(msg)\n", stderr) }

// MARK: CoreAudio

func address(_ selector: AudioObjectPropertySelector,
             _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal)
  -> AudioObjectPropertyAddress {
  AudioObjectPropertyAddress(mSelector: selector, mScope: scope,
                             mElement: kAudioObjectPropertyElementMain)
}

func readUInt32(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress) -> UInt32? {
  var a = addr
  var value: UInt32 = 0
  var size = UInt32(MemoryLayout<UInt32>.size)
  return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr ? value : nil
}

func name(_ id: AudioDeviceID) -> String {
  var a = address(kAudioObjectPropertyName)
  var value: Unmanaged<CFString>?
  var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
  guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr,
        let s = value?.takeRetainedValue() else { return "?" }
  return s as String
}

func allDevices() -> [AudioDeviceID] {
  var a = address(kAudioHardwarePropertyDevices)
  var size: UInt32 = 0
  guard AudioObjectGetPropertyDataSize(system, &a, 0, nil, &size) == noErr else { return [] }
  var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
  guard AudioObjectGetPropertyData(system, &a, 0, nil, &size, &ids) == noErr else { return [] }
  return ids
}

func hasInput(_ id: AudioDeviceID) -> Bool {
  var a = address(kAudioDevicePropertyStreams, kAudioObjectPropertyScopeInput)
  var size: UInt32 = 0
  return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
}

// Found by transport type, so no device name needs configuring.
func builtInMic() -> AudioDeviceID? {
  allDevices().first {
    readUInt32($0, address(kAudioDevicePropertyTransportType)) == kAudioDeviceTransportTypeBuiltIn
      && hasInput($0)
  }
}

func inputDevices() -> [AudioDeviceID] { allDevices().filter(hasInput) }

// Matched by name rather than UID, since a USB device's UID can include its port.
func device(named wanted: String) -> AudioDeviceID? {
  inputDevices().first { name($0) == wanted }
}

// List entry that means the built-in mic, whatever it is called on this Mac.
let builtInEntry = "built-in"

func resolve(_ entry: String) -> AudioDeviceID? {
  entry == builtInEntry ? builtInMic() : device(named: entry)
}

// The first connected device in the priority list, or the built-in mic when
// no list is set. nil when none is connected, in which case the input is left alone.
func target(_ preferred: [String]) -> AudioDeviceID? {
  preferred.isEmpty ? builtInMic() : preferred.lazy.compactMap(resolve).first
}

func describe(_ preferred: [String]) -> String {
  preferred.isEmpty ? "built-in mic" : preferred.joined(separator: " > ")
}

func defaultInput() -> AudioDeviceID? {
  readUInt32(system, address(kAudioHardwarePropertyDefaultInputDevice))
}

func enforce(_ preferred: [String]) {
  guard var mic = target(preferred), defaultInput() != mic else { return }
  let previous = defaultInput().map(name) ?? "none"
  var a = address(kAudioHardwarePropertyDefaultInputDevice)
  let status = AudioObjectSetPropertyData(
    system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mic)
  log(status == noErr ? "input \(previous) -> \(name(mic))" : "set input failed: \(status)")
}

func run(_ preferred: [String]) -> Never {
  // Device list changes too, so a preferred device takes over when plugged in.
  for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
    var a = address(selector)
    AudioObjectAddPropertyListenerBlock(system, &a, .main) { _, _ in enforce(preferred) }
  }
  log("watching default input, priority: \(describe(preferred))")
  enforce(preferred)
  dispatchMain()
}

// MARK: launchd

func launchctl(_ args: String..., quiet: Bool = false) {
  let p = Process()
  p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
  p.arguments = args
  if quiet { p.standardError = FileHandle.nullDevice }
  try? p.run()
  p.waitUntilExit()
}

// Turns device numbers (as printed by `devices`) into names; anything else is
// taken as a device name or `built-in`. nil if a number is out of range.
func choices(_ items: [String]) -> [String]? {
  let names = inputDevices().map(name)
  var out: [String] = []
  for item in items {
    if let i = Int(item) {
      guard names.indices.contains(i - 1) else {
        print("no device \(item); numbers go from 1 to \(names.count)")
        return nil
      }
      out.append(names[i - 1])
    } else {
      if item != builtInEntry && !names.contains(item) { print("note: \(item) is not connected now") }
      out.append(item)
    }
  }
  return out
}

func printDevices() {
  let current = defaultInput()
  let builtIn = builtInMic()
  let preferred = installedPreferences()
  for (i, id) in inputDevices().enumerated() {
    var tags: [String] = []
    if id == current { tags.append("default") }
    if id == builtIn { tags.append("built-in") }
    if let p = preferred.firstIndex(where: { resolve($0) == id }) { tags.append("priority \(p + 1)") }
    print("  \(i + 1)) \(name(id))" + (tags.isEmpty ? "" : "  [\(tags.joined(separator: ", "))]"))
  }
}

func install(_ preferred: [String]) throws {
  let fm = FileManager.default
  guard let me = Bundle.main.executableURL?.resolvingSymlinksInPath() else {
    throw CocoaError(.fileNoSuchFile)
  }
  try fm.createDirectory(at: binPath.deletingLastPathComponent(), withIntermediateDirectories: true)
  if me.path != binPath.path {
    try? fm.removeItem(at: binPath)
    try fm.copyItem(at: me, to: binPath)
  }
  let plist: [String: Any] = [
    "Label": label,
    "ProgramArguments": [binPath.path, "run"] + preferred.flatMap { ["--prefer", $0] },
    "RunAtLoad": true,
    "KeepAlive": true,
    "StandardErrorPath": logPath.path,
  ]
  let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
  try fm.createDirectory(at: plistPath.deletingLastPathComponent(), withIntermediateDirectories: true)
  try data.write(to: plistPath)
  launchctl("bootout", "\(domain)/\(label)", quiet: true)
  launchctl("bootstrap", domain, plistPath.path)
  print("installed \(binPath.path)\nagent \(plistPath.path)\nlog \(logPath.path)")
  print("priority \(describe(preferred))")
}

func uninstall() {
  launchctl("bootout", "\(domain)/\(label)", quiet: true)
  try? FileManager.default.removeItem(at: plistPath)
  try? FileManager.default.removeItem(at: binPath)
  print("uninstalled")
}

// The installed agent's --prefer values, read back from its plist.
func installedPreferences() -> [String] {
  guard let data = try? Data(contentsOf: plistPath),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let args = plist["ProgramArguments"] as? [String] else { return [] }
  return preferences(args)
}

func isInstalled() -> Bool { FileManager.default.fileExists(atPath: plistPath.path) }

func printList() {
  let preferred = installedPreferences()
  if preferred.isEmpty { print("  1) built-in mic (no list set)"); return }
  let active = target(preferred)
  for (i, entry) in preferred.enumerated() {
    let id = resolve(entry)
    let state = id == nil ? "not connected" : id == active ? "active" : "connected"
    print("  \(i + 1)) \(entry)  [\(state)]")
  }
}


func status() {
  let installed = isInstalled()
  let preferred = installedPreferences()
  print("built-in mic:  \(builtInMic().map(name) ?? "not found")")
  print("default input: \(defaultInput().map(name) ?? "none")")
  print("agent plist:   \(installed ? plistPath.path : "not installed")")
  if installed {
    print("target:        \(target(preferred).map(name) ?? "none connected")")
    print("priority:")
    printList()
  }
}

// MARK: main

// Every --prefer value, in order; the order is the priority.
func preferences(_ args: [String]) -> [String] {
  args.indices.compactMap { i in
    args[i] == "--prefer" && args.indices.contains(i + 1) ? args[i + 1] : nil
  }
}

func installOrExit(_ preferred: [String]) {
  do { try install(preferred) } catch { log("install failed: \(error)"); exit(1) }
}

let usage = """
  usage: micguard COMMAND
    devices                   list input devices, numbered
    prefer DEVICE...          set the priority list (numbers from `devices`,
                              names, or `built-in`); installs or restarts the agent
    status                    default input, agent state and priority list
    install                   install or update the agent, keeping the list
    uninstall                 remove the agent and binary
    run [--prefer DEVICE]...  run in the foreground (what the agent runs)
  """

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "run" {
case "run": run(preferences(args))
case "install": installOrExit(installedPreferences())
case "prefer":
  let items = Array(args.dropFirst())
  guard !items.isEmpty, let preferred = choices(items) else { print(usage); exit(2) }
  installOrExit(preferred)
case "devices": printDevices()
case "uninstall": uninstall()
case "status": status()
default:
  print(usage)
  exit(2)
}
