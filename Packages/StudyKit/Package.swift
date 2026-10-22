// swift-tools-version: 6.0
//
// StudyKit holds everything below the UI:
//   StudyDomain   – pure models and rules (workload, progress, filters). No dependencies.
//   StudyData     – repository protocols, offline cache, outbox and sync. Depends on StudyDomain.
//   StudySupabase – the Supabase implementation of StudyData's protocols.
// The app target only adds SwiftUI screens on top.

import PackageDescription

let package = Package(
    name: "StudyKit",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "StudyDomain", targets: ["StudyDomain"]),
        .library(name: "StudyData", targets: ["StudyData"]),
        .library(name: "StudySupabase", targets: ["StudySupabase"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.55.0"),
    ],
    targets: [
        .target(name: "StudyDomain"),
        .target(name: "StudyData", dependencies: ["StudyDomain"]),
        .target(
            name: "StudySupabase",
            dependencies: [
                "StudyDomain",
                "StudyData",
                .product(name: "Supabase", package: "supabase-swift"),
            ]
        ),
        .testTarget(name: "StudyDomainTests", dependencies: ["StudyDomain"]),
        .testTarget(name: "StudyDataTests", dependencies: ["StudyData", "StudyDomain"]),
        .testTarget(name: "StudySupabaseTests", dependencies: ["StudySupabase", "StudyDomain"]),
    ]
)
