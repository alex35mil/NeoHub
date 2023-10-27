import SwiftUI

struct AboutView: View {
    static let defaultWidth: CGFloat = 300
    static let defaultHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
            Text(APP_NAME)
                .font(.title)
            if #available(macOS 14, *) {
                Text("Version \(APP_VERSION) (\(APP_BUILD))")
                    .foregroundColor(.gray)
                    .selectionDisabled(false)
            } else {
                Text("Version \(APP_VERSION) (\(APP_BUILD))")
                    .foregroundColor(.gray)
            }
            VStack {
                Text("© 2023 Alex Fedoseev")
                HStack(spacing: 1) {
                    Text("Icon by ")
                    Link(
                        "u/danbee",
                        destination: URL(string: "https://www.reddit.com/user/danbee/")!
                    )
                    .focusable(false)
                }
            }
            .font(.caption)
        }
        .padding()
        .frame(width: Self.defaultWidth, height: Self.defaultHeight)
    }
}
