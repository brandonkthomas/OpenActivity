//
//  Preferences.swift
//  OpenActivity
//
//  User settings backed by UserDefaults. Posts `Preferences.didChange` after every change.
//

import AppKit
import ServiceManagement

enum MenuBarStyle: String, CaseIterable {
    /// A single glyph that turns into a warning sign under strain.
    case icon
    /// One figure per chosen metric: "CPU 27%".
    case figure
    /// A small live graph per chosen metric.
    case graph
    /// Two short figures stacked on top of each other.
    case stacked

    var title: String {
        switch self {
        case .icon: return "Icon"
        case .figure: return "Figure"
        case .graph: return "Graph"
        case .stacked: return "Stacked"
        }
    }
}

/// How often figures refresh while a window or the menu bar dashboard is open.
enum UpdateFrequency: String, CaseIterable {
    case veryOften
    case often
    case normally

    var interval: TimeInterval {
        switch self {
        case .veryOften: return 1
        case .often: return 2
        case .normally: return 5
        }
    }

    var title: String {
        switch self {
        case .veryOften: return "Very often (1 sec)"
        case .often: return "Often (2 sec)"
        case .normally: return "Normally (5 sec)"
        }
    }
}

final class Preferences {
    static let shared = Preferences()
    static let didChange = Notification.Name("OpenActivityPreferencesDidChange")

    /// Metrics that can be shown in the menu bar. `.sensors` stands for the CPU temperature.
    static let menuBarChoices: [Metric] = [.cpu, .memory, .gpu, .network, .disk, .sensors, .battery]

    /// How many apps the menu bar dashboard can list in one section.
    static let dashboardAppCounts = 1...10

    private let defaults = UserDefaults.standard

    private enum Key {
        static let menuBarStyle = "menuBar.style"
        static let menuBarMetrics = "menuBar.metrics"
        static let showSystem = "apps.showSystem"
        static let showDockIcon = "app.showDockIcon"
        static let lastPage = "window.lastPage"
        static let updateFrequency = "monitor.updateFrequency"
        static let hiddenDashboardTabs = "popover.hiddenTabs"
        static let dashboardBusiestCount = "popover.busiestCount"
        static let dashboardTopAppsCount = "popover.topAppsCount"
    }

    init() {
        defaults.register(defaults: [
            Key.menuBarStyle: MenuBarStyle.figure.rawValue,
            Key.menuBarMetrics: [Metric.cpu.rawValue, Metric.memory.rawValue],
            Key.showSystem: true,
            Key.showDockIcon: true,
            Key.lastPage: Metric.overview.rawValue,
            Key.updateFrequency: UpdateFrequency.often.rawValue,
            Key.dashboardBusiestCount: 3,
            Key.dashboardTopAppsCount: 5,
        ])
    }

    var menuBarStyle: MenuBarStyle {
        get { MenuBarStyle(rawValue: defaults.string(forKey: Key.menuBarStyle) ?? "") ?? .figure }
        set { defaults.set(newValue.rawValue, forKey: Key.menuBarStyle); changed() }
    }

    /// Ordered as in `menuBarChoices`.
    var menuBarMetrics: [Metric] {
        get {
            let stored = Set((defaults.stringArray(forKey: Key.menuBarMetrics) ?? []).compactMap(Metric.init(rawValue:)))
            return Self.menuBarChoices.filter(stored.contains)
        }
        set { defaults.set(newValue.map(\.rawValue), forKey: Key.menuBarMetrics); changed() }
    }

    /// Whether the macOS group (daemons and system agents) is listed with the apps.
    var showSystemProcesses: Bool {
        get { defaults.bool(forKey: Key.showSystem) }
        set { defaults.set(newValue, forKey: Key.showSystem); changed() }
    }

    var showDockIcon: Bool {
        get { defaults.bool(forKey: Key.showDockIcon) }
        set {
            defaults.set(newValue, forKey: Key.showDockIcon)
            NSApp.setActivationPolicy(newValue ? .regular : .accessory)
            changed()
        }
    }

    var updateFrequency: UpdateFrequency {
        get { UpdateFrequency(rawValue: defaults.string(forKey: Key.updateFrequency) ?? "") ?? .often }
        set { defaults.set(newValue.rawValue, forKey: Key.updateFrequency); changed() }
    }

    /// Tabs left out of the menu bar dashboard. Stored as hidden rather than shown so tabs added
    /// in later versions appear by default.
    var hiddenDashboardTabs: Set<Metric> {
        get { Set((defaults.stringArray(forKey: Key.hiddenDashboardTabs) ?? []).compactMap(Metric.init(rawValue:))) }
        set { defaults.set(newValue.map(\.rawValue).sorted(), forKey: Key.hiddenDashboardTabs); changed() }
    }

    /// Apps listed under "Busiest right now" on the dashboard's Overview tab.
    var dashboardBusiestCount: Int {
        get { Self.clampedAppCount(defaults.integer(forKey: Key.dashboardBusiestCount)) }
        set { defaults.set(Self.clampedAppCount(newValue), forKey: Key.dashboardBusiestCount); changed() }
    }

    /// Apps listed under "Top apps" on the dashboard's metric tabs.
    var dashboardTopAppsCount: Int {
        get { Self.clampedAppCount(defaults.integer(forKey: Key.dashboardTopAppsCount)) }
        set { defaults.set(Self.clampedAppCount(newValue), forKey: Key.dashboardTopAppsCount); changed() }
    }

    private static func clampedAppCount(_ count: Int) -> Int {
        min(max(count, dashboardAppCounts.lowerBound), dashboardAppCounts.upperBound)
    }

    var lastPage: Metric {
        get { Metric(rawValue: defaults.string(forKey: Key.lastPage) ?? "") ?? .overview }
        set { defaults.set(newValue.rawValue, forKey: Key.lastPage) }
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                if newValue { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            } catch {
                NSAlert(error: error).runModal()
            }
            changed()
        }
    }

    private func changed() {
        NotificationCenter.default.post(name: Self.didChange, object: self)
    }
}
