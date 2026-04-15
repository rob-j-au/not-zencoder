#!/bin/bash

set -e

echo "NotZencoder Dependency Installer"
echo "================================="
echo ""

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        echo "linux"
    else
        echo "unsupported"
    fi
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

install_macos_dependencies() {
    echo "Installing dependencies for macOS..."
    echo ""
    
    if ! check_command brew; then
        echo "Error: Homebrew is not installed."
        echo "Please install Homebrew first: https://brew.sh"
        exit 1
    fi
    
    echo "Checking FFmpeg..."
    if ! check_command ffmpeg; then
        echo "Installing FFmpeg..."
        brew install ffmpeg
    else
        echo "✓ FFmpeg already installed"
    fi
    
    echo "Checking FFprobe..."
    if ! check_command ffprobe; then
        echo "Installing FFprobe (part of FFmpeg)..."
        brew install ffmpeg
    else
        echo "✓ FFprobe already installed"
    fi
    
    echo "Checking qt-faststart..."
    if ! check_command qt-faststart; then
        echo "Note: qt-faststart is included with FFmpeg"
        echo "If not available, you may need to build it from FFmpeg source"
    else
        echo "✓ qt-faststart already installed"
    fi
    
    echo "Checking ImageMagick..."
    if ! check_command convert; then
        echo "Installing ImageMagick..."
        brew install imagemagick
    else
        echo "✓ ImageMagick already installed"
    fi
    
    echo "Checking md5..."
    if ! check_command md5; then
        echo "Warning: md5 command not found (should be built-in on macOS)"
    else
        echo "✓ md5 already installed"
    fi
}

install_linux_dependencies() {
    echo "Installing dependencies for Linux..."
    echo ""
    
    if check_command apt-get; then
        PKG_MANAGER="apt-get"
        UPDATE_CMD="sudo apt-get update"
        INSTALL_CMD="sudo apt-get install -y"
    elif check_command yum; then
        PKG_MANAGER="yum"
        UPDATE_CMD="sudo yum check-update || true"
        INSTALL_CMD="sudo yum install -y"
    elif check_command dnf; then
        PKG_MANAGER="dnf"
        UPDATE_CMD="sudo dnf check-update || true"
        INSTALL_CMD="sudo dnf install -y"
    else
        echo "Error: No supported package manager found (apt-get, yum, or dnf)"
        exit 1
    fi
    
    echo "Updating package list..."
    $UPDATE_CMD
    echo ""
    
    echo "Checking FFmpeg..."
    if ! check_command ffmpeg; then
        echo "Installing FFmpeg..."
        $INSTALL_CMD ffmpeg
    else
        echo "✓ FFmpeg already installed"
    fi
    
    echo "Checking FFprobe..."
    if ! check_command ffprobe; then
        echo "Installing FFprobe (part of FFmpeg)..."
        $INSTALL_CMD ffmpeg
    else
        echo "✓ FFprobe already installed"
    fi
    
    echo "Checking qt-faststart..."
    if ! check_command qt-faststart; then
        echo "Installing qt-faststart..."
        if [[ "$PKG_MANAGER" == "apt-get" ]]; then
            $INSTALL_CMD qtfaststart || echo "Note: qt-faststart may need manual installation"
        else
            echo "Note: qt-faststart may need manual installation from FFmpeg source"
        fi
    else
        echo "✓ qt-faststart already installed"
    fi
    
    echo "Checking ImageMagick..."
    if ! check_command convert; then
        echo "Installing ImageMagick..."
        $INSTALL_CMD imagemagick
    else
        echo "✓ ImageMagick already installed"
    fi
    
    echo "Checking md5sum..."
    if ! check_command md5sum; then
        echo "Installing coreutils (includes md5sum)..."
        $INSTALL_CMD coreutils
    else
        echo "✓ md5sum already installed"
    fi
}

install_ruby_dependencies() {
    echo ""
    echo "Installing Ruby dependencies..."
    echo ""
    
    if ! check_command ruby; then
        echo "Error: Ruby is not installed."
        echo "Please install Ruby first: https://www.ruby-lang.org/en/documentation/installation/"
        exit 1
    fi
    
    echo "Ruby version: $(ruby -v)"
    
    if ! check_command bundle; then
        echo "Installing Bundler..."
        gem install bundler
    else
        echo "✓ Bundler already installed"
    fi
    
    echo "Installing gems from Gemfile..."
    bundle install
}

verify_installation() {
    echo ""
    echo "Verifying installation..."
    echo ""
    
    local all_good=true
    
    if check_command ffmpeg; then
        echo "✓ ffmpeg: $(ffmpeg -version | head -n1)"
    else
        echo "✗ ffmpeg: NOT FOUND"
        all_good=false
    fi
    
    if check_command ffprobe; then
        echo "✓ ffprobe: $(ffprobe -version | head -n1)"
    else
        echo "✗ ffprobe: NOT FOUND"
        all_good=false
    fi
    
    if check_command convert; then
        echo "✓ ImageMagick: $(convert -version | head -n1)"
    else
        echo "✗ ImageMagick: NOT FOUND"
        all_good=false
    fi
    
    if check_command qt-faststart; then
        echo "✓ qt-faststart: FOUND"
    else
        echo "⚠ qt-faststart: NOT FOUND (may need manual installation)"
    fi
    
    echo ""
    if [ "$all_good" = true ]; then
        echo "✓ All required dependencies are installed!"
    else
        echo "⚠ Some dependencies are missing. Please install them manually."
    fi
}

main() {
    OS=$(detect_os)
    
    if [ "$OS" = "unsupported" ]; then
        echo "Error: Unsupported operating system"
        exit 1
    fi
    
    echo "Detected OS: $OS"
    echo ""
    
    if [ "$OS" = "macos" ]; then
        install_macos_dependencies
    elif [ "$OS" = "linux" ]; then
        install_linux_dependencies
    fi
    
    install_ruby_dependencies
    verify_installation
    
    echo ""
    echo "Installation complete!"
}

main
