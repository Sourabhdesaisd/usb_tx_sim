# USB PHY TX Directed Testcases

This folder adds directed TX tests to the existing UVM environment. It reuses the existing PHY driver, USB slave model, `usb_tx_wire_checker`, and scoreboard. It does not add a second wire checker.

## Added source files

- `phy_agent/phy_directed_tx_seq.sv`: directed payload sequence. Every transaction field is initialized.
- `test/usb_phy_tx_corner_tests.sv`: reusable directed-test base plus eight focused test classes.
- `test_pkg/usb_phy_tb_pkg.sv`: includes the new sequence and test file.

## Test names

| Test | Intent |
|---|---|
| `usb_phy_tx_data_pattern_test` | 00, FF, AA, 55, 7E, 81, F0, 0F, 96, 69 payload patterns |
| `usb_phy_tx_bitstuff_boundary_test` | Long runs of ones and a six-one run crossing a byte boundary |
| `usb_phy_tx_nrzi_test` | Transition-rich and transition-sparse patterns |
| `usb_phy_tx_sync_eop_test` | SYNC and packet EOP checking; HS includes an HS SOF packet |
| `usb_phy_tx_fifo_boundary_test` | Packet lengths 1, 15, 16, 17, 31 and 64 around the 16-entry FIFO depth |
| `usb_phy_tx_backpressure_test` | 64-byte burst intended to exercise FIFO backpressure |
| `usb_phy_tx_back_to_back_test` | Eight sequential packets with no added software idle interval |
| `usb_phy_tx_interpacket_gap_test` | Short and longer explicit inter-packet idle gaps |
| `usb_phy_tx_sof_test` | HS SOF EOP path; LS/FS run a normal packet because SOF is HS-specific in this project |

## Run commands

Run from the project's `sim` directory. Use the existing `filelist.f`.

```sh
xrun -64bit -uvm -sv -access +rwc -f filelist.f -top top_tb +UVM_TESTNAME=usb_phy_tx_data_pattern_test +USB_SPEED=0 -l tx_pattern_ls.log
xrun -64bit -uvm -sv -access +rwc -f filelist.f -top top_tb +UVM_TESTNAME=usb_phy_tx_data_pattern_test +USB_SPEED=1 -l tx_pattern_fs.log
xrun -64bit -uvm -sv -access +rwc -f filelist.f -top top_tb +UVM_TESTNAME=usb_phy_tx_data_pattern_test +USB_SPEED=2 -l tx_pattern_hs.log
```

Replace the test name and speed for the other combinations. Speed encoding: 0=LS, 1=FS, 2=HS.

## Important verification notes

1. The existing TX wire checker is the physical-layer oracle. It compares the resolved bus symbol stream against the expected SYNC, NRZI data, stuffed bits and EOP symbols, and checks packet duration.
2. These tests intentionally use the project's current wire-model assumptions, including 8 SYNC symbols for LS/FS, 32 for HS, LS/FS EOP of two SE0 symbols followed by J, HS normal EOP of eight SE0 symbols, and HS SOF EOP of forty SE0 symbols. Confirm these against the RTL/spec implementation before sign-off.
3. The backpressure test reports a warning if the monitor observes no SIE ready stall. A long packet does not guarantee FIFO-full if the consumer drains at the same rate as the producer; treat the stall counter as the evidence that backpressure was actually exercised.
4. The driver waits for physical TX completion on the EOP transaction, so each packet sequence returns after the bus has been released. The test adds a short monitor drain interval before checking packet counts.
5. The testbench does not claim HS RX support. These are TX-only tests and run at all three configured speeds.
6. No Cadence Xcelium compile or simulation was available when this archive was assembled. Compile and run the directed tests in your project environment before using the results for sign-off.

### Per-packet randomized TX speed and HS source rate

The `usb_phy_tx_random_test` selects LS, FS, and HS independently at packet boundaries. Payload bytes and inter-byte gaps are randomized with speed-aware constraints: LS/FS gaps are 0-20 system clocks; HS gaps are limited to 0-4 system clocks. The HS restriction prevents the SIE driver from feeding the 16-entry TX FIFO more slowly than the HS PISO consumes bytes, which would cause a packet underrun. Use `USB_TX_RX_LOOPBACK=1` to enable the configured internal TX-to-RX path.
