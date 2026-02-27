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
            VStack(alignment: .leading, spacing: 12) {
                preflightSummaryRow
                compactActionsRow
                compactIssuePreview

                DisclosureGroup("查看全部问题与筛选", isExpanded: $preflightSecondaryActionsExpanded) {
                    VStack(alignment: .leading, spacing: 10) {
                        preflightFilterRow
                        issueListSection
                        secondaryOptionsPanel
                        if !viewModel.skippedAssetNamesFromPreflight.isEmpty {
                            Text("已跳过: \(viewModel.skippedAssetNamesFromPreflight.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)
                }
                .font(.caption)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private var preflightSummaryRow: some View {
        HStack(spacing: 8) {
            summaryBadge(
                title: "必须修复",
                count: viewModel.preflightReport?.blockingIssues.count ?? 0,
                tint: .red
            )
            summaryBadge(
                title: "建议关注",
                count: viewModel.preflightReport?.reviewIssues.count ?? 0,
                tint: .orange
            )
            summaryBadge(
                title: "已忽略",
                count: viewModel.ignoredIssueCount,
                tint: .secondary
            )
            Spacer(minLength: 0)
        }
    }

    private var compactActionsRow: some View {
        HStack(spacing: 8) {
            Button("重新检查") {
                viewModel.rerunPreflight()
            }
            .controlSize(.small)
            .disabled(viewModel.isBusy)

            if viewModel.hasBlockingPreflightIssues {
                Button("跳过问题素材并导出") {
                    viewModel.exportSkippingPreflightIssues()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }

            Spacer(minLength: 0)

            if let first = displayIssues.first {
                Button("定位首个问题") {
                    if let url = viewModel.focusAssetForIssue(first) {
                        onSelectAsset(url)
                    }
                }
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }
        }
    }

    private var compactIssuePreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let first = displayIssues.first {
                issueRow(first)

                let hiddenCount = max(0, displayIssues.count - 1)
                if hiddenCount > 0 {
                    Text("另有 \(hiddenCount) 项问题，展开“查看全部问题与筛选”可处理。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("当前筛选下没有问题项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 2)
            }
        }
    }

    private var preflightFilterRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("问题筛选", selection: $viewModel.preflightIssueFilter) {
                ForEach(ExportViewModel.PreflightIssueFilter.allCases) { filter in
                    Text(filter.title).tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)
            .controlSize(.small)

            HStack(spacing: 12) {
                Toggle("仅未处理", isOn: $preflightOnlyPending)
                Toggle("严重优先", isOn: $preflightPrioritizeMustFix)
            }
            .toggleStyle(.checkbox)
            .font(.caption)
            .controlSize(.small)
        }
    }

    private var issueListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if displayIssues.isEmpty {
                Text("当前筛选下没有问题项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach(displayIssues, id: \.ignoreKey) { issue in
                    issueRow(issue)
                }
            }
        }
    }

    private var secondaryOptionsPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button("展开全部") {
                    expandedPreflightIssueKeys.formUnion(displayIssues.map(\.ignoreKey))
                }
                .disabled(displayIssues.isEmpty)

                Button("收起全部") {
                    expandedPreflightIssueKeys.subtract(displayIssues.map(\.ignoreKey))
                }
                .disabled(displayIssues.isEmpty)
            }
            .controlSize(.small)

            if viewModel.ignoredIssueCount > 0 {
                ignoredIssuesSection
            }
        }
        .padding(.top, 2)
    }

    private var ignoredIssuesSection: some View {
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
                        .disabled(viewModel.isBusy)
                    }
                    .font(.caption)
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

    private func issueRow(_ issue: PreflightIssue) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(issue.severity == .mustFix ? "必须修复" : "建议关注")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(issue.severity == .mustFix ? Color.red.opacity(0.2) : Color.orange.opacity(0.2))
                    .clipShape(Capsule())
                    .foregroundStyle(issue.severity == .mustFix ? .red : .orange)

                Text(issue.fileName)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button("定位") {
                    if let url = viewModel.focusAssetForIssue(issue) {
                        onSelectAsset(url)
                    }
                }
                .font(.caption)
                .controlSize(.small)
                .disabled(viewModel.isBusy)

                Button(viewModel.isIssueIgnored(issue) ? "恢复" : "忽略") {
                    viewModel.toggleIgnoreIssue(issue)
                }
                .font(.caption)
                .controlSize(.small)
                .disabled(viewModel.isBusy)
            }

            Text(issue.message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summaryBadge(title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 5) {
            Text(title)
            Text("\(count)")
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(tint.opacity(0.15))
        .foregroundStyle(tint)
        .clipShape(Capsule())
    }
}
