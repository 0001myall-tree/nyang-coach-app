import Flutter
import UIKit
import UserNotifications
import WidgetKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let widgetStatusChannel = "nyang_coach/widget_status"

  private func reloadWidgetsIfAvailable() {
    if #available(iOS 14.0, *) {
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  private func storeWidgetIntent(from url: URL) {
    guard url.scheme == "nyangcoach", url.host == "widget" else { return }

    let parts = url.pathComponents.filter { $0 != "/" }
    let coachId = parts.first ?? "cat"
    let route = parts.dropFirst().first ?? "tasks"
    let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
    let defaults = UserDefaults.standard
    defaults.set(route, forKey: "flutter.widget_route")
    defaults.set(coachId, forKey: "flutter.widget_coach_id")
    for item in queryItems {
      if item.name == "date" {
        defaults.set(item.value, forKey: "flutter.widget_date")
      } else if item.name == "id" {
        defaults.set(item.value, forKey: "flutter.widget_item_id")
      }
    }
    defaults.synchronize()
  }

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: widgetStatusChannel,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { call, result in
        if call.method == "hasInstalledCatHomeWidget" {
          self.hasInstalledCatHomeWidget(result: result)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }
    if let url = launchOptions?[.url] as? URL {
      storeWidgetIntent(from: url)
    }
    reloadWidgetsIfAvailable()
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

  private func hasInstalledCatHomeWidget(result: @escaping FlutterResult) {
    guard #available(iOS 14.0, *) else {
      result(false)
      return
    }

    WidgetCenter.shared.getCurrentConfigurations { configurationsResult in
      switch configurationsResult {
      case .success(let widgets):
        let hasCatWidget = widgets.contains { info in
          info.kind == "NyangWidget" || info.kind == "NyangCompactWidget"
        }
        DispatchQueue.main.async {
          result(hasCatWidget)
        }
      case .failure:
        DispatchQueue.main.async {
          result(false)
        }
      }
    }
  }
}
