import CoreGraphics
import CoreImage
import CoreMIDI
import Foundation
import SwiftUI

/// The FM-1 over CoreMIDI (USB through a camera adapter or USB-C, or Bluetooth MIDI once paired: both look the same
/// here), its screen, the sound it says it's playing, and the notes played on its own keys.
@MainActor
final class Mirror: ObservableObject {
    enum State: Equatable {
        case noFm1                  // nothing that looks like an FM-1
        case waiting(String)        // an FM-1, but no screen yet (the name of its port)
        case showing(String)
    }

    @Published private(set) var state: State = .noFm1
    @Published private(set) var image: CGImage?
    @Published private(set) var sound: String?
    @Published private(set) var firmware: String?
    /// What the spyglass shows: the notes (sorted), a chord's name, the last velocity; nil = nothing played yet.
    @Published private(set) var shownNotes: [Int]?
    @Published private(set) var shownChord: String?
    @Published private(set) var shownVelocity = 0

    @AppStorage("look") var lookName = Codec.Look.color.rawValue { didSet { redraw() } }
    @AppStorage("smooth") var smooth = true { didSet { redraw() } }
    /// The keyboard that plays the FM-1 through this app: "auto" (the first that isn't an FM-1), "off", or its name.
    @AppStorage("keys") var keysChoice = "auto" { didSet { scan(force: true) } }
    /// Keyboards (MIDI sources that aren't an FM-1) and the one playing it now.
    @Published private(set) var keyboards: [String] = []
    @Published private(set) var keyboard: String?
    var look: Codec.Look { Codec.Look(rawValue: lookName) ?? .color }

    private var pixels = [UInt16](repeating: 0, count: Codec.size * Codec.size)
    private var dirty = false
    private var client = MIDIClientRef()
    private var inPort = MIDIPortRef()
    private var outPort = MIDIPortRef()
    private var sources: [MIDIEndpointRef] = []
    private var keysSource: MIDIEndpointRef = 0
    private let bridge = Bridge()
    private var destinations: [MIDIEndpointRef] = []
    private var portName = ""
    private var helloCount = 0
    private var asked = false
    private var timer: Timer?
    private var frameTimer: Timer?
    private var held: [Int: Int] = [:]          // note -> velocity
    private var lastUp = Date.distantPast
    private var pairTimer: Timer?

    init() {
        MIDIClientCreateWithBlock("FM-1 Big Screen" as CFString, &client) { [weak self] _ in
            Task { @MainActor in self?.scan() }       // something was plugged in, paired or let go
        }
        let receiver = Receiver(), bridge = self.bridge
        MIDIOutputPortCreate(client, "to FM-1" as CFString, &outPort)
        bridge.outPort = outPort
        MIDIInputPortCreateWithProtocol(client, "from FM-1 and the keys" as CFString, ._1_0, &inPort) { list, refCon in
            let fromKeys = refCon == Mirror.keysTag
            if fromKeys { bridge.forward(list) }            // straight on to the FM-1, on CoreMIDI's thread
            let parsed = fromKeys ? Receiver.notes(list) : receiver.parse(list)
            if parsed.sysex.isEmpty && parsed.notes.isEmpty { return }
            Task { @MainActor [weak self] in self?.take(parsed) }
        }
        scan()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        frameTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.frame() }
        }
    }

    // ---- finding the FM-1

    private static func name(_ e: MIDIEndpointRef) -> String {
        var device = "", entity = "", endpoint = ""
        var s: Unmanaged<CFString>?
        if MIDIObjectGetStringProperty(e, kMIDIPropertyName, &s) == noErr, let v = s?.takeRetainedValue() { endpoint = v as String }
        var ent = MIDIEntityRef()
        if MIDIEndpointGetEntity(e, &ent) == noErr {
            if MIDIObjectGetStringProperty(ent, kMIDIPropertyName, &s) == noErr, let v = s?.takeRetainedValue() { entity = v as String }
            var dev = MIDIDeviceRef()
            if MIDIEntityGetDevice(ent, &dev) == noErr,
               MIDIObjectGetStringProperty(dev, kMIDIPropertyName, &s) == noErr, let v = s?.takeRetainedValue() {
                device = v as String
            }
        }
        return [device, entity, endpoint].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Which source a message came from (MIDIPortConnectSource's refCon).
    nonisolated(unsafe) static let fm1Tag = UnsafeMutableRawPointer(bitPattern: 1)
    nonisolated(unsafe) static let keysTag = UnsafeMutableRawPointer(bitPattern: 2)

    private func scan(force: Bool = false) {
        var src: [MIDIEndpointRef] = [], dst: [MIDIEndpointRef] = [], found = ""
        var keyNames: [String] = [], keyEnds: [MIDIEndpointRef] = []
        for i in 0..<MIDIGetNumberOfSources() {
            let e = MIDIGetSource(i)
            let n = Mirror.name(e)
            if Codec.isFm1(n) {
                src.append(e); if found.isEmpty { found = n }
            } else if !n.isEmpty && !keyNames.contains(n) {
                keyNames.append(n); keyEnds.append(e)
            }
        }
        // the keyboard: the one chosen, or with "auto" the first there is
        let pick = keysChoice == "off" ? nil : keysChoice == "auto" ? keyEnds.first
            : keyNames.firstIndex(of: keysChoice).map { keyEnds[$0] }
        keyboards = keyNames
        if pick ?? 0 != keysSource {
            if keysSource != 0 { MIDIPortDisconnectSource(inPort, keysSource) }
            keysSource = pick ?? 0
            if keysSource != 0 { MIDIPortConnectSource(inPort, keysSource, Mirror.keysTag) }
            keyboard = pick.map { keyNames[keyEnds.firstIndex(of: $0)!] }
        }
        for i in 0..<MIDIGetNumberOfDestinations() {
            let e = MIDIGetDestination(i)
            if Codec.isFm1(Mirror.name(e)) { dst.append(e) }
        }
        bridge.setTargets(dst)
        #if DEBUG
        print("scan: \(MIDIGetNumberOfSources()) sources, \(MIDIGetNumberOfDestinations()) destinations; FM-1:",
              src.count, dst.count, found)
        #endif
        if src == sources && dst == destinations && !force { return }
        #if DEBUG
        if portName == "FM1 Demo" { return }
        #endif
        for e in sources { MIDIPortDisconnectSource(inPort, e) }
        for e in src { MIDIPortConnectSource(inPort, e, Mirror.fm1Tag) }
        sources = src
        destinations = dst
        portName = found
        helloCount = 0
        asked = false
        if src.isEmpty || dst.isEmpty {
            state = .noFm1
            firmware = nil
            sound = nil
        } else {
            state = .waiting(found)
            tick()
        }
    }

    private func send(_ bytes: [UInt8]) {
        for d in destinations {
            // MIDISendSysex sends from our buffer and moves `data` along as it goes: the buffer (kept in the
            // request's refCon) and the request are freed when it's done, not before.
            let data = UnsafeMutablePointer<UInt8>.allocate(capacity: bytes.count)
            data.initialize(from: bytes, count: bytes.count)
            let req = UnsafeMutablePointer<MIDISysexSendRequest>.allocate(capacity: 1)
            req.initialize(to: MIDISysexSendRequest(destination: d, data: UnsafePointer(data),
                                                    bytesToSend: UInt32(bytes.count), complete: false,
                                                    reserved: (0, 0, 0), completionProc: { r in
                r.pointee.completionRefCon?.assumingMemoryBound(to: UInt8.self).deallocate()
                r.deallocate()
            }, completionRefCon: UnsafeMutableRawPointer(data)))
            if MIDISendSysex(req) != noErr {
                data.deallocate()
                req.deallocate()
            }
        }
    }

    /// Once a second: hello (the first one asks for the whole screen), and the firmware's name once.
    private func tick() {
        guard !destinations.isEmpty else { return }
        send(helloCount == 0 ? Codec.helloAll : Codec.hello)
        helloCount += 1
        if !asked { asked = true; send(Codec.askInfo) }
    }

    // ---- what comes in

    private func take(_ p: Receiver.Parsed) {
        for m in p.sysex {
            if Codec.apply(&pixels, m) {
                dirty = true
                if case .showing = state {} else { state = .showing(portName) }
            } else if let s = Codec.sound(m) {
                sound = s.isEmpty ? nil : s
            } else if let info = Codec.firmwareInfo(m) {
                firmware = Codec.firmwareName(info)
            }
        }
        for (note, velocity) in p.notes {
            if velocity > 0 { held[note] = velocity; shownVelocity = velocity } else { held[note] = nil }
        }
        if !p.notes.isEmpty { follow() }
    }

    /// The spyglass follows the keys: one key its note, more a chord (an interval only after it's been held a little,
    /// so legato playing doesn't flash pairs); the last notes stay 3 s after the keys come up.
    private func follow() {
        pairTimer?.invalidate()
        let keys = held.keys.sorted()
        if keys.isEmpty {
            lastUp = Date()
            let stamp = lastUp
            Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.held.isEmpty, self.lastUp == stamp else { return }
                    self.shownNotes = nil
                    self.shownChord = nil
                }
            }
            return
        }
        if keys.count == 1 {
            shownNotes = keys
            shownChord = nil
            return
        }
        let name = Chord.name(keys) ?? keys.map(NoteNames.name).joined(separator: " ")
        if Chord.isPair(keys) {
            pairTimer = Timer.scheduledTimer(withTimeInterval: Chord.pairExtraMs / 1000, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.held.keys.sorted() == keys else { return }
                    self.shownNotes = keys
                    self.shownChord = name
                }
            }
        } else {
            shownNotes = keys
            shownChord = name
        }
    }

    #if DEBUG
    /// Demo.swift: as if an FM-1 named "FM1 Demo" were plugged in.
    func demoBegin() { portName = "FM1 Demo"; state = .waiting(portName); firmware = "ERIK37 (recording)" }
    func demoTake(_ p: Receiver.Parsed) { take(p) }
    #endif

    // ---- the picture

    private var rendering = false

    private func frame() {
        if dirty && !rendering { dirty = false; redraw() }
    }

    /// Makes the picture off the main thread (the look, Smooth: a 960 x 960 image), one at a time; rows that come
    /// meanwhile mark it dirty again and go into the next one.
    func redraw() {
        guard case .showing = state else { if image != nil && state == .noFm1 { image = nil }; return }
        if rendering { dirty = true; return }
        rendering = true
        let snapshot = pixels, look = self.look, smooth = self.smooth
        Task.detached(priority: .userInitiated) {
            let made = Mirror.render(snapshot, look, smooth)
            await MainActor.run {
                self.image = made
                self.rendering = false
            }
        }
    }

    /// One Core Image context for every frame (they're costly to make).
    nonisolated private static let ci = CIContext(options: [.useSoftwareRenderer: false])

    /// The picture in the chosen look; with Smooth, 4 times bigger with Lanczos and a light unsharp mask, which keeps
    /// letters crisp and smooth (Erik37 and others dither their screens: Scale2x made stairs of the dots).
    nonisolated static func render(_ pixels: [UInt16], _ look: Codec.Look, _ smooth: Bool) -> CGImage? {
        let argb = look.paintAll(pixels, side: Codec.size)
        let size = Codec.size
        let plain: CGImage? = argb.withUnsafeBytes { raw -> CGImage? in
            guard let provider = CGDataProvider(data: Data(raw) as CFData) else { return nil }
            return CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
                           space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipFirst.rawValue
                                                    | CGBitmapInfo.byteOrder32Little.rawValue),
                           provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
        }
        guard smooth, let plain else { return plain }
        let scale = CGFloat(Codec.smoothScale)
        let big = CIImage(cgImage: plain).clampedToExtent()
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1])
            .applyingFilter("CIUnsharpMask", parameters: [kCIInputRadiusKey: 1.0, kCIInputIntensityKey: 2.6])
        let out = CGRect(x: 0, y: 0, width: CGFloat(size) * scale, height: CGFloat(size) * scale)
        return ci.createCGImage(big, from: out)
    }
}

/// The keyboard to the FM-1: its notes and controls (MIDI 1.0 channel voice messages), on channel 1, where the FM-1
/// listens, whatever channel the keyboard sends on. Runs on CoreMIDI's thread, so nothing waits on the screen.
final class Bridge: @unchecked Sendable {
    private let lock = NSLock()
    private var targets: [MIDIEndpointRef] = []
    var outPort = MIDIPortRef()

    func setTargets(_ t: [MIDIEndpointRef]) { lock.lock(); targets = t; lock.unlock() }

    func forward(_ list: UnsafePointer<MIDIEventList>) {
        lock.lock(); let t = targets; lock.unlock()
        guard !t.isEmpty else { return }
        var words: [UInt32] = []
        Receiver.eachWord(list) { w in
            if w >> 28 == 0x2 { words.append(w & 0xFFF0_FFFF) }     // channel voice: channel 1 (its low nibble 0)
        }
        guard !words.isEmpty else { return }
        var i = 0
        while i < words.count {                                       // a packet holds up to 64 words
            let chunk = Array(words[i..<min(i + 60, words.count)])
            var out = MIDIEventList()
            let packet = MIDIEventListInit(&out, ._1_0)
            _ = chunk.withUnsafeBufferPointer { MIDIEventListAdd(&out, MemoryLayout<MIDIEventList>.size, packet, 0, $0.count, $0.baseAddress!) }
            for d in t { MIDISendEventList(outPort, d, &out) }
            i += 60
        }
    }
}

/// Turns CoreMIDI's MIDI 1.0 event lists (Universal MIDI Packets) back into SysEx messages and notes. Runs on
/// CoreMIDI's own thread; only this object touches its state.
final class Receiver: @unchecked Sendable {
    struct Parsed {
        var sysex: [[UInt8]] = []
        var notes: [(Int, Int)] = []            // note, velocity (0: up)
    }

    private var part: [UInt8] = []

    /// Every 32-bit word of every packet.
    static func eachWord(_ list: UnsafePointer<MIDIEventList>, _ body: (UInt32) -> Void) {
        let offset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.wordCount)
            let w = UnsafeBufferPointer(start: (UnsafeRawPointer(packet) + offset).assumingMemoryBound(to: UInt32.self), count: n)
            for x in w { body(x) }
        }
    }

    /// Only the notes (the keyboard's: nothing else is needed from it).
    static func notes(_ list: UnsafePointer<MIDIEventList>) -> Parsed {
        var out = Parsed()
        eachWord(list) { w in
            guard w >> 28 == 0x2 else { return }
            let status = (w >> 16) & 0xF0, d1 = Int((w >> 8) & 0x7F), d2 = Int(w & 0x7F)
            if status == 0x90 { out.notes.append((d1, d2)) }
            if status == 0x80 { out.notes.append((d1, 0)) }
        }
        return out
    }

    func parse(_ list: UnsafePointer<MIDIEventList>) -> Parsed {
        var out = Parsed()
        let offset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
        for packet in list.unsafeSequence() {
            let n = Int(packet.pointee.wordCount)
            let words = UnsafeBufferPointer(start: (UnsafeRawPointer(packet) + offset).assumingMemoryBound(to: UInt32.self),
                                            count: n)
            var i = 0
            while i < words.count {
                let w0 = words[i]
                let type = w0 >> 28
                switch type {
                case 0x2:                                   // MIDI 1.0 channel voice, one word
                    let status = (w0 >> 16) & 0xF0, d1 = Int((w0 >> 8) & 0x7F), d2 = Int(w0 & 0x7F)
                    if status == 0x90 { out.notes.append((d1, d2)) }
                    if status == 0x80 { out.notes.append((d1, 0)) }
                    i += 1
                case 0x3:                                   // 7-bit SysEx, two words: up to six bytes
                    guard i + 1 < words.count else { i = words.count; break }
                    let w1 = words[i + 1]
                    let status = (w0 >> 20) & 0xF, count = Int((w0 >> 16) & 0xF)
                    let bytes: [UInt8] = [UInt8((w0 >> 8) & 0x7F), UInt8(w0 & 0x7F), UInt8((w1 >> 24) & 0x7F),
                                          UInt8((w1 >> 16) & 0x7F), UInt8((w1 >> 8) & 0x7F), UInt8(w1 & 0x7F)]
                    let data = bytes.prefix(min(count, 6))
                    switch status {
                    case 0: out.sysex.append([0xF0] + data + [0xF7])      // complete in one
                    case 1: part = [0xF0] + data                          // start
                    case 2: part += data                                  // continue
                    default:                                              // end
                        part += data
                        part.append(0xF7)
                        out.sysex.append(part)
                        part = []
                    }
                    i += 2
                case 0x0, 0x1, 0x6, 0x7: i += 1             // utility, system: one word
                case 0x4, 0x8, 0x9, 0xA: i += 2
                case 0xB, 0xC: i += 3
                default: i += 4
                }
            }
        }
        return out
    }
}
