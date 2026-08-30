import Foundation

/// The deliberately small cross-process command vocabulary for arranging the
/// running Blink desk. Durable note content still travels through the files;
/// these commands only address live panel state owned by the app.
public enum BlinkDeskCommand {
    public static let notificationName = Notification.Name("dev.arach.blink.desk-command")
    public static let responseNotificationName = Notification.Name(
        "dev.arach.blink.desk-command-response"
    )

    public enum Verb: String, Sendable {
        case open
        case move
        case focus
        case close
    }

    public enum Key {
        public static let verb = "verb"
        public static let noteID = "noteID"
        public static let requestID = "requestID"
        public static let home = "home"
        public static let x = "x"
        public static let y = "y"
        public static let width = "width"
        public static let height = "height"
        public static let display = "display"
        public static let animated = "animated"
        public static let success = "success"
        public static let error = "error"
    }

    public static func canonicalHomePath(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        BlinkPaths.home(environment: environment)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
    }
}
