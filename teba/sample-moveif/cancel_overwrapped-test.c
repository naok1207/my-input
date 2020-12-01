/* a test case for cancel_overwrapped_ifdef()
   No.1 and No.2 does not have overrwapped regions before/after the directives,
   but each of them include the other directions in their regions.
 */
#ifdef X // No.1
#ifdef Y
{
#endif
#endif

#ifdef X // No.2
#ifdef Y
}
#endif
#endif
