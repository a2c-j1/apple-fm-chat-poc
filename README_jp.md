# FM Chat

Apple Foundation Models を使った macOS チャットアプリの PoC です。テキストと画像に対応しています。

[English](README.md)

## 動作条件

- Apple Intelligence を有効にし、オンデバイスモデルの準備ができた Apple Silicon Mac
- テキストチャットは macOS 26 以降。画像入力には macOS 27 以降が必要です。
- Xcode 27 以降

オンデバイスモデルを使うため、API キーは不要です。

## ビルドと起動

```sh
./scripts/build-app.sh
open "dist/FM Chat.app"
```

クリップボタンから、1枚20 MB以下の画像を最大4枚添付できます。画像について質問するか、画像だけを送信して説明を依頼できます。

会話履歴は `~/Library/Application Support/FMChat/conversations.json` に保存します。添付画像は `~/Library/Application Support/FMChat/attachments/` にコピーします。
