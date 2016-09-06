import PackageDescription

let package = Package(
    name: "spartanX",
    dependencies: [.Package(url: "https://github.com/michael-yuji/CKit.git", versions: Version(0,0,0)..<Version(1,0,0)),
                   .Package(url: "https://github.com/michael-yuji/swiftTLS.git", versions: Version(0,0,0)..<Version(1,0,0)),
                   .Package(url: "https://github.com/michael-yuji/XThreads.git", versions: Version(0,0,0)..<Version(1,0,0))]

)
