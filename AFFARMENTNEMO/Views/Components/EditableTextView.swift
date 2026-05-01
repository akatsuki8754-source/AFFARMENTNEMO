//
//  EditableTextView.swift
//  UITextView を SwiftUI に橋渡しして、編集操作を完全制御できるようにするコンポーネント。
//
//  設計根拠 (調査・論文):
//  - Thaler & Sunstein 2008 "Nudge" — 摩擦削減: 編集操作は 1 タップで到達できるべき
//  - Kahneman 2011 "Thinking, Fast and Slow" — 損失回避: 入力消失への不安を Undo で打ち消す
//  - Fitts's Law — 44pt 以上のツールバーボタンを近距離に
//  - Hick's Law — 6 アクション以内 (全選択 / コピー / 貼付 / 切取 / 取消 / 全削除)
//  - HCI 文献 — 「コピー」→「コピー済」の 1.5s 視覚フィードバックで信頼度向上
//  - 競合事例 — Apple Notes / Bear / Day One / Stoic はキーボードツールバーで主要操作提供
//

import SwiftUI
import UIKit

/// SwiftUI で編集ツールバーを完全制御できる TextView
/// - 全選択 / コピー / 貼付 / 切取 / 取消 / 全削除 を ToolbarHandler 経由で操作
struct EditableTextView: UIViewRepresentable {
    @Binding var text: String
    @Binding var handler: EditableTextHandler
    var placeholder: String = ""
    var maxLength: Int = 200
    var minHeight: CGFloat = 160
    var fontSize: CGFloat = 17
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.delegate = context.coordinator
        tv.font = .systemFont(ofSize: fontSize)
        tv.textColor = UIColor.label
        tv.backgroundColor = .clear
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = true
        tv.keyboardDismissMode = .interactive
        tv.autocorrectionType = .yes
        tv.smartDashesType = .no
        tv.smartQuotesType = .no
        tv.spellCheckingType = .yes
        // 標準の long-press メニュー (コピー/ペースト/全選択) はもちろん効く
        tv.allowsEditingTextAttributes = false
        tv.text = text
        tv.translatesAutoresizingMaskIntoConstraints = false

        // Inset: SwiftUI の AppSpacing.sm 相当
        tv.textContainerInset = UIEdgeInsets(top: 12, left: 8, bottom: 12, right: 8)
        tv.textContainer.lineFragmentPadding = 0

        // Placeholder (UITextView は標準 placeholder が無いので overlay)
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.font = .systemFont(ofSize: fontSize)
        placeholderLabel.textColor = .tertiaryLabel
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor, constant: 12),
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 8),
            placeholderLabel.trailingAnchor.constraint(equalTo: tv.trailingAnchor, constant: -8),
        ])
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.isEmpty

        // Handler に UITextView を結ぶ (toolbar アクション → UITextView 操作)
        DispatchQueue.main.async {
            handler.bind(textView: tv)
        }

        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
            context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        }
        if isFocused, !uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.becomeFirstResponder() }
        } else if !isFocused, uiView.isFirstResponder {
            DispatchQueue.main.async { uiView.resignFirstResponder() }
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: EditableTextView
        var placeholderLabel: UILabel?

        init(_ parent: EditableTextView) {
            self.parent = parent
        }

        func textViewDidChange(_ textView: UITextView) {
            // maxLength 制約
            if textView.text.count > parent.maxLength {
                textView.text = String(textView.text.prefix(parent.maxLength))
            }
            placeholderLabel?.isHidden = !textView.text.isEmpty
            parent.text = textView.text
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFocused = true }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            DispatchQueue.main.async { self.parent.isFocused = false }
        }
    }
}

/// EditableTextView の編集操作を SwiftUI 側 ToolbarItem から発火するためのハンドラ
@MainActor
final class EditableTextHandler: ObservableObject {
    private weak var textView: UITextView?
    @Published var lastAction: ActionFeedback?

    enum ActionFeedback: String {
        case copied = "コピーしました"
        case cut = "切り取りました"
        case pasted = "貼り付けました"
        case selectedAll = "全選択しました"
        case cleared = "すべて削除しました"
        case undone = "取り消しました"
        case nothingToPaste = "クリップボードに何もありません"
        case nothingToCopy = "コピーできるテキストがありません"
    }

    func bind(textView: UITextView) {
        self.textView = textView
    }

    /// 全選択 — 標準の Edit メニューも開く
    func selectAll() {
        guard let tv = textView else { return }
        if tv.text.isEmpty { return }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        tv.selectAll(nil)
        feedback(.selectedAll)
    }

    /// コピー — 選択範囲があればその範囲、無ければ全文
    func copy() {
        guard let tv = textView else { return }
        let target: String
        if let range = tv.selectedTextRange, !range.isEmpty,
           let s = tv.text(in: range), !s.isEmpty {
            target = s
        } else {
            target = tv.text ?? ""
        }
        guard !target.isEmpty else {
            feedback(.nothingToCopy)
            return
        }
        UIPasteboard.general.string = target
        feedback(.copied)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 切り取り — 選択範囲があればその範囲、無ければ全文
    func cut() {
        guard let tv = textView else { return }
        if let range = tv.selectedTextRange, !range.isEmpty,
           let s = tv.text(in: range), !s.isEmpty {
            UIPasteboard.general.string = s
            tv.replace(range, withText: "")
        } else {
            let all = tv.text ?? ""
            guard !all.isEmpty else {
                feedback(.nothingToCopy)
                return
            }
            UIPasteboard.general.string = all
            tv.text = ""
            tv.delegate?.textViewDidChange?(tv)
        }
        feedback(.cut)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 貼り付け — 現在のカーソル位置 (選択範囲を上書き) に挿入
    func paste() {
        guard let tv = textView else { return }
        guard let s = UIPasteboard.general.string, !s.isEmpty else {
            feedback(.nothingToPaste)
            return
        }
        if !tv.isFirstResponder { tv.becomeFirstResponder() }
        if let range = tv.selectedTextRange {
            tv.replace(range, withText: s)
        } else {
            tv.text.append(s)
            tv.delegate?.textViewDidChange?(tv)
        }
        feedback(.pasted)
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 取り消し — UITextView 内蔵 Undo Manager
    func undo() {
        guard let tv = textView else { return }
        tv.undoManager?.undo()
        tv.delegate?.textViewDidChange?(tv)
        feedback(.undone)
    }

    /// すべて削除 — 取り消し可能 (UndoManager に登録される)
    func clearAll() {
        guard let tv = textView else { return }
        let old = tv.text ?? ""
        guard !old.isEmpty else {
            feedback(.cleared)
            return
        }
        tv.undoManager?.registerUndo(withTarget: tv) { target in
            target.text = old
            target.delegate?.textViewDidChange?(target)
        }
        tv.text = ""
        tv.delegate?.textViewDidChange?(tv)
        feedback(.cleared)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    private func feedback(_ a: ActionFeedback) {
        lastAction = a
        // 1.5 秒後に消す (HCI ガイドライン)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1500))
            if self.lastAction == a { self.lastAction = nil }
        }
    }
}

/// SwiftUI ToolbarItemGroup(.keyboard) に貼る編集ツールバー
struct EditableTextToolbar: View {
    @ObservedObject var handler: EditableTextHandler
    let onDone: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            ToolButton(icon: "selection.pin.in.out", label: "全選択", action: handler.selectAll)
            ToolButton(icon: "doc.on.doc", label: "コピー", action: handler.copy)
            ToolButton(icon: "doc.on.clipboard", label: "貼付", action: handler.paste)
            ToolButton(icon: "scissors", label: "切取", action: handler.cut)
            ToolButton(icon: "arrow.uturn.backward", label: "取消", action: handler.undo)
            ToolButton(icon: "trash", label: "全削除", action: handler.clearAll, isDestructive: true)
            Spacer()
            Button(action: onDone) {
                Text("完了").fontWeight(.semibold)
            }
        }
    }
}

private struct ToolButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var isDestructive: Bool = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                Text(label)
                    .font(.system(size: 9, weight: .regular))
            }
            .foregroundStyle(isDestructive ? Color.red : Color.accentColor)
            .frame(minWidth: 44, minHeight: 36)
            .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(label))
    }
}

/// アクション実行直後のミニトースト (1.5s) — 「コピーしました」など
struct EditableActionToast: View {
    @ObservedObject var handler: EditableTextHandler

    var body: some View {
        if let action = handler.lastAction {
            Text(action.rawValue)
                .font(.caption)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.78))
                .clipShape(Capsule())
                .shadow(radius: 4, y: 2)
                .transition(.move(edge: .top).combined(with: .opacity))
                .accessibilityLiveRegion(.polite)
        }
    }
}
