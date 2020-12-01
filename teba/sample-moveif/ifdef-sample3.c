int g(void) {
  int x;
  x = base 
#ifdef TEST1 /*TEBA:markx*/
    + 1
#elif defined TEST2
    + 2
#elif defined TEST3
    + 3
#endif
#ifdef TEST1 /*TEBA:markx*/
    + 1
#elif defined TEST2
    + 2
#elif defined TEST3
    + 3
#endif
    ;
}

#ifdef TEST4 /*TEBA:mark*/
    + 1
#elif defined TEST5
    + 2
#elif defined TEST6
    + 3
#endif
    ;

#if !defined(INLINE) && !!defined(TEST) /*TEBA:markx*/
inline
#endif
int f(int x, int y) {
 return 
#ifdef NO_MULT /*TEBA:markx*/
   (x + y)
#else
   (x * y)
#endif
     +
#ifndef NO_MULT /*TEBA:markx*/
   (x * y)
#else
   (x + y)
#endif
     ;
}

#if !defined(INLINE) && !!defined(TEST) /*TEBA:markx*/
inline
#endif
int f(int x, int y) {
#ifdef MULT /*TEBA:markx*/
  return (x * y);
#elif ADD
  return (x + y);
#else SUB
  return (x - y);
#endif

}

