import time
import sys

file = open("day9.txt", 'r')

time.sleep(3)

while True:
    line = file.readline()
    line = list(line)
    for x in line:
        print(x, end="")
    sys.stdout.flush()

print()
time.sleep(0.1)
print()
time.sleep(0.1)
print()
time.sleep(0.1)
