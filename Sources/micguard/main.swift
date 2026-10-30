// micguard: keeps the default input on the Mac's built-in microphone, or on
// a preferred input device chosen at install time.
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

// The preferred device if one was chosen, otherwise the built-in mic.
// nil when it isn't connected, in which case the input is left alone.
func target(_ preferred: String?) -> AudioDeviceID? {
  preferred.map(device(named:)) ?? builtInMic()
}

func defaultInput() -> AudioDeviceID? {
  readUInt32(system, address(kAudioHardwarePropertyDefaultInputDevice))
}

func enforce(_ preferred: String?) {
  guard var mic = target(preferred), defaultInput() != mic else { return }
  let previous = defaultInput().map(name) ?? "none"
  var a = address(kAudioHardwarePropertyDefaultInputDevice)
  let status = AudioObjectSetPropertyData(
    system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mic)
  log(status == noErr ? "input \(previous) -> \(name(mic))" : "set input failed: \(status)")
}

func run(_ preferred: String?) -> Never {
  // Device list changes too, so a preferred device takes over when plugged in.
  for selector in [kAudioHardwarePropertyDefaultInputDevice, kAudioHardwarePropertyDevices] {
    var a = address(selector)
    AudioObjectAddPropertyListenerBlock(system, &a, .main) { _, _ in enforce(preferred) }
  }
  log("watching default input, target: \(preferred ?? "built-in mic")")
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

// Numbered list of input devices; empty answer or 0 keeps the built-in mic.
func pick() -> String? {
  let names = inputDevices().map(name)
  print("Which input should micguard keep as default?")
  print("  0) built-in microphone (default)")
  for (i, n) in names.enumerated() { print("  \(i + 1)) \(n)") }
  while true {
    print("> ", terminator: "")
    guard let line = readLine()?.trimmingCharacters(in: .whitespaces) else { return nil }
    if line.isEmpty || line == "0" { return nil }
    if let i = Int(line), names.indices.contains(i - 1) { return names[i - 1] }
    print("enter a number from 0 to \(names.count)")
  }
}

func install(_ preferred: String?) throws {
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
    "ProgramArguments": [binPath.path, "run"] + (preferred.map { ["--prefer", $0] } ?? []),
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
  print("target \(preferred ?? "built-in mic")")
}

func uninstall() {
  launchctl("bootout", "\(domain)/\(label)", quiet: true)
  try? FileManager.default.removeItem(at: plistPath)
  try? FileManager.default.removeItem(at: binPath)
  print("uninstalled")
}

// The installed agent's --prefer value, read back from its plist.
func installedPreference() -> String? {
  guard let data = try? Data(contentsOf: plistPath),
        let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
        let args = plist["ProgramArguments"] as? [String] else { return nil }
  return preference(args)
}

func status() {
  let installed = FileManager.default.fileExists(atPath: plistPath.path)
  let preferred = installedPreference()
  print("built-in mic:  \(builtInMic().map(name) ?? "not found")")
  print("default input: \(defaultInput().map(name) ?? "none")")
  print("agent plist:   \(installed ? plistPath.path : "not installed")")
  if installed {
    let present = target(preferred) != nil ? "connected" : "not connected"
    print("target:        \(preferred ?? "built-in mic") (\(present))")
  }
}

// MARK: main

func preference(_ args: [String]) -> String? {
  args.firstIndex(of: "--prefer").flatMap { args.indices.contains($0 + 1) ? args[$0 + 1] : nil }
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "run" {
case "run": run(preference(args))
case "install":
  let preferred = args.contains("--prefer") ? preference(args) : (isatty(0) != 0 ? pick() : nil)
  do { try install(preferred) } catch { log("install failed: \(error)"); exit(1) }
case "uninstall": uninstall()
case "status": status()
default:
  print("usage: micguard [run|install|uninstall|status] [--prefer DEVICE]")
  exit(2)
}
