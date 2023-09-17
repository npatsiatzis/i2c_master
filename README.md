![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/regression_controller.yml/badge.svg)
![example workflow](https://github.com/npatsiatzis/i2c_master/actions/workflows/coverage_controller.yml/badge.svg)

### simple limited features i2c master controller RTL implementation

- design based on lattice reference design for i2c master, adapted based on different requirements.
- rtl design verified by a a testbench implementing a trivial i2c slave. testbench (CoCoTB) comprises a single test case in which a write operation with random data is issued followed by a read operation. it is checked that a master can thus both transmit and receive data correctly.
    - $ make


### Repo Structure

This is a short tabular description of the contents of each folder in the repo.

| Folder | Description |
| ------ | ------ |
| [rtl](https://github.com/npatsiatzis/i2c_master/tree/main/rtl/VHDL) | VHDL RTL implementation files |
| [cocotb_sim](https://github.com/npatsiatzis/i2c_master/tree/main/cocotb_sim) | Functional Verification with CoCoTB (Python-based) |
| [pyuvm_sim](https://github.com/npatsiatzis/i2c_master/tree/main/pyuvm_sim) | Functional Verification with pyUVM (Python impl. of UVM standard) |


This is the tree view of the strcture of the repo.
<pre>
<font size = "2">
.
├── <font size = "4"><b><a href="https://github.com/npatsiatzis/i2c_master/tree/main/rtl">rtl</a></b> </font>
│   └── VHD files
├── <font size = "4"><b><a href="https://github.com/npatsiatzis/i2c_master/tree/main/cocotb_sim">cocotb_sim</a></b></font>
│   ├── Makefile
│   └── python files
└── <font size = "4"><b><a 
 href="https://github.com/npatsiatzis/i2c_master/tree/main/pyuvm_sim">pyuvm_sim</a></b></font>
    ├── Makefile
    └── python files
</pre>