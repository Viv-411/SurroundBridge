// Lists every audio output device and the physical stream formats it offers.
// We look for 'cac3' / 'ac-3' / 'IAC3' / 'iac3' — those mean "this device accepts an AC-3 bitstream".
import CoreAudio
import Foundation

func fourCC(_ v: UInt32) -> String {
    let b = [UInt8((v >> 24) & 255), UInt8((v >> 16) & 255), UInt8((v >> 8) & 255), UInt8(v & 255)]
    return String(bytes: b, encoding: .ascii) ?? "\(v)"
}
func getArray<T>(_ id: AudioObjectID, _ sel: AudioObjectPropertySelector, _ scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, _ type: T.Type) -> [T] {
    var addr = AudioObjectPropertyAddress(mSelector: sel, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(id, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
    let count = Int(size) / MemoryLayout<T>.stride
    let buf = UnsafeMutablePointer<T>.allocate(capacity: count); defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, buf) == noErr else { return [] }
    return Array(UnsafeBufferPointer(start: buf, count: count))
}
func name(_ id: AudioObjectID) -> String {
    var addr = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var s: Unmanaged<CFString>?; var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
    guard AudioObjectGetPropertyData(id, &addr, 0, nil, &size, &s) == noErr, let v = s else { return "?" }
    return v.takeRetainedValue() as String
}
let sys = AudioObjectID(kAudioObjectSystemObject)
let defOut = getArray(sys, kAudioHardwarePropertyDefaultOutputDevice, kAudioObjectPropertyScopeGlobal, AudioObjectID.self).first ?? 0
for dev in getArray(sys, kAudioHardwarePropertyDevices, kAudioObjectPropertyScopeGlobal, AudioObjectID.self) {
    let streams = getArray(dev, kAudioDevicePropertyStreams, kAudioObjectPropertyScopeOutput, AudioObjectID.self)
    if streams.isEmpty { continue }
    print("DEVICE: \(name(dev))\(dev == defOut ? "   <-- current default output" : "")")
    for (i, st) in streams.enumerated() {
        let cur = getArray(st, kAudioStreamPropertyPhysicalFormat, kAudioObjectPropertyScopeGlobal, AudioStreamBasicDescription.self).first
        if let c = cur { print("  stream \(i) current: \(fourCC(c.mFormatID)) \(Int(c.mSampleRate)) Hz \(c.mChannelsPerFrame) ch \(c.mBitsPerChannel) bit") }
        var seen = Set<String>()
        for f in getArray(st, kAudioStreamPropertyAvailablePhysicalFormats, kAudioObjectPropertyScopeGlobal, AudioStreamRangedDescription.self) {
            let d = f.mFormat
            let s = "\(fourCC(d.mFormatID)) \(Int(d.mSampleRate)) Hz \(d.mChannelsPerFrame) ch \(d.mBitsPerChannel) bit"
            if seen.insert(s).inserted { print("    available: \(s)") }
        }
    }
}
