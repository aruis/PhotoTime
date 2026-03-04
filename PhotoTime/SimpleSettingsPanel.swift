import SwiftUI
import UniformTypeIdentifiers

struct SimpleSettingsPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    @Binding var isAudioDropTarget: Bool
    let onAudioDrop: ([NSItemProvider]) -> Bool
    @State private var plateLiteralInput = ""
    @State private var isPlateReordering = false
    @State private var plateSimpleDrafts: [PlateSimpleElementKey: String] = [:]
    @State private var draggedPlateSimpleKey: PlateSimpleElementKey?

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

    var body: some View {
        Form {
            Section("常用参数") {
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
                                delegate: SimplePlateRowDropDelegate(
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

private struct SimplePlateRowDropDelegate: DropDelegate {
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
