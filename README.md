![example workflow](https://github.com/npatsiatzis/spi_master/actions/workflows/coverage.yml/badge.svg)
![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/formal.yml/badge.svg)

### i2c-master RTL implementation

- CoCoTB testbench for functional verification
    - $ make
- formal verification (bmc, not full proof) using SymbiYosys (sby), (properties specified in PSL)
    - $ make formal

