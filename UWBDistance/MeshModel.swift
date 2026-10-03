import Foundation

struct MeshEdge: Equatable {
    let a: String   // a < b
    let b: String
    let distance: Float
}

/// Pairwise distance matrix built from our own readings plus every peer's gossiped readings.
/// Receive time (not sender time) is used for freshness because phone clocks differ.
struct MeshModel {
    struct Reading { var distance: Float; var time: Date }
    private(set) var rows: [String: [String: Reading]] = [:]

    /// Replace everything `from` reported.
    mutating func update(from: String, distances: [String: Float], at time: Date) {
        rows[from] = distances.mapValues { Reading(distance: $0, time: time) }
    }

    mutating func remove(_ id: String) {
        rows[id] = nil
        for key in rows.keys { rows[key]?[id] = nil }
    }

    /// One edge per unordered pair. If both ends have a fresh reading we average them so both phones show the same number.
    func edges(now: Date, maxAge: TimeInterval) -> [MeshEdge] {
        var acc: [[String]: [Float]] = [:]
        for (from, row) in rows {
            for (to, r) in row where now.timeIntervalSince(r.time) <= maxAge && from != to {
                acc[[min(from, to), max(from, to)], default: []].append(r.distance)
            }
        }
        return acc.map { key, vals in MeshEdge(a: key[0], b: key[1], distance: vals.reduce(0, +) / Float(vals.count)) }
            .sorted { ($0.a, $0.b) < ($1.a, $1.b) }
    }
}
