import SwiftUI
import UIKit

/// Settings: where Murzik lives (Dynamic Island, in-app walker), sound, haptics, name, and a little
/// "us" corner with the love streak, gifts and today's mood diary.
struct SettingsSheet: View {
    @EnvironmentObject private var model: PetModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @AppStorage(ExperienceSettings.walkerKey) private var walkerEnabled = true
    @AppStorage(ExperienceSettings.soundKey) private var soundEnabled = true
    @AppStorage(ExperienceSettings.hapticsKey) private var hapticsEnabled = true
    @AppStorage(ExperienceSettings.showNameKey) private var showName = true

    var body: some View {
        ZStack {
            LinearGradient(colors: [MurzikPalette.cream, MurzikPalette.sand], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    hero
                    section(Strings.sectionWhereHeLives) {
                        islandRow
                        if model.islandStatus == .disabledBySystem {
                            systemDisabledNotice
                        }
                        rowDivider
                        SettingToggleRow(
                            symbol: "figure.walk", tint: MurzikPalette.mint,
                            title: Strings.walkerTitle, subtitle: Strings.walkerSubtitle,
                            isOn: $walkerEnabled, identifier: "settings.walker"
                        )
                    }
                    section(Strings.sectionFeel) {
                        SettingToggleRow(
                            symbol: "speaker.wave.2.fill", tint: MurzikPalette.amber,
                            title: Strings.soundTitle, subtitle: Strings.soundSubtitle,
                            isOn: $soundEnabled, identifier: "settings.sound"
                        )
                        rowDivider
                        SettingToggleRow(
                            symbol: "hand.tap.fill", tint: MurzikPalette.heart,
                            title: Strings.hapticsTitle, subtitle: Strings.hapticsSubtitle,
                            isOn: $hapticsEnabled, identifier: "settings.haptics"
                        )
                        rowDivider
                        SettingToggleRow(
                            symbol: "textformat", tint: MurzikPalette.sky,
                            title: Strings.showNameTitle, subtitle: Strings.showNameSubtitle,
                            isOn: $showName, identifier: "settings.name"
                        )
                    }
                    section(Strings.sectionUs) {
                        statsGrid
                        rowDivider
                        moodDiary
                    }
                    Label(Strings.madeWithLove, systemImage: "heart.fill")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(MurzikPalette.inkSoft)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 20)
                .padding(.top, 22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
        }
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Text(Strings.settingsTitle)
                .font(.system(size: 30, weight: .heavy, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button {
                dismiss()
            } label: {
                Text(Strings.settingsDone)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(MurzikPalette.ink))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings.done")
        }
    }

    private var hero: some View {
        HStack(spacing: 14) {
            CatFace(mood: model.mood)
                .frame(width: 64, height: 64)
                .padding(6)
                .background(Circle().fill(Color(red: 0.18, green: 0.17, blue: 0.22)))
            VStack(alignment: .leading, spacing: 4) {
                Text(Strings.name)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                HStack(spacing: 6) {
                    Image(systemName: model.mood.symbolName)
                        .foregroundStyle(MurzikPalette.accent(for: model.mood))
                    Text(Strings.moodMessage(model.mood))
                        .foregroundStyle(MurzikPalette.inkSoft)
                }
                .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(cardBackground)
        .accessibilityElement(children: .combine)
    }

    // MARK: Island

    private var islandRow: some View {
        HStack(spacing: 12) {
            IslandPreview(mood: model.mood)
            VStack(alignment: .leading, spacing: 3) {
                Text(Strings.islandTitle)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                IslandStatusText()
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
            }
            Spacer(minLength: 0)
            Toggle(isOn: Binding(
                get: { model.islandEnabled },
                set: { model.setIslandEnabled($0) }
            )) {
                Text(Strings.islandTitle)
            }
            .labelsHidden()
            .tint(MurzikPalette.amber)
            .accessibilityIdentifier("settings.island")
        }
    }

    private var systemDisabledNotice: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(Strings.islandDisabledBySystem, systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(red: 0.72, green: 0.38, blue: 0.10))
            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
            } label: {
                Text(Strings.openSystemSettings)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(MurzikPalette.amber.opacity(0.25)))
            }
            .buttonStyle(PressableStyle())
            .accessibilityIdentifier("settings.openSystem")
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MurzikPalette.amber.opacity(0.12)))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: Us

    private var statsGrid: some View {
        let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: columns, spacing: 12) {
            StatTile(symbol: "heart.fill", tint: MurzikPalette.heart, value: "\(model.loveToday)", label: Strings.loveToday)
            StatTile(symbol: "flame.fill", tint: MurzikPalette.amber, value: "\(model.streak)", label: Strings.streak)
            StatTile(symbol: "gift.fill", tint: MurzikPalette.mint, value: "\(model.bond.giftsReceived)", label: Strings.gifts)
            StatTile(symbol: "waveform", tint: MurzikPalette.sky,
                     value: "\(Int((model.bond.purrSeconds / 60).rounded()))", label: Strings.purrTime)
        }
    }

    private var moodDiary: some View {
        let today = model.moodsToday
        return VStack(alignment: .leading, spacing: 10) {
            Text(Strings.todaysMoods)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(MurzikPalette.ink)
            if today.isEmpty {
                Text(Strings.noMoodsYet)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 10) {
                        ForEach(Array(today.suffix(24).reversed().enumerated()), id: \.offset) { _, sample in
                            MoodDot(sample: sample)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    // MARK: Layout helpers

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(Color.white.opacity(0.86))
            .shadow(color: MurzikPalette.ink.opacity(0.06), radius: 10, y: 4)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(MurzikPalette.sand)
            .frame(height: 1)
            .padding(.vertical, 2)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(MurzikPalette.inkSoft)
                .padding(.horizontal, 6)
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(16)
            .background(cardBackground)
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: model.islandStatus)
    }
}

// MARK: - Rows

struct SettingToggleRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool
    let identifier: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(tint.gradient))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle(isOn: $isOn) { Text(title) }
                .labelsHidden()
                .tint(MurzikPalette.amber)
                .accessibilityIdentifier(identifier)
                .accessibilityHint(Text(subtitle))
        }
    }
}

struct StatTile: View {
    let symbol: String
    let tint: Color
    let value: String
    let label: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 34, height: 34)
                .background(Circle().fill(tint.opacity(0.15)))
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundStyle(MurzikPalette.ink)
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(MurzikPalette.inkSoft)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(MurzikPalette.cream))
        .accessibilityElement(children: .combine)
    }
}

struct MoodDot: View {
    let sample: MoodSample

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: sample.mood.symbolName)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(MurzikPalette.accent(for: sample.mood))
                .frame(width: 38, height: 38)
                .background(Circle().fill(MurzikPalette.accent(for: sample.mood).opacity(0.16)))
            Text(sample.date, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(MurzikPalette.inkSoft)
                .monospacedDigit()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(Strings.moodTitle(sample.mood)))
        .accessibilityValue(Text(sample.date, style: .time))
    }
}

/// Live status of the Dynamic Island Live Activity.
struct IslandStatusText: View {
    @EnvironmentObject private var model: PetModel

    var body: some View {
        switch model.islandStatus {
        case let .running(endsAt):
            if let endsAt, endsAt > model.now {
                HStack(spacing: 4) {
                    Text(Strings.islandEndsIn)
                    Text(timerInterval: model.now...endsAt, countsDown: true)
                        .monospacedDigit()
                }
            } else {
                Text(Strings.islandOn)
            }
        case .off:
            Text(model.islandEnabled ? Strings.islandSubtitle : Strings.islandOff)
        case .disabledBySystem:
            Text(Strings.islandDisabledBySystem)
        case .failed:
            Text(Strings.islandStartFailed)
        }
    }
}
