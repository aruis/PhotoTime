import SwiftUI

struct WorkflowOverviewPanel: View {
    let statusMessage: String
    let nextActionHint: String
    let firstRunPrimaryActionTitle: String?
    let firstRunPrimaryActionSubtitle: String?
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

                if let firstRunPrimaryActionTitle {
                    WorkflowPrimaryActionButton(
                        title: firstRunPrimaryActionTitle,
                        subtitle: firstRunPrimaryActionSubtitle,
                        isBusy: isBusy,
                        accessibilityIdentifier: "workflow_overview_primary_action",
                        action: onFirstRunPrimaryAction
                    )
                        .disabled(isBusy)
                        .padding(.top, 2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct WorkflowPrimaryActionButton: View {
    let title: String
    let subtitle: String?
    let isBusy: Bool
    let accessibilityIdentifier: String
    let action: () -> Void

    private var systemImage: String {
        switch title {
        case "导出 MP4":
            return "square.and.arrow.up.fill"
        case "导入图片":
            return "photo.badge.plus"
        default:
            return "play.rectangle.fill"
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(.white.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: systemImage)
                        .font(.system(size: 15, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(2)
                    }
                }

                Spacer(minLength: 0)

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "arrow.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 0.09, green: 0.45, blue: 0.94),
                    Color(red: 0.03, green: 0.67, blue: 0.74)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(.white.opacity(0.14))
        )
        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
        .accessibilityIdentifier(accessibilityIdentifier)
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
                    Button("执行：\(copy.actionTitle)") { onPrimaryAction() }
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
    let onOpenOutputFile: () -> Void
    let onOpenOutputDirectory: () -> Void
    let onOpenLog: () -> Void

    var body: some View {
        GroupBox("导出完成") {
            VStack(alignment: .leading, spacing: 8) {
                Text(filename ?? "已生成可播放的 MP4 文件")
                    .font(.callout.weight(.semibold))

                HStack(spacing: 10) {
                    Button("打开文件") { onOpenOutputFile() }
                        .accessibilityIdentifier("success_open_file")
                        .buttonStyle(.borderedProminent)
                    Button("打开目录") { onOpenOutputDirectory() }
                        .accessibilityIdentifier("success_open_output")
                    Button("再次导出") { onExportAgain() }
                        .accessibilityIdentifier("success_export_again")
                        .disabled(isBusy)
                    if logPath != nil {
                        Button("查看日志") { onOpenLog() }
                            .accessibilityIdentifier("success_open_log")
                    }
                }
                .controlSize(.small)

                if let logPath {
                    Text(logPath)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("success_card")
    }
}
