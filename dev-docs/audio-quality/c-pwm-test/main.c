/*
 * PicoRuby を通さずに、C だけで音声ピンに PWM を出す（report.md A-9）。
 *
 * A ボタン（SW6 = GPIO22）で段階を進める。段階に入るとき、緑 LED（GPIO16）が
 * 段階の番号の回数だけ点滅する（そのあいだアンプは止めてある）。5 のあとは 1 に戻る。
 *
 *   1  アンプ ON、GPIO10 = 0V                         基準の無音
 *   2  150kHz 50%、CPU は空ループ                      無音のはず
 *   3  150kHz 50%、CPU は __wfi で眠る（SDK の既定）   無音のはず
 *   4  150kHz 50%、CPU は __wfi で眠る + R2P2 と同じ   R2P2 と同じノイズが出るはず
 *      sleep_en0 = 0（眠っているあいだ PWM のクロックを止める）
 *   5  150kHz のまま、デューティを 880Hz の正弦波で    きれいな「ラ」が、小 → 中 → 大と鳴るはず
 *      揺らす。振れ幅は ±5% → ±10% → ±20% を 1.5 秒
 *      ずつ繰り返す（±20% で PSG の 1 声より少し小さい
 *      くらい）。CPU は空ループ。
 *      最初は 440Hz ±5% だけにしていて、聞こえなかった
 *
 * 2・3・5 が静か／きれいなら、基板（フィルタ・アンプ・配線）は健全。
 * 4 だけノイズなら、原因は picoruby-machine の sleep_en0 = 0 で確定。
 */
#include <math.h>
#include "pico/stdlib.h"
#include "hardware/clocks.h"
#include "hardware/pwm.h"
#include "hardware/sync.h"

#define PIN_AUDIO 10
#define PIN_LED   16
#define PIN_BTN_A 22
#define PIN_AMP   23

#define WRAP  999   /* 150MHz / 1000 = 150kHz */
#define HALF  500

static bool
tick_cb(repeating_timer_t *t)
{
  (void)t;
  return true;      /* 起こすだけ */
}

/* 押して離したら true。呼ぶたびに 1 回読むだけなので、どの待ち方からも呼べる */
static bool
button_clicked(void)
{
  static bool was_down = false;
  static uint64_t changed_at = 0;
  bool down = !gpio_get(PIN_BTN_A);
  uint64_t now = time_us_64();
  if (down != was_down && 30000 < now - changed_at) {
    was_down = down;
    changed_at = now;
    return !down;
  }
  return false;
}

static void
announce(int n)
{
  gpio_put(PIN_AMP, 0);
  pwm_set_gpio_level(PIN_AUDIO, 0);
  busy_wait_ms(400);
  for (int i = 0; i < n; i++) {
    gpio_put(PIN_LED, 1);
    busy_wait_ms(150);
    gpio_put(PIN_LED, 0);
    busy_wait_ms(200);
  }
  busy_wait_ms(300);
}

int
main(void)
{
  gpio_init(PIN_LED);   gpio_set_dir(PIN_LED, GPIO_OUT);
  gpio_init(PIN_AMP);   gpio_set_dir(PIN_AMP, GPIO_OUT);
  gpio_init(PIN_BTN_A); gpio_set_dir(PIN_BTN_A, GPIO_IN); gpio_pull_up(PIN_BTN_A);

  gpio_set_function(PIN_AUDIO, GPIO_FUNC_PWM);
  uint slice = pwm_gpio_to_slice_num(PIN_AUDIO);
  pwm_set_clkdiv_int_frac4(slice, 1, 0);
  pwm_set_wrap(slice, WRAP);
  pwm_set_gpio_level(PIN_AUDIO, 0);
  pwm_set_enabled(slice, true);

  /* R2P2 と同じ 1ms の割り込み。眠る段階ではこれで起きる */
  static repeating_timer_t timer;
  add_repeating_timer_us(-1000, tick_cb, NULL, &timer);

  const uint32_t en0_default = clocks_hw->sleep_en0;
  const uint32_t en1_default = clocks_hw->sleep_en1;

  int stage = 1;
  for (;;) {
    announce(stage);
    pwm_set_gpio_level(PIN_AUDIO, stage == 1 ? 0 : HALF);
    busy_wait_ms(200);
    gpio_put(PIN_AMP, 1);

    if (stage == 4) {
      /* mrbgems/picoruby-machine/ports/rp2040/machine.c の picorb_hal_init と同じ */
      clocks_hw->sleep_en0 = 0;
      clocks_hw->sleep_en1 =
        CLOCKS_SLEEP_EN1_CLK_SYS_TIMER0_BITS
        | CLOCKS_SLEEP_EN1_CLK_SYS_TIMER1_BITS
        | CLOCKS_SLEEP_EN1_CLK_REF_TICKS_BITS
        | CLOCKS_SLEEP_EN1_CLK_SYS_TICKS_BITS
        | CLOCKS_SLEEP_EN1_CLK_SYS_USBCTRL_BITS
        | CLOCKS_SLEEP_EN1_CLK_USB_BITS
        | CLOCKS_SLEEP_EN1_CLK_SYS_UART0_BITS
        | CLOCKS_SLEEP_EN1_CLK_PERI_UART0_BITS
        | CLOCKS_SLEEP_EN1_CLK_SYS_UART1_BITS
        | CLOCKS_SLEEP_EN1_CLK_PERI_UART1_BITS;
    }

    while (!button_clicked()) {
      if (stage == 3 || stage == 4) {
        __wfi();
      } else if (stage == 5) {
        static const float depth[] = { 50.0f, 100.0f, 200.0f };
        uint64_t now = time_us_64();
        float t = (float)(now % 1000000u) * 1e-6f;            /* 880Hz は 1 秒でちょうど閉じる */
        float a = depth[(now / 1500000u) % 3];
        pwm_set_gpio_level(PIN_AUDIO, (uint16_t)(HALF + a * sinf(6.2831853f * 880.0f * t)));
      }
    }

    clocks_hw->sleep_en0 = en0_default;
    clocks_hw->sleep_en1 = en1_default;
    stage = stage % 5 + 1;
  }
}
