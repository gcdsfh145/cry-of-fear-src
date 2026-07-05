#!/bin/bash
set -e

export CFLAGS="${CFLAGS} -D_LIBCPP_HAS_MUSL_LIBC -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS"
export CXXFLAGS="${CXXFLAGS} -D_LIBCPP_HAS_MUSL_LIBC -D__STDC_LIMIT_MACROS -D__STDC_CONSTANT_MACROS -D__STDC_FORMAT_MACROS"

# Defaults
CONFIGURATION="Release"
ABI_INPUT="arm"
NDK_VERSION="26.1.10909125"
ANDROID_NDK_ROOT=""
ANDROID_SDK_ROOT="$ANDROID_HOME"
MIN_SDK=23
JOBS=$(nproc 2>/dev/null || echo 4)
CLEAN_NATIVE=0

# Parse arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -Configuration) CONFIGURATION="$2"; shift ;;
        -Abi) ABI_INPUT="$2"; shift ;;
        -NdkVersion) NDK_VERSION="$2"; shift ;;
        -AndroidNdkRoot) ANDROID_NDK_ROOT="$2"; shift ;;
        -AndroidSdkRoot) ANDROID_SDK_ROOT="$2"; shift ;;
        -CleanNative) CLEAN_NATIVE=1 ;;
    esac
    shift
done

# Resolve ABIs
declare -a ABIS
case "${ABI_INPUT,,}" in
    "arm") ABIS=("armeabi-v7a" "arm64-v8a") ;;
    "all") ABIS=("armeabi-v7a" "arm64-v8a" "x86" "x86_64") ;;
    "armeabi-v7a"|"armv7"|"armv7a") ABIS=("armeabi-v7a") ;;
    "arm64-v8a"|"arm64"|"aarch64") ABIS=("arm64-v8a") ;;
    "x86") ABIS=("x86") ;;
    "x86_64") ABIS=("x86_64") ;;
    *) echo "Unknown Android ABI '$ABI_INPUT'"; exit 1 ;;
esac

# Directories
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_ROOT="$REPO_ROOT/external/xash3d-fwgs"
TEMPLATE_DIR="$ENGINE_ROOT/android"
COF_SOURCE_DIR="$REPO_ROOT/src/cof"
GENERATED_ROOT="$REPO_ROOT/build/android"
PROJECT_DIR="$GENERATED_ROOT/xash3d-cof"
COF_NATIVE_BUILD_ROOT="$GENERATED_ROOT/cof-libs"
OUTPUT_APK="$REPO_ROOT/out/android/xash3d-cof.apk"

# Resolve NDK Root
if [ -z "$ANDROID_NDK_ROOT" ]; then
    if [ -n "$ANDROID_SDK_ROOT" ]; then
        ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
    else
        ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
    fi
fi

if [ ! -d "$ANDROID_NDK_ROOT" ]; then
    if [ -d "$ANDROID_SDK_ROOT/ndk" ]; then
        LATEST_NDK=$(ls -1 "$ANDROID_SDK_ROOT/ndk" | sort -V -r | head -n 1)
        if [ -n "$LATEST_NDK" ]; then
            NDK_VERSION="$LATEST_NDK"
            ANDROID_NDK_ROOT="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
            echo "Requested NDK not found. Using latest found NDK: $NDK_VERSION"
        fi
    fi
fi

if [ ! -d "$ANDROID_NDK_ROOT" ]; then
    echo "Error: Android NDK not found at $ANDROID_NDK_ROOT"
    exit 1
fi

echo "Preparing Xash3D CoF Android project..."
echo "ABIs: ${ABIS[*]}"

# Remove old project
if [[ "$PROJECT_DIR" == "$GENERATED_ROOT"* ]]; then
    rm -rf "$PROJECT_DIR"
fi

mkdir -p "$(dirname "$PROJECT_DIR")"
cp -r "$TEMPLATE_DIR" "$PROJECT_DIR"

# Patch build.gradle.kts
BUILD_FILE="$PROJECT_DIR/app/build.gradle.kts"
REPO_LITERAL="file(\"${REPO_ROOT}\")"
ENGINE_LITERAL="file(\"${ENGINE_ROOT}\")"
ABIS_LITERAL=$(printf '\"%s\", ' "${ABIS[@]}")
ABIS_LITERAL=${ABIS_LITERAL%, }

sed -i "s|plugins {|plugins {\nval cofRepoRoot = $REPO_LITERAL\nval xashEngineRoot = $ENGINE_LITERAL\n|" "$BUILD_FILE"
sed -i 's/namespace = "su.xash.engine"/namespace = "su.xash.cof"/' "$BUILD_FILE"
sed -i "s/ndkVersion = \".*\"/ndkVersion = \"$NDK_VERSION\"/" "$BUILD_FILE"
sed -i 's/applicationId = "su.xash.engine"/applicationId = "su.xash.cof"/' "$BUILD_FILE"
sed -i 's/versionName = "0.21-" + getGitHash()/versionName = "cof-" + getGitHash()/' "$BUILD_FILE"
sed -i 's/val engineRoot = projectDir.parentFile.parent/val engineRoot = xashEngineRoot/' "$BUILD_FILE"
sed -i "s/experimentalProperties\[\"ninja.abiFilters\"\] = setOf([^)]*)/experimentalProperties[\"ninja.abiFilters\"] = setOf($ABIS_LITERAL)/" "$BUILD_FILE"
sed -i 's|assets.directories.add("../../3rdparty/extras/xash-extras")|assets.directories.add(File(xashEngineRoot, "3rdparty/extras/xash-extras"))|' "$BUILD_FILE"
sed -i 's|java.directories.add("../../3rdparty/SDL/android-project/app/src/main/java")|java.directories.add(File(xashEngineRoot, "3rdparty/SDL/android-project/app/src/main/java"))|' "$BUILD_FILE"
sed -i '/applicationIdSuffix = ".test"/d' "$BUILD_FILE"
sed -i 's/release {/release {\n            signingConfig = signingConfigs.getByName("androidDebugKey")/' "$BUILD_FILE"
sed -i 's/.directory(project.rootDir)/.directory(cofRepoRoot)/' "$BUILD_FILE"

# Patch settings.gradle.kts
SETTINGS_FILE="$PROJECT_DIR/settings.gradle.kts"
sed -i 's/rootProject.name = "Xash3D FWGS"/rootProject.name = "Xash3D CoF"/' "$SETTINGS_FILE"

# Patch AndroidManifest.xml
MANIFEST_FILE="$PROJECT_DIR/app/src/main/AndroidManifest.xml"
REPLACEMENT='<activity android:name=".CofLauncherActivity" android:exported="true"><intent-filter><action android:name="android.intent.action.MAIN" /><category android:name="android.intent.category.LAUNCHER" /><\/intent-filter><\/activity>\n\t\t<activity android:name=".MainActivity" android:exported="false" \/>'
sed -i -z "s|<activity[[:space:]]*android:name=\"\.MainActivity\"[[:space:]]*android:exported=\"true\">[[:space:]]*<intent-filter>.*</intent-filter>[[:space:]]*</activity>|$REPLACEMENT|" "$MANIFEST_FILE"

# Patch strings.xml
STRINGS_FILE="$PROJECT_DIR/app/src/main/res/values/strings.xml"
sed -i -z 's|<string name="app_name" translatable="false">.*</string>|<string name="app_name" translatable="false">Xash3D CoF</string>|' "$STRINGS_FILE"

# Create Launcher Activity
ACTIVITY_DIR="$PROJECT_DIR/app/src/main/java/su/xash/engine"
mkdir -p "$ACTIVITY_DIR"
cat << 'EOF' > "$ACTIVITY_DIR/CofLauncherActivity.kt"
package su.xash.engine

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.Settings

class CofLauncherActivity : Activity() {
	private var requestedStorage = false
	private var startedEngine = false

	override fun onCreate(savedInstanceState: Bundle?) {
		super.onCreate(savedInstanceState)
		launchWhenReady()
	}

	override fun onResume() {
		super.onResume()
		launchWhenReady()
	}

	override fun onRequestPermissionsResult(
		requestCode: Int,
		permissions: Array<out String>,
		grantResults: IntArray
	) {
		super.onRequestPermissionsResult(requestCode, permissions, grantResults)
		launchWhenReady()
	}

	private fun launchWhenReady() {
		if (startedEngine) return

		if (!hasStorageAccess()) {
			requestStorageAccess()
			return
		}

		startedEngine = true

		val baseDir = Environment.getExternalStorageDirectory().absolutePath + "/xash"
		val args = "-game cryoffear -dll @hl -clientlib @client -console -log"

		startActivity(Intent(this, XashActivity::class.java).apply {
			flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK
			putExtra("gamedir", "valve")
			putExtra("argv", args)
			putExtra("basedir", baseDir)
			putExtra("gamelibdir", applicationInfo.nativeLibraryDir)
			putExtra("package", packageName)
		})

		finish()
	}

	private fun hasStorageAccess(): Boolean {
		return when {
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.R -> Environment.isExternalStorageManager()
			Build.VERSION.SDK_INT >= Build.VERSION_CODES.M -> {
				checkSelfPermission(Manifest.permission.READ_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED &&
					checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED
			}
			else -> true
		}
	}

	private fun requestStorageAccess() {
		if (requestedStorage) return
		requestedStorage = true

		if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
			val uri = Uri.fromParts("package", packageName, null)
			try {
				startActivity(Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION).setData(uri))
			} catch (e: Exception) {
				startActivity(Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION))
			}
		} else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
			requestPermissions(
				arrayOf(
					Manifest.permission.READ_EXTERNAL_STORAGE,
					Manifest.permission.WRITE_EXTERNAL_STORAGE
				),
				1
			)
		}
	}
}
EOF

# Build CoF game libraries with waf
export ANDROID_NDK="$ANDROID_NDK_ROOT"
export ANDROID_NDK_HOME="$ANDROID_NDK_ROOT"

WAF_BUILD_TYPE="release"
if [[ "${CONFIGURATION,,}" == "debug" ]]; then
    WAF_BUILD_TYPE="debug"
fi

for abi in "${ABIS[@]}"; do
    echo ""
    echo "Building CoF game libraries for $abi..."
    
    ABI_BUILD_DIR="$COF_NATIVE_BUILD_ROOT/$abi"
    cd "$COF_SOURCE_DIR"
    
    # Run waf
    chmod +x waf
    ./waf configure -T "$WAF_BUILD_TYPE" -o "$ABI_BUILD_DIR" --prefix=/ --disable-werror --android="$abi,,$MIN_SDK" --enable-android-apk --gamedir=cryoffear --server-install-dir=cl_dlls --client-install-dir=cl_dlls --server-library-name=hl
    
    if [ "$CLEAN_NATIVE" -eq 1 ]; then
        ./waf clean -o "$ABI_BUILD_DIR"
    fi
    
    ./waf build -o "$ABI_BUILD_DIR" -j"$JOBS"
    
    # Copy libraries
    JNI_DIR="$PROJECT_DIR/app/src/main/jniLibs/$abi"
    mkdir -p "$JNI_DIR"
    
    SERVER_LIB=$(find "$ABI_BUILD_DIR" -name "libhl.so" | head -n 1)
    CLIENT_LIB=$(find "$ABI_BUILD_DIR" -name "libclient.so" | head -n 1)
    
    if [ -n "$SERVER_LIB" ]; then cp "$SERVER_LIB" "$JNI_DIR/"; fi
    if [ -n "$CLIENT_LIB" ]; then cp "$CLIENT_LIB" "$JNI_DIR/"; fi
done

# Build APK
echo ""
echo "Building APK..."
cd "$PROJECT_DIR"
export ANDROID_HOME="$ANDROID_SDK_ROOT"
export ANDROID_SDK_ROOT="$ANDROID_SDK_ROOT"

chmod +x gradlew
./gradlew ":app:assemble${CONFIGURATION}"

# Copy APK
VARIANT_DIR="${CONFIGURATION,,}"
APK_DIR="$PROJECT_DIR/app/build/outputs/apk/$VARIANT_DIR"
APK_FILE=$(find "$APK_DIR" -name "*.apk" | head -n 1)

if [ -n "$APK_FILE" ]; then
    mkdir -p "$(dirname "$OUTPUT_APK")"
    cp "$APK_FILE" "$OUTPUT_APK"
    echo ""
    echo "Xash3D CoF APK created:"
    echo "$OUTPUT_APK"
else
    echo "Error: Gradle did not produce an APK in $APK_DIR."
    exit 1
fi
