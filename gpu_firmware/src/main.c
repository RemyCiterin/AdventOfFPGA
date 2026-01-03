#include <stdint.h>
#include <stdbool.h>
#include <alloca.h>
#include "stdlib.h"
#include "stats.h"

// CPU version: 298.791M cycles
// GPU version: 273.558M cycles

#define NCPU (4 * 16)

int volatile kernel_lock[NCPU];

timestamp_t volatile start_timestamp;
timestamp_t volatile finish_timestamp;
uint32_t volatile bitmask[NCPU];

uint32_t volatile *valid_buffer;

uint32_t volatile *xmin_buffer;
uint32_t volatile *ymin_buffer;
uint32_t volatile *xmax_buffer;
uint32_t volatile *ymax_buffer;

uint32_t volatile *hit_buffer;
uint32_t volatile *inter_num_buffer;

uint32_t volatile *hedges_y_buffer;
uint32_t volatile *vedges_x_buffer;
uint32_t volatile *hedges_xmin_buffer;
uint32_t volatile *vedges_ymin_buffer;
uint32_t volatile *hedges_xmax_buffer;
uint32_t volatile *vedges_ymax_buffer;

uint32_t volatile *x_buffer;
uint32_t volatile *y_buffer;

uint32_t num_vedges;
uint32_t num_hedges;

unsigned readint(char* buf, unsigned size, uint32_t *ret) {
  unsigned i;
  *ret = 0;

  for (i=0; i < size && '0' <= buf[i] && buf[i] <= '9'; i++) {
    *ret = *ret * 10 + buf[i] - '0';
  }

  return i;
}

uint64_t best_area;

uint64_t area_buffer[NCPU];
int gpu_core_index;

////////////////////////////////////////////////////////////////////////////
// Run a set of intersection computations on the GPU
////////////////////////////////////////////////////////////////////////////
void run_gpu_kernel() {
  ////////////////////////////////////////////////////////////////////////////
  // Synchronize GPU threads
  ////////////////////////////////////////////////////////////////////////////
  set_print_device(DEVICE_GPU);
  for (int i=0; i < NCPU; i++) valid_buffer[i] = i < gpu_core_index;
  for (int i=0; i < NCPU; i++) bitmask[i] = 0;
  for (int i=0; i < NCPU; i++) kernel_lock[i]++;

  ////////////////////////////////////////////////////////////////////////////
  // Wait for the kernel computation to finish
  ////////////////////////////////////////////////////////////////////////////
  for (int i=0; i < NCPU; i++) while (!bitmask[i]) {}
  set_print_device(DEVICE_CPU);

  for (int i=0; i < gpu_core_index; i++) {
    if (hit_buffer[i] == 0 && area_buffer[i] > best_area)
      best_area = area_buffer[i];
  }

  gpu_core_index = 0;
}

////////////////////////////////////////////////////////////////////////////
// Add a new intersection computation on the GPU, flush the buffers if
// necessary (by running all their computations)
////////////////////////////////////////////////////////////////////////////
void enq_computation(uint64_t area, uint32_t xmin, uint32_t xmax, uint32_t ymin, uint32_t ymax) {
  if (gpu_core_index >= NCPU) run_gpu_kernel();

  area_buffer[gpu_core_index] = area;
  xmin_buffer[gpu_core_index] = xmin;
  xmax_buffer[gpu_core_index] = xmax;
  ymin_buffer[gpu_core_index] = ymin;
  ymax_buffer[gpu_core_index] = ymax;
  gpu_core_index++;
}

extern void cpu_main() {
  printf("Start main CPU!\n");

  ////////////////////////////////////////////////////////////////////////////
  // Initialize the buffers we use to communicate with the fpga
  ////////////////////////////////////////////////////////////////////////////
  valid_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);

  xmin_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);
  ymin_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);
  xmax_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);
  ymax_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);

  hit_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);
  inter_num_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * NCPU);

  y_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  x_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  hedges_y_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  vedges_x_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  hedges_xmin_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  vedges_ymin_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  hedges_xmax_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);
  vedges_ymax_buffer = (uint32_t volatile*)malloc(sizeof(uint32_t) * 1024);

  ////////////////////////////////////////////////////////////////////////////
  // Read all the points from the serial port
  ////////////////////////////////////////////////////////////////////////////
  int num_points = 0;

  while (true) {
    char line[256];

    int size = readline(line, 256);

    uint32_t value;
    int i = readint(&line[0], size, &value);
    x_buffer[num_points] = value;
    if (line[i] != ',') break;

    readint(&line[i+1], size-i-1, &value);
    y_buffer[num_points] = value;

    num_points++;
    printf("\r%d", num_points);
  }

  printf("\n");

  printf("%d points\n", num_points);

  ////////////////////////////////////////////////////////////////////////////
  // Initialize horizontal and vertical edges
  ////////////////////////////////////////////////////////////////////////////
  for (int i=1; i < num_points; i++) {
    if (x_buffer[i] == x_buffer[i-1]) {
      uint32_t y0 = y_buffer[i-1];
      uint32_t y1 = y_buffer[i];
      uint32_t x = x_buffer[i];

      vedges_ymax_buffer[num_vedges] = y1 > y0 ? y1 : y0;
      vedges_ymin_buffer[num_vedges] = y1 > y0 ? y0 : y1;
      vedges_x_buffer[num_vedges] = x;
      num_vedges++;
    } else {
      uint32_t x0 = x_buffer[i-1];
      uint32_t x1 = x_buffer[i];
      uint32_t y = y_buffer[i];

      hedges_xmax_buffer[num_hedges] = x1 > x0 ? x1 : x0;
      hedges_xmin_buffer[num_hedges] = x1 > x0 ? x0 : x1;
      hedges_y_buffer[num_hedges] = y;
      num_hedges++;
    }
  }

  if (x_buffer[num_points-1] == x_buffer[0]) {
    uint32_t y0 = y_buffer[num_points-1];
    uint32_t y1 = y_buffer[0];
    uint32_t x = x_buffer[0];

    vedges_ymax_buffer[num_vedges] = y1 > y0 ? y1 : y0;
    vedges_ymin_buffer[num_vedges] = y1 > y0 ? y0 : y1;
    vedges_x_buffer[num_vedges] = x;
    num_vedges++;
  } else {
    uint32_t x0 = x_buffer[num_points-1];
    uint32_t x1 = x_buffer[0];
    uint32_t y = y_buffer[0];

    hedges_xmax_buffer[num_hedges] = x1 > x0 ? x1 : x0;
    hedges_xmin_buffer[num_hedges] = x1 > x0 ? x0 : x1;
    hedges_y_buffer[num_hedges] = y;
    num_hedges++;
  }

  ////////////////////////////////////////////////////////////////////////////
  // Initialize the best area to zero
  ////////////////////////////////////////////////////////////////////////////
  best_area = 0;

  ////////////////////////////////////////////////////////////////////////////
  // Empty the computation buffers
  ////////////////////////////////////////////////////////////////////////////
  gpu_core_index = 0;

  init_timestamp((timestamp_t*)&start_timestamp);
  for (int i=0; i < num_points; i++) {
    printf("\rpoint %d", i);
    for (int j=i+1; j < num_points; j++) {
      uint32_t xmin = (x_buffer[i] > x_buffer[j] ? x_buffer[j] : x_buffer[i]) + 1;
      uint32_t xmax = (x_buffer[i] > x_buffer[j] ? x_buffer[i] : x_buffer[j]) - 1;
      uint32_t ymin = (y_buffer[i] > y_buffer[j] ? y_buffer[j] : y_buffer[i]) + 1;
      uint32_t ymax = (y_buffer[i] > y_buffer[j] ? y_buffer[i] : y_buffer[j]) - 1;

      uint64_t area = (uint64_t)(xmax-xmin+3) * (uint64_t)(ymax-ymin+3);

      if (area <= best_area) continue;

      enq_computation(area, xmin, xmax, ymin, ymax);

      //bool found = false;

      //for (int k=0; k < num_vedges && !found; k++) {
      //  uint32_t ex = vedges_x_buffer[k];
      //  uint32_t eymin = vedges_ymin_buffer[k];
      //  uint32_t eymax = vedges_ymax_buffer[k];

      //  bool inter =
      //    xmin <= ex && ex <= xmax && (
      //      (eymin <= ymin && ymin <= eymax) ||
      //      (eymin <= ymax && ymax <= eymax)
      //    );

      //  found = found || inter;
      //}

      //for (int k=0; k < num_hedges && !found; k++) {
      //  uint32_t ey = hedges_y_buffer[k];
      //  uint32_t exmin = hedges_xmin_buffer[k];
      //  uint32_t exmax = hedges_xmax_buffer[k];

      //  bool inter =
      //    ymin <= ey && ey <= ymax && (
      //      (exmin <= xmin && xmin <= exmax) ||
      //      (exmin <= xmax && xmax <= exmax)
      //    );

      //  found = found || inter;
      //}

      //if (!found) best_area = area;
    }
  }

  run_gpu_kernel();

  init_timestamp((timestamp_t*)&finish_timestamp);
  print_stats(1, (timestamp_t*)&start_timestamp, (timestamp_t*)&finish_timestamp);

  printf("best area: %d%d\n", (int32_t)(best_area >> 32), (int32_t)(best_area & 0xffffffff));

  printf("End of demo!\n");
  while (true) {}
}

extern void kernel(int, int, int);

extern void gpu_main(int threadid) {
  int expected = 1;

  while (true) {
    while (kernel_lock[threadid] != expected) {}
    kernel(threadid, num_vedges, num_hedges);
    bitmask[threadid] = 1;
    expected++;
  }
}
