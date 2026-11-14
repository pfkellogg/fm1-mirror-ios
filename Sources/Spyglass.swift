import SwiftUI

/// The spyglass: a round brass eyepiece with the note or chord played, the notes on a grand staff, how hard the key
/// was hit, and the sound's name on top. The same drawing as the Android app's Glass.java and StaffView.java.
struct Spyglass: View {
    var notes: [Int]?
    var chord: String?
    var velocity: Int
    var sound: String?
    var idle = "play a note"

    static let brass = Color(red: 0xC9 / 255, green: 0x9A / 255, blue: 0x45 / 255)
    static let brassLight = Color(red: 0xF3 / 255, green: 0xD6 / 255, blue: 0x8A / 255)
    static let brassDark = Color(red: 0x8A / 255, green: 0x62 / 255, blue: 0x24 / 255)
    static let brassShadow = Color(red: 0x3E / 255, green: 0x2A / 255, blue: 0x0E / 255)
    static let soundGold = Color(red: 0xF7 / 255, green: 0xDC / 255, blue: 0x92 / 255)

    var body: some View {
        Canvas { c, size in
            let d = min(size.width, size.height), cx = size.width / 2, cy = size.height / 2
            lens(&c, cx, cy, d)
            // the staff, between the name and the details: as big as the glass allows (as on Android)
            let sw = d * 0.45, sh = sw * 1.06
            let staff = CGRect(x: cx - sw / 2, y: cy + d * 0.087 - sh / 2, width: sw, height: sh)
            Staff.draw(&c, notes ?? [], in: staff)
            if let sound, !sound.isEmpty { soundBand(&c, sound, cx, cy - d * 0.325, d) }
            let name: String, detail: String
            if let notes, !notes.isEmpty {
                if let chord {
                    name = chord
                    var s = notes.map(NoteNames.name).joined(separator: "  ")
                    if let i = Chord.interval(notes) { s += "   ·   " + i }
                    detail = s
                } else {
                    let n = notes[0]
                    name = NoteNames.pitchClass(n)
                    detail = String(format: "%@   %.1f Hz", NoteNames.name(n), NoteNames.hz(n))
                        + (velocity > 0 ? "   vel \(velocity)" : "")
                }
                label(&c, name, cx, cy - d * 0.215, chord != nil ? d * 0.10 : d * 0.115, d * 0.72, .white)
            } else {
                name = ""
                detail = idle
            }
            _ = name
            label(&c, detail, cx, cy + d * 0.365, max(12, d * 0.055), d * 0.54, .white)
            if chord == nil, notes?.isEmpty == false, velocity > 0 {
                let w = d * 0.26, h = max(3, d * 0.012), top = cy + d * 0.405 - h / 2
                c.fill(Path(roundedRect: CGRect(x: cx - w / 2, y: top, width: w, height: h), cornerRadius: h / 2),
                       with: .color(Spyglass.brassShadow))
                c.fill(Path(roundedRect: CGRect(x: cx - w / 2, y: top, width: w * CGFloat(velocity) / 127, height: h),
                            cornerRadius: h / 2), with: .color(Spyglass.brassLight))
            }
        }
    }

    /// Text centred on (x, y), smaller if it wouldn't fit in `room`.
    private func label(_ c: inout GraphicsContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat,
                       _ room: CGFloat, _ color: Color) {
        var t = c.resolve(Text(s).font(.system(size: size, weight: .semibold)).foregroundColor(color))
        let w = t.measure(in: CGSize(width: 10_000, height: 1_000)).width
        if w > room {
            t = c.resolve(Text(s).font(.system(size: size * room / w, weight: .semibold)).foregroundColor(color))
        }
        c.draw(t, at: CGPoint(x: x, y: y), anchor: .center)
    }

    /// The sound's name: warm gold letters on a band of dark smoked glass with a thin brass edge and a soft shine.
    private func soundBand(_ c: inout GraphicsContext, _ s: String, _ x: CGFloat, _ y: CGFloat, _ d: CGFloat) {
        let str = "♪  " + s
        var size = max(12, d * 0.06)
        let room = d * 0.5
        func text(_ color: Color) -> Text {
            Text(str).font(.system(size: size, weight: .semibold)).kerning(size * 0.06).foregroundColor(color)
        }
        var w = c.resolve(text(Spyglass.soundGold)).measure(in: CGSize(width: 10_000, height: 1_000)).width
        if w > room {
            size *= room / w
            w = c.resolve(text(Spyglass.soundGold)).measure(in: CGSize(width: 10_000, height: 1_000)).width
        }
        let h = size * 1.7, bw = w + size * 1.4
        let r = CGRect(x: x - bw / 2, y: y - h / 2, width: bw, height: h)
        c.fill(Path(roundedRect: r.offsetBy(dx: 0, dy: 2), cornerRadius: h / 2), with: .color(.black.opacity(0.35)))
        c.fill(Path(roundedRect: r, cornerRadius: h / 2), with: .color(Color(red: 16 / 255, green: 12 / 255, blue: 6 / 255).opacity(0.88)))
        let up = CGRect(x: r.minX + 2, y: r.minY + 2, width: r.width - 4, height: r.height / 2 - 2)
        c.fill(Path(roundedRect: up, cornerRadius: up.height / 2), with: .color(.white.opacity(0.07)))
        c.stroke(Path(roundedRect: r, cornerRadius: h / 2), with: .color(Spyglass.brassLight), lineWidth: 1.25)
        c.draw(text(.black.opacity(0.8)), at: CGPoint(x: x, y: y + 1), anchor: .center)
        c.draw(text(Spyglass.soundGold), at: CGPoint(x: x, y: y), anchor: .center)
    }

    /// A spyglass's eyepiece: dark glass and a knurled brass rim lit from the top left.
    private func lens(_ c: inout GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ d: CGFloat) {
        let rad = d / 2, rim = max(7, d * 0.05), gr = rad - rim
        func circle(_ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)) }
        let glass = Color(red: 0x0E / 255, green: 0x14 / 255, blue: 0x1A / 255)
        c.fill(circle(gr), with: .radialGradient(
            Gradient(stops: [.init(color: glass.opacity(0.78), location: 0), .init(color: glass.opacity(0.78), location: 0.7),
                             .init(color: Color(red: 4 / 255, green: 6 / 255, blue: 9 / 255).opacity(0.92), location: 1)]),
            center: CGPoint(x: cx, y: cy), startRadius: 0, endRadius: gr))
        // the brass rim: bands from dark to light and back, so it looks rounded
        let bands = [Spyglass.brassShadow, Spyglass.brassDark, Spyglass.brass, Spyglass.brassLight, Spyglass.brass, Spyglass.brassDark]
        let bw = rim / CGFloat(bands.count)
        for (i, col) in bands.enumerated() {
            c.stroke(circle(gr + bw * (CGFloat(i) + 0.5)), with: .color(col), lineWidth: bw + 0.6)
        }
        // light from the top left, shade at the bottom right
        func arc(_ r: CGFloat, _ from: Double, _ to: Double) -> Path {
            var p = Path()
            p.addArc(center: CGPoint(x: cx, y: cy), radius: r, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
            return p
        }
        c.stroke(arc(rad - rim * 0.45, 198, 288), with: .color(Color(red: 1, green: 240 / 255, blue: 200 / 255).opacity(0.27)),
                 lineWidth: rim * 0.35)
        c.stroke(arc(rad - rim * 0.5, 18, 108), with: .color(Color(red: 40 / 255, green: 25 / 255, blue: 5 / 255).opacity(0.35)),
                 lineWidth: rim * 0.5)
        // knurling on the outer edge
        let ticks = Int((rad * 2 * .pi) / max(5, d * 0.025))
        var knurl = Path()
        for k in 0..<ticks {
            let a = 2 * Double.pi * Double(k) / Double(ticks), dx = CGFloat(cos(a)), dy = CGFloat(sin(a))
            knurl.move(to: CGPoint(x: cx + dx * (rad - rim * 0.42), y: cy + dy * (rad - rim * 0.42)))
            knurl.addLine(to: CGPoint(x: cx + dx * (rad - 0.5), y: cy + dy * (rad - 0.5)))
        }
        c.stroke(knurl, with: .color(Color(red: 40 / 255, green: 25 / 255, blue: 5 / 255).opacity(0.5)), lineWidth: max(1, d * 0.004))
        c.stroke(circle(gr), with: .color(Spyglass.brassShadow), lineWidth: max(1, d * 0.004))
        c.stroke(circle(rad - 0.5), with: .color(Spyglass.brassShadow), lineWidth: 1)
    }
}

/// The notes on a grand staff (treble + bass clef) as whole notes, with ledger lines and sharps. Middle C and up on
/// the treble staff, B3 and down on the bass staff. Positions in staff spaces, scaled to fit.
enum Staff {
    private static let trebleBottom = 37   // E4
    private static let bassTop = 33        // A3
    private static let gap: CGFloat = 4
    private static let width: CGFloat = 11.2
    private static let noteX: CGFloat = 7.4
    private static let stepOf = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6]
    private static let sharp = [false, true, false, true, false, false, true, false, true, false, true, false]

    private static func step(_ n: Int) -> Int { 7 * (n / 12) + stepOf[n % 12] }
    private static func y(_ n: Int) -> CGFloat {
        n >= 60 ? CGFloat(trebleBottom - step(n)) / 2 : gap + CGFloat(bassTop - step(n)) / 2
    }

    static func draw(_ c: inout GraphicsContext, _ unsorted: [Int], in box: CGRect) {
        let notes = unsorted.sorted()
        var top: CGFloat = -6.5, bottom = gap + 6.5
        for n in notes { top = min(top, y(n) - 1); bottom = max(bottom, y(n) + 1) }
        let sp = min(box.height / (bottom - top), box.width / width)
        let ox = box.minX + (box.width - width * sp) / 2, oy = box.minY + (box.height - (bottom - top) * sp) / 2 - top * sp
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * sp, y: oy + y * sp) }
        func line(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ w: CGFloat, _ color: Color) {
            var p = Path(); p.move(to: pt(x0, y0)); p.addLine(to: pt(x1, y1))
            c.stroke(p, with: .color(color), lineWidth: max(1, w * sp))
        }
        func glyph(_ contours: [[Double]], _ x: CGFloat, _ y: CGFloat) {
            var p = Path()
            for pts in contours {
                p.move(to: pt(x + CGFloat(pts[0]), y + CGFloat(pts[1])))
                var i = 2
                while i + 1 < pts.count { p.addLine(to: pt(x + CGFloat(pts[i]), y + CGFloat(pts[i + 1]))); i += 2 }
                p.closeSubpath()
            }
            c.fill(p, with: .color(.white), style: FillStyle(eoFill: true))
        }
        let grey = Color(white: 170 / 255)
        for i in 0..<5 {
            line(0.2, -CGFloat(i), width - 0.2, -CGFloat(i), 0.12, grey)
            line(0.2, gap + CGFloat(i), width - 0.2, gap + CGFloat(i), 0.12, grey)
        }
        line(0.2, -4, 0.2, gap + 4, 0.16, grey)                  // the brace line joining the staves
        glyph(StaffGlyphs.gClef, 0.7, 0)
        glyph(StaffGlyphs.fClef, 0.7, gap + 4)

        let head = CGFloat(StaffGlyphs.wholeWidth)
        // a second (two neighbouring steps) can't share a column: the upper head moves right
        var right = [Bool](repeating: false, count: notes.count)
        for i in notes.indices.dropFirst() {
            right[i] = (notes[i] >= 60) == (notes[i - 1] >= 60) && step(notes[i]) - step(notes[i - 1]) == 1 && !right[i - 1]
        }
        let anyRight = right.contains(true)
        let ledgerFrom = noteX - 0.45, ledgerTo = noteX + head * (anyRight ? 2 : 1) + 0.45
        for n in notes {
            let ny = y(n), from: CGFloat = n >= 60 ? -4 : gap, to: CGFloat = n >= 60 ? 0 : gap + 4
            var l = from - 1
            while l >= ny - 0.01 { line(ledgerFrom, l, ledgerTo, l, 0.16, grey); l -= 1 }
            l = to + 1
            while l <= ny + 0.01 { line(ledgerFrom, l, ledgerTo, l, 0.16, grey); l += 1 }
        }
        // sharps, from the top down; one closer to its note than another would clash moves further left
        var placed: [(CGFloat, Int)] = []
        for i in notes.indices.reversed() where sharp[notes[i] % 12] {
            let ny = y(notes[i])
            var col = 0
            while placed.contains(where: { $0.1 == col && abs($0.0 - ny) < 3 }) { col += 1 }
            placed.append((ny, col))
            glyph(StaffGlyphs.sharp, noteX - 0.25 - CGFloat(StaffGlyphs.sharpWidth) / 2 - CGFloat(col), ny)
        }
        for i in notes.indices {
            glyph(StaffGlyphs.whole, noteX + head / 2 + (right[i] ? head : 0), y(notes[i]))
        }
    }
}
