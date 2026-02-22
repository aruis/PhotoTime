import SwiftUI

struct WorkflowOverviewPanel: View {
    let statusMessage: String
    let nextActionHint: String
    let flowSteps: [ExportViewModel.FlowStep]
    let firstRunPrimaryActionTitle: String?
    let isBusy: Bool
    let onFirstRunPrimaryAction: () -> Void

    var body: some View {
        GroupBox("流程状态") {
            VStack(alignment: .leading, spacing: 8) {
                Text(statusMessage)
                    .font(.callout)
                    .accessibilityIdentifier("workflow_status_message")
                Text(nextActionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("flow_next_hint")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        GroupBox("快速开始") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(flowSteps) { step in
                    HStack(spacing: 8) {
                        Image(systemName: step.done ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(step.done ? .green : .secondary)
                        Text(step.title)
                            .font(.caption)
                            .foregroundStyle(step.done ? .secondary : .primary)
                    }
                }

                if let firstRunPrimaryActionTitle {
                    Button(firstRunPrimaryActionTitle) { onFirstRunPrimaryAction() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(isBusy)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct FailureStatusCard: View {
    let copy: FailureCardCopy
    let isBusy: Bool
    let onPrimaryAction: () -> Void
    let onOpenLog: () -> Void

    var body: some View {
        GroupBox("导出失败") {
            VStack(alignment: .leading, spacing: 10) {
                Text("建议先执行：\(copy.actionTitle)")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)
                Text("问题是什么")
                    .font(.subheadline.weight(.semibold))
                Text(copy.problemSummary)
                    .font(.callout)
                Text("下一步做什么")
                    .font(.subheadline.weight(.semibold))
                Text(copy.nextStep)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button(copy.actionTitle) { onPrimaryAction() }
                        .accessibilityIdentifier("failure_primary_action")
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy)
                    Button("查看日志") { onOpenLog() }
                        .accessibilityIdentifier("failure_open_log")
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("failure_card")
    }
}

struct FailedAssetsPanel: View {
    let names: [String]
    let hiddenCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("失败素材")
                .font(.subheadline.weight(.semibold))
            ForEach(names, id: \.self) { name in
                Text(name)
                    .font(.callout)
            }
            if hiddenCount > 0 {
                Text("另有 \(hiddenCount) 项失败素材，可在“素材列表”查看全部。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct SuccessStatusCard: View {
    let filename: String?
    let logPath: String?
    let isBusy: Bool
    let onExportAgain: () -> Void
    let onOpenOutputDirectory: () -> Void
    let onOpenLog: () -> Void

    var body: some View {
        GroupBox("导出成功") {
            VStack(alignment: .leading, spacing: 10) {
                Text("已生成可播放的 MP4 文件。")
                    .font(.callout)
                if let filename {
                    Text("文件: \(filename)")
                        .font(.callout)
                }
                if let logPath {
                    Text("日志: \(logPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                HStack(spacing: 10) {
                    Button("打开输出目录") { onOpenOutputDirectory() }
                        .accessibilityIdentifier("success_open_output")
                        .buttonStyle(.borderedProminent)
                    Button("查看日志") { onOpenLog() }
                        .accessibilityIdentifier("success_open_log")
                    Button("再次导出") { onExportAgain() }
                        .accessibilityIdentifier("success_export_again")
                        .disabled(isBusy)
                }
                .controlSize(.small)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("success_card")
    }
}
