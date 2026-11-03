import AppKit
import SwiftUI

/// The app icon: one hand-drawn AirPod mid-flick and the arc of its swipe, on macOS's 1024-point grid
/// (824-point squircle). Few, heavy shapes so it still reads at 16 px.
struct AppIconArt: View {
    // Pivot at the bottom of the stem; the bud swings clockwise about it.
    static let pivot = CGPoint(x: 470, y: 780)
    static let tilt = -12.0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 186, style: .continuous)
                .fill(LinearGradient(colors: [Color(hex: 0x5B4FF0), Color(hex: 0x8B3FE6)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: 186, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.16), .clear], startPoint: .top, endPoint: .center)))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.28), radius: 18, y: 12)
            ZStack {
                SwipeArrow().fill(.white.opacity(0.9))
                ZStack {
                    AirPodShape().fill(.white)
                        .shadow(color: Color(hex: 0x2A1470).opacity(0.35), radius: 18, y: 10)
                    EarTip().fill(Color(hex: 0x6D4AEA).opacity(0.5))
                }
                .rotationEffect(.degrees(Self.tilt), anchor: UnitPoint(x: Self.pivot.x / 1024, y: Self.pivot.y / 1024))
            }
            .offset(x: -62, y: -36)
        }
        .frame(width: 1024, height: 1024)
    }
}

/// Bud head plus stem, upright, in 1024-point icon space.
private struct AirPodShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.addEllipse(in: CGRect(x: 312, y: 330, width: 262, height: 248))
        p.addRoundedRect(in: CGRect(x: 418, y: 480, width: 104, height: 312), cornerSize: CGSize(width: 52, height: 52))
        return p
    }
}

private struct EarTip: Shape {
    func path(in rect: CGRect) -> Path {
        Path(ellipseIn: CGRect(x: 326, y: 386, width: 100, height: 124))
    }
}

/// A thick arc concentric with the pivot, sweeping clockwise past the bud, ending in an arrowhead.
private struct SwipeArrow: Shape {
    func path(in rect: CGRect) -> Path {
        let c = AppIconArt.pivot
        let radius = 440.0, width = 56.0
        let start = -74.0, end = -36.0
        var arc = Path()
        arc.addArc(center: c, radius: radius, startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        var p = arc.strokedPath(StrokeStyle(lineWidth: width, lineCap: .round))
        // Arrowhead centred on the arc's end, pointing along its clockwise tangent.
        let a = end * .pi / 180
        let endPoint = CGPoint(x: c.x + radius * cos(a), y: c.y + radius * sin(a))
        let t = CGPoint(x: -sin(a), y: cos(a)), n = CGPoint(x: cos(a), y: sin(a))
        let half = 70.0, length = 96.0
        var head = Path()
        head.move(to: CGPoint(x: endPoint.x + t.x * length, y: endPoint.y + t.y * length))
        head.addLine(to: CGPoint(x: endPoint.x + n.x * half - t.x * 6, y: endPoint.y + n.y * half - t.y * 6))
        head.addLine(to: CGPoint(x: endPoint.x - n.x * half - t.x * 6, y: endPoint.y - n.y * half - t.y * 6))
        head.closeSubpath()
        p.addPath(head.strokedPath(StrokeStyle(lineWidth: 24, lineJoin: .round)))
        p.addPath(head)
        return p
    }
}

/// Developer tool: `AirAnki --render-assets <dir>` writes the icon set and preview frames, then exits.
@MainActor
enum AssetRenderer {
    static func run(_ directory: String) -> Int32 {
        let root = URL(fileURLWithPath: directory, isDirectory: true)
        let iconset = root.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
            for (points, scales) in [(16, [1, 2]), (32, [1, 2]), (128, [1, 2]), (256, [1, 2]), (512, [1, 2])] {
                for scale in scales {
                    let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
                    try write(AppIconArt().scaleEffect(CGFloat(points * scale) / 1024)
                        .frame(width: CGFloat(points * scale), height: CGFloat(points * scale)),
                              to: iconset.appendingPathComponent(name), scale: 1)
                }
            }
            try write(AppIconArt(), to: root.appendingPathComponent("icon-1024.png"), scale: 1)
            let sizes = HStack(alignment: .center, spacing: 18) {
                ForEach([256, 128, 64, 32, 16], id: \.self) { side in
                    AppIconArt().scaleEffect(CGFloat(side) / 1024).frame(width: CGFloat(side), height: CGFloat(side))
                }
            }.padding(20)
            try write(VStack(spacing: 0) { sizes.background(Color.white); sizes.background(Color(hex: 0x1E1E1E)) },
                      to: root.appendingPathComponent("icon-sizes.png"), scale: 1)
            for t in stride(from: 0.0, to: DemoScript.period, by: 0.2) {
                let view = DemoFrameView(frame: DemoScript.frame(at: t)).padding(20).frame(width: 560, height: 280)
                    .background(Color(nsColor: .windowBackgroundColor))
                try write(view, to: root.appendingPathComponent(String(format: "demo-%05.2f.png", t)), scale: 1)
            }
            let times = [1.0, 1.4, 3.0, 3.45, 5.1, 6.65, 7.0, 8.62, 9.05, 10.2]
            let sheet = LazyVGrid(columns: [GridItem(.fixed(540)), GridItem(.fixed(540))], spacing: 0) {
                ForEach(times, id: \.self) { t in
                    DemoFrameView(frame: DemoScript.frame(at: t)).frame(width: 540, height: 260)
                        .overlay(alignment: .topLeading) { Text(String(format: "t=%.2f", t)).font(.caption).padding(6) }
                }
            }.background(Color(nsColor: .windowBackgroundColor))
            try write(sheet, to: root.appendingPathComponent("demo-sheet.png"), scale: 1)
            try write(PreviewSheet().environment(\.colorScheme, .light), to: root.appendingPathComponent("sheet-light.png"), scale: 2)
            try write(PreviewSheet().environment(\.colorScheme, .dark), to: root.appendingPathComponent("sheet-dark.png"), scale: 2)
            print("Rendered assets into \(root.path)")
            return 0
        } catch {
            fputs("Render failed: \(error)\n", stderr)
            return 1
        }
    }

    static func write<V: View>(_ view: V, to url: URL, scale: CGFloat) throws {
        let renderer = ImageRenderer(content: view)
        renderer.scale = scale
        guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}

/// Static frames of every figure for visual review.
private struct PreviewSheet: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 10) {
                ForEach([ActionStyle.again, .easy, .undo, .reveal, .unclear], id: \.self) { style in
                    VStack {
                        ForEach([0.1, 0.25, 0.5, 0.8], id: \.self) { p in PopBadge(style: style, progress: p) }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach([0.0, 0.06, 0.11, 0.18, 0.26, 0.36], id: \.self) { s in
                    let m = Motion.flick(s, direction: 1)
                    PodFigure(tilt: m.tilt, streak: m.streak, size: 60).frame(width: 100, height: 90)
                }
            }
            HStack(spacing: 6) {
                ForEach([0.0, 0.07, 0.15, 0.22, 0.3, 0.45], id: \.self) { s in
                    PodFigure(twist: Motion.twist(s), size: 60).frame(width: 100, height: 90)
                }
            }
        }
        .padding(24)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}
