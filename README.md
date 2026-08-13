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

Note上部の目のボタンを押すとMarkdownプレビューへ切り替わり、鉛筆ボタンを押すとNote全体の原文編集へ戻ります。プレビューは見出し、太字、斜体、箇条書き、番号付きリスト、リンク、インラインコード、引用、コードブロック、区切り線を表示します。表示中のブロックをクリックすると、そのブロックだけMarkdown原文で編集できます。外側のクリック、`⌘Return`、`Esc`で完成形表示へ戻ります。リンクのクリックはブラウザで開きます。管理画面のNoteエディタでも同じ切替が使えます。

小さいNoteウインドウでは、`⌘⌥←`／`⌘⌥→`でNoteを循環し、`⌘⌥↑`／`⌘⌥↓`で「すべて → Tag名順 → Tagなし」を循環できます。通常の矢印キーは本文中のカーソル移動に使えます。

NoteとTagの削除確認は、それぞれ最初に削除を確定した時だけ表示されます。削除後5秒間は画面下部の「元に戻す」から復元できます。確認を再表示したい場合は、設定の「データ」から「削除確認をもう一度表示」を選択してください。Noteファイルは削除時にmacOSのゴミ箱へ移動します。

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

テストはFront Matter、外部Markdown取込、重複UUID修復、Atomic Save競合保護、メタデータ、保存先移行、Markdownプレビュー変換と原文範囲、Tag循環、削除確認・復元を検証します。

## Development DMG

```sh
chmod +x scripts/build-dmg.sh
scripts/build-dmg.sh
```

`dist/SimpleMenuNote-1.0.0.dmg`が生成されます。このDMG内のアプリはUniversal Binaryかつad-hoc署名で、Apple公証はされていません。

## Developer ID signing and notarization

正式配布時は`SIGN_IDENTITY`を指定すると、同じスクリプトがアプリをHardened Runtime付きでDeveloper ID署名し、DMGにも署名します。資格情報はリポジトリへ保存しません。

```sh
SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' scripts/build-dmg.sh
```

続いてnotarytool用のKeychain Profileを設定して公証します。

```sh
xcrun notarytool store-credentials SimpleMenuNote-Notary
NOTARY_PROFILE=SimpleMenuNote-Notary scripts/notarize-dmg.sh path/to/SimpleMenuNote-1.0.0.dmg
```

## Privacy

アカウント、広告、Analytics、Tracking、独自Cloud、外部AI送信はありません。すべての機能をオフラインで利用できます。
