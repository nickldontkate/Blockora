import AVFoundation

/// Centralized sound effect playback (§56). MVP ships with system sounds so
/// the game is never silent while bespoke SFX are produced; swapping in real
/// assets later only touches `SoundEffect.fileName`.
enum SoundEffect: String {
    case moduleSnap
    case modulePlace
    case synergyDiscovered
    case constructionComplete
    case collapse
    case contractComplete
    case districtUnlock
    case resourceCollect
    case uiTap
}

final class AudioManager {
    static let shared = AudioManager()

    private var players: [SoundEffect: AVAudioPlayer] = [:]
    var isMuted = false

    private init() {
        try? AVAudioSession.sharedInstance().setCategory(.ambient, options: [.mixWithOthers])
    }

    /// No-op safe: if a bundled asset is missing (true until art/audio pass),
    /// this simply does nothing rather than crashing the build.
    func play(_ effect: SoundEffect) {
        guard !isMuted else { return }
        if let cached = players[effect] {
            cached.currentTime = 0
            cached.play()
            return
        }
        guard let url = Bundle.main.url(forResource: effect.rawValue, withExtension: "caf")
            ?? Bundle.main.url(forResource: effect.rawValue, withExtension: "wav") else { return }
        guard let player = try? AVAudioPlayer(contentsOf: url) else { return }
        players[effect] = player
        player.play()
    }
}
