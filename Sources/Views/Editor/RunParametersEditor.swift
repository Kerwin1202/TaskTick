import SwiftUI
import TaskTickCore

struct RunParametersEditor: View {
    @Binding var configuration: RunParametersConfiguration
    var requiresDefaults: Bool
    var onInsertVariable: ((String) -> Void)? = nil
    @State private var previewing = false
    @State private var previewValues: [RunParameterValue] = []
    @State private var previewTaskID = UUID()

    var body: some View {
        Section {
            Toggle(L10n.tr("run_parameters.enable"), isOn: $configuration.isEnabled)
            if configuration.isEnabled {
                ForEach($configuration.parameters) { $parameter in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .bottom, spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.tr("run_parameters.name"))
                                    .font(.subheadline)
                                TextField(L10n.tr("run_parameters.name"), text: $parameter.name)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.tr("run_parameters.kind"))
                                    .font(.subheadline)
                                Picker(L10n.tr("run_parameters.kind"), selection: $parameter.kind) {
                                    ForEach(RunParameterKind.allCases, id: \.self) { kind in
                                        Text(kind.displayName).tag(kind)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                            }
                            .frame(width: 130, alignment: .leading)
                            Button(role: .destructive) {
                                configuration.parameters.removeAll { $0.id == parameter.id }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help(L10n.tr("run_parameters.remove_parameter"))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L10n.tr("run_parameters.variable"))
                                .font(.subheadline)
                            HStack(spacing: 8) {
                                TextField(L10n.tr("run_parameters.variable"), text: $parameter.variableName)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                                if let onInsertVariable {
                                    Button(L10n.tr("run_parameters.insert_variable"), systemImage: "text.insert") {
                                        onInsertVariable(parameter.variableName)
                                    }
                                    .disabled(parameter.variableName.range(of: "^[A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) == nil)
                                    .pointerCursor()
                                }
                            }
                            Text(L10n.tr("run_parameters.reference", "\"${\(parameter.variableName)}\""))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if parameter.kind == .choice {
                            optionRows(for: $parameter)
                        } else {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(L10n.tr("run_parameters.default_value"))
                                    .font(.subheadline)
                                TextField(L10n.tr("run_parameters.default_value"), text: $parameter.defaultText)
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
                Button(L10n.tr("run_parameters.add_parameter"), systemImage: "plus") {
                    var parameter = RunParameter()
                    var suffix = configuration.parameters.count + 1
                    while configuration.parameters.contains(where: { $0.variableName == "TASKTICK_VALUE_\(suffix)" }) {
                        suffix += 1
                    }
                    parameter.variableName = "TASKTICK_VALUE_\(suffix)"
                    configuration.parameters.append(parameter)
                }
                .pointerCursor()

                Toggle(L10n.tr("run_parameters.auto_run"), isOn: Binding(
                    get: { configuration.autoRunSeconds > 0 },
                    set: { configuration.autoRunSeconds = $0 ? 5 : 0 }
                ))
                if configuration.autoRunSeconds > 0 {
                    Stepper(value: $configuration.autoRunSeconds, in: 1...300) {
                        Text(L10n.tr("run_parameters.countdown", configuration.autoRunSeconds))
                    }
                }
                Button(L10n.tr("run_parameters.preview"), systemImage: "play") {
                    previewing = true
                    let snapshot = configuration
                    Task {
                        let values = await RunParametersPrompt.shared.choose(
                            taskID: previewTaskID,
                            taskName: L10n.tr("run_parameters.preview"),
                            configuration: snapshot,
                            preview: true
                        )
                        previewValues = configuration == snapshot ? values ?? [] : []
                        previewing = false
                    }
                }
                .disabled(previewing || configuration.validationError() != nil)
                .pointerCursor()
                if !previewValues.isEmpty {
                    Text(previewValues.map { "\($0.name)：\($0.optionLabel ?? $0.value)" }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.tr("run_parameters.title"))
        } footer: {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.tr("run_parameters.hint"))
                if configuration.isEnabled {
                    Text(L10n.tr("run_parameters.usage_hint"))
                    Text("echo \"${\(configuration.parameters.first?.variableName ?? "VERSION")}\"")
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                    Text(L10n.tr("run_parameters.automatic_hint"))
                    if let error = configuration.validationError(requireDefaults: requiresDefaults) {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }
        }
        .onChange(of: configuration) { _, _ in previewValues = [] }
        .onDisappear { RunParametersPrompt.shared.cancel(taskID: previewTaskID) }
    }

    private func optionRows(for parameter: Binding<RunParameter>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(L10n.tr("run_parameters.default")).frame(width: 34)
                Text(L10n.tr("run_parameters.option_name")).frame(width: 135, alignment: .leading)
                Text(L10n.tr("run_parameters.option_value")).frame(maxWidth: .infinity, alignment: .leading)
                Color.clear.frame(width: 25, height: 1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            ForEach(parameter.options) { $option in
                HStack(spacing: 8) {
                    Button {
                        parameter.wrappedValue.defaultOptionID = option.id
                    } label: {
                        Image(systemName: parameter.wrappedValue.defaultOption?.id == option.id ? "largecircle.fill.circle" : "circle")
                            .foregroundStyle(parameter.wrappedValue.defaultOption?.id == option.id ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .frame(width: 34)
                    .accessibilityLabel(L10n.tr("run_parameters.use_default", option.label))
                    TextField(L10n.tr("run_parameters.option_name"), text: $option.label)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 135)
                    TextField(L10n.tr("run_parameters.option_value"), text: $option.value)
                        .labelsHidden()
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                    Button {
                        let id = option.id
                        parameter.wrappedValue.options.removeAll { $0.id == id }
                        if parameter.wrappedValue.defaultOptionID == id {
                            parameter.wrappedValue.defaultOptionID = parameter.wrappedValue.options.first?.id
                        }
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 25)
                    .disabled(parameter.wrappedValue.options.count < 2)
                    .help(L10n.tr("run_parameters.remove_option"))
                }
            }
            Button(L10n.tr("run_parameters.add_option"), systemImage: "plus") {
                parameter.wrappedValue.options.append(RunParameterOption())
            }
            .pointerCursor()
            .padding(.leading, 42)
        }
    }
}
