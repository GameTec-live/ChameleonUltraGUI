// Keep the small decoder helpers in one translation unit so the compiler can
// inline them and reuse the thread-local state address inside decoding loops.
// Apple builds already include these sources together in Classes/recovery.c.
#include "inputbuf.c"
#include "dictbuf.c"
#include "lzmadec.c"
#include "lzma2dec.c"
#include "rangedec.c"
#include "xzcrc.c"
#include "xzstream.c"
