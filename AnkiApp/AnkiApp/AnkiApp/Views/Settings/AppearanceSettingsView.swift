import SwiftUI
import AppleBridgeCore
import AppleSharedUI

struct AppearanceSettingsView: View {
    @AppStorage("appearance") private var appearance = "system"

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Color Scheme", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
#if os(macOS)
                .pickerStyle(.radioGroup)
#else
                .pickerStyle(.inline)
#endif
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

#Preview {
    AppearanceSettingsView()
}
