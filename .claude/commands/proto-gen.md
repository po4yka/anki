Regenerate Swift protobuf types from the proto definitions:

```bash
protoc --swift_out=AnkiApp/AnkiApp/AnkiApp/Proto/ --proto_path=proto/ proto/anki/*.proto
```

Report which files were generated. If protoc is not installed, show:
```bash
brew install protobuf swift-protobuf
```
