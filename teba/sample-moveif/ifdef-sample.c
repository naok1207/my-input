#include <stdio.h>

int main() {
  int i;
  for (i = 0; i < 100; i++) {
    printf(
#ifdef TEST /*TEBA:mark*/
	   "%d\n"
#else
	   "Num %d\n"
#endif
           , i);    }

print(
#ifdef DEBUG0 /* TEBA:mark */
"sample\n"
#endif
);

#ifdef DEBUG1 /* TEBA:mark */
  if (i != 100) {
#endif
    print("error\n");
    exit(1);
#ifdef DEBUG1 /* TEBA:mark */
  }
#endif


  (void*)
# ifdef TEST /* TEBA:mark */
  printf("this is test\n")
#else
  return 0
# endif
    ;
}

int f1() {
  int c
#ifdef F1 /* TEBA:markx */
    ,f1T
#ifdef F2 /* TEBA:mark */
    ,f1T_f2T
#else
    ,f1T_f2F
#endif
#else
#ifdef F2 /* TEBA:mark */
    ,f1F_f2T
#else
    ,f1F_f2F
#endif
#endif
    ;
}

int v0
#ifdef V1 /*TEBA:mark*/
,v1
#endif //V1
#ifdef V2 /*TEBA:mark*/
  ,v2
#endif //V2
#ifdef V3 /*TEBA:mark*/
  ,v3
#endif //V3
  ;


#ifdef HEAD /*TEBA:markx*/
if (cond) 
#endif
#ifdef BODY /*TEBA:mark*/
{
    print("ok");
}
#endif

