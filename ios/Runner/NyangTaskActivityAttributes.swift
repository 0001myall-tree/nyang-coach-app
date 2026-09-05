import Foundation

#if canImport(ActivityKit)
import ActivityKit

/// 진행 중인 일정을 잠금화면과 다이내믹 아일랜드에 띄우기 위한 자료.
///
/// 앱과 위젯 확장이 같은 타입을 봐야 해서 이 파일은 두 타깃 모두에 들어간다.
/// 아이폰에서는 다른 앱 위에 무언가를 그릴 수 없기 때문에, 안드로이드의
/// "가장자리에 잠깐 나타나는 냥냥이" 자리를 이것이 대신한다. 잠깐 나왔다
/// 사라지는 대신 일정 내내 조용히 떠 있는다.
@available(iOS 16.1, *)
struct NyangTaskActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// 일정 이름.
        var taskText: String

        /// 흐른 시간을 셀 기준점. 이미 쌓인 시간만큼 과거로 당겨서 넘긴다.
        var startedAt: Date

        /// 흐르는 시간을 보여줄지.
        ///
        /// 할 일 화면의 타이머를 끈 사람에게는 여기서도 숫자를 안 보여준다.
        /// 타이머를 끄는 이유는 대개 쫓기는 느낌이 싫어서인데, 잠금화면은 앱보다
        /// 더 자주 눈에 띄는 자리라 거기서 계속 흐르면 끈 의미가 없어진다.
        ///
        /// 예전 버전이 보낸 값에는 이 항목이 없다. 그때는 보여주는 쪽이 맞다 —
        /// 그게 여태 하던 일이다.
        var showsTimer: Bool = true
    }

    /// 어떤 일정인지. 눌러서 앱에 들어왔을 때 그 일정을 찾는 데 쓴다.
    var taskId: String
}
#endif
