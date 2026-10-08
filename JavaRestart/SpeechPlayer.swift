import AVFoundation
import MediaPlayer
import Observation

// MARK: - 学習ノート（聞く用台本）のデータ

struct ListenNote: Decodable, Identifiable, Hashable {
    let id: String
    let date: String
    let title: String
    let category: String
    let chapter: Int?
    let summary: String
    let script: [String]
}

private struct NotesFile: Decodable {
    let readings: [String: String]
    let notes: [ListenNote]
}

enum NotesContent {
    private static let file: NotesFile = {
        guard let url = Bundle.main.url(forResource: "notes", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            fatalError("notes.json がバンドルにありません")
        }
        do {
            return try JSONDecoder().decode(NotesFile.self, from: data)
        } catch {
            fatalError("notes.json を読み込めません: \(error)")
        }
    }()

    /// 新しいノートが上に来るよう、追記順の逆で並べる
    static var notes: [ListenNote] { file.notes.reversed() }

    /// 再生は追記した順（古い順）
    static var playOrder: [ListenNote] { file.notes }

    /// 英単語をカタカナの読みに置き換える（長い語から順に、英字の境界でのみ置換）
    private static let readingRules: [(NSRegularExpression, String)] = {
        file.readings.keys.sorted { $0.count > $1.count }.compactMap { word in
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
            guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (re, NSRegularExpression.escapedTemplate(for: file.readings[word] ?? word))
        }
    }()

    static func spoken(_ text: String) -> String {
        var s = text
        for (re, template) in readingRules {
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        return s
    }
}

// MARK: - 読み上げ

/// 台本を段落ごとに読み上げるプレイヤー。
/// キューはノートの並び。1段落＝1発話で、読み終えたら次の段落、ノートの最後まで来たら次のノートへ進む。
@Observable
final class SpeechPlayer: NSObject, AVSpeechSynthesizerDelegate {
    static let rates: [Double] = [0.8, 1.0, 1.2, 1.5]

    private(set) var queue: [ListenNote] = []
    private(set) var noteIndex = 0
    private(set) var paragraphIndex = 0
    private(set) var isPlaying = false
    private(set) var isPaused = false

    private(set) var rate: Double = {
        let saved = UserDefaults.standard.double(forKey: "speech.rate")
        return saved == 0 ? 1.0 : saved
    }()

    /// 1つのノートを最後まで聞き終えたときに呼ばれる（進捗の記録用）
    @ObservationIgnored var onFinishNote: ((ListenNote) -> Void)?

    @ObservationIgnored private let synthesizer = AVSpeechSynthesizer()
    /// いま読んでいる発話。停止・スキップした古い発話の完了通知を無視するために使う
    @ObservationIgnored private var currentUtterance: AVSpeechUtterance?
    @ObservationIgnored private var commandsInstalled = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    var current: ListenNote? { queue.indices.contains(noteIndex) ? queue[noteIndex] : nil }
    var isActive: Bool { isPlaying || isPaused }

    func isCurrent(_ note: ListenNote) -> Bool { isActive && current?.id == note.id }

    // MARK: 操作

    /// notes を先頭から再生する。startAt を指定するとそのノート（と段落）から始める
    func play(_ notes: [ListenNote], startAt note: ListenNote? = nil, paragraph: Int = 0) {
        guard !notes.isEmpty else { return }
        queue = notes
        noteIndex = note.flatMap { n in notes.firstIndex { $0.id == n.id } } ?? 0
        paragraphIndex = paragraph
        activateSession()
        installRemoteCommands()
        restart()   // 再生中に別のノートを選んだときは、読んでいる発話を止めてから始める
    }

    func togglePause() {
        if isPaused {
            if synthesizer.isPaused {
                synthesizer.continueSpeaking()
            } else {
                speakCurrent()
            }
            isPaused = false
            isPlaying = true
        } else if isPlaying {
            synthesizer.pauseSpeaking(at: .word)
            isPaused = true
            isPlaying = false
        }
        updateNowPlaying()
    }

    func stop() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPlaying = false
        isPaused = false
        queue = []
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    func nextParagraph() {
        guard let note = current else { return }
        if paragraphIndex + 1 < note.script.count {
            paragraphIndex += 1
        } else if noteIndex + 1 < queue.count {
            noteIndex += 1
            paragraphIndex = 0
        } else {
            stop()
            return
        }
        restart()
    }

    /// 1つ前の段落へ。ノートの先頭にいるときは、前のノートの最後の段落へ
    func previousParagraph() {
        guard current != nil else { return }
        if paragraphIndex > 0 {
            paragraphIndex -= 1
        } else if noteIndex > 0 {
            noteIndex -= 1
            paragraphIndex = max(0, queue[noteIndex].script.count - 1)
        }
        restart()
    }

    func nextNote() {
        guard noteIndex + 1 < queue.count else { stop(); return }
        noteIndex += 1
        paragraphIndex = 0
        restart()
    }

    func jump(to paragraph: Int, in note: ListenNote) {
        if let i = queue.firstIndex(where: { $0.id == note.id }) {
            noteIndex = i
            paragraphIndex = paragraph
            restart()
        } else {
            play([note], paragraph: paragraph)
        }
    }

    func setRate(_ value: Double) {
        rate = value
        UserDefaults.standard.set(value, forKey: "speech.rate")
        if isPlaying { restart() }    // 速さは発話ごとに決まるので、今の段落から読み直す
    }

    private func restart() {
        currentUtterance = nil
        synthesizer.stopSpeaking(at: .immediate)
        isPaused = false
        speakCurrent()
    }

    // MARK: 発話

    private func speakCurrent() {
        guard let note = current, note.script.indices.contains(paragraphIndex) else {
            stop()
            return
        }
        let text = NotesContent.spoken(note.script[paragraphIndex])
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = Self.japaneseVoice
        utterance.rate = Self.utteranceRate(for: rate)
        utterance.preUtteranceDelay = paragraphIndex == 0 ? 0.3 : 0.1
        utterance.postUtteranceDelay = paragraphIndex == note.script.count - 1 ? 0.8 : 0.25
        isPlaying = true
        isPaused = false
        currentUtterance = utterance
        synthesizer.speak(utterance)
        updateNowPlaying()
    }

    private func advanceAfterFinish() {
        guard let note = current else { return }
        if paragraphIndex + 1 < note.script.count {
            paragraphIndex += 1
            speakCurrent()
        } else {
            onFinishNote?(note)
            if noteIndex + 1 < queue.count {
                noteIndex += 1
                paragraphIndex = 0
                speakCurrent()
            } else {
                stop()
            }
        }
    }

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        DispatchQueue.main.async { [weak self] in
            guard let self, utterance === self.currentUtterance, self.isPlaying else { return }
            self.advanceAfterFinish()
        }
    }

    // MARK: 声と速さ

    /// 端末にある日本語の声のうち、最も品質の高いもの（プレミアム > 拡張 > 標準）
    private static let japaneseVoice: AVSpeechSynthesisVoice? = {
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == "ja-JP" }
        let best = voices.max { $0.quality.rawValue < $1.quality.rawValue }
        return best ?? AVSpeechSynthesisVoice(language: "ja-JP")
    }()

    static var voiceDescription: String {
        guard let v = japaneseVoice else { return "日本語の声が見つかりません" }
        switch v.quality {
        case .premium: return "\(v.name)（プレミアム）"
        case .enhanced: return "\(v.name)（拡張）"
        default: return "\(v.name)（標準）"
        }
    }

    static var hasHighQualityVoice: Bool {
        (japaneseVoice?.quality.rawValue ?? 0) >= AVSpeechSynthesisVoiceQuality.enhanced.rawValue
    }

    private static func utteranceRate(for factor: Double) -> Float {
        let base = Double(AVSpeechUtteranceDefaultSpeechRate)
        let r = base * factor
        return Float(min(max(r, Double(AVSpeechUtteranceMinimumSpeechRate)), Double(AVSpeechUtteranceMaximumSpeechRate)))
    }

    // MARK: オーディオセッション・ロック画面

    private func activateSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }

    private func installRemoteCommands() {
        guard !commandsInstalled else { return }
        commandsInstalled = true
        let center = MPRemoteCommandCenter.shared()
        _ = center.playCommand.addTarget { [weak self] _ in
            guard let self, self.isPaused else { return .commandFailed }
            self.togglePause()
            return .success
        }
        _ = center.pauseCommand.addTarget { [weak self] _ in
            guard let self, self.isPlaying else { return .commandFailed }
            self.togglePause()
            return .success
        }
        _ = center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self, self.isActive else { return .commandFailed }
            self.togglePause()
            return .success
        }
        _ = center.nextTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isActive else { return .commandFailed }
            self.nextNote()
            return .success
        }
        _ = center.previousTrackCommand.addTarget { [weak self] _ in
            guard let self, self.isActive else { return .commandFailed }
            self.previousParagraph()
            return .success
        }
    }

    private func updateNowPlaying() {
        guard let note = current else { return }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = [
            MPMediaItemPropertyTitle: note.title,
            MPMediaItemPropertyArtist: "Java学習ノート",
            MPMediaItemPropertyAlbumTitle: "\(noteIndex + 1) / \(queue.count)  ・  段落 \(paragraphIndex + 1) / \(note.script.count)",
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]
    }
}
