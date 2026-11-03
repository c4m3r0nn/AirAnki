import AirAnkiCore
import AVFoundation
import MediaPlayer
import os

/// Silent playback + command routing adapted from MIT PodMouse; see notices.
@MainActor
final class StemInput {
    var onCommand: ((StemEvent) -> Void)?
    var onError: ((String) -> Void)?
    var ignoreExplicitPlayPause = true
    private(set) var isActive = false
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private var targets: [(MPRemoteCommand, Any)] = []
    private var configurationObserver: NSObjectProtocol?
    private var generation = 0
    private let logger = Logger(subsystem: "com.camerondent.AirAnki", category: "StemInput")

    func start() throws {
        guard !isActive else { return }
        try startAudio()
        isActive = true
        generation += 1
        let currentGeneration = generation
        let center = MPRemoteCommandCenter.shared()
        let commands: [(MPRemoteCommand, StemCommand)] = [
            (center.togglePlayPauseCommand, .togglePlayPause),
            (center.playCommand, .play),
            (center.pauseCommand, .pause),
            (center.nextTrackCommand, .nextTrack),
            (center.previousTrackCommand, .previousTrack)
        ]
        for (command, raw) in commands {
            command.isEnabled = true
            let target = command.addTarget { [weak self] _ in
                let time = ProcessInfo.processInfo.systemUptime
                let wall = Date()
                DispatchQueue.main.async {
                    guard let self else { return }
                    let listening = self.isActive && self.generation == currentGeneration
                    let event = StemEvent(command: raw, time: time, wall: wall,
                                          ignoreExplicitPlayPause: self.ignoreExplicitPlayPause,
                                          isListening: listening)
                    self.logger.info("Raw command \(raw.rawValue, privacy: .public) t=\(time) wall=\(wall.description, privacy: .public) detail=\(event.detail, privacy: .public)")
                    if listening { MPNowPlayingInfoCenter.default().playbackState = .playing }
                    self.onCommand?(event)
                }
                return .success
            }
            targets.append((command, target))
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: "AirAnki",
            MPMediaItemPropertyArtist: "Anki remote active",
            MPNowPlayingInfoPropertyPlaybackRate: 1.0
        ]
        MPNowPlayingInfoCenter.default().playbackState = .playing
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.isActive else { return }
                do {
                    self.player.stop()
                    self.engine.stop()
                    try self.startAudio()
                } catch {
                    self.stop()
                    self.onError?("Silent audio stopped: \(error.localizedDescription). Enable the remote to retry.")
                }
            }
        }
    }

    func stop() {
        // With experimental stems disabled, never touch Now Playing or audio.
        guard isActive || !targets.isEmpty || configurationObserver != nil else { return }
        generation += 1
        isActive = false
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        for (command, target) in targets {
            command.removeTarget(target)
            command.isEnabled = false
        }
        targets.removeAll()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        player.stop()
        engine.stop()
    }

    private func startAudio() throws {
        guard let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100),
              let channels = buffer.floatChannelData else {
            throw AnkiError.message("Could not allocate silent audio.")
        }
        buffer.frameLength = buffer.frameCapacity
        for channel in 0..<Int(format.channelCount) {
            channels[channel].update(repeating: 0, count: Int(buffer.frameLength))
        }
        if player.engine == nil { engine.attach(player) }
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do {
            try engine.start()
            player.scheduleBuffer(buffer, at: nil, options: .loops)
            player.play()
        } catch {
            player.stop()
            engine.stop()
            throw error
        }
    }
}
