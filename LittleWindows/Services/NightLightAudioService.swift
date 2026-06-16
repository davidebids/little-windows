import AVFoundation
import Foundation

@MainActor
final class NightLightAudioService: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var statusMessage: String?

    private var player: AVAudioPlayer?
    private var currentSound: NightLightSound = .none

    func play(_ sound: NightLightSound, volume: Double) {
        guard sound != .none else {
            stop()
            return
        }

        if sound == currentSound, let player, player.isPlaying {
            player.volume = Float(volume)
            return
        }

        stop(clearStatus: false)

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(
                .playback,
                mode: .default,
                options: [.mixWithOthers]
            )
            try session.setActive(true)

            let audioPlayer = try AVAudioPlayer(
                data: Self.generatedWAVData(for: sound)
            )
            audioPlayer.numberOfLoops = -1
            audioPlayer.volume = Float(volume)
            audioPlayer.prepareToPlay()

            guard audioPlayer.play() else {
                throw NightLightAudioError.playbackDidNotStart
            }

            player = audioPlayer
            currentSound = sound
            isPlaying = true
            statusMessage = nil
        } catch {
            stop(clearStatus: false)
            statusMessage = "Could not start ambient sound. Check the device volume and try again."
        }
    }

    func updateVolume(_ volume: Double) {
        player?.volume = Float(volume)
    }

    func stop() {
        stop(clearStatus: true)
    }

    nonisolated static func generatedWAVData(
        for sound: NightLightSound
    ) -> Data {
        let sampleRate = 44_100
        let durationSeconds = 14
        let sampleCount = sampleRate * durationSeconds
        var samples = [Double]()
        samples.reserveCapacity(sampleCount)

        var seed: UInt64 = 0x1234ABCD
        func noise() -> Double {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1
            return Double((seed >> 33) & 0xFFFF) / 32_767.5 - 1
        }
        func randomUnit() -> Double {
            (noise() + 1) / 2
        }

        var softLow = 0.0
        var wideLow = 0.0
        var rainMist = 0.0
        var rainRumble = 0.0
        var rainDropEnvelope = 0.0
        var oceanFoam = 0.0
        var oceanBody = 0.0
        var shushLow = 0.0
        var shushSilk = 0.0
        var fanAir = 0.0
        var fanBody = 0.0
        var flameBed = 0.0
        var flameFlutter = 0.0
        var emberEnvelope = 0.0
        var snapEnvelope = 0.0

        for frame in 0..<sampleCount {
            let time = Double(frame) / Double(sampleRate)
            let rawNoise = noise()
            let rawNoise2 = noise()

            softLow = softLow * 0.985 + rawNoise * 0.015
            wideLow = wideLow * 0.997 + rawNoise * 0.003
            let value: Double

            switch sound {
            case .whiteNoise:
                value = rawNoise * 0.20
            case .rain:
                rainMist = rainMist * 0.76 + rawNoise * 0.24
                rainRumble = rainRumble * 0.9988 + rawNoise2 * 0.0012
                if randomUnit() > 0.9987 {
                    rainDropEnvelope += 0.08 + pow(randomUnit(), 2) * 0.34
                }
                rainDropEnvelope *= 0.9982
                let tinyDrop = rainDropEnvelope * (rawNoise - rainMist) * 0.26
                let windowWash = rainMist * 0.11 + rainRumble * 0.24
                value = windowWash + tinyDrop
            case .lullaby:
                let notes = [261.63, 329.63, 392.0, 329.63, 293.66, 349.23, 293.66, 329.63]
                let note = notes[Int(time) % notes.count]
                let notePhase = time.truncatingRemainder(dividingBy: 1)
                let envelope = pow(sin(.pi * min(1, notePhase)), 1.5)
                let fundamental = sin(2 * .pi * note * time)
                let harmonic = sin(2 * .pi * note * 2 * time) * 0.18
                let bell = sin(2 * .pi * note * 0.5 * time) * 0.08
                value = (fundamental + harmonic + bell) * envelope * 0.12
            case .heartbeat:
                let beat = time.truncatingRemainder(dividingBy: 1.2)
                let pulse1 = exp(-pow((beat - 0.12) / 0.035, 2))
                let pulse2 = exp(-pow((beat - 0.30) / 0.045, 2)) * 0.72
                let thump = sin(2 * .pi * 48 * time) * 0.42
                    + sin(2 * .pi * 78 * time) * 0.10
                value = (pulse1 + pulse2) * thump
            case .ocean:
                oceanFoam = oceanFoam * 0.94 + rawNoise * 0.06
                oceanBody = oceanBody * 0.999 + rawNoise2 * 0.001
                let swell = 0.32 + 0.68 * pow((sin(2 * .pi * time / 8.5 - .pi / 2) + 1) / 2, 1.6)
                let retreat = 0.45 + 0.55 * pow((sin(2 * .pi * time / 13.0) + 1) / 2, 1.2)
                value = (oceanFoam * 0.22 + oceanBody * 0.55) * swell * retreat
            case .shushing:
                shushLow = shushLow * 0.90 + rawNoise * 0.10
                let sibilance = rawNoise - shushLow
                shushSilk = shushSilk * 0.46 + sibilance * 0.54
                let cycle = time.truncatingRemainder(dividingBy: 3.8) / 3.8
                let breath = 0.48 + 0.52 * pow(sin(.pi * cycle), 0.75)
                let humanVariation = 0.90 + 0.07 * sin(2 * .pi * time / 6.5)
                    + 0.03 * sin(2 * .pi * time / 1.9)
                value = shushSilk * breath * humanVariation * 0.15
            case .fan:
                fanAir = fanAir * 0.985 + rawNoise * 0.015
                fanBody = fanBody * 0.9992 + rawNoise2 * 0.0008
                let rotor = sin(2 * .pi * 88 * time) * 0.018
                    + sin(2 * .pi * 176 * time) * 0.006
                value = fanAir * 0.28 + fanBody * 0.42 + rotor
            case .fireplace:
                flameBed = flameBed * 0.996 + rawNoise * 0.004
                flameFlutter = flameFlutter * 0.985 + rawNoise2 * 0.015
                if randomUnit() > 0.99982 {
                    snapEnvelope += 0.35 + randomUnit() * 0.85
                }
                if randomUnit() > 0.99935 {
                    emberEnvelope += 0.08 + randomUnit() * 0.24
                }
                snapEnvelope *= 0.9955
                emberEnvelope *= 0.9991
                let warmFlame = flameBed * (0.42 + 0.18 * sin(2 * .pi * time / 2.7))
                    + flameFlutter * 0.08
                let ember = emberEnvelope * (softLow + wideLow) * 0.22
                let snap = snapEnvelope * (rawNoise - flameBed) * 0.16
                value = warmFlame * 0.42 + ember + snap
            case .none:
                value = 0
            }

            let clamped = max(-1, min(1, value))
            samples.append(clamped)
        }

        applyGentleLoopFade(to: &samples, sampleRate: sampleRate)
        return wavData(
            samples: samples.map { Int16(max(-1, min(1, $0)) * Double(Int16.max)) },
            sampleRate: sampleRate
        )
    }

    private func stop(clearStatus: Bool) {
        player?.stop()
        player = nil
        currentSound = .none
        isPlaying = false
        if clearStatus {
            statusMessage = nil
        }
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    nonisolated private static func wavData(
        samples: [Int16],
        sampleRate: Int
    ) -> Data {
        let bytesPerSample = 2
        let dataSize = samples.count * bytesPerSample
        var data = Data()
        data.reserveCapacity(44 + dataSize)
        data.append(contentsOf: "RIFF".utf8)
        append(UInt32(36 + dataSize), to: &data)
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        append(UInt32(16), to: &data)
        append(UInt16(1), to: &data)
        append(UInt16(1), to: &data)
        append(UInt32(sampleRate), to: &data)
        append(UInt32(sampleRate * bytesPerSample), to: &data)
        append(UInt16(bytesPerSample), to: &data)
        append(UInt16(16), to: &data)
        data.append(contentsOf: "data".utf8)
        append(UInt32(dataSize), to: &data)

        for sample in samples {
            append(UInt16(bitPattern: sample), to: &data)
        }
        return data
    }

    nonisolated private static func applyGentleLoopFade(
        to samples: inout [Double],
        sampleRate: Int
    ) {
        let fadeFrames = min(samples.count / 3, sampleRate / 2)
        guard fadeFrames > 0 else { return }
        for index in 0..<fadeFrames {
            let position = Double(index) / Double(fadeFrames)
            let fadeIn = 0.5 - 0.5 * cos(.pi * position)
            let fadeOut = 0.5 + 0.5 * cos(.pi * position)
            samples[index] *= fadeIn
            samples[samples.count - 1 - index] *= fadeOut
        }
    }

    nonisolated private static func append(
        _ value: UInt16,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) {
            data.append(contentsOf: $0)
        }
    }

    nonisolated private static func append(
        _ value: UInt32,
        to data: inout Data
    ) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) {
            data.append(contentsOf: $0)
        }
    }
}

private enum NightLightAudioError: Error {
    case playbackDidNotStart
}
