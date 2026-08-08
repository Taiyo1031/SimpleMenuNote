# SimpleMenuNote

SimpleMenuNoteは、macOSのメニューバーからすぐに開いて書けるMarkdownメモアプリです。Tagを表示Modeとして切り替え、そのTagに属するNoteを左右にめくれます。

## Requirements

- macOS 13 Ventura以降
- Xcode 26以降（Swift 5 language mode）
- Apple SiliconまたはIntel Mac

## Run

1. `SimpleMenuNote.xcodeproj`をXcodeで開きます。
2. `SimpleMenuNote` Schemeを選択してRunします。
3. メニューバーのNoteアイコンをクリックし、初回だけMarkdown保存フォルダを選択します。

アプリは`LSUIElement`として動作するため、Dockには常駐しません。メニューバーアイコンを右クリックすると管理画面と終了メニューを表示できます。

## Data format

1 Noteは1つの`.md`ファイルです。本文はアプリ独自DBではなくMarkdownファイルを正本として保存します。

```markdown
---
id: "A31F90B2-1234-5678-ABCD-0123456789AB"
created: "2026-08-08T15:23:15+09:00"
updated: "2026-08-08T15:31:02+09:00"
tags:
  - "TODO"
  - "Maya"
---

# 今日やること

- Maya
- レポート
```

Front Matterがない外部Markdownも読み込まれ、本文を維持したまま必要な管理項目が追加されます。補助情報（Tag UUID、表示位置、カーソル、スクロール）は`~/Library/Application Support/SimpleMenuNote/metadata.json`に保存されます。

## Test

```sh
xcodebuild test \
  -project SimpleMenuNote.xcodeproj \
  -scheme SimpleMenuNote \
  -destination 'platform=macOS'
```

テストはFront Matter、外部Markdown取込、重複UUID修復、Atomic Save競合保護、メタデータ、保存先移行を検証します。

## Development DMG

```sh
chmod +x Scripts/build-dmg.sh
Scripts/build-dmg.sh
```

`dist/SimpleMenuNote-1.0.0.dmg`が生成されます。このDMG内のアプリはUniversal Binaryかつad-hoc署名で、Apple公証はされていません。

## Developer ID signing and notarization

正式配布時は`SIGN_IDENTITY`を指定すると、同じスクリプトがアプリをHardened Runtime付きでDeveloper ID署名し、DMGにも署名します。資格情報はリポジトリへ保存しません。

```sh
SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' Scripts/build-dmg.sh
```

続いてnotarytool用のKeychain Profileを設定して公証します。

```sh
xcrun notarytool store-credentials SimpleMenuNote-Notary
NOTARY_PROFILE=SimpleMenuNote-Notary Scripts/notarize-dmg.sh path/to/SimpleMenuNote-1.0.0.dmg
```

## Privacy

アカウント、広告、Analytics、Tracking、独自Cloud、外部AI送信はありません。すべての機能をオフラインで利用できます。
