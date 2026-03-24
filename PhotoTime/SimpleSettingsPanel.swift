import SwiftUI

struct SimpleSettingsPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool
    @State private var isPlateReordering = false
    @State private var plateSimplePrefixDrafts: [PlateSimpleElementKey: String] = [:]
    @FocusState private var focusedPlatePrefixKey: PlateSimpleElementKey?

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

        var transitionDuration: Double {
            switch self {
            case .off: return 0
            case .soft: return 0.4
            case .standard: return 0.8
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
            Section("常用参数") {
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

                Picker("展示节奏", selection: imageDurationBinding) {
                    ForEach(DurationChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)

                Picker("转场", selection: transitionBinding) {
                    ForEach(TransitionChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy)

                Toggle("启用 Ken Burns", isOn: $viewModel.config.enableKenBurns)
                    .disabled(viewModel.isBusy)

                Toggle("显示底部铭牌文字", isOn: $viewModel.config.plateEnabled)
                    .disabled(viewModel.isBusy)

                Picker("信息位置", selection: $viewModel.config.platePlacement) {
                    Text("相框").tag(PlatePlacement.frame)
                    Text("黑底下方").tag(PlatePlacement.canvasBottom)
                }
                .pickerStyle(.segmented)
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)

                plateContentEditor
                    .disabled(viewModel.isBusy)
            }

            Section("风格") {
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

    private var plateContentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("铭牌编辑", selection: plateEditorModeBinding) {
                ForEach(PlateEditorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if effectivePlateEditorMode == .simple {
                Picker("字号", selection: plateFontSizeChoiceBinding) {
                    ForEach(PlateFontSizeChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            } else if effectivePlateEditorMode == .custom {
                customPlateFontSizeControl
            }

            if effectivePlateEditorMode == .simple {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("显示项目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("恢复默认") {
                            commitAllPlateSimpleDrafts()
                            viewModel.config.resetSimplePlateElementsToDefault()
                            isPlateReordering = false
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        Button {
                            commitAllPlateSimpleDrafts()
                            isPlateReordering.toggle()
                        } label: {
                            Label(isPlateReordering ? "完成" : "排序", systemImage: isPlateReordering ? "checkmark" : "arrow.up.arrow.down")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule(style: .continuous)
                                        .fill(Color.white.opacity(isPlateReordering ? 0.08 : 0.04))
                                )
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(Color.white.opacity(isPlateReordering ? 0.12 : 0.06), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(isPlateReordering ? .primary : .secondary)
                    }

                    List {
                        ForEach(viewModel.config.plateSimpleElements.indices, id: \.self) { index in
                            let key = viewModel.config.plateSimpleElements[index].key
                            let isEnabled = viewModel.config.plateSimpleElements[index].enabled
                            GeometryReader { geometry in
                                let inputWidth = max(96, geometry.size.width * 0.3)

                                HStack(spacing: 10) {
                                    Toggle("", isOn: $viewModel.config.plateSimpleElements[index].enabled)
                                        .labelsHidden()
                                        .focusable(false)

                                    Text(key.displayName)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(isEnabled ? .primary : .secondary)
                                        .frame(width: 44, alignment: .leading)

                                    Spacer(minLength: 0)

                                    TextField(
                                        "前缀",
                                        text: prefixDraftBinding(for: $viewModel.config.plateSimpleElements[index]),
                                        onEditingChanged: { editing in
                                            if !editing {
                                                commitPrefixDraft(for: key)
                                            }
                                        },
                                        onCommit: {
                                            commitPrefixDraft(for: key)
                                        }
                                    )
                                    .textFieldStyle(.plain)
                                    .font(.system(.caption, design: .monospaced))
                                    .focused($focusedPlatePrefixKey, equals: key)
                                    .frame(width: inputWidth, alignment: .leading)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 6)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(focusedPlatePrefixKey == key ? Color.white.opacity(0.06) : .clear)
                                    )
                                    .overlay(
                                        Rectangle()
                                            .fill(Color.white.opacity(focusedPlatePrefixKey == key ? 0.34 : (isEnabled ? 0.16 : 0.08)))
                                            .frame(height: 1),
                                        alignment: .bottom
                                    )
                                    .disabled(isPlateReordering)

                                    if isPlateReordering {
                                        Image(systemName: "line.3.horizontal")
                                            .font(.caption)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            .frame(height: 22)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .fill(Color.white.opacity(isEnabled ? 0.035 : 0.015))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.white.opacity(isEnabled ? 0.06 : 0.03), lineWidth: 1)
                            )
                            .opacity(isEnabled ? 1 : 0.58)
                            .animation(.easeInOut(duration: 0.12), value: isEnabled)
                            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                            .listRowBackground(Color.clear)
                            .moveDisabled(!isPlateReordering)
                        }
                        .onMove(perform: moveSimpleElements)
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.hidden)
                    .frame(height: plateSimpleListHeight)
                }
            } else if effectivePlateEditorMode == .custom {
                Text("模板（可直接编辑，占位符可用按钮插入）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                customPlateTemplateEditor

                Text("可用占位符：{camera} {lens} {shutter} {aperture} {iso} {focal} {date}")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                plateTemplatePreview

                HStack(spacing: 6) {
                    plateTokenButton(title: "快门", token: "{shutter}")
                    plateTokenButton(title: "光圈", token: "{aperture}")
                    plateTokenButton(title: "ISO", token: "{iso}")
                    plateTokenButton(title: "焦距", token: "{focal}")
                    plateTokenButton(title: "日期", token: "{date}")
                    plateTokenButton(title: "机型", token: "{camera}")
                    plateTokenButton(title: "镜头", token: "{lens}")
                }

                HStack {
                    Spacer(minLength: 0)
                    Button("恢复默认") {
                        viewModel.config.resetPlateTemplateToDefault()
                    }
                    Button("清空") {
                        viewModel.config.plateTemplateText = ""
                    }
                }
            } else {
                Text("已关闭铭牌文字")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var plateEditorModeBinding: Binding<PlateEditorMode> {
        Binding(
            get: {
                effectivePlateEditorMode
            },
            set: { mode in
                viewModel.config.plateEditorMode = mode
                viewModel.config.plateEnabled = mode != .none
                if mode != .simple {
                    isPlateReordering = false
                }
                if mode == .simple, viewModel.config.plateSimpleElements.isEmpty {
                    viewModel.config.plateSimpleElements = PlateSimpleElement.default
                }
            }
        )
    }

    private var effectivePlateEditorMode: PlateEditorMode {
        viewModel.config.plateEnabled ? viewModel.config.plateEditorMode : .none
    }

    private func plateTokenButton(title: String, token: String) -> some View {
        Button(title) {
            viewModel.config.insertPlateToken(token)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func prefixDraftBinding(for element: Binding<PlateSimpleElement>) -> Binding<String> {
        Binding(
            get: { plateSimplePrefixDrafts[element.wrappedValue.key] ?? element.wrappedValue.prefix },
            set: { plateSimplePrefixDrafts[element.wrappedValue.key] = $0 }
        )
    }

    private func settingsValidationView(_ message: String) -> some View {
        Label(message, systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.red)
    }

    private var customPlateTemplateEditor: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $viewModel.config.plateTemplateText)
                .font(.system(.caption, design: .monospaced))
                .frame(minHeight: 88)
                .padding(8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

            if viewModel.config.plateTemplateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(PlateSettings.defaultTemplateText)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
                    .allowsHitTesting(false)
            }
        }
    }

    private var plateTemplatePreview: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("示例预览")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(samplePlatePreviewText)
                .font(.system(.caption, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private var samplePlatePreviewText: String {
        sampleExif.resolvedPlateText(template: viewModel.config.plateTemplateText)
    }

    private var sampleExif: ExifInfo {
        ExifInfo(
            shutter: "1/125",
            aperture: "2.8",
            iso: "400",
            focalLength: "35",
            date: "2026-02-06",
            camera: "Leica Q3",
            lens: "Summilux 28"
        )
    }

    private func commitPrefixDraft(for key: PlateSimpleElementKey) {
        guard let draft = plateSimplePrefixDrafts[key] else { return }
        guard let index = viewModel.config.plateSimpleElements.firstIndex(where: { $0.key == key }) else {
            plateSimplePrefixDrafts.removeValue(forKey: key)
            return
        }
        viewModel.config.plateSimpleElements[index].prefix = draft
        plateSimplePrefixDrafts.removeValue(forKey: key)
    }

    private func commitAllPlateSimpleDrafts() {
        for key in Array(plateSimplePrefixDrafts.keys) {
            commitPrefixDraft(for: key)
        }
    }

    private func moveSimpleElements(from source: IndexSet, to destination: Int) {
        commitAllPlateSimpleDrafts()
        viewModel.config.moveSimplePlateElements(from: source, to: destination)
    }

    private var plateSimpleListHeight: CGFloat {
        let rowHeight: CGFloat = 44
        let verticalSpacing: CGFloat = 4
        let contentPadding: CGFloat = 4
        let count = CGFloat(viewModel.config.plateSimpleElements.count)
        return count * rowHeight + max(0, count - 1) * verticalSpacing + contentPadding
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

    private var customPlateFontSizeControl: some View {
        LabeledContent("字号") {
            HStack(spacing: 4) {
                HStack(spacing: 4) {
                    TextField(
                        "",
                        value: $viewModel.config.plateFontSize,
                        format: .number.precision(.fractionLength(0...1))
                    )
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 44)

                    Text("点")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 10, alignment: .leading)
                }
                .frame(width: 78, height: 28)
                .padding(.horizontal, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )

                Stepper("", value: $viewModel.config.plateFontSize, in: RenderEditorConfig.plateFontSizeRange, step: 0.5)
                    .labelsHidden()
                    .controlSize(.small)
            }
            .frame(minHeight: 28)
        }
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
                viewModel.config.imageDuration = choice.seconds
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
                    viewModel.config.transitionDuration = 0
                    return
                }
                viewModel.config.enableCrossfade = true
                viewModel.config.transitionDuration = choice.transitionDuration
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
