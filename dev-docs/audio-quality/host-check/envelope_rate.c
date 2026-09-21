/*
 * Do the three channels' envelopes run at the same rate? (upstream-issues.md, 7)
 * The PSG renderer is plain C, so this builds on the host with nothing but
 * the two critical-section stubs below.
 *
 *   sh dev-docs/audio-quality/host-check/envelope_rate.sh
 *
 * Expected: the same number of cycles on every channel.
 */
#include <stdio.h>
#include "../../../mrbgems/picoruby-psg/include/psg.h"

extern psg_t psg;
psg_cs_token_t PSG_enter_critical(void) { return 0; }
void PSG_exit_critical(psg_cs_token_t t) { (void)t; }

int
main(void)
{
  enum { PERIOD = 20, SECONDS = 2 };
  uint32_t buf[1];
  int cycles[3] = {0, 0, 0};
  uint8_t last[3] = {15, 15, 15};

  PSG_write_reg(11, PERIOD);
  PSG_write_reg(12, 0);
  for (int tr = 0; tr < 3; tr++) PSG_write_reg(8 + tr, 0x10);   /* volume from the envelope */
  PSG_write_reg(13, 0x08);                                      /* repeating decay */

  for (int n = 0; n < SAMPLE_RATE * SECONDS; n++) {
    PSG_render_block(buf, 1);   /* one sample at a time, to see every step */
    for (int tr = 0; tr < 3; tr++) {
      if (last[tr] < psg.env_level[tr]) cycles[tr]++;           /* wrapped from 0 back to 15 */
      last[tr] = psg.env_level[tr];
    }
  }
  printf("envelope cycles in %d s, period %d: A=%d B=%d C=%d (ideal %d)\n",
         SECONDS, PERIOD, cycles[0], cycles[1], cycles[2], SAMPLE_RATE * SECONDS / (PERIOD * 16));
  return (cycles[0] == cycles[1] && cycles[1] == cycles[2]) ? 0 : 1;
}
