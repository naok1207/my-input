/* test */
#define BLOCK(f, y)  do { f(y); g(y); } while(0)
BLOCK(block_func, x1);
/* If the argument y is a structured expression, the reverse pattern
   does not work. This is because the back reference facility does
   not support pair-ids. */

#define F(a, b) f(a, b)
F(x, ADD(a, b));

#define ADD(a, b) ((a) + (b))
int x = (ADD(ADD(a, b), c));

#define VAR_HOGE(v) hoge_ ## v
int VAR_HOGE(ika);

#define PREFIXED_FUNCTIONS(name, func)		\
  int teba_##name (T a, T b)			\
  { return func (a, b); }

PREFIXED_FUNCTIONS(next, add)

#define print_int_var(v) printf("debug: %s = %d\n", #v, v)
print_int_var(x);
printf("debug: x = %d\n", x); /* difficult */

#define cond(c, f) if (c) { f(); }

cond(a > 0, positive_a);
