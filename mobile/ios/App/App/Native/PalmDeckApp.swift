import SwiftUI

@main
struct PalmDeckApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var ctrl = CockpitController()
    @State private var entered = UserDefaults.standard.bool(forKey: "palmdeck_entered")

    var body: some Scene {
        WindowGroup {
            Group {
                if entered {
                    CockpitView(ctrl: ctrl, s: ctrl.state, onExit: {
                        entered = false
                        UserDefaults.standard.set(false, forKey: "palmdeck_entered")
                    })
                } else {
                    PreflightView(ctrl: ctrl) {
                        Haptics.prepare(); Haptics.success()
                        entered = true
                        UserDefaults.standard.set(true, forKey: "palmdeck_entered")
                    }
                }
            }
            // 只浅色：系统深色由 Info.plist 的 UIUserInterfaceStyle=Light 挡住
            .palmDynamicType()
        }
    }
}
