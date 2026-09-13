import AppKit
import CoreGraphics
import MonitorLizardCore

/// Everything the menu shows, refreshed on display reconfiguration and wake.
/// DDC values are read on demand (menu open, after a write), never on a timer.
final class DisplayModel {
    struct Entry {
        let info: DisplayInfo
        var ddc: DDCService?
        var ddcUnavailable = false
        var brightness: VCPValue?
        var contrast: VCPValue?
        var builtInBrightness: Float?
        var plan: ModePlan
        var all: [ModeSpec]
        var modes: [CGDisplayMode]
        var tvState: TVRoleState
        var isExternalControllable: Bool { ddc != nil && !ddcUnavailable }
    }

    private(set) var entries: [Entry] = []
    let nightShift: NightShiftBackend?
    let tvRoles: TVRoleTracker
    private let brightness: BrightnessBackend
    var onChange: (() -> Void)?
    var onWrite: (() -> Void)?
    var onNeedsTVFix: ((DisplayInfo) -> Void)?
    private var refreshWork: DispatchWorkItem?

    init(brightness: BrightnessBackend, nightShift: NightShiftBackend?, tvRoles: TVRoleTracker) {
        self.brightness = brightness
        self.nightShift = nightShift
        self.tvRoles = tvRoles
    }

    func start() {
        // Reconfiguration fires several times per change; act once, after the last one.
        CGDisplayRegisterReconfigurationCallback({ _, flags, userInfo in
            // The callback fires once per display with `.beginConfigurationFlag`
            // before reconfiguration, then again per display, without that flag,
            // once CoreGraphics/QuickDraw/Carbon Display Manager state is all
            // up to date. Act only on the latter; `scheduleRefresh`'s debounce
            // collapses the one-per-display fan-out into a single refresh.
            guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
            let model = Unmanaged<DisplayModel>.fromOpaque(userInfo).takeUnretainedValue()
            model.scheduleRefresh()
        }, Unmanaged.passUnretained(self).toOpaque())
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.scheduleRefresh()
        }
        nightShift?.onChange { [weak self] in self?.onChange?() }
        refresh()
    }

    private func scheduleRefresh() {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }
        refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    func refresh() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &count)
        let infos = ids.prefix(Int(count)).map { CoreDisplayInfo.info(for: $0) }
            .sorted { $0.isMain && !$1.isMain }
        // Old services are dropped wholesale: after a long sleep the display ids
        // and the AV services behind them are new objects.
        let services = IORegistryScanner.makeDDCServices(for: infos)
        entries = infos.map { info in
            let (all, current, modes) = DisplayModes.specs(for: info.id)
            return Entry(info: info,
                         ddc: info.isBuiltIn ? nil : services[info.id],
                         builtInBrightness: info.isBuiltIn ? brightness.brightness(info.id) : nil,
                         plan: DisplayModes.plan(all: all, current: current),
                         all: all,
                         modes: modes,
                         tvState: tvRoles.state(for: info))
        }
        Log.menu.info("enumerated \(self.entries.count) displays, \(services.count) with DDC")
        onChange?()
        for e in entries where tvRoles.needsFix(e.info) { onNeedsTVFix?(e.info) }
        readValues()
    }

    func readValues() {
        for (index, entry) in entries.enumerated() {
            if entry.info.isBuiltIn {
                entries[index].builtInBrightness = brightness.brightness(entry.info.id)
                continue
            }
            guard let ddc = entry.ddc else { continue }
            let id = entry.info.id
            ddc.read(.brightness) { [weak self] result in
                DispatchQueue.main.async { self?.store(id: id, ddc: ddc, code: .brightness, result: result) }
                ddc.read(.contrast) { [weak self] result in
                    DispatchQueue.main.async { self?.store(id: id, ddc: ddc, code: .contrast, result: result) }
                }
            }
        }
    }

    /// The poll tick: built-in brightness only. DDC is never read on a timer.
    func readBuiltInOnly() {
        var changed = false
        for (i, e) in entries.enumerated() where e.info.isBuiltIn {
            let value = brightness.brightness(e.info.id)
            if value != entries[i].builtInBrightness {
                entries[i].builtInBrightness = value
                changed = true
            }
        }
        if changed { onChange?() }
    }

    private func store(id: CGDirectDisplayID, ddc: DDCService, code: VCPCode, result: Result<VCPValue, DDCError>) {
        guard let i = entries.firstIndex(where: { $0.info.id == id }) else { return }
        // `refresh()` drops old services wholesale on reconfiguration; a
        // completion from a service that's no longer this entry's must not
        // write into the entry that replaced it.
        guard entries[i].ddc === ddc else { return }
        switch result {
        case .success(let value):
            if code == .brightness { entries[i].brightness = value } else { entries[i].contrast = value }
            entries[i].ddcUnavailable = false
        case .failure(let error):
            Log.ddc.error("display \(id) \(code.rawValue, format: .hex) read failed: \(String(describing: error))")
            entries[i].ddcUnavailable = true
        }
        onChange?()
    }

    func setBrightness(_ id: CGDirectDisplayID, _ value: UInt16) { write(id, .brightness, value) }
    func setContrast(_ id: CGDirectDisplayID, _ value: UInt16) { write(id, .contrast, value) }

    private func write(_ id: CGDirectDisplayID, _ code: VCPCode, _ value: UInt16) {
        guard let entry = entry(id), let ddc = entry.ddc else { return }
        ddc.write(code, value: value) { [weak self] result in
            switch result {
            case .success:
                DispatchQueue.main.async {
                    self?.store(id: id, ddc: ddc, code: code, result: result)
                    self?.onWrite?()
                }
            case .failure(let error):
                // A failed write says nothing about whether the display is
                // still readable — only a read failure may legitimately mark
                // it unavailable — so re-read instead of storing the write's
                // own failure through `store`.
                Log.ddc.error("display \(id) \(code.rawValue, format: .hex) write failed: \(String(describing: error))")
                ddc.read(code) { [weak self] readResult in
                    DispatchQueue.main.async { self?.store(id: id, ddc: ddc, code: code, result: readResult) }
                }
            }
        }
    }

    func setBuiltInBrightness(_ id: CGDirectDisplayID, _ value: Float) {
        guard brightness.setBrightness(id, value), let i = entries.firstIndex(where: { $0.info.id == id }) else { return }
        entries[i].builtInBrightness = value
        onChange?()
    }

    func apply(_ spec: ModeSpec, to id: CGDirectDisplayID) -> CGError {
        guard let entry = entry(id) else { return .illegalArgument }
        return DisplayModes.apply(spec, all: entry.all, modes: entry.modes, to: id)   // the reconfigure callback refreshes the plan
    }

    func entry(_ id: CGDirectDisplayID) -> Entry? { entries.first { $0.info.id == id } }

    /// What the glyph shows: the main display's brightness, whichever backend owns it.
    var mainBrightnessFraction: CGFloat {
        guard let main = entries.first(where: { $0.info.isMain }) ?? entries.first else { return 0 }
        if let b = main.builtInBrightness { return CGFloat(b) }
        if let v = main.brightness, v.maximum > 0 { return CGFloat(v.current) / CGFloat(v.maximum) }
        return 0
    }
}
