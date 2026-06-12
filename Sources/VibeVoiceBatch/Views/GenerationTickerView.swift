import SwiftUI

struct GenerationTickerView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 7, height: 7)

            Text(store.generationTicker.displayLine)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(textColor)
        .padding(.horizontal, 10)
        .frame(height: 28)
        .background(.black.opacity(0.88), in: RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .stroke(textColor.opacity(store.generationTicker.isActive ? 0.55 : 0.25), lineWidth: 1)
        }
        .accessibilityLabel(store.generationTicker.displayLine)
    }

    private var indicatorColor: Color {
        if store.generationTicker.isProblem {
            return .orange
        }
        return store.generationTicker.isActive ? .green : .gray
    }

    private var textColor: Color {
        if store.generationTicker.isProblem {
            return Color(red: 1.0, green: 0.45, blue: 0.30)
        }
        if store.generationTicker.isActive {
            return Color(red: 0.62, green: 1.0, blue: 0.58)
        }
        return Color(red: 0.70, green: 0.78, blue: 0.68)
    }
}
