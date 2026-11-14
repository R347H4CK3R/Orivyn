# Configure each simulator slice separately: pinned ggml recognizes only a
# single CMAKE_OSX_ARCHITECTURES value; universal configuration selects GENERIC.
for simulator_arch in arm64 x86_64; do
    simulator_build="build-ios-sim-${simulator_arch}"
    echo "Building for iOS simulator ${simulator_arch}..."
    cmake -B "$simulator_build" -G Xcode \
        "${COMMON_CMAKE_ARGS[@]}" \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=${IOS_MIN_OS_VERSION} \
        -DIOS=ON \
        -DCMAKE_SYSTEM_NAME=iOS \
        -DCMAKE_OSX_SYSROOT=iphonesimulator \
        -DCMAKE_OSX_ARCHITECTURES="$simulator_arch" \
        -DCMAKE_XCODE_ATTRIBUTE_SUPPORTED_PLATFORMS=iphonesimulator \
        -DCMAKE_C_FLAGS="${COMMON_C_FLAGS}" \
        -DCMAKE_CXX_FLAGS="${COMMON_CXX_FLAGS}" \
        -DLLAMA_OPENSSL=OFF \
        -S .
    cmake --build "$simulator_build" --config Release --target orivyn-bridges --parallel 2 -- -quiet
    setup_framework_structure "$simulator_build" ${IOS_MIN_OS_VERSION} "ios"
    combine_static_libraries "$simulator_build" "Release-iphonesimulator" "ios" "true" "$simulator_arch"
done
# Merge linked slices and matching DWARF UUIDs, not CMake architecture decisions.
mkdir -p build-ios-sim
cp -R build-ios-sim-arm64/framework build-ios-sim/framework
cp -R build-ios-sim-arm64/dSYMs build-ios-sim/dSYMs
xcrun lipo -create build-ios-sim-arm64/framework/llama.framework/llama \
    build-ios-sim-x86_64/framework/llama.framework/llama \
    -output build-ios-sim/framework/llama.framework/llama
xcrun lipo -create build-ios-sim-arm64/dSYMs/llama.dSYM/Contents/Resources/DWARF/llama \
    build-ios-sim-x86_64/dSYMs/llama.dSYM/Contents/Resources/DWARF/llama \
    -output build-ios-sim/dSYMs/llama.dSYM/Contents/Resources/DWARF/llama
xcrun lipo -verify_arch arm64 x86_64 build-ios-sim/framework/llama.framework/llama
xcrun lipo -verify_arch arm64 x86_64 build-ios-sim/dSYMs/llama.dSYM/Contents/Resources/DWARF/llama
