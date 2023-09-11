

/*@
lemma uint_ctz_uf_repr(integer x)
  requires
    good<unsigned int>(x)
  ensures
    0 <= bw_ctz_uf(x) && bw_ctz_uf(x) <= 64
@*/

int
f (unsigned int x)
{
  unsigned int y;

  if (x == 0) {
    x = 42;
  }

  /*@ apply uint_ctz_uf_repr(x); @*/
  y = __builtin_ctz(x);
  y = __builtin_ffs(y);

  if (y < 10) {
    return 1;
  }
  else {
    return 3;
  }
}

