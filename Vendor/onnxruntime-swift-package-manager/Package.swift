// swift-tools-version: 5.9

// Copyright (c) Microsoft Corporation. All rights reserved.
// Licensed under the MIT License.
//
// A user of the Swift Package Manager (SPM) package will consume this file directly from the ORT SPM github repository.
// For example, the end user's config will look something like:
//
//     dependencies: [
//       .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.16.0"), 
//       ...
//     ],
//
// NOTE: For valid version numbers, please refer to this page:
// https://github.com/microsoft/onnxruntime-swift-package-manager/releases

import PackageDescription
import class Foundation.ProcessInfo

let package = Package(
    name: "onnxruntime",
    platforms: [.iOS(.v15), .macOS(.v14)],
    products: [
        .library(name: "onnxruntime", type: .static, targets: ["OnnxRuntimeBindings"]),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "OnnxRuntimeBindings",
            dependencies: ["onnxruntime"],
            path: "objectivec",
            exclude: [
                "ReadMe.md", "format_objc.sh", "test", "docs",
                "ort_checkpoint.mm",
                "ort_checkpoint_internal.h",
                "ort_training_session_internal.h",
                "ort_training_session.mm",
                "include/ort_checkpoint.h",
                "include/ort_training_session.h",
                "include/onnxruntime_training.h"
            ],
            cxxSettings: [
                .define("SPM_BUILD"),
            ]
        ),
        .testTarget(
            name: "OnnxRuntimeBindingsTests",
            dependencies: ["OnnxRuntimeBindings"],
            path: "swift/OnnxRuntimeBindingsTests",
            resources: [
                .copy("Resources/single_add.basic.ort")
            ]
        ),
        .binaryTarget(
            name: "onnxruntime",
            path: "../pod-archive-onnxruntime-c-1.24.2.zip"
        ),
    ],
    cxxLanguageStandard: .cxx17
)
