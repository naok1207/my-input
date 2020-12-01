if (test1) {
  test1_ok();
 } else {
  test1_fail();
  exit(1);
 }

if (test2) {
  test2_ok();
 } else {
  test2_fail();
  return 2;
 }

return 0;

