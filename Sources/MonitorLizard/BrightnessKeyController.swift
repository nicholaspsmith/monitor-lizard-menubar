// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import HotkeyKit
import MonitorLizardCore

/// Makes the keyboard's brightness keys drive the main external monitor —
/// over DDC, or through DisplayServices where DDC has refused and macOS can
/// dim the display itself. It listens for the plain brightness media keys —
/// the ones an Apple keyboard sends, and the ones KeyLight posts for F1/F2 on
/// other boards — and swallows a press only when the main display is a
/// monitor we control; otherwise the key passes through and macOS dims the
/// built-in panel as usual. Ctrl+brightness is not bound, so KeyLight still
/// gets it.
///
/// Needs Accessibility, like every event tap. The tap is only created once
/// trusted; until then `isWaitingForTrust` is true and the menu says so.
final class BrightnessKeyController {
    static let enabledKey = "brightnessKeys"

    /// NX_KEYTYPE_BRIGHTNESS_UP / _DOWN, no modifiers.
    private static let bindings: [Binding] = [
        Binding(token: "brightness.up", trigger: .mediaKey(2, [])),
        Binding(token: "brightness.down", trigger: .mediaKey(3, [])),
    ]

    private let tap: HotkeyTap
    private var trustTimer: Timer?
    /// Returns the display to step, or nil to pass the key through.
    private let target: () -> CGDirectDisplayID?
    private let step: (CGDirectDisplayID, BrightnessKeys.Direction) -> Void

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledKey)
            isEnabled ? start() : stop()
        }
    }

    var isTrusted: Bool { tap.isTrusted }
    var isWaitingForTrust: Bool { isEnabled && !tap.isTrusted }

    init(target: @escaping () -> CGDirectDisplayID?,
         step: @escaping (CGDirectDisplayID, BrightnessKeys.Direction) -> Void) {
        self.target = target
        self.step = step
        // On by default: an absent key reads as enabled.
        isEnabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        var handler: ((String) -> Bool)!
        tap = HotkeyTap(bindings: Self.bindings, onMatch: { handler($0) })
        handler = { [weak self] token in self?.handle(token) ?? false }
    }

    func start() {
        guard isEnabled else { return }
        if !tap.isTrusted { tap.requestTrust() }
        startTapIfPossible()
    }

    func stop() {
        trustTimer?.invalidate()
        trustTimer = nil
        tap.stop()
    }

    /// Ask again for Accessibility (the menu row).
    func requestTrust() {
        tap.requestTrust()
        startTapIfPossible()
    }

    /// Other apps re-create their taps head-inserted in front of ours; called
    /// from the poll tick to keep ours frontmost.
    func reassert() {
        guard isEnabled, tap.isTrusted, tap.isRunning else { return }
        tap.stop()
        tap.start()
    }

    private func startTapIfPossible() {
        // Gate on trust, not on start()'s return: an untrusted process gets an
        // inert tap that a later grant never wakes up.
        guard tap.isTrusted else {
            if trustTimer == nil {
                trustTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    guard let self, self.tap.isTrusted else { return }
                    self.startTapIfPossible()
                }
            }
            return
        }
        trustTimer?.invalidate()
        trustTimer = nil
        if !tap.isRunning { tap.start() }
    }

    private func handle(_ token: String) -> Bool {
        guard let id = target() else { return false }
        step(id, token == "brightness.up" ? .up : .down)
        return true
    }
}
