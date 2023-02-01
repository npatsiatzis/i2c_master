![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/regression_pyuvm.yml/badge.svg)
![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/coverage_pyuvm.yml/badge.svg)

### i2c-master RTL implementation
### testbench based on pyuvm with the help of cocotb


- run pyuvm testbench
    - $ make
- run unit testing of the pyuvm testbench
    - $  SIM=ghdl pytest -n auto -o log_cli=True --junitxml=test-results.xml --cocotbxml=test-cocotb.xml

