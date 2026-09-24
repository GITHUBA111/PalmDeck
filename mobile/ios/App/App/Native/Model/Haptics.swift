import UIKit

/// 触觉反馈（Taptic Engine）。每次新建 generator 最可靠。
enum Haptics {
    /// 触觉总开关（持久化；设置里可关）。默认开。
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: "palmdeck_haptics") as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "palmdeck_haptics") }
    }

    static func prepare() {
        UIImpactFeedbackGenerator(style: .light).prepare()
        UISelectionFeedbackGenerator().prepare()
    }

    static func tap()      { guard enabled else { return }; UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func press()    { guard enabled else { return }; UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
    static func bump()     { guard enabled else { return }; UIImpactFeedbackGenerator(style: .heavy).impactOccurred() }
    static func rigidTap() { guard enabled else { return }; UIImpactFeedbackGenerator(style: .rigid).impactOccurred() }
    static func select()   { guard enabled else { return }; UISelectionFeedbackGenerator().selectionChanged() }
    static func success()  { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.success) }
    static func warning()  { guard enabled else { return }; UINotificationFeedbackGenerator().notificationOccurred(.warning) }
}
