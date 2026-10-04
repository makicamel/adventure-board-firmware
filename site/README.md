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

## チームの確認用（Cloudflare Pages + Access）

リポジトリが非公開のあいだ、チームには Cloudflare Pages に置いたものを見てもらう。**確認用だけ**で、公開は GitHub Pages。
前に Cloudflare Access（ログインの門番）を置き、許可したメールアドレスの人だけが見られるようにする。

`build` の最後の 3 段がそれ。Secrets の `CLOUDFLARE_API_TOKEN` が無ければ飛ばす。
pages.dev はサイトを根元に置くので、`SITE_BASE=/` でもう一度組み立てて送る。
プロジェクト名は `adventure-board`（Actions の変数 `CLOUDFLARE_PROJECT` で変えられる）。

### 最初の設定（Cloudflare の画面）

**順番を守ること。** Access より先に何かを送ると、そのあいだ誰でも見られる。Secrets は最後に入れる。

1. Cloudflare のアカウントを作る
2. **API トークン**を作る: My Profile → API Tokens → Create Token → Custom token。
   権限は **Account / Cloudflare Pages / Edit** だけ。あわせて **Account ID**（アカウントのホームの右側）を控える
3. **プロジェクトだけを作る**（中身は送らない）。手元で:
   ```console
   export CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=…
   docker compose -f docker/compose.yml run --rm -e CLOUDFLARE_API_TOKEN -e CLOUDFLARE_ACCOUNT_ID site \
     npx --yes wrangler@4 pages project create adventure-board --production-branch main
   ```
   `adventure-board.pages.dev` が取られていると、後ろに文字が付いた名前になる。そのときは出てきた名前を
   GitHub の Settings → Secrets and variables → Actions → **Variables** に `CLOUDFLARE_PROJECT` として入れる
4. **Access を付ける**: Zero Trust → Access → Applications → Add an application → **Self-hosted**
   - 守る場所（Public hostname）を 2 つ: `adventure-board.pages.dev` と `*.adventure-board.pages.dev`
     （本番の URL と、送るたびに付く版ごとの URL。Pages の設定の「Enable access policy」は版ごとの URL しか守らない）
   - Policy: Action **Allow**、Include **Emails** にチームのメールアドレスを並べる
   - ログイン方法は **One-time PIN**（メールに届くコード）
   - Zero Trust を初めて開くと、チーム名とプランを聞かれる。**Free**（50 人まで）を選ぶ
5. ブラウザで `https://adventure-board.pages.dev` を開き、**ログイン画面が出ることを確かめる**
   （まだ中身が無いので、通っても空のページ）
6. GitHub の Settings → Secrets and variables → Actions → **Secrets** に
   `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` を入れる
7. Actions → site → Run workflow（または main に push）。終わったら 5 の URL で中身が見える

人を足すときは 4 の Policy にメールアドレスを足す。見る人は URL を開いてメールアドレスを入れ、届いたコードを入れる。

### 公開の日

GitHub Pages で公開したら、Cloudflare のプロジェクトは消してよい（Pages → プロジェクト → Settings → Delete）。
Secrets を消せば、workflow は Cloudflare に送らなくなる。

## 公開の日にすること

1. リポジトリを公開にする
2. Settings → Pages → Source を GitHub Actions にする
3. Actions → site → **Run workflow**（main）。手で起動したときだけ Pages に出る
4. `https://picorubykaigi.org/adventure-board-firmware/` を開いて確かめる
5. UF2 の Release を作る（`guide/firmware.md` がリンクしている）。タグは `v2026.10.31` のように日付、
   ファイルは `dist/picoruby-pico2-prod/R2P2-*.uf2`（prod、`R2P2_CONSOLE_UART=1`）を `adventure-board-2026.10.31.uf2` に名前を変えて付ける
