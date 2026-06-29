import AppKit
import Foundation

final class BrowserUseController {
    static let shared = BrowserUseController()

    private init() {}

    func getText(params: JSON?) throws -> JSON {
        let window = try resolveBrowserWindow(params: params)
        guard AXIsProcessTrusted() else {
            throw RouterError.custom("Accessibility permission is required for browser.getText")
        }
        let result = AccessibilityTextExtractor().extract(pid: window.pid, wid: window.wid, minChars: 0)
        let text = result?.fullText ?? ""
        return .object([
            "ok": .bool(true),
            "action": .string("browser.getText"),
            "target": Encoders.window(window),
            "source": .string("accessibility"),
            "text": .string(text),
            "blocks": .array((result?.texts ?? []).map { .string($0) }),
        ])
    }

    func queryDom(params: JSON?) throws -> JSON {
        let window = try resolveBrowserWindow(params: params)
        let selector = try requiredString(params, keys: ["selector", "query"])
        let limit = max(1, min(params?["limit"]?.intValue ?? 20, 200))
        guard allowAutomation(params) else {
            throw RouterError.custom("browser.queryDom requires allowAutomation true because it uses browser JavaScript automation")
        }

        let js = """
        (() => {
          const selector = \(jsString(selector));
          const limit = \(limit);
          const nodes = Array.from(document.querySelectorAll(selector)).slice(0, limit);
          return JSON.stringify(nodes.map((el, index) => ({
            index,
            tag: el.tagName ? el.tagName.toLowerCase() : '',
            id: el.id || null,
            classes: el.className || null,
            text: (el.innerText || el.textContent || '').slice(0, 2000),
            href: el.href || null,
            value: el.value || null,
            ariaLabel: el.getAttribute('aria-label') || null,
            role: el.getAttribute('role') || null
          })));
        })()
        """
        let raw = try runBrowserJavaScript(app: window.app, script: js)
        return .object([
            "ok": .bool(true),
            "action": .string("browser.queryDom"),
            "target": Encoders.window(window),
            "selector": .string(selector),
            "result": parseJSONString(raw) ?? .string(raw),
            "raw": .string(raw),
        ])
    }

    func executeJavascript(params: JSON?) throws -> JSON {
        let source = params?["source"]?.stringValue ?? "daemon"
        let treatment = ComputerTreatment.resolve(params: params, defaultValue: .stage)
        let window = try resolveBrowserWindow(params: params)
        let script = try requiredString(params, keys: ["script", "javascript", "js"])
        let run = try RunStore.shared.createRun(
            title: "Browser JavaScript",
            source: source,
            surfaces: [.window(window)]
        )

        _ = try RunStore.shared.markRunning(
            id: run.id,
            summary: "Resolved browser JavaScript action",
            data: [
                "treatment": .string(treatment.rawValue),
                "wid": .int(Int(window.wid)),
                "app": .string(window.app),
                "characters": .int(script.count),
            ]
        )

        var result = ""
        var executed = false
        do {
            if treatment == .execute {
                guard allowAutomation(params) else {
                    throw RouterError.custom("browser.executeJavascript requires allowAutomation true")
                }
                result = try runBrowserJavaScript(app: window.app, script: script)
                executed = true
                _ = try RunStore.shared.appendTrace(
                    id: run.id,
                    kind: "browser.javascript.executed",
                    summary: "Executed browser JavaScript",
                    data: ["resultCharacters": .int(result.count)]
                )
            }

            let completed = try RunStore.shared.complete(
                id: run.id,
                summary: executed ? "Executed browser JavaScript" : "Staged browser JavaScript",
                data: [
                    "executed": .bool(executed),
                    "treatment": .string(treatment.rawValue),
                ]
            )
            return .object([
                "ok": .bool(true),
                "action": .string("browser.executeJavascript"),
                "treatment": .string(treatment.rawValue),
                "executed": .bool(executed),
                "target": Encoders.window(window),
                "run": completed.json,
                "result": parseJSONString(result) ?? .string(result),
                "raw": .string(result),
            ])
        } catch {
            _ = try? RunStore.shared.fail(
                id: run.id,
                summary: "Browser JavaScript failed",
                data: ["error": .string(error.localizedDescription)]
            )
            throw error
        }
    }

    private func resolveBrowserWindow(params: JSON?) throws -> WindowEntry {
        let window = try CaptureController.shared.resolveWindow(params: params)
        guard isSupportedBrowser(window.app) else {
            throw RouterError.custom("browser.* requires Safari, Google Chrome, Chrome, Brave Browser, Microsoft Edge, or Arc; resolved \(window.app)")
        }
        return window
    }

    private func isSupportedBrowser(_ app: String) -> Bool {
        let normalized = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized == "safari"
            || normalized == "google chrome"
            || normalized == "chrome"
            || normalized == "brave browser"
            || normalized == "microsoft edge"
            || normalized == "arc"
    }

    private func allowAutomation(_ params: JSON?) -> Bool {
        params?["allowAutomation"]?.boolValue == true
            || params?["allow-automation"]?.boolValue == true
            || params?["automation"]?.boolValue == true
    }

    private func requiredString(_ params: JSON?, keys: [String]) throws -> String {
        for key in keys {
            if let value = params?[key]?.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines),
               !value.isEmpty {
                return value
            }
        }
        throw RouterError.missingParam(keys.first ?? "value")
    }

    private func runBrowserJavaScript(app: String, script: String) throws -> String {
        let appLiteral = appleScriptString(app)
        let scriptLiteral = appleScriptString(script)
        let normalized = app.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let appleScript: String
        if normalized == "safari" {
            appleScript = """
            tell application \(appLiteral)
                if (count of windows) is 0 then error "No browser windows"
                return do JavaScript \(scriptLiteral) in current tab of front window
            end tell
            """
        } else {
            appleScript = """
            tell application \(appLiteral)
                if (count of windows) is 0 then error "No browser windows"
                return execute active tab of front window javascript \(scriptLiteral)
            end tell
            """
        }

        return ProcessQuery.shell(["/usr/bin/osascript", "-e", appleScript])
    }

    private func appleScriptString(_ value: String) -> String {
        "\"" + value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\r", with: "\\r")
            .replacingOccurrences(of: "\n", with: "\\n")
            + "\""
    }

    private func jsString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value),
              let encoded = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return encoded
    }

    private func parseJSONString(_ raw: String) -> JSON? {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return jsonValue(value)
    }

    private func jsonValue(_ value: Any) -> JSON {
        switch value {
        case let string as String:
            return .string(string)
        case let bool as Bool:
            return .bool(bool)
        case let number as NSNumber:
            let double = number.doubleValue
            if floor(double) == double {
                return .int(number.intValue)
            }
            return .double(double)
        case let array as [Any]:
            return .array(array.map(jsonValue))
        case let object as [String: Any]:
            return .object(object.mapValues(jsonValue))
        default:
            return .null
        }
    }
}
