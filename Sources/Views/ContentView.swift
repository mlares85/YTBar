import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var vm: AppViewModel

    /// Height of the top-controls layer (player + divider + nav bar). Must
    /// match `AppDelegate.collapsedPopoverHeight` so the collapsed popover
    /// exactly frames the top controls with no empty sliver.
    private let topBarHeight: CGFloat = 170
    private let totalHeight: CGFloat = 520
    private let popoverWidth: CGFloat = 420

    var body: some View {
        ZStack(alignment: .top) {
            Group {
                if vm.hasActiveTrack {
                    activeLayout
                } else {
                    noTrackLayout
                }
            }
            if let toast = vm.activeToast {
                ToastView(toast: toast, onDismiss: { vm.dismissToast() })
                    .zIndex(999)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if vm.ytdlpOutdated && !vm.ytdlpBannerDismissed {
                ytdlpBanner
            }
        }
        .animation(.easeInOut(duration: 0.25), value: vm.activeToast != nil)
    }

    private var ytdlpBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("yt-dlp is outdated — playback may fail")
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("Update") { vm.updateYtdlp() }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(vm.isUpdatingYtdlp)
            Button {
                vm.ytdlpBannerDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss banner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.orange.opacity(0.1))
    }

    // MARK: - Active track layout (sliding browse panel)

    /// Outer VStack: topControlsLayer is a *sibling* of slideContainer, not
    /// a child. SwiftUI computes the VStack's height as the sum of the two,
    /// and the top controls' layout is `{y: 0, height: 160}` regardless of
    /// what state slideContainer is in — so the top controls never get
    /// re-laid-out and cannot jitter. Only `slideContainer` participates in
    /// the animation.
    private var activeLayout: some View {
        VStack(spacing: 0) {
            topControlsLayer
            slideContainer
        }
        .frame(width: popoverWidth, alignment: .top)
    }

    /// The player + nav bar. No animation modifier, no state-dependent
    /// sizing — this view's frame is pure `{width: 420, height: 160}` and
    /// SwiftUI has no reason to re-layout it when `isBrowsePanelVisible`
    /// flips.
    private var topControlsLayer: some View {
        VStack(spacing: 0) {
            NowPlayingView()
            Divider()
            tabBar
            Spacer(minLength: 0)
        }
        .frame(width: popoverWidth, height: topBarHeight, alignment: .top)
        .background(.background)
    }

    /// The browse panel container. No animation — the panel snaps in and
    /// out. The popover bubble resizes instantly in sync (see
    /// `AppDelegate.updatePopoverSizeIfNeeded`).
    private var slideContainer: some View {
        let panelHeight = totalHeight - topBarHeight
        return VStack(spacing: 0) {
            Divider()
            browsePanel
        }
        .frame(width: popoverWidth, height: panelHeight, alignment: .top)
        .frame(
            width: popoverWidth,
            height: vm.isBrowsePanelVisible ? panelHeight : 0,
            alignment: .top
        )
        .clipped()
        // Disable hit testing when the panel is hidden. `.clipped()` only
        // clips the rendered pixels — the children's logical frames are
        // still hit-testable at their original positions, so without this,
        // clicks on a nav button could leak through to a TrackRow in the
        // hidden content and start playing that track.
        .allowsHitTesting(vm.isBrowsePanelVisible)
    }

    // MARK: - No active track layout (static)

    /// When nothing is playing, the top of the popover has no player — just
    /// the nav bar and the browse panel. No slide animation needed.
    private var noTrackLayout: some View {
        VStack(spacing: 0) {
            tabBar
            Divider()
            browsePanel
        }
        .frame(width: popoverWidth, height: totalHeight)
    }

    // MARK: - Browse panel content

    private var browsePanel: some View {
        ZStack {
            tabContent
            if vm.showLyrics {
                LyricsView()
                    .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var tabContent: some View {
        switch vm.selectedTab {
        case 0: SearchView()
        case 1: LibraryView()
        case 2: LikedMusicView()
        case 3: QueueView { }
        case 4: SettingsView()
        default: SearchView()
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 0) {
            tabButton(icon: "magnifyingglass", label: "Search", index: 0)
            tabButton(icon: "music.note.list", label: "Library", index: 1)
            tabButton(icon: "heart.fill", label: "Liked", index: 2)
            tabButton(icon: "list.bullet", label: "Queue", index: 3)
            tabButton(icon: "gear", label: "Settings", index: 4)
        }
        .padding(.horizontal, 4)
        .padding(.top, 4)
        .padding(.bottom, 14)
    }

    private func tabButton(icon: String, label: String, index: Int) -> some View {
        Button {
            vm.selectTab(index)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 16))
                Text(label)
                    .font(.system(size: 10))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .foregroundStyle(isTabActive(index) ? .primary : .secondary)
            .background(tabBackground(active: isTabActive(index)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isTabActive(index) ? .isSelected : [])
        .help(label)
    }

    @ViewBuilder
    private func tabBackground(active: Bool) -> some View {
        if active {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.primary.opacity(0.14))
        } else {
            Color.clear
        }
    }

    private func isTabActive(_ index: Int) -> Bool {
        vm.isBrowsePanelVisible && vm.selectedTab == index
    }
}
