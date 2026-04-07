Start the embedded Anki sync server for local testing:

```bash
SYNC_USER1=user:pass cargo run -p anki-sync-server
```

Instructions:
- Set `SYNC_USER1` environment variable to `username:password` for auth
- The server listens on `http://127.0.0.1:8080` by default
- Configure Anki clients to use this URL as the sync endpoint
- Press Ctrl+C to stop the server
