#include <stdint.h>
#include <stdbool.h>
#include "stdlib.h"
#include "stats.h"

void zero_timestamp(timestamp_t* t) {
  t->instret = 0;
  t->cycle = 0;
}

void init_timestamp(timestamp_t* t) {
  t->instret = r_minstret();
  t->cycle = r_mcycle();
}

inline int r_minstret() {
  int x;
  asm volatile("csrr %0, minstret" : "=r" (x));
  return x;
}

inline int r_mcycle() {
  int x;
  asm volatile("csrr %0, mcycle" : "=r" (x));
  return x;
}

static void print_thousandth(int x) {
  int i = x / 1000;
  int f = x % 1000;
  if (f >= 100) printf("%d.%d", i, f);
  else if (f >= 10) printf("%d.0%d", i, f);
  else if (f) printf("%d.00%d", i, f);
  else printf("%d.000", i);
}

static void print_order_magnitude(int x) {
  int kilo = 1000;
  int mega = 1000000;
  int giga = 1000000000;
  if (x >= giga) { print_thousandth(x / mega); printf("G"); }
  else if (x >= mega) { print_thousandth(x / kilo); printf("M"); }
  else if (x >= kilo) { print_thousandth(x); printf("K"); }
  else printf("%d", x);
}

void print_stats(int threadid, const timestamp_t* before, const timestamp_t* after) {
  int ins = after->instret - before->instret;
  int time = after->cycle - before->cycle;

  printf("thread %d finish at ", threadid);
  print_order_magnitude(time);
  printf(" cycles and ");
  print_order_magnitude(ins);
  printf(" instructions\n");
}
