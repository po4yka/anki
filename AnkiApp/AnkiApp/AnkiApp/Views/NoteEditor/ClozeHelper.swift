import AppleBridgeCore
import AppleSharedUI
import Foundation

enum ClozeHelper {
    static func insertCloze(into text: String, at range: NSRange, number: Int) -> String {
        guard let swiftRange = Range(range, in: text) else {
            return text + "{{c\(number)::\(text)}}"
        }
        let selected = String(text[swiftRange])
        let cloze = "{{c\(number)::\(selected)}}"
        var result = text
        result.replaceSubrange(swiftRange, with: cloze)
        return result
    }

    static func nextClozeNumber(existing: [Int]) -> Int {
        guard let max = existing.max() else { return 1 }
        return max + 1
    }
}
