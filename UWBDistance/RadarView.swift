import SwiftUI

extension DotStatus {
    var color: Color {
        switch self {
        case .ranging: return .green
        case .stale, .searching: return .yellow
        case .lost: return .red
        case .disconnected: return .gray
        }
    }
}

struct RadarView: View {
    @ObservedObject var service: NearbyService
    @State private var showDiagnostics = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Canvas { ctx, size in draw(ctx, size) }
                .background(Color(.systemBackground))
                .ignoresSafeArea(edges: .top)
            controls
        }
        .sheet(isPresented: $showDiagnostics) { DiagnosticsView(service: service) }
    }

    private var controls: some View {
        VStack(spacing: 6) {
        Text("Up = the way your phone points").font(.caption2).foregroundColor(.secondary)
        HStack(spacing: 12) {
            Button("Lobby") { service.showRadar = false }
            Button("Diagnostics") { showDiagnostics = true }
            if service.isRecording {
                Button("Stop rec", role: .destructive) { service.stopRecording() }
            } else {
                Button("Record") { service.startRecording() }
            }
            if let url = service.recordingURL, !service.isRecording {
                ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
            }
        }
        }
        .buttonStyle(.bordered)
        .padding()
        .background(.ultraThinMaterial)
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let now = Date()
        let pos = service.positions
        let maxR = max(1, pos.values.map { Double(hypot($0.x, $0.y)) }.max() ?? 1)
        let scale = min(size.width, size.height) / 2 * 0.72 / maxR
        let center = CGPoint(x: size.width / 2, y: size.height / 2 - 30)
        func screen(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x * scale, y: center.y + p.y * scale) }

        // range rings
        let step = niceStep(maxR)
        var r = step
        while r <= maxR + step {
            let rect = CGRect(x: center.x - r * scale, y: center.y - r * scale, width: 2 * r * scale, height: 2 * r * scale)
            ctx.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.25)), lineWidth: 1)
            ctx.draw(Text("\(Int(r)) m").font(.caption2).foregroundColor(.secondary),
                     at: CGPoint(x: center.x, y: center.y - r * scale - 6))
            r += step
        }

        // edges + distance labels
        for e in service.edges {
            guard let a = pos[e.a], let b = pos[e.b] else { continue }
            let pa = screen(a), pb = screen(b)
            let mine = e.a == service.myID || e.b == service.myID
            var path = Path(); path.move(to: pa); path.addLine(to: pb)
            ctx.stroke(path, with: .color(mine ? .accentColor.opacity(0.7) : .secondary.opacity(0.5)),
                       lineWidth: mine ? 2 : 1)
            ctx.draw(Text(String(format: "%.2f m", e.distance)).font(.caption2.monospacedDigit()).foregroundColor(.primary),
                     at: CGPoint(x: (pa.x + pb.x) / 2, y: (pa.y + pb.y) / 2))
        }

        // dots
        for (id, p) in pos {
            let pt = screen(p)
            let isMe = id == service.myID
            let status = service.peers.first { $0.id == id }?.dotStatus(now: now)
            let color: Color = isMe ? .accentColor : (status?.color ?? .gray)
            let rad: CGFloat = isMe ? 13 : 11
            ctx.fill(Path(ellipseIn: CGRect(x: pt.x - rad, y: pt.y - rad, width: 2 * rad, height: 2 * rad)), with: .color(color))
            ctx.draw(Text(isMe ? "You" : id.playerShortName).font(.caption.bold()).foregroundColor(.primary),
                     at: CGPoint(x: pt.x, y: pt.y + rad + 10))
        }
    }

    private func niceStep(_ maxR: Double) -> Double {
        let target = maxR / 3
        for s in [1.0, 2, 5, 10, 20, 50] where s >= target { return s }
        return 100
    }
}
