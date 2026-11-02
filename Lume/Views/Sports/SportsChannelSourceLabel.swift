import SwiftUI

/// Shows the channel's owning playlist and its provider category.
struct SportsChannelSourceLabel: View {
    let channel: ResolvedChannel

    var body: some View {
        if let text {
            Text(verbatim: text)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
                .accessibilityLabel(Text(verbatim: accessibilityText))
        }
    }

    private var text: String? {
        let playlist = channel.stream.playlistName
        let category = channel.stream.categoryName
        return switch (playlist, category) {
        case let (.some(playlist), .some(category)):
            "\(playlist) · \(category)"
        case let (.some(playlist), nil):
            playlist
        case let (nil, .some(category)):
            category
        case (nil, nil):
            nil
        }
    }

    private var accessibilityText: String {
        text ?? channel.stream.name
    }
}

/// Clips long channel labels at rest and scrolls them continuously after the
/// label remains highlighted for five seconds.
struct SportsOverflowText: View {
    let text: String
    var lineHeight: CGFloat = 17

    @State private var contentWidth: CGFloat = 0
    @State private var isHovering = false
    @State private var isScrolling = false
    @Environment(\.isFocused) private var isFocused

    private let gap: CGFloat = 32
    private let pointsPerSecond: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let overflows = contentWidth > geometry.size.width
            let shouldScroll = isScrolling && overflows
            HStack(spacing: gap) {
                label
                if overflows {
                    label
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: shouldScroll ? -(contentWidth + gap) : 0)
            .animation(
                shouldScroll
                    ? .linear(duration: Double((contentWidth + gap) / pointsPerSecond))
                        .repeatForever(autoreverses: false)
                    : nil,
                value: shouldScroll
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .clipped()
            #if os(macOS)
                .onHover { isHovering = $0 }
            #endif
            .background {
                label
                    .fixedSize(horizontal: true, vertical: false)
                    .hidden()
                    .background {
                        GeometryReader { textGeometry in
                            Color.clear.preference(key: SportsTextWidthKey.self, value: textGeometry.size.width)
                        }
                    }
            }
        }
        .frame(height: lineHeight)
        .onPreferenceChange(SportsTextWidthKey.self) { contentWidth = $0 }
        .task(id: isHighlighted) {
            isScrolling = false
            guard isHighlighted else { return }
            do {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                guard !Task.isCancelled else { return }
                isScrolling = true
            } catch {
                return
            }
        }
        .accessibilityLabel(Text(verbatim: text))
    }

    private var isHighlighted: Bool {
        #if os(macOS)
            return isHovering || isFocused
        #else
            return isFocused
        #endif
    }

    private var label: some View {
        Text(verbatim: text)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
    }
}

private struct SportsTextWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
