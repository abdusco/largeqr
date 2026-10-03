# largeqr

A macOS command-line utility that generates a QR code and displays it as large as possible in a fullscreen overlay. The app is a single Swift file, using only Apple's built-in frameworks.

## Build

Requires macOS and the Xcode command-line tools (`swiftc`). Supports macOS 11 and later.

```sh
./build.sh
./largeqr-arm64 'https://example.com'

# Specify an architecture and embedded version:
ARCH=x86_64 VERSION=v1.2.3 ./build.sh
./largeqr-x86_64 --version
```

The default build produces `largeqr-arm64`. No Swift package manager or external libraries are needed. To install, copy the binary to a directory on your PATH as `largeqr`.

## Usage

```sh
largeqr 'https://example.com'
largeqr 'WIFI:T:WPA;S:MyNetwork;P:MyPassword;;' --hide-after 30
printf '%s' 'Hello world' | largeqr --correction-level H
largeqr 'Scan me' --padding 10% --background-color 000000ff
largeqr -- '--text-starting-with-dashes'
```

The QR appears on the main screen, centered in a borderless overlay above other windows. It preserves the entire code and scales each module to a whole number of display pixels without smoothing. A solid white margin surrounds the black code so it remains readable over any background. The app does not add a Dock icon.

Click anywhere or press Escape to dismiss. Escape while another app has focus depends on macOS allowing global keyboard monitoring; Escape in the overlay does not require that permission.

| Option | Default | Description |
| --- | --- | --- |
| `--correction-level L\|M\|Q\|H` | `M` | QR error correction level; higher levels provide more redundancy and less capacity. |
| `--background-color rrggbbaa` | `00000080` | Overlay background in hex RGBA; an optional leading `#` is accepted. |
| `--padding number[px\|%]` | `5%` | Padding on each side. Bare numbers and `px` use macOS points; percentages use each screen dimension. |
| `--hide-after seconds` | Disabled | Automatically dismiss after a positive number of seconds. |
| `--help` | | Print help without opening the overlay. |
| `--version` | | Print the embedded build version. |
| `--` | | Treat all remaining arguments as text. |

Multiple positional arguments are joined with spaces. Positional text takes precedence over piped input. Stdin must be UTF-8; trailing CR/LF characters are removed to accommodate `echo`, while other whitespace is preserved. Positional text is preserved, including line endings. Empty payloads and invalid options produce an error on stderr and exit with status 1.

## QR limits

Generation is offline using Core Image's `CIQRCodeGenerator`. The payload is encoded as UTF-8 bytes. Maximum byte-mode capacities are:

| Correction level | Maximum bytes |
| --- | ---: |
| L | 2,953 |
| M | 2,331 |
| Q | 1,663 |
| H | 1,273 |

Non-ASCII characters can occupy multiple bytes. Larger payloads produce denser codes, which can be harder to scan. For long content, encode a short URL instead. A generated code contains the data itself and does not expire; a linked URL's availability depends on its host.

See [Apple's Core Image filter reference](https://developer.apple.com/library/archive/documentation/GraphicsImaging/Reference/CoreImageFilterReference/index.html) and [DENSO's QR capacity and versions](https://www.qrcode.com/en/about/version.html).

## Releases

Pushing a `v*` tag runs `.github/workflows/release.yml`, compiles arm64 and x86_64 binaries, and creates a **draft** GitHub release. Each binary embeds the version without its leading `v`, followed by the short commit hash.

`.github/generate_changelog.sh` is copied unchanged from `htmlpopup`. Release notes group conventional commits since the preceding tag into sections; the first release includes the full history through its tag.

```sh
.github/generate_changelog.sh v1.0.0..v1.1.0
```
