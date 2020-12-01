/* An example to replace a partial sub-tree. */
/* Because the tree structure of y->_value is different from the one
   in obj->y->_value, the expression in the macro 'value' is not 
   to be replaced. */

struct Y {
  int _value;
};

struct X {
  struct Y *y;
};

#define value y->_value

int  get_value(struct X *obj) {
  return obj->y->_value;
}
