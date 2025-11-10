import SwiftUI

struct TBTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black.opacity(0.2))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(TBTheme.offWhite.opacity(0.25), lineWidth: 1)
            )
            .foregroundStyle(TBTheme.offWhite)
    }
}
