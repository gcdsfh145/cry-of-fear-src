#!/bin/bash
set -e

echo "======================================"
echo "    Cry of Fear - All-in-One Build    "
echo "======================================"

echo ""
echo "[1/3] Building Xash3D Engine..."
./build_xash.sh -Configuration Release

echo ""
echo "[2/3] Building Game Libraries (Linux)..."
./build_game.sh -Configuration Release

echo ""
echo "[3/3] Building Android APK..."
./build_android.sh -Configuration Release -Abi all -NdkVersion "29.0.14206865"

echo ""
echo "======================================"
echo "          Build Completed!            "
echo "======================================"
echo "You can find the Android APK in out/android/"
