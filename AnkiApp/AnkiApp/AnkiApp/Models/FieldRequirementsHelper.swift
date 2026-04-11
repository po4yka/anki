import Foundation
import AppleBridgeCore
import AppleSharedUI

struct FieldRequirements {
    let requiredFieldIndexes: Set<Int>
    let cardCount: Int
    let emptyRequiredFields: [String]
}

enum FieldRequirementsHelper {
    static func analyze(
        notetype: Anki_Notetypes_Notetype,
        fieldValues: [String]
    ) -> FieldRequirements {
        let reqs = notetype.config.reqs
        var requiredIndexes = Set<Int>()
        var satisfiedCount = 0

        for req in reqs {
            let fieldOrds = req.fieldOrds.map { Int($0) }
            for ord in fieldOrds {
                requiredIndexes.insert(ord)
            }

            let satisfied: Bool = switch req.kind {
                case .any:
                    fieldOrds.contains { isNonEmpty(fieldValues, at: $0) }
                case .all:
                    fieldOrds.allSatisfy { isNonEmpty(fieldValues, at: $0) }
                case .none, .UNRECOGNIZED:
                    false
            }

            if satisfied { satisfiedCount += 1 }
        }

        let fieldNames = notetype.fields.map(\.name)
        let emptyRequired = requiredIndexes.sorted().compactMap { index -> String? in
            guard index < fieldValues.count, !isNonEmpty(fieldValues, at: index) else {
                return nil
            }
            return index < fieldNames.count ? fieldNames[index] : "Field \(index)"
        }

        return FieldRequirements(
            requiredFieldIndexes: requiredIndexes,
            cardCount: satisfiedCount,
            emptyRequiredFields: emptyRequired
        )
    }

    private static func isNonEmpty(_ fields: [String], at index: Int) -> Bool {
        guard index < fields.count else { return false }
        let stripped = fields[index]
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return !stripped.isEmpty
    }
}
