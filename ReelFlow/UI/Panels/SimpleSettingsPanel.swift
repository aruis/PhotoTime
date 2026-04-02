import SwiftUI

struct SimpleSettingsPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool

    private enum ResolutionChoice: Int, CaseIterable, Identifiable {
        case hd720
        case fullHD1080
        case qhd1440
        case uhd4K

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .hd720: return "720p"
            case .fullHD1080: return "1080p"
            case .qhd1440: return "1440p"
            case .uhd4K: return "4K"
            }
        }

        var size: (width: Int, height: Int) {
            switch self {
            case .hd720: return (1280, 720)
            case .fullHD1080: return (1920, 1080)
            case .qhd1440: return (2560, 1440)
            case .uhd4K: return (3840, 2160)
            }
        }
    }

    private enum DurationChoice: String, CaseIterable, Identifiable {
        case quick
        case standard
        case relaxed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .quick: return "快节奏"
            case .standard: return "标准"
            case .relaxed: return "舒缓"
            }
        }

        var subtitle: String? {
            switch self {
            case .quick: return "约 1.5 秒/张"
            case .standard: return "约 2.5 秒/张"
            case .relaxed: return "约 4 秒/张"
            }
        }

        var seconds: Double {
            switch self {
            case .quick: return 1.5
            case .standard: return 2.5
            case .relaxed: return 4.0
            }
        }
    }

    private enum TransitionChoice: String, CaseIterable, Identifiable {
        case off
        case soft
        case standard

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "关闭"
            case .soft: return "柔和"
            case .standard: return "标准"
            }
        }

        var subtitle: String? {
            switch self {
            case .off: return "不使用转场"
            case .soft: return "0.4 秒"
            case .standard: return "0.8 秒"
            }
        }

        var transitionDuration: Double {
            switch self {
            case .off: return 0
            case .soft: return 0.4
            case .standard: return 0.8
            }
        }
    }

    private enum TransitionGapChoice: String, CaseIterable, Identifiable {
        case none
        case short
        case medium

        var id: String { rawValue }

        var title: String {
            switch self {
            case .none: return "无"
            case .short: return "短"
            case .medium: return "中"
            }
        }

        var subtitle: String? {
            switch self {
            case .none: return "无空窗"
            case .short: return "0.18 秒"
            case .medium: return "0.36 秒"
            }
        }

        var duration: Double {
            switch self {
            case .none: return 0
            case .short: return 0.18
            case .medium: return 0.36
            }
        }
    }

    private enum KenBurnsChoice: String, CaseIterable, Identifiable {
        case off
        case subtle
        case standard

        var id: String { rawValue }

        var title: String {
            switch self {
            case .off: return "关闭"
            case .subtle: return "轻微"
            case .standard: return "标准"
            }
        }

        var subtitle: String? {
            switch self {
            case .off: return "无动效"
            case .subtle: return "更克制"
            case .standard: return "标准幅度"
            }
        }
    }

    private enum PlateFontSizeChoice: Int, CaseIterable, Identifiable {
        case small = 22
        case medium = 26
        case large = 32

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .small: return "小"
            case .medium: return "中"
            case .large: return "大"
            }
        }
    }

    var body: some View {
        Form {
            Section("快速设置") {
                if let settingsValidationMessage {
                    settingsValidationView(settingsValidationMessage)
                }

                Picker("分辨率", selection: resolutionBinding) {
                    ForEach(ResolutionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .disabled(viewModel.isBusy)

                Picker("FPS", selection: $viewModel.config.fps) {
                    ForEach([24, 30, 60], id: \.self) { fps in
                        Text("\(fps)").tag(fps)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("展示节奏")
                        .font(.subheadline.weight(.medium))
                    choiceGrid(
                        DurationChoice.allCases,
                        selection: imageDurationBinding,
                        title: \DurationChoice.title,
                        subtitle: \DurationChoice.subtitle
                    )
                }
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("转场")
                        .font(.subheadline.weight(.medium))
                    choiceGrid(
                        TransitionChoice.allCases,
                        selection: transitionBinding,
                        title: \TransitionChoice.title,
                        subtitle: \TransitionChoice.subtitle
                    )
                }
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 6) {
                    Text("背景空窗")
                        .font(.subheadline.weight(.medium))
                    choiceGrid(
                        TransitionGapChoice.allCases,
                        selection: transitionGapBinding,
                        title: \TransitionGapChoice.title,
                        subtitle: \TransitionGapChoice.subtitle
                    )
                    .disabled(viewModel.isBusy)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Ken Burns")
                        .font(.subheadline.weight(.medium))
                    choiceGrid(
                        KenBurnsChoice.allCases,
                        selection: kenBurnsBinding,
                        title: \KenBurnsChoice.title,
                        subtitle: \KenBurnsChoice.subtitle
                    )
                }
                .disabled(viewModel.isBusy)
            }

            Section("画面风格") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("横竖图策略")
                        .font(.subheadline.weight(.medium))
                    HStack(spacing: 8) {
                        orientationChoiceButton(
                            title: PhotoOrientationStrategy.followAsset.displayName,
                            strategy: .followAsset
                        )
                        orientationChoiceButton(
                            title: PhotoOrientationStrategy.forceLandscape.displayName,
                            strategy: .forceLandscape
                        )
                        orientationChoiceButton(
                            title: PhotoOrientationStrategy.forcePortrait.displayName,
                            strategy: .forcePortrait
                        )
                    }
                }
                .disabled(viewModel.isBusy)

                VStack(alignment: .leading, spacing: 8) {
                    Text("相框风格")
                        .font(.subheadline.weight(.medium))
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                        ForEach(FrameStylePreset.allCases.filter { $0 != .custom }, id: \.self) { preset in
                            frameStyleChoiceButton(
                                title: preset.displayName,
                                preset: preset
                            )
                        }
                    }
                }
                .disabled(viewModel.isBusy)
            }

            Section("文字信息") {
                Toggle("显示底部铭牌文字", isOn: $viewModel.config.plateEnabled)
                    .disabled(viewModel.isBusy)

                Picker("信息位置", selection: $viewModel.config.platePlacement) {
                    Text("相框").tag(PlatePlacement.frame)
                    Text("黑底下方").tag(PlatePlacement.canvasBottom)
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)

                Picker("字号", selection: plateFontSizeChoiceBinding) {
                    ForEach(PlateFontSizeChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)

                Text("前缀、字段排序和模板编辑请切到“高级”模式。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            AudioSettingsSection(
                viewModel: viewModel,
                isAudioDropTarget: $isAudioDropTarget,
                onAudioDrop: onAudioDrop
            )
        }
        .formStyle(.grouped)
    }

    private var settingsValidationMessage: String? {
        viewModel.validationMessage
    }

    private func settingsValidationView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private func choiceGrid<T: Hashable & Identifiable & CaseIterable>(
        _ choices: T.AllCases,
        selection: Binding<T>,
        title: KeyPath<T, String>,
        subtitle: KeyPath<T, String?>
    ) -> some View where T.AllCases: RandomAccessCollection, T.AllCases.Element == T {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
            ForEach(Array(choices)) { choice in
                let isSelected = selection.wrappedValue == choice
                Button {
                    selection.wrappedValue = choice
                } label: {
                    VStack(spacing: 4) {
                        Text(choice[keyPath: title])
                            .font(.caption.weight(.semibold))
                        if let subtitle = choice[keyPath: subtitle] {
                            Text(subtitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.4 : 1)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var plateFontSizeChoiceBinding: Binding<PlateFontSizeChoice> {
        Binding(
            get: {
                let size = viewModel.config.plateFontSize
                return PlateFontSizeChoice.allCases.min(by: {
                    abs(Double($0.rawValue) - size) < abs(Double($1.rawValue) - size)
                }) ?? .medium
            },
            set: { choice in
                viewModel.config.plateFontSize = Double(choice.rawValue)
            }
        )
    }

    private var resolutionBinding: Binding<ResolutionChoice> {
        Binding(
            get: {
                switch (viewModel.config.outputWidth, viewModel.config.outputHeight) {
                case (1280, 720): return .hd720
                case (1920, 1080): return .fullHD1080
                case (2560, 1440): return .qhd1440
                case (3840, 2160): return .uhd4K
                default: return .fullHD1080
                }
            },
            set: { choice in
                let size = choice.size
                viewModel.config.outputWidth = size.width
                viewModel.config.outputHeight = size.height
            }
        )
    }

    private var imageDurationBinding: Binding<DurationChoice> {
        Binding(
            get: {
                let value = viewModel.config.imageDuration
                return DurationChoice.allCases.min(by: { abs($0.seconds - value) < abs($1.seconds - value) }) ?? .standard
            },
            set: { choice in
                viewModel.config.setImageDurationSafely(choice.seconds)
            }
        )
    }

    private var transitionBinding: Binding<TransitionChoice> {
        Binding(
            get: {
                if !viewModel.config.enableCrossfade || viewModel.config.transitionDuration <= 0.001 {
                    return .off
                }
                let duration = viewModel.config.transitionDuration
                let candidates: [TransitionChoice] = [.soft, .standard]
                return candidates.min(by: { abs($0.transitionDuration - duration) < abs($1.transitionDuration - duration) }) ?? .standard
            },
            set: { choice in
                if choice == .off {
                    viewModel.config.enableCrossfade = false
                    viewModel.config.setTransitionDurationSafely(0)
                    return
                }
                viewModel.config.enableCrossfade = true
                viewModel.config.setTransitionDurationSafely(choice.transitionDuration)
            }
        )
    }

    private var transitionGapBinding: Binding<TransitionGapChoice> {
        Binding(
            get: {
                let value = viewModel.config.transitionDipDuration
                return TransitionGapChoice.allCases.min(by: {
                    abs($0.duration - value) < abs($1.duration - value)
                }) ?? .short
            },
            set: { choice in
                viewModel.config.transitionDipDuration = choice.duration
            }
        )
    }

    private var kenBurnsBinding: Binding<KenBurnsChoice> {
        Binding(
            get: {
                guard viewModel.config.enableKenBurns else { return .off }
                switch viewModel.config.kenBurnsIntensity {
                case .small: return .subtle
                case .medium, .large: return .standard
                }
            },
            set: { choice in
                switch choice {
                case .off:
                    viewModel.config.enableKenBurns = false
                case .subtle:
                    viewModel.config.enableKenBurns = true
                    viewModel.config.kenBurnsIntensity = .small
                case .standard:
                    viewModel.config.enableKenBurns = true
                    viewModel.config.kenBurnsIntensity = .medium
                }
            }
        )
    }

    private func orientationChoiceButton(title: String, strategy: PhotoOrientationStrategy) -> some View {
        let isSelected = viewModel.config.orientationStrategy == strategy
        return Button {
            viewModel.config.orientationStrategy = strategy
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                Text(title)
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 32)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.4 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func frameStyleChoiceButton(title: String, preset: FrameStylePreset) -> some View {
        let isSelected = viewModel.config.frameStylePreset == preset
        return Button {
            viewModel.config.frameStylePreset = preset
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.secondary.opacity(0.08))
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity, minHeight: 34)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 1.4 : 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
