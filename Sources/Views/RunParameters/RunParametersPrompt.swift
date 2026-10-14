import AppKit
import SwiftUI
import TaskTickCore

@MainActor
final class RunParametersPrompt: NSObject, NSWindowDelegate {
    static let shared = RunParametersPrompt()

    private struct Request {
        let taskID: UUID
        let taskName: String
        let configuration: RunParametersConfiguration
        let preview: Bool
        let continuation: CheckedContinuation<[RunParameterValue]?, Never>
    }

    private var requests: [Request] = []
    private var active: Request?
    private var window: NSWindow?

    func choose(taskID: UUID, taskName: String, configuration: RunParametersConfiguration, preview: Bool = false) async -> [RunParameterValue]? {
        await withCheckedContinuation { continuation in
            requests.append(Request(taskID: taskID, taskName: taskName, configuration: configuration, preview: preview, continuation: continuation))
            showNext()
        }
    }

    func focus(taskID: UUID) {
        guard active?.taskID == taskID else { return }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func showNext() {
        guard active == nil, !requests.isEmpty else { return }
        let request = requests.removeFirst()
        active = request
        let screen = NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
            styleMask: [.titled, .closable], backing: .buffered, defer: false
        )
        window.title = request.preview
            ? L10n.tr("run_parameters.preview")
            : "\(L10n.tr("run_parameters.confirm_title")) · \(request.taskName)"
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .modalPanel
        let host = NSHostingController(rootView: RunParametersPromptView(
            configuration: request.configuration,
            preview: request.preview,
            window: window,
            onFinish: { [weak self] in self?.finish($0) }
        ).localized())
        host.sizingOptions = .preferredContentSize
        host.safeAreaRegions = []
        window.contentViewController = host
        host.view.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: 480, height: max(180, host.view.fittingSize.height)))
        self.window = window
        NSApp.setActivationPolicy(.regular)
        if let visibleFrame = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(
                x: visibleFrame.midX - window.frame.width / 2,
                y: visibleFrame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func finish(_ values: [RunParameterValue]?) {
        guard let request = active else { return }
        active = nil
        let oldWindow = window
        window = nil
        oldWindow?.delegate = nil
        MenuBarHideNotice.suppressBriefly()
        oldWindow?.close()
        oldWindow?.contentViewController = nil
        request.continuation.resume(returning: values)
        DispatchQueue.main.async { [weak self] in self?.showNext() }
    }

    func windowWillClose(_ notification: Notification) {
        finish(nil)
    }

    func cancel(taskID: UUID) {
        let waiting = requests.filter { $0.taskID == taskID }
        requests.removeAll { $0.taskID == taskID }
        for request in waiting { request.continuation.resume(returning: nil) }
        if active?.taskID == taskID { finish(nil) }
    }

    func cancelAll() {
        let waiting = requests
        requests.removeAll()
        for request in waiting { request.continuation.resume(returning: nil) }
        finish(nil)
    }
}

private struct RunParametersPromptView: View {
    let configuration: RunParametersConfiguration
    let preview: Bool
    let window: NSWindow
    let onFinish: ([RunParameterValue]?) -> Void

    @State private var inputs: [UUID: String] = [:]
    @State private var remaining = 0
    @State private var countdownCancelled = false
    @State private var contentHeight: CGFloat = 1
    @State private var showingError = false
    @State private var timer: Task<Void, Never>?
    @State private var keyMonitor: Any?
    @FocusState private var focusedTextParameter: UUID?

    private var isCountingDown: Bool {
        remaining > 0 && !countdownCancelled
    }

    private var maximumContentHeight: CGFloat {
        let screenHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height ?? 800
        return min(360, max(120, screenHeight - 260))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(configuration.parameters) { parameter in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(parameter.name).font(.subheadline.weight(.semibold))
                            if parameter.kind == .choice {
                                VStack(spacing: 8) {
                                    ForEach(parameter.options) { option in
                                        optionCard(option, for: parameter)
                                    }
                                }
                            } else {
                                TextField(parameter.name, text: inputBinding(for: parameter))
                                    .labelsHidden()
                                    .textFieldStyle(.roundedBorder)
                                    .focused($focusedTextParameter, equals: parameter.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(1)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
            .frame(height: min(contentHeight, maximumContentHeight))
            .scrollBounceBehavior(.basedOnSize)

            if preview {
                Text(L10n.tr("run_parameters.preview_hint"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 6) {
                if isCountingDown {
                    Label(L10n.tr("run_parameters.remaining", remaining), systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label(L10n.tr(countdownCancelled ? "run_parameters.paused" : "run_parameters.confirm_hint"),
                          systemImage: countdownCancelled ? "pause.circle" : "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isCountingDown {
                    ProgressView(value: Double(remaining), total: Double(configuration.autoRunSeconds))
                        .progressViewStyle(.linear)
                        .controlSize(.small)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            if showingError {
                Text(L10n.tr("run_parameters.error.input")).font(.caption).foregroundStyle(.red)
            }
            Divider()
            HStack(spacing: 8) {
                Button(L10n.tr(preview ? "editor.cancel" : "run_parameters.cancel_run")) { onFinish(nil) }
                    .pointerCursor()
                Spacer()
                if configuration.autoRunSeconds > 0 {
                    Button(L10n.tr("run_parameters.cancel_countdown"), systemImage: "pause") { cancelCountdown() }
                        .disabled(!isCountingDown)
                        .pointerCursor()
                }
                Button(L10n.tr(preview ? "run_parameters.confirm" : "run_parameters.run_now")) { confirm() }
                    .buttonStyle(.borderedProminent)
                    .pointerCursor()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(width: 480)
        .background(Color(nsColor: .windowBackgroundColor))
        .fixedSize(horizontal: false, vertical: true)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            // Keep the current center when resizing, including after a user drag.
            if abs(window.contentLayoutRect.height - size.height) > 0.5 {
                var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
                frame.origin = NSPoint(
                    x: window.frame.midX - frame.width / 2,
                    y: window.frame.midY - frame.height / 2
                )
                window.setFrame(frame, display: true)
            }
        }
        .onAppear {
            installKeyMonitor()
            if let parameter = configuration.parameters.first(where: { $0.kind == .text }) {
                focusedTextParameter = parameter.id
            }
            remaining = configuration.autoRunSeconds
            if remaining > 0 {
                timer = Task { @MainActor in
                    while remaining > 0 && !Task.isCancelled {
                        do { try await Task.sleep(for: .seconds(1)) } catch { return }
                        guard !Task.isCancelled, !countdownCancelled else { return }
                        // Start counting only after the prompt is displayed.
                        guard window.isVisible else { continue }
                        if let client = window.firstResponder as? NSTextInputClient, client.hasMarkedText() {
                            cancelCountdown()
                            return
                        }
                        remaining -= 1
                    }
                    if !Task.isCancelled && !countdownCancelled { confirm() }
                }
            }
        }
        .onDisappear {
            timer?.cancel()
            if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
            keyMonitor = nil
        }
    }

    private func optionCard(_ option: RunParameterOption, for parameter: RunParameter) -> some View {
        let selected = inputValue(for: parameter) == option.id.uuidString
        return Button {
            inputBinding(for: parameter).wrappedValue = option.id.uuidString
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(option.label).font(.subheadline.weight(.medium))
                        Spacer()
                        if option.id == parameter.defaultOption?.id {
                            Text(L10n.tr("run_parameters.default"))
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.1), in: Capsule())
                        }
                    }
                    Text(option.value)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(selected ? Color.accentColor.opacity(0.08) : Color(nsColor: .textBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10)
                .stroke(selected ? Color.accentColor.opacity(0.6) : Color(nsColor: .separatorColor))
                .allowsHitTesting(false))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .pointerCursor()
        .help(option.value)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func inputValue(for parameter: RunParameter) -> String {
        inputs[parameter.id] ?? (parameter.kind == .choice
            ? parameter.defaultOption?.id.uuidString ?? ""
            : parameter.defaultText)
    }

    private func inputBinding(for parameter: RunParameter) -> Binding<String> {
        Binding(
            get: { inputValue(for: parameter) },
            set: {
                guard $0 != inputValue(for: parameter) else { return }
                cancelCountdown()
                inputs[parameter.id] = $0
                showingError = false
            }
        )
    }

    private func cancelCountdown() {
        guard configuration.autoRunSeconds > 0 else { return }
        countdownCancelled = true
        timer?.cancel()
    }

    private func confirm() {
        guard let values = configuration.resolve(inputs: inputs) else {
            cancelCountdown()
            showingError = true
            return
        }
        timer?.cancel()
        onFinish(values)
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard NSApp.keyWindow === window else { return event }
            if let client = window.firstResponder as? NSTextInputClient, client.hasMarkedText() {
                cancelCountdown()
                return event
            }
            // A single choice parameter also supports the script-style 1/2/3
            // and arrow keys. Text fields keep their normal editing keys.
            if configuration.parameters.count == 1,
               let parameter = configuration.parameters.first, parameter.kind == .choice,
               focusedTextParameter == nil,
               event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
                let current = parameter.options.firstIndex { $0.id.uuidString == inputValue(for: parameter) } ?? 0
                var next: Int?
                if event.keyCode == 125 { next = (current + 1) % parameter.options.count }
                if event.keyCode == 126 { next = (current - 1 + parameter.options.count) % parameter.options.count }
                if let digit = Int(event.charactersIgnoringModifiers ?? ""), (1...min(9, parameter.options.count)).contains(digit) {
                    next = digit - 1
                }
                if let next {
                    inputBinding(for: parameter).wrappedValue = parameter.options[next].id.uuidString
                    return nil
                }
            }
            switch event.keyCode {
            case 36, 76:
                if !event.isARepeat { confirm() }
                return nil
            case 53:
                onFinish(nil)
                return nil
            default:
                return event
            }
        }
    }
}
