# 使い方のサイト（site/）

Adventure Board の使い方とチュートリアル。VitePress で作る。

- 使い方とチュートリアル: **https://picorubykaigi.org/adventure-board/**（リポジトリ `picorubykaigi/adventure-board` の Pages）
- コンソール（`sim/`）: **https://picorubykaigi.org/adventure-board-console/**（リポジトリ `picorubykaigi/adventure-board-console` の Pages）

2026-10-25〜26 は両方とも https://picorubykaigi.org/adventure-board-firmware/ にあった（コンソールは `console/`）。
そこは今、新しい URL へ送るページだけになっている（下の「公開」）。

```console
rake site:dev        # 書きながら見る → http://localhost:5173/adventure-board/（コンソールは入らない）
rake site:build      # site/.vitepress/dist に組み立てる（手元で見るために、コンソールを console/ に入れる）
rake site:preview    # 組み立てたものを見る → 同じ URL
rake site:console_standalone   # コンソールだけを公開と同じ形で tmp/console に組み立てる（OUT=dir で変えられる）
```

Node は Docker の `node:22-bookworm-slim` の中で動かす（`docker/compose.yml` の `site`）。ホストには入れない。
パッケージは最初の `rake site:*` で `site/node_modules` に入る（git 管理外）。

## 構成

| 場所 | 中身 |
|---|---|
| `index.md` | トップ |
| `guide/` | はじめに（基板の各部、コンソール、シェル、ファームウェアの書き込み） |
| `tutorial/` | チュートリアル 1〜8 |
| `reference/` | ライブラリ、ピンとコネクタ |
| （`../sim/examples/0*.rb`） | チュートリアルのコード。ページのサンプルと同じファイルで、本文は `<<< @/../sim/examples/01_light.rb` のように読み込む |
| `public/` | 画像とフォント。そのまま出る |
| `.vitepress/config.mts` | 目次（サイドバー）、URL の前置き（`SITE_BASE`、既定 `/adventure-board/`）、コンソールの URL（`VITE_CONSOLE_URL`） |
| `.vitepress/theme/ConsoleLink.vue` | コンソールへのリンク。`<ConsoleLink example="01_light.rb" />` でそのサンプルを開く。本文に `[…](/console/){target="_blank"}` と書くと、VitePress が前置きを足さず公開先で 404 になる |
| `old-url-redirect/` | 古い URL（`/adventure-board-firmware/`）から新しい URL へ送るページ |
| `.vitepress/theme/style.css` | 色とフォント。picorubykaigi.org とコンソールに合わせてある |

## コンソールの組み立て

コンソールは、リポジトリの `lib/`・`examples/`・`mrbgems/` を `window.REPO_ROOT`（`sim/index.html` の 1 行）の下から読む。

| 組み立て方 | コンソールの置き場所 | リポジトリのファイル | `REPO_ROOT` |
|---|---|---|---|
| `rake sim:server`（リポジトリそのまま） | `sim/` | リポジトリのまま | `../` |
| `rake site:build`（手元で見る用） | `dist/console/` | `dist/lib/` など | `../` |
| `rake site:console_standalone`（公開用） | 一番上 | `repo/lib/` など | `./repo/`（書き換える） |

写すのは `sim/`（`README.md` と `test/` を除く）、`lib/adventure_board*`、`examples/*.rb`、`sim/index.html` が `M + '…'` で読む gem の `.rb`。
`sim/vendor/`（`rake sim:wasm`）が無いと、CDN の素の wasm で動く（漢字と色付けが出ない）。そのときは警告を出す。

## チュートリアルのコード

チュートリアルのコード（`sim/examples/` の番号付きのもの）は、シミュレータで動かして確かめてから載せる。実機と同じ書き方しか使わない
（シミュレータ専用の構文は禁止。基板の stdlib に無いメソッド、たとえば `Integer#clamp` や `Array#count` も避ける）。

## 公開（GitHub Actions）

組み立て方はこのリポジトリにだけある。公開するリポジトリは、それを呼んで自分の Pages に出すだけ。

| workflow | 何をする |
|---|---|
| `.github/workflows/build-guide.yml` | ガイドを組み立てる（`SITE_BASE=/adventure-board/`、`VITE_CONSOLE_URL=https://picorubykaigi.org/adventure-board-console/`）。ほかのリポジトリから呼ぶ |
| `.github/workflows/build-console.yml` | wasm を作り（emsdk、`EMSDK_VERSION` は手元の `~/emsdk` と同じ版）、`rake site:console_standalone` で組み立てる。ほかのリポジトリから呼ぶ |
| `.github/workflows/site.yml` | main への push で上の 2 つを組み立てるだけ（壊れていないかの確認）。手で起動して「GitHub Pages にも出す」にチェックすると、このリポジトリの Pages（古い URL）に `old-url-redirect/` を出す |
| `picorubykaigi/adventure-board` の `deploy.yml` | `build-guide.yml` を呼んで Pages に出す |
| `picorubykaigi/adventure-board-console` の `deploy.yml` | `build-console.yml` を呼んで Pages に出す |

**ドキュメントやコンソールを直しても、push しただけでは公開中のサイトは変わらない。** 公開するリポジトリの
Actions → deploy → **Run workflow** で出す（`ref` で、このリポジトリのブランチ・タグ・コミットを選べる。既定は `main`）。
`gh` なら `gh workflow run deploy.yml -R picorubykaigi/adventure-board`（コンソールは `-R picorubykaigi/adventure-board-console`）。

## チームの確認用だったもの（Cloudflare Pages + Access）

リポジトリが非公開だったあいだ（〜2026-10-25）、チームには https://adventure-board.pages.dev を Cloudflare Access の後ろで見てもらっていた。
もう使わない。workflow からは送る段を外した。残っているなら次で片付ける。

1. GitHub の Secrets から `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` を消す
2. Cloudflare の Workers & Pages → `adventure-board` → 設定 → 一般 → 削除
3. Zero Trust のアプリ `adventure-board - Cloudflare Pages` とポリシー `Allow Members - Cloudflare Pages` を消す
4. API トークンを消す
