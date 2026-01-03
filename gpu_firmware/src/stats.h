
typedef struct __attribute__((packed)) {
  int instret;
  int cycle;
} timestamp_t;

// zero all the fields of a timestamp, like if it was generated at the initialization of the core
void zero_timestamp(timestamp_t*);

// Set the current values inside the timestamp
void init_timestamp(timestamp_t*);

int r_mcycle();
int r_minstret();

void print_stats(int, const timestamp_t* before, const timestamp_t* after);
