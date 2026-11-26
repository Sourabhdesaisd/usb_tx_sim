# USB PHY TX wire checker update

## Files changed
- `phy_bfm_agent/usb_slave_model.sv`

## What changed
- The existing `usb_tx_wire_checker` now obtains both `usb_phy_if` and `usb_bus_if`.
- It samples the resolved shared USB bus (`bus_dp`, `bus_dm`) while the DUT TX is active.
- It compares resolved bus symbols against DUT TX pins and reports bus contention during transmission.
- It checks expected packet symbol count, bit-period duration, SYNC/data/EOP symbol stream, NRZI-decoded bytes, and stuffed-zero presence.
- It reports packet, symbol, stuffing, SYNC, EOP, timing, contention, and ready-stall statistics at end of simulation.
- The checker remains integrated inside the existing `usb_slave_model`; no duplicate checker or new package include is required.

## Integration
`usb_slave_model.build_phase()` now passes `cfg.bus_vif` to `tx_wire_checker` using UVM config_db. `usb_bfm_agent_config` already contains `bus_vif`, so no new top-level connection is required.

## Important limitations
- This environment does not have Cadence Xcelium or another SystemVerilog simulator installed, so this archive has not been compiled or simulated here.
- The expected SYNC/EOP conventions follow the current project's model: LS/FS SYNC = 8 bit cells, HS SYNC = 32 bit cells, LS/FS EOP = SE0, SE0, J, HS EOP = configured SE0 interval (8 normal / 40 SOF bit cells).
- Validate those HS conventions against the actual RTL and the USB 2.0 PHY specification before sign-off.
- The checker samples one symbol at the start of each configured bit period using the existing `tx_valid`-window sampling convention. If the RTL's `tx_valid` assertion is not aligned to the first SYNC bit boundary, align sampling to the actual TX bit-tick signal in a follow-up integration change.
