import Combine
import Foundation

// A setting: its UserDefaults key, its default, and how its value is stored. Declare one as a static on Setting
// (see AppSettings.swift in the app) and read or write it through SettingsStore.
public struct Setting<Value> {
    public let key: String
    public let defaultValue: Value
    let decode: (Any) -> Value?
    let encode: (Value) -> Any

    public init(_ key: String, default defaultValue: Value,
                decode: @escaping (Any) -> Value?, encode: @escaping (Value) -> Any) {
        self.key = key
        self.defaultValue = defaultValue
        self.decode = decode
        self.encode = encode
    }
}

extension Setting where Value == Bool {
    public init(_ key: String, default defaultValue: Bool) {
        self.init(key, default: defaultValue, decode: { $0 as? Bool }, encode: { $0 })
    }
}

extension Setting where Value == String {
    public init(_ key: String, default defaultValue: String) {
        self.init(key, default: defaultValue, decode: { $0 as? String }, encode: { $0 })
    }
}

extension Setting where Value == Double {
    public init(_ key: String, default defaultValue: Double) {
        self.init(key, default: defaultValue, decode: { $0 as? Double }, encode: { $0 })
    }
}

extension Setting where Value: RawRepresentable, Value.RawValue == String {
    public init(_ key: String, default defaultValue: Value) {
        self.init(key, default: defaultValue, decode: { ($0 as? String).flatMap(Value.init(rawValue:)) }, encode: { $0.rawValue })
    }
}

// The settings, kept in UserDefaults. SwiftUI views observe it; app code subscribes to the settings it reacts to.
public final class SettingsStore: ObservableObject {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults
    private var observers: [String: [(Any) -> Void]] = [:]

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public subscript<Value>(_ setting: Setting<Value>) -> Value {
        get { defaults.object(forKey: setting.key).flatMap(setting.decode) ?? setting.defaultValue }
        set {
            objectWillChange.send()
            defaults.set(setting.encode(newValue), forKey: setting.key)
            observers[setting.key]?.forEach { $0(newValue) }
        }
    }

    // called on the main thread after each change of that setting
    public func observe<Value>(_ setting: Setting<Value>, _ handler: @escaping (Value) -> Void) {
        observers[setting.key, default: []].append { value in (value as? Value).map(handler) }
    }
}
