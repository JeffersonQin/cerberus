struct int_list_items {
  int iv;
  struct int_list_items* next;
};

predicate {integer len} IntList(pointer l) {
  if ( l == NULL ) {
    return { len: 0 } ;
  } else {
    take Head_item = Owned<struct int_list_items>(l) ;
    take Tail = IntList(Head_item.next) ;
    return { len: Tail.len + 1 } ;
  }
}
