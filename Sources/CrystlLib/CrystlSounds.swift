// CrystlSounds.swift — Programmatic 8-bit sound effects
//
// Generates retro game-style sounds in memory using raw PCM audio.
// No external sound files needed — sounds are synthesized on the fly.

import Cocoa
import AVFoundation

class CrystlSounds {
    static let shared = CrystlSounds()

    /// Available custom sounds (in addition to system sounds).
    static let customSoundNames = ["Coin", "Crystal", "Wand", "Level Up", "Sword"]

    private var cachedSounds: [String: NSSound] = [:]
    private let sampleRate: Double = 44100

    /// Play a sound by name. Handles both system and custom sounds.
    func play(_ name: String) {
        guard name != "None" else { return }

        // Check custom sounds first
        if CrystlSounds.customSoundNames.contains(name) {
            if cachedSounds[name] == nil {
                cachedSounds[name] = generateSound(name)
            }
            cachedSounds[name]?.play()
            return
        }

        // Fall back to system sound
        NSSound(named: NSSound.Name(name))?.play()
    }

    // MARK: - Sound Generation

    private func generateSound(_ name: String) -> NSSound? {
        let samples: [Float]
        switch name {
        case "Coin":       samples = coinSound()
        case "Crystal":    samples = crystalSound()
        case "Wand":   samples = powerUpSound()
        case "Level Up":   samples = levelUpSound()
        case "Sword":      samples = swordSound()
        default:           return nil
        }
        return soundFromSamples(samples)
    }

    /// Soft sine tone helper
    private func sineNote(_ t: Double, freq: Double) -> Double {
        sin(freq * t * .pi * 2) + sin(freq * 2 * t * .pi * 2) * 0.15
    }

    /// Smooth envelope: fade in, sustain, fade out
    private func smoothEnv(_ t: Double, attack: Double, duration: Double) -> Double {
        let fadeIn = min(1.0, t / attack)
        let fadeOut = max(0, 1.0 - t / duration)
        return fadeIn * fadeOut * fadeOut
    }

    /// Coin — soft two-tone chime with reverb
    private func coinSound() -> [Float] {
        let note1Len = 0.08
        let note2Len = 0.35
        let count1 = Int(sampleRate * note1Len)
        let count2 = Int(sampleRate * note2Len)
        var samples = [Float](repeating: 0, count: count1 + count2)

        for i in 0..<count1 {
            let t = Double(i) / sampleRate
            let env = smoothEnv(t, attack: 0.005, duration: note1Len)
            samples[i] = Float(sineNote(t, freq: 988) * env * 0.2)
        }
        for i in 0..<count2 {
            let t = Double(i) / sampleRate
            let env = smoothEnv(t, attack: 0.005, duration: note2Len)
            samples[count1 + i] = Float(sineNote(t, freq: 1319) * env * 0.2)
        }

        addReverb(&samples)
        return samples
    }

    /// Crystal — magical shimmering cascade with reverb tail
    private func crystalSound() -> [Float] {
        let totalDuration = 1.2
        let count = Int(sampleRate * totalDuration)
        var samples = [Float](repeating: 0, count: count)

        // Ascending sparkle notes — like wind chimes
        let notes: [Double] = [1047, 1319, 1568, 2093, 2637, 3136] // C6, E6, G6, C7, E7, G7
        for (n, freq) in notes.enumerated() {
            let start = Int(Double(n) * 0.08 * sampleRate)
            let ringLen = 0.6 - Double(n) * 0.05 // higher notes ring shorter
            let len = Int(ringLen * sampleRate)
            for i in 0..<len where start + i < count {
                let t = Double(i) / sampleRate
                let env = smoothEnv(t, attack: 0.003, duration: ringLen)
                // Detuned pair for shimmer
                let tone1 = sin(freq * t * .pi * 2)
                let tone2 = sin((freq * 1.003) * t * .pi * 2) // slightly detuned = shimmer
                let octave = sin((freq * 2) * t * .pi * 2) * 0.15
                let shimmer = (tone1 + tone2) * 0.5 + octave
                samples[start + i] += Float(shimmer * env * 0.1)
            }
        }

        addReverb(&samples, tailSeconds: 0.4)
        return samples
    }

    /// Power up — gentle rising tone
    private func powerUpSound() -> [Float] {
        let duration = 0.45
        let count = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: count)

        for i in 0..<count {
            let t = Double(i) / sampleRate
            let progress = t / duration
            let freq = 300 + progress * progress * 1200
            let env = smoothEnv(t, attack: 0.02, duration: duration) * 0.18
            samples[i] = Float(sin(freq * t * .pi * 2) * env)
        }
        addReverb(&samples)
        return samples
    }

    /// Level up — soft ascending chime
    private func levelUpSound() -> [Float] {
        let notes: [Double] = [523, 659, 784, 1047]
        let noteLen = 0.15
        let totalDuration = 0.12 * Double(notes.count) + noteLen + 0.1
        let count = Int(sampleRate * totalDuration)
        var samples = [Float](repeating: 0, count: count)

        for (n, freq) in notes.enumerated() {
            let start = Int(Double(n) * 0.12 * sampleRate)
            let len = Int((noteLen + 0.1) * sampleRate)
            for i in 0..<len where start + i < count {
                let t = Double(i) / sampleRate
                let env = smoothEnv(t, attack: 0.008, duration: noteLen + 0.1) * 0.15
                samples[start + i] += Float(sineNote(t, freq: freq) * env)
            }
        }
        addReverb(&samples)
        return samples
    }

    /// Sword — whoosh then clank
    private func swordSound() -> [Float] {
        let duration = 0.5
        let count = Int(sampleRate * duration)
        var samples = [Float](repeating: 0, count: count)
        var rng: UInt64 = 98765

        // Pre-generate noise buffer
        var noise = [Float](repeating: 0, count: count)
        for i in 0..<count {
            rng = rng &* 6364136223846793005 &+ 1442695040888963407
            noise[i] = Float(Double(Int64(bitPattern: rng)) / Double(Int64.max))
        }

        // Smooth the noise (multiple passes for softer whoosh)
        for _ in 0..<3 {
            for i in 1..<count {
                noise[i] = noise[i] * 0.3 + noise[i - 1] * 0.7
            }
        }

        let clankTime = 0.15 // when the clank hits

        for i in 0..<count {
            let t = Double(i) / sampleRate

            // ── Whoosh: noise builds up then cuts at clank ──
            let whooshEnv: Double
            if t < clankTime {
                whooshEnv = pow(t / clankTime, 1.5) * 0.25
            } else {
                whooshEnv = max(0, 1.0 - (t - clankTime) / 0.05) * 0.1 // quick cutoff
            }
            samples[i] += noise[i] * Float(whooshEnv)

            // ── Clank: metallic impact ──
            let ct = t - clankTime
            if ct > 0 {
                // Crash — big noise burst layered under the metal
                let crash = Double(noise[i]) * exp(-ct * 15) * 0.6

                // High-frequency metallic partials — detuned pairs for shimmer
                let m1 = sin(1870 * ct * .pi * 2) + sin(1890 * ct * .pi * 2)
                let m2 = sin(2950 * ct * .pi * 2) + sin(2980 * ct * .pi * 2)
                let m3 = sin(4700 * ct * .pi * 2) + sin(4750 * ct * .pi * 2)
                let m4 = sin(6300 * ct * .pi * 2) * 0.5

                // Metal ring decays slower than crash
                let metalEnv = exp(-ct * 18) * 0.15
                let metal = m1 * 0.4 + m2 * 0.3 + m3 * 0.2 + m4

                samples[i] += Float(crash + metal * metalEnv)
            }
        }

        // No reverb on sword — clanks are dry
        return samples
    }

    // MARK: - Helpers

    /// Multi-tap reverb applied to any sample buffer
    private func addReverb(_ samples: inout [Float], tailSeconds: Double = 0.25) {
        let tailFrames = Int(tailSeconds * sampleRate)
        let oldCount = samples.count
        samples.append(contentsOf: [Float](repeating: 0, count: tailFrames))

        let taps: [(delay: Double, gain: Float)] = [
            (0.06, 0.3), (0.11, 0.2), (0.18, 0.12), (0.27, 0.07)
        ]
        for tap in taps {
            let delayFrames = Int(tap.delay * sampleRate)
            for i in delayFrames..<samples.count {
                samples[i] += samples[i - delayFrames] * tap.gain
            }
        }
    }

    private func squareWave(_ t: Double, freq: Double) -> Double {
        let phase = t * freq
        return (phase - floor(phase)) < 0.5 ? 1.0 : -1.0
    }

    /// Convert raw Float samples to an NSSound via WAV data
    private func soundFromSamples(_ samples: [Float]) -> NSSound? {
        let bitsPerSample: UInt16 = 16
        let numChannels: UInt16 = 1
        let byteRate = UInt32(sampleRate) * UInt32(numChannels) * UInt32(bitsPerSample / 8)
        let blockAlign = numChannels * (bitsPerSample / 8)
        let dataSize = UInt32(samples.count * 2) // 16-bit = 2 bytes per sample

        var data = Data()

        // RIFF header
        data.append(contentsOf: "RIFF".utf8)
        data.append(uint32LE: 36 + dataSize)
        data.append(contentsOf: "WAVE".utf8)

        // fmt chunk
        data.append(contentsOf: "fmt ".utf8)
        data.append(uint32LE: 16) // chunk size
        data.append(uint16LE: 1)  // PCM
        data.append(uint16LE: numChannels)
        data.append(uint32LE: UInt32(sampleRate))
        data.append(uint32LE: byteRate)
        data.append(uint16LE: blockAlign)
        data.append(uint16LE: bitsPerSample)

        // data chunk
        data.append(contentsOf: "data".utf8)
        data.append(uint32LE: dataSize)

        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
            let int16 = Int16(clamped * 32767)
            data.append(uint16LE: UInt16(bitPattern: int16))
        }

        return NSSound(data: data)
    }
}

// MARK: - Data Helpers

private extension Data {
    mutating func append(uint16LE value: UInt16) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }

    mutating func append(uint32LE value: UInt32) {
        var v = value.littleEndian
        append(UnsafeBufferPointer(start: &v, count: 1))
    }
}
