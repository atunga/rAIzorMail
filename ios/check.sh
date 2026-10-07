#!/bin/sh
# Tests use fictional data and a mock URLSession. No Google account is contacted.
set -eu
cd "$(dirname "$0")/.."
check_dir="$(mktemp -d /tmp/raizor-ios-checks.XXXXXX)"
trap 'rm -rf "$check_dir"' EXIT
swiftc ios/MailCore/Sources/MailCore/MailCore.swift ios/checks/CoreChecks.swift -o "$check_dir/core"
"$check_dir/core"
swiftc -swift-version 5 -typecheck ios/MailCore/Sources/MailCore/MailCore.swift ios/rAIzorMail/Accounts.swift ios/rAIzorMail/GoogleAPI.swift ios/rAIzorMail/Gemini.swift ios/rAIzorMail/MailModel.swift
swiftc -swift-version 5 ios/MailCore/Sources/MailCore/MailCore.swift ios/checks/AccountsStub.swift ios/rAIzorMail/GoogleAPI.swift ios/rAIzorMail/Gemini.swift ios/checks/ServiceChecks.swift -o "$check_dir/services"
"$check_dir/services"
swiftc -frontend -parse ios/rAIzorMail/*.swift ios/MailCore/Sources/MailCore/*.swift
plutil -lint ios/rAIzorMail.xcodeproj/project.pbxproj ios/rAIzorMail/Info.plist ios/rAIzorMail/PrivacyInfo.xcprivacy
printf '\nCore and service checks passed. Full iOS compilation still requires Xcode and the iOS SDK.\n'
