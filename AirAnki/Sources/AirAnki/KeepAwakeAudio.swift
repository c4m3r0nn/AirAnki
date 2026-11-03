import AirAnkiCore
import AVFoundation

/// Does not claim media commands or publish Now Playing metadata.
@MainActor
final class KeepAwakeAudio {
    var onError: ((String) -> Void)?
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var observer: NSObjectProtocol?
    private var wanted = false
    private var restarting = false

    func setActive(_ active: Bool) {
        guard active != wanted else { return }
        wanted = active
        if active {
            if observer == nil {
                observer = NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
                    object: engine, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async { self?.restart() }
                }
            }
            restart()
        } else {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            player.stop(); engine.stop()
        }
    }
    private func restart() {
        guard wanted, !restarting else { return }
        restarting = true
        defer { restarting = false }
        player.stop(); engine.stop()
        // Fixed source format is converted by the mixer to the current default output.
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000),
              let channels = buffer.floatChannelData else {
            onError?("Could not allocate keep-awake audio."); return
        }
        buffer.frameLength = buffer.frameCapacity
        // Uniform noise: RMS = peak / sqrt(3), approximately -75 dBFS RMS.
        let peak = Float(pow(10.0, -75.0 / 20.0) * sqrt(3.0))
        for channel in 0..<Int(format.channelCount) {
            for frame in 0..<Int(buffer.frameLength) { channels[channel][frame] = Float.random(in: -peak...peak) }
        }
        if player.engine == nil { engine.attach(player) }
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            engine.prepare()
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            player.stop(); engine.stop()
            onError?("Keep AirPods awake: \(error.localizedDescription)")
            // Keep the observer so a later output reconnect can recover.
        }
    }
}
