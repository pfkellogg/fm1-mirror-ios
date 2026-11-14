#if DEBUG
import Foundation

/// Test builds only, started with `-demo`: plays a recording of a real FM-1's Big Screen messages
/// (Resources/Demo/erik37.syx: Erik37 + Big Screen) into the mirror, then an A minor 7 chord, so the screen, the looks,
/// Smooth and the spyglass can be checked in the simulator, which can't see USB or Bluetooth MIDI devices.
/// (The CoreMIDI side, finding the FM-1 and the UMP parser, needs a real iPad.)
@MainActor
enum Demo {
    static func start(_ mirror: Mirror) {
        guard ProcessInfo.processInfo.arguments.contains("-demo"),
              let url = Bundle.main.url(forResource: "erik37", withExtension: "syx"),
              let data = try? Data(contentsOf: url) else { return }
        let bytes = [UInt8](data)
        var messages: [[UInt8]] = []
        var start = 0
        for (i, b) in bytes.enumerated() where b == 0xF7 {
            messages.append(Array(bytes[start...i]))
            start = i + 1
        }
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
}
#endif
