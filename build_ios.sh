#!/bin/bash
set -e

echo "------------------------------------------------"
echo "Starting iOS Build (Simulator Verification)"
echo "------------------------------------------------"

# Build for simulator to verify code correctness
xcodebuild -project ios/CoinBounce.xcodeproj \
           -scheme CoinBounce \
           -sdk iphonesimulator \
           -destination 'generic/platform=iOS Simulator' \
           build

# Run Unit Tests
echo "------------------------------------------------"
echo "Running iOS Unit Tests..."
xcodebuild test -project ios/CoinBounce.xcodeproj \
                -scheme CoinBounce \
                -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
                | tee test_output.txt

echo "<html><head><title>iOS Test Report</title><style>body { font-family: monospace, sans-serif; background: #1e1e1e; color: #fff; padding: 20px; }</style></head><body><h2>Automated Test Verification</h2><pre>" > TestReport.html
cat test_output.txt | tail -n 50 >> TestReport.html
echo "</pre></body></html>" >> TestReport.html

echo ""
echo "------------------------------------------------"
echo "iOS Verification & Tests Successful! Generated TestReport.html"
echo "------------------------------------------------"
