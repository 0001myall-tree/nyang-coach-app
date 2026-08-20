import Flutter
import UIKit
import WidgetKit

class SceneDelegate: FlutterSceneDelegate {
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

  override func scene(
    _ scene: UIScene,
    willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions
  ) {
    for context in connectionOptions.urlContexts {
      storeWidgetIntent(from: context.url)
    }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
    registerNativeChannels(in: scene)
  }

  /// 네이티브 채널은 창이 생긴 뒤에 붙여야 한다.
  ///
  /// AppDelegate에서 붙이고 있었는데, 씬을 쓰는 앱에서는 그 시점의 window가 nil이라
  /// 등록이 통째로 건너뛰어졌다. Flutter 쪽 호출은 전부 조용히 실패했고 — 그쪽 코드가
  /// MissingPluginException을 삼키고 "할 수 없음"으로 처리한다 — 그래서 라이브
  /// 액티비티가 아이폰 설정에서 꺼진 것처럼 보이고, 설정을 열어달라는 요청은
  /// 아무 일도 일어나지 않았다.
  private func registerNativeChannels(in scene: UIScene) {
    let fromScene = (scene as? UIWindowScene)?
      .windows
      .compactMap { $0.rootViewController as? FlutterViewController }
      .first
    guard let controller = fromScene ?? (window?.rootViewController as? FlutterViewController)
    else { return }
    (UIApplication.shared.delegate as? AppDelegate)?
      .registerNativeChannels(with: controller)
  }


  override func sceneDidBecomeActive(_ scene: UIScene) {
    reloadWidgetsIfAvailable()
    super.sceneDidBecomeActive(scene)
  }

  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      storeWidgetIntent(from: context.url)
    }
    super.scene(scene, openURLContexts: URLContexts)
  }
}
