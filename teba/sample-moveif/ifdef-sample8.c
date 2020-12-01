#ifdef X
if (c) {
#else
  {
#endif
  f();
#ifdef Y
 }
{
#endif
  g();
}
