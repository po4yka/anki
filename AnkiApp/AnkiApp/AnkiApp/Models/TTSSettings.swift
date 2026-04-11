import AppleBridgeCore
import AppleSharedUI
import SwiftUI

@Observable
@MainActor
final class TTSSettings {
    @ObservationIgnored
    @AppStorage("ttsEnabled") var isEnabled: Bool = true

    @ObservationIgnored
    @AppStorage("ttsAutoPlay") var autoPlay: Bool = true
}
