import CoreAudioKit
import SwiftUI

@main
struct FM1MirrorApp: App {
    @StateObject private var mirror = Mirror()


    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mirror)
                .preferredColorScheme(.dark)
                .statusBarHidden()
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var mirror: Mirror
    @AppStorage("spyglass") private var spyglassOn = true
    @State private var bluetooth = false

    var body: some View {
        GeometryReader { g in
            let wide = g.size.width > g.size.height
            VStack(spacing: 0) {
                Group {
                    if wide {
                        HStack(spacing: 12) { screen; if spyglassOn { glass } }
                    } else {
                        VStack(spacing: 12) { screen; if spyglassOn { glass } }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                bar
            }
            .background(Color.black.ignoresSafeArea())
        }
        .sheet(isPresented: $bluetooth) { BluetoothPicker().ignoresSafeArea() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true      // a screen to look at: don't dim it
            #if DEBUG
            Demo.start(mirror)
            #endif
        }
    }

    // ---- the FM-1's screen, or what to do

    @ViewBuilder private var screen: some View {
        ZStack {
            Color.black
            if let image = mirror.image, case .showing = mirror.state {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(mirror.smooth ? .high : .none)
                    .aspectRatio(1, contentMode: .fit)
            } else {
                panel
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .layoutPriority(1)
    }

    @ViewBuilder private var panel: some View {
        VStack(spacing: 14) {
            switch mirror.state {
            case .noFm1:
                Text("No FM-1 yet").font(.title.bold()).foregroundColor(Spyglass.brassLight)
                Text("Plug the FM-1 in with its USB cable (an iPad with Lightning needs Apple's USB 3 Camera Adapter), or connect it over Bluetooth.")
                    .multilineTextAlignment(.center)
                Button { bluetooth = true } label: { Label("Bluetooth…", systemImage: "dot.radiowaves.left.and.right") }
                    .buttonStyle(.borderedProminent).tint(Spyglass.brass)
            case .waiting(let name):
                Text("FM-1 found").font(.title.bold()).foregroundColor(Spyglass.brassLight)
                Text("\(name)\(mirror.firmware.map { " · \($0)" } ?? "")").foregroundColor(.secondary)
                Text("It isn't sending its screen. That needs a Big Screen firmware on the FM-1 (see FM-1 Mirror's page on GitHub). The spyglass works with any firmware.")
                    .multilineTextAlignment(.center)
            case .showing:
                ProgressView()
            }
        }
        .foregroundColor(.white)
        .padding(28)
    }

    private var glass: some View {
        Spyglass(notes: mirror.shownNotes, chord: mirror.shownChord, velocity: mirror.shownVelocity, sound: mirror.sound)
            .aspectRatio(1, contentMode: .fit)
    }

    // ---- the bar

    private var bar: some View {
        HStack(spacing: 10) {
            Button { bluetooth = true } label: { Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right") }
            Menu {
                Picker("Look", selection: $mirror.lookName) {
                    ForEach(Codec.Look.allCases) { Text($0.rawValue).tag($0.rawValue) }
                }
            } label: { Label(mirror.look.rawValue, systemImage: "paintpalette") }
            Toggle(isOn: $mirror.smooth) { Text("Smooth") }.toggleStyle(.button)
            Toggle(isOn: $spyglassOn) { Text("Spyglass") }.toggleStyle(.button)
            Spacer(minLength: 4)
            Text(status).font(.footnote).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
        }
        .tint(Spyglass.brassLight)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(white: 0.11))
    }

    private var status: String {
        switch mirror.state {
        case .noFm1: return "No FM-1"
        case .waiting(let n), .showing(let n): return "FM-1: " + (mirror.firmware ?? n)
        }
    }
}

/// Apple's own Bluetooth MIDI page: find the FM-1 ("FM1 Community_BLE" and the like) and connect. Once connected it
/// is a MIDI device like the USB one, and the mirror finds it by itself.
struct BluetoothPicker: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UINavigationController {
        let central = CABTMIDICentralViewController()
        let nav = UINavigationController(rootViewController: central)
        central.navigationItem.rightBarButtonItem = UIBarButtonItem(systemItem: .done, primaryAction: UIAction { _ in
            nav.dismiss(animated: true)
        })
        return nav
    }

    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
}
