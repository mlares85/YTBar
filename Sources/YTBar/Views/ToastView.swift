import SwiftUI

enum ToastStyle {
    case error, success, info

    var color: Color {
        switch self {
        case .error: return .red
        case .success: return .green
        case .info: return .blue
        }
    }

    var icon: String {
        switch self {
        case .error: return "exclamationmark.triangle.fill"
        case .success: return "checkmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

struct Toast: Identifiable, Equatable {
    let id: UUID
    let style: ToastStyle
    let message: String
    let detail: String?
}

struct ToastView: View {
    let toast: Toast
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onDismiss) {
            HStack(spacing: 8) {
                Image(systemName: toast.style.icon)
                    .foregroundStyle(toast.style.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(toast.message)
                        .font(.system(size: 12, weight: .medium))
                    if let detail = toast.detail {
                        Text(detail)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(toast.style.color.opacity(0.4), lineWidth: 1)
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(toast.message)
        .accessibilityHint("Tap to dismiss")
    }
}
