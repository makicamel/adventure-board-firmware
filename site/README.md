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
| （`../sim/examples/0*.rb`） | チュートリアルのコード。ページのサンプルと同じファイルで、本文は `<<< @/../sim/examples/01_light.rb` のように読み込む |
| `public/` | 画像とフォント。そのまま出る |
| `.vitepress/config.mts` | 目次（サイドバー）、URL の前置き（`SITE_BASE`、既定 `/adventure-board-firmware/`） |
| `.vitepress/theme/style.css` | 色とフォント。picorubykaigi.org とコンソールに合わせてある |

## コンソールの同梱

`rake site:build` は VitePress のあとに `site:console` を走らせ、次を `dist/` にコピーする。
コンソールはリポジトリのファイルを相対パスで読むので、リポジトリと同じ並びにしてある。

- `sim/`（`README.md` と `test/` を除く）→ `console/`
- `lib/` → `lib/`、`examples/*.rb` → `examples/`
- `sim/index.html` が `M + '…'` で読む gem の `.rb` → `mrbgems/…`

`sim/vendor/`（`rake sim:wasm`）が無いと、CDN の素の wasm で動く（漢字と色付けが出ない）。そのときは警告を出す。

## チュートリアルのコード

チュートリアルのコード（`sim/examples/` の番号付きのもの）は、シミュレータで動かして確かめてから載せる。実機と同じ書き方しか使わない
（シミュレータ専用の構文は禁止。基板の stdlib に無いメソッド、たとえば `Integer#clamp` や `Array#count` も避ける）。

## GitHub Actions

`.github/workflows/site.yml`。main への push（サイト・コンソール・ライブラリ・サンプルが変わったとき）では
**組み立てるだけ**で、できたものは Actions の中に残るだけ。**Pages に出すのは、手で起動して「GitHub Pages にも出す」にチェックを入れたときだけ**（`workflow_dispatch`）。
wasm は Docker ではなく、Actions の上で emsdk（`EMSDK_VERSION`、手元の `~/emsdk` と同じ版）を入れて作る。

非公開のリポジトリ（organization は Free プラン）では Pages を有効にできないので、手で起動しても出す段で失敗するだけで、
外からは何も見えない。organization を有料プランにして Pages を有効にすると、リポジトリが非公開でもサイトは誰でも見える。

## チームの確認用（Cloudflare Pages + Access）

リポジトリが非公開のあいだ、チームには Cloudflare Pages に置いたものを見てもらう。**確認用だけ**で、公開は GitHub Pages。
前に Cloudflare Access（ログインの門番）を置き、許可したメールアドレスの人だけが見られるようにしてある。

- URL: **https://adventure-board.pages.dev**（送るたびに `<番号>.adventure-board.pages.dev` の版ごとの URL も付く）
- 見る人: URL を開く → メールアドレスを入れる → メールに届いたコードを入れる
- 中身: main に push するたび（`site.yml` の `paths` に当たる変更のとき）と、Actions → site → Run workflow のたびに新しくなる

### いまの設定（2026-10-04 に作った）

| もの | 場所 | 値 |
|---|---|---|
| Pages のプロジェクト | Workers & Pages | `adventure-board`（プロダクション ブランチ `main`）。**中身を送る前は一覧に出なかった** |
| API トークン | アカウント API トークン | 権限は Pages の Edit だけ。GitHub の Secrets `CLOUDFLARE_API_TOKEN` に入れてある |
| アカウント ID | Workers & Pages の右側「アカウントの詳細」 | GitHub の Secrets `CLOUDFLARE_ACCOUNT_ID` に入れてある |
| Zero Trust のチーム | Zero Trust | ログイン画面は `kishima.cloudflareaccess.com` |
| ログイン方法 | Zero Trust → インテグレーション → ID プロバイダーの統合 | 「ワンタイム PIN」（メールに届くコード）を足した。「Cloudflare」は元からあったもの |
| Access のアプリ | Zero Trust → Access コントロール → アプリケーション | `adventure-board - Cloudflare Pages`。宛先は `*.adventure-board.pages.dev` と `adventure-board.pages.dev` の **2 行** |
| 通す人 | 同じアプリのポリシー | `Allow Members - Cloudflare Pages`。アクション Allow、包含 Emails |

`build` の最後の 3 段が送る段。Secrets の `CLOUDFLARE_API_TOKEN` が無ければ飛ばす。
pages.dev はサイトを根元に置くので、`SITE_BASE=/` でもう一度組み立てて送る。
プロジェクト名は `adventure-board`（Actions の変数 `CLOUDFLARE_PROJECT` で変えられる）。

### 人を足す・外す

Zero Trust → Access コントロール → ポリシー → `Allow Members - Cloudflare Pages` → 編集 → 包含の Emails にアドレスを足す（外す）。
足した人はすぐ入れる。外した人も、ログインが切れるまで（アプリのセッションの長さ）は見えるままのことがある。

### 守られているかを確かめる

ログインせずに開くと、ページではなくログイン画面への転送（302）が返ればよい。

```console
for u in https://adventure-board.pages.dev/ https://adventure-board.pages.dev/console/ https://main.adventure-board.pages.dev/; do
  curl -s -o /dev/null -w "$u %{http_code} %{redirect_url}\n" "$u" | cut -c1-120
done
# どれも 302 https://kishima.cloudflareaccess.com/cdn-cgi/access/login/... になる
```

### 作り直すときの手順

**順番を守ること。** Access より先に中身を送ると、そのあいだ誰でも見られる。Secrets は最後に入れる。

1. **API トークン**: 右上の人のアイコン → プロフィール → API トークン → トークンを作成 → カスタム トークン。
   ポリシーの編集で「アカウント全体」のまま、`pages` で探して **Developer Platform の Pages の Edit** だけにチェック。
   値は作った画面でしか見られないので、その場で控える
2. **アカウント ID**: Workers & Pages の画面の右側「アカウントの詳細」の Account ID
3. **プロジェクトだけを作る**（中身は送らない）。トークンが履歴に残らないよう `read -s` で入れる:
   ```console
   read -s -p 'token: ' CLOUDFLARE_API_TOKEN; echo; export CLOUDFLARE_API_TOKEN
   docker compose -f docker/compose.yml run --rm -e CLOUDFLARE_API_TOKEN site \
     npx --yes wrangler@4 pages project create adventure-board --production-branch main
   docker compose -f docker/compose.yml run --rm -e CLOUDFLARE_API_TOKEN site \
     npx --yes wrangler@4 pages project list      # 作れたかの確認。ダッシュボードの一覧には、送るまで出ない
   ```
   アカウントが 1 つなら `CLOUDFLARE_ACCOUNT_ID` は無くてよい（トークンから決まる）。最後に出る URL を控える。
   `adventure-board.pages.dev` がほかの人に取られていると後ろに文字が付くので、以下はその URL に読み替える
4. **Zero Trust**: 左のメニューの Zero Trust。初めてならチーム名とプラン（**Free**、50 人まで）を聞かれる
5. **ログイン方法**: Zero Trust → インテグレーション → **ID プロバイダーの統合** →「ID プロバイダーを追加する」→ **ワンタイム PIN**。
   （アカウントの管理 → メンバー → 設定 は、ダッシュボード自体のログインの設定で、関係ない）
6. **版ごとの URL を守る**: Workers & Pages → `adventure-board` → 設定 → 右の目次の「一般」→ **プレビュー アクセス** の
   「**プレビューを制限**」。Zero Trust にアプリ `adventure-board - Cloudflare Pages`（宛先 `*.adventure-board.pages.dev`）と
   ポリシー `Allow Members - Cloudflare Pages` が自動で作られる。**これだけでは本番の URL は守られない**
7. **本番の URL も守る**: Zero Trust → Access コントロール → アプリケーション → そのアプリ → 宛先の「＋ パブリック ホスト名を追加」→
   サブドメインは**空**、ドメインは `adventure-board.pages.dev`。`*` の行と 2 行並べて保存
8. **通す人**: 同じアプリのポリシー（`Allow Members - Cloudflare Pages`）を編集 → アクション Allow、包含を **Emails** にして
   アドレスを並べる（自分も入れる）。自動で入っていた別の条件は外す
9. **確かめる**: 上の「守られているかを確かめる」で、本番と版ごとの URL がどちらもログイン画面に飛ぶこと。
   シークレットウィンドウで開いて、自分のアドレスとコードでログインできること
10. **Secrets**: GitHub の Settings → Secrets and variables → Actions → Secrets に
    `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` を入れる。ターミナルのトークンは `unset CLOUDFLARE_API_TOKEN`
11. **送る**: Actions → site → Run workflow（main、「GitHub Pages にも出す」は**チェックしない**）。
    ログの「Send to Cloudflare Pages」に `Deployment complete!` が出ればよい。9 の確かめをもう一度

### 公開の日に片付ける

GitHub Pages で公開したら、Cloudflare 側は要らなくなる。

1. GitHub の Secrets から `CLOUDFLARE_API_TOKEN` と `CLOUDFLARE_ACCOUNT_ID` を消す（workflow は Cloudflare に送らなくなる）
2. Workers & Pages → `adventure-board` → 設定 → 一般 → 削除
3. Zero Trust のアプリとポリシーを消す
4. API トークンを消す（アカウント API トークン、またはプロフィール → API トークン）

## 公開の日にすること

1. リポジトリを公開にする
2. Settings → Pages → Source を GitHub Actions にする
3. Actions → site → **Run workflow**（main）で「GitHub Pages にも出す」にチェックを入れて起動する。チェックを入れたときだけ Pages に出る
4. `https://picorubykaigi.org/adventure-board-firmware/` を開いて確かめる
5. UF2 の Release を作る（`guide/firmware.md` がリンクしている）。タグは `v2026.10.31` のように日付、
   ファイルは `dist/picoruby-pico2-prod/R2P2-*.uf2`（prod、`R2P2_CONSOLE_UART=1`）を `adventure-board-2026.10.31.uf2` に名前を変えて付ける
6. Cloudflare の確認用を片付ける（上の「公開の日に片付ける」）
