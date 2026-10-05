import SwiftUI

/// Bottom-trailing tick on a selected tile, Photos-style.
struct SelectionCheckmark: View {
    let isSelected: Bool

    var body: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? Theme.Color.accent : .white, isSelected ? .white : .clear)
            .shadow(color: .black.opacity(0.3), radius: 2)
            .padding(6)
    }
}

/// Replaces a grid screen's normal top bar while selecting.
struct SelectionTopBar: View {
    let count: Int
    let onDone: () -> Void

    var body: some View {
        HStack {
            Text(count == 0 ? "Select Items" : "\(count) Selected")
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Color.primaryText)
            Spacer()
            Button("Done", action: onDone)
                .font(Theme.Font.body(15, weight: .medium))
                .foregroundStyle(Theme.Color.accent)
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}

struct SelectionActionBar: View {
    let count: Int
    let removeTitle: String
    let onAdd: () -> Void
    let onRemove: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            action("Add to Closet", systemImage: "plus.rectangle.on.rectangle", action: onAdd)
            action(removeTitle, systemImage: "minus.rectangle", action: onRemove)
            action("Edit Tags", systemImage: "tag", action: onEdit)
            action("Delete", systemImage: "trash", tint: .red, action: onDelete)
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
        .background(Theme.Color.background)
        .overlay(alignment: .top) {
            Rectangle().fill(Theme.Color.divider).frame(height: 0.5)
        }
        .disabled(count == 0)
        .opacity(count == 0 ? 0.4 : 1)
    }

    private func action(
        _ title: String,
        systemImage: String,
        tint: Color = Theme.Color.accent,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemImage)
                    .font(.system(size: 18))
                Text(title)
                    .font(Theme.Font.body(10, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}
