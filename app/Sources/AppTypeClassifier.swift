import Foundation

enum AppType: String, CaseIterable {
    case terminal
    case editor
    case browser
    case chat
    case media
    case design
    case system
    case other

    var label: String { rawValue }
}

enum AppTypeClassifier {
    private static let nameMap: [String: AppType] = [
        // Terminals
        "iTerm2": .terminal, "Terminal": .terminal, "Alacritty": .terminal,
        "kitty": .terminal, "Warp": .terminal, "Hyper": .terminal,
        "WezTerm": .terminal, "Rio": .terminal, "Ghostty": .terminal,

        // Editors / IDEs
        "Xcode": .editor, "Code": .editor, "Visual Studio Code": .editor,
        "Cursor": .editor, "Sublime Text": .editor, "TextEdit": .editor,
        "Nova": .editor, "BBEdit": .editor, "Zed": .editor,
        "IntelliJ IDEA": .editor, "WebStorm": .editor, "PyCharm": .editor,
        "CLion": .editor, "GoLand": .editor, "RustRover": .editor,
        "Android Studio": .editor, "Fleet": .editor, "Neovide": .editor,

        // Browsers
        "Safari": .browser, "Google Chrome": .browser, "Firefox": .browser,
        "Arc": .browser, "Brave Browser": .browser, "Microsoft Edge": .browser,
        "Orion": .browser, "Vivaldi": .browser, "Opera": .browser,
        "Chrome": .browser, "Zen Browser": .browser,

        // Chat / Communication
        "Slack": .chat, "Discord": .chat, "Messages": .chat,
        "Telegram": .chat, "WhatsApp": .chat, "Signal": .chat,
        "Teams": .chat, "Microsoft Teams": .chat, "Zoom": .chat,
        "FaceTime": .chat, "Skype": .chat,

        // Media
        "Spotify": .media, "Music": .media, "QuickTime Player": .media,
        "VLC": .media, "IINA": .media, "Podcasts": .media,
        "Photos": .media, "Preview": .media, "mpv": .media,

        // Design
        "Figma": .design, "Sketch": .design, "Pixelmator Pro": .design,
        "Affinity Designer 2": .design, "Affinity Photo 2": .design,
        "Adobe Photoshop": .design, "Adobe Illustrator": .design,
        "Blender": .design, "OmniGraffle": .design,

        // System
        "Finder": .system, "System Preferences": .system, "System Settings": .system,
        "Activity Monitor": .system, "Console": .system, "Disk Utility": .system,
        "Keychain Access": .system,
    ]

    static func classify(_ appName: String) -> AppType {
        if let exact = nameMap[appName] { return exact }
        // Substring fallback
        let lower = appName.lowercased()
        if lower.contains("terminal") || lower.contains("term") { return .terminal }
        if lower.contains("code") || lower.contains("studio") || lower.contains("edit") { return .editor }
        if lower.contains("chrome") || lower.contains("firefox") || lower.contains("safari") || lower.contains("browser") { return .browser }
        if lower.contains("slack") || lower.contains("discord") || lower.contains("chat") || lower.contains("teams") { return .chat }
        return .other
    }
}
