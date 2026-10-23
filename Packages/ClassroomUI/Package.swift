// swift-tools-version: 6.2
//
// ClassroomUI is the Class area of Homework Progress: Sign in with Apple, the shared lesson
// catalog, subscriptions, private progress and the administrator's publishing screens.
// It sits on top of StudyKit (domain rules, sync, Supabase) and exposes a few entry views
// (ClassroomCompactView, ClassroomDetailView) that the app places in its tab bar and sidebar.
//
// Images and strings come from the app's main bundle (Assets.xcassets, Localizable.xcstrings).

import PackageDescription

let package = Package(
    name: "ClassroomUI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "ClassroomUI", targets: ["ClassroomUI"]),
    ],
    dependencies: [
        .package(path: "../StudyKit"),
    ],
    targets: [
        .target(
            name: "ClassroomUI",
            dependencies: [
                .product(name: "StudyDomain", package: "StudyKit"),
                .product(name: "StudyData", package: "StudyKit"),
                .product(name: "StudySupabase", package: "StudyKit"),
            ],
            swiftSettings: [
                .defaultIsolation(MainActor.self),
                .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
                .enableUpcomingFeature("InferIsolatedConformances"),
            ]
        ),
        .testTarget(
            name: "ClassroomUITests",
            dependencies: [
                "ClassroomUI",
                .product(name: "StudyDomain", package: "StudyKit"),
                .product(name: "StudyData", package: "StudyKit"),
            ],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
    ]
)
