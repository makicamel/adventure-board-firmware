# 使い方のサイト（site/）

Adventure Board の使い方とチュートリアル。VitePress で作り、コンソール（`sim/`）を `console/` に同梱して
GitHub Pages に出す。**公開はイベントの日（2026-10-31）**。それまではリポジトリが非公開なので、手元で見るだけ。

```console
rake site:dev        # 書きながら見る → http://localhost:5173/adventure-board-firmware/（コンソールは入らない）
rake site:build      # site/.vitepress/dist に組み立てる（コンソールも入る）
rake site:preview    # 組み立てたものを公開と同じ形で見る → 同じ URL
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
| `snippets/*.rb` | チュートリアルのコード。本文は `<<< @/snippets/xxx.rb` で読み込む |
| `public/` | 画像とフォント。そのまま出る |
| `.vitepress/config.mts` | 目次（サイドバー）、URL の前置き（`SITE_BASE`、既定 `/adventure-board-firmware/`） |
| `.vitepress/theme/style.css` | 色とフォント。picorubykaigi.org とコンソールに合わせてある |

## コンソールの同梱

`rake site:build` は VitePress のあとに `site:console` を走らせ、次を `dist/` に写す。
コンソールはリポジトリのファイルを相対パスで読むので、リポジトリと同じ並びにしてある。

- `sim/`（`README.md` と `test/` を除く）→ `console/`
- `lib/` → `lib/`、`examples/*.rb` → `examples/`
- `sim/index.html` が `M + '…'` で読む gem の `.rb` → `mrbgems/…`

`sim/vendor/`（`rake sim:wasm`）が無いと、CDN の素の wasm で動く（漢字と色付けが出ない）。そのときは警告を出す。

## チュートリアルのコード

`snippets/` のコードは、シミュレータで動かして確かめてから載せる。実機と同じ書き方しか使わない
（シミュレータ専用の構文は禁止。基板の stdlib に無いメソッド、たとえば `Integer#clamp` や `Array#count` も避ける）。

## GitHub Actions

`.github/workflows/site.yml`。main への push（サイト・コンソール・ライブラリ・サンプルが変わったとき）では
**組み立てるだけ**で、できたものは Actions の中に残るだけ。**Pages に出すのは手で起動したときだけ**（`workflow_dispatch`）。
wasm は Docker ではなく、Actions の上で emsdk（`EMSDK_VERSION`、手元の `~/emsdk` と同じ版）を入れて作る。

非公開のリポジトリ（organization は Free プラン）では Pages を有効にできないので、手で起動しても出す段で失敗するだけで、
外からは何も見えない。organization を有料プランにして Pages を有効にすると、リポジトリが非公開でもサイトは誰でも見える。

## 公開の日にすること

1. リポジトリを公開にする
2. Settings → Pages → Source を GitHub Actions にする
3. Actions → site → **Run workflow**（main）。手で起動したときだけ Pages に出る
4. `https://picorubykaigi.org/adventure-board-firmware/` を開いて確かめる
5. UF2 の Release を作る（`guide/firmware.md` がリンクしている）。タグは `v2026.10.31` のように日付、
   ファイルは `dist/picoruby-pico2-prod/R2P2-*.uf2`（prod、`R2P2_CONSOLE_UART=1`）を `adventure-board-2026.10.31.uf2` に名前を変えて付ける
