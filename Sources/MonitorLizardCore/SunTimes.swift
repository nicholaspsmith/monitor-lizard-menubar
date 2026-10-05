// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Nicholas Smith

import Foundation

public struct Coordinate: Codable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public init(latitude: Double, longitude: Double) { self.latitude = latitude; self.longitude = longitude }
}

/// Sunrise and sunset from the sunrise equation (good to a minute or two,
/// which is all a Night Shift schedule needs).
public enum SunTimes {
    public enum Event { case sunrise, sunset }

    /// The sunrise or sunset on `day`'s calendar date in `calendar`'s time
    /// zone, or nil when the sun doesn't cross the horizon that day (polar
    /// day or night).
    public static func time(of event: Event, on day: Date, at place: Coordinate,
                            calendar: Calendar = .current) -> Date? {
        guard let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day) else { return nil }
        let rad = Double.pi / 180
        let julianDay = noon.timeIntervalSince1970 / 86400 + 2_440_587.5
        let n = (julianDay - 2_451_545.0 + 0.0008).rounded()
        let meanNoon = n - place.longitude / 360
        let anomaly = (357.5291 + 0.98560028 * meanNoon).truncatingRemainder(dividingBy: 360)
        let center = 1.9148 * sin(anomaly * rad) + 0.02 * sin(2 * anomaly * rad) + 0.0003 * sin(3 * anomaly * rad)
        let ecliptic = (anomaly + center + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let transit = 2_451_545.0 + meanNoon + 0.0053 * sin(anomaly * rad) - 0.0069 * sin(2 * ecliptic * rad)
        let declination = asin(sin(ecliptic * rad) * sin(23.4397 * rad))
        let lat = place.latitude * rad
        let cosHour = (sin(-0.833 * rad) - sin(lat) * sin(declination)) / (cos(lat) * cos(declination))
        guard (-1...1).contains(cosHour) else { return nil }
        let hourAngle = acos(cosHour) / rad
        let julian = event == .sunrise ? transit - hourAngle / 360 : transit + hourAngle / 360
        return Date(timeIntervalSince1970: (julian - 2_440_587.5) * 86400)
    }

    /// Where a time zone's principal city is, from the system's `zone.tab`:
    /// a place for the sun's times that needs no Location Services.
    public static func coordinate(forTimeZone identifier: String,
                                  zoneTab: String? = try? String(contentsOfFile: "/usr/share/zoneinfo/zone.tab", encoding: .utf8)) -> Coordinate? {
        guard let zoneTab else { return nil }
        for line in zoneTab.split(separator: "\n") where !line.hasPrefix("#") {
            let fields = line.split(separator: "\t")
            guard fields.count >= 3, fields[2] == identifier else { continue }
            return parseISO6709(String(fields[1]))
        }
        return nil
    }

    /// `±DDMM±DDDMM` or `±DDMMSS±DDDMMSS`, as zone.tab writes them.
    static func parseISO6709(_ s: String) -> Coordinate? {
        guard let split = s.dropFirst().firstIndex(where: { $0 == "+" || $0 == "-" }) else { return nil }
        func degrees(_ part: Substring, degreeDigits: Int) -> Double? {
            guard let sign = part.first, sign == "+" || sign == "-" else { return nil }
            let digits = part.dropFirst()
            guard digits.count == degreeDigits + 2 || digits.count == degreeDigits + 4,
                  let d = Double(digits.prefix(degreeDigits)),
                  let m = Double(digits.dropFirst(degreeDigits).prefix(2)) else { return nil }
            let sec = digits.count == degreeDigits + 4 ? Double(digits.suffix(2)) ?? 0 : 0
            let value = d + m / 60 + sec / 3600
            return sign == "-" ? -value : value
        }
        guard let lat = degrees(s[s.startIndex..<split], degreeDigits: 2),
              let lon = degrees(s[split...], degreeDigits: 3) else { return nil }
        return Coordinate(latitude: lat, longitude: lon)
    }
}
