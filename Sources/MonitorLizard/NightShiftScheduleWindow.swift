// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import MonitorLizardCore
import SwiftUI

/// The Night Shift Schedule window, opened from the menu.
final class NightShiftScheduleWindow {
    private var window: NSWindow?
    private let scheduler: NightShiftScheduler

    init(scheduler: NightShiftScheduler) { self.scheduler = scheduler }

    func show() {
        if window == nil {
            let host = NSHostingController(rootView: NightShiftScheduleView(scheduler: scheduler))
            let w = NSWindow(contentViewController: host)
            w.title = "Night Shift Schedule"
            w.styleMask = [.titled, .closable]
            w.isReleasedWhenClosed = false
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct NightShiftScheduleView: View {
    @ObservedObject var scheduler: NightShiftScheduler

    private var binding: Binding<NightShiftSchedule> { $scheduler.schedule }

    var body: some View {
        Form {
            Toggle("Turn Night Shift on and off automatically", isOn: binding.isEnabled)
            Section {
                EdgeRow(title: "Turn on", sunName: "sunset", edge: binding.on)
                EdgeRow(title: "Turn off", sunName: "sunrise", edge: binding.off)
            }
            .disabled(!scheduler.schedule.isEnabled)
            Section {
                Toggle("Ramp the warmth", isOn: binding.ramps)
                Picker("Over", selection: binding.rampMinutes) {
                    ForEach(NightShiftSchedule.rampChoices, id: \.self) { Text(Self.duration($0)).tag($0) }
                }
                .disabled(!scheduler.schedule.ramps)
                Text(rampNote).font(.caption).foregroundStyle(.secondary)
            }
            .disabled(!scheduler.schedule.isEnabled)
            Section {
                Text(summary).font(.callout)
                if usesSun {
                    Text(placeNote).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var usesSun: Bool { scheduler.schedule.on.anchor == .sun || scheduler.schedule.off.anchor == .sun }

    private var rampNote: String {
        let span = Self.duration(scheduler.schedule.rampMinutes)
        return "Warmth climbs from none to \(Int((scheduler.warmth * 100).rounded())) over the first \(span) after "
            + "Night Shift turns on, and fades over the last \(span) before it turns off. Set the top with the menu's Warmth slider."
    }

    private var summary: String {
        guard scheduler.schedule.isEnabled else { return "Night Shift is only switched by hand." }
        let f = DateFormatter()
        f.dateStyle = .none
        f.timeStyle = .short
        if let now = scheduler.currentWindow {
            return "On now, until \(f.string(from: now.off))."
        }
        if let next = scheduler.nextWindow {
            let day = Calendar.current.isDateInToday(next.on) ? "today" : "tomorrow"
            return "Next: on \(day) at \(f.string(from: next.on)), off at \(f.string(from: next.off))."
        }
        return "Night Shift won't turn on: the off time comes before the on time."
    }

    private var placeNote: String {
        scheduler.placeIsLocation
            ? "Sunset and sunrise for this Mac's location."
            : "Sunset and sunrise for your time zone's main city. Allow Location Services for Monitor Lizard for times where you are."
    }

    static func duration(_ minutes: Int) -> String {
        if minutes < 60 { return "\(minutes) min" }
        let h = Double(minutes) / 60
        return h == h.rounded() ? "\(Int(h)) h" : String(format: "%.1f h", h)
    }
}

private struct EdgeRow: View {
    let title: String
    let sunName: String
    @Binding var edge: NightShiftSchedule.Edge

    var body: some View {
        Picker(title, selection: $edge.anchor) {
            Text("At \(sunName)").tag(NightShiftSchedule.Edge.Anchor.sun)
            Text("At a set time").tag(NightShiftSchedule.Edge.Anchor.clock)
        }
        if edge.anchor == .sun {
            Stepper(value: $edge.offsetMinutes, in: -180...180, step: 15) {
                Text(offsetText).foregroundStyle(.secondary)
            }
        } else {
            DatePicker("Time", selection: clockBinding, displayedComponents: .hourAndMinute)
        }
    }

    private var offsetText: String {
        let m = edge.offsetMinutes
        if m == 0 { return "Right at \(sunName)" }
        let span = m.magnitude < 60 ? "\(m.magnitude) min"
            : (m.magnitude % 60 == 0 ? "\(m.magnitude / 60) h" : "\(m.magnitude / 60) h \(m.magnitude % 60) min")
        return "\(span) \(m < 0 ? "before" : "after") \(sunName)"
    }

    private var clockBinding: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(byAdding: .minute, value: edge.clockMinutes,
                                      to: Calendar.current.startOfDay(for: Date())) ?? Date()
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                edge.clockMinutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            }
        )
    }
}
