import AppKit
import MonitorLizardCore

/// Writes the per-model override into the root-owned Overrides directory
/// through the standard macOS administrator dialog. One prompt per new model.
enum OverrideWriter {
    enum Outcome { case written, cancelled, failed(String) }

    static func write(for display: DisplayInfo) -> Outcome {
        let dest = OverridePlist.path(vendorID: display.vendorID, productID: display.productID)
        let dir = (dest as NSString).deletingLastPathComponent
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("monitor-lizard-override-\(display.productID).plist")
        do {
            try OverridePlist.contents(vendorID: display.vendorID, productID: display.productID).write(to: tmp)
        } catch {
            return .failed("could not stage override: \(error.localizedDescription)")
        }
        func q(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let shell = "mkdir -p \(q(dir)) && cp \(q(tmp.path)) \(q(dest)) && chmod 644 \(q(dest))"
        let source = "do shell script \"\(shell.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\""))\" with administrator privileges"
        var error: NSDictionary?
        let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
        try? FileManager.default.removeItem(at: tmp)
        if result != nil {
            Log.tvrole.info("wrote override for \(display.name) at \(dest)")
            return .written
        }
        let code = (error?[NSAppleScript.errorNumber] as? Int) ?? 0
        if code == -128 {                       // userCanceledErr
            Log.tvrole.info("override for \(display.name) cancelled by the user")
            return .cancelled
        }
        let message = (error?[NSAppleScript.errorMessage] as? String) ?? "AppleScript error \(code)"
        Log.tvrole.error("override for \(display.name) failed: \(message)")
        return .failed(message)
    }
}
