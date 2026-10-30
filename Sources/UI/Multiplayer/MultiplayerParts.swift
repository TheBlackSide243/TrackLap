import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Your name and vehicle, as friends see them on shared laps, in the group and in the leaderboards.
struct ProfileFields: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let p = model.profile
        VStack(spacing: 10) {
            field(L("Il tuo nome"), "person.fill", Binding(get: { p.name }, set: { p.set(name: $0) }))
            field(L("Auto o moto (facoltativo)"), "car.fill", Binding(get: { p.vehicle }, set: { p.set(vehicle: $0) }))
        }
    }

    private func field(_ prompt: String, _ icon: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 22)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .foregroundStyle(Theme.text)
                .onSubmit { model.group.profileChanged() }
        }
        .padding(12)
        .background(Theme.input, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// One colour per member of the group, in the order they joined; you are always the accent.
enum GroupColors {
    static let all: [Color] = [Theme.yellow, Theme.purple, Theme.good, Color(rgb: 255, 146, 72),
                               Color(rgb: 244, 114, 182), Color(rgb: 96, 165, 250)]

    static func color(_ i: Int?) -> Color { i.map { all[$0 % all.count] } ?? Theme.accent }
}

/// A QR code, black on white, sharp at any size.
struct QRCodeView: View {
    let text: String

    var body: some View {
        if let image = Self.image(text) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(14)
                .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private static func image(_ text: String) -> UIImage? {
        let f = CIFilter.qrCodeGenerator()
        f.message = Data(text.utf8)
        f.correctionLevel = "M"
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
