import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(spacing: 28) {
            Text("Inline Rewriter")
                .font(.system(size: 24, weight: .bold))

            Image("AppIconImage")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 200, height: 200)

            Text("Made with \u{1FA77} by Kevin")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            Button("Settings…") {
                WelcomeWindowController.shared.close()
                SettingsWindowController.shared.showSettings()
            }
        }
        .padding(80)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
