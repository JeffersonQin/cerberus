#ifndef _STDARG_H_
#define _STDARG_H_

// TODO
typedef int va_list;

#define va_arg(ap, type)    __cerb_va_arg(ap, type)
#define va_copy(dest, src)  (dest = __cerb_va_copy(dest, src))
#define va_end(ap)          __cerb_va_end(ap)
#define va_start(ap, param) (ap = __cerb_va_start(ap, param))

#endif
