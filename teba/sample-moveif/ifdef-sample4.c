int g() {
#ifdef A /* TEBA:mark */
   a
#endif
#ifndef X
     ;
#else
   +b;
#endif
  
}

int f(int x, int y) {
#ifdef COND /* TEBA:mark */
  if (x > y)
#endif
#ifdef MULT /* TEBA:mark */
  return (x * y)
#elif ADD
  return (x + y)
#elif SUB
  return (x - y)
#else
    return 0
#endif
    ; /* end */
}
