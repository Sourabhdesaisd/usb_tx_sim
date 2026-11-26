// Directed TX sequence. Every field is initialized explicitly.
class phy_directed_tx_seq extends uvm_sequence #(phy_transaction);
  `uvm_object_utils(phy_directed_tx_seq)

  byte unsigned payload[$];
  speed_t packet_speed;
  bit sof_packet;
  int unsigned inter_byte_gap;
  int unsigned next_id;

  function new(string name="phy_directed_tx_seq");
    super.new(name);
    packet_speed = FS;
    sof_packet = 0;
    inter_byte_gap = 0;
    next_id = 0;
  endfunction

  virtual task body();
    phy_transaction req;
    if (payload.size() == 0)
      `uvm_fatal("TX_DIRECTED", "Cannot transmit an empty packet")
    if (!(packet_speed inside {LS,FS,HS}))
      `uvm_fatal("TX_DIRECTED", $sformatf("Unsupported speed %0d",packet_speed))
    if (sof_packet && packet_speed != HS)
      `uvm_fatal("TX_DIRECTED", "SOF flag is only enabled for HS in this project")

    foreach (payload[i]) begin
      req = phy_transaction::type_id::create($sformatf("tx_req_%0d",i));
      start_item(req);
      req.speed            = packet_speed;
      req.data             = payload[i];
      req.valid            = 1'b1;
      req.ready            = 1'b0;
      req.sop              = (i == 0);
      req.eop              = (i == payload.size()-1);
      req.sof_packet       = sof_packet && (i == 0);
      req.delay_cycles     = (i == 0) ? 0 : inter_byte_gap;
      req.valid_gap_cycles = 0;
      req.transaction_id   = next_id++;
      req.rx_error         = 1'b0;
      req.rx_stuff_err     = 1'b0;
      req.rx_align_err     = 1'b0;
      req.rx_line_err      = 1'b0;
      req.rx_sync_err      = 1'b0;
      req.rx_bus_reset     = 1'b0;
      finish_item(req);
    end
  endtask
endclass
