import SwiftUI

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
                .pickerStyle(.radioGroup)
            }
        }
        .formStyle(.grouped)
        .padding()
        .preferredColorScheme(colorScheme)
    }

    private var colorScheme: ColorScheme? {
        switch appearance {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}

#Preview {
    AppearanceSettingsView()
}
