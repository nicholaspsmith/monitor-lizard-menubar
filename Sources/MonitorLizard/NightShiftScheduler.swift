// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import AppKit
import CoreLocation
import MonitorLizardCore

/// Runs Night Shift on Monitor Lizard's schedule: on and off at sunset and
/// sunrise (each with an offset) or at set times, with the warmth optionally
/// climbing in after it turns on and fading before it turns off.
final class NightShiftScheduler: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let scheduleKey = "nightShiftSchedule"
    static let warmthKey = "nightShiftScheduleWarmth"
    static let placeKey = "nightShiftPlace"
    private static let tick: TimeInterval = 30

    private let backend: NightShiftBackend
    private var timer: Timer?
    private var edges = NightShiftEdgeTracker()
    private let location = CLLocationManager()
    private var lastLocated = Date.distantPast
    /// The strength last set by the ramp, to tell it from a change made
    /// elsewhere (Control Center, the Warmth slider).
    private var lastRampStrength: Float?

    @Published var schedule: NightShiftSchedule {
        didSet {
            guard schedule != oldValue else { return }
            save(schedule, Self.scheduleKey)
            edges.reset()
            if schedule.isEnabled && !oldValue.isEnabled {
                (backend as? CoreBrightnessNightShift)?.turnOffSystemSchedule()
            }
            if usesSun { locate() }
            restartTimer()
            apply()
        }
    }

    /// The warmth Night Shift reaches at the top of the ramp.
    @Published var warmth: Float {
        didSet { UserDefaults.standard.set(warmth, forKey: Self.warmthKey); apply() }
    }

    /// Where the sun's times are worked out for: the Mac's location when
    /// Location Services allow it, else the time zone's principal city.
    @Published private(set) var place: Coordinate?
    @Published private(set) var placeIsLocation = false

    /// Called whenever the schedule changes Night Shift or its own settings.
    var onChange: (() -> Void)?

    init(backend: NightShiftBackend) {
        self.backend = backend
        schedule = Self.load(NightShiftSchedule.self, Self.scheduleKey) ?? NightShiftSchedule()
        warmth = UserDefaults.standard.object(forKey: Self.warmthKey) as? Float ?? max(0.5, backend.status().strength)
        super.init()
        if let saved = Self.load(Coordinate.self, Self.placeKey) {
            place = saved
            placeIsLocation = true
        } else {
            place = SunTimes.coordinate(forTimeZone: TimeZone.current.identifier)
        }
        location.delegate = self
        location.desiredAccuracy = kCLLocationAccuracyReduced
    }

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(clockMoved), name: NSWorkspace.didWakeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(clockMoved), name: .NSSystemClockDidChange, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(timeZoneChanged), name: .NSSystemTimeZoneDidChange, object: nil)
        if schedule.isEnabled { (backend as? CoreBrightnessNightShift)?.turnOffSystemSchedule() }
        if usesSun { locate() }
        restartTimer()
        apply()
    }

    private var usesSun: Bool { schedule.isEnabled && (schedule.on.anchor == .sun || schedule.off.anchor == .sun) }

    var currentWindow: NightShiftSchedule.Window? { schedule.window(at: Date(), place: place) }
    var nextWindow: NightShiftSchedule.Window? { schedule.nextWindow(after: Date(), place: place) }

    /// The warmth the ramp calls for right now, if the ramp is in charge.
    var rampedWarmth: Float? {
        guard schedule.isEnabled, schedule.ramps, let w = currentWindow else { return nil }
        return warmth * Float(schedule.rampFactor(at: Date(), in: w))
    }

    // MARK: - Applying

    private func restartTimer() {
        timer?.invalidate()
        timer = nil
        guard schedule.isEnabled else { return }
        let t = Timer(timeInterval: Self.tick, repeats: true) { [weak self] _ in self?.apply() }
        t.tolerance = 5
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    @objc private func clockMoved() { apply() }

    @objc private func timeZoneChanged() {
        if !placeIsLocation { place = SunTimes.coordinate(forTimeZone: TimeZone.current.identifier) }
        if usesSun { locate() }
        apply()
    }

    func apply() {
        guard schedule.isEnabled else { return }
        if usesSun, Date().timeIntervalSince(lastLocated) > 6 * 3600 { locate() }
        let window = currentWindow
        var changed = false
        if let on = edges.update(inside: window != nil) {
            Log.nightshift.info("schedule: Night Shift \(on ? "on" : "off", privacy: .public)")
            if on, let level = rampedWarmth { setStrength(level) }
            _ = backend.setEnabled(on)
            if !on, schedule.ramps {
                // Leave the full warmth for the next time it's switched on by hand.
                setStrength(warmth)
            }
            changed = true
        }
        if let level = rampedWarmth, backend.status().enabled {
            let current = backend.status().strength
            if lastRampStrength == nil || abs(current - (lastRampStrength ?? current)) < 0.02 {
                if abs(current - level) > 0.004 { setStrength(level); changed = true }
            }
        }
        if changed { onChange?() }
    }

    private func setStrength(_ level: Float) {
        lastRampStrength = level
        _ = backend.setStrength(level)
    }

    /// The Warmth slider moved. With the ramp in charge it sets the warmth
    /// the ramp climbs to, shown scaled to where the ramp is now.
    func warmthSliderMoved(to level: Float) {
        if schedule.isEnabled && schedule.ramps {
            warmth = level
            lastRampStrength = nil
            if let ramped = rampedWarmth { setStrength(ramped) }
        } else {
            _ = backend.setStrength(level)
        }
    }

    /// What the Warmth slider shows: the top of the ramp while it runs.
    var sliderWarmth: Float {
        schedule.isEnabled && schedule.ramps ? warmth : backend.status().strength
    }

    // MARK: - Location

    func locate() {
        switch location.authorizationStatus {
        case .notDetermined:
            location.requestWhenInUseAuthorization()
        case .authorized, .authorizedAlways:
            lastLocated = Date()
            location.requestLocation()
        default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorized, .authorizedAlways:
            if usesSun { lastLocated = Date(); manager.requestLocation() }
        case .denied, .restricted:
            placeIsLocation = false
            place = SunTimes.coordinate(forTimeZone: TimeZone.current.identifier)
            UserDefaults.standard.removeObject(forKey: Self.placeKey)
            apply()
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let c = locations.last?.coordinate else { return }
        // Two decimals (about a kilometre) is far finer than the sun needs.
        let rounded = Coordinate(latitude: (c.latitude * 100).rounded() / 100, longitude: (c.longitude * 100).rounded() / 100)
        guard rounded != place || !placeIsLocation else { return }
        place = rounded
        placeIsLocation = true
        save(rounded, Self.placeKey)
        apply()
        onChange?()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.nightshift.info("location unavailable: \(error.localizedDescription, privacy: .public)")
    }

    // MARK: - Storage

    private func save<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func load<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
