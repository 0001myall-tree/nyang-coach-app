import Flutter
import UIKit
import UserNotifications
import WidgetKit
#if canImport(ActivityKit)
import ActivityKit
#endif

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let widgetStatusChannel = "nyang_coach/widget_status"
  private let ongoingNudgeChannel = "nyang_coach/ongoing_nudge"

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
    // 이 앱은 UIScene을 쓴다. 그러면 창을 만드는 것은 SceneDelegate이고, 여기서는
    // window가 아직 nil이다 — 아래 등록이 통째로 건너뛰어진다. 그래서 SceneDelegate가
    // 창을 세운 뒤에 한 번 더 부른다. 여기 남겨두는 것은 씬을 쓰지 않는 경우를 위한
    // 것이고, 두 번 불러도 채널 하나에 최신 핸들러가 붙을 뿐이라 문제가 없다.
    if let controller = window?.rootViewController as? FlutterViewController {
      registerNativeChannels(with: controller)
    }
    if let url = launchOptions?[.url] as? URL {
      storeWidgetIntent(from: url)
    }
    reloadWidgetsIfAvailable()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// 네이티브에만 있는 기능을 Flutter 쪽에 열어준다.
  ///
  /// 등록되지 않으면 Flutter의 호출이 전부 MissingPluginException으로 떨어지는데,
  /// 그쪽 코드는 그것을 조용히 삼키고 "할 수 없음"으로 처리한다. 그래서 라이브
  /// 액티비티가 아이폰 설정에서 꺼진 것처럼 보이고, 설정을 열어달라는 요청은
  /// 아무 일도 일어나지 않은 것처럼 보였다.
  func registerNativeChannels(with controller: FlutterViewController) {
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

    let nudgeChannel = FlutterMethodChannel(
      name: ongoingNudgeChannel,
      binaryMessenger: controller.binaryMessenger
    )
    nudgeChannel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(self.liveActivitiesEnabled())
      case "openSystemSettings":
        self.openAppSettings()
        result(nil)
      case "start":
        let args = call.arguments as? [String: Any] ?? [:]
        let taskId = args["taskId"] as? String ?? ""
        let taskText = args["taskText"] as? String ?? ""
        let startedAtMillis = args["startedAtMillis"] as? NSNumber
        if taskId.isEmpty {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing taskId", details: nil))
          return
        }
        self.startOrUpdateActivity(
          taskId: taskId,
          taskText: taskText,
          startedAtMillis: startedAtMillis?.doubleValue
        )
        result(nil)
      case "stop":
        self.endAllActivities()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  override func application(
    _ app: UIApplication,
    open url: URL,
    options: [UIApplication.OpenURLOptionsKey: Any] = [:]
  ) -> Bool {
    storeWidgetIntent(from: url)
    return super.application(app, open: url, options: options)
  }

  // MARK: - 진행 중인 일정 (라이브 액티비티)

  /// 사용자가 설정에서 라이브 액티비티를 꺼둘 수 있다. 꺼져 있으면 시작해도 뜨지 않는다.
  private func liveActivitiesEnabled() -> Bool {
    #if canImport(ActivityKit)
    if #available(iOS 16.1, *) {
      return ActivityAuthorizationInfo().areActivitiesEnabled
    }
    #endif
    return false
  }

  private func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  /// 같은 일정이면 내용만 갈아끼우고, 다른 일정이면 있던 것을 끝내고 새로 띄운다.
  private func ongoingNudgeLog(_ message: String) {
    NSLog("[OngoingNudge] %@", message)
  }

  private func startOrUpdateActivity(
    taskId: String,
    taskText: String,
    startedAtMillis: Double?
  ) {
    #if canImport(ActivityKit)
    guard #available(iOS 16.1, *) else {
      ongoingNudgeLog("start skipped: iOS < 16.1")
      return
    }

    let authorizationInfo = ActivityAuthorizationInfo()
    guard authorizationInfo.areActivitiesEnabled else {
      ongoingNudgeLog("start skipped: live activities disabled by system")
      return
    }

    let startedAt = startedAtMillis.map { Date(timeIntervalSince1970: $0 / 1000) } ?? Date()
    let state = NyangTaskActivityAttributes.ContentState(
      taskText: taskText,
      startedAt: startedAt
    )

    let running = Activity<NyangTaskActivityAttributes>.activities
    ongoingNudgeLog(
      "start called taskId=\(taskId), taskTextLength=\(taskText.count), runningCount=\(running.count)"
    )
    if let existing = running.first(where: { $0.attributes.taskId == taskId }) {
      ongoingNudgeLog("updating existing activity id=\(existing.id)")
      Task { await existing.update(using: state) }
      return
    }

    for activity in running {
      ongoingNudgeLog("ending existing activity id=\(activity.id), taskId=\(activity.attributes.taskId)")
      Task { await activity.end(dismissalPolicy: .immediate) }
    }

    do {
      let activity = try Activity.request(
        attributes: NyangTaskActivityAttributes(taskId: taskId),
        contentState: state,
        pushType: nil
      )
      ongoingNudgeLog("request succeeded activityId=\(activity.id)")
    } catch {
      ongoingNudgeLog("request failed: \(error.localizedDescription) (\(String(describing: error)))")
    }
    #else
    ongoingNudgeLog("start skipped: ActivityKit cannot be imported")
    #endif
  }

  private func endAllActivities() {
    #if canImport(ActivityKit)
    if #available(iOS 16.1, *) {
      for activity in Activity<NyangTaskActivityAttributes>.activities {
        Task { await activity.end(dismissalPolicy: .immediate) }
      }
    }
    #endif
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
