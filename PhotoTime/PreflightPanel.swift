import SwiftUI

struct PreflightPanel: View {
    @ObservedObject var viewModel: ExportViewModel
    let displayIssues: [PreflightIssue]
    let filteredIgnoredIssues: [PreflightIssue]
    let onSelectAsset: (URL) -> Void
    let expansionBindingForKey: (String) -> Binding<Bool>

    @Binding var preflightSecondaryActionsExpanded: Bool
    @Binding var preflightOnlyPending: Bool
    @Binding var preflightPrioritizeMustFix: Bool
    @Binding var expandedPreflightIssueKeys: Set<String>
    @Binding var ignoredIssuesExpanded: Bool
    @Binding var ignoredIssueSearchText: String

    var body: some View {
        GroupBox("导出前检查") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Button("仅看问题素材") {
                        if let url = viewModel.focusOnProblematicAssets() {
                            onSelectAsset(url)
                        }
                    }
                    .disabled(viewModel.isBusy)

                    Button("重新检查") {
                        viewModel.rerunPreflight()
                    }
                    .disabled(viewModel.isBusy)

                    if viewModel.hasBlockingPreflightIssues {
                        Button("跳过问题素材并导出") {
                            viewModel.exportSkippingPreflightIssues()
                        }
                        .disabled(viewModel.isBusy)
                    }
                }

                DisclosureGroup("次级选项", isExpanded: $preflightSecondaryActionsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        Picker("问题筛选", selection: $viewModel.preflightIssueFilter) {
                            ForEach(ExportViewModel.PreflightIssueFilter.allCases) { filter in
                                Text(filter.title).tag(filter)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 320)
                        .controlSize(.small)

                        HStack(spacing: 12) {
                            Toggle("仅未处理", isOn: $preflightOnlyPending)
                            Toggle("严重优先", isOn: $preflightPrioritizeMustFix)
                        }
                        .toggleStyle(.checkbox)
                        .font(.caption)
                        .controlSize(.small)

                        HStack(spacing: 10) {
                            Button("展开全部") {
                                expandedPreflightIssueKeys.formUnion(displayIssues.map(\.ignoreKey))
                            }
                            .font(.caption)
                            .disabled(displayIssues.isEmpty)

                            Button("收起全部") {
                                expandedPreflightIssueKeys.subtract(displayIssues.map(\.ignoreKey))
                            }
                            .font(.caption)
                            .disabled(displayIssues.isEmpty)
                        }
                        .controlSize(.small)

                        ForEach(displayIssues, id: \.ignoreKey) { issue in
                            DisclosureGroup(
                                isExpanded: expansionBindingForKey(issue.ignoreKey)
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(issue.message)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    HStack(spacing: 10) {
                                        Button(viewModel.isIssueIgnored(issue) ? "恢复" : "忽略本次") {
                                            viewModel.toggleIgnoreIssue(issue)
                                        }
                                        .font(.caption)
                                        .disabled(viewModel.isBusy)
                                        Button("定位") {
                                            if let url = viewModel.focusAssetForIssue(issue) {
                                                onSelectAsset(url)
                                            }
                                        }
                                        .font(.caption)
                                        .disabled(viewModel.isBusy)
                                    }
                                }
                                .padding(.top, 2)
                            } label: {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text("[\(issue.severity == .mustFix ? "必须修复" : "建议关注")]")
                                        .font(.caption)
                                        .foregroundStyle(issue.severity == .mustFix ? .red : .orange)
                                    Text(issue.fileName)
                                        .font(.caption)
                                        .lineLimit(1)
                                    Text(issue.message)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }

                        if viewModel.ignoredIssueCount > 0 {
                            DisclosureGroup(
                                "已忽略 \(viewModel.ignoredIssueCount) 项（本次）",
                                isExpanded: $ignoredIssuesExpanded
                            ) {
                                VStack(alignment: .leading, spacing: 6) {
                                    TextField("搜索已忽略文件名", text: $ignoredIssueSearchText)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(maxWidth: 280)

                                    HStack(spacing: 10) {
                                        Button("恢复全部") {
                                            viewModel.restoreAllIgnoredIssues()
                                            ignoredIssueSearchText = ""
                                        }
                                        .font(.caption)
                                        .disabled(viewModel.isBusy)
                                        Text("显示 \(filteredIgnoredIssues.count) / \(viewModel.ignoredIssueCount)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }

                                    ForEach(filteredIgnoredIssues.prefix(5), id: \.ignoreKey) { issue in
                                        HStack(spacing: 8) {
                                            Text(issue.fileName)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                            Button("恢复") {
                                                viewModel.toggleIgnoreIssue(issue)
                                            }
                                            .font(.caption)
                                            .disabled(viewModel.isBusy)
                                        }
                                    }

                                    if filteredIgnoredIssues.isEmpty {
                                        Text("没有匹配的已忽略项。")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.top, 2)
                            }
                        }

                    }
                    .padding(.top, 4)
                }

                if !viewModel.skippedAssetNamesFromPreflight.isEmpty {
                    Text("已跳过: \(viewModel.skippedAssetNamesFromPreflight.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        }
    }
}
