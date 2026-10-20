import SwiftUI
import UniformTypeIdentifiers

// ============================================================
// 全量备份 / 恢复
//
// 备份 = 一个 JSON 文件，含全部车辆、全部充电记录、温度标签与预算，
//        由用户在「文件」里自己挑保存位置（UIDocumentPickerController）。
// 恢复 = 由用户手动选文件；JSON 走全量合并（按 id 去重），
//        旧版 CSV 备份继续兼容（按 车+日期+里程 去重）。
// ============================================================

struct BackupPayload: Codable {
    var app: String = "电车助手"
    var schema: Int = 1
    var appVersion: String = ""
    var exportedAt: Date = Date()
    var vehicles: [Vehicle] = []
    var records: [ChargeRecord] = []
    var temperatures: [String: Int] = [:]
    var monthlyBudget: Double?
}

// MARK: - 文档选择器（从最上层 VC 直接 present，避免 SwiftUI sheet 里套 UIKit 出现空白）

@MainActor
final class DocumentGate: NSObject, UIDocumentPickerDelegate {
    static let shared = DocumentGate()

    private var onImport: ((Data, String) -> Void)?
    private var onExportDone: ((Bool) -> Void)?

    private var topViewController: UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController
        else { return nil }
        while let presented = top.presentedViewController {
            top = presented
        }
        return top
    }

    /// 导出到用户指定位置（「文件」App 的任意目录）
    func export(_ url: URL, done: ((Bool) -> Void)? = nil) {
        guard let top = topViewController else { done?(false); return }
        onExportDone = done
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = self
        picker.modalPresentationStyle = .formSheet
        top.present(picker, animated: true)
    }

    /// 手动选择文件恢复
    func pickImport(completion: @escaping (Data, String) -> Void) {
        guard let top = topViewController else { return }
        onImport = completion
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.json, .commaSeparatedText, .plainText])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        picker.modalPresentationStyle = .formSheet
        top.present(picker, animated: true)
    }

    // MARK: UIDocumentPickerDelegate

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        if let handler = onImport {
            onImport = nil
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { return }
            handler(data, url.lastPathComponent)
            return
        }
        onExportDone?(true)
        onExportDone = nil
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        onImport = nil
        onExportDone?(false)
        onExportDone = nil
    }
}

// MARK: - 文件名

enum BackupNaming {
    static func stamp(_ date: Date = Date()) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyyMMdd_HHmm"
        return f.string(from: date)
    }

    static func fileName(_ date: Date = Date()) -> String {
        "电车助手_备份_\(stamp(date)).json"
    }
}
