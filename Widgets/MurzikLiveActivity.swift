import ActivityKit
import SwiftUI
import WidgetKit

@main
struct MurzikWidgetBundle: WidgetBundle {
    var body: some Widget {
        MurzikLiveActivity()
    }
}

struct MurzikLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MurzikAttributes.self) { context in
            LockScreenView(name: context.attributes.name, state: context.state, isStale: context.isStale)
                .activityBackgroundTint(Color.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            let mood = context.state.displayMood(isStale: context.isStale)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExpandedLeadingView(mood: mood)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    ExpandedTrailingView(mood: mood)
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenterView(name: context.attributes.name, mood: mood)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedBottomView(state: context.state, isStale: context.isStale)
                }
            } compactLeading: {
                CompactLeadingView(mood: mood)
            } compactTrailing: {
                CompactTrailingView(mood: mood)
            } minimal: {
                MinimalView(mood: mood)
            }
            .keylineTint(MurzikPalette.eyeCenter)
            .widgetURL(URL(string: "murzik://open"))
        }
    }
}
