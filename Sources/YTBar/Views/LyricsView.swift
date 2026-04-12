import SwiftUI

struct LyricsView: View {
    @EnvironmentObject private var vm: AppViewModel

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            content
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Lyrics")
    }

    @ViewBuilder
    private var content: some View {
        if vm.lyricsLoading {
            ProgressView("Loading lyrics...")
                .font(.system(size: 12))
        } else if let synced = vm.currentLyrics?.syncedLyrics {
            SyncedLyricsContent(lines: synced, progress: vm.progress)
        } else if let plain = vm.currentLyrics?.plainLyrics {
            plainLyricsContent(plain)
        } else {
            noLyricsContent
        }
    }

    private func plainLyricsContent(_ text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .padding()
                .frame(maxWidth: .infinity)
        }
    }

    private var noLyricsContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.quote")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No lyrics available")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }
}

private struct SyncedLyricsContent: View {
    let lines: [LyricLine]
    let progress: Double
    @State private var activeIndex: Int = 0

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 8) {
                    Spacer().frame(height: 80)
                    ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                        Text(line.text)
                            .font(.system(size: idx == activeIndex ? 15 : 13,
                                          weight: idx == activeIndex ? .bold : .regular))
                            .opacity(opacity(for: idx))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 2)
                            .id(idx)
                            .animation(.easeInOut(duration: 0.5), value: activeIndex)
                    }
                    Spacer().frame(height: 80)
                }
                .padding(.horizontal)
            }
            .onChange(of: computedIndex) { _, newIdx in
                guard newIdx != activeIndex else { return }
                activeIndex = newIdx
                withAnimation(.easeInOut(duration: 0.6)) {
                    proxy.scrollTo(newIdx, anchor: .center)
                }
            }
            .onAppear {
                // Jump straight to the correct line on first render without
                // animating from the default 0 state — otherwise every time
                // the lyrics overlay re-mounts (e.g. after the browse panel
                // was collapsed and re-opened), the initial font-size /
                // opacity animation from line 0 looks like a flicker.
                var tx = Transaction()
                tx.disablesAnimations = true
                withTransaction(tx) {
                    activeIndex = computedIndex
                }
                // Snap the scroll to the active line immediately as well.
                proxy.scrollTo(computedIndex, anchor: .center)
            }
        }
    }

    private var computedIndex: Int {
        guard !lines.isEmpty else { return 0 }
        var best = 0
        for (i, line) in lines.enumerated() {
            if line.timestamp <= progress { best = i }
        }
        return best
    }

    private func opacity(for index: Int) -> Double {
        let distance = abs(index - activeIndex)
        if distance == 0 { return 1.0 }
        if distance <= 2 { return 0.6 }
        return 0.35
    }
}
