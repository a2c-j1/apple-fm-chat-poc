# FM Chat

A macOS chat app PoC built with Apple Foundation Models. It supports text chats and image attachments.

[日本語](README_jp.md)

## Requirements

- Apple Silicon Mac with Apple Intelligence enabled and its on-device model ready
- macOS 26 or later for text chats. Image input requires macOS 27 or later.
- Xcode 27 or later

The app uses on-device models and needs no API key.

## Build and run

```sh
./scripts/build-app.sh
open "dist/FM Chat.app"
```

Click the paperclip button to attach up to four images, each up to 20 MB. Add a question or send images alone to ask the model to describe them.

Chats are saved in `~/Library/Application Support/FMChat/conversations.json`. The app copies attached images to `~/Library/Application Support/FMChat/attachments/`.
