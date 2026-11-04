import SwiftUI

/// Shows the channel's owning playlist and its provider category.
struct SportsChannelSourceLabel: View {
    let channel: ResolvedChannel

    var body: some View {
        Group {
            if let text {
                #if os(tvOS)
                    Text(verbatim: text)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel(Text(verbatim: accessibilityText))
                #else
                    Text(verbatim: text)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.quaternary, in: Capsule())
                        .accessibilityLabel(Text(verbatim: accessibilityText))
                #endif
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .leading)
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

/// Clips long channel labels at rest and scrolls them continuously when the
/// channel row is available for interaction.
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
        #if os(iOS) || os(macOS)
            ScrollView(.horizontal, showsIndicators: false) {
                label
                    .padding(.trailing, 8)
            }
            .frame(height: lineHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            .accessibilityLabel(Text(verbatim: text))
        #else
            marqueeBody
        #endif
    }

    #if os(tvOS) || os(visionOS)
        private var marqueeBody: some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .clipped()
        .onPreferenceChange(SportsTextWidthKey.self) { contentWidth = $0 }
        .task(id: isHighlighted) {
            isScrolling = false
            guard isHighlighted else { return }
            #if os(iOS) || os(macOS)
                isScrolling = true
                return
            #endif
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
    #endif

    private var isHighlighted: Bool {
        #if os(iOS) || os(macOS)
            return true
        #elseif os(tvOS) || os(visionOS)
            return isFocused
        #else
            return false
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
