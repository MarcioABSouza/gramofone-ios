import AVFoundation
import MediaPlayer
import UIKit
import SwiftUI

/// Player único do app: fila, áudio em segundo plano, tela de bloqueio,
/// persistência da fila e disparo dos scrobbles.
@MainActor
final class PlayerController: ObservableObject {
    enum RepeatMode: String, CaseIterable {
        case off, one, all

        var symbol: String {
            switch self {
            case .off: return "repeat"
            case .one: return "repeat.1"
            case .all: return "repeat"
            }
        }

        var isActive: Bool { self != .off }
    }

    // MARK: - Estado publicado

    @Published private(set) var queue: [QueueItem] = []
    @Published private(set) var index = 0
    @Published private(set) var isPlaying = false
    @Published private(set) var position: Double = 0
    @Published private(set) var duration: Double = 0
    @Published private(set) var repeatMode: RepeatMode = .off
    @Published private(set) var errorMessage: String?
    @Published var isExpanded = false

    // MARK: - Interno

    private var player: AVPlayer?
    private var timeObserver: Any?
    private var endObserver: NSObjectProtocol?
    private var session: Session?
    private var scrobbles: ScrobbleQueue?
    private var network: NetworkMonitor?
    private var playSession: PlaySession?
    private var lastTick = Date()
    private var lastSave = Date()
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var commandsConfigured = false
    private var isConfigured = false

    private struct PlaySession {
        let playId: String
        let startedAt: Date
        let item: QueueItem
        var played: Double = 0
        var scrobbled = false
    }

    private struct Snapshot: Codable {
        let items: [QueueItem]
        let index: Int
        let position: Double
    }

    // MARK: - Setup

    func configure(session: Session, scrobbles: ScrobbleQueue, network: NetworkMonitor) {
        guard !isConfigured else { return }
        isConfigured = true

        self.session = session
        self.scrobbles = scrobbles
        self.network = network

        loadRepeatMode()
        configureRemoteCommands()
        observeInterruptions()
        restoreSnapshot()
    }

    var currentItem: QueueItem? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var hasQueue: Bool { !queue.isEmpty }

    /// Salva a posição agora (usado quando o app vai para segundo plano).
    func persistNow() {
        saveSnapshot()
    }

    /// Capa da faixa: arquivo baixado primeiro, senão o cache do servidor.
    func coverURL(for item: QueueItem) -> URL? {
        if let albumId = item.albumId, let file = OfflineStore.coverFile(albumId) {
            return file
        }

        if let albumId = item.albumId, let client = session?.client {
            return client.coverURL(albumId: albumId)
        }

        return nil
    }

    // MARK: - Controles

    func play(queue items: [QueueItem], startingAt start: Int) {
        guard !items.isEmpty, items.indices.contains(start) else { return }

        finalizePlaySession()
        queue = items
        index = start
        startCurrent(autoplay: true)
        saveSnapshot()
    }

    /// Acrescenta faixas ao fim da fila (sem duplicar). Fila vazia → começa a tocar.
    /// Devolve quantas entraram de fato.
    @discardableResult
    func append(_ items: [QueueItem]) -> Int {
        guard !items.isEmpty else { return 0 }

        if queue.isEmpty {
            play(queue: items, startingAt: 0)
            return items.count
        }

        let existing = Set(queue.map(\.trackId))
        let newItems = items.filter { !existing.contains($0.trackId) }
        guard !newItems.isEmpty else { return 0 }

        queue.append(contentsOf: newItems)
        saveSnapshot()
        return newItems.count
    }

    /// Toca o conjunto embaralhado (as faixas da lista, não a ordem dos álbuns).
    func playShuffled(_ items: [QueueItem]) {
        guard !items.isEmpty else { return }
        play(queue: items.shuffled(), startingAt: 0)
    }

    func resume() {
        guard currentItem != nil else { return }
        activateAudioSession()

        if player == nil {
            startCurrent(autoplay: true)
            return
        }

        if playSession == nil {
            beginPlaySession()
        }

        player?.play()
        isPlaying = true
        updateNowPlaying()
    }

    func pause() {
        player?.pause()
        isPlaying = false
        updateNowPlaying()
        saveSnapshot()
    }

    func toggle() {
        if isPlaying { pause() } else { resume() }
    }

    func next() {
        guard !queue.isEmpty else { return }
        finalizePlaySession()

        if index + 1 < queue.count {
            index += 1
            startCurrent(autoplay: true)
        } else if repeatMode == .all {
            index = 0
            startCurrent(autoplay: true)
        } else {
            pause()
            seek(to: 0)
        }

        saveSnapshot()
    }

    func previous() {
        guard !queue.isEmpty else { return }

        if position > 3 {
            seek(to: 0)
            return
        }

        finalizePlaySession()

        if index > 0 {
            index -= 1
            startCurrent(autoplay: true)
        } else if repeatMode == .all {
            index = queue.count - 1
            startCurrent(autoplay: true)
        } else {
            seek(to: 0)
        }

        saveSnapshot()
    }

    func seek(to seconds: Double) {
        let clamped = max(0, min(seconds, duration > 0 ? duration : seconds))
        player?.seek(to: CMTime(seconds: clamped, preferredTimescale: 600))
        position = clamped
        updateNowPlaying()
    }

    func jump(to itemIndex: Int) {
        guard queue.indices.contains(itemIndex) else { return }
        finalizePlaySession()
        index = itemIndex
        startCurrent(autoplay: true)
        saveSnapshot()
    }

    func cycleRepeat() {
        switch repeatMode {
        case .off: repeatMode = .one
        case .one: repeatMode = .all
        case .all: repeatMode = .off
        }
        UserDefaults.standard.set(repeatMode.rawValue, forKey: "gramofone.player.repeat")
    }

    /// Logout: para o áudio e limpa a fila (o snapshot também).
    func stop() {
        finalizePlaySession()
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        isPlaying = false
        queue = []
        index = 0
        position = 0
        duration = 0
        playSession = nil
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? FileManager.default.removeItem(at: snapshotURL)
    }

    // MARK: - Reprodução

    private func startCurrent(autoplay: Bool) {
        guard let item = currentItem else { return }
        errorMessage = nil

        guard let url = resolveURL(for: item) else {
            errorMessage = "Faixa sem cópia local e sem servidor — não é possível tocar."
            isPlaying = false
            return
        }

        let asset = AVURLAsset(url: url)
        let avItem = AVPlayerItem(asset: asset)

        if let existing = player {
            existing.replaceCurrentItem(with: avItem)
        } else {
            let created = AVPlayer(playerItem: avItem)
            player = created
            addTimeObserver(to: created)
        }

        observeEnd(of: avItem)

        duration = item.duration ?? 0
        position = 0

        if autoplay {
            activateAudioSession()
            beginPlaySession()
            player?.play()
            isPlaying = true
        } else {
            isPlaying = false
        }

        updateNowPlaying()
    }

    private func resolveURL(for item: QueueItem) -> URL? {
        // 1) baixado: toca do disco
        if let albumId = item.albumId,
           let offline = OfflineStore.load(albumId),
           let track = offline.tracks.first(where: { $0.trackId == item.trackId }),
           let file = OfflineStore.localFile(albumId, fileName: track.fileName) {
            return file
        }

        // 2) streaming pela LAN
        if let path = item.filePath, let client = session?.client {
            return client.mediaURL(path: path)
        }

        return nil
    }

    private func addTimeObserver(to player: AVPlayer) {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor in
                self?.tick(time: time.seconds)
            }
        }
    }

    private func tick(time: Double) {
        guard !time.isNaN else { return }

        position = time
        isPlaying = (player?.rate ?? 0) > 0

        if let itemDuration = player?.currentItem?.duration.seconds,
           itemDuration.isFinite,
           itemDuration > 0 {
            duration = itemDuration
        }

        accumulateListenTime()
        maybeScrobble()

        if Date().timeIntervalSince(lastSave) > 5 {
            lastSave = Date()
            saveSnapshot()
        }
    }

    private func accumulateListenTime() {
        let now = Date()
        let delta = now.timeIntervalSince(lastTick)
        lastTick = now

        guard var session = playSession, isPlaying, delta > 0, delta < 2 else { return }
        session.played += delta
        playSession = session
    }

    private func maybeScrobble() {
        guard var session = playSession, !session.scrobbled else { return }
        guard let threshold = scrobbleThreshold(for: duration) else { return }
        guard session.played >= threshold else { return }

        session.scrobbled = true
        playSession = session

        scrobbles?.enqueue(
            title: session.item.title,
            artist: session.item.artist,
            album: session.item.albumTitle,
            duration: duration,
            startedAt: session.startedAt,
            playId: session.playId
        )
    }

    /// Regra do Last.fm: faixa > 30 s e metade dela **ou** 4 min ouvidos.
    private func scrobbleThreshold(for duration: Double) -> Double? {
        guard duration > 30 else { return nil }
        return min(duration / 2, 240)
    }

    private func beginPlaySession() {
        guard let item = currentItem, playSession == nil else { return }

        let playId = UUID().uuidString
        let startedAt = Date()
        playSession = PlaySession(playId: playId, startedAt: startedAt, item: item)
        lastTick = Date()

        guard let session else { return }
        let albumId = item.albumId
        let songId = item.songId
        let durationSeconds = item.duration ?? 0

        let playBody = APIClient.PlayBody(
            trackId: item.trackId,
            songId: songId,
            albumId: albumId,
            title: item.title,
            artist: item.artist,
            albumTitle: item.albumTitle,
            duration: durationSeconds > 0 ? durationSeconds : nil
        )

        let nowPlayingBody = APIClient.NowPlayingBody(
            title: item.title,
            artist: item.artist,
            album: item.albumTitle,
            duration: max(1, Int(durationSeconds.rounded()))
        )

        Task {
            _ = try? await session.authorized { client, token in
                await client.recordPlay(token: token, body: playBody)
                return ()
            }
            _ = try? await session.authorized { client, token in
                await client.nowPlaying(token: token, body: nowPlayingBody)
                return ()
            }
        }
    }

    private func finalizePlaySession() {
        // Scrobble pendente de uma faixa que não chegou ao fim do rádio.
        maybeScrobble()
        playSession = nil
    }

    // MARK: - Fim da faixa

    private func observeEnd(of item: AVPlayerItem) {
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.handleTrackEnded()
            }
        }
    }

    private func handleTrackEnded() {
        finalizePlaySession()

        if repeatMode == .one {
            seek(to: 0)
            beginPlaySession()
            player?.play()
            isPlaying = true
            return
        }

        if index + 1 < queue.count {
            index += 1
            startCurrent(autoplay: true)
        } else if repeatMode == .all, !queue.isEmpty {
            index = 0
            startCurrent(autoplay: true)
        } else {
            pause()
            seek(to: 0)
            isPlaying = false
        }

        saveSnapshot()
    }

    // MARK: - Áudio em segundo plano / tela de bloqueio

    private func activateAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .default, options: [])
            try audioSession.setActive(true)
        } catch {
            // sem áudio em segundo plano; toca no primeiro plano
        }
    }

    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                let type = AVAudioSession.InterruptionType(rawValue: raw)
            else {
                return
            }

            Task { @MainActor in
                if type == .began {
                    self?.pause()
                }
            }
        }
    }

    private func configureRemoteCommands() {
        guard !commandsConfigured else { return }
        commandsConfigured = true

        let center = MPRemoteCommandCenter.shared()

        _ = center.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.resume() }
            return .success
        }

        _ = center.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pause() }
            return .success
        }

        _ = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }

        _ = center.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }

        _ = center.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.previous() }
            return .success
        }

        _ = center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }

            Task { @MainActor in self?.seek(to: event.positionTime) }
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let item = currentItem else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }

        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyMediaType: NSNumber(value: MPNowPlayingInfoMediaType.audio.rawValue),
        ]

        if let artist = item.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = item.albumTitle { info[MPMediaItemPropertyAlbumTitle] = album }
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        if let artwork = artwork(for: item) { info[MPMediaItemPropertyArtwork] = artwork }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    private func artwork(for item: QueueItem) -> MPMediaItemArtwork? {
        let key = item.albumId ?? item.trackId

        if let cached = artworkCache[key] { return cached }

        if let albumId = item.albumId,
           let file = OfflineStore.coverFile(albumId),
           let image = UIImage(contentsOfFile: file.path) {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            artworkCache[key] = artwork
            return artwork
        }

        if let albumId = item.albumId, let url = session?.client?.coverURL(albumId: albumId) {
            Task { [weak self] in
                guard let (data, _) = try? await URLSession.shared.data(from: url),
                      let image = UIImage(data: data)
                else {
                    return
                }

                await MainActor.run {
                    guard let self else { return }
                    self.artworkCache[key] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                    self.updateNowPlaying()
                }
            }
        }

        return nil
    }

    // MARK: - Persistência

    private var snapshotURL: URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("queue.json")
    }

    private func saveSnapshot() {
        guard !queue.isEmpty else { return }

        let snapshot = Snapshot(items: queue, index: index, position: position)
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: snapshotURL, options: .atomic)
    }

    private func restoreSnapshot() {
        guard
            let data = try? Data(contentsOf: snapshotURL),
            let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
            !snapshot.items.isEmpty,
            snapshot.items.indices.contains(snapshot.index)
        else {
            return
        }

        queue = snapshot.items
        index = snapshot.index
        position = snapshot.position
        duration = snapshot.items[snapshot.index].duration ?? 0

        // Reaparece pausado, no ponto salvo (sem autoplay).
        startCurrent(autoplay: false)
        seek(to: snapshot.position)
        updateNowPlaying()
    }

    private func loadRepeatMode() {
        let raw = UserDefaults.standard.string(forKey: "gramofone.player.repeat") ?? ""
        repeatMode = RepeatMode(rawValue: raw) ?? .off
    }
}
