// Generates an A/V sync test video: a marker sweeps across a ruler marked in milliseconds
// and a short click plays at the exact moment the marker crosses 0.
// Where the marker is when you HEAR the click = how late (or early) the audio is.
// Usage: make-sync-test <output.mov>
import AVFoundation
import CoreGraphics
import CoreText
import Foundation

let outURL = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.removeItem(at: outURL)
let W = 1280, H = 720, fps = 60, seconds = 60
let period = 2.0            // one sweep every 2 s, click in the middle of each sweep
let msSpan = 2000.0         // ruler covers -1000 ms ... +1000 ms
let sampleRate = 48000.0

let writer = try AVAssetWriter(outputURL: outURL, fileType: .mov)
let vIn = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: vIn, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H])
var asbd = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: 2, mBitsPerChannel: 16, mReserved: 0)
var fmt: CMAudioFormatDescription?
CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &fmt)
let aIn = AVAssetWriterInput(mediaType: .audio, outputSettings: nil, sourceFormatHint: fmt)  // nil = store PCM untouched
writer.add(vIn); writer.add(aIn)
writer.startWriting(); writer.startSession(atSourceTime: .zero)

func text(_ ctx: CGContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, centered: Bool = true, gray: CGFloat = 1) {
    let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
    let attr = NSAttributedString(string: s, attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: gray, alpha: 1)])
    let line = CTLineCreateWithAttributedString(attr)
    let w = CTLineGetBoundsWithOptions(line, []).width
    ctx.textPosition = CGPoint(x: centered ? x - w / 2 : x, y: y)
    CTLineDraw(line, ctx)
}
func xFor(ms: Double) -> CGFloat { CGFloat(Double(W) / 2 + ms / msSpan * Double(W)) }

// ---- audio: 15 ms 1 kHz click at 1 s, 3 s, 5 s, ... ----
let total = Int(sampleRate) * seconds
var pcm = [Int16](repeating: 0, count: total * 2)
let clickLen = Int(0.015 * sampleRate)
var clickT = period / 2
while clickT < Double(seconds) {
    let start = Int(clickT * sampleRate)
    for i in 0..<clickLen where start + i < total {
        let env = min(1.0, Double(clickLen - i) / Double(clickLen) * 3)   // instant attack, short fade
        let v = Int16(sin(2 * .pi * 1000 * Double(i) / sampleRate) * env * 16000)
        pcm[(start + i) * 2] = v; pcm[(start + i) * 2 + 1] = v
    }
    clickT += period
}
var pos = 0
func appendAudioSecond() {
    guard pos < total else { return }
    let chunk = 800   // exactly one video frame of audio (48000 / 60)
    while !aIn.isReadyForMoreMediaData { usleep(2000) }
    let n = min(chunk, total - pos)
    var block: CMBlockBuffer?
    CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: n * 4, blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: n * 4, flags: 0, blockBufferOut: &block)
    pcm.withUnsafeBytes { _ = CMBlockBufferReplaceDataBytes(with: $0.baseAddress! + pos * 4, blockBuffer: block!, offsetIntoDestination: 0, dataLength: n * 4) }
    var sb: CMSampleBuffer?
    CMAudioSampleBufferCreateReadyWithPacketDescriptions(allocator: nil, dataBuffer: block!, formatDescription: fmt!, sampleCount: n, presentationTimeStamp: CMTime(value: CMTimeValue(pos), timescale: 48000), packetDescriptions: nil, sampleBufferOut: &sb)
    aIn.append(sb!)
    pos += n
}

// ---- video (one frame of audio is written after each video frame, so neither track stalls waiting for the other) ----
for frame in 0..<(fps * seconds) {
    while !vIn.isReadyForMoreMediaData { usleep(2000) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    CVPixelBufferLockBaseAddress(pb!, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb!), width: W, height: H, bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(pb!), space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    let t = Double(frame) / Double(fps)
    let phase = t.truncatingRemainder(dividingBy: period)       // 0..2 s; click at 1.0 s
    let ms = (phase - period / 2) * 1000                        // -1000..+1000
    ctx.setFillColor(CGColor(gray: 0.06, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
    // flash block for the first 2 frames after the click (for slow-motion camera measurements)
    if ms >= 0 && ms < 2000.0 / Double(fps) {
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 520, width: W, height: 200))
    }
    text(ctx, "A/V SYNC TEST — click plays when the marker crosses 0", CGFloat(W) / 2, 470, 30)
    text(ctx, "← you hear the click here: sound is EARLY", 20, 120, 24, centered: false, gray: 0.7)
    text(ctx, "sound is LATE: you hear the click here →", CGFloat(W) - 500, 120, 24, centered: false, gray: 0.7)
    text(ctx, "numbers are milliseconds", CGFloat(W) / 2, 60, 22, gray: 0.5)
    // ruler
    let baseY: CGFloat = 250
    for m in stride(from: -1000, through: 1000, by: 50) {
        let major = m % 100 == 0
        ctx.setFillColor(CGColor(gray: m == 0 ? 1 : 0.6, alpha: 1))
        ctx.fill(CGRect(x: xFor(ms: Double(m)) - (m == 0 ? 2 : 1), y: baseY, width: m == 0 ? 4 : 2, height: major ? 60 : 30))
        if m % 200 == 0 { text(ctx, m > 0 ? "+\(m)" : "\(m)", xFor(ms: Double(m)), baseY - 34, 22, gray: m == 0 ? 1 : 0.75) }
    }
    // moving marker
    ctx.setFillColor(CGColor(red: 1, green: 0.25, blue: 0.2, alpha: 1))
    ctx.fill(CGRect(x: xFor(ms: ms) - 5, y: baseY + 60, width: 10, height: 130))
    text(ctx, String(format: "%+.0f ms", ms), CGFloat(W) / 2, 410, 28, gray: 0.5)
    CVPixelBufferUnlockBaseAddress(pb!, [])
    adaptor.append(pb!, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
    appendAudioSecond()
}
vIn.markAsFinished()

aIn.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print(writer.status == .completed ? "wrote \(outURL.path)" : "FAILED: \(String(describing: writer.error))")
