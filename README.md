# MLXWhisperApp

A high-performance, native macOS application for audio-to-text transcription powered by **MLX Whisper**. Designed specifically for Apple Silicon, it provides a seamless experience for transcribing audio and video files with state-of-the-art accuracy and speed.

## ✨ Features

-   **Apple Silicon Optimized**: Uses the MLX framework for lightning-fast inference on Mac hardware.
-   **Multiple Models**: Support for all Whisper models (Tiny, Base, Small, Medium, Large-v3) and custom Hugging Face models.
-   **Smart History**: Automatically saves transcription history with local persistence and search functionality.
-   **Professional Export**: Export results to **SRT**, **VTT**, or **Plain Text** with accurate timestamps.
-   **System Dashboard**: Real-time monitoring of CPU, GPU, and Memory usage during transcription.
-   **Drag & Drop**: Simply drop any audio or video file to start transcribing.
-   **Standalone**: Fully self-contained app bundle with embedded Python and FFmpeg.

## 🛠 Tech Stack

-   **Frontend**: SwiftUI
-   **Backend**: Python 3.12 (via `mlx-whisper`)
-   **Hardware Acceleration**: Apple MLX
-   **Audio Processing**: FFmpeg

## 🚀 Getting Started

### Prerequisites

-   macOS 14.0 or later
-   Apple Silicon Mac (M1, M2, M3, M4)
-   Swift 5.9+ (included with Xcode Command Line Tools)

### Build Instructions

The project uses a custom build script that handles environment setup, dependency management, and compilation.

1.  **Clone the repository**:
    ```bash
    git clone <repository-url>
    cd MLXWhisperApp
    ```

2.  **Build the application**:
    ```bash
    chmod +x build.sh
    ./build.sh
    ```
    *Note: The first run will download an embedded Python distribution (~1GB) and install required MLX libraries.*

3.  **Run the app**:
    The compiled app will be located at `build/MLXWhisperApp.app`.

### Packaging

To create a distributable DMG file:
```bash
chmod +x package.sh
./package.sh
```
The DMG will be saved to your `~/Downloads` folder (if run locally) or the current directory (in CI environment).

## 🛡 Security & Installation

Because this app is self-signed and not notarized by Apple (which requires a paid developer account), macOS will show a "Developer cannot be verified" warning when you first open it.

### How to open the app:

1.  **Right-Click Method (Recommended)**:
    -   Locate the app in your `/Applications` folder.
    -   **Right-click** (or Control-click) the app icon and choose **Open**.
    -   In the dialog that appears, click **Open** again. This only needs to be done once.

2.  **Terminal Method (If the above fails)**:
    -   If you still see a "Move to Trash" or "Cancel" message, run the following command in Terminal:
        ```bash
        xattr -cr /Applications/MLXWhisperApp.app
        ```
    -   This removes the "quarantine" flag that macOS assigns to files downloaded from the internet.

## 📁 Project Structure

-   `Sources/`: Native Swift/SwiftUI code for the app logic and UI.
-   `Python/`: Python transcription engine and dependency requirements.
-   `build.sh`: Universal build script for environment setup and compilation.
-   `package.sh`: DMG packaging script.
-   `AppIcon.icns`: Application icon.
-   `LICENSE`: MIT License file.

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
