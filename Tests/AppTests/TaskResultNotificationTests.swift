import AppKit
import SwiftUI
import XCTest
@testable import TaskTickApp

final class TaskResultNotificationTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "test.taskResultNotification.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testExistingUsersAndUnknownValuesKeepSystemNotifications() {
        XCTAssertEqual(TaskResultNotificationStyle.current(defaults), .system)
        XCTAssertNil(resultToast(succeeded: true))

        defaults.set("unknown", forKey: TaskResultNotificationStyle.settingKey)
        XCTAssertEqual(TaskResultNotificationStyle.current(defaults), .system)
        XCTAssertNil(resultToast(succeeded: false))
    }

    func testChangingStyleAppliesToNextResultAndKeepsItsContent() throws {
        defaults.set(TaskResultNotificationStyle.bottom.rawValue, forKey: TaskResultNotificationStyle.settingKey)
        // Read through a fresh defaults instance, as after reopening settings.
        let reloaded = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        XCTAssertEqual(TaskResultNotificationStyle.current(reloaded), .bottom)

        let success = try XCTUnwrap(resultToast(succeeded: true))
        XCTAssertEqual(success.title, "[Success] Backup")
        XCTAssertEqual(success.message, "Duration: 2s\nCustom output")
        XCTAssertEqual(success.icon, .success)
        XCTAssertEqual(success.duration, 5)

        let failure = try XCTUnwrap(resultToast(succeeded: false))
        XCTAssertEqual(failure.icon, .error)
        XCTAssertEqual(failure.message, success.message)

        defaults.set(TaskResultNotificationStyle.system.rawValue, forKey: TaskResultNotificationStyle.settingKey)
        XCTAssertNil(resultToast(succeeded: true))
    }

    @MainActor
    func testLongResultFitsInsideBottomOverlay() {
        let descriptor = ToastDescriptor(
            message: String(repeating: "运行结果内容很长，需要换行显示。\n", count: 20),
            icon: .success,
            duration: 5,
            title: String(repeating: "很长的任务名称", count: 20)
        )
        let host = NSHostingView(rootView: ToastView(descriptor: descriptor))
        let size = host.fittingSize
        XCTAssertGreaterThan(size.height, 38, "Result should have room for both title and body")
        XCTAssertLessThanOrEqual(size.width, 520)
        XCTAssertLessThanOrEqual(size.height, 160 - ToastHost.bottomInset)
    }

    private func resultToast(succeeded: Bool) -> ToastDescriptor? {
        NotificationManager.taskResultToast(
            title: "[Success] Backup",
            body: "Duration: 2s\nCustom output",
            succeeded: succeeded,
            defaults: defaults
        )
    }
}
