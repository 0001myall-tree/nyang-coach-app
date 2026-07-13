import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  private func storeWidgetIntent(from url: URL) {
    guard url.scheme == "nyangcoach", url.host == "widget" else { return }

    let parts = url.pathComponents.filter { $0 != "/" }
    let coachId = parts.first ?? "cat"
    let route = parts.dropFirst().first ?? "tasks_remaining_bottom_sheet"
    let defaults = UserDefaults.standard
    defaults.set(route, forKey: "flutter.widget_route")
    defaults.set(coachId, forKey: "flutter.widget_coach_id")
    defaults.synchronize()
  }

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for context in connectionOptions.urlContexts {
      storeWidgetIntent(from: context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      storeWidgetIntent(from: context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
