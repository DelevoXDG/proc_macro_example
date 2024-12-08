# Get package info from Scarb.toml
$scarbContent = Get-Content "Scarb.toml" -Raw
$packageName = [regex]::Match($scarbContent, 'name\s*=\s*"([^"]+)"').Groups[1].Value
$packageVersion = [regex]::Match($scarbContent, 'version\s*=\s*"([^"]+)"').Groups[1].Value
$cargoContent = Get-Content "Cargo.toml" -Raw
$cargoPackageName = [regex]::Match($cargoContent, 'name\s*=\s*"([^"]+)"').Groups[1].Value
$cargoPackageVersion = [regex]::Match($cargoContent, 'version\s*=\s*"([^"]+)"').Groups[1].Value

if (!$packageName -or !$packageVersion) {
    Write-Error "Could not extract package name or version from Scarb.toml"
    exit 1
}

# Create target directory
$targetDir = "target/package/$packageName-$packageVersion/target/scarb/cairo-plugin"
New-Item -ItemType Directory -Force -Path $targetDir | Out-Null

# Build for Windows
$target = "x86_64-pc-windows-msvc"
$env:RUSTFLAGS = "-C target-feature=-crt-static"
cargo build --release --target $target

# Copy and rename the file
$binaryName = "${packageName}_v${packageVersion}_${target}.dll"
$sourcePath = "target/$target/release"

if (Test-Path "$sourcePath/lib$cargoPackageName.dll") {
    Copy-Item "$sourcePath/lib$cargoPackageName.dll" "$targetDir/$binaryName"
} elseif (Test-Path "$sourcePath/$cargoPackageName.dll") {
    Copy-Item "$sourcePath/$cargoPackageName.dll" "$targetDir/$binaryName"
} else {
    Write-Error "Could not find binary in $sourcePath"
    exit 1
}

Write-Host "Build complete. Binary is in $targetDir"
Get-ChildItem $targetDir