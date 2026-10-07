// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "MailCore", platforms: [.macOS(.v13), .iOS(.v17)], products: [.library(name: "MailCore", targets: ["MailCore"])], targets: [.target(name: "MailCore"), .testTarget(name: "MailCoreTests", dependencies: ["MailCore"])])
