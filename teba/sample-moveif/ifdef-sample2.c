//F1 F2 E2
int c, f1, f21;
//F1 F2 !E2
int c, f1, f21;
//F1 !F2 E2
int c, f1, f22;
//F1 !F2 !E2
int c, f1, f22;
//!F1 F2 E2
int c, e21;
//!F1 F2 !E2
int c, e22;
//!F1 !F2 E2
int c, e21;
//!F1 !F2 !E2
int c, e22;

int f1() {
  int c
#ifdef F1 /* TEBA:markx */
    ,f1
#ifdef F2 /* TEBA:mark */
    ,f21
#else //F2
    ,f22
#endif //F2
#else //F1
#ifdef E2 /* TEBA:mark */
    ,e21
#else //E2
    ,e22
#endif //E2
#endif //F1
    ;
}

#ifdef 0
int f1() {
  int c
#ifdef F1 /* TEBA:markx */
    ,f1
#ifdef F2 /* TEBA:mark */
    ,f21
#else //F2
    ,f22
#endif //F2
#else  //F1
#ifdef E2 /* TEBA:markx */
    ,e21
#else //E2
    ,e22
#endif //E2
#endif //F1
    ;
}
#endif
