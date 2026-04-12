//
//  richimajApp.swift
//  richimaj
//
//  Created by linzihao on 2026/3/31.
//

import SwiftUI

@main
struct richimajApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
    }
}

private struct AppRootView: View {
    private var isRunningInPreviews: Bool {
        ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }

    var body: some View {
        if isRunningInPreviews {
            AnyView(PreviewFallbackRootView())
        } else {
            AnyView(ContentView())
        }
    }
}

private struct PreviewFallbackRootView: View {
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text("Preview Mode")
                    .font(.title2)
                    .bold()
                Text("Xcode Preview 已切到轻量根视图，避免拍照识别与 ONNX 运行时在 Preview 注入阶段崩溃。正式运行不受影响。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Text("需要验证真实 UI 和识别流程时，请直接运行模拟器或真机。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
    }
}
