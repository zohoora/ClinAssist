#!/bin/bash
# Deploy ClinAssist to Dropbox
# Run this after making changes: ./deploy.sh

cd "$(dirname "$0")"

# Option to skip tests with --skip-tests
SKIP_TESTS=false
if [ "$1" == "--skip-tests" ]; then
    SKIP_TESTS=true
fi

# Run tests before deployment (unless skipped)
if [ "$SKIP_TESTS" == "false" ]; then
    echo "Running tests..."
    xcodebuild test \
        -project ClinAssist.xcodeproj \
        -scheme ClinAssist \
        -destination 'platform=macOS' \
        -quiet 2>&1 | tail -20

    if [ ${PIPESTATUS[0]} -ne 0 ]; then
        echo "❌ Tests failed. Fix tests before deploying."
        echo "   Run with --skip-tests to bypass (not recommended)"
        exit 1
    fi
    echo "✅ All tests passed"
    echo ""
fi

echo "Building ClinAssist..."
xcodebuild \
    -project ClinAssist.xcodeproj \
    -scheme ClinAssist \
    -configuration Debug \
    build 2>&1 | grep -E "(error:|warning:|BUILD)"

if [ $? -eq 0 ]; then
    echo ""
    echo "Copying to Dropbox..."
    rm -rf ~/Dropbox/livecode_records/ClinAssist.app
    cp -R ~/Library/Developer/Xcode/DerivedData/ClinAssist-*/Build/Products/Debug/ClinAssist.app ~/Dropbox/livecode_records/
    echo "✅ Deployed to ~/Dropbox/livecode_records/ClinAssist.app"
    echo ""
    echo "Dropbox will sync to other computers automatically."
else
    echo "❌ Build failed"
    exit 1
fi

