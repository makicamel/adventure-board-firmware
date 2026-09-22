# WebSerial コンソール調査 — 統合版に向けて

**（2026-09-22）統合した。** シミュレータのページに xterm.js の端末が付き、`sim/sim_device.rb` が下の部品をそのまま使っている。
以下は当時の調査。

シミュレータと実機コンソールを 1 つのページにまとめられるか、の下調べ。
**結論から言うと、必要な部品はすべて揃っている。**

## 1. すでに存在するもの（すべて確認済み）

| | 場所 | 状態 |
|---|---|---|
| ブラウザ側 WebSerial | `picoruby-wasm/mrblib/webserial.rb` + `src/mruby/webserial.c` | **stock パッケージに同梱**（`JS::WebSerial`） |
| 実機コンソールのページ | `picoruby-wasm/demo/www/terminal.html`（879行） | xterm.js + ファイル転送。UI ロジックは全部 Ruby |
| 実機側の転送プロトコル | `picoruby-picomodem`（RBTP） | **我々のファームに入っている**（`picoruby-shell` が依存。pico2_w の `gem_init.c` で確認） |
| 実機側の入口 | `Shell#run_shell` の **Ctrl-B** | `PicoModem.session($stdin, $stdout)` へ入る |

### `JS::WebSerial` の API

```ruby
JS::WebSerial.supported?
JS::WebSerial.connect(baud_rate: 115200, data_bits: 8, stop_bits: 1, parity: "none") { |ws| ... }
JS::WebSerial.request_port(filters: []) { |port| ... }

ws.on_receive { |bytes| ... }
ws.on_disconnect { ... }
ws.write_bytes(bytes, chunk_size: 32)
ws.close
ws.opened?
```

バイナリ転送用に C 側へ `serial_binary_capture_start` / `_read` があり、
`JS::WebSerial.binary_capture_*` として使える（PicoModem のファイル転送がこれを使う）。

### 実機との会話の始め方

R2P2 のシェルで **Ctrl-B**（STX）を送ると、`\x06`（ACK）を返して
`PicoModem.session` に入る。ブラウザはその ACK を合図にバイナリ捕捉へ切り替える。
セッションを抜けるとシェルへ戻る。

### R2P2 の CDC ポート（3本）

| ポート | 用途 |
|---|---|
| CDC 0 | **シェル本体**と stdout。WebSerial で繋ぐのはここ |
| CDC 1 | デバッグ出力（デバッグビルドのみ） |
| CDC 2 | 生 MIDI バイトストリーム（WebSerial 用） |

ブラウザのポート選択ダイアログには 3 本とも出るので、**利用者がどれを選ぶか**の
案内が要る。

## 2. これが解く問題

`/lib/picorubykaigi01.rb` をどうやってデバイスへ入れるか
（[../board-gems/README.md](../board-gems/README.md) §3-2）が、**ブラウザから解決できる**。

`terminal.html` のファイルエディタは、パスを指定してアップロードできる
（既定は `/home/app.rb`、`Plain` / `Compile` の 2 モード）。
`/lib/picorubykaigi01.rb` を指定すれば、**picotool も littlefs イメージも要らず**
ブラウザからボードライブラリを配置できる。

Compile モードは `.mrb` に落とすので、**ソースを読ませたい今回の方針では Plain を使う**。

## 3. 統合版の姿

1 つのページで、

```
┌──────────────┬──────────────────────────────┐
│  16×16 パネル │  [シミュレータ] / [実機に接続] │
│              │  ─────────────────────────── │
│  ボタン       │  エディタ / ターミナル         │
└──────────────┴──────────────────────────────┘
```

- **シミュレータモード**: 今のまま。仮想チップに描く
- **実機モード**: WebSerial で R2P2 に繋ぎ、xterm.js でシェル。
  同じエディタの内容を `/home/app.rb` や `/lib/...` へ送れる

**サンプルコードは両モードで同一**（シミュレータ専用構文を禁止したので、
そのまま実機へ送れる）。これが統合版の一番の価値。

パネル表示は実機モードでは意味を持たない（実機の LED は物理的に光る）。
代わりに実機からの stdout をターミナルに出す。

## 4. 制約と未確認事項

| 項目 | 内容 |
|---|---|
| ブラウザ | WebSerial は Chrome / Edge のみ。Safari と Firefox では使えない |
| セキュアコンテキスト | `localhost` か HTTPS が必要 |
| ポート選択 | CDC が 3 本見える（シェル / デバッグ / MIDI）。選ぶのは**最後に接続されたもの**で、COM 番号の若いほう（CDC0 と思っていた）ではなかった（2026-09-22 訂正） |
| ファイル転送の実地確認 | **未検証**。Pico 2 W に我々のファームを焼いて Ctrl-B → アップロードを試す必要がある |
| ヘッドレス検証 | Playwright で WebSerial は扱えない。**実機モードは自動検証できない**ので、シミュレータモードとは検証手段が分かれる |
| `terminal.html` の流用 | 879 行あり、Funicular ではなく素の Ruby + xterm.js で書かれている。組み込むなら Funicular のコンポーネントに書き直すか、`ref` で xterm.js を掴む形にする |

## 5. 次の一歩（統合版を作るなら）

1. **まず実機で経路を確認する。** Pico 2 W に現行ファームを焼き、
   `terminal.html` を開いて Ctrl-B → `/lib/picorubykaigi01.rb` をアップロード →
   `require 'picorubykaigi01'` が通るか
2. 通れば、その手順が**そのまま配布手順**になる（30 枚ぶん、ブラウザだけで済む）
3. 統合版はそのあと。UI の設計より先に、経路が生きていることを確かめる方が早い
