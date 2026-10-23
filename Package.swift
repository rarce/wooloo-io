// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "WoolooMobile",
    platforms: [.iOS(.v17), .macOS("15.0")],
    products: [.library(name: "WoolooCore", targets: ["WoolooCore"])],
    dependencies: [
        .package(path: "Vendor/Citadel"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", exact: "1.5.1")
    ],
    targets: [
        .target(name: "WoolooCore", dependencies: [.product(name: "Citadel", package: "Citadel"), .product(name: "SwiftTerm", package: "SwiftTerm", condition: .when(platforms: [.iOS]))]),
        .testTarget(name: "WoolooCoreTests", dependencies: ["WoolooCore"])
    ]
)
