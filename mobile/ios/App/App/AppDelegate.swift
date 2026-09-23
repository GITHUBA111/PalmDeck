import UIKit

// SwiftUI 生命周期由 PalmDeckApp 接管；这里保留一个最小 AppDelegate（由 adaptor 引入）。
// 不再依赖 Capacitor / storyboard 启动。
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        }
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }
}
