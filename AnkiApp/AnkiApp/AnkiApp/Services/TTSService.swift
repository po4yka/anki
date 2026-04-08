import AVFoundation

actor TTSService {
    private let synthesizer = AVSpeechSynthesizer()
    private let delegate = Delegate()

    init() {
        synthesizer.delegate = delegate
    }

    func speak(tag: Anki_CardRendering_TTSTag) async {
        let text = stripHTML(tag.fieldText)
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        guard let voice = resolveVoice(lang: tag.lang, preferredVoices: tag.voices) else { return }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = clampedRate(tag.speed)

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            delegate.onFinish = { continuation.resume() }
            synthesizer.speak(utterance)
        }
    }

    func stop() {
        delegate.onFinish?()
        delegate.onFinish = nil
        synthesizer.stopSpeaking(at: .immediate)
    }

    var isSpeaking: Bool {
        synthesizer.isSpeaking
    }

    // MARK: - Voice Resolution

    private func resolveVoice(lang: String, preferredVoices: [String]) -> AVSpeechSynthesisVoice? {
        let allVoices = AVSpeechSynthesisVoice.speechVoices()

        for preferred in preferredVoices where !preferred.isEmpty {
            let lowered = preferred.lowercased()
            if let match = allVoices.first(where: { $0.name.lowercased().contains(lowered) }) {
                return match
            }
        }

        if !lang.isEmpty {
            let normalizedLang = lang.replacingOccurrences(of: "_", with: "-")
            if let voice = AVSpeechSynthesisVoice(language: normalizedLang) {
                return voice
            }
        }

        return AVSpeechSynthesisVoice(language: AVSpeechSynthesisVoice.currentLanguageCode())
    }

    // MARK: - Helpers

    private func clampedRate(_ speed: Float) -> Float {
        let rate = AVSpeechUtteranceDefaultSpeechRate * (speed > 0 ? speed : 1.0)
        return min(max(rate, AVSpeechUtteranceMinimumSpeechRate), AVSpeechUtteranceMaximumSpeechRate)
    }

    private func stripHTML(_ text: String) -> String {
        guard text.contains("<") else { return text }
        let stripped = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        return stripped
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
    }
}

// MARK: - Delegate

extension TTSService {
    final class Delegate: NSObject, AVSpeechSynthesizerDelegate, Sendable {
        nonisolated(unsafe) var onFinish: (() -> Void)?

        func speechSynthesizer(_: AVSpeechSynthesizer, didFinish _: AVSpeechUtterance) {
            onFinish?()
            onFinish = nil
        }

        func speechSynthesizer(_: AVSpeechSynthesizer, didCancel _: AVSpeechUtterance) {
            onFinish?()
            onFinish = nil
        }
    }
}
