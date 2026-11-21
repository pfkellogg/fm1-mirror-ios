import Foundation

/// The other FM-1 screen mirror: Charles Vestal's, in firmware built on fm1-base with `mirror = true` in its fm1.toml
/// (LOOM-8, Polly, Ocarina, and others by other makers). It speaks in the updater's framing (F0, [0, 89, command,
/// length (3 bytes), body…, checksum] packed 7 bits at a time, F7), as documented in device/mirror.c of
/// github.com/charlesvestal/fm1-base. Our own decoder of what that file describes (as the Mac app's src/fm1base.rs):
/// we send command 0x50 with one byte (2 on and the whole screen again, 1 keep on, at least every 6 s; 0 off); it
/// answers 0x50 (hello), then sends 0x51 rectangles (x, y, w, h, seq, then a pixel code with a 64-colour cache) and
/// 0x52 fills (x, y, w, h, seq, colour high, low).
enum Fm1Base {
    enum Got { case nothing, hello, painted }

    private static let request = UInt8(0x50), rectangle = UInt8(0x51), fill = UInt8(0x52)

    /// Asks for the screen: 2 on with the whole screen again, 1 keep on, 0 off.
    static func ask(_ what: UInt8) -> [UInt8] { frame(request, [what]) }

    /// One message from the FM-1, into the pixels (RGB565, 240 x 240, row by row).
    static func apply(_ pixels: inout [UInt16], _ m: [UInt8]) -> Got {
        guard let (command, body) = parse(m) else { return .nothing }
        switch command {
        case request: return .hello
        case rectangle: return rect(&pixels, body) ? .painted : .nothing
        case fill: return fillRect(&pixels, body) ? .painted : .nothing
        default: return .nothing
        }
    }

    static func frame(_ command: UInt8, _ body: [UInt8]) -> [UInt8] {
        let n = body.count
        var raw: [UInt8] = [0, 89, command, UInt8(n & 255), UInt8(n >> 8 & 255), 0] + body
        raw.append(~body.reduce(UInt8(0), &+))
        var out: [UInt8] = [0xF0]
        var value: UInt32 = 0, bits: UInt32 = 0
        for b in raw {
            value |= UInt32(b) << bits
            bits += 8
            while bits >= 7 { out.append(UInt8(value & 127)); value >>= 7; bits -= 7 }
        }
        if bits > 0 { out.append(UInt8(value & 127)) }
        out.append(0xF7)
        return out
    }

    private static func parse(_ m: [UInt8]) -> (UInt8, [UInt8])? {
        guard m.count >= 10, m.first == 0xF0, m.last == 0xF7 else { return nil }
        var raw: [UInt8] = []
        raw.reserveCapacity(m.count)
        var value: UInt32 = 0, bits: UInt32 = 0
        for b in m[1..<(m.count - 1)] {
            guard b < 128 else { return nil }
            value |= UInt32(b) << bits
            bits += 7
            while bits >= 8 { raw.append(UInt8(value & 255)); value >>= 8; bits -= 8 }
        }
        guard raw.count >= 7, raw[0] == 0, raw[1] == 89 else { return nil }
        let n = Int(raw[3]) | Int(raw[4]) << 8 | Int(raw[5]) << 16
        guard n + 7 <= raw.count, raw[6..<(7 + n)].reduce(UInt8(0), &+) == 255 else { return nil }
        return (raw[2], Array(raw[6..<(6 + n)]))
    }

    private static func side(_ b: UInt8) -> Int { b == 0 ? 256 : Int(b) }
    private static func hash(_ c: UInt16) -> Int { Int((UInt32(c) &* 40503) >> 10 & 63) }

    private static func rect(_ px: inout [UInt16], _ b: [UInt8]) -> Bool {
        guard b.count >= 5 else { return false }
        let x = Int(b[0]), y = Int(b[1]), w = side(b[2]), h = side(b[3]), size = Codec.size
        guard x + w <= size, y + h <= size else { return false }
        let total = w * h
        var p = 0, i = 5, now: UInt16 = 0
        var cache = [UInt16](repeating: 0, count: 64)
        while i < b.count {
            let op = b[i]
            i += 1
            var count = 1
            if op < 0x80 {
                count = Int(op) + 1
            } else if op < 0xC0 {
                now = cache[Int(op & 63)]
            } else {
                guard i + 2 <= b.count else { return false }
                now = UInt16(b[i]) << 8 | UInt16(b[i + 1])
                i += 2
                cache[hash(now)] = now
                count = Int(op & 63) + 1
            }
            guard p + count <= total else { return false }
            for _ in 0..<count {
                px[(y + p / w) * size + x + p % w] = now
                p += 1
            }
        }
        return p == total
    }

    private static func fillRect(_ px: inout [UInt16], _ b: [UInt8]) -> Bool {
        guard b.count >= 7 else { return false }
        let x = Int(b[0]), y = Int(b[1]), w = side(b[2]), h = side(b[3]), size = Codec.size
        let colour = UInt16(b[5]) << 8 | UInt16(b[6])
        for row in y..<min(size, y + h) {
            for col in x..<min(size, x + w) { px[row * size + col] = colour }
        }
        return true
    }
}
