![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/regression_controller.yml/badge.svg)
![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/coverage_controller.yml/badge.svg)

### simple limited features i2c master controller RTL implementation

- design based on lattice reference design for i2c master, adapted based on different requirements.
- rtl design verified by a a testbench implementing a trivial i2c slave. testbench (CoCoTB) comprises a single test case in which a write operation with random data is issued followed by a read operation. it is checked that a master can thus both transmit and receive data correctly.
    - $ make