import Foundation
import SwiftData
import TaskTickCore

/// Every user-facing run/restart goes through the same preparation step.
/// Scheduled execution still calls ScriptExecutor directly with default values.
@MainActor
final class ManualTaskRunner {
    static let shared = ManualTaskRunner()
    private var pendingTaskIDs = Set<UUID>()

    func run(
        task: ScheduledTask,
        modelContext: ModelContext,
        restart: Bool = false,
        promptUser: Bool = true,
        forceBanner: Bool = false,
        recordLauncherUsage: Bool = false
    ) async {
        let taskID = task.id
        guard pendingTaskIDs.insert(taskID).inserted else {
            RunParametersPrompt.shared.focus(taskID: taskID)
            return
        }
        var preparing = true
        defer { if preparing { pendingTaskIDs.remove(taskID) } }
        guard restart || !TaskScheduler.shared.runningTaskIDs.contains(taskID) else { return }

        let configuration = (task.shortcutName?.isEmpty ?? true) ? task.runParametersConfiguration : nil
        var values: [RunParameterValue]?
        if promptUser, let configuration, configuration.isEnabled {
            if let error = configuration.validationError() {
                ActionToast.notify(.failed(taskName: task.name, reason: error), taskId: taskID, wantsBanner: true)
                return
            }
            values = await RunParametersPrompt.shared.choose(taskID: taskID, taskName: task.name, configuration: configuration)
            guard values != nil, task.modelContext != nil, !Task.isCancelled else { return }
            guard task.runParametersConfiguration == configuration else {
                ActionToast.notify(.failed(taskName: task.name, reason: L10n.tr("run_parameters.error.changed")), taskId: taskID, wantsBanner: true)
                return
            }
        }

        guard task.modelContext != nil, !Task.isCancelled else { return }
        let wasRunning = TaskScheduler.shared.runningTaskIDs.contains(taskID)
        if wasRunning {
            guard restart else { return }
            let oldProcess = ScriptExecutor.shared.runningProcesses[taskID]
            let adoptedPID = ScriptExecutor.shared.adoptedProcesses[taskID]
            ScriptExecutor.shared.cancel(taskId: taskID)
            // Wait for the old execution to finish before its cleanup can race
            // with the replacement process. Cancelling the prompt never gets here.
            func isStopping() -> Bool {
                TaskScheduler.shared.runningTaskIDs.contains(taskID)
                    || oldProcess?.isRunning == true
                    || adoptedPID.map { ProcessReconciler.isAlive(pid: $0) } == true
            }
            for _ in 0..<50 where isStopping() {
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            guard !isStopping() else {
                ActionToast.notify(.failed(taskName: task.name, reason: L10n.tr("run_parameters.error.stopping")), taskId: taskID, wantsBanner: true)
                return
            }
        }
        guard task.modelContext != nil, !Task.isCancelled else { return }
        if promptUser, let configuration, configuration.isEnabled,
           task.runParametersConfiguration != configuration {
            ActionToast.notify(.failed(taskName: task.name, reason: L10n.tr("run_parameters.error.changed")), taskId: taskID, wantsBanner: true)
            return
        }
        pendingTaskIDs.remove(taskID)
        preparing = false
        if recordLauncherUsage { QuickLauncherUsage.markUsed(taskID) }
        let name = task.name
        let wantsBanner = forceBanner || task.notifyOnAction
        if restart {
            ActionToast.notify(.restarted(taskName: name), taskId: taskID, wantsBanner: wantsBanner)
            ToastCenter.shared.running(L10n.tr("toast.task.restarted", name))
        } else {
            ActionToast.notify(.started(taskName: name), taskId: taskID, wantsBanner: wantsBanner)
            ToastCenter.shared.running(L10n.tr("toast.task.started", name))
        }
        await ScriptExecutor.shared.execute(task: task, modelContext: modelContext, parameterValues: values)
    }
}
