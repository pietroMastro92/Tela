import Foundation

#if canImport(UserNotifications)
import UserNotifications

/// Local notification adapter used by the production timer. Authorization is
/// requested lazily on the first schedule (which corresponds to the first
/// explicit Start action), never during app launch.
public final class UserNotificationService: NSObject, Notifications, @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let defaults: UserDefaults
    private let soundKey: String
    private let enabledKey: String
    private let identifierPrefix: String
    private var didRequestAuthorization = false

    public var soundEnabled: Bool {
        didSet { defaults.set(soundEnabled, forKey: soundKey) }
    }

    public var isEnabled: Bool {
        didSet {
            defaults.set(isEnabled, forKey: enabledKey)
            if !isEnabled { cancel() }
        }
    }

    public init(
        center: UNUserNotificationCenter = .current(),
        defaults: UserDefaults = .standard,
        soundEnabled: Bool? = nil,
        isEnabled: Bool? = nil,
        identifierPrefix: String = "tela.timer"
    ) {
        self.center = center
        self.defaults = defaults
        self.soundKey = "Tela.notifications.soundEnabled"
        self.enabledKey = "Tela.notifications.enabled"
        self.identifierPrefix = identifierPrefix
        self.soundEnabled = soundEnabled ?? defaults.object(forKey: "Tela.notifications.soundEnabled") as? Bool ?? true
        self.isEnabled = isEnabled ?? defaults.object(forKey: "Tela.notifications.enabled") as? Bool ?? true
        super.init()
    }

    public func requestAuthorizationIfNeeded() {
        guard isEnabled else { return }
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        var options: UNAuthorizationOptions = [.alert]
        if soundEnabled { options.insert(.sound) }
        center.requestAuthorization(options: options) { _, _ in }
    }

    public func schedule(deadline: Date, phase: TimerPhase) {
        guard isEnabled else { return }
        requestAuthorizationIfNeeded()
        center.removePendingNotificationRequests(withIdentifiers: [scheduledIdentifier])
        let content = UNMutableNotificationContent()
        content.title = phase == .focus ? "Focus complete" : "Break complete"
        content.body = phase == .focus ? "Time for a break." : "Ready for another focus session."
        if soundEnabled { content.sound = .default }
        content.userInfo = ["phase": phase.rawValue]
        let seconds = max(1, deadline.timeIntervalSinceNow)
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: scheduledIdentifier, content: content, trigger: trigger)
        center.add(request) { _ in }
    }

    public func cancel() {
        center.removePendingNotificationRequests(withIdentifiers: [scheduledIdentifier])
    }

    public func notify(_ notification: TimerNotification) {
        // Scheduling is handled by `schedule`; completion events are exposed
        // for recording adapters and do not create duplicate notifications.
    }

    private var scheduledIdentifier: String { "\(identifierPrefix).scheduled" }
}

#else

/// Build-safe fallback for non-Apple test hosts. Tela's app target uses the
/// UserNotifications implementation above on macOS.
public final class UserNotificationService: Notifications, @unchecked Sendable {
    public var soundEnabled: Bool
    public var isEnabled: Bool
    public init(soundEnabled: Bool = true, isEnabled: Bool = true) {
        self.soundEnabled = soundEnabled
        self.isEnabled = isEnabled
    }
    public func requestAuthorizationIfNeeded() {}
    public func schedule(deadline: Date, phase: TimerPhase) { requestAuthorizationIfNeeded() }
    public func cancel() {}
    public func notify(_ notification: TimerNotification) {}
}

#endif
