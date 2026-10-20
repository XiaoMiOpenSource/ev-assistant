import UIKit

// ============================================================
// 分享面板统一入口
//
// 为什么不放在 SwiftUI 的 .sheet 里：把 UIActivityViewController 当作 sheet
// 内容（UIViewControllerRepresentable）在新系统上会得到一个纯白空面板——
// CSV / PDF 导出都点不出内容。改成从最上层 UIViewController 直接 present，
// 走系统原生的分享流程，稳定且和别家 App 观感一致。
// ============================================================

@MainActor
enum SharePresenter {
    static func share(_ items: [Any]) {
        guard !items.isEmpty else { return }
        guard let scene = UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first,
              let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first,
              var top = window.rootViewController
        else { return }

        while let presented = top.presentedViewController {
            top = presented
        }

        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let popover = controller.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
            popover.permittedArrowDirections = []
        }
        top.present(controller, animated: true)
    }
}
