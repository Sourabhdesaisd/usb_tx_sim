# Run with Xcelium

Requires Cadence Xcelium `xrun` with SystemVerilog and UVM 1.2 compatible support and covergroups. From `sim/`:

```sh
make compile
make run TEST=usb_phy_full_path_test USB_SPEED=1
make run TEST=usb_phy_full_path_test USB_SPEED=2
make run TEST=usb_phy_hs_peer_test USB_SPEED=2
make run TEST=usb_phy_fault_test USB_SPEED=0 FAULT=2
make run TEST=usb_phy_reset_test USB_SPEED=1 RESET_CASE=2
make regression
```

`USB_SPEED=0/1/2` selects LS/FS/HS. The HS peer test generates and checks HS line traffic and turnaround; the supplied CDR cannot produce HS RX bytes. `FAULT=1/2/3/4` chooses SE1/missing stuff/long SE0/broken SYNC in the LS/FS RX fault test; the HS peer test generates SE1/stuff/SYNC faults without checking DUT HS RX status. `RESET_CASE=0/1/2` selects initialization/during TX/during RX; RX reset is LS/FS only. `make regression` launches each applicable combination, writing separate `logs/*.log`; the first failure stops the Make target. `make -n regression` prints commands without running. Check UVM_ERROR/UVM_FATAL totals, wire checker packet counters, RX scoreboard checks and actual coverage report before marking results Passed. No simulator was available during creation, so compile and run status is Pending.

The filelist references the included RTL by relative path. Do not mix these files with another version of the same modules; substitute your production RTL in `filelist.f` if needed. Keep WIDTH=8 and 480 MHz defaults unless the TB parameters and timing functions are updated together.


## Per-packet randomized USB TX test

The `usb_phy_tx_random_test` test randomizes the operating speed independently for each packet. It uses a `randc` speed variable so LS, FS, and HS are each selected once before a speed repeats. Payload length, payload bytes, inter-byte gap, and the HS SOF option are randomized for every packet.

The speed is changed only after the preceding packet has completed and the DUT TX, RX activity, and external BFM output-enable are idle. The test updates the environment, PHY-agent, and USB-BFM configuration objects together with the DUT `usb_speed` input. This is a PHY-mode stress test between packets; it is not USB protocol-level speed negotiation.

Run from this `sim` directory:

```bash
make tx_random SEED=12345 TX_RANDOM_PACKETS=4 USB_TX_RX_LOOPBACK=1
```

`USB_TX_RX_LOOPBACK=1` gates the DUT analog RX enable with the BFM's analog-enable request and feeds the resolved shared DP/DM bus back into the DUT RX input. Use `USB_TX_RX_LOOPBACK=0` to disable this internal feedback. The loopback setting is controlled by the `+USB_TX_RX_LOOPBACK` plusarg.

The run log prints each packet's selected speed and ends with LS/FS/HS packet counts plus TX wire-checker counters. For four packets, all three speeds are guaranteed to appear at least once because the speed selector is cyclic-random (`randc`).

**Implementation scope note:** the supplied PHY's CDR/RX implementation does not support HS receive. HS packets are still driven and checked on the TX physical pins; enabling loopback at HS does not establish HS RX verification. LS/FS loopback RX behavior may be observed separately.
