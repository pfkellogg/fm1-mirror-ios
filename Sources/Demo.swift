#if DEBUG
import CoreMIDI
import Foundation

/// Test builds only. The simulator can't see USB or Bluetooth MIDI devices, so:
///   -demo        plays a recording of a real FM-1's Big Screen messages (Resources/Demo/erik37.syx: Erik37 + Big
///                Screen) straight into the mirror, then an A minor 7 chord.
///   -demo-midi   the same through CoreMIDI: a pretend FM-1 ("FM1 Demo", a virtual source and destination) that the
///                app has to find, say hello to and read (the UMP parser), and a pretend keyboard ("Demo Keys") that
///                plays a C major chord, for the keyboard bridge.
@MainActor
enum Demo {
    private static var client = MIDIClientRef()
    nonisolated(unsafe) private static var fm1Out = MIDIEndpointRef()       // what the pretend FM-1 sends
    private static var fm1In = MIDIEndpointRef()        // what reaches it (hellos, the keyboard's notes)
    nonisolated(unsafe) private static var keys = MIDIEndpointRef()
    nonisolated(unsafe) static var heardByFm1: [UInt32] = []   // UMP words that reached the pretend FM-1

    static func start(_ mirror: Mirror) {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-demo") || args.contains("-demo-midi"),
              let url = Bundle.main.url(forResource: "erik37", withExtension: "syx"),
              let data = try? Data(contentsOf: url) else { return }
        let bytes = [UInt8](data)
        var messages: [[UInt8]] = []
        var start = 0
        for (i, b) in bytes.enumerated() where b == 0xF7 {
            messages.append(Array(bytes[start...i]))
            start = i + 1
        }
        if args.contains("-demo-midi") { throughMidi(messages) } else { direct(mirror, messages) }
    }

    private static func direct(_ mirror: Mirror, _ messages: [[UInt8]]) {
        mirror.demoBegin()
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            var parsed = Receiver.Parsed()
            for (k, m) in messages.enumerated() {
                parsed.sysex.append(m)
                if k % 200 == 199 { mirror.demoTake(parsed); parsed = Receiver.Parsed(); try? await Task.sleep(nanoseconds: 20_000_000) }
            }
            mirror.demoTake(parsed)
            try? await Task.sleep(nanoseconds: 800_000_000)
            var chord = Receiver.Parsed()
            chord.notes = [(57, 100), (60, 100), (64, 100), (67, 100)]
            mirror.demoTake(chord)
        }
    }

    private static func throughMidi(_ messages: [[UInt8]]) {
        let a = MIDIClientCreateWithBlock("FM1 Demo" as CFString, &client, nil)
        let b = MIDISourceCreateWithProtocol(client, "FM1 Demo" as CFString, ._1_0, &fm1Out)
        let c = MIDIDestinationCreateWithProtocol(client, "FM1 Demo" as CFString, ._1_0, &fm1In) { list, _ in
            for p in list.unsafeSequence() {
                let n = Int(p.pointee.wordCount)
                let off = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words)!
                let w = UnsafeBufferPointer(start: (UnsafeRawPointer(p) + off).assumingMemoryBound(to: UInt32.self), count: n)
                heardByFm1.append(contentsOf: w)
            }
        }
        let d = MIDISourceCreateWithProtocol(client, "Demo Keys" as CFString, ._1_0, &keys)
        print("demo-midi: client \(a) fm1 \(b) \(c) keys \(d)")
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            for (k, m) in messages.enumerated() {
                send(fm1Out, m)
                if k % 50 == 49 { usleep(3_000) }
            }
            print("demo-midi: sent \(messages.count) messages; the FM-1 heard \(heardByFm1.count) words")
            usleep(800_000)
            for n in [48, 60, 64, 67] { send(keys, [0x90, UInt8(n), 90]) }   // the keyboard: C major
            usleep(500_000)
            let notes = heardByFm1.filter { $0 >> 28 == 0x2 && ($0 >> 16) & 0xF0 == 0x90 }.map { ($0 >> 8) & 0x7F }
            print("demo-midi: notes the FM-1 got from the keyboard: \(notes)")
        }
    }

    /// Bytes out of a virtual source, as the old packet list (CoreMIDI turns it into UMP for the reader).
    nonisolated private static func send(_ source: MIDIEndpointRef, _ m: [UInt8]) {
        var list = MIDIPacketList()
        let packet = MIDIPacketListInit(&list)
        _ = m.withUnsafeBufferPointer { buf in
            MIDIPacketListAdd(&list, MemoryLayout<MIDIPacketList>.size, packet, 0, buf.count, buf.baseAddress!)
        }
        MIDIReceived(source, &list)
    }
}
#endif
