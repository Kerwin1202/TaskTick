import Foundation
import Testing
import TaskTickCore
@testable import TaskTickApp

@Suite("Menu Bar Task List")
@MainActor
struct MenuBarTaskTests {
    private func task(_ name: String, manual: Bool, created: TimeInterval) -> ScheduledTask {
        let task = ScheduledTask(name: name)
        task.isManualOnly = manual
        task.createdAt = Date(timeIntervalSince1970: created)
        return task
    }

    @Test("All seven enabled tasks appear, including the sixth manual script")
    func enabledCountMatchesRows() {
        let scheduled = task("scheduled", manual: false, created: 1)
        scheduled.nextRunAt = Date(timeIntervalSince1970: 100)
        let manual = (1...6).map { task("manual-\($0)", manual: true, created: Double($0)) }
        let disabledManual = task("disabled-manual", manual: true, created: 10)
        let disabledScheduled = task("disabled-scheduled", manual: false, created: 10)
        disabledManual.isEnabled = false
        disabledScheduled.isEnabled = false
        let tasks = [scheduled] + manual + [disabledManual, disabledScheduled]

        let displayed = MenuBarView.scheduledTasks(from: tasks) + MenuBarView.manualTasks(from: tasks)
        #expect(displayed.count == 7)
        #expect(Set(displayed.map(\.id)) == Set(tasks.filter(\.isEnabled).map(\.id)))
    }

    @Test("Running a manual script does not change its position")
    func manualRunDoesNotReorder() {
        let old = task("old", manual: true, created: 1)
        let new = task("new", manual: true, created: 2)
        let tasks = [old, new]
        let before = MenuBarView.manualTasks(from: tasks).map(\.id)

        old.lastManualRunAt = Date(timeIntervalSince1970: 100)
        old.lastRunAt = Date(timeIntervalSince1970: 101)

        #expect(MenuBarView.manualTasks(from: tasks).map(\.id) == before)
        #expect(MenuBarView.manualTasks(from: tasks).map(\.name) == ["new", "old"])
    }

    @Test("Manual order is deterministic when creation times match")
    func manualCreationTies() {
        let first = task("first", manual: true, created: 1)
        let second = task("second", manual: true, created: 1)
        first.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        #expect(MenuBarView.manualTasks(from: [second, first]).map(\.id)
                == MenuBarView.manualTasks(from: [first, second]).map(\.id))
    }

    @Test("Scheduled list keeps more than three tasks and tasks with no next run")
    func scheduledTasksAreNotTruncated() {
        let tasks = (1...5).map { index in
            let task = task("scheduled-\(index)", manual: false, created: Double(index))
            task.nextRunAt = Date(timeIntervalSince1970: Double(index * 100))
            return task
        }
        tasks[0].nextRunAt = nil

        let displayed = MenuBarView.scheduledTasks(from: tasks)
        #expect(displayed.count == 5)
        #expect(displayed.map(\.name) == ["scheduled-2", "scheduled-3", "scheduled-4", "scheduled-5", "scheduled-1"])
    }

    @Test("Scheduled order is deterministic when next-run and creation times match")
    func scheduledDateTies() {
        let first = task("first", manual: false, created: 1)
        let second = task("second", manual: false, created: 1)
        first.nextRunAt = Date(timeIntervalSince1970: 100)
        second.nextRunAt = first.nextRunAt
        first.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        second.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!

        #expect(MenuBarView.scheduledTasks(from: [second, first]).map(\.id)
                == MenuBarView.scheduledTasks(from: [first, second]).map(\.id))
    }
}
