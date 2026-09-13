/*
 * POSIX port: host test target for the event bridge.
 *
 * There is no interrupt source here -- tests drive the bridge with
 * IRQ.simulate, which runs in ordinary VM context -- so the GCC
 * __atomic builtins are all this port needs.
 *
 * GPIO interrupts are simulated the same way: IRQ.simulate_gpio moves a
 * pin and IRQ.simulate_elapse moves a millisecond clock, and the handler
 * table, event queue and debounce below follow the rp2040 port. Only
 * edges are modelled; a level registration sees the edge into its
 * level.
 */

#include <stdint.h>
#include <stdbool.h>
#include <string.h>

#include "../../include/irq.h"

#if defined(PICORB_IRQ_EVENT_BRIDGE)

uint32_t
IRQ_hal_atomic_load_u32(const volatile uint32_t *p)
{
  return __atomic_load_n(p, __ATOMIC_SEQ_CST);
}

uint32_t
IRQ_hal_atomic_or_u32(volatile uint32_t *p, uint32_t bits)
{
  return __atomic_fetch_or(p, bits, __ATOMIC_SEQ_CST);
}

uint32_t
IRQ_hal_atomic_and_u32(volatile uint32_t *p, uint32_t mask)
{
  return __atomic_fetch_and(p, mask, __ATOMIC_SEQ_CST);
}

uint32_t
IRQ_hal_atomic_exchange_u32(volatile uint32_t *p, uint32_t v)
{
  return __atomic_exchange_n(p, v, __ATOMIC_SEQ_CST);
}

#endif /* PICORB_IRQ_EVENT_BRIDGE */

#define MAX_IRQ_HANDLERS 16
#define IRQ_EVENT_QUEUE_SIZE (1<<5)
#define MAX_PINS 64

#define EDGE_MASK (PICORB_GPIO_IRQ_EVENT_EDGE_FALL | PICORB_GPIO_IRQ_EVENT_EDGE_RISE)
#define LEVEL_MASK (PICORB_GPIO_IRQ_EVENT_LEVEL_LOW | PICORB_GPIO_IRQ_EVENT_LEVEL_HIGH)

typedef struct {
  int pin;
  uint32_t event_mask;
  bool enabled;
  uint32_t debounce_ms;
  irq_debounce_t debounce;
  bool window;
  uint64_t window_end_ms;
} irq_handler_t;

typedef struct {
  int irq_id;
  int event_type;
} irq_event_t;

static irq_handler_t irq_handlers[MAX_IRQ_HANDLERS];
static irq_event_t event_queue[IRQ_EVENT_QUEUE_SIZE];
static int queue_head = 0;
static int queue_tail = 0;
static uint8_t pin_level[MAX_PINS];
static uint64_t now_ms = 0;

static bool
valid_pin(int pin)
{
  return 0 <= pin && pin < MAX_PINS;
}

static void
queue_event(int slot, uint32_t events)
{
  int next_tail = (queue_tail + 1) & (IRQ_EVENT_QUEUE_SIZE - 1);
  if (next_tail != queue_head) {
    event_queue[queue_tail].irq_id = slot + 1;
    event_queue[queue_tail].event_type = (int)events;
    queue_tail = next_tail;
#if defined(PICORB_IRQ_EVENT_BRIDGE)
    IRQ_signal_from_isr(IRQ_SRC_GPIO, 1);
#endif
  }
}

static bool
debounced(const irq_handler_t *h)
{
  return h->debounce_ms > 0 && (h->event_mask & LEVEL_MASK) == 0;
}

static void
report_edge(int slot, int edge, bool window)
{
  irq_handler_t *h = &irq_handlers[slot];
  if (edge != 0 && (h->event_mask & (uint32_t)edge)) {
    queue_event(slot, (uint32_t)edge);
  }
  h->window = window;
  if (window) h->window_end_ms = now_ms + h->debounce_ms;
}

void
IRQ_posix_gpio_set(int pin, int level)
{
  if (!valid_pin(pin)) return;
  level = level ? 1 : 0;
  if (pin_level[pin] == level) return;
  pin_level[pin] = (uint8_t)level;
  uint32_t events = level ? PICORB_GPIO_IRQ_EVENT_EDGE_RISE : PICORB_GPIO_IRQ_EVENT_EDGE_FALL;
  if (!level) events |= PICORB_GPIO_IRQ_EVENT_LEVEL_LOW;
  else        events |= PICORB_GPIO_IRQ_EVENT_LEVEL_HIGH;

  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    irq_handler_t *h = &irq_handlers[i];
    if (!h->enabled || h->pin != pin) continue;
    if (debounced(h)) {
      bool window;
      int edge = IRQ_debounce_edge(&h->debounce, level, &window);
      if (edge != 0 || window) report_edge(i, edge, window);
      break;
    }
    if (events & h->event_mask) {
      queue_event(i, events & h->event_mask);
      break;
    }
  }
}

void
IRQ_posix_elapse_ms(uint32_t ms)
{
  while (0 < ms--) {
    now_ms++;
    for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
      irq_handler_t *h = &irq_handlers[i];
      if (!h->enabled || !h->window || now_ms < h->window_end_ms) continue;
      bool window;
      int edge = IRQ_debounce_settle(&h->debounce, pin_level[h->pin], &window);
      report_edge(i, edge, window);
    }
  }
}

int
IRQ_register_gpio(int pin, int event_type, uint32_t debounce_ms)
{
  if (!valid_pin(pin)) return -1;
  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    irq_handler_t *h = &irq_handlers[i];
    if (h->enabled) continue;
    h->pin = pin;
    h->event_mask = (uint32_t)event_type;
    h->debounce_ms = debounce_ms;
    h->window = false;
    IRQ_debounce_init(&h->debounce, pin_level[pin]);
    h->enabled = true;
    return i + 1;
  }
  return -1;
}

bool
IRQ_unregister_gpio(int irq_id)
{
  int slot = irq_id - 1;
  if (slot < 0 || slot >= MAX_IRQ_HANDLERS || !irq_handlers[slot].enabled) {
    return false;
  }
  memset(&irq_handlers[slot], 0, sizeof(irq_handler_t));
  return true;
}

bool
IRQ_peek_event(int *irq_id, int *event_type)
{
  if (queue_head == queue_tail) {
    return false;
  }
  *irq_id = event_queue[queue_head].irq_id;
  *event_type = event_queue[queue_head].event_type;
  queue_head = (queue_head + 1) & (IRQ_EVENT_QUEUE_SIZE - 1);
  return true;
}

void
IRQ_init(void)
{
  memset(irq_handlers, 0, sizeof(irq_handlers));
  memset(event_queue, 0, sizeof(event_queue));
  memset(pin_level, 1, sizeof(pin_level));   /* pulled up */
  queue_head = 0;
  queue_tail = 0;
  now_ms = 0;
}
