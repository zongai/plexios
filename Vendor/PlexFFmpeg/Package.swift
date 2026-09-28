// swift-tools-version: 5.9
import PackageDescription

/// Thin Plex demux/decode bridge + binary libav XCFrameworks (iOS).
/// Binaries sourced from tylerjonesio/ffmpeg-libav-spm release min.v7.1.3.0 (LGPL).
let release = "min.v7.1.3.0"
let frameworks: [String: String] = [
    "libavcodec": "03426fcda41ec61b925afbb6cf0c5e8796c569443ef53f32bbb74191f0b4386c",
    "libavformat": "e5e4e7ef94a275529c0852f2865e0dc6f3965c1ee991e281ecaa525529ab8e2c",
    "libavutil": "b87310b863224f7bf7095c1aae8835d173335bd945714776d9e9d6e2fa6eded7",
    "libswresample": "46bbe79946676a0293ae8f60ef27980a2bee93abf1b8fa3b43466ddc985e5df4",
    "libswscale": "1497cee3d8fd96fef8dc1480b20aacaa5717c875fb9c80ec698a34552372e5d1",
]

let package = Package(
    name: "PlexFFmpeg",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "PlexFFmpeg", targets: ["PlexFFmpeg"]),
    ],
    targets: [
        .target(
            name: "PlexFFmpeg",
            dependencies: frameworks.keys.map { .byName(name: $0) },
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
                .define("NATIVE_FFMPEG", to: "1"),
            ],
            linkerSettings: [
                .linkedFramework("VideoToolbox"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreMedia"),
                .linkedLibrary("z"),
                .linkedLibrary("bz2"),
                .linkedLibrary("iconv"),
            ]
        ),
    ] + frameworks.map { name, checksum in
        .binaryTarget(
            name: name,
            url: "https://github.com/tylerjonesio/ffmpeg-libav-spm/releases/download/\(release)/\(name).xcframework.zip",
            checksum: checksum
        )
    }
)
