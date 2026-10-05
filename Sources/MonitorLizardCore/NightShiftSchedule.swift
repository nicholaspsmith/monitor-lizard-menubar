// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

/// When Night Shift turns itself on and off, and how its warmth follows the
/// clock in between. Pure: the app feeds it the time and a place.
public struct NightShiftSchedule: Codable, Equatable {
    /// One end of the night: the sun (sunset to turn on, sunrise to turn off)
    /// moved by an offset, or a fixed time of day.
    public struct Edge: Codable, Equatable {
        public enum Anchor: String, Codable { case sun, clock }
        public var anchor: Anchor
        /// Minutes after the sunset or sunrise; negative is before.
        public var offsetMinutes: Int
        /// Minutes after midnight, for `.clock`.
        public var clockMinutes: Int
        public init(anchor: Anchor, offsetMinutes: Int = 0, clockMinutes: Int) {
            self.anchor = anchor; self.offsetMinutes = offsetMinutes; self.clockMinutes = clockMinutes
        }
    }

    public struct Window: Equatable {
        public let on: Date
        public let off: Date
        public func contains(_ date: Date) -> Bool { date >= on && date < off }
    }

    public var isEnabled: Bool
    public var on: Edge
    public var off: Edge
    /// Warmth climbs from nothing to the chosen warmth over `rampMinutes`
    /// after turning on, and falls back over the same before turning off.
    public var ramps: Bool
    public var rampMinutes: Int

    public static let rampChoices = [15, 30, 60, 90, 120, 180]

    public init(isEnabled: Bool = false,
                on: Edge = Edge(anchor: .sun, clockMinutes: 21 * 60),
                off: Edge = Edge(anchor: .sun, clockMinutes: 7 * 60),
                ramps: Bool = false, rampMinutes: Int = 60) {
        self.isEnabled = isEnabled; self.on = on; self.off = off; self.ramps = ramps; self.rampMinutes = rampMinutes
    }

    /// The time an edge falls on `day`. The sun's edges fall back to their
    /// clock time on a day the sun doesn't set or rise.
    func time(of edge: Edge, event: SunTimes.Event, on day: Date, place: Coordinate?, calendar: Calendar) -> Date? {
        if edge.anchor == .sun, let place,
           let sun = SunTimes.time(of: event, on: day, at: place, calendar: calendar) {
            return sun.addingTimeInterval(TimeInterval(edge.offsetMinutes * 60))
        }
        let start = calendar.startOfDay(for: day)
        return calendar.date(byAdding: .minute, value: edge.clockMinutes, to: start)
    }

    /// The night that begins on `day`'s date: on that evening, off at the
    /// first off time after it.
    func window(beginning day: Date, place: Coordinate?, calendar: Calendar) -> Window? {
        guard let on = time(of: on, event: .sunset, on: day, place: place, calendar: calendar),
              let sameDay = time(of: off, event: .sunrise, on: day, place: place, calendar: calendar) else { return nil }
        if sameDay > on { return Window(on: on, off: sameDay) }
        guard let next = calendar.date(byAdding: .day, value: 1, to: day),
              let off = time(of: off, event: .sunrise, on: next, place: place, calendar: calendar),
              off > on else { return nil }
        return Window(on: on, off: off)
    }

    /// The night `date` falls in, if any.
    public func window(at date: Date, place: Coordinate?, calendar: Calendar = .current) -> Window? {
        for back in [0, -1] {
            guard let day = calendar.date(byAdding: .day, value: back, to: date),
                  let w = window(beginning: day, place: place, calendar: calendar) else { continue }
            if w.contains(date) { return w }
        }
        return nil
    }

    /// The next night to begin after `date` (tonight's, if it hasn't yet).
    public func nextWindow(after date: Date, place: Coordinate?, calendar: Calendar = .current) -> Window? {
        for ahead in 0...2 {
            guard let day = calendar.date(byAdding: .day, value: ahead, to: date),
                  let w = window(beginning: day, place: place, calendar: calendar) else { continue }
            if w.on > date { return w }
        }
        return nil
    }

    /// The share (0...1) of the chosen warmth to show at `date` in `window`.
    /// 1 throughout without ramping. A night shorter than two ramps peaks
    /// halfway through.
    public func rampFactor(at date: Date, in window: Window) -> Double {
        guard ramps, window.contains(date) else { return window.contains(date) ? 1 : 0 }
        let length = window.off.timeIntervalSince(window.on)
        let ramp = min(TimeInterval(rampMinutes * 60), length / 2)
        guard ramp > 0 else { return 1 }
        let up = date.timeIntervalSince(window.on) / ramp
        let down = window.off.timeIntervalSince(date) / ramp
        return max(0, min(1, up, down))
    }
}

/// Applies a schedule the way macOS's own does: Night Shift is switched on
/// and off only as the schedule crosses an edge, so switching it by hand
/// holds until the next one.
public struct NightShiftEdgeTracker {
    private var lastInside: Bool?
    public init() {}

    /// What to switch Night Shift to now, if anything. The first look after
    /// launch or a schedule change brings it into line.
    public mutating func update(inside: Bool) -> Bool? {
        defer { lastInside = inside }
        return lastInside == inside ? nil : inside
    }

    public mutating func reset() { lastInside = nil }
}
