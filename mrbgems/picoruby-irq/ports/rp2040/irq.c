#include <stdint.h>
#include <stdbool.h>
#include <string.h>
#include "hardware/gpio.h"
#include "hardware/irq.h"
#include "pico/time.h"
#include "hardware/sync.h"

#include "../../include/irq.h"

#define MAX_IRQ_HANDLERS 16
#define IRQ_EVENT_QUEUE_SIZE (1<<5)

typedef struct {
  int pin;
  uint32_t event_mask;     /* what the handler asked for */
  uint32_t enabled_mask;   /* what is enabled on the pin */
  bool enabled;
  uint32_t debounce_ms;
  uint32_t last_event_time;
  uint32_t last_event_type;
  irq_debounce_t debounce;
  alarm_id_t alarm;        /* 0 when no window is open */
} mrb_irq_handler_t;

typedef struct {
  int irq_id;
  int event_type;
} irq_event_t;

static mrb_irq_handler_t irq_handlers[MAX_IRQ_HANDLERS];
static irq_event_t event_queue[IRQ_EVENT_QUEUE_SIZE];
static int queue_head = 0;
static int queue_tail = 0;
static int next_irq_id = 1;

#define EDGE_MASK (GPIO_IRQ_EDGE_FALL | GPIO_IRQ_EDGE_RISE)
#define LEVEL_MASK (GPIO_IRQ_LEVEL_LOW | GPIO_IRQ_LEVEL_HIGH)

static void
queue_event(int slot, uint32_t events)
{
  int next_tail = (queue_tail + 1) & (IRQ_EVENT_QUEUE_SIZE - 1);
  if (next_tail != queue_head) {  /* Queue not full */
    event_queue[queue_tail].irq_id = slot + 1;  /* IRQ ID is 1-based */
    event_queue[queue_tail].event_type = events;
    queue_tail = next_tail;
#if defined(PICORB_IRQ_EVENT_BRIDGE)
    /* Publish after the event is visible in the queue, so a task
       woken by the token always finds it. Dropped events (queue
       full) do not signal: there is nothing new to drain. */
    IRQ_signal_from_isr(IRQ_SRC_GPIO, 1);
#endif
  }
}

/* The edge-debounced path: see src/irq_debounce.c. Such a handler
   always has both edges enabled; event_mask only filters what is
   reported. */
static bool
debounced(const mrb_irq_handler_t *h)
{
  return h->debounce_ms > 0 && (h->event_mask & LEVEL_MASK) == 0;
}

static void
report_edge(int slot, int edge)
{
  if (edge == 0) return;
  uint32_t events = (edge == PICORB_GPIO_IRQ_EVENT_EDGE_FALL) ? GPIO_IRQ_EDGE_FALL : GPIO_IRQ_EDGE_RISE;
  if (irq_handlers[slot].event_mask & events) {
    queue_event(slot, events);
  }
}

static int64_t
window_closed(alarm_id_t id, void *user_data)
{
  int slot = (int)(intptr_t)user_data;
  mrb_irq_handler_t *h = &irq_handlers[slot];
  if (!h->enabled || h->alarm != id) return 0;
  bool again;
  int edge = IRQ_debounce_settle(&h->debounce, gpio_get(h->pin), &again);
  report_edge(slot, edge);
  if (again) {
    /* The settled level was a change of its own; it may bounce too.
       A negative return reschedules this same alarm from now. */
    return -(int64_t)h->debounce_ms * 1000;
  }
  h->alarm = 0;
  return 0;
}

static void
open_window(int slot)
{
  mrb_irq_handler_t *h = &irq_handlers[slot];
  alarm_id_t id = add_alarm_in_ms(h->debounce_ms, window_closed, (void *)(intptr_t)slot, true);
  if (id > 0) {
    h->alarm = id;
  } else {
    /* No timer to close the window: leave it open rather than go
       deaf to the pin. Bounces get through; presses are not lost. */
    h->alarm = 0;
    h->debounce.quiet = false;
  }
}

static void
gpio_irq_callback(uint gpio, uint32_t events)
{
  uint32_t current_time = time_us_32() / 1000;  /* Convert to milliseconds */

  /* Find handler for this GPIO pin and matching event */
  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    mrb_irq_handler_t *h = &irq_handlers[i];
    if (h->enabled && h->pin == gpio && (events & h->enabled_mask)) {
      if (debounced(h)) {
        if ((events & EDGE_MASK) == 0) break;
        /* One edge says where the pin went, even if it has already
           bounced back by now. Both at once say nothing; read it. */
        int level;
        uint32_t edges = events & EDGE_MASK;
        if (edges == GPIO_IRQ_EDGE_FALL) {
          level = 0;
        } else if (edges == GPIO_IRQ_EDGE_RISE) {
          level = 1;
        } else {
          level = gpio_get(gpio);
        }
        bool window;
        int edge = IRQ_debounce_edge(&h->debounce, level, &window);
        report_edge(i, edge);
        if (window) open_window(i);
        break;
      }

      /* Level interrupts keep the old rule: the same kind again within
         the period is dropped. */
      if (h->debounce_ms > 0) {
        uint32_t time_diff = (current_time - h->last_event_time) & 0xFFFFFFFF;
        if (time_diff < h->debounce_ms &&
            events == h->last_event_type) {
          continue;  /* Skip due to debounce */
        }
      }

      /* Update event history */
      h->last_event_time = current_time;
      h->last_event_type = events;

      queue_event(i, events);
      break;
    }
  }
}

int
IRQ_register_gpio(int pin, int event_type, uint32_t debounce_ms)
{
  /* Find free slot */
  int slot = -1;
  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    if (!irq_handlers[i].enabled) {
      slot = i;
      break;
    }
  }

  if (slot < 0) {
    return -1;  /* No free slots */
  }

  /* Convert event_type to GPIO event mask */
  uint32_t event_mask = 0;
  if (event_type & PICORB_GPIO_IRQ_EVENT_LEVEL_LOW)  event_mask |= GPIO_IRQ_LEVEL_LOW;   /* LEVEL_LOW = 1 */
  if (event_type & PICORB_GPIO_IRQ_EVENT_LEVEL_HIGH) event_mask |= GPIO_IRQ_LEVEL_HIGH;  /* LEVEL_HIGH = 2 */
  if (event_type & PICORB_GPIO_IRQ_EVENT_EDGE_FALL)  event_mask |= GPIO_IRQ_EDGE_FALL;   /* EDGE_FALL = 4 */
  if (event_type & PICORB_GPIO_IRQ_EVENT_EDGE_RISE)  event_mask |= GPIO_IRQ_EDGE_RISE;   /* EDGE_RISE = 8 */

  /* Store handler info before enabling, so the first interrupt finds it */
  mrb_irq_handler_t *h = &irq_handlers[slot];
  h->pin = pin;
  h->event_mask = event_mask;
  h->debounce_ms = debounce_ms;
  h->last_event_time = 0;
  h->last_event_type = 0;
  h->alarm = 0;
  h->enabled_mask = event_mask;
  if (debounced(h)) {
    h->enabled_mask = EDGE_MASK;
    IRQ_debounce_init(&h->debounce, gpio_get(pin));
  }
  h->enabled = true;

  /* Configure GPIO IRQ */
  gpio_set_irq_enabled_with_callback(pin, h->enabled_mask, true, &gpio_irq_callback);

  return slot + 1;  /* Return 1-based ID */
}

bool
IRQ_unregister_gpio(int irq_id)
{
  int slot = irq_id - 1;  /* Convert to 0-based index */

  if (slot < 0 || slot >= MAX_IRQ_HANDLERS || !irq_handlers[slot].enabled) {
    return false;  /* Invalid ID or not registered */
  }

  bool prev_state = irq_handlers[slot].enabled;

  /* Disable GPIO IRQ */
  gpio_set_irq_enabled(irq_handlers[slot].pin, irq_handlers[slot].enabled_mask, false);
  if (irq_handlers[slot].alarm > 0) {
    cancel_alarm(irq_handlers[slot].alarm);
  }

  /* Clear handler */
  memset(&irq_handlers[slot], 0, sizeof(mrb_irq_handler_t));

  return prev_state;
}

bool
IRQ_peek_event(int *irq_id, int *event_type)
{
  if (queue_head == queue_tail) {
    return false;  /* Queue empty */
  }

  *irq_id = event_queue[queue_head].irq_id;
  *event_type = event_queue[queue_head].event_type;

  queue_head = (queue_head + 1) & (IRQ_EVENT_QUEUE_SIZE - 1);

  return true;
}

void
IRQ_init(void)
{
  /* Initialize data structures */
  memset(irq_handlers, 0, sizeof(irq_handlers));
  memset(event_queue, 0, sizeof(event_queue));
  queue_head = 0;
  queue_tail = 0;
  next_irq_id = 1;
}

/* Machine.sleep with a GPIO wake source hands the shared IO_BANK0 IRQ
 * and the per-core GPIO callback to pico_low_power for the duration.
 * These hooks, called by picoruby-machine's rp2040 port (declared
 * weak there, so a build without this gem still links), take this
 * gem's registrations offline and rebuild them afterwards. The SDK
 * NULLs the callback and disables the wake pin's events on its way
 * out, so resume must re-register both. gpio_set_irq_enabled() acks
 * stale latched events on enable: EDGE events that fired during the
 * sleep are deliberately discarded, while a LEVEL condition still
 * asserted at resume fires again immediately -- level is condition,
 * not history. */

void
picorb_irq_gpio_suspend(void)
{
  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    if (irq_handlers[i].enabled) {
      gpio_set_irq_enabled(irq_handlers[i].pin, irq_handlers[i].enabled_mask, false);
      if (irq_handlers[i].alarm > 0) {
        cancel_alarm(irq_handlers[i].alarm);
        irq_handlers[i].alarm = 0;
      }
    }
  }
}

void
picorb_irq_gpio_resume(void)
{
  for (int i = 0; i < MAX_IRQ_HANDLERS; i++) {
    if (irq_handlers[i].enabled) {
      /* Where the pin is now is where it is; what happened during the
         sleep is discarded like the edges themselves. */
      if (debounced(&irq_handlers[i])) {
        IRQ_debounce_init(&irq_handlers[i].debounce, gpio_get(irq_handlers[i].pin));
      }
      gpio_set_irq_enabled_with_callback(irq_handlers[i].pin,
          irq_handlers[i].enabled_mask, true, &gpio_irq_callback);
    }
  }
}

#if defined(PICORB_IRQ_EVENT_BRIDGE)

/*
 * Atomic primitives for the event bridge.
 *
 * Cortex-M0+ has no LDREX/STREX, so C11 atomics would lower to
 * libatomic calls; a short interrupt-save critical section is both
 * cheaper and valid in ISR and task context alike. This masks
 * interrupts on the CURRENT core only: producers (ISRs) and the VM
 * are expected to live on core 0, as PicoRuby runs today.
 */

uint32_t
IRQ_hal_atomic_load_u32(const volatile uint32_t *p)
{
  uint32_t v;
  uint32_t state = save_and_disable_interrupts();
  v = *p;
  restore_interrupts(state);
  return v;
}

uint32_t
IRQ_hal_atomic_or_u32(volatile uint32_t *p, uint32_t bits)
{
  uint32_t old;
  uint32_t state = save_and_disable_interrupts();
  old = *p;
  *p = old | bits;
  restore_interrupts(state);
  return old;
}

uint32_t
IRQ_hal_atomic_and_u32(volatile uint32_t *p, uint32_t mask)
{
  uint32_t old;
  uint32_t state = save_and_disable_interrupts();
  old = *p;
  *p = old & mask;
  restore_interrupts(state);
  return old;
}

uint32_t
IRQ_hal_atomic_exchange_u32(volatile uint32_t *p, uint32_t v)
{
  uint32_t old;
  uint32_t state = save_and_disable_interrupts();
  old = *p;
  *p = v;
  restore_interrupts(state);
  return old;
}

#endif /* PICORB_IRQ_EVENT_BRIDGE */
