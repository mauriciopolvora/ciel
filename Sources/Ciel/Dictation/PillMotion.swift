import CoreText
import Foundation

struct Spring: Equatable {
    private(set) var value: Double
    private(set) var velocity = 0.0
    var target: Double
    var response: Double

    init(_ value: Double, response: Double) {
        self.value = value
        target = value
        self.response = response
    }

    var isSettled: Bool { value == target && velocity == 0 }

    mutating func snap(to value: Double) {
        self.value = value
        target = value
        velocity = 0
    }

    mutating func shift(by delta: Double) { value += delta }

    mutating func advance(by seconds: Double) {
        guard !isSettled else { return }
        let frequency = 2 * Double.pi / response
        var remaining = seconds
        while remaining > 0 {
            let step = min(remaining, Self.step)
            velocity += (frequency * frequency * (target - value) - 2 * frequency * velocity) * step
            value += velocity * step
            remaining -= step
        }
        if abs(target - value) < Self.precision, abs(velocity) < Self.precision * 10 { snap(to: target) }
    }

    private static let step = 1.0 / 240
    private static let precision = 0.002
}

struct LevelMeter: Equatable {
    private var queue: [Slice] = []
    private var input = 0.0
    private(set) var level = 0.0

    static let attack = 0.03
    static let release = 0.2
    static let latency = 0.15

    mutating func hear(_ rms: [Float], every interval: Double) {
        queue += rms.map { Slice(level: Self.loudness($0), duration: interval) }
        var queued = queue.reduce(0) { $0 + $1.duration }
        while queued > Self.latency, queue.count > 1 { queued -= queue.removeFirst().duration }
    }

    mutating func advance(by seconds: Double) {
        var remaining = seconds
        while remaining > 0 {
            var used = remaining
            if !queue.isEmpty {
                input = queue[0].level
                used = min(remaining, queue[0].duration)
                queue[0].duration -= used
                if queue[0].duration <= 0 { queue.removeFirst() }
            }
            let time = input > level ? Self.attack : Self.release
            level += (input - level) * (1 - exp(-used / time))
            remaining -= used
        }
    }

    private static let quietestDecibels = -50.0
    private static let loudestDecibels = -10.0

    static func loudness(_ rms: Float) -> Double {
        let decibels = 20 * log10(max(Double(rms), 0.000_01))
        let span = loudestDecibels - quietestDecibels
        return min(max((decibels - quietestDecibels) / span, 0), 1)
    }

    private struct Slice: Equatable {
        let level: Double
        var duration: Double
    }
}

struct Waveform: Equatable {
    static let bars = 15
    static let period = 1.0 / 24
    private static let half = bars / 2
    private var history = [Double](repeating: 0, count: half + 2)
    private var since = 0.0
    private var current = 0.0

    mutating func advance(by seconds: Double, level: Double) {
        current = level
        since += seconds
        while since >= Self.period {
            since -= Self.period
            history.insert(level, at: 0)
            history.removeLast()
        }
    }

    func amplitudes(flowing: Bool) -> [Double] {
        let side = (0...Self.half).map { distance in
            Self.weight(distance) * (flowing ? level(age: Double(distance) * Self.period) : current)
        }
        return side.reversed() + side.dropFirst()
    }

    static func ripple(at time: Double) -> [Double] {
        let side = (0...half).map { distance in
            weight(distance) * 0.2 * (0.5 + 0.5 * sin(2 * .pi * time / 1.1 - Double(distance) * 0.7))
        }
        return side.reversed() + side.dropFirst()
    }

    private func level(age: Double) -> Double {
        if age == 0 { return current }
        if age <= since { return current + (history[0] - current) * age / since }
        let position = (age - since) / Self.period
        let index = min(Int(position), history.count - 2)
        let fraction = position - Double(index)
        return history[index] * (1 - fraction) + history[index + 1] * fraction
    }

    private static func weight(_ distance: Int) -> Double {
        0.35 + 0.65 * cos(Double(distance) / Double(half) * .pi / 2)
    }
}

struct TranscriptLayout {
    static let lineHeight: CGFloat = 16
    let lines: [CTLine]
    let widths: [CGFloat]
    let width: CGFloat

    init(_ text: NSAttributedString = NSAttributedString(), maxWidth: CGFloat) {
        let typesetter = CTTypesetterCreateWithAttributedString(text)
        var lines: [CTLine] = []
        var start = 0
        while start < text.length {
            let count = max(CTTypesetterSuggestLineBreak(typesetter, start, Double(maxWidth)), 1)
            lines.append(CTTypesetterCreateLine(typesetter, CFRange(location: start, length: count)))
            start += count
        }
        self.lines = lines
        widths = lines.map { line in
            CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
        }
        width = ceil(widths.max() ?? 0)
    }

    var height: CGFloat { CGFloat(lines.count) * Self.lineHeight }

    static func start(of width: CGFloat, in space: CGFloat) -> CGFloat { (space - width) / 2 }
}

enum PillLayout {
    static let waveform = CGSize(width: 96, height: 32)
    static let gap: CGFloat = 8
    static let padding = CGSize(width: 14, height: 8)
    static let textWidth: CGFloat = 360
    static let maxLines = 3
    static let margin: CGFloat = 12
    static let radius: CGFloat = 16

    static var canvas: CGSize {
        CGSize(
            width: textWidth + 2 * padding.width + 2 * margin,
            height: 2 * margin + waveform.height + gap + transcript(lines: maxLines, width: textWidth).height)
    }

    static func transcript(_ layout: TranscriptLayout) -> CGSize {
        transcript(lines: layout.lines.count, width: layout.width)
    }

    private static func transcript(lines: Int, width: CGFloat) -> CGSize {
        CGSize(
            width: max(waveform.width, min(width, textWidth) + 2 * padding.width),
            height: CGFloat(min(max(lines, 1), maxLines)) * TranscriptLayout.lineHeight + 2 * padding.height)
    }
}
