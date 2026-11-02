//
//  TVCategoryRail.swift
//  Lume
//
//  The tvOS Live TV category sidebar: virtual collections followed by each
//  IPTV provider's categories, beside the channel list or guide.
//

#if os(tvOS)
    import SwiftUI

    /// The Live TV categories as a `TVSidebarRail`: the virtual collections,
    /// the Recordings entry, then the provider's categories.
    struct TVCategoryRail: View {
        let sections: [LiveTVSection]
        let categoryGroups: [LiveTVCategoryGroup]
        @Binding var selectedSection: LiveTVSection?
        /// Fired when the user activates (clicks) a category.
        var onCategoryActivated: () -> Void = {}
        var onRefreshAll: () -> Void = {}
        /// The Recordings entry, below the virtual collections and above the
        /// first category; nil hides it.
        var recordings: TVCategoryRailRecordingsEntry?
        /// Told whether focus is inside the rail, for the tab-bar entry catcher.
        @Environment(TVLiveTVFocusRegions.self) private var focusRegions: TVLiveTVFocusRegions?

        var body: some View {
            TVSidebarRail(items: items, selectedID: selectedID, usesGlass: false) { isFocused in
                if let focusRegions, focusRegions.railFocused != isFocused {
                    focusRegions.railFocused = isFocused
                }
            }
        }

        /// Visual order is focus order: virtual collections, Recordings, then
        /// categories grouped under each IPTV provider.
        private var items: [TVSidebarRailItem] {
            let pinnedCount = sections.prefix(while: \.isVirtual).count
            var items = [TVSidebarRailItem(
                id: "lume.liveSection.refreshAll",
                title: Text("Refresh All"),
                icon: "arrow.clockwise",
                iconLeading: true,
                action: onRefreshAll
            )]
            items += sections.prefix(pinnedCount).map(categoryItem)
            if let recordings {
                items.append(TVSidebarRailItem(
                    id: TVCategoryRailRecordingsEntry.id,
                    title: Text("Recordings"),
                    icon: recordings.isLocked ? "crown" : "recordingtape",
                    action: recordings.onActivate
                ))
            }
            for group in categoryGroups {
                items.append(TVSidebarRailItem(
                    id: "provider-header-\(group.id)",
                    title: Text(group.title),
                    icon: group.isLocked ? "crown.fill" : nil,
                    isHeader: true,
                    action: {}
                ))
                items += group.sections.map(categoryItem)
            }
            return items
        }

        /// The row that reads as selected: Recordings while its library shows,
        /// else the selected category.
        private var selectedID: String? {
            recordings?.isSelected == true ? TVCategoryRailRecordingsEntry.id : selectedSection?.id
        }

        private func categoryItem(_ section: LiveTVSection) -> TVSidebarRailItem {
            TVSidebarRailItem(id: section.id, title: section.titleText, icon: section.icon, iconLeading: true) {
                selectedSection = section
                onCategoryActivated()
            }
        }
    }

    /// The Recordings row under the virtual collections, shown while a
    /// recording server is paired and Settings › Live TV lists it in the rail.
    /// Locked (no Lume Pro) it carries the crown.
    struct TVCategoryRailRecordingsEntry {
        static let id = "lume.liveSection.recordings"

        let isSelected: Bool
        let isLocked: Bool
        let onActivate: () -> Void
    }
#endif
