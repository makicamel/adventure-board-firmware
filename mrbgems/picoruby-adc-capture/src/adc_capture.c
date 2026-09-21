/*
 * ADCCapture.start(pin, rate_hz)  -> true / false
 * ADCCapture.stop                 -> index of the oldest sample in the ring
 * ADCCapture.addr                 -> where the ring is, for a debugger
 * ADCCapture.size                 -> 32768
 *
 * The samples are not handed to Ruby. They are read out of RAM over SWD:
 * they would not fit the heap beside a program, and the point is
 * to look at them on a PC anyway.
 */
#include "../include/adc_capture.h"

#if defined(PICORB_VM_MRUBY)

#include <mruby.h>
#include <mruby/presym.h>

static mrb_value
mrb_s_start(mrb_state *mrb, mrb_value klass)
{
  mrb_int pin, rate;
  mrb_get_args(mrb, "ii", &pin, &rate);
  return mrb_bool_value(ADC_capture_start((uint8_t)pin, (uint32_t)rate));
}

static mrb_value
mrb_s_stop(mrb_state *mrb, mrb_value klass)
{
  return mrb_int_value(mrb, (mrb_int)ADC_capture_stop());
}

static mrb_value
mrb_s_addr(mrb_state *mrb, mrb_value klass)
{
  return mrb_int_value(mrb, (mrb_int)ADC_capture_addr());
}

static mrb_value
mrb_s_size(mrb_state *mrb, mrb_value klass)
{
  return mrb_int_value(mrb, (mrb_int)ADC_CAPTURE_SIZE);
}

void
mrb_picoruby_adc_capture_gem_init(mrb_state *mrb)
{
  struct RClass *module_ADCCapture = mrb_define_module_id(mrb, MRB_SYM(ADCCapture));
  mrb_define_class_method_id(mrb, module_ADCCapture, MRB_SYM(start), mrb_s_start, MRB_ARGS_REQ(2));
  mrb_define_class_method_id(mrb, module_ADCCapture, MRB_SYM(stop), mrb_s_stop, MRB_ARGS_NONE());
  mrb_define_class_method_id(mrb, module_ADCCapture, MRB_SYM(addr), mrb_s_addr, MRB_ARGS_NONE());
  mrb_define_class_method_id(mrb, module_ADCCapture, MRB_SYM(size), mrb_s_size, MRB_ARGS_NONE());
}

void
mrb_picoruby_adc_capture_gem_final(mrb_state *mrb)
{
  (void)mrb;
}

#endif
