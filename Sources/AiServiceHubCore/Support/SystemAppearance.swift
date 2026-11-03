import Foundation

/// 系统外观检测
///
/// ## 为什么不用 `NSApp.effectiveAppearance`
///
/// 应用内的主题选择（跟随系统 / 浅色 / 深色）会给窗口强制指定外观，
/// 此时 `NSApp.effectiveAppearance` 反映的是**应用内**的选择，而不是系统环境。
/// 想表达「白天浅色、夜间深色」必须直接读系统的全局偏好。
///
/// ## 数据来源
///
/// 全局域的 `AppleInterfaceStyle`：系统处于深色模式时有值（`"Dark"`），
/// 浅色模式下该键不存在。`UserDefaults.standard` 读取时会落到全局域，
/// 且实测能实时反映系统外观切换。
public enum SystemAppearance {
    /// 系统外观的 UserDefaults key
    public static let appearanceKey = "AppleInterfaceStyle"

    /// 系统当前是否为深色模式
    public static func isDark(defaults: UserDefaults = .standard) -> Bool {
        isDarkValue(defaults.string(forKey: appearanceKey))
    }

    /// 判断外观值是否代表深色
    ///
    /// 拆出来是为了能单独测：读取 `AppleInterfaceStyle` 时会**回落到全局域**，
    /// 所以拿一个自定义 suite 也测不出「浅色」（浅色时该键在全局域本就不存在）。
    public static func isDarkValue(_ value: String?) -> Bool {
        value == "Dark"
    }
}
