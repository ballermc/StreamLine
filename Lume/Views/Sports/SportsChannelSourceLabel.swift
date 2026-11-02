import SwiftUI

/// Shows the channel's owning playlist and its provider category.
struct SportsChannelSourceLabel: View {
    let channel: ResolvedChannel

    var body: some View {
        if let text {
            SportsOverflowText(text: text)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text(verbatim: accessibilityText))
        }
    }

    private var text: String? {
        let playlist = channel.stream.playlistName
        let category = channel.stream.categoryName
        switch (playlist, category) {
        case let (.some(playlist), .some(category)):
            String(localized: "Playlist: \(playlist) · Category: \(category)")
        case let (.some(playlist), nil):
            String(localized: "Playlist: \(playlist)")
        case let (nil, .some(category)):
            String(localized: "Category: \(category)")
        case (nil, nil):
            nil
        }
    }

    private var accessibilityText: String {
        text ?? channel.stream.name
    }
}

/// A compact channel summary used directly on the fixture card.
struct SportsFixtureChannelSummary: View {
    let channel: ResolvedChannel

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "tv")
                .font(.caption2)
                .accessibilityHidden(true)
            SportsOverflowText(text: Self.displayText(for: channel))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    static func displayText(for channel: ResolvedChannel) -> String {
        [
            channel.stream.name,
            channel.stream.playlistName,
            channel.stream.categoryName
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

/// Clips long channel labels at rest and scrolls them continuously while the
/// pointer is over the label on macOS.
struct SportsOverflowText: View {
    let text: String

    @State private var contentWidth: CGFloat = 0
    @State private var isHovering = false

    private let gap: CGFloat = 32
    private let lineHeight: CGFloat = 17
    private let pointsPerSecond: CGFloat = 28

    var body: some View {
        GeometryReader { geometry in
            let overflows = contentWidth > geometry.size.width
            let isScrolling = isHovering && overflows
            HStack(spacing: gap) {
                label
                if overflows {
                    label
                }
            }
            .fixedSize(horizontal: true, vertical: false)
            .offset(x: isScrolling ? -(contentWidth + gap) : 0)
            .animation(
                isScrolling
                    ? .linear(duration: Double((contentWidth + gap) / pointsPerSecond))
                        .repeatForever(autoreverses: false)
                    : nil,
                value: isScrolling
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
        .accessibilityLabel(Text(verbatim: text))
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
