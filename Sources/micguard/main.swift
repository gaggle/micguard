// micguard: keeps the default input on the Mac's built-in microphone.
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

func defaultInput() -> AudioDeviceID? {
  readUInt32(system, address(kAudioHardwarePropertyDefaultInputDevice))
}

func enforce() {
  guard var mic = builtInMic(), defaultInput() != mic else { return }
  let previous = defaultInput().map(name) ?? "none"
  var a = address(kAudioHardwarePropertyDefaultInputDevice)
  let status = AudioObjectSetPropertyData(
    system, &a, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &mic)
  log(status == noErr ? "input \(previous) -> \(name(mic))" : "set input failed: \(status)")
}

func run() -> Never {
  var a = address(kAudioHardwarePropertyDefaultInputDevice)
  AudioObjectAddPropertyListenerBlock(system, &a, .main) { _, _ in enforce() }
  log("watching default input")
  enforce()
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

func install() throws {
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
    "ProgramArguments": [binPath.path, "run"],
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
}

func uninstall() {
  launchctl("bootout", "\(domain)/\(label)", quiet: true)
  try? FileManager.default.removeItem(at: plistPath)
  try? FileManager.default.removeItem(at: binPath)
  print("uninstalled")
}

func status() {
  print("built-in mic:  \(builtInMic().map(name) ?? "not found")")
  print("default input: \(defaultInput().map(name) ?? "none")")
  print("agent plist:   \(FileManager.default.fileExists(atPath: plistPath.path) ? plistPath.path : "not installed")")
}

// MARK: main

switch CommandLine.arguments.dropFirst().first ?? "run" {
case "run": run()
case "install":
  do { try install() } catch { log("install failed: \(error)"); exit(1) }
case "uninstall": uninstall()
case "status": status()
default:
  print("usage: micguard [run|install|uninstall|status]")
  exit(2)
}
