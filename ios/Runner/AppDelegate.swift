import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
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

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let url = launchOptions?[.url] as? URL {
      storeWidgetIntent(from: url)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    storeWidgetIntent(from: url)
    return super.application(app, open: url, options: options)
  }
}
