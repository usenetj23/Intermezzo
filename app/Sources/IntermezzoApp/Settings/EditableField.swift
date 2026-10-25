import SwiftUI

/// Text input with a visibly different background and a thin border, so editable
/// values stand apart from plain labels on every surface theme.
struct EditableFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .textFieldStyle(.plain)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.09)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.22), lineWidth: 1))
    }
}

extension TextFieldStyle where Self == EditableFieldStyle {
    static var editable: EditableFieldStyle { EditableFieldStyle() }
}
