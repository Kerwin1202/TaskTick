import Foundation

/// Search task names by their original text, full pinyin, or word initials.
public enum TaskNameSearch {

    /// Whether the query appears in the task name or one of its pinyin forms.
    public static func matches(query: String, candidate: String) -> Bool {
        guard !query.isEmpty else { return true }
        if candidate.localizedCaseInsensitiveContains(query) { return true }

        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return false }
        return searchForms(for: candidate).contains {
            normalize($0).contains(normalizedQuery)
        }
    }

    /// Fuzzy score across the task name, full pinyin, and pinyin initials.
    public static func score(query: String, candidate: String) -> Int? {
        searchForms(for: candidate)
            .compactMap { FuzzyMatch.score(query: query, candidate: $0) }
            .max()
    }

    private static func searchForms(for candidate: String) -> [String] {
        guard let latin = candidate.applyingTransform(.toLatin, reverse: false) else {
            return [candidate]
        }

        let folded = latin.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        let words = folded.split { !$0.isLetter && !$0.isNumber }
        guard !words.isEmpty else { return [candidate] }

        let fullPinyin = words.joined()
        let initials = words.compactMap(\.first).map(String.init).joined()
        return [candidate, fullPinyin, initials]
    }

    private static func normalize(_ value: String) -> String {
        value.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        .filter { $0.isLetter || $0.isNumber }
        .lowercased()
    }
}
