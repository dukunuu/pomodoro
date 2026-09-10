import AppKit
import Foundation

/// The end-of-phase chime, synthesised rather than shipped as an asset.
///
/// A kitchen timer's bell is a struck tone: a fundamental with a couple of
/// slightly inharmonic partials over an exponential decay. Two are built from
/// that here, so the two announcements are told apart without looking at the
/// screen — a falling pair when focus is over and it is time to stop, a rising
/// triad when a break is over and it is time to start again. The same two
/// figures are synthesised on Windows, from the same numbers.
@MainActor
enum Chime {
    private static let rate = 44_100.0

    private static let focusOver = render([
        Note(start: 0.00, frequency: 880.00, length: 0.90, gain: 0.85),   // A5
        Note(start: 0.17, frequency: 587.33, length: 1.35, gain: 1.00)    // D5, falling
    ])

    private static let breakOver = render([
        Note(start: 0.00, frequency: 659.25, length: 0.45, gain: 0.75),   // E5
        Note(start: 0.12, frequency: 880.00, length: 0.45, gain: 0.85),   // A5
        Note(start: 0.24, frequency: 1046.50, length: 0.85, gain: 1.00)   // C6, rising
    ])

    /// An NSSound stops when it is released, so the one playing is held.
    private static var playing: NSSound?

    static func play(finished: Phase) {
        guard let sound = NSSound(data: finished == .focus ? focusOver : breakOver) else {
            NSSound.beep()
            return
        }
        playing?.stop()
        playing = sound
        sound.play()
    }

    private struct Note {
        let start: Double
        let frequency: Double
        let length: Double
        let gain: Double
    }

    private static func render(_ notes: [Note]) -> Data {
        let frames = Int((notes.map { $0.start + $0.length }.max() ?? 0) * rate)
        var samples = [Double](repeating: 0, count: frames)

        for note in notes {
            let start = Int(note.start * rate)
            let length = Int(note.length * rate)
            guard length > 0 else { continue }
            for index in 0..<length where start + index < frames {
                let t = Double(index) / rate
                // Decay to near silence by the end of the note, with a 4 ms
                // attack so the strike does not click.
                let envelope = exp(-3.4 * t / note.length) * min(1, t / 0.004)
                let w = 2 * Double.pi * note.frequency * t
                let tone = sin(w) + 0.42 * sin(2.01 * w) + 0.17 * sin(3.02 * w)
                samples[start + index] += note.gain * envelope * tone / 1.59
            }
        }

        let peak = samples.map { abs($0) }.max() ?? 0
        let scale = peak > 0 ? 0.72 * Double(Int16.max) / peak : 0

        var wave = Data()
        wave.reserveCapacity(44 + frames * 2)
        func tag(_ text: String) { wave.append(contentsOf: Array(text.utf8)) }
        func word(_ value: Int32) {
            withUnsafeBytes(of: value.littleEndian) { wave.append(contentsOf: $0) }
        }
        func half(_ value: Int16) {
            withUnsafeBytes(of: value.littleEndian) { wave.append(contentsOf: $0) }
        }

        tag("RIFF"); word(Int32(36 + frames * 2)); tag("WAVE")
        tag("fmt "); word(16); half(1); half(1)               // PCM, mono
        word(Int32(rate)); word(Int32(rate) * 2); half(2); half(16)  // 16-bit
        tag("data"); word(Int32(frames * 2))
        for sample in samples {
            half(Int16(max(Double(Int16.min), min(Double(Int16.max), (sample * scale).rounded()))))
        }
        return wave
    }
}
