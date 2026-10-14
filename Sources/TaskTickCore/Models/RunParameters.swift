import Foundation

public enum RunParameterKind: String, Codable, CaseIterable, Sendable {
    case choice, text

    public var displayName: String {
        L10n.tr(self == .choice ? "run_parameters.choice" : "run_parameters.text")
    }
}

public struct RunParameterOption: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var value: String

    public init(label: String = "", value: String = "") {
        id = UUID()
        self.label = label
        self.value = value
    }
}

public struct RunParameter: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var variableName: String
    public var kind: RunParameterKind
    public var options: [RunParameterOption]
    public var defaultOptionID: UUID?
    public var defaultText: String

    public init() {
        id = UUID()
        name = L10n.tr("run_parameters.parameter")
        variableName = "TASKTICK_VALUE"
        kind = .choice
        options = [
            RunParameterOption(label: L10n.tr("run_parameters.option_n", 1), value: "option1"),
            RunParameterOption(label: L10n.tr("run_parameters.option_n", 2), value: "option2"),
        ]
        defaultOptionID = options.first?.id
        defaultText = ""
    }

    public var defaultOption: RunParameterOption? {
        options.first { $0.id == defaultOptionID } ?? options.first
    }
}

/// Configuration is JSON-backed so existing SwiftData stores gain only one
/// optional column. Parameter values are passed through Process.environment.
public struct RunParametersConfiguration: Codable, Equatable, Sendable {
    public var isEnabled = false
    /// Zero disables automatic confirmation.
    public var autoRunSeconds = 5
    public var parameters: [RunParameter] = [RunParameter()]

    public init() {}

    public func validationError(requireDefaults: Bool = false) -> String? {
        guard isEnabled else { return nil }
        guard !parameters.isEmpty else { return L10n.tr("run_parameters.error.empty") }
        guard (0...300).contains(autoRunSeconds),
              Set(parameters.map(\.id)).count == parameters.count else {
            return L10n.tr("run_parameters.error.configuration")
        }
        var names = Set<String>()
        for parameter in parameters {
            guard !parameter.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  parameter.variableName.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) != nil,
                  names.insert(parameter.variableName).inserted else {
                return L10n.tr("run_parameters.error.variable")
            }
            if parameter.kind == .choice {
                let validOptions = parameter.options.allSatisfy { option in
                    !option.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && !option.value.isEmpty && !option.value.contains("\0")
                }
                guard !parameter.options.isEmpty,
                      Set(parameter.options.map(\.id)).count == parameter.options.count,
                      validOptions else {
                    return L10n.tr("run_parameters.error.options")
                }
            } else if (requireDefaults || autoRunSeconds > 0) && parameter.defaultText.isEmpty {
                return L10n.tr("run_parameters.error.default")
            }
        }
        return nil
    }

    /// Choice inputs store stable option IDs, never row numbers or labels.
    /// Missing inputs use the configured default (automatic execution).
    public func resolve(inputs: [UUID: String] = [:]) -> [RunParameterValue]? {
        guard isEnabled else { return [] }
        guard validationError() == nil else { return nil }
        var result: [RunParameterValue] = []
        for parameter in parameters {
            let value: String
            let label: String?
            if parameter.kind == .choice {
                let option: RunParameterOption?
                if let rawID = inputs[parameter.id] {
                    guard let id = UUID(uuidString: rawID) else { return nil }
                    option = parameter.options.first { $0.id == id }
                } else {
                    option = parameter.defaultOption
                }
                guard let option else { return nil }
                value = option.value
                label = option.label
            } else {
                value = inputs[parameter.id] ?? parameter.defaultText
                label = nil
            }
            guard !value.isEmpty, !value.contains("\0") else { return nil }
            result.append(RunParameterValue(
                name: parameter.name,
                variableName: parameter.variableName,
                value: value,
                optionLabel: label
            ))
        }
        return result
    }
}

public struct RunParameterValue: Codable, Equatable, Sendable {
    public let name: String
    public let variableName: String
    public let value: String
    public let optionLabel: String?
}
