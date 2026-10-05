// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import XCTest
@testable import MonitorLizardCore

final class NightShiftScheduleTests: XCTestCase {
    private let newYork = Coordinate(latitude: 40.7128, longitude: -74.006)
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        return c
    }()

    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // NOAA: New York, 2026-06-21 sunrise 05:25, sunset 20:31 (EDT).
    func testSunTimesMatchAlmanac() {
        let day = date(2026, 6, 21)
        let rise = SunTimes.time(of: .sunrise, on: day, at: newYork, calendar: calendar)!
        let set = SunTimes.time(of: .sunset, on: day, at: newYork, calendar: calendar)!
        XCTAssertEqual(rise.timeIntervalSince(date(2026, 6, 21, 5, 25)), 0, accuracy: 120)
        XCTAssertEqual(set.timeIntervalSince(date(2026, 6, 21, 20, 31)), 0, accuracy: 120)
    }

    func testNoSunsetInPolarSummer() {
        let tromso = Coordinate(latitude: 69.65, longitude: 18.96)
        XCTAssertNil(SunTimes.time(of: .sunset, on: date(2026, 6, 21), at: tromso, calendar: calendar))
    }

    func testZoneTabCoordinate() {
        let tab = "# comment\nUS\t+404251-0740023\tAmerica/New_York\tEastern\nAU\t-3352+15113\tAustralia/Sydney\n"
        let ny = SunTimes.coordinate(forTimeZone: "America/New_York", zoneTab: tab)!
        XCTAssertEqual(ny.latitude, 40.714, accuracy: 0.001)
        XCTAssertEqual(ny.longitude, -74.006, accuracy: 0.001)
        let syd = SunTimes.coordinate(forTimeZone: "Australia/Sydney", zoneTab: tab)!
        XCTAssertEqual(syd.latitude, -33.867, accuracy: 0.001)
        XCTAssertEqual(syd.longitude, 151.217, accuracy: 0.001)
        XCTAssertNil(SunTimes.coordinate(forTimeZone: "Europe/Nowhere", zoneTab: tab))
    }

    func testSunsetToSunriseWithOffsets() {
        let s = NightShiftSchedule(isEnabled: true,
                                   on: .init(anchor: .sun, offsetMinutes: -30, clockMinutes: 0),
                                   off: .init(anchor: .sun, offsetMinutes: 15, clockMinutes: 0))
        let w = s.window(at: date(2026, 6, 21, 23), place: newYork, calendar: calendar)!
        // 30 min before the 20:31 sunset, 15 min after the next day's 05:26 sunrise.
        XCTAssertEqual(w.on.timeIntervalSince(date(2026, 6, 21, 20, 1)), 0, accuracy: 120)
        XCTAssertEqual(w.off.timeIntervalSince(date(2026, 6, 22, 5, 41)), 0, accuracy: 120)
        XCTAssertNil(s.window(at: date(2026, 6, 21, 12), place: newYork, calendar: calendar))
    }

    func testWindowFoundAfterMidnight() {
        let s = NightShiftSchedule(isEnabled: true, on: .init(anchor: .clock, clockMinutes: 22 * 60),
                                   off: .init(anchor: .clock, clockMinutes: 7 * 60))
        let w = s.window(at: date(2026, 3, 2, 3), place: nil, calendar: calendar)!
        XCTAssertEqual(w.on, date(2026, 3, 1, 22))
        XCTAssertEqual(w.off, date(2026, 3, 2, 7))
    }

    func testSameEveningClockWindow() {
        let s = NightShiftSchedule(isEnabled: true, on: .init(anchor: .clock, clockMinutes: 20 * 60),
                                   off: .init(anchor: .clock, clockMinutes: 23 * 60))
        XCTAssertNotNil(s.window(at: date(2026, 3, 2, 21), place: nil, calendar: calendar))
        XCTAssertNil(s.window(at: date(2026, 3, 2, 23, 30), place: nil, calendar: calendar))
        XCTAssertEqual(s.nextWindow(after: date(2026, 3, 2, 23, 30), place: nil, calendar: calendar)?.on, date(2026, 3, 3, 20))
    }

    func testSunEdgeWithoutPlaceUsesClock() {
        let s = NightShiftSchedule(isEnabled: true)
        let w = s.window(at: date(2026, 3, 2, 22), place: nil, calendar: calendar)!
        XCTAssertEqual(w.on, date(2026, 3, 2, 21))
        XCTAssertEqual(w.off, date(2026, 3, 3, 7))
    }

    func testRamp() {
        let s = NightShiftSchedule(isEnabled: true, ramps: true, rampMinutes: 60)
        let w = NightShiftSchedule.Window(on: date(2026, 3, 2, 21), off: date(2026, 3, 3, 7))
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 2, 21), in: w), 0, accuracy: 1e-9)
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 2, 21, 30), in: w), 0.5, accuracy: 1e-9)
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 3, 1), in: w), 1, accuracy: 1e-9)
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 3, 6, 45), in: w), 0.25, accuracy: 1e-9)
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 3, 8), in: w), 0)
    }

    func testShortNightPeaksHalfway() {
        let s = NightShiftSchedule(isEnabled: true, ramps: true, rampMinutes: 180)
        let w = NightShiftSchedule.Window(on: date(2026, 3, 2, 21), off: date(2026, 3, 2, 23))
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 2, 22), in: w), 1, accuracy: 1e-9)
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 2, 21, 30), in: w), 0.5, accuracy: 1e-9)
    }

    func testNoRampIsFull() {
        let s = NightShiftSchedule(isEnabled: true)
        let w = NightShiftSchedule.Window(on: date(2026, 3, 2, 21), off: date(2026, 3, 3, 7))
        XCTAssertEqual(s.rampFactor(at: date(2026, 3, 2, 21, 1), in: w), 1)
    }

    func testEdgeTrackerOnlySwitchesAtEdges() {
        var t = NightShiftEdgeTracker()
        XCTAssertEqual(t.update(inside: true), true) // first look brings it into line
        XCTAssertNil(t.update(inside: true))         // a hand toggle in between holds
        XCTAssertEqual(t.update(inside: false), false)
        XCTAssertNil(t.update(inside: false))
        t.reset()
        XCTAssertEqual(t.update(inside: false), false)
    }

    func testCodableRoundTrip() throws {
        let s = NightShiftSchedule(isEnabled: true, on: .init(anchor: .clock, clockMinutes: 1290),
                                   off: .init(anchor: .sun, offsetMinutes: -45, clockMinutes: 420), ramps: true, rampMinutes: 90)
        XCTAssertEqual(try JSONDecoder().decode(NightShiftSchedule.self, from: JSONEncoder().encode(s)), s)
    }
}
