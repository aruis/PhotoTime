import SwiftUI
import UniformTypeIdentifiers

struct AdvancedSettingsPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool
    @State private var plateLiteralInput = ""
    @State private var isPlateReordering = false
    @State private var plateSimpleDrafts: [PlateSimpleElementKey: String] = [:]
    @State private var draggedPlateSimpleKey: PlateSimpleElementKey?

    var body: some View {
        Form {
            Section("导出设置") {
                Stepper("宽: \(viewModel.config.outputWidth)", value: $viewModel.config.outputWidth, in: RenderEditorConfig.outputWidthRange, step: 2)
                    .disabled(viewModel.isBusy)
                Stepper("高: \(viewModel.config.outputHeight)", value: $viewModel.config.outputHeight, in: RenderEditorConfig.outputHeightRange, step: 2)
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
                    Slider(value: $viewModel.config.imageDuration, in: RenderEditorConfig.imageDurationRange, step: 0.1)
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
                    Slider(value: $viewModel.config.transitionDuration, in: RenderEditorConfig.transitionDurationRange, step: 0.05)
                        .disabled(viewModel.isBusy || !viewModel.config.enableCrossfade)
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

    private var plateContentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("铭牌编辑", selection: plateEditorModeBinding) {
                ForEach(PlateEditorMode.allCases, id: \.self) { mode in
                    Text(mode.displayName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.config.plateEditorMode == .simple {
                HStack {
                    Text("铭牌内容")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(isPlateReordering ? "完成排序" : "排序") {
                        commitAllPlateSimpleDrafts()
                        isPlateReordering.toggle()
                    }
                    .controlSize(.small)
                }
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(viewModel.config.plateSimpleElements.indices, id: \.self) { index in
                            let key = viewModel.config.plateSimpleElements[index].key
                            HStack(spacing: 8) {
                                Toggle("", isOn: $viewModel.config.plateSimpleElements[index].enabled)
                                    .labelsHidden()
                                    .focusable(false)
                                Text(key.displayName)
                                    .frame(width: 72, alignment: .leading)
                                TextField(
                                    "",
                                    text: draftBinding(for: $viewModel.config.plateSimpleElements[index]),
                                    onEditingChanged: { editing in
                                        if !editing {
                                            commitPlateSimpleDraft(for: key)
                                        }
                                    },
                                    onCommit: {
                                        commitPlateSimpleDraft(for: key)
                                    }
                                )
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))
                                .disabled(isPlateReordering)
                                if isPlateReordering {
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                        .onDrag {
                                            draggedPlateSimpleKey = key
                                            return NSItemProvider(object: key.rawValue as NSString)
                                        }

                                    HStack(spacing: 4) {
                                        Button {
                                            moveSimpleElementUp(at: index)
                                        } label: {
                                            Image(systemName: "chevron.up")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(index == 0)

                                        Button {
                                            moveSimpleElementDown(at: index)
                                        } label: {
                                            Image(systemName: "chevron.down")
                                        }
                                        .buttonStyle(.borderless)
                                        .disabled(index == viewModel.config.plateSimpleElements.count - 1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                            .onDrop(
                                of: [UTType.text],
                                delegate: AdvancedPlateRowDropDelegate(
                                    targetKey: key,
                                    draggedKey: $draggedPlateSimpleKey
                                ) { source, target in
                                    moveSimpleElement(source: source, target: target)
                                }
                            )
                        }
                    }
                }
                .frame(minHeight: 170, maxHeight: 220)
            } else if viewModel.config.plateEditorMode == .custom {
                Text("模板（占位符请用按钮插入）")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(viewModel.config.plateTemplateText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))

                HStack(spacing: 6) {
                    plateTokenButton(title: "快门", token: "{shutter}")
                    plateTokenButton(title: "光圈", token: "{aperture}")
                    plateTokenButton(title: "ISO", token: "{iso}")
                    plateTokenButton(title: "焦距", token: "{focal}")
                    plateTokenButton(title: "日期", token: "{date}")
                    plateTokenButton(title: "机型", token: "{camera}")
                    plateTokenButton(title: "镜头", token: "{lens}")
                }

                HStack(spacing: 8) {
                    TextField("追加文字", text: $plateLiteralInput)
                        .textFieldStyle(.roundedBorder)
                    Button("追加") {
                        viewModel.config.appendPlateLiteral(plateLiteralInput)
                        plateLiteralInput = ""
                    }
                    .disabled(plateLiteralInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                viewModel.config.plateEnabled ? viewModel.config.plateEditorMode : .none
            },
            set: { mode in
                viewModel.config.plateEditorMode = mode
                viewModel.config.plateEnabled = mode != .none
                if mode == .simple, viewModel.config.plateSimpleElements.isEmpty {
                    viewModel.config.plateSimpleElements = PlateSimpleElement.default
                }
            }
        )
    }

    private func plateTokenButton(title: String, token: String) -> some View {
        Button(title) {
            viewModel.config.insertPlateToken(token)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    private func draftBinding(for element: Binding<PlateSimpleElement>) -> Binding<String> {
        Binding(
            get: { plateSimpleDrafts[element.wrappedValue.key] ?? element.wrappedValue.templateText },
            set: { plateSimpleDrafts[element.wrappedValue.key] = $0 }
        )
    }

    private func commitPlateSimpleDraft(for key: PlateSimpleElementKey) {
        guard let draft = plateSimpleDrafts[key] else { return }
        guard let index = viewModel.config.plateSimpleElements.firstIndex(where: { $0.key == key }) else {
            plateSimpleDrafts.removeValue(forKey: key)
            return
        }

        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? key.defaultTemplatePart : trimmed
        if viewModel.config.plateSimpleElements[index].templateText != resolved {
            viewModel.config.plateSimpleElements[index].templateText = resolved
        }
        plateSimpleDrafts.removeValue(forKey: key)
    }

    private func commitAllPlateSimpleDrafts() {
        for key in Array(plateSimpleDrafts.keys) {
            commitPlateSimpleDraft(for: key)
        }
    }

    private func moveSimpleElementUp(at index: Int) {
        guard index > 0 else { return }
        commitAllPlateSimpleDrafts()
        viewModel.config.moveSimplePlateElements(from: IndexSet(integer: index), to: index - 1)
    }

    private func moveSimpleElementDown(at index: Int) {
        guard index < viewModel.config.plateSimpleElements.count - 1 else { return }
        commitAllPlateSimpleDrafts()
        viewModel.config.moveSimplePlateElements(from: IndexSet(integer: index), to: index + 2)
    }

    private func moveSimpleElement(source: PlateSimpleElementKey, target: PlateSimpleElementKey) {
        guard source != target else { return }
        guard let fromIndex = viewModel.config.plateSimpleElements.firstIndex(where: { $0.key == source }),
              let toIndex = viewModel.config.plateSimpleElements.firstIndex(where: { $0.key == target }) else {
            return
        }
        guard fromIndex != toIndex else { return }

        commitAllPlateSimpleDrafts()
        let destination = fromIndex < toIndex ? toIndex + 1 : toIndex
        viewModel.config.moveSimplePlateElements(from: IndexSet(integer: fromIndex), to: destination)
    }
}

private struct AdvancedPlateRowDropDelegate: DropDelegate {
    let targetKey: PlateSimpleElementKey
    @Binding var draggedKey: PlateSimpleElementKey?
    let onMove: (PlateSimpleElementKey, PlateSimpleElementKey) -> Void

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropEntered(info: DropInfo) {
        guard let draggedKey, draggedKey != targetKey else { return }
        onMove(draggedKey, targetKey)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggedKey = nil
        return true
    }
}
