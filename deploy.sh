#!/bin/bash
# Deploy ClinAssist to Dropbox
# Run this after making changes: ./deploy.sh

cd "$(dirname "$0")"

echo "Building ClinAssist..."
/Applications/Xcode-beta.app/Contents/Developer/usr/bin/xcodebuild \
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

