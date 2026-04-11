import Foundation
import AppleBridgeCore
import AppleSharedUI

struct ReviewRuntimePreferences: Equatable {
    var showRemainingDueCounts = false
    var showIntervalsOnButtons = false
    var hideAudioPlayButtons = false
    var interruptAudioWhenAnswering = false
    var timeLimitSecs: UInt32 = 0

    init() {}

    init(reviewing: Anki_Config_Preferences.Reviewing) {
        showRemainingDueCounts = reviewing.showRemainingDueCounts
        showIntervalsOnButtons = reviewing.showIntervalsOnButtons
        hideAudioPlayButtons = reviewing.hideAudioPlayButtons
        interruptAudioWhenAnswering = reviewing.interruptAudioWhenAnswering
        timeLimitSecs = reviewing.timeLimitSecs
    }
}
