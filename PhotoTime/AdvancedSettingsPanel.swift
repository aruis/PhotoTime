import SwiftUI

struct AdvancedSettingsPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool
    @State private var isPlateReordering = false
    @State private var plateSimplePrefixDrafts: [PlateSimpleElementKey: String] = [:]
    @FocusState private var focusedPlatePrefixKey: PlateSimpleElementKey?

    private enum ResolutionPreset: Int, CaseIterable, Identifiable {
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

    var body: some View {
        Form {
            Section("导出设置") {
                if let settingsValidationMessage {
                    settingsValidationView(settingsValidationMessage)
                }

                Stepper("宽: \(viewModel.config.outputWidth)", value: $viewModel.config.outputWidth, in: RenderEditorConfig.outputWidthRange, step: 2)
                    .disabled(viewModel.isBusy)
                Stepper("高: \(viewModel.config.outputHeight)", value: $viewModel.config.outputHeight, in: RenderEditorConfig.outputHeightRange, step: 2)
                    .disabled(viewModel.isBusy)

                HStack(spacing: 6) {
                    ForEach(ResolutionPreset.allCases) { preset in
                        resolutionPresetButton(preset)
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

                VStack(alignment: .leading, spacing: 6) {
                    Text("单图时长: \(viewModel.config.imageDuration, specifier: "%.2f")s")
                    Slider(value: imageDurationBinding, in: RenderEditorConfig.imageDurationRange, step: 0.1)
                        .disabled(viewModel.isBusy)
                }
                Picker("横竖图策略", selection: $viewModel.config.orientationStrategy) {
                    Text(PhotoOrientationStrategy.followAsset.displayName).tag(PhotoOrientationStrategy.followAsset)
                    Text(PhotoOrientationStrategy.forceLandscape.displayName).tag(PhotoOrientationStrategy.forceLandscape)
                    Text(PhotoOrientationStrategy.forcePortrait.displayName).tag(PhotoOrientationStrategy.forcePortrait)
                }
                .disabled(viewModel.isBusy)
                Picker("相框风格", selection: $viewModel.config.frameStylePreset) {
                    ForEach(FrameStylePreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .disabled(viewModel.isBusy)
                if viewModel.config.frameStylePreset == .custom {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("背景灰度: \(viewModel.config.canvasBackgroundGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasBackgroundGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("相纸亮度: \(viewModel.config.canvasPaperWhite, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasPaperWhite, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("边框灰度: \(viewModel.config.canvasStrokeGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasStrokeGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("文字灰度: \(viewModel.config.canvasTextGray, specifier: "%.2f")")
                        Slider(value: $viewModel.config.canvasTextGray, in: RenderEditorConfig.grayRange, step: 0.01)
                            .disabled(viewModel.isBusy)
                    }
                }
                Toggle("启用淡入淡出转场", isOn: $viewModel.config.enableCrossfade)
                    .disabled(viewModel.isBusy)
                VStack(alignment: .leading, spacing: 6) {
                    Text("转场时长: \(viewModel.config.transitionDuration, specifier: "%.2f")s")
                    Slider(value: transitionDurationBinding, in: RenderEditorConfig.transitionDurationRange, step: 0.05)
                        .disabled(viewModel.isBusy || !viewModel.config.enableCrossfade)
                    if let transitionValidationMessage {
                        Text(transitionValidationMessage)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                Toggle("启用 Ken Burns", isOn: $viewModel.config.enableKenBurns)
                    .disabled(viewModel.isBusy)
            }

            Section("高级布局") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("左右留白: \(viewModel.config.horizontalMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.horizontalMargin, in: RenderEditorConfig.horizontalMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("上留白: \(viewModel.config.topMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.topMargin, in: RenderEditorConfig.topMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("下留白: \(viewModel.config.bottomMargin, specifier: "%.0f")")
                    Slider(value: $viewModel.config.bottomMargin, in: RenderEditorConfig.bottomMarginRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("内边距: \(viewModel.config.innerPadding, specifier: "%.0f")")
                    Slider(value: $viewModel.config.innerPadding, in: RenderEditorConfig.innerPaddingRange, step: 1)
                        .disabled(viewModel.isBusy)
                }
                Toggle("显示底部铭牌文字", isOn: $viewModel.config.plateEnabled)
                    .disabled(viewModel.isBusy)
                Picker("信息位置", selection: $viewModel.config.platePlacement) {
                    Text("相框").tag(PlatePlacement.frame)
                    Text("黑底下方").tag(PlatePlacement.canvasBottom)
                }
                .disabled(viewModel.isBusy || !viewModel.config.plateEnabled)

                plateContentEditor
                    .disabled(viewModel.isBusy)
            }

            Section("性能设置") {
                Stepper("预取半径: \(viewModel.config.prefetchRadius)", value: $viewModel.config.prefetchRadius, in: RenderEditorConfig.prefetchRadiusRange)
                    .disabled(viewModel.isBusy)
                Stepper("预取并发: \(viewModel.config.prefetchMaxConcurrent)", value: $viewModel.config.prefetchMaxConcurrent, in: RenderEditorConfig.prefetchMaxConcurrentRange)
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

    private var transitionValidationMessage: String? {
        guard viewModel.config.enableCrossfade else { return nil }
        guard viewModel.config.transitionDuration >= viewModel.config.imageDuration else { return nil }
        return "转场时长必须小于单图时长，请缩短转场或延长单图时长。"
    }

    private func resolutionPresetButton(_ preset: ResolutionPreset) -> some View {
        let isSelected = viewModel.config.outputWidth == preset.size.width && viewModel.config.outputHeight == preset.size.height
        return Button {
            viewModel.config.outputWidth = preset.size.width
            viewModel.config.outputHeight = preset.size.height
        } label: {
            Text(preset.title)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(isSelected ? .accentColor : .gray.opacity(0.35))
    }

    private var imageDurationBinding: Binding<Double> {
        Binding(
            get: { viewModel.config.imageDuration },
            set: { viewModel.config.setImageDurationSafely($0) }
        )
    }

    private var transitionDurationBinding: Binding<Double> {
        Binding(
            get: { viewModel.config.transitionDuration },
            set: { viewModel.config.setTransitionDurationSafely($0) }
        )
    }

    private var plateContentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("铭牌编辑", selection: plateEditorModeBinding) {
                ForEach(PlateEditorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if effectivePlateEditorMode != .none {
                HStack(spacing: 10) {
                    Text("字号")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 0) {
                        TextField(
                            "字号",
                            value: $viewModel.config.plateFontSize,
                            format: .number.precision(.fractionLength(0...1))
                        )
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 54)

                        Text("点")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 6)
                    }
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.secondary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )

                    Stepper("", value: $viewModel.config.plateFontSize, in: RenderEditorConfig.plateFontSizeRange, step: 0.5)
                        .labelsHidden()
                        .controlSize(.small)
                }
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
}
