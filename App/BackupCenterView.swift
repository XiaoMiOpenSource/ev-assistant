import SwiftUI

// ============================================================
// 备份与恢复
//
// 设置页只留一个入口，避免「备份全部数据 / 导出 CSV / 本机副本 / 恢复」
// 四个按钮语义重叠。这里按用途分成三块：
//   1. 完整备份：JSON，含全部车辆/记录/温度/预算，保存位置自选；可从这里恢复任意备份文件
//   2. 本机自动备份：每次记账后自动生成的 CSV（滚动 10 份），就地可恢复 / 分享 / 删除
//   3. 导出：当前车辆明细 CSV，走系统分享
// ============================================================

struct BackupCenterView: View {
    @EnvironmentObject private var store: Store

    @State private var backups: [URL] = []
    @State private var toast: String?
    @State private var pendingRestore: URL?

    var body: some View {
        Form {
            fullBackupSection
            autoBackupSection
            exportSection
        }
        .navigationTitle("备份与恢复")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            reload()
            runDebugHooks()
        }
        .overlay(alignment: .bottom) { toastView }
        .confirmationDialog("恢复这份自动备份？",
                            isPresented: Binding(get: { pendingRestore != nil },
                                                 set: { if !$0 { pendingRestore = nil } }),
                            titleVisibility: .visible) {
            Button("恢复") {
                if let url = pendingRestore { restore(url) }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: {
            Text(pendingRestore?.lastPathComponent ?? "")
        }
    }

    // MARK: - 完整备份

    private var fullBackupSection: some View {
        Section {
            Button {
                backupAll()
            } label: {
                Label("备份全部数据到文件…", systemImage: "externaldrive.badge.checkmark")
            }
            Button {
                restoreFromFile()
            } label: {
                Label("从备份文件恢复…", systemImage: "tray.and.arrow.up")
            }
        } header: {
            Text("完整备份")
        } footer: {
            Text("一个 JSON 文件装下全部车辆、充电记录、温度标签与月预算，保存位置在「文件」里自己选（iCloud 云盘 / 我的 iPhone 都行）。恢复时手动挑文件，按 id 去重合并，旧版 CSV 备份也能导入。")
        }
    }

    // MARK: - 本机自动备份

    private var autoBackupSection: some View {
        Section {
            if backups.isEmpty {
                Text("暂无自动备份")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(backups, id: \.self) { url in
                    Button {
                        pendingRestore = url
                    } label: {
                        backupRow(url)
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .leading) {
                        Button {
                            SharePresenter.share([url])
                        } label: {
                            Label("分享", systemImage: "square.and.arrow.up")
                        }
                        .tint(.blue)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            store.deleteAutoBackup(url)
                            reload()
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("本机自动备份（\(backups.count)/10）")
        } footer: {
            Text("每次记账或删除后自动留一份当前车辆的 CSV，滚动保留最近 10 份，不需要手动操作。点按可恢复，左滑分享，右滑删除。")
        }
    }

    private func backupRow(_ url: URL) -> some View {
        HStack {
            Image(systemName: "doc.text")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(url))
                    .font(.subheadline)
                Text(subtitle(url))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func displayName(_ url: URL) -> String {
        // EVLogger_20261020_145945.csv → 10月20日 14:59
        let raw = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "EVLogger_", with: "")
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "zh_CN")
        parser.dateFormat = "yyyyMMdd_HHmmss"
        guard let date = parser.date(from: raw) else { return raw }
        let out = DateFormatter()
        out.locale = Locale(identifier: "zh_CN")
        out.dateFormat = "M月d日 HH:mm"
        return out.string(from: date)
    }

    private func subtitle(_ url: URL) -> String {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        let size = ByteCountFormatter.string(fromByteCount: Int64(values?.fileSize ?? 0), countStyle: .file)
        return "\(size) · 当前车辆 CSV"
    }

    // MARK: - 导出

    private var exportSection: some View {
        Section {
            Button {
                exportCSV()
            } label: {
                Label("导出当前车辆 CSV…", systemImage: "square.and.arrow.up")
            }
            .disabled(store.activeVehicle == nil)
        } header: {
            Text("导出")
        } footer: {
            Text("当前车辆的明细表（日期/桩型/电量/金额/里程/电耗/成本/SOC/备注），适合发给别人或在表格软件里看。要完整迁移数据请用上面的「备份全部数据」。")
        }
    }

    // MARK: - 操作

    private func backupAll() {
        guard let data = store.makeFullBackup() else {
            show("备份失败：数据编码出错")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(BackupNaming.fileName())
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            show("备份失败：\(error.localizedDescription)")
            return
        }
        DocumentGate.shared.export(url) { ok in
            if ok { show("已保存备份：\(url.lastPathComponent)") }
        }
    }

    private func restoreFromFile() {
        DocumentGate.shared.pickImport { data, name in
            let result = store.restoreBackup(from: data)
            if let error = result.error {
                show("恢复失败：\(error)")
            } else {
                show("已恢复 \(name)：新增 \(result.imported) 项，跳过 \(result.skipped) 项")
                reload()
            }
        }
    }

    private func restore(_ url: URL) {
        let result = store.restoreFile(url)
        if let error = result.error {
            show("恢复失败：\(error)")
        } else {
            show("已恢复 \(displayName(url))：新增 \(result.imported) 项，跳过 \(result.skipped) 项")
        }
    }

    private func exportCSV() {
        guard let v = store.activeVehicle else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("电车助手_\(v.name.replacingOccurrences(of: " ", with: ""))_\(Date().isoDate()).csv")
        do {
            try store.makeCSV(for: v).write(to: url, atomically: true, encoding: .utf8)
            SharePresenter.share([url])
        } catch {
            show("导出失败：\(error.localizedDescription)")
        }
    }

    private func reload() {
        backups = store.autoBackupFiles()
    }

    // MARK: - 轻提示

    private func show(_ message: String) {
        withAnimation { toast = message }
    }

    private var toastView: some View {
        Group {
            if let toast {
                Text(toast)
                    .font(.footnote)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(Color(.label).opacity(0.85))
                    .foregroundColor(Color(.systemBackground))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity)
                    .task(id: toast) {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { self.toast = nil }
                    }
            }
        }
    }

    // MARK: - 调试

    private func runDebugHooks() {
        #if DEBUG
        let args = CommandLine.arguments
        if args.contains("-backup") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { backupAll() }
        }
        if args.contains("-exportcsv") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { exportCSV() }
        }
        if let i = args.firstIndex(of: "-restorefile"), i + 1 < args.count {
            let name = args[i + 1]
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) {
                    restore(url)
                } else {
                    show("找不到测试备份：\(name)")
                }
            }
        }
        if args.contains("-restoretest") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                guard let data = store.makeFullBackup() else { return }
                let r = store.restoreBackup(from: data)
                show("自测恢复：新增 \(r.imported)，跳过 \(r.skipped)")
            }
        }
        #endif
    }
}
