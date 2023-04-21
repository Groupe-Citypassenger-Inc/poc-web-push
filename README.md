Install dependencies

```
cpanm Dotenv;
cpanm HTTP::Request::Webpush
```

Generate keys

```
npx web-push generate-vapid-keys
```

Create .env with

PRIVATE_KEY=...
PUBLIC_KEY=...