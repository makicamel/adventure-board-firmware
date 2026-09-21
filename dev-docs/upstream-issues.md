# upstream で見つけた問題

この repo で踏んだ、[picoruby](https://github.com/picoruby/picoruby) 側の問題。
PR を送るための記録なので、基板に依存しない形で書く。
この repo のファイルに入れた変更そのものは [upstream-changes.md](upstream-changes.md) に載せる。

| # | gem | 内容 | 状態 |
|---|---|---|---|
| 1 | `picoruby-irq` | GPIO 割り込みのデバウンスが、タクトスイッチのチャタリングを取れない | rp2040 / posix は修正済み（PR 未送付）。esp32 は未修正 |
| 2 | `picoruby-irq` | シェルでスクリプトを流し終えても GPIO 割り込みの登録が残り、同じピンに登録し直すと届かない | 同じピンは「新しい登録で置き換える」に修正済み（PR 未送付）。別のピンの登録が溜まる件は未修正 |
| 3 | `picoruby-machine` | rp2040 ポートが `SLEEP_EN0 = 0` にしていて、タスクが全部待っているあいだ PWM / DMA / PIO / I2C / SPI / ADC が止まる | この repo では代入を消した（PR 未送付）。upstream には「止めてはいけない回路を残す」形で出すのがよさそう |
| 4 | `picoruby-littlefs` / `picoruby-psg` | core1（PSG）が動いているあいだにフラッシュへ書くと、core1 が二重フォールトでロックアップする | 修正済み（PR 未送付）。rp2040 ポートのみ |
| 5 | `picoruby-psg` | 音色 `PSG_TIMBRE_TRIANGLE` が三角波ではなく鋸波を出す（折り返しの式の誤り） | 修正済み（PR 未送付）。全ポート共通の `ports/common/psg.c` |
| 6 | `picoruby-psg` | core1 の音声処理がフラッシュ上で動き、debug ビルド（`-O0`）では DMA への積み直しに間に合わない。各音のあたまにノイズ | 修正済み（PR 未送付）。音声処理を RAM に置き、常に最適化する。rp2040 ポートのみ |

---

## 1. デバウンスがチャタリングを取れない

### 症状

6 個のタクトスイッチ（10kΩ プルアップ、押すと L）を `gpio.irq(..., debounce: 20)` で受けると、
1 回の押下が 2 回に数えられることがある。GPIO を直接読む poll では回数が合っていた。

### 原因

`ports/rp2040/irq.c` の判定（`ports/esp32/irq.c` も同じ）:

```c
if (time_diff < irq_handlers[i].debounce_ms &&
    events == irq_handlers[i].last_event_type) {
  continue;  /* Skip due to debounce */
}
```

「**前回と同じ種類**のイベントが `debounce_ms` 以内に来たら捨てる」。これではどちらの登録でも取れない。

- **`EDGE_FALL | EDGE_RISE`**: チャタリングは F と R が交互に来るので、前回と同じ種類にならず、何も捨てない
- **`EDGE_FALL` だけ**（README の「IRQ with Debouncing」の例と同じ）: 押したときの F R F は捨てられる。
  しかし**離したときの R F R の F** は、前回の F（押したとき）から押していた時間ぶん後なので捨てられず、
  もう 1 回の押下として届く。さらに R は登録されていないので、C 側からは見えてすらいない
- `events` に F と R の両方のビットが立って届いた場合は `==` の比較から漏れる

### 実機での再現（RP2350、ボタンの代わりに GPIO を自分で動かす）

GPIO16 を出力にし、同じピンに割り込みを登録して、次の波形を 3 回作った:
押す `F R F`（1ms 間隔）→ 100ms 押しっぱなし → 離す `R F R`（1ms 間隔）→ 100ms。
RP2350 は出力ピンでも入力バッファが生きているので、自分の出力で割り込みが立つ。

| 登録 | debounce | F | R | 理想 |
|---|---|---|---|---|
| F と R | 0 | 9 | 9 | |
| **F と R** | **20** | **9** | **9** | 3 / 3 |
| F だけ | 0 | 9 | – | |
| **F だけ** | **20** | **6** | – | 3 |
| **F だけ** | **50** | **6** | – | 3 |

スクリプト（`/home/devtest/irq_debounce.rb` として実行）:

```ruby
require 'gpio'
require 'irq'
pin = GPIO.new(16, GPIO::OUT)
pin.write(1)
IRQ.start

press = lambda do
  pin.write(0); sleep_ms 1; pin.write(1); sleep_ms 1; pin.write(0)
  sleep_ms 100
  pin.write(1); sleep_ms 1; pin.write(0); sleep_ms 1; pin.write(1)
  sleep_ms 100
end

run = lambda do |label, mask, debounce|
  log = []
  inst = pin.irq(mask, debounce: debounce) { |_p, type| log << type }
  3.times { press.call }
  sleep_ms 50
  inst.unregister
  # log の F(4) と R(8) を数えて表示
end
```

### 修正（この repo で実施）

「前回と同じ種類か」ではなく、**ピンのレベルを持つ**判定にした。ポートに依存しない状態機械を
`src/irq_debounce.c` に置き、ポートはピンのレベルとタイマーだけを受け持つ。

1. `debounce` を指定したエッジの登録は、登録された種類にかかわらず**両エッジを有効にする**
   （登録された種類は、報告するかどうかの絞り込みにだけ使う）
2. 最後に報告したレベルと違うエッジが来たら**すぐ報告**し、`debounce` ms の**静かな時間**を始める
3. 静かな時間の中のエッジはすべて捨てる
4. 静かな時間が終わったらピンを 1 回読む。報告したレベルと違っていれば（時間より短いタップ、
   その間に離された、など）その変化を報告し、もう一度静かな時間を始める

こうすると、1 回の押下は F 1 回、離しても余計な F は出ない。反応は遅れず、短いタップも落とさない。
`debounce: 0` とレベル割り込み（`LEVEL_LOW` / `LEVEL_HIGH`）の動作は変えていない。

- rp2040: 静かな時間の終わりは SDK の既定アラームプール（`add_alarm_in_ms`）。
  再延長はコールバックの戻り値で行い、`unregister` と `Machine.sleep` の suspend で取り消す
- posix: テスト用に `IRQ.simulate_gpio(pin, level)` と `IRQ.simulate_elapse(ms)` を足し、
  ハンドラ表・キュー・デバウンスを rp2040 と同じ形で模擬する。
  テストは `test/irq_gpio_debounce_test.rb`（上の実測と同じ波形を含む）
- esp32: **未修正**。レベル割り込みを切り替える作りで判定は同じ。ビルド環境が無いので手を入れていない。
  `IRQ_debounce_edge` / `IRQ_debounce_settle` と `esp_timer` のワンショットで同じ形にできるはず

修正後の実機（同じ波形・同じスクリプト）:

| 登録 | debounce | 修正前 F / R | 修正後 F / R |
|---|---|---|---|
| F と R | 20 | 9 / 9 | **3 / 3** |
| F だけ | 20 | 6 | **3** |
| F だけ | 50 | 6 | **3** |
| F だけ | 0 | 9 | 9（変えていない） |

あわせて実機で確認: 20ms の窓に 5ms のタップ ×3 → `FRFRFR`、25ms 押し / 25ms 間隔の
チャタリング付き押下 ×5 → `FFFFF`、窓が開いたまま `unregister` → 再登録で正常に届く。

---

## 2. スクリプトが終わっても GPIO 割り込みの登録が残る

### 症状

R2P2 のシェルで、ボタンの割り込みを登録するスクリプトを何度か流すと、
あとのスクリプトで**同じピンに登録した割り込みが届かない**。

### 実機で確認したこと（再起動せずに、同じスクリプトを 2 回流した）

空きピン GPIO15 を出力にして自分で 5 回往復させ、同じピンの割り込みで受けた:

```
1 回目: HANDLER before: [1, 2, ..., 9]   ← 前に流したスクリプトの登録が 9 個残っている
        registered:     [1, ..., 10]
        IRQ.start => true
        log=[4, 8, 4, 8, 4, 8, 4, 8, 4, 8]   ← 届く
2 回目: HANDLER before: [1, ..., 10]
        registered:     [1, ..., 11]
        IRQ.start => false                   ← 前のスクリプトの start が生きている
        log=[]                               ← 1 つも届かない
```

### 原因（コードから）

- シェルはスクリプトを**同じ VM の Sandbox** で動かす（`picoruby-shell/mrblib/job.rb`）。
  スクリプトが作ったタスクは、エラーで止まったときだけシェルが止め、正常に終わったときは
  バックグラウンドで動き続けられるように残す。割り込みの登録はタスクではないので、どちらの場合も外さない
- C 側のハンドラ表（16 個）を消すのは起動時の `IRQ_init()` だけ。Ruby 側の `IRQ::HANDLER` と
  `IRQ.start` の状態も残る
- `gpio_irq_callback` は、ピンが一致した**最初の**ハンドラに配って `break` する。
  そのため同じピンに登録し直すと、古い（もう誰も見ていない）ハンドラが先に取る
- 登録を続けると 16 個で `Failed to register GPIO IRQ` になるはず（未確認）

学習用の基板では、同じサンプルを直しては流すのが普通なので、実害が大きい。

### 未確認のこと

- 修正前の観測のうち 1 つは説明できていない。下ボタン（GPIO18）に割り込みを付けた計測で、
  **割り込みを使わない poll まで 0 回**になり、押しても LED が点かなかった。
  割り込みを付けない同じ計測では正常だった
- Ctrl-C で止めた場合に登録がどうなるか（エラー扱いならシェルがタスクは止めるが、登録は外さないはず）

### 仕様ではなくバグと考える理由

シェルがタスクを残すのは「シェルに戻ったあとも動き続ける処理」を許すためで、筋が通っている。
しかし割り込みの登録が残るのは、その意図とは別の話で、どう解釈しても困る:

- 直して流し直すと、**直す前のコードが反応し続け、直したコードは反応しない**
- 登録を持っていた変数は前のスクリプトと一緒に消えているので、**外す手段が無い**（再起動しかない）
- 「ボタンで LED 反転」を 2 回流した利用者が期待するのは「2 回目に置き換わる」こと

### 修正（この repo で実施）: 同じピンは新しい登録で置き換える

`mrblib/irq.rb` の `IRQ.register` で、GPIO を登録する前に、同じピンの既存の登録を外す。
Ruby 側で行うのでポート（rp2040 / esp32 / posix）に依存せず、`IRQ::HANDLER` にも古い登録が残らない。

- 1 つのピンに登録は 1 つ。押下と離しを別々に受けたいときは、1 つの登録で両エッジを受けて中で分ける
- 置き換えられた登録の `IRQInstance#unregister` は `false` を返す。C 側の登録番号は使い回されるので、
  番号がまだ自分を指しているときだけ外す（でないと、同じ番号を得た別の登録を外してしまう）。
  2 回目の `unregister` も、例外ではなく `false` を返すようになった
- テストは `test/irq_gpio_registration_test.rb`。置き換えの 1 行を外すと 6 件中 4 件が落ちることを確認済み

実機（GPIO16 に登録して解除せずに終わるスクリプトを、再起動せず 3 回続けて流した）:

```
handlers before=0 after=1 falls=3
handlers before=1 after=1 falls=3
handlers before=1 after=1 falls=3
```

修正前は 2 回目から 0 回だった。

### 残っていること

- **別のピンを使うスクリプトを次々流すと、使われない登録が溜まる**（16 個で登録に失敗するはず）。
  ジョブと登録を結び付ける必要があり、シェルの設計に関わるので upstream と相談したい
- 解除より前に割り込みが起きても、Ruby 側に配られる前に解除すると、そのイベントは届かない
  （元からの動作。実機では配られるまで 5〜20ms かかることがあった）

---

## 3. CPU が眠ると PWM などの周辺回路が止まる（rp2040 ポート）

### 症状

`PWM.new(pin, frequency: 150_000, duty: 50)` のあと `sleep_ms` で待つと、ピンには連続した PWM が出ない。
RP2350 で測ると、1ms ごとに約 27µs（4 周期）だけ進み、残りは止まった瞬間の High / Low のまま。
RC フィルタとアンプをつなぐと大きな雑音になる。440Hz の矩形波のような遅い PWM も同じように乱れる。
タスクが空ループで回っているあいだは正常に出る。

### 原因

`mrbgems/picoruby-machine/ports/rp2040/machine.c` の `picorb_hal_init`:

```c
clocks_hw->sleep_en0 = 0;
clocks_hw->sleep_en1 = /* TIMER, TICKS, USBCTRL, UART0/1 だけ */;
```

`SLEEP_EN0/1` は「コアが全部 WFI / WFE で眠っているあいだ、どの回路にクロックを配るか」。
RP2350 では PWM・DMA・PIO0〜2・I2C0/1・ADC が `SLEEP_EN0`、SPI0/1 が `SLEEP_EN1` にある（RP2040 は SPI も `SLEEP_EN0`）。
`picorb_hal_idle_cpu` は `__wfi` なので、走れるタスクが無い時間はこれらが全部止まる。
core1 を使う gem（`picoruby-psg`）でも、両方のコアが同時に眠った瞬間は止まる。

### PicoRuby 抜きでの再現

pico-sdk だけのファーム（この repo の `dev-docs/audio-quality/c-pwm-test/`）。150kHz 50% の PWM を出して 1ms の
repeating timer + `__wfi` で待つ。

| `SLEEP_EN` | PWM のピン |
|---|---|
| リセット値（全 ON） | 連続した 150kHz |
| 上の 2 行と同じ値 | 3.3V か 0V に 1〜2ms ずつ止まる（150kHz は出ない） |

### 修正

- この repo: 代入を消した（全 ON）。学習用の基板なので、漏れが無いことを優先
- upstream 向けの案: 節電の意図を保つなら、`SLEEP_EN0` に PWM / DMA / PIO0〜2 / I2C0/1 / ADC（SYS と ADC）、
  SPI0/1（RP2350 は `SLEEP_EN1`）を残す。ほかにも CPU を待たずに動く回路（TRNG、HSTX など）が要るかは要検討

---

## 4. PSG が動いているあいだにファイルを書くと core1 が固まる（rp2040 ポート）

### 症状

`PSG::Driver.new(:pwm, ...)` を一度でも呼んだあと（音が鳴っていなくてもよい）、シェルからファイルを書く
（`dfucli` / PicoModem の転送、`cp` など）と、シェルが応答しなくなる。SWD でつなぐと openocd が
`[rp2350.dap.core1] clearing lockup after double fault` を出す。RP2350（Pico 2 相当）で確認。

### 原因

- `picoruby-littlefs/ports/rp2040/flash_hal.c` は `save_and_disable_interrupts()` だけで
  `flash_range_erase` / `flash_range_program` を呼ぶ。止まるのは呼んだ側（core0）の割り込みだけ
- `picoruby-psg/ports/rp2040/psg_port.c` の `psg_core1_main` は core1 でフラッシュ上（XIP）のコードを休まず実行し、
  1kHz のタイマー割り込みもフラッシュ上
- 消去・書き込みのあいだ XIP は読めないので、core1 は次の命令が読めずフォールトし、ハンドラも読めず二重フォールトになる

### 修正（この repo で実施）

- `flash_hal.c`: core1 がロックアウトの対象になっていれば（`multicore_lockout_victim_is_initialized(1)`）、
  `multicore_lockout_start_blocking()` / `_end_blocking()` で挟む
- `psg_port.c`: core1 の入口で `multicore_lockout_victim_init()`。core0 → core1 の `CMD_CLEANUP` は FIFO をやめて
  `volatile bool` に（SDK のロックアウトハンドラは core1 の FIFO 受信を割り込みで取り、ロックアウト要求以外の値を捨てる）

### 確認（実機、UART のシェルから）

| 手順 | 修正前 | 修正後 |
|---|---|---|
| MML をループ再生したまま 8KB のファイルを 3 回書く | 1 回目で core1 ロックアップ、シェル無応答 | 3 回とも成功、再生は続く |
| 「`melody.rb` → 8KB 書く」を 5 往復 | — | 全部成功 |
| `Driver#deinit` → `Driver.new` → `deinit`、そのあと書き込みと `rm` | — | 成功（フラグでの停止が届いている） |

### 残っていること

- ループ再生の `Player` タスクが生きたまま、別のスクリプトで `Driver#deinit` し、そのあと `rm` を続けたら
  core0 が応答しなくなったことが 1 回ある（core1 のロックアップは無し）。再生中の音源を下から外す不自然な手順で、
  再現確認も原因調査もしていない
- 書き込み中は core1 が止まるので音が途切れる

---

## 5. 三角波の音色が鋸波になっている

### 症状

`set_timbre` で三角波（1）を選んでも、出てくる波形は 0 → 最大へ上がって落ちる鋸波。RP2350 の PWM 出力を
RC フィルタのあとでオシロで測ると、437Hz の鋸波で、倍音は偶数・奇数とも 1/n で並んでいた
（509 / 250 / 164 / 121 / 95 mV …）。三角波なら奇数次だけが 1/n² で並ぶ。

### 原因

`ports/common/psg.c` の `PSG_calc_sample`:

```c
uint32_t idx = psg.tone_phase[tr] >> 19;  // 0..8191
idx ^= (idx >> 12);                       // ← (idx >> 12) は 0 か 1。最下位ビットが反転するだけ
uint32_t tri = idx & 0x1FFF;
tone_amp = tri >> 1;                      // 0..4095 の上り坂 = 鋸波
```

コメントは「MSB で XOR して鋸波を三角波に折り返す」だが、折り返すには上位ビットが立っているとき全ビットを反転する必要がある。

### 修正（この repo で実施）

```c
if (idx & 0x1000) idx ^= 0x1FFF;          // 0..4095 のあと 4095..0
tone_amp = idx;
```

三角波は倍音が少ないので、音量は同じでも聞こえ方は前より丸く、小さく感じるはず。

## 6. core1 の音声処理が DMA への積み直しに間に合わない（rp2040 ポート、debug ビルド）

### 症状

PWM + DMA の出力（`PICORUBY_PSG_PWM_DMA=ON`）で MML を鳴らすと、各音のあたまに短いノイズが入る。debug ビルドで確認。
出力を ADC で録ると、音符の境目の前後 約 70ms に、出力が DMA 1 かたまりぶん（またはその一部）だけ別の内容になる区間が数回入る。

この repo では DMA を 2 チャンネルの交互連鎖にしてある（[upstream-changes.md](upstream-changes.md) の 11）ので「0V に落ちる区間」として見えた。
upstream の 1 チャンネル版では、同じ遅れは「最後の値のまま止まる区間」になるはずで、耳には同じくノイズに聞こえる（キャリア変更前から同じ症状があった）。

### 原因

- core1 のループ（`PSG_render_block` → `write_buffer`）と 1ms ティックの処理は、すべてフラッシュ上にある
- debug ビルドは `-O0`。RP2350・150MHz で、64 サンプルのレンダリングに平均 1.06ms、DMA バッファへの詰め込みに平均 0.56ms（最大 2.0ms）。
  締め切りは 2.88ms
- 2 つのコアは同じ QSPI フラッシュから命令を取る。core0 が VM を回している時間帯は core1 の取り込みが待たされ、所要時間が数倍に伸びる
  （同じ `-O2` のコードで、フラッシュ上 557µs → RAM 上 172µs）

測定値（曲を鳴らしている 10 秒間、RP2350）:

| 条件 | レンダリング 平均 / 最大 | 詰め込み 平均 / 最大 | 締め切り越え |
|---|---|---|---|
| `-O0`、フラッシュ上（debug ビルドそのまま） | 1060 / 4517 µs | 564 / 1989 µs | 166 回 |
| 音声処理だけ `-O2`、フラッシュ上（prod 相当） | 557 / 2307 µs | 222 / 926 µs | 0 回 |
| `-O2` + RAM | 172 / 327 µs | 62 / 218 µs | 0 回 |

prod ビルド（`-O2`）では締め切りは越えなかったが、最大値は 1 かたまりの 8 割に達していて、余裕は小さい。

### 修正（この repo で実施）

core1 がかたまりごと・ティックごとに通る関数と表に、`optimize("O2")` と `.time_critical` セクションの属性を付けた（`PSG_HOT`）。
RAM は約 3.2KB。ADC の記録で、2.6 秒あたり 71 個あった異常区間が 0 個になった。

### 残っていること

- SDK の `alarm_pool_irq_handler`（1ms ごと）はフラッシュ上のまま
- core1 が数かたまりぶん止められる場合（フラッシュ書き込み中のロックアウト）の出力は未対処
- RP2040 では未測定（クロックが遅く、フラッシュの取り込みも遅いので、prod でも越えている可能性がある）
