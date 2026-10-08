import SwiftUI

// MARK: - 一覧

struct NotesView: View {
    @Environment(ProgressStore.self) private var store
    @Environment(SpeechPlayer.self) private var player
    let openChapter: (Int) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                Section {
                    ForEach(NotesContent.notes) { note in
                        NavigationLink(value: note) {
                            NoteRow(note: note)
                        }
                        .swipeActions(edge: .leading) {
                            Button {
                                player.play([note])
                            } label: {
                                Label("聞く", systemImage: "play.fill")
                            }
                            .tint(Palette.accent)
                        }
                    }
                } header: {
                    Text("新しい順").textCase(nil)
                }
            }
            .navigationTitle("学習ノート")
            .navigationDestination(for: ListenNote.self) { note in
                NoteDetailView(note: note, openChapter: openChapter)
            }
        }
    }

    private var header: some View {
        let total = NotesContent.notes.count
        let heard = NotesContent.notes.filter { store.listened.contains($0.id) }.count
        return VStack(alignment: .leading, spacing: 12) {
            Text("質問して解説してもらった内容を、聞くための台本にしたものです。コードは言葉で説明しているので、画面を見なくても分かります。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ProgressView(value: Double(heard), total: Double(max(total, 1))) {
                Text("最後まで聞いたノート \(heard) / \(total)")
                    .font(.caption).monospacedDigit()
            }

            HStack(spacing: 10) {
                Button {
                    player.play(NotesContent.playOrder)
                } label: {
                    Label("全部を通して聞く", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                if let next = NotesContent.playOrder.first(where: { !store.listened.contains($0.id) }), heard > 0 {
                    Button {
                        player.play(NotesContent.playOrder, startAt: next)
                    } label: {
                        Label("未聴から", systemImage: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)

            VoiceHint()
        }
        .padding(.vertical, 6)
    }
}

private struct VoiceHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("声：\(SpeechPlayer.voiceDescription)", systemImage: "waveform")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !SpeechPlayer.hasHighQualityVoice {
                Text("設定 → アクセシビリティ → 読み上げコンテンツ → 声 → 日本語 で「拡張」の声をダウンロードすると、より自然な読み上げになります。ダウンロード後はアプリを再起動してください。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct NoteRow: View {
    @Environment(ProgressStore.self) private var store
    @Environment(SpeechPlayer.self) private var player
    let note: ListenNote

    var body: some View {
        let playing = player.isCurrent(note)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: playing ? "speaker.wave.2.fill"
                  : store.listened.contains(note.id) ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(playing || store.listened.contains(note.id) ? Palette.accent : .secondary)
                .symbolEffect(.variableColor.iterative, isActive: playing && player.isPlaying)
                .frame(width: 22)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(note.title).font(.body.weight(.medium))
                Text(md(note.summary)).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                HStack(spacing: 6) {
                    TagView(text: note.category)
                    Text(note.date).font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                    Text("・約\(Self.minutes(note))分").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    /// 日本語の読み上げを 1 分あたり約 300 字として概算
    static func minutes(_ note: ListenNote) -> Int {
        max(1, Int((Double(note.script.joined().count) / 300).rounded()))
    }
}

// MARK: - 詳細（台本）

struct NoteDetailView: View {
    @Environment(SpeechPlayer.self) private var player
    @Environment(ProgressStore.self) private var store
    let note: ListenNote
    let openChapter: (Int) -> Void

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(note.script.indices, id: \.self) { i in
                            paragraph(i)
                                .id(i)
                        }
                    }
                    if let ch = note.chapter, let chapter = Content.chapter(ch) {
                        Button {
                            openChapter(ch)
                        } label: {
                            Label("参考書：第\(ch)章 \(chapter.t)", systemImage: "book")
                        }
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .onChange(of: player.paragraphIndex) {
                guard player.isCurrent(note) else { return }
                withAnimation { proxy.scrollTo(player.paragraphIndex, anchor: .center) }
            }
        }
        .navigationTitle(note.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TagView(text: note.category)
                Text(note.date).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                if store.listened.contains(note.id) {
                    Label("聞いた", systemImage: "checkmark.circle.fill")
                        .font(.caption).foregroundStyle(Palette.accent)
                }
            }
            Text(note.title).font(.title2.bold())
            HStack(spacing: 10) {
                if player.isCurrent(note) {
                    Button {
                        player.togglePause()
                    } label: {
                        Label(player.isPaused ? "再開" : "一時停止",
                              systemImage: player.isPaused ? "play.fill" : "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        player.play([note])
                    } label: {
                        Label("このノートを聞く", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        player.play(NotesContent.playOrder, startAt: note)
                    } label: {
                        Label("ここから続けて", systemImage: "text.line.first.and.arrowtriangle.forward")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .controlSize(.large)
            Text("段落をタップすると、そこから読み上げます。")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func paragraph(_ i: Int) -> some View {
        let active = player.isCurrent(note) && player.paragraphIndex == i
        return Button {
            player.jump(to: i, in: note)
        } label: {
            Text(note.script[i])
                .lineSpacing(5)
                .multilineTextAlignment(.leading)
                .foregroundStyle(active ? Color.primary : Color.primary.opacity(player.isCurrent(note) ? 0.55 : 0.9))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(active ? Palette.accent.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: 10))
                .overlay(alignment: .leading) {
                    if active {
                        RoundedRectangle(cornerRadius: 2).fill(Palette.accent).frame(width: 3).padding(.vertical, 8)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: active)
    }
}

// MARK: - どのタブにも出るミニプレイヤー

struct MiniPlayerModifier: ViewModifier {
    @Environment(SpeechPlayer.self) private var player

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            if player.isActive, let note = player.current {
                MiniPlayer(note: note)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: player.isActive)
    }
}

extension View {
    func miniPlayer() -> some View { modifier(MiniPlayerModifier()) }
}

private struct MiniPlayer: View {
    @Environment(SpeechPlayer.self) private var player
    let note: ListenNote

    var body: some View {
        VStack(spacing: 8) {
            ProgressView(value: Double(player.paragraphIndex + 1), total: Double(max(note.script.count, 1)))
                .tint(Palette.accent)
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(note.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text("\(player.noteIndex + 1)/\(player.queue.count) ノート・段落 \(player.paragraphIndex + 1)/\(note.script.count)")
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button { player.previousParagraph() } label: {
                    Image(systemName: "backward.fill")
                }
                .accessibilityLabel("前の段落")
                Button { player.togglePause() } label: {
                    Image(systemName: player.isPaused ? "play.fill" : "pause.fill").font(.title2)
                }
                .accessibilityLabel(player.isPaused ? "再開" : "一時停止")
                Button { player.nextParagraph() } label: {
                    Image(systemName: "forward.fill")
                }
                .accessibilityLabel("次の段落")
                Menu {
                    Picker("読む速さ", selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                        ForEach(SpeechPlayer.rates, id: \.self) { r in
                            Text(String(format: "%.1f倍", r)).tag(r)
                        }
                    }
                    Button("次のノートへ", systemImage: "forward.end.fill") { player.nextNote() }
                    Button("停止", systemImage: "stop.fill", role: .destructive) { player.stop() }
                } label: {
                    Text(String(format: "%.1fx", player.rate))
                        .font(.caption.monospacedDigit().weight(.semibold))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.secondary.opacity(0.5)))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(Palette.accent)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}
