#!/bin/bash
set -euo pipefail

# List of supported target platforms
TARGETS=(
    "aarch64-apple-darwin"
    "aarch64-unknown-linux-gnu"
    "x86_64-apple-darwin"
    # "x86_64-pc-windows-msvc"
    "x86_64-unknown-linux-gnu"
)

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WORKSPACE_ROOT="$( pwd )"
cd "$SCRIPT_DIR"

# Get package name and version from Scarb.toml
PACKAGE_NAME=$(grep '^name = ' Scarb.toml | cut -d'"' -f2)
PACKAGE_VERSION=$(grep '^version = ' Scarb.toml | cut -d'"' -f2)

if [ -z "$PACKAGE_NAME" ] || [ -z "$PACKAGE_VERSION" ]; then
    echo "Error: Could not extract package name or version from Scarb.toml"
    exit 1
fi

# Create the package directory structure
PACKAGE_DIR="$WORKSPACE_ROOT/target/package/${PACKAGE_NAME}-${PACKAGE_VERSION}"
PLUGIN_DIR="$PACKAGE_DIR/target/scarb/cairo-plugin"
mkdir -p "$PLUGIN_DIR"

# Get the appropriate extension for a target
get_extension() {
    local target=$1
    if [[ $target == *"-windows-"* ]]; then
        echo "dll"
    elif [[ $target == *"-apple-"* ]]; then
        echo "dylib"
    else
        echo "so"
    fi
}

# Check if cross is installed
if ! command -v cross &> /dev/null; then
    echo "Installing cross..."
    cargo install cross
fi

for TARGET in "${TARGETS[@]}"; do
    echo "Building for $TARGET..."
    
    if ! rustup target list | grep -q "$TARGET (installed)"; then
        echo "Installing target $TARGET..."
        rustup target add "$TARGET"
    fi

    # Use Docker for Linux targets, cargo for macOS
    if [[ $TARGET == *"-linux-"* ]]; then
        echo "Running Docker build for $TARGET..."
        # Check if Docker is installed and running
        if ! command -v docker &> /dev/null; then
            echo "Error: Docker is required for Linux targets. Please install Docker and try again."
            exit 1
        fi

        # Create a temporary Dockerfile
        cat > Dockerfile.build <<EOF
FROM rust:latest
RUN apt-get update && apt-get install -y \
    gcc-aarch64-linux-gnu \
    gcc-x86-64-linux-gnu
WORKDIR /build
COPY . .
RUN mkdir -p .cargo && \
    echo '[target.aarch64-unknown-linux-gnu]\n\
linker = "aarch64-linux-gnu-gcc"' > .cargo/config.toml && \
    echo '[target.x86_64-unknown-linux-gnu]\n\
linker = "x86_64-linux-gnu-gcc"' >> .cargo/config.toml

RUN rustup target add ${TARGET}

# Set environment variables for cross-compilation
ENV CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-linux-gnu-gcc \
    CC_aarch64_unknown_linux_gnu=aarch64-linux-gnu-gcc \
    CXX_aarch64_unknown_linux_gnu=aarch64-linux-gnu-g++ \
    RUSTFLAGS="-C target-feature=-crt-static"

CMD cargo build --target ${TARGET} --release
EOF

        # Build using Docker
        docker build -t rust-cross-build -f Dockerfile.build .
        docker run --rm \
            -v "$(pwd)":/build \
            -v "$(pwd)/target":/build/target \
            -e TARGET="${TARGET}" \
            -e RUSTFLAGS="-C target-feature=-crt-static" \
            rust-cross-build

        # Cleanup
        rm Dockerfile.build
    else
        echo "Running cargo build for $TARGET..."
        RUSTFLAGS="-C target-feature=-crt-static" cargo build --target "$TARGET" --release
    fi

    EXT=$(get_extension "$TARGET")
    BINARY_NAME="${PACKAGE_NAME}_v${PACKAGE_VERSION}_${TARGET}.${EXT}"
    
    SOURCE_PATH="$WORKSPACE_ROOT/target/$TARGET/release"
    if [[ -f "$SOURCE_PATH/lib${PACKAGE_NAME}.${EXT}" ]]; then
        echo "Copying lib${PACKAGE_NAME}.${EXT}"
        cp "$SOURCE_PATH/lib${PACKAGE_NAME}.${EXT}" "$PLUGIN_DIR/$BINARY_NAME"
    elif [[ -f "$SOURCE_PATH/${PACKAGE_NAME}.${EXT}" ]]; then
        echo "Copying ${PACKAGE_NAME}.${EXT}"
        cp "$SOURCE_PATH/${PACKAGE_NAME}.${EXT}" "$PLUGIN_DIR/$BINARY_NAME"
    else
        echo "Error: Could not find binary for $TARGET"
        echo "Contents of $SOURCE_PATH:"
        ls -la "$SOURCE_PATH" || echo "Directory $SOURCE_PATH does not exist"
    fi
done

echo "Prebuild complete. Binaries are in $PLUGIN_DIR/"
ls -la "$PLUGIN_DIR/"
