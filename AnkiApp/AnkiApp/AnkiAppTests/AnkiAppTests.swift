@testable import AnkiApp
import Testing

struct AnkiAppTests {
    @Test func parsesFieldTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "<div>[[type:Front]]</div>")

        #expect(spec == TypeAnswerSpec(kind: .field(combining: true), fieldName: "Front"))
    }

    @Test func parsesNonCombiningFieldTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "[[type:nc:Back]]")

        #expect(spec == TypeAnswerSpec(kind: .field(combining: false), fieldName: "Back"))
    }

    @Test func parsesClozeTypeAnswer() {
        let spec = TypeAnswerSpec.parse(questionHTML: "<span>[[type:cloze:Text]]</span>")

        #expect(spec == TypeAnswerSpec(kind: .cloze, fieldName: "Text"))
    }

    @Test func ignoresCardsWithoutTypeAnswerMarker() {
        #expect(TypeAnswerSpec.parse(questionHTML: "<div>Front</div>") == nil)
    }
}
