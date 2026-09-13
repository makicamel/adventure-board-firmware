/*
 * Debounced edge detection, shared by the ports.
 *
 * A contact bounces on the way down and again on the way up, so the
 * filter has to see both edges whatever the handler asked for: a
 * handler registered for EDGE_FALL alone still gets a burst of falls
 * when the button is released. Comparing each event with the previous
 * one of the same kind cannot tell those apart from a new press.
 *
 * Instead the filter keeps the level it last reported. The first edge
 * that changes it is reported at once and opens a quiet window; every
 * edge inside the window is ignored. When the window closes the port
 * samples the pin once. If the pin settled somewhere other than the
 * reported level -- a tap shorter than the window, or a release that
 * happened during it -- that change is reported too, and a new window
 * opens. Nothing is reported twice and the last level is never lost.
 *
 * Pure state: the port supplies the pin level and runs the timer. The
 * functions are called from interrupt context and do not block.
 */

#include "../include/irq.h"

void
IRQ_debounce_init(irq_debounce_t *d, int level)
{
  d->level = level ? 1 : 0;
  d->quiet = false;
}

static int
report(irq_debounce_t *d, int level, bool *open_window)
{
  level = level ? 1 : 0;
  if (level == d->level) {
    *open_window = false;
    return 0;
  }
  d->level = (uint8_t)level;
  d->quiet = true;
  *open_window = true;
  return level ? PICORB_GPIO_IRQ_EVENT_EDGE_RISE : PICORB_GPIO_IRQ_EVENT_EDGE_FALL;
}

int
IRQ_debounce_edge(irq_debounce_t *d, int level, bool *open_window)
{
  if (d->quiet) {
    *open_window = false;
    return 0;
  }
  return report(d, level, open_window);
}

int
IRQ_debounce_settle(irq_debounce_t *d, int level, bool *open_window)
{
  d->quiet = false;
  return report(d, level, open_window);
}
