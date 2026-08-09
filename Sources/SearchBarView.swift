import SwiftUI

// MARK: - Search Bar

struct SearchBarView: View {
    @Binding var query: String
    let onSearch: (String) -> Void
    let language: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 12))

            TextField(L10n.t("search_placeholder", language: language), text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .onChange(of: query) { newValue in
                    onSearch(newValue)
                }

            if !query.isEmpty {
                Button(action: { query = ""; onSearch("") }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
        .cornerRadius(6)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }
}
