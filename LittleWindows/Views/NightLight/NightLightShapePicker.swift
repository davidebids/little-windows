import SwiftUI

struct NightLightShapePicker: View {
    @Binding var selection: NightLightShape
    @Environment(\.dismiss) private var dismiss

    private let columns = [
        GridItem(.adaptive(minimum: 102), spacing: 12)
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(NightLightShape.selectableCases) { shape in
                        Button {
                            selection = shape
                            dismiss()
                        } label: {
                            VStack(spacing: 10) {
                                if shape == .fullScreenGlow {
                                    Image(systemName: "rectangle.inset.filled")
                                        .font(.title2)
                                        .foregroundStyle(.orange)
                                        .frame(width: 34, height: 34)
                                } else {
                                    NightLightShapeView(
                                        shape: shape,
                                        color: .orange,
                                        softness: 0.35
                                    )
                                    .frame(width: 34, height: 34)
                                }
                                Text(shape.displayName)
                                    .font(.caption2.weight(.medium))
                                    .lineLimit(2)
                                    .minimumScaleFactor(0.82)
                                    .multilineTextAlignment(.center)
                                    .frame(minHeight: 28, alignment: .top)
                            }
                            .foregroundStyle(
                                selection == shape ? Color.black : Color.white
                            )
                            .frame(maxWidth: .infinity, minHeight: 100)
                            .background(
                                selection == shape
                                    ? Color.white
                                    : Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 18)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .background(Color(red: 0.035, green: 0.03, blue: 0.055))
            .navigationTitle("Light Shape")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}
