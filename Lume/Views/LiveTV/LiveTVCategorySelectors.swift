//
//  LiveTVCategorySelectors.swift
//  Lume
//
//  How the viewer picks a Live TV collection: provider-grouped sidebars on
//  macOS/tvOS and the iOS button-plus-searchable-sheet. Split out of
//  `LiveTVView` to keep that file focused on cross-platform composition.
//

import SwiftData
import SwiftUI

// MARK: - Category Sidebar

struct CategorySidebar: View {
    let sections: [LiveTVSection]
    let categoryGroups: [LiveTVCategoryGroup]
    @Binding var selectedSection: LiveTVSection?

    var body: some View {
        List {
            ForEach(sections.filter(\.isVirtual)) { section in
                sectionRow(section)
            }
            ForEach(categoryGroups) { group in
                Section {
                    ForEach(group.sections) { section in
                        sectionRow(section)
                    }
                } header: {
                    groupHeader(group)
                }
            }
        }
        .listStyle(.plain)
    }

    private func sectionRow(_ section: LiveTVSection) -> some View {
        let isSelected = selectedSection?.id == section.id
        return Button {
            selectedSection = section
        } label: {
            HStack(spacing: 8) {
                if let icon = section.icon {
                    Image(systemName: icon)
                        .font(.subheadline)
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                }
                section.titleText
                    .font(.headline)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.primary)
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
    }

    private func groupHeader(_ group: LiveTVCategoryGroup) -> some View {
        HStack(spacing: 6) {
            Text(group.title)
            if group.isLocked {
                Image(systemName: "crown.fill")
                    .accessibilityHidden(true)
            }
        }
    }
}

// MARK: - iOS Category Bar

#if os(iOS)
    /// iOS category selector. The current section is shown as a single button
    /// that opens a searchable, provider-grouped list of all available sections.
    struct CategoryBar: View {
        let sections: [LiveTVSection]
        let categoryGroups: [LiveTVCategoryGroup]
        @Binding var selectedSection: LiveTVSection?

        @State private var showingPicker = false

        /// The section the button reflects — the user's selection, or the first
        /// available one if that selection has since disappeared (mirrors
        /// `displayedSection(in:)`).
        private var currentSection: LiveTVSection? {
            guard let selectedSection else { return sections.first }
            return sections.first { $0.id == selectedSection.id } ?? sections.first
        }

        var body: some View {
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: 8) {
                    if let icon = currentSection?.icon {
                        Image(systemName: icon)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    (currentSection?.titleText ?? Text("Select a Category"))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(uiColor: .secondarySystemBackground))
            .sheet(isPresented: $showingPicker) {
                CategoryPickerSheet(
                    sections: sections,
                    categoryGroups: categoryGroups,
                    selectedSection: $selectedSection
                )
            }

            Divider()
        }
    }

    /// Searchable list of every Live TV section. Type to filter hundreds of
    /// synced categories down to a handful; the virtual collections stay pinned
    /// at the top while the search field is empty.
    private struct CategoryPickerSheet: View {
        let sections: [LiveTVSection]
        let categoryGroups: [LiveTVCategoryGroup]
        @Binding var selectedSection: LiveTVSection?

        @Environment(\.dismiss) private var dismiss
        @State private var query = ""

        private var filteredVirtualSections: [LiveTVSection] {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            return sections.filter {
                $0.isVirtual && (trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed))
            }
        }

        private var filteredGroups: [LiveTVCategoryGroup] {
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            return categoryGroups.compactMap { group in
                let matchingSections = group.sections.filter {
                    trimmed.isEmpty || $0.title.localizedCaseInsensitiveContains(trimmed)
                }
                guard !matchingSections.isEmpty else { return nil }
                return LiveTVCategoryGroup(
                    id: group.id,
                    title: group.title,
                    isLocked: group.isLocked,
                    sections: matchingSections
                )
            }
        }

        private var hasResults: Bool {
            !filteredVirtualSections.isEmpty || !filteredGroups.isEmpty
        }

        var body: some View {
            NavigationStack {
                List {
                    ForEach(filteredVirtualSections) { section in
                        sectionRow(section)
                    }
                    ForEach(filteredGroups) { group in
                        Section {
                            ForEach(group.sections) { section in
                                sectionRow(section)
                            }
                        } header: {
                            HStack(spacing: 6) {
                                Text(group.title)
                                if group.isLocked {
                                    Image(systemName: "crown.fill")
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemBackground))
                .overlay {
                    if !hasResults {
                        ContentUnavailableView.search(text: query)
                    }
                }
                .searchable(text: $query, prompt: "Search categories")
                .navigationTitle("Categories")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
                .toolbarBackground(.visible, for: .navigationBar)
                .presentationBackground(Color(uiColor: .systemBackground))
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }

        private func sectionRow(_ section: LiveTVSection) -> some View {
            let isSelected = selectedSection?.id == section.id
            return Button {
                selectedSection = section
                dismiss()
            } label: {
                HStack(spacing: 12) {
                    if let icon = section.icon {
                        Image(systemName: icon)
                            .foregroundStyle(.secondary)
                    }
                    section.titleText
                        .foregroundStyle(.primary)
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .fontWeight(.semibold)
                            .foregroundStyle(.tint)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
#endif
