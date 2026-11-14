import Foundation

/// The FM-1's messages, the same as the Android app's Codec.java and the desktop app's src/screen.rs.
///
/// Screen: the app says hello (F0 7D 'F' 'S' 00 F7, or 01 to have the whole screen sent again) about once a second;
/// while it does, a Big Screen firmware sends every row it paints as F0 7D 'F' 'S' 01, the row and first column (two
/// 7-bit bytes each), then runs of four bytes: a count, and the RGB565 colour in 7, 7 and 2 bits.
enum Codec {
    static let size = 240
    static let hello: [UInt8] = [0xF0, 0x7D, 0x46, 0x53, 0x00, 0xF7]
    /// Hello, and send the whole screen again.
    static let helloAll: [UInt8] = [0xF0, 0x7D, 0x46, 0x53, 0x01, 0xF7]
    /// Asks a firmware of the Felucca family what it is (its editor's INFO); others don't answer.
    static let askInfo: [UInt8] = [0xF0, 0x7D, 0x46, 0x4C, 0x01, 0xF7]

    /// Paints one row message into `pixels` (RGB565, row by row); false if it isn't one.
    static func apply(_ pixels: inout [UInt16], _ m: [UInt8]) -> Bool {
        let n = m.count
        guard n >= 10, m[0] == 0xF0, m[1] == 0x7D, m[2] == 0x46, m[3] == 0x53, m[4] == 1, m[n - 1] == 0xF7 else { return false }
        let y = Int(m[5] & 127) | Int(m[6] & 127) << 7
        var x = Int(m[7] & 127) | Int(m[8] & 127) << 7
        guard y < size else { return false }
        var i = 9
        while i + 4 <= n - 1 {
            let c = UInt32(m[i + 1] & 127) | UInt32(m[i + 2] & 127) << 7 | UInt32(m[i + 3] & 127) << 14
            for _ in 0..<Int(m[i] & 127) {
                if x < size { pixels[y * size + x] = UInt16(c & 0xFFFF) }
                x += 1
            }
            i += 4
        }
        return true
    }

    /// The sound playing, if this is the FM-1 saying it: F0 7D 'F' 'S' 02 name F7 ("" for none).
    static func sound(_ m: [UInt8]) -> String? {
        let n = m.count
        guard n >= 6, m[0] == 0xF0, m[1] == 0x7D, m[2] == 0x46, m[3] == 0x53, m[4] == 2, m[n - 1] == 0xF7 else { return nil }
        let s = String(decoding: m[5..<(n - 1)].filter { $0 >= 0x20 && $0 < 0x7F }, as: UTF8.self)
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// The firmware's own name, if this is its answer to askInfo: "FELUCCA SLOOP 2.8.4", then other things.
    static func firmwareInfo(_ m: [UInt8]) -> String? {
        let n = m.count
        guard n >= 7, m[0] == 0xF0, m[1] == 0x7D, m[2] == 0x46, m[3] == 0x4C, m[4] == 1, m[n - 1] == 0xF7 else { return nil }
        var s = ""
        for b in m[5..<(n - 1)] {
            if b == 0 { break }
            if b >= 0x20 && b < 0x7F { s.append(Character(UnicodeScalar(b))) }
        }
        let name = s.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    /// The name to show: "FELUCCA SLOOP 2.8.4" is SLOOP; "FELUCCA v2.1.1" is Felucca.
    static func firmwareName(_ info: String) -> String {
        guard info.hasPrefix("FELUCCA ") else { return info }
        let rest = String(info.dropFirst(8))
        let bareVersion = rest.count > 1 && rest.first == "v" && rest.dropFirst().first?.isNumber == true
        return bareVersion ? "Felucca " + rest : rest
    }

    /// The FM-1's MIDI name: "FM1 Community" with Open firmware, "USB Composite Device" with the original, the
    /// Felucca family's own names (Felucca, JIANT, ChoralRoot), and "..._BLE" over Bluetooth.
    static func isFm1(_ name: String) -> Bool {
        let n = name.lowercased()
        let felucca = (n.contains("jiant") && !n.contains("update")) || n.contains("felucca") || n.contains("choralroot")
            || n.contains("erik37")
        return (n.contains("fm1") || n.contains("fm-1") || felucca || n.contains("usb composite") || n.contains("loom-8"))
            && !n.contains("bridge") && !n.contains("mirror")
    }

    /// RGB565 to 8-bit red, green, blue.
    @inline(__always) static func rgb(_ c: UInt16) -> (Int, Int, Int) {
        let r = Int(c >> 11) & 31, g = Int(c >> 5) & 63, b = Int(c) & 31
        return (r << 3 | r >> 2, g << 2 | g >> 4, b << 3 | b >> 2)
    }

    /// Ways to show the screen, easier to read for some eyes.
    enum Look: String, CaseIterable, Identifiable {
        case color = "Color", bright = "Bright color", yellow = "Yellow on black", white = "White on black",
             inverted = "Black on white"
        var id: String { rawValue }

        /// An RGB565 pixel as 0xAARRGGBB.
        func paint(_ c: UInt16) -> UInt32 {
            let (r, g, b) = Codec.rgb(c)
            let luma = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255
            let lit = Int(min(1, luma * 1.6) * 255)   // light text on black: anything not background at full strength
            switch self {
            case .bright: return Look.lift(Look.bright(r), Look.bright(g), Look.bright(b))
            case .yellow: return Look.argb(lit, lit, 0)
            case .white: return Look.argb(lit, lit, lit)
            case .inverted: return Look.argb(255 - lit, 255 - lit, 255 - lit)
            case .color: return Look.argb(r, g, b)
            }
        }

        private static func bright(_ v: Int) -> Int { Int(min(255, Double(v) * 1.6)) }

        /// Any colour that isn't the black background up to at least 80% brightness, keeping its hue.
        private static func lift(_ r0: Int, _ g0: Int, _ b0: Int) -> UInt32 {
            var r = r0, g = g0, b = b0
            let l = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 255, want = 0.8
            if l > 0.03 && l < want {
                let t = (want - l) / (1 - l)
                r += Int(Double(255 - r) * t); g += Int(Double(255 - g) * t); b += Int(Double(255 - b) * t)
            }
            return argb(r, g, b)
        }

        @inline(__always) static func argb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
            0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
        }
    }

    /// Smooth: how many times bigger the picture is made (Mirror.render: Lanczos and an unsharp mask).
    static let smoothScale = 4
}

/// SysEx out of a byte stream that may arrive in pieces.
struct SysexAssembler {
    private var part: [UInt8] = []
    private var inside = false

    mutating func feed(_ bytes: [UInt8], _ sink: ([UInt8]) -> Void) {
        for b in bytes {
            if b == 0xF0 {
                part = [b]; inside = true
            } else if b >= 0xF8 {
                // clock and other real-time bytes may come between any two others
            } else if inside && b == 0xF7 {
                part.append(b); inside = false; sink(part)
            } else if inside && b < 0x80 {
                part.append(b)
            } else {
                inside = false
            }
        }
    }
}

/// Note names and pitches.
enum NoteNames {
    private static let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    /// Equal-tempered pitch, A4 (note 69) = 440 Hz.
    static func hz(_ note: Int) -> Double { 440 * pow(2, Double(note - 69) / 12) }
    static func pitchClass(_ note: Int) -> String { names[note % 12] }
    static func name(_ note: Int) -> String { names[note % 12] + String(note / 12 - 1) }
}

/// Names the chord made by a set of held keys (C4 E4 G4: "C major", E3 G3 C4: "C major / E", A3 C4 E4 G4: "Am7"),
/// an interval for two notes ("E + G", "minor 3rd"), or nil. The same as the Android app's Chord.java.
enum Chord {
    private static let shapes: [[Int]] = [
        [0, 4, 7], [0, 3, 7], [0, 3, 6], [0, 4, 8], [0, 2, 7], [0, 5, 7],
        [0, 4, 7, 10], [0, 4, 7, 11], [0, 3, 7, 10], [0, 3, 6, 10], [0, 3, 6, 9],
        [0, 3, 7, 11], [0, 4, 7, 9], [0, 3, 7, 9], [0, 5, 7, 10], [0, 2, 4, 7], [0, 2, 3, 7],
        [0, 2, 4, 7, 10], [0, 2, 4, 7, 11], [0, 2, 3, 7, 10],
        [0, 4, 10], [0, 4, 11], [0, 3, 10],
    ]
    private static let suffix = [
        " major", " minor", "dim", "aug", "sus2", "sus4",
        "7", "maj7", "m7", "m7b5", "dim7",
        "m(maj7)", "6", "m6", "7sus4", "add9", "m(add9)",
        "9", "maj9", "m9",
        "7", "maj7", "m7",
    ]
    /// An interval must stay held this much longer than a chord before it's named (legato playing).
    static let pairExtraMs: Double = 200
    private static let intervals = ["octave", "minor 2nd", "major 2nd", "minor 3rd", "major 3rd", "4th",
                                    "tritone", "5th", "minor 6th", "major 6th", "minor 7th", "major 7th"]

    static func name(_ notes: [Int]) -> String? {
        if pairBass(notes) >= 0 { return pairName(notes) }
        guard notes.count >= 3 else { return nil }
        let bass = lowest(notes) % 12, m = mask(notes)
        guard m.nonzeroBitCount >= 3 else { return nil }
        var best: String?
        for root in 0..<12 where m & (1 << root) != 0 {
            for s in shapes.indices where shapeMask(shapes[s], root) == m {
                let name = NoteNames.pitchClass(root) + suffix[s]
                if root == bass { return name }
                if best == nil { best = name + " / " + NoteNames.pitchClass(bass) }
            }
        }
        return best
    }

    static func isPair(_ notes: [Int]) -> Bool { pairBass(notes) >= 0 }

    static func interval(_ notes: [Int]) -> String? {
        let bass = pairBass(notes)
        guard bass >= 0 else { return nil }
        let rest = mask(notes) & ~(1 << bass)
        let other = rest == 0 ? bass : rest.trailingZeroBitCount
        return intervals[(other - bass + 12) % 12]
    }

    private static func pairBass(_ notes: [Int]) -> Int {
        guard notes.count >= 2 else { return -1 }
        let pcs = mask(notes).nonzeroBitCount
        return pcs == 2 || pcs == 1 ? lowest(notes) % 12 : -1
    }

    private static func pairName(_ notes: [Int]) -> String {
        let bass = pairBass(notes)
        let rest = mask(notes) & ~(1 << bass)
        let other = rest == 0 ? bass : rest.trailingZeroBitCount
        return NoteNames.pitchClass(bass) + " + " + NoteNames.pitchClass(other)
    }

    private static func mask(_ notes: [Int]) -> Int { notes.reduce(0) { $0 | 1 << ($1 % 12) } }
    private static func shapeMask(_ shape: [Int], _ root: Int) -> Int { shape.reduce(0) { $0 | 1 << (($1 + root) % 12) } }
    private static func lowest(_ notes: [Int]) -> Int { notes.min() ?? 0 }
}
